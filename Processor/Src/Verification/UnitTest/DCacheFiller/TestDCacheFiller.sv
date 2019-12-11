// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;
import CacheSystemTypes::*;
import OpFormatTypes::*;

parameter STEP = 20;
parameter HOLD = 4;
parameter SETUP = 1;
parameter WAIT = STEP*2-HOLD-SETUP;

module TestDCacheFiller;
    
    //
    // Clock and Reset
    //
    logic clk, rst, rstOut;
    TestBenchClockGenerator #( .STEP(STEP) ) clkgen (.*);
    
    //
    // Top Module
    //
    logic dcMiss;
    AddrPath dcMissAddr;
    WayPtr dcVictimWayPtr;
    MemAccessResult dcMemAccessResult;
    logic dcFillReq;
    logic dcFillerBusy;
    AddrPath dcFillAddr;
    WayPtr dcFillWayPtr;
    LineDataPath dcFillData;
    logic dcFillAck;
    logic dcReplace;
    AddrPath dcReplaceAddr;
    LineDataPath dcReplaceData;
    MemAccessReq dcMemAccessReq;
    
    TestDCacheFillerTop top (
        .clk_p( clk ),
        .clk_n( ~clk ),
        .rstOut( rstOut ),
        .rstTrigger( rst ),
        .*
    );

    //
    // Test Data
    //
    initial begin
        // Initialize
        dcMiss = FALSE;
        dcMissAddr = '0;
        dcVictimWayPtr = '0;
        dcMemAccessResult = '0;
        dcFillAck = FALSE;
        dcReplace = FALSE;
        dcReplaceAddr = '0;
        dcReplaceData = '0;

        // Wait during reset sequence
        #WAIT;
        @(negedge rstOut);

        // Send request (Not replace)
        @(posedge clk);
        #HOLD;
        dcMiss = TRUE;
        dcMissAddr = 32'h12345678;
        dcVictimWayPtr = 1;
        
        @(posedge clk);
        #HOLD;
        dcMiss = FALSE;
        #WAIT;
        assert( dcMemAccessReq.valid == TRUE );
        assert( dcMemAccessReq.serial == 0 );
        assert( dcMemAccessReq.addr == 32'h12345678 );
        assert( dcMemAccessReq.we == FALSE );
        assert( dcFillerBusy == TRUE );
        
        // Receive result (immediate Ack)
        @(posedge clk);
        #HOLD;
        dcMemAccessResult.valid = TRUE;
        dcMemAccessResult.serial = 0;
        dcMemAccessResult.data = 128'h87654321_87654321_87654321_87654321;
        dcFillAck = TRUE;
        #WAIT;
        assert( dcFillReq == TRUE );
        assert( dcFillAddr == 32'h12345678 );
        assert( dcFillData == 128'h87654321_87654321_87654321_87654321 );
        assert( dcFillWayPtr == 1 );
        
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( dcFillerBusy == FALSE );

        // Send request (Replace)
        @(posedge clk);
        #HOLD;
        dcMiss = TRUE;
        dcMissAddr = 32'h00112233;
        dcVictimWayPtr = 0;
        dcReplace = TRUE;
        dcReplaceAddr = 32'h44556677;
        dcReplaceData = 128'h77665544_77665544_77665544_77665544;
        
        @(posedge clk);
        #HOLD;
        dcMiss = FALSE;
        #WAIT;
        assert( dcMemAccessReq.valid == TRUE );
        assert( dcMemAccessReq.serial == 1 );
        assert( dcMemAccessReq.addr == 32'h44556677 );
        assert( dcMemAccessReq.we == TRUE );
        assert( dcMemAccessReq.data == 128'h77665544_77665544_77665544_77665544 );
        assert( dcFillerBusy == TRUE );
        
        // Send request (Fill after Replace)
        @(posedge clk);
        #HOLD;
        dcMemAccessResult.valid = TRUE;
        dcMemAccessResult.serial = 1;
        #WAIT;
        assert( dcFillReq == FALSE );
        
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( dcMemAccessReq.valid == TRUE );
        assert( dcMemAccessReq.serial == 2 );
        assert( dcMemAccessReq.addr == 32'h00112233 );
        assert( dcMemAccessReq.we == FALSE );
        assert( dcFillerBusy == TRUE );

        // Receive result (wait to Ack)
        @(posedge clk);
        #HOLD;
        dcMemAccessResult.valid = TRUE;
        dcMemAccessResult.serial = 2;
        dcMemAccessResult.data = 128'h33221100_33221100_33221100_33221100;
        dcFillAck = FALSE;
        #WAIT;
        assert( dcFillReq == TRUE );
        assert( dcFillAddr == 32'h00112233 );
        assert( dcFillData == 128'h33221100_33221100_33221100_33221100 );
        assert( dcFillWayPtr == 0 );

        @(posedge clk);
        #HOLD;
        dcFillAck = TRUE;
        #WAIT;
        assert( dcFillerBusy == TRUE );

        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( dcFillerBusy == FALSE );

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        $finish;
    end

endmodule
