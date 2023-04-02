// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// FP Write back stage
//

import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import RenameLogicTypes::*;
import PipelineTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import DebugTypes::*;

`ifdef RSD_MARCH_FP_PIPE

module FPRegisterWriteStage(
    FPExecutionStageIF.NextStage prev,
    RegisterFileIF.FPRegisterWriteStage registerFile,
    ActiveListIF.FPRegisterWriteStage activeList,
    RecoveryManagerIF.FPRegisterWriteStage recovery,
    ControllerIF.FPRegisterWriteStage ctrl,
    DebugIF.FPRegisterWriteStage debug
);
    FPRegisterWriteStageRegPath pipeReg[FP_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif
    // --- Pipeline registers
    always_ff@(posedge ctrl.clk)   // synchronous rst
    begin
        if (ctrl.rst) begin
            for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin
                pipeReg[i].valid <= '0;
            end
        end
        else if(!ctrl.backEnd.stall) begin    // write data
            pipeReg <= prev.nextStage;
        end
    end

    ActiveListWriteData alWriteData[FP_ISSUE_WIDTH];
    FPIssueQueueEntry iqData[FP_ISSUE_WIDTH];
    logic stall, clear;
    logic flush[ FP_ISSUE_WIDTH ];
    logic update [ FP_ISSUE_WIDTH ];
    logic valid [ FP_ISSUE_WIDTH ];
    logic regValid [ FP_ISSUE_WIDTH ];

    always_comb begin

        // Pipeline controll
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            iqData[i] = pipeReg[i].fpQueueData;
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

            registerFile.fpDstRegWE[i] =
                update[i] && iqData[i].opDst.writeReg;

            registerFile.fpDstRegNum[i] = iqData[i].opDst.phyDstRegNum;
            registerFile.fpDstRegData[i] = pipeReg[i].dataOut;
            //
            // Active list
            //
            alWriteData[i].ptr = iqData[i].activeListPtr;
            alWriteData[i].loadQueuePtr = iqData[i].loadQueueRecoveryPtr;
            alWriteData[i].storeQueuePtr = iqData[i].storeQueueRecoveryPtr;
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

            activeList.fpWrite[i] = update[i];
            activeList.fpWriteData[i] = alWriteData[i];
            activeList.fpFFlagsData[i] = pipeReg[i].fflagsOut;
        end

        // Debug Register
        `ifndef RSD_DISABLE_DEBUG_REGISTER
            for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
                debug.fpRwReg[i].valid = valid[i];
                debug.fpRwReg[i].flush = flush[i];
                debug.fpRwReg[i].opId = pipeReg[i].opId;
            end
        `endif
    end
endmodule : FPRegisterWriteStage

`endif
