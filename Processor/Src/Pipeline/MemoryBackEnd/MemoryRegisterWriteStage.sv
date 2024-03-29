// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Memory Write back stage
//

import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import PipelineTypes::*;
import DebugTypes::*;
import CacheSystemTypes::*;



module MemoryRegisterWriteStage(
    //MemoryRegisterWriteStageIF.ThisStage port,
    MemoryAccessStageIF.NextStage prev,
    LoadStoreUnitIF.MemoryRegisterWriteStage loadStoreUnit,
    RegisterFileIF.MemoryRegisterWriteStage registerFile,
    ActiveListIF.MemoryRegisterWriteStage activeList,
    RecoveryManagerIF.MemoryRegisterWriteStage recovery,
    ControllerIF.MemoryRegisterWriteStage ctrl,
    DebugIF.MemoryRegisterWriteStage debug
);
    MemoryRegisterWriteStageRegPath pipeReg[MEM_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif

    // --- Pipeline registers
    always_ff@( posedge /*port.clk*/ ctrl.clk )   // synchronous rst
    begin
        if (ctrl.rst) begin
            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                pipeReg[i].valid <= '0;
            end
        end
        else if(!ctrl.backEnd.stall) begin    // write data
            pipeReg <= prev.nextStage;
        end
    end


    logic stall, clear;
    logic flush[ MEM_ISSUE_WIDTH ];
    logic update [ MEM_ISSUE_WIDTH ];
    logic valid [ MEM_ISSUE_WIDTH ];
    ActiveListWriteData alWriteData[MEM_ISSUE_WIDTH];

    ExecutionState execState[MEM_ISSUE_WIDTH];
    MSHR_IndexPath mshrID;
    logic makeMSHRCanBeInvalid[MSHR_NUM];

    always_comb begin

        // Pipeline controll
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        // 以下のいずれかの場合，握っている MSHR を解放する
        // 1. MSHR を確保した命令がライトバックまで達した場合
        // 2. MSHR を確保した命令が後から SQ からのフォワードミスが発生した場合
        //      フォワード元のストアがミスしていた場合，MSHR をてばなさいとデッドロックする
        for (int j = 0; j < MSHR_NUM; j++) begin
            loadStoreUnit.makeMSHRCanBeInvalidDirect[j] = FALSE;
            for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
                if (j == pipeReg[i].mshrID && 
                    ((pipeReg[i].dataOut.valid && pipeReg[i].hasAllocatedMSHR) || pipeReg[i].storeForwardMiss) &&
                    pipeReg[i].valid && 
                    pipeReg[i].isLoad
                ) begin
                    loadStoreUnit.makeMSHRCanBeInvalidDirect[j] = TRUE;
                end
            end
        end

        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            valid[i] = pipeReg[i].valid;
            flush[i] = SelectiveFlushDetector(
                recovery.toRecoveryPhase,
                recovery.flushRangeHeadPtr,
                recovery.flushRangeTailPtr,
                recovery.flushAllInsns,
                pipeReg[i].activeListPtr
            );
            update[i] = !stall && !clear && valid[i] && !flush[i];

            //
            // Active list
            //
            alWriteData[i].ptr = pipeReg[i].activeListPtr;
            alWriteData[i].loadQueuePtr = pipeReg[i].loadQueueRecoveryPtr;
            alWriteData[i].storeQueuePtr = pipeReg[i].storeQueueRecoveryPtr;

            alWriteData[i].isBranch = FALSE;
            alWriteData[i].isStore = pipeReg[i].isStore;

            // ExecState
            if ( update[i] ) begin
                alWriteData[i].state = pipeReg[i].execState;
            end
            else begin
                alWriteData[i].state = EXEC_STATE_NOT_FINISHED;
            end
            execState[i] = alWriteData[i].state;

            alWriteData[i].pc = pipeReg[i].pc;
            alWriteData[i].dataAddr = pipeReg[i].addrOut;

            activeList.memWrite[i] = update[i];
            activeList.memWriteData[i] = alWriteData[i];
        end


        //
        // Register file
        //
        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin

            registerFile.memDstRegWE[i] =
                update[i] && pipeReg[i].opDst.writeReg;

            registerFile.memDstRegNum[i] = pipeReg[i].opDst.phyDstRegNum;
            registerFile.memDstRegData[i] = pipeReg[i].dataOut;
        end


        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            debug.memRwReg[i].valid = valid[i];
            debug.memRwReg[i].flush = flush[i];
            debug.memRwReg[i].opId = pipeReg[i].opId;
        end
`endif
    end
endmodule : MemoryRegisterWriteStage
