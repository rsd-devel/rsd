// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for register read.
//


import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import CacheSystemTypes::*;
import PipelineTypes::*;
import DebugTypes::*;

//
// --- オペランドの選択
//
function automatic DataPath SelectOperand(
input
    OpOperandType opType, DataPath regV, DataPath immV, DataPath pcV
);
    case( opType )
    default:    // OOT_REG
        return regV;
    OOT_IMM:
        return immV;
    OOT_PC:
        return pcV;
    endcase
endfunction

//
// --- Memory Register Read Stage
//
module MemoryRegisterReadStage(
    MemoryRegisterReadStageIF.ThisStage port,
    MemoryIssueStageIF.NextStage prev,
    LoadStoreUnitIF.MemoryRegisterReadStage loadStoreUnit,
    MulDivUnitIF.MemoryRegisterReadStage mulDivUnit,
    RegisterFileIF.MemoryRegisterReadStage registerFile,
    BypassNetworkIF.MemoryRegisterReadStage bypass,
    RecoveryManagerIF.MemoryRegisterReadStage recovery,
    ControllerIF.MemoryRegisterReadStage ctrl,
    DebugIF.MemoryRegisterReadStage debug
);

    // --- Pipeline registers
    MemoryRegisterReadStageRegPath pipeReg [MEM_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif

    always_ff@( posedge port.clk )   // synchronous rst
    begin
        if (port.rst) begin
            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                pipeReg[i].valid <= '0;
            end
        end
        else if (!ctrl.backEnd.stall) begin             // write data
            pipeReg <= prev.nextStage;
        end
    end


    // Operand
    DataPath immOut [ MEM_ISSUE_WIDTH ];
    AddrPath pc [ MEM_ISSUE_WIDTH ];
    PRegDataPath operandA [ MEM_ISSUE_WIDTH ];
    PRegDataPath operandB [ MEM_ISSUE_WIDTH ];

    // Pipeline controll
    logic stall, clear;
    logic flush[ MEM_ISSUE_WIDTH ];
    MemIssueQueueEntry iqData[MEM_ISSUE_WIDTH];
    MemOpInfo memOpInfo[MEM_ISSUE_WIDTH];
    OpSrc opSrc[MEM_ISSUE_WIDTH];
    OpDst opDst[MEM_ISSUE_WIDTH];
    MemoryExecutionStageRegPath nextStage [MEM_ISSUE_WIDTH];
    MSHR_IndexPath mshrID;

    logic makeMSHRCanBeInvalid[LOAD_ISSUE_WIDTH];
    logic isLoad[LOAD_ISSUE_WIDTH];

    always_comb begin
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            iqData[i] = pipeReg[i].memQueueData;
            memOpInfo[i] = iqData[i].memOpInfo;
            opSrc[i] = iqData[i].opSrc;
            opDst[i] = iqData[i].opDst;
            pc[i] = iqData[i].pc;

            //
            // Register file
            //

            registerFile.memSrcRegNumA[i] = opSrc[i].phySrcRegNumA;
            registerFile.memSrcRegNumB[i] = opSrc[i].phySrcRegNumB;


            //
            // To a bypass network.
            // ストールやフラッシュの制御は，Bypass モジュールの内部で
            // コントローラの信号を参照して行われている
            //
            bypass.memPhySrcRegNumA[i] = opSrc[i].phySrcRegNumA;
            bypass.memPhySrcRegNumB[i] = opSrc[i].phySrcRegNumB;

            bypass.memWriteReg[i]  = opDst[i].writeReg & pipeReg[i].valid;
            bypass.memPhyDstRegNum[i] = opDst[i].phyDstRegNum;
            bypass.memReadRegA[i] = ( memOpInfo[i].operandTypeA == OOT_REG );
            bypass.memReadRegB[i] = ( memOpInfo[i].operandTypeB == OOT_REG );

            //
            // --- オペランド選択
            //
            immOut[i] = '0; //RISCVにおいて即値をオペランドにとるようなロード/ストアはない(アドレス計算はExecutionStage)
            operandA[i].data = SelectOperand(
                memOpInfo[i].operandTypeA,
                registerFile.memSrcRegDataA[i].data,
                immOut[i],
                pc[i]
            );
            operandB[i].data = SelectOperand(
                memOpInfo[i].operandTypeB,
                registerFile.memSrcRegDataB[i].data,
                immOut[i],
                pc[i]
            );
            operandA[i].valid = (memOpInfo[i].operandTypeA != OOT_REG || registerFile.memSrcRegDataA[i].valid);
            operandB[i].valid = (memOpInfo[i].operandTypeB != OOT_REG || registerFile.memSrcRegDataB[i].valid);

            //
            // --- Pipeline ラッチ書き込み
            //
            `ifndef RSD_DISABLE_DEBUG_REGISTER
                nextStage[i].opId = pipeReg[i].opId;
            `endif


            // リセットorフラッシュ時はNOP
            flush[i] = SelectiveFlushDetector(
                recovery.toRecoveryPhase,
                recovery.flushRangeHeadPtr,
                recovery.flushRangeTailPtr,
                iqData[i].activeListPtr
            );
            nextStage[i].valid =
                (stall || clear || port.rst || flush[i]) ? FALSE : pipeReg[i].valid;

            nextStage[i].memQueueData = pipeReg[i].memQueueData;

            // レジスタ値&フラグ
            nextStage[i].operandA = operandA[i];
            nextStage[i].operandB = operandB[i];

            // バイパス制御
            nextStage[i].bCtrl = bypass.memCtrlOut[i];

            // Release the entries of the issue queue.
            nextStage[i].replay = pipeReg[i].replay && pipeReg[i].valid;
            nextStage[i].issueQueuePtr = pipeReg[i].issueQueuePtr;
        end

        `ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            // divがこのステージ内でフラッシュされた場合，演算器を解放する
            for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin
                mulDivUnit.divResetFromMR_Stage[i] = 
                    (memOpInfo[i].opType == MEM_MOP_TYPE_DIV) &&
                    pipeReg[i].valid && flush[i];
            end
        `endif

        // Vector Operand
`ifdef RSD_ENABLE_VECTOR_PATH
        `RSD_STATIC_ASSERT(FALSE, "TODO: ls/st unified pipeline");
        for ( int i = 0; i < STORE_ISSUE_LANE_BEGIN; i++ ) begin
            nextStage[i].vecOperandB = '0;
        end
        for ( int i = 0; i < STORE_ISSUE_WIDTH; i++ ) begin
            nextStage[i+STORE_ISSUE_LANE_BEGIN].vecOperandB = registerFile.memSrcVecDataB[i];
        end
`endif
        port.nextStage = nextStage;

        //フラッシュによってMSHRをアロケートしたロード命令がフラッシュされる場合のMSHRの解放処理
        for (int i = 0; i < MSHR_NUM; i++) begin
            loadStoreUnit.makeMSHRCanBeInvalidByMemoryRegisterReadStage[i] = FALSE;
        end


        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            isLoad[i] = pipeReg[i].memQueueData.memOpInfo.opType == MEM_MOP_TYPE_LOAD;
            if (pipeReg[i].valid && isLoad[i] && flush[i]) begin
                makeMSHRCanBeInvalid[i] = pipeReg[i].memQueueData.memOpInfo.hasAllocatedMSHR;
            end
            else begin
                makeMSHRCanBeInvalid[i] = FALSE;
            end

            mshrID = pipeReg[i].memQueueData.memOpInfo.mshrID;
            if (makeMSHRCanBeInvalid[i]) begin
                loadStoreUnit.makeMSHRCanBeInvalidByMemoryRegisterReadStage[mshrID] = TRUE;
            end
        end

        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            debug.memRrReg[i].valid = pipeReg[i].valid;
            debug.memRrReg[i].flush = flush[i];
            debug.memRrReg[i].opId = pipeReg[i].opId;
        end
`endif
    end
endmodule : MemoryRegisterReadStage
