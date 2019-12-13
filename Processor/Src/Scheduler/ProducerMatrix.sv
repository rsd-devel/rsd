// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Dependency matrix.
//

import BasicTypes::*;
import SchedulerTypes::*;

module ProducerMatrix (
    input logic clk, stall,

    input logic dispatch[ DISPATCH_WIDTH ],
    input logic dispatchedSrcRegReady [ DISPATCH_WIDTH ][ ISSUE_QUEUE_SRC_REG_NUM ],
    input IssueQueueIndexPath [ DISPATCH_WIDTH-1:0 ][ ISSUE_QUEUE_SRC_REG_NUM-1:0 ] dispatchedSrcRegPtr,
    input [ISSUE_QUEUE_ENTRY_NUM-1:0] dependStoreBitVector [DISPATCH_WIDTH], 
    input IssueQueueIndexPath dispatchPtr[ DISPATCH_WIDTH ],

    input IssueQueueOneHotPath wakeupDstVector[ WAKEUP_WIDTH + STORE_ISSUE_WIDTH ],

    output logic opReady[ ISSUE_QUEUE_ENTRY_NUM ]
);
    // ProducerMatrix can be updated without regarding the validness of consumer
    // rows because an outer logic (Scheduler) check their validness.
    IssueQueueOneHotPath [ISSUE_QUEUE_ENTRY_NUM-1:0] nextMatrix;
    IssueQueueOneHotPath [ISSUE_QUEUE_ENTRY_NUM-1:0] matrix;   // Don't care.

`ifndef RSD_SYNTHESIS
    `ifndef RSD_VIVADO_SIMULATION
        // Don't care these values, but avoiding undefined status in Questa.
        initial begin
            matrix = '0;
        end
    `endif
`endif

    always_ff @(posedge clk) begin
        matrix <= nextMatrix;
    end

    IssueQueueOneHotPath [DISPATCH_WIDTH-1:0] dispatchVector;
    IssueQueueOneHotPath wakeupVector;
    always_comb begin

        nextMatrix = matrix;

        // Wakeup
        wakeupVector = '0;
        for (int w = 0; w < WAKEUP_WIDTH + STORE_ISSUE_WIDTH; w++) begin
            // A producer column can be cleared without regarding to validness of wakeup.
            //if (wakeup[w]) begin
            //end
            wakeupVector |= wakeupDstVector[w];
        end

        for (int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++) begin
            for (int j = 0; j < ISSUE_QUEUE_ENTRY_NUM; j++) begin
                nextMatrix[i][j] = wakeupVector[j] ? FALSE : nextMatrix[i][j];
            end
        end

        // It is ready when its all source bits are zero.
        for (int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++) begin
            opReady[i] = !(|(nextMatrix[i]));
        end

        if (stall) begin
            // Does not update.
            nextMatrix = matrix;
        end

        // Dispatch
        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
            dispatchVector[i] = '0;
            for (int j = 0; j < ISSUE_QUEUE_SRC_REG_NUM; j++) begin
                // dispatchedSrcRegReady are from a ready bit table and it includes validness information.
                if (!dispatchedSrcRegReady[i][j]) begin
                    dispatchVector[i][dispatchedSrcRegPtr[i][j]] = TRUE;
                end
            end

            for (int j = 0; j < ISSUE_QUEUE_ENTRY_NUM; j++) begin 
                if (dependStoreBitVector[i][j]) begin 
                    dispatchVector[i][j] = TRUE; 
                end 
            end 
        end

        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
            if (dispatch[i]) begin
                nextMatrix[dispatchPtr[i]] = dispatchVector[i];
            end
        end

    end

endmodule : ProducerMatrix
