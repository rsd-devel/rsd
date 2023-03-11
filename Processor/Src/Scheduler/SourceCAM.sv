// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Source Register CAM module for Wakeup Logic
//
`ifndef REF
    `define REF ref
`endif

import BasicTypes::*;
import SchedulerTypes::*;

// - Written:
// dispatch: A write enable signal for cam entries on dispatch.
// dispatchPtr: Write pointer (one-hot).
// dispatchedSrcRegNum: Written CAM entry data, which are physical register numbers of source operands.
// dispatchedSrcReady: True if written source operands are already ready
//                     or dispatch they are invalid in the instruction.
// - Wakeup:
// wakeupDstRegNum: A tag data for wakeup, which are physical register numbers of destination operands.
// opReady: Bit vector corresponding to an issue queue. Each bit indicates
// whether each entry is ready or not.

module SourceCAM #(
    parameter SRC_OP_NUM = 1,
    parameter REG_NUM_BIT_WIDTH = 1
)(
    // input
    input   logic clk, rst,
    input   logic dispatch [ DISPATCH_WIDTH ],
    input   IssueQueueIndexPath dispatchPtr [ DISPATCH_WIDTH ],
    input   logic [REG_NUM_BIT_WIDTH-1:0] dispatchedSrcRegNum [ DISPATCH_WIDTH ][ SRC_OP_NUM ],
    input   logic dispatchedSrcReady [ DISPATCH_WIDTH ][ SRC_OP_NUM ],
    input   logic wakeup [ WAKEUP_WIDTH ],
    input   logic wakeupDstValid [ WAKEUP_WIDTH ],
    input   logic [REG_NUM_BIT_WIDTH-1:0] wakeupDstRegNum [ WAKEUP_WIDTH ],
    // output
    output     IssueQueueOneHotPath opReady

);
    typedef logic [REG_NUM_BIT_WIDTH-1:0] RegNumPath;

    // A bit array of a CAM wake-up logic rdyL / rdyR.
    logic srcReady[ ISSUE_QUEUE_ENTRY_NUM ][ SRC_OP_NUM ];
    logic nextSrcReady[ ISSUE_QUEUE_ENTRY_NUM ][ SRC_OP_NUM ];

    // # of source register : key entries of the CAM.
    RegNumPath srcRegNum[ ISSUE_QUEUE_ENTRY_NUM ][ SRC_OP_NUM ];

    // Match lines of CAM.
    logic match[ ISSUE_QUEUE_ENTRY_NUM ][ SRC_OP_NUM ];


    always_ff @( posedge clk ) begin
        // rdyL / rdyR
        for( int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++ ) begin
            for( int j = 0; j < SRC_OP_NUM; j++ ) begin
                srcReady[i][j] <= ( rst ? FALSE : nextSrcReady[i][j] );
            end
        end

        if (rst) begin
            for( int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++ ) begin
                for( int j = 0; j < SRC_OP_NUM; j++ ) begin
                    srcRegNum[i][j] <= 0;
                end
            end
        end
        else begin
            // Dispatch
            for ( int i = 0; i < DISPATCH_WIDTH; i++ ) begin
                if( dispatch[i] ) begin
                    for( int j = 0; j < SRC_OP_NUM; j++ ) begin
                        srcRegNum[ dispatchPtr[i] ][j] <= dispatchedSrcRegNum[i][j];
                    end
                end
            end
        end
    end

    always_comb begin
        // Tag match
        for( int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++ ) begin
            for( int j = 0; j < SRC_OP_NUM; j++ ) begin
                match[i][j] = FALSE;
                // Test all broadcasted tags.
                for( int k = 0; k < WAKEUP_WIDTH; k++ ) begin
                    if ( wakeup[k] && wakeupDstValid[k] )
                        match[i][j] = match[i][j] || ( wakeupDstRegNum[k] == srcRegNum[i][j] );
                end
            end
        end

        // Output ready information of each op.
        for( int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++ ) begin
            opReady[i] = TRUE;
            for( int j = 0; j < SRC_OP_NUM; j++ ) begin
                opReady[i] = opReady[i] && ( match[i][j] || srcReady[i][j] );
            end
        end

        // Set nextSrcReady
        for( int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++ ) begin
            for( int j = 0; j < SRC_OP_NUM; j++ ) begin
                nextSrcReady[i][j] = srcReady[i][j] || match[i][j];
            end
        end
        for( int i = 0; i < DISPATCH_WIDTH; i++ ) begin
            for ( int j = 0; j < SRC_OP_NUM; j++ ) begin
                if( dispatch[i] )
                    nextSrcReady[ dispatchPtr[i] ][j] = dispatchedSrcReady[i][j];    // Dispatch
            end
        end

    end


endmodule : SourceCAM

