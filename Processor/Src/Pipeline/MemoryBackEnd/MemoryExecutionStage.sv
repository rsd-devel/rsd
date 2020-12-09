// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Execution stage
//

`include "BasicMacros.sv"

import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import DebugTypes::*;
import MemoryMapTypes::*;


//
// 実行ステージ
//

module MemoryExecutionStage(
    MemoryExecutionStageIF.ThisStage port,
    MemoryRegisterReadStageIF.NextStage prev,
    LoadStoreUnitIF.MemoryExecutionStage loadStoreUnit,
    CacheFlushManagerIF.MemoryExecutionStage cacheFlush,
    MulDivUnitIF.MemoryExecutionStage mulDivUnit,
    BypassNetworkIF.MemoryExecutionStage bypass,
    RecoveryManagerIF.MemoryExecutionStage recovery,
    ControllerIF.MemoryExecutionStage ctrl,
    CSR_UnitIF.MemoryExecutionStage csrUnit,
    DebugIF.MemoryExecutionStage debug
);

    MemoryExecutionStageRegPath pipeReg[MEM_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif

    // --- Pipeline registers
    always_ff@( posedge port.clk )   // synchronous rst
    begin
        if (port.rst) begin
            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                pipeReg[i].valid <= '0;
            end
        end
        else if(!ctrl.backEnd.stall) begin              // write data
            pipeReg <= prev.nextStage;
        end
    end


    // Pipeline controll
    logic stall, clear;
    logic flush[ MEM_ISSUE_WIDTH ];

    MemIssueQueueEntry iqData[MEM_ISSUE_WIDTH];
    MemOpInfo memOpInfo  [ MEM_ISSUE_WIDTH ];

    PRegDataPath  fuOpA  [ MEM_ISSUE_WIDTH ];
    PRegDataPath  fuOpB  [ MEM_ISSUE_WIDTH ];

    // Valid bits of registers
    logic regValid[MEM_ISSUE_WIDTH];

`ifdef RSD_ENABLE_VECTOR_PATH
    PVecDataPath  fuVecOpB [ MEM_ISSUE_WIDTH ];
    logic vecRegValid[MEM_ISSUE_WIDTH];
`endif

    AddrPath addrOut[ MEM_ISSUE_WIDTH ];
    MemoryMapType memMapType[MEM_ISSUE_WIDTH];
    PhyAddrPath phyAddrOut[MEM_ISSUE_WIDTH];
    logic isUncachable[MEM_ISSUE_WIDTH];

    // MSHRをAllocateした命令からのメモリリクエストかどうか
    // そのリクエストがアクセスに成功した場合，AllocateされたMSHRは解放可能になる
    logic makeMSHRCanBeInvalid[LOAD_ISSUE_WIDTH];

    // FENCE.I
    logic cacheFlushReq;

    always_comb begin
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            makeMSHRCanBeInvalid[i] = 
                pipeReg[i].memQueueData.memOpInfo.hasAllocatedMSHR;
        end

        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            iqData[i] = pipeReg[i].memQueueData;
            flush[i] = SelectiveFlushDetector(
                        recovery.toRecoveryPhase,
                        recovery.flushRangeHeadPtr,
                        recovery.flushRangeTailPtr,
                        iqData[i].activeListPtr
                        );
            memOpInfo[i]  = iqData[i].memOpInfo;

      
            // オペランド
            fuOpA[i] = ( pipeReg[i].bCtrl.rA.valid ? bypass.memSrcRegDataOutA[i] : pipeReg[i].operandA );
            fuOpB[i] = ( pipeReg[i].bCtrl.rB.valid ? bypass.memSrcRegDataOutB[i] : pipeReg[i].operandB );

            // Address unit
            addrOut[i] = fuOpA[i].data + { {ADDR_SIGN_EXTENTION_WIDTH{memOpInfo[i].addrIn[ADDR_OPERAND_IMM_WIDTH-1]}}, memOpInfo[i].addrIn };
            phyAddrOut[i] = ToPhyAddrFromLogical(addrOut[i]);
            memMapType[i] = GetMemoryMapType(addrOut[i]);
            isUncachable[i] = IsPhyAddrUncachable(phyAddrOut[i]);

            // --- Bypass
            // 制御
            bypass.memCtrlIn[i] = pipeReg[i].bCtrl;

            // Register valid bits.
            // If invalid regisers are read, regValid is negated and this op must be replayed.
            `ifdef RSD_ENABLE_VECTOR_PATH
                if ( memOpInfo[i].memAccessMode.size == MEM_ACCESS_SIZE_VEC ) begin
                    regValid[i] = vecRegValid[i];
                end
                else begin
                    regValid[i] =
                        (memOpInfo[i].operandTypeA != OOT_REG || fuOpA[i].valid ) &&
                        (memOpInfo[i].operandTypeB != OOT_REG || fuOpB[i].valid );
                end
            `else
                regValid[i] =
                    (memOpInfo[i].operandTypeA != OOT_REG || fuOpA[i].valid ) &&
                    (memOpInfo[i].operandTypeB != OOT_REG || fuOpB[i].valid );
            `endif

        end // for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin

        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            // --- DCache access
            // TODO: メモリマップが MMT_MEMORY じゃなかったとしても，一度 MSHR を確保して
            // しまった場合にはデータを受け取らないと行けないので，とりあえずどんな
            // 領域にアクセスをするとしても DC からデータを拾うようにしておく
            loadStoreUnit.dcReadReq[i] =
                !stall && !clear && pipeReg[i].valid && regValid[i] && !flush[i] &&
                (memOpInfo[i].opType inside { MEM_MOP_TYPE_LOAD });

            //loadStoreUnit.dcReadAddr[i] = addrOut[i];
            loadStoreUnit.dcReadAddr[i] = phyAddrOut[i];

            loadStoreUnit.dcReadUncachable[i] = isUncachable[i];

            // To notify MSHR that the requester is its allocator load.
            loadStoreUnit.makeMSHRCanBeInvalid[i] = makeMSHRCanBeInvalid[i];
        end

        // FENCE.I (with ICache and DCache flush)
        // FENCE.I must be issued to the lane 0;
        cacheFlushReq = FALSE;
        if (pipeReg[0].valid && (memOpInfo[0].opType == MEM_MOP_TYPE_FENCE) && memOpInfo[0].isFenceI) begin
            cacheFlushReq = TRUE;
            if (!cacheFlush.cacheFlushComplete) begin
                // FENCEI must be replayed after cache flush is completed.
                regValid[0] = FALSE;
            end
        end
        cacheFlush.cacheFlushReq = cacheFlushReq;
    end

    //
    // --- Vector Operand
    //
