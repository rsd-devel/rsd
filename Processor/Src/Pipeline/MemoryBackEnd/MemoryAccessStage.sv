// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Memory access stage
//

`include "BasicMacros.sv"

import BasicTypes::*;
import OpFormatTypes::*;
import RenameLogicTypes::*;
import PipelineTypes::*;
import DebugTypes::*;
import MicroOpTypes::*;
import MemoryMapTypes::*;

module MemoryAccessStage(
    MemoryAccessStageIF.ThisStage port,
    MemoryTagAccessStageIF.NextStage prev,
    LoadStoreUnitIF.MemoryAccessStage loadStoreUnit,
    MulDivUnitIF.MemoryAccessStage mulDivUnit,
    BypassNetworkIF.MemoryAccessStage bypass,
    IO_UnitIF.MemoryAccessStage ioUnit,
    RecoveryManagerIF.MemoryAccessStage recovery,
    ControllerIF.MemoryAccessStage ctrl,
    DebugIF.MemoryAccessStage debug
);

    MemoryAccessStageRegPath pipeReg[MEM_ISSUE_WIDTH];

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



    logic isStore  [ MEM_ISSUE_WIDTH ];
    logic isLoad  [ MEM_ISSUE_WIDTH ];
    logic isCSR   [ MEM_ISSUE_WIDTH ];
    logic isDiv   [ MEM_ISSUE_WIDTH ];
    logic isMul   [ MEM_ISSUE_WIDTH ];


    logic valid   [ MEM_ISSUE_WIDTH ];
    logic update  [ MEM_ISSUE_WIDTH ];

    logic regValid[ MEM_ISSUE_WIDTH ];

    // Pipeline controll
    logic stall, clear;
    logic flush[ MEM_ISSUE_WIDTH ];
    MemoryRegisterWriteStageRegPath nextStage [ MEM_ISSUE_WIDTH ];

    PRegDataPath  dataOut[MEM_ISSUE_WIDTH];
    PRegDataPath  ldDataOut[LOAD_ISSUE_WIDTH];
    PRegDataPath  stDataOut[STORE_ISSUE_WIDTH];
    PVecDataPath  vecDataOut[MEM_ISSUE_WIDTH];

    always_comb begin
        
        // Pipeline controll
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            valid[i]   = pipeReg[i].valid;
            flush[i] = SelectiveFlushDetector(
                            recovery.toRecoveryPhase,
                            recovery.flushRangeHeadPtr,
                            recovery.flushRangeTailPtr,
                            recovery.flushAllInsns,
                            pipeReg[i].activeListPtr
                        );
            isStore[i] = pipeReg[i].isStore;
            isLoad[i]  = pipeReg[i].isLoad;
            isCSR[i]   = pipeReg[i].isCSR;
            isDiv[i]   = pipeReg[i].isDiv;
            isMul[i]   = pipeReg[i].isMul;
            update[i]  = pipeReg[i].valid && !stall && !clear && !flush[i];
            regValid[i] = pipeReg[i].regValid;
        end

        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            if (i == 0) begin
                ioUnit.ioReadAddrIn = pipeReg[i].phyAddrOut;
            end

            if (isLoad[i]) begin
                if (i == 0 && pipeReg[i].memMapType == MMT_IO) begin
                    ldDataOut[i].data = ioUnit.ioReadDataOut;
                end
                else begin
                    ldDataOut[i].data = loadStoreUnit.executedLoadData[i];
                end
            end
            else if (isCSR[i])
                ldDataOut[i].data = pipeReg[i].csrDataOut;
            else
                ldDataOut[i].data = pipeReg[i].addrOut;

            `ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
                if (isDiv[i])
                    ldDataOut[i].data = mulDivUnit.divDataOut[i];
                else if (isMul[i])
                    ldDataOut[i].data = mulDivUnit.mulDataOut[i];

                if (mulDivUnit.divFinished[i] &&
                    update[i] &&
                    isDiv[i] && 
                    regValid[i]
                ) begin 
                    // Divが除算器から結果を取得できたので，
                    // IQからのdivの発行を許可する 
                    mulDivUnit.divRelease[i] = TRUE;
                end
                else begin
                    mulDivUnit.divRelease[i] = FALSE;
                end

            `endif


            ldDataOut[i].valid = regValid[i];
        end
        
        for ( int i = 0; i < STORE_ISSUE_WIDTH; i++ ) begin
            stDataOut[i].data = '0;
            stDataOut[i].valid = FALSE;
        end


        `ifdef RSD_MARCH_UNIFIED_LDST_MEM_PIPE
            for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
                dataOut[i] = isStore[i] ? stDataOut[i] : ldDataOut[i];
            end
        `else
            for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
                dataOut[i] = ldDataOut[i];
            end
            for ( int i = 0; i < STORE_ISSUE_WIDTH; i++ ) begin
                dataOut[i+STORE_ISSUE_LANE_BEGIN] = stDataOut[i];
            end
        `endif

        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin

`ifdef RSD_ENABLE_VECTOR_PATH
            vecDataOut[i].data = loadStoreUnit.executedLoadVectorData[i];
            vecDataOut[i].valid = regValid[i];
            nextStage[i].vecDataOut = vecDataOut[i];
`endif

            nextStage[i].dataOut = dataOut[i];
            bypass.memDstRegDataOut[i] = dataOut[i];    // Bypass

            // Pipeline レジスタ書き込み
`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].opId = pipeReg[i].opId;
`endif

            nextStage[i].opDst = pipeReg[i].opDst;

            nextStage[i].activeListPtr = pipeReg[i].activeListPtr;
            nextStage[i].loadQueueRecoveryPtr = pipeReg[i].loadQueueRecoveryPtr;
            nextStage[i].storeQueueRecoveryPtr = pipeReg[i].storeQueueRecoveryPtr;
            nextStage[i].execState = pipeReg[i].execState;
            nextStage[i].pc = pipeReg[i].pc;
            nextStage[i].addrOut = pipeReg[i].addrOut;
            nextStage[i].isStore = pipeReg[i].isStore;

            // リセットorフラッシュ時はNOP
            nextStage[i].valid =
                (stall || clear || port.rst || flush[i]) ? FALSE : pipeReg[i].valid;
        end


        // Vector Bypass
        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
`ifdef RSD_ENABLE_VECTOR_PATH
            bypass.memDstVecDataOut[i] = vecDataOut[i];
`endif
        end


        port.nextStage = nextStage;

        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            debug.maReg[i].valid = pipeReg[i].valid;
            debug.maReg[i].flush = flush[i];
            debug.maReg[i].opId = pipeReg[i].opId;
        end
`ifdef RSD_FUNCTIONAL_SIMULATION
        for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            debug.maReg[i].executeLoad       = update[i] && isLoad[i];
            debug.maReg[i].executedLoadData  = dataOut[i].data;
            debug.maReg[i].executedLoadVectorData = loadStoreUnit.executedLoadVectorData[i];
        end
`endif
`endif
    end

    generate 
        for (genvar i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            `RSD_ASSERT_CLK(
                port.clk, 
                !(isLoad[i] && valid[i] && !flush[i] && i != 0 && pipeReg[i].memMapType == MMT_IO),
                "IO access cane be accessed in the mem lane 0."
            );
        end
    endgenerate


endmodule : MemoryAccessStage
