// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for scheduling.
//


import BasicTypes::*;
import MemoryMapTypes::*;
import MicroOpTypes::*;
import PipelineTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import DebugTypes::*;

module ScheduleStage(
    ScheduleStageIF.ThisStage port,
    SchedulerIF.ScheduleStage scheduler,
    RecoveryManagerIF.ScheduleStage recovery,
    ControllerIF.ScheduleStage ctrl
);
    // Pipeline controll
    logic stall, clear;
    logic flush [ ISSUE_WIDTH ];
    logic valid [ ISSUE_WIDTH ];
    logic update [ ISSUE_WIDTH ];
    IssueStageRegPath nextStage [ ISSUE_WIDTH ];
    IssueQueueIndexPath issueQueuePtr [ ISSUE_WIDTH ];
    IssueQueueOneHotPath flushIQ_Entry;

    always_comb begin

        stall = ctrl.scStage.stall;
        clear = ctrl.scStage.clear;

        // Scheduling
        scheduler.stall = stall;

        flushIQ_Entry = recovery.flushIQ_Entry;

        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            valid[i] = scheduler.selected[i];
            issueQueuePtr[i] = scheduler.selectedPtr[i];
            flush[i] = flushIQ_Entry[issueQueuePtr[i]];
            update[i] = !stall && !clear && valid[i] && !flush[i];

            // --- Pipeline ラッチ書き込み
            // リセットorフラッシュ時はNOP
            nextStage[i].valid =
                (stall || clear || port.rst || flush[i]) ? FALSE : valid[i];

            nextStage[i].issueQueuePtr = scheduler.selectedPtr[i];

            if ( i < INT_ISSUE_WIDTH )
                port.intNextStage[i] = nextStage[i];
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            else if ( i < INT_ISSUE_WIDTH + COMPLEX_ISSUE_WIDTH )
                port.complexNextStage[ i-INT_ISSUE_WIDTH ] = nextStage[i];
`endif
            else if ( i < INT_ISSUE_WIDTH + COMPLEX_ISSUE_WIDTH + MEM_ISSUE_WIDTH)
                port.memNextStage[ i-INT_ISSUE_WIDTH-COMPLEX_ISSUE_WIDTH ] = nextStage[i];
`ifdef RSD_MARCH_FP_PIPE
            else
                port.fpNextStage[ i-INT_ISSUE_WIDTH-COMPLEX_ISSUE_WIDTH-MEM_ISSUE_WIDTH] = nextStage[i];
`endif
        end
    end


endmodule : ScheduleStage
