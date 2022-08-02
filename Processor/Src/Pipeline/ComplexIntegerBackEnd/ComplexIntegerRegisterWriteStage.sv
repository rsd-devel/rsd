// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Complex Integer Write back stage
//

import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import RenameLogicTypes::*;
import PipelineTypes::*;
import SchedulerTypes::*;
import DebugTypes::*;

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE

module ComplexIntegerRegisterWriteStage(
    ComplexIntegerExecutionStageIF.NextStage prev,
    RegisterFileIF.ComplexIntegerRegisterWriteStage registerFile,
    ActiveListIF.ComplexIntegerRegisterWriteStage activeList,
    RecoveryManagerIF.ComplexIntegerRegisterWriteStage recovery,
    ControllerIF.ComplexIntegerRegisterWriteStage ctrl,
    DebugIF.ComplexIntegerRegisterWriteStage debug
);
    ComplexIntegerRegisterWriteStageRegPath pipeReg[COMPLEX_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif
    // --- Pipeline registers
    always_ff@(posedge ctrl.clk)   // synchronous rst
    begin
        if (ctrl.rst) begin
            for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
                pipeReg[i].valid <= '0;
            end
        end
        else if(!ctrl.backEnd.stall) begin    // write data
            pipeReg <= prev.nextStage;
        end
    end

    ActiveListWriteData alWriteData[COMPLEX_ISSUE_WIDTH];
    IntIssueQueueEntry iqData[COMPLEX_ISSUE_WIDTH];
    logic stall, clear;
    logic flush[ COMPLEX_ISSUE_WIDTH ];
    logic update [ COMPLEX_ISSUE_WIDTH ];
    logic valid [ COMPLEX_ISSUE_WIDTH ];
    logic regValid [ COMPLEX_ISSUE_WIDTH ];

    always_comb begin

        // Pipeline controll
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            iqData[i] = pipeReg[i].complexQueueData;
            regValid[i] = pipeReg[i].dataOut.valid;

            valid[i] = pipeReg[i].valid;
            flush[i] = SelectiveFlushDetector(
                        recovery.toRecoveryPhase,
                        recovery.flushRangeHeadPtr,
                        recovery.flushRangeTailPtr,
                        recovery.flushAllInsns,
                        iqData[i].activeListPtr
                        );
            update[i] = !stall && !clear && valid[i] && !flush[i];


            //
            // Register file
            //

            registerFile.complexDstRegWE[i] =
                update[i] && iqData[i].opDst.writeReg;

            registerFile.complexDstRegNum[i] = iqData[i].opDst.phyDstRegNum;
            registerFile.complexDstRegData[i] = pipeReg[i].dataOut;
`ifdef RSD_ENABLE_VECTOR_PATH
            registerFile.complexDstVecData[i] = pipeReg[i].vecDataOut;
`endif
            //
            // Active list
            //
            alWriteData[i].ptr = iqData[i].activeListPtr;
            alWriteData[i].loadQueuePtr = iqData[i].loadQueueRecoveryPtr;
            alWriteData[i].storeQueuePtr = iqData[i].storeQueueRecoveryPtr;
            alWriteData[i].ptr = iqData[i].activeListPtr;
            alWriteData[i].pc = iqData[i].pc;
            alWriteData[i].dataAddr = '0;
            alWriteData[i].isBranch = FALSE;
            alWriteData[i].isStore = FALSE;

            // ExecState
            if ( update[i] && regValid[i] ) begin
                alWriteData[i].state = EXEC_STATE_SUCCESS;
            end
            else begin
                alWriteData[i].state = EXEC_STATE_NOT_FINISHED;
            end

            activeList.complexWrite[i] = update[i];
            activeList.complexWriteData[i] = alWriteData[i];
        end

        // Debug Register
        `ifndef RSD_DISABLE_DEBUG_REGISTER
            for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
                debug.complexRwReg[i].valid = valid[i];
                debug.complexRwReg[i].flush = flush[i];
                debug.complexRwReg[i].opId = pipeReg[i].opId;
            end
        `endif
    end
endmodule : ComplexIntegerRegisterWriteStage

`endif
