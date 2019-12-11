// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;
import SchedulerTypes::*;

module TestSourceCAM_Top #(
    parameter SRC_OP_NUM = 2
)(
input
    logic clk_p, clk_n, rstTrigger,
output
    logic rstOut,
input
    logic [ DISPATCH_WIDTH-1:0 ] dispatch,
    IssueQueueIndexPath [ DISPATCH_WIDTH-1:0 ] dispatchPtr,
    PRegNumPath [ DISPATCH_WIDTH-1:0 ][ SRC_OP_NUM-1:0 ] dispatchedSrcRegNum,
    logic [ DISPATCH_WIDTH-1:0 ][ SRC_OP_NUM-1:0 ] dispatchedSrcReady,
    logic [ WAKEUP_WIDTH-1:0 ] wakeup,
    SchedulerRegTag [ WAKEUP_WIDTH-1:0 ] wakeupDstTag,
output
    IssueQueueOneHotPath opReady
);
    int i, j;
    
    // Clock and Reset
    logic clk, rst, mmcmLocked;
    `ifdef RSD_SYNTHESIS
        SingleClock clkgen( clk_p, clk_n, clk );
    `else
        assign clk = clk_p;
    `endif
    
    ResetController rstController(.*);
    assign rstOut = rst;
    assign mmcmLocked = TRUE;
    
    // Module for test
    logic unpackedDispatch [ DISPATCH_WIDTH ];
    IssueQueueIndexPath unpackedDispatchPtr [ DISPATCH_WIDTH ];
    PRegNumPath unpackedDispatchedSrcRegNum [ DISPATCH_WIDTH ][ SRC_OP_NUM ];
    logic unpackedDispatchedSrcReady [ DISPATCH_WIDTH ][ SRC_OP_NUM ];
    logic unpackedWakeup [ WAKEUP_WIDTH ];
    SchedulerRegTag unpackedWakeupDstTag [ WAKEUP_WIDTH ];

    SourceCAM #( 
        .SRC_OP_NUM( SRC_OP_NUM )
    ) sourceCAM (
        .dispatch( unpackedDispatch ),
        .dispatchPtr( unpackedDispatchPtr ),
        .dispatchedSrcRegNum( unpackedDispatchedSrcRegNum ),
        .dispatchedSrcReady( unpackedDispatchedSrcReady ),
        .wakeup( unpackedWakeup ),
        .wakeupDstTag( unpackedWakeupDstTag ),
        .*
    );
    
    always_comb begin
        for ( i = 0; i < DISPATCH_WIDTH; i++ ) begin
            unpackedDispatch[i] = dispatch[i];
            unpackedDispatchPtr[i] = dispatchPtr[i];
            for ( j = 0; j < SRC_OP_NUM; j++ ) begin
                unpackedDispatchedSrcRegNum[i][j] = dispatchedSrcRegNum[i][j];
                unpackedDispatchedSrcReady[i][j]  = dispatchedSrcReady[i][j];
            end
        end
        for ( i = 0; i < WAKEUP_WIDTH; i++ ) begin
            unpackedWakeup[i] = wakeup[i];
            unpackedWakeupDstTag[i] = wakeupDstTag[i];
        end
    end
    
endmodule