`ifdef RSD_ENABLE_VECTOR_PATH
    always_comb begin
        for ( int i = 0; i < STORE_ISSUE_LANE_BEGIN; i++ ) begin
            fuVecOpB[i] = '0;
            vecRegValid[i] =
                (memOpInfo[i].operandTypeA != OOT_REG || fuOpA[i].valid );
        end
        for ( int i = 0; i < STORE_ISSUE_WIDTH; i++ ) begin
            fuVecOpB[i+STORE_ISSUE_LANE_BEGIN] = ( pipeReg[i+STORE_ISSUE_LANE_BEGIN].bCtrl.rB.valid ? bypass.memSrcVecDataOutB[i] : pipeReg[i+STORE_ISSUE_LANE_BEGIN].vecOperandB );
            vecRegValid[i+STORE_ISSUE_LANE_BEGIN] =
                (memOpInfo[i+STORE_ISSUE_LANE_BEGIN].operandTypeA != OOT_REG || fuOpA[i+STORE_ISSUE_LANE_BEGIN].valid ) &&
                fuVecOpB[i+STORE_ISSUE_LANE_BEGIN].valid;
        end
    end
`endif

    //
    // CSR access
    //
    generate
        // Since a CSR op is serialized, so multiple CSR ops are not issued.
        for (genvar i = 1; i < MEM_ISSUE_WIDTH; i++) begin : assertionBlock
            `RSD_ASSERT_CLK(
                port.clk, 
                !(memOpInfo[i].opType inside {
                    MEM_MOP_TYPE_CSR, MEM_MOP_TYPE_FENCE, MEM_MOP_TYPE_ENV
                } && pipeReg[i].valid),
                "A CSR/FENCE/ENV op was issued to a lane other than 0."
            );
        end
    endgenerate

    logic isCSR;
    always_comb begin   // CSR must be issued to the lane 0;
        isCSR = memOpInfo[0].opType == MEM_MOP_TYPE_CSR;

        // CSR request
        csrUnit.csrWE = pipeReg[0].valid && isCSR;
        csrUnit.csrNumber = memOpInfo[0].addrIn;
        csrUnit.csrWriteIn = 
            memOpInfo[0].csrCtrl.isImm ? memOpInfo[0].csrCtrl.imm : pipeReg[0].operandA;
        csrUnit.csrCode = memOpInfo[0].csrCtrl.code;
    end

    //
    // MulDiv
    //
`ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    logic isDiv         [ MULDIV_ISSUE_WIDTH ]; 
    logic finished      [ MULDIV_ISSUE_WIDTH ];

    // For selective flush
    ActiveListIndexPath regActiveListIndex  [ MULDIV_ISSUE_WIDTH ];
    ActiveListIndexPath nextActiveListIndex [ MULDIV_ISSUE_WIDTH ];
    logic divReset[ MULDIV_ISSUE_WIDTH ];

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin
                regActiveListIndex[i] <= '0;
            end
        end
        else begin
            regActiveListIndex <= nextActiveListIndex;
        end
    end

    MulOpSubInfo mulSubInfo[MULDIV_ISSUE_WIDTH];
    DivOpSubInfo divSubInfo[MULDIV_ISSUE_WIDTH];
    always_comb begin

        for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin
            mulDivUnit.dataInA[i] = fuOpA[i].data;
            mulDivUnit.dataInB[i] = fuOpB[i].data;

            // MUL
            mulSubInfo[i]  = memOpInfo[i].mulSubInfo;
            divSubInfo[i]  = memOpInfo[i].divSubInfo;
            mulDivUnit.mulGetUpper[i] = mulSubInfo[i].mulGetUpper;
            mulDivUnit.mulCode[i] = mulSubInfo[i].mulCode;

            // DIV
            mulDivUnit.divCode[i] = divSubInfo[i].divCode;

            isDiv[i] =  
                memOpInfo[i].opType inside {MEM_MOP_TYPE_DIV};

            // Dividerで処理中のdivがフラッシュされたら，Dividerの状態をFREEに変更して
            // IQからdivを発行できるようにする
            divReset[i] = FALSE;
            if (recovery.toRecoveryPhase) begin
                divReset[i] = SelectiveFlushDetector( 
                    recovery.toRecoveryPhase, 
                    recovery.flushRangeHeadPtr, 
                    recovery.flushRangeTailPtr, 
                    regActiveListIndex[i]
                );
            end
            if (clear) begin
                divReset[i] = TRUE;
            end
            if (isDiv[i] && flush[i]) begin
                // Div is flushed at register read stage, so release the divider
                divReset[i] = TRUE;
            end
            mulDivUnit.divReset[i] = divReset[i];

            // Request to the divider
            // NOT make a request when below situation
            // 1) When any operands of inst. are invalid
            // 2) When the divider is waiting for the instruction
            //    to receive the result of the divider
            mulDivUnit.divReq[i] = 
                mulDivUnit.divReserved[i] && 
                pipeReg[i].valid && isDiv[i] && 
                fuOpA[i].valid && fuOpB[i].valid;


            if (pipeReg[i].valid && isDiv[i] && mulDivUnit.divReserved[i]) begin
                nextActiveListIndex[i] = 
                    iqData[i].activeListPtr;
            end
            else begin
                nextActiveListIndex[i] = regActiveListIndex[i];
            end

        end

    end


