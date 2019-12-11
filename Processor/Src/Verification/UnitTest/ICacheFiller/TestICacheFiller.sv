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

module TestICacheFiller;
    
    //
    // Clock and Reset
    //
    logic clk, rst, rstOut;
    TestBenchClockGenerator #( .STEP(STEP) ) clkgen (.*);
    
    //
    // Top Module
    //
    logic icMiss;
    AddrPath icMissAddr;
    WayPtr icVictimWayPtr;
    MemAccessResult icMemAccessResult;
    logic icFill;
    logic icFillerBusy;
    AddrPath icFillAddr;
    WayPtr icFillWayPtr;
    LineDataPath icFillData;
    MemReadAccessReq icMemAccessReq;
    
    TestICacheFillerTop top (
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
        icMiss = FALSE;
        icMissAddr = '0;
        icVictimWayPtr = '0;
        icMemAccessResult = '0;

        // Wait during reset sequence
        #WAIT;
        @(negedge rstOut);

        // Send request
        @(posedge clk);
        #HOLD;
        icMiss = TRUE;
        icMissAddr = 32'h12345678;
        icVictimWayPtr = 1;
        
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( icMemAccessReq.valid == TRUE );
        assert( icMemAccessReq.serial == 0 );
        assert( icMemAccessReq.addr == 32'h12345678 );
        assert( icFillerBusy == TRUE );
        
        // Receive result
        @(posedge clk);
        #HOLD;
        icMemAccessResult.valid = TRUE;
        icMemAccessResult.serial = 0;
        icMemAccessResult.data = 128'h87654321_87654321_87654321_87654321;
        #WAIT;
        assert( icFill == TRUE );
        assert( icFillAddr == 32'h12345678 );
        assert( icFillData == 128'h87654321_87654321_87654321_87654321 );
        assert( icFillWayPtr == 1 );

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        $finish;
    end

endmodule
