// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for issuing ops.
//


import BasicTypes::*;
import MicroOpTypes::*;
import PipelineTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import DebugTypes::*;

module MemoryIssueStage(
    MemoryIssueStageIF.ThisStage port,
    ScheduleStageIF.MemNextStage prev,
    SchedulerIF.MemoryIssueStage scheduler,
    RecoveryManagerIF.MemoryIssueStage recovery,
    MulDivUnitIF.MemoryIssueStage mulDivUnit,
    ControllerIF.MemoryIssueStage ctrl,
    DebugIF.MemoryIssueStage debug
);

    // --- Pipeline registers
    IssueStageRegPath pipeReg [ MEM_ISSUE_WIDTH ];
    IssueStageRegPath nextPipeReg [ MEM_ISSUE_WIDTH ];
    always_ff@( posedge port.clk )   // synchronous rst
    begin
        if ( port.rst ) begin
            for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ )
                pipeReg[i] <= '0;
        end
        else if( !ctrl.isStage.stall )              // write data
            pipeReg <= prev.memNextStage;
        else
            pipeReg <= nextPipeReg;
    end

    always_comb begin
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            if (recovery.toRecoveryPhase) begin
                nextPipeReg[i].valid = 
                    pipeReg[i].valid &&
                    !SelectiveFlushDetector(
                        recovery.toRecoveryPhase,
                        recovery.flushRangeHeadPtr,
                        recovery.flushRangeTailPtr,
                        recovery.flushAllInsns,
                        scheduler.memIssuedData[i].activeListPtr
                    );
            end
            else begin
                nextPipeReg[i].valid = pipeReg[i].valid;
            end
            
            nextPipeReg[i].issueQueuePtr = pipeReg[i].issueQueuePtr;
        end
    end



    // Pipeline controll
    logic stall, clear;
    logic flush[ MEM_ISSUE_WIDTH ];
    logic valid [ MEM_ISSUE_WIDTH ];
    MemoryRegisterReadStageRegPath nextStage [ MEM_ISSUE_WIDTH ];
    MemIssueQueueEntry issuedData [ MEM_ISSUE_WIDTH ];
    IssueQueueIndexPath issueQueuePtr [ MEM_ISSUE_WIDTH ];

    always_comb begin

        stall = ctrl.isStage.stall;
        clear = ctrl.isStage.clear;

        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin

            if (scheduler.replay) begin
                issuedData[i] = scheduler.memReplayData[i];
                valid[i] = scheduler.memReplayEntry[i];
            end
            else begin
                issuedData[i] = scheduler.memIssuedData[i];
                valid[i] = !stall && pipeReg[i].valid;
            end

            issueQueuePtr[i] = pipeReg[i].issueQueuePtr;

            flush[i] = SelectiveFlushDetector(
                        recovery.toRecoveryPhase,
                        recovery.flushRangeHeadPtr,
                        recovery.flushRangeTailPtr,
                        recovery.flushAllInsns,
                        issuedData[i].activeListPtr
                        );

            // Issue
            scheduler.memIssue[i] = !clear && valid[i] && !flush[i];
            scheduler.memIssuePtr[i] = issueQueuePtr[i];

            // Release the entries of the issue queue.
            nextStage[i].replay = scheduler.replay;
            nextStage[i].issueQueuePtr = issueQueuePtr[i];

            // --- Pipeline ラッチ書き込み
            // リセットorフラッシュ時はNOP
            nextStage[i].valid =
                (clear || port.rst || flush[i]) ? FALSE : valid[i];
            nextStage[i].memQueueData = issuedData[i];
`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].opId = issuedData[i].opId;
`endif
        end

`ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin
            // Lock div units
            mulDivUnit.divAcquire[i] = 
                !clear && valid[i] && !flush[i] && 
                issuedData[i].memOpInfo.opType == MEM_MOP_TYPE_DIV;
            mulDivUnit.acquireActiveListPtr[i] = issuedData[i].activeListPtr;
        end
`endif
        port.nextStage = nextStage;

`ifndef RSD_DISABLE_DEBUG_REGISTER
        // Debug Register
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            debug.memIsReg[i].valid = valid[i];
            debug.memIsReg[i].flush = flush[i];
            debug.memIsReg[i].opId = issuedData[i].opId;
        end
`endif
    end


endmodule : MemoryIssueStage