`endif



    //
    // --- Pipeline レジスタ書き込み
    //
    MemoryTagAccessStageRegPath nextStage [ MEM_ISSUE_WIDTH ];

    always_comb begin
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            nextStage[i].memQueueData = pipeReg[i].memQueueData;

            // リセットorフラッシュ時はNOP
            nextStage[i].valid =
                (stall || clear || port.rst || flush[i]) ? FALSE : pipeReg[i].valid;
            nextStage[i].condEnabled = TRUE;
            nextStage[i].dataIn = (i == 0 && isCSR) ? csrUnit.csrReadOut : fuOpB[i].data;   // CSR must be issued to the lane 0
            `ifdef RSD_ENABLE_VECTOR_PATH
                nextStage[i].vecDataIn = fuVecOpB[i].data;
            `endif
            nextStage[i].addrOut = addrOut[i];
            nextStage[i].regValid = regValid[i];
            nextStage[i].memMapType = memMapType[i];
            nextStage[i].phyAddrOut = phyAddrOut[i];
`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].opId = pipeReg[i].opId;
`endif
        end

        for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            if (makeMSHRCanBeInvalid[i]) begin
                nextStage[i].memQueueData.memOpInfo.hasAllocatedMSHR = FALSE;
            end
        end
        for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
            nextStage[i+STORE_ISSUE_LANE_BEGIN].memQueueData.memOpInfo.hasAllocatedMSHR = FALSE;
        end


        // Output
        port.nextStage = nextStage;

        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            debug.memExReg[i].valid = pipeReg[i].valid;
            debug.memExReg[i].flush = flush[i];
            debug.memExReg[i].opId = pipeReg[i].opId;
`ifdef RSD_FUNCTIONAL_SIMULATION
            if (isCSR && i == 0) begin  // Special case for CSR
                debug.memExReg[i].addrOut = csrUnit.csrReadOut;
                debug.memExReg[i].fuOpA   = memOpInfo[0].addrIn;
                debug.memExReg[i].fuOpB   = memOpInfo[0].csrCtrl.isImm ? memOpInfo[0].csrCtrl.imm : pipeReg[0].operandA;
            end
            else begin
                debug.memExReg[i].addrOut = addrOut[i];
                debug.memExReg[i].fuOpA   = fuOpA[i].data;
                debug.memExReg[i].fuOpB   = fuOpB[i].data;
            end
            `ifdef RSD_ENABLE_VECTOR_PATH
                debug.memExReg[i].fuVecOpB = fuVecOpB[i].data;
            `endif
            debug.memExReg[i].opType = memOpInfo[i].opType;
            debug.memExReg[i].size = memOpInfo[i].memAccessMode.size;
            debug.memExReg[i].isSigned = memOpInfo[i].memAccessMode.isSigned;
`endif
        end
`endif
    end

endmodule : MemoryExecutionStage
