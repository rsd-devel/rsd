// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;
import SchedulerTypes::*;

parameter STEP = 200;
parameter HOLD = 40; // When HOLD = 3ns, a X_RAMB18E1 causes hold time error!
parameter SETUP = 10;
parameter WAIT = STEP*2-HOLD-SETUP;

module TestSourceCAM;
    
    //
    // Clock and Reset
    //
    logic clk, rst, rstOut;
    TestBenchClockGenerator #( .STEP(STEP) )clkgen(.*);
    
    //
    // Modules for test
    //
    parameter SRC_OP_NUM = 2;
    
    logic [ DISPATCH_WIDTH-1:0 ] dispatch;
    IssueQueueIndexPath [ DISPATCH_WIDTH-1:0 ] dispatchPtr;
    PRegNumPath [ DISPATCH_WIDTH-1:0 ][ SRC_OP_NUM-1:0 ] dispatchedSrcRegNum;
    logic [ DISPATCH_WIDTH-1:0 ][ SRC_OP_NUM-1:0 ] dispatchedSrcReady;
    logic [ WAKEUP_WIDTH-1:0 ] wakeup;
    SchedulerRegTag [ WAKEUP_WIDTH-1:0 ] wakeupDstTag;
    IssueQueueOneHotPath opReady;
    
    TestSourceCAM_Top top (
        .clk_p( clk ),
        .clk_n( ~clk ),
        .rstTrigger( rst ),
        .*
    );
    
    //
    // Test data
    //
    initial begin
        int i, j;
        
        assert( DISPATCH_WIDTH == 4 );
        assert( WAKEUP_WIDTH == 4 );
        assert( SRC_OP_NUM == 2 );
        assert( ISSUE_QUEUE_ENTRY_NUM == 16 );
        
        // Initialize logic
        for ( i = 0; i < DISPATCH_WIDTH; i++ ) begin
            dispatch[i] = FALSE;
            dispatchPtr[i] = 0;
            for ( j = 0; j < SRC_OP_NUM; j++ ) begin
                dispatchedSrcRegNum[i][j] = 0;
                dispatchedSrcReady[i][j] = FALSE;
            end
        end
        for ( i = 0; i < WAKEUP_WIDTH; i++ ) begin
            wakeup[i] = FALSE;
            wakeupDstTag[i].valid = FALSE;
            wakeupDstTag[i].tag = 0;
        end
        
        // Wait during reset sequence
        #WAIT;
        @(negedge rstOut);
        
        @(posedge clk);
        
        //
        // cycle_1
        //
        #HOLD;
        
        // lane_0 : 即ウェイクアップ可能
        dispatch[0] = TRUE;
        dispatchPtr[0] = 0;
        dispatchedSrcReady[0][0] = TRUE;
        dispatchedSrcReady[0][1] = TRUE;

        // lane_1 : 即ウェイクアップ可能
        dispatch[1] = TRUE;
        dispatchPtr[1] = 1;
        dispatchedSrcReady[1][0] = TRUE;
        dispatchedSrcReady[1][1] = TRUE;
        
        // lane_2 : 即ウェイクアップ可能
        dispatch[2] = TRUE;
        dispatchPtr[2] = 2;
        dispatchedSrcReady[2][0] = TRUE;
        dispatchedSrcReady[2][1] = TRUE;
        
        // lane_3 : 即ウェイクアップ可能
        dispatch[3] = TRUE;
        dispatchPtr[3] = 3;
        dispatchedSrcReady[3][0] = TRUE;
        dispatchedSrcReady[3][1] = TRUE;
        
        @(posedge clk);
        
        //
        // cycle_2
        //
        #HOLD;
        
        // lane_0 : 即ウェイクアップ可能
        dispatch[0] = TRUE;
        dispatchPtr[0] = 4;
        dispatchedSrcReady[0][0] = TRUE;
        dispatchedSrcReady[0][1] = TRUE;

        // lane_1 : lane_0に依存
        dispatch[1] = TRUE;
        dispatchPtr[1] = 5;
        dispatchedSrcReady[1][0] = TRUE;
        dispatchedSrcReady[1][1] = FALSE;
        dispatchedSrcRegNum[1][1] = 4;

        // lane_2 : lane_1に依存
        dispatch[2] = TRUE;
        dispatchPtr[2] = 6;
        dispatchedSrcReady[2][0] = FALSE;
        dispatchedSrcReady[2][1] = TRUE;
        dispatchedSrcRegNum[2][0] = 5;

        // lane_3 : lane_0とlane_1に依存
        dispatch[3] = TRUE;
        dispatchPtr[3] = 7;
        dispatchedSrcRegNum[3][0] = 4;
        dispatchedSrcRegNum[3][1] = 5;
        dispatchedSrcReady[3][0] = FALSE;
        dispatchedSrcReady[3][1] = FALSE;
        
        #WAIT;
        // cycle_1 のディスパッチ・ウェイクアップ結果を反映
        assert( opReady[3:0] == 4'b1111 );
        @(posedge clk);
        
        //
        // cycle_3
        //
        #HOLD;
        dispatch[0] = FALSE;
        dispatch[1] = FALSE;
        dispatch[2] = FALSE;
        dispatch[3] = FALSE;
        
        #WAIT;
        // cycle_2 のディスパッチ・ウェイクアップ結果を反映
        assert( opReady[7:0] == 8'b0001_1111 );
        
        @(posedge clk);
        
        //
        // cycle_4
        //
        #HOLD;
        // cycle2.lane_0 のdstをwakeup
        wakeup[0] = FALSE;
        wakeup[1] = FALSE;
        wakeup[2] = TRUE;
        wakeupDstTag[2].valid = TRUE;
        wakeupDstTag[2].tag = 4;
        wakeup[3] = FALSE;
        
        #WAIT;
        // cycle_3 のディスパッチ・ウェイクアップ結果を反映
        assert( opReady[7:0] == 8'b0011_1111 );
        
        @(posedge clk);
        
        //
        // cycle_5
        //
        #HOLD;
        // lane_1 のDstをwakeup
        wakeup[0] = FALSE;
        wakeup[1] = TRUE;
        wakeupDstTag[1].valid = TRUE;
        wakeupDstTag[1].tag = 5;
        wakeup[2] = FALSE;
        wakeup[3] = FALSE;
        #WAIT;
        // cycle_4 のディスパッチ・ウェイクアップ結果を反映
        assert( opReady[7:0] == 8'b1111_1111 );
        
        @(posedge clk);

        //
        // cycle_6
        //
        #HOLD;
        wakeup[0] = FALSE;
        wakeup[1] = FALSE;
        wakeup[2] = FALSE;
        wakeup[3] = FALSE;

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        //
        // MainでFibonacciを動かした時に、バグっているケース
        //
        #HOLD;
        
        // lane_0 : r2 = #1
        dispatch[0] = TRUE;
        dispatchPtr[0] = 14;
        dispatchedSrcRegNum[0][0] = 6;
        dispatchedSrcRegNum[0][1] = 6;
        dispatchedSrcReady[0][0] = TRUE;
        dispatchedSrcReady[0][1] = TRUE;

        // lane_1 : r3 = r1 + r2
        dispatch[1] = TRUE;
        dispatchPtr[1] = 15;
        dispatchedSrcRegNum[1][0] = 6;
        dispatchedSrcRegNum[1][1] = 1;
        dispatchedSrcReady[1][0] = TRUE;
        dispatchedSrcReady[1][1] = FALSE;
        
        // lane_2 : r1 = r2
        dispatch[2] = TRUE;
        dispatchPtr[2] = 0;
        dispatchedSrcRegNum[2][0] = 6;
        dispatchedSrcRegNum[2][1] = 1;
        dispatchedSrcReady[2][0] = TRUE;
        dispatchedSrcReady[2][1] = FALSE;
        
        // lane_3 : r2 = r3
        dispatch[3] = TRUE;
        dispatchPtr[3] = 1;
        dispatchedSrcRegNum[3][0] = 6;
        dispatchedSrcRegNum[3][1] = 0;
        dispatchedSrcReady[3][0] = TRUE;
        dispatchedSrcReady[3][1] = FALSE;
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        $finish;
    end

endmodule
