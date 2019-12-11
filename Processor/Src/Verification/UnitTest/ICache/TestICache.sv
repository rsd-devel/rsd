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

`ifdef RSD_POST_SYNTHESIS_SIMULATION
    `define ASSERT_FILLER_PHASE_NONE
    `define ASSERT_FILLER_PHASE_REPLACE
`else
    `define ASSERT_FILLER_PHASE_NONE assert( top.dCacheFiller.phase == FILLER_PHASE_NONE );
    `define ASSERT_FILLER_PHASE_REPLACE assert( top.dCacheFiller.phase == FILLER_PHASE_REPLACE );
`endif

module TestICache;
    
    //
    // Clock and Reset
    //
    logic clk, rst, rstOut;
    TestBenchClockGenerator #( .STEP(STEP) ) clkgen (.*);
    
    //
    // Top Module
    //
    logic       icRE;
    AddrPath    icNextReadAddrIn;
    logic       [ FETCH_WIDTH-1:0 ] icReadHit;
    DataPath    [ FETCH_WIDTH-1:0 ] icReadDataOut;
    logic icFill, icMiss;
    logic icFillerBusy;
    AddrPath icFillAddr, icMissAddr;
    WayPtr icFillWayPtr, icVictimWayPtr;
    LineDataPath icFillData;
    
    TestICacheTop top (
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
        assert( FETCH_WIDTH == 4 );
        assert( WAY_NUM == 2 );
        assert( LINE_WORD_WIDTH_BIT_SIZE == 2 );
        assert( INDEX_BIT_WIDTH == 4 );
        
        // Initialize
        icRE = FALSE;
        icNextReadAddrIn = '1;
        icFill = FALSE;
        icFillAddr = '1;
        icFillData = '1;
        icFillWayPtr = '1;
        icFillerBusy = FALSE;

        // Wait during reset sequence
        #WAIT;
        @(negedge rstOut);

        //
        // Read ICache
        //

        // 1st Read (Cache Miss)
        @(posedge clk);
        #HOLD;
        icNextReadAddrIn = 32'h00004000;
        @(posedge clk);
        #HOLD;
        icRE = TRUE;
        #WAIT;
        //assert( icFiller.phase == FILLER_PHASE_NONE );
        assert( !icReadHit[0] );
        assert( !icReadHit[1] );
        assert( !icReadHit[2] );
        assert( !icReadHit[3] );
        assert( icMiss );
        assert( icMissAddr == 32'h00004000 );
        assert( icVictimWayPtr == 0 );
        
        // Fill
        @(posedge clk);
        #HOLD;
        icFill = TRUE;
        icFillAddr = 32'h00004000;
        icFillData = 128'he3a01000e3a00000eafffffeea000000;
        icFillWayPtr = 0;
        @(posedge clk);
        #HOLD;
        icFill = FALSE;

        // 2nd Read (Cache Hit)
        @(posedge clk);
        #HOLD;
        #WAIT;
        //assert( icFiller.phase == FILLER_PHASE_NONE );
        assert( icReadHit[0] );
        assert( icReadHit[1] );
        assert( icReadHit[2] );
        assert( icReadHit[3] );
        assert( icReadDataOut[0] == 32'hea000000 );
        assert( icReadDataOut[1] == 32'heafffffe );
        assert( icReadDataOut[2] == 32'he3a00000 );
        assert( icReadDataOut[3] == 32'he3a01000 );
        assert( !icMiss );

        // Same line (Cache Hit)
        @(posedge clk);
        #HOLD;
        icNextReadAddrIn = 32'h00004004;
        @(posedge clk);
        #HOLD;
        #WAIT;
        //assert( icFiller.phase == FILLER_PHASE_NONE );
        assert( icReadHit[0] );
        assert( icReadHit[1] );
        assert( icReadHit[2] );
        assert( !icReadHit[3] );
        assert( icReadDataOut[0] == 32'heafffffe );
        assert( icReadDataOut[1] == 32'he3a00000 );
        assert( icReadDataOut[2] == 32'he3a01000 );
        assert( !icMiss );

        // Another line (Cache Miss)
        @(posedge clk);
        #HOLD;
        icNextReadAddrIn = 32'h00004040;
        icFillerBusy = TRUE;
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( !icReadHit[0] );
        assert( !icReadHit[1] );
        assert( !icReadHit[2] );
        assert( !icReadHit[3] );
        assert( icMiss );
        assert( icMissAddr == 32'h00004040 );
        assert( icVictimWayPtr == 0 );
        
        // Filler Busy
        @(posedge clk);
        @(posedge clk);
        #HOLD;
        icFillerBusy = FALSE;
        #WAIT;
        assert( icMiss );
        assert( icMissAddr == 32'h00004040 );
        assert( icVictimWayPtr == 0 );
        
        // Fill
        @(posedge clk);
        #HOLD;
        icFill = TRUE;
        icFillAddr = 32'h00004040;
        icFillData = 128'he3a00000eaffffedeb00017ce3a0e000;
        icFillWayPtr = 0;
        @(posedge clk);
        #HOLD;
        icFill = FALSE;
        
        @(posedge clk);
        #HOLD;
        #WAIT;
        //assert( icFiller.phase == FILLER_PHASE_NONE );
        assert( icReadHit[0] );
        assert( icReadHit[1] );
        assert( icReadHit[2] );
        assert( icReadHit[3] );
        assert( icReadDataOut[0] == 32'he3a0e000 );
        assert( icReadDataOut[1] == 32'heb00017c );
        assert( icReadDataOut[2] == 32'heaffffed );
        assert( icReadDataOut[3] == 32'he3a00000 );
        assert( !icMiss );
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        //
        // Cause replace
        //
        
        // Read 4100 (Cache Miss)
        @(posedge clk);
        #HOLD;
        icNextReadAddrIn = 32'h00004100;
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( !icReadHit[0] );
        assert( !icReadHit[1] );
        assert( !icReadHit[2] );
        assert( !icReadHit[3] );
        assert( icMiss );
        assert( icMissAddr == 32'h00004100 );
        assert( icVictimWayPtr == 1 );

        // Fill
        @(posedge clk);
        #HOLD;
        icFill = TRUE;
        icFillAddr = 32'h00004100;
        icFillData = 128'h00010001000100010001000100010001;
        icFillWayPtr = 1;
        @(posedge clk);
        #HOLD;
        icFill = FALSE;
        
        // Read 4100 (Cache Hit)
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( icReadHit[0] );
        assert( icReadHit[1] );
        assert( icReadHit[2] );
        assert( icReadHit[3] );
        assert( icReadDataOut[0] == 32'h00010001 );
        assert( icReadDataOut[1] == 32'h00010001 );
        assert( icReadDataOut[2] == 32'h00010001 );
        assert( icReadDataOut[3] == 32'h00010001 );
        assert( !icMiss );

        // Read 4200 (Cache Miss)
        @(posedge clk);
        #HOLD;
        icNextReadAddrIn = 32'h00004200;
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( !icReadHit[0] );
        assert( !icReadHit[1] );
        assert( !icReadHit[2] );
        assert( !icReadHit[3] );
        assert( icMiss );
        assert( icMissAddr == 32'h00004200 );
        assert( icVictimWayPtr == 0 );

        // Fill (Cache Miss)
        @(posedge clk);
        #HOLD;
        icFill = TRUE;
        icFillAddr = 32'h00004200;
        icFillData = 128'h00020002000200020002000200020002;
        icFillWayPtr = 0;
        @(posedge clk);
        #HOLD;
        icFill = FALSE;
        
        // Read 4200 (Cache Hit)
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( icReadHit[0] );
        assert( icReadHit[1] );
        assert( icReadHit[2] );
        assert( icReadHit[3] );
        assert( icReadDataOut[0] == 32'h00020002 );
        assert( icReadDataOut[1] == 32'h00020002 );
        assert( icReadDataOut[2] == 32'h00020002 );
        assert( icReadDataOut[3] == 32'h00020002 );
        assert( !icMiss );

        // Read 4000 (Cache Miss)
        @(posedge clk);
        #HOLD;
        icNextReadAddrIn = 32'h00004000;
        @(posedge clk);
        #HOLD;
        #WAIT;
        //assert( icFiller.phase == FILLER_PHASE_NONE );
        assert( !icReadHit[0] );
        assert( !icReadHit[1] );
        assert( !icReadHit[2] );
        assert( !icReadHit[3] );
        assert( icMiss );
        assert( icMissAddr == 32'h00004000 );
        assert( icVictimWayPtr == 1 );
        
        // Fill (Cache Miss)
        @(posedge clk);
        #HOLD;
        icFill = TRUE;
        icFillAddr = 32'h00004000;
        icFillData = 128'he3a01000e3a00000eafffffeea000000;
        icFillWayPtr = 1;
        @(posedge clk);
        #HOLD;
        icFill = FALSE;

        @(posedge clk);
        #HOLD;
        #WAIT;
        //assert( icFiller.phase == FILLER_PHASE_NONE );
        assert( icReadHit[0] );
        assert( icReadHit[1] );
        assert( icReadHit[2] );
        assert( icReadHit[3] );
        assert( icReadDataOut[0] == 32'hea000000 );
        assert( icReadDataOut[1] == 32'heafffffe );
        assert( icReadDataOut[2] == 32'he3a00000 );
        assert( icReadDataOut[3] == 32'he3a01000 );
        assert( !icMiss );

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        // Another line (2nd Read)
        @(posedge clk);
        #HOLD;
        icNextReadAddrIn = 32'h00004040;
        @(posedge clk);
        #HOLD;
        #WAIT;
        //assert( icFiller.phase == FILLER_PHASE_NONE );
        assert( icReadHit[0] );
        assert( icReadHit[1] );
        assert( icReadHit[2] );
        assert( icReadHit[3] );
        assert( icReadDataOut[0] == 32'he3a0e000 );
        assert( icReadDataOut[1] == 32'heb00017c );
        assert( icReadDataOut[2] == 32'heaffffed );
        assert( icReadDataOut[3] == 32'he3a00000 );
        assert( !icMiss );

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        $finish;
    end

endmodule
