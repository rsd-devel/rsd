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

module TestDCache;
    
    //
    // Clock and Reset
    //
    logic clk, rst, rstOut;
    TestBenchClockGenerator #( .STEP(STEP) ) clkgen (.*);
    
    //
    // Top Module
    //
    logic       [ MEM_ISSUE_WIDTH-1:0 ] dcRE;
    AddrPath    [ MEM_ISSUE_WIDTH-1:0 ] dcReadAddrIn;
    logic       dcWE;
    DataPath    dcWriteDataIn;
    AddrPath    dcWriteAddrIn;
    MemAccessSizeType dcWriteAccessSize;
    logic dcFillReq;
    logic dcFillerBusy;
    AddrPath dcFillAddr;
    WayPtr dcFillWayPtr;
    LineDataPath dcFillData;
    logic        [ MEM_ISSUE_WIDTH-1:0 ] dcReadHit;
    DataPath     [ MEM_ISSUE_WIDTH-1:0 ] dcReadDataOut;
    logic        dcWriteHit;
    logic        dcFillAck;
    logic        dcMiss, dcReplace;
    AddrPath     dcMissAddr, dcReplaceAddr;
    WayPtr       dcVictimWayPtr;
    LineDataPath dcReplaceData;
    
    TestDCacheTop top (
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
        assert( WAY_NUM == 2 );
        assert( LINE_WORD_WIDTH_BIT_SIZE == 2 );
        assert( INDEX_BIT_WIDTH == 4 );
        assert( DCACHE_PORT_WIDTH == 2 );
        assert( DCACHE_STORE_PORT_ID == 0 );
        assert( DCACHE_FILL_PORT_ID == 1 );
        
        // Initialize
        dcRE[0] = FALSE;
        dcRE[1] = FALSE;
        dcReadAddrIn[0] = '1;
        dcReadAddrIn[1] = '1;
        dcWE = FALSE;
        dcWriteDataIn = '1;
        dcWriteAddrIn = '1;
        dcWriteAccessSize = MEM_ACCESS_SIZE_WORD;
        dcFillReq = FALSE;
        dcFillerBusy = FALSE;
        dcFillAddr = '1;
        dcFillWayPtr = '1;
        dcFillData = '1;

        // Wait during reset sequence
        #WAIT;
        @(negedge rstOut);

        //
        // Read/Write DCache
        //
        
        // Cache Write (Miss)
        @(posedge clk);
        #HOLD;
        dcWE = TRUE;
        dcWriteAddrIn = 32'h00000000;
        dcWriteDataIn = 32'h01010101;
        #WAIT;
        assert( dcWriteHit == FALSE );
        assert( dcMiss == TRUE );
        assert( dcMissAddr == 32'h00000000 );
        assert( dcReplace == FALSE );
        assert( dcVictimWayPtr == 0 );

        // Fill (addr:0000)
        @(posedge clk);
        #HOLD;
        dcFillReq = TRUE;
        dcFillAddr = 32'h00000000;
        dcFillData = 128'h04040404_03030303_00000000_00000000;
        dcFillWayPtr = 0;
        #WAIT;
        assert( dcFillAck == TRUE );
        @(posedge clk);
        #HOLD;
        dcFillReq = FALSE;

        // Cache Write (Hit)
        @(posedge clk);
        #HOLD;
        dcWE = TRUE;
        dcWriteAddrIn = 32'h00000004;
        dcWriteDataIn = 32'h02020202;
        #WAIT;
        assert( dcWriteHit == TRUE );
        
        // Cache Read (Hit) - read written data (addr:0000,0004)
        @(posedge clk);
        #HOLD;
        dcWE = FALSE;
        dcFillReq = FALSE;
        dcRE[0] = TRUE;
        dcRE[1] = TRUE;
        dcReadAddrIn[0] = 32'h00000000;
        dcReadAddrIn[1] = 32'h00000004; // Same line
        #WAIT;
        assert( dcReadHit[0] == TRUE );
        assert( dcReadDataOut[0] == 32'h01010101 );
        assert( dcReadHit[1] == TRUE );
        assert( dcReadDataOut[1] == 32'h02020202 );

        // Cache Read (Hit) - read filled data (addr:0008,000c)
        @(posedge clk);
        #HOLD;
        dcWE = TRUE;
        dcFillReq = TRUE;
        dcRE[0] = TRUE;
        dcRE[1] = TRUE;
        dcReadAddrIn[0] = 32'h00000008;
        dcReadAddrIn[1] = 32'h0000000c; // Same line
        #WAIT;
        assert( dcWriteHit == FALSE );
        assert( dcFillAck == FALSE );
        assert( dcReadHit[0] == TRUE );
        assert( dcReadDataOut[0] == 32'h03030303 );
        assert( dcReadHit[1] == TRUE );
        assert( dcReadDataOut[1] == 32'h04040404 );

        // Cache Read (Miss) - prepare for replace (addr:1000)
        @(posedge clk);
        #HOLD;
        dcWE = FALSE;
        dcFillReq = FALSE;
        dcRE[0] = TRUE;
        dcRE[1] = FALSE;
        dcReadAddrIn[0] = 32'h00001000;
        #WAIT;
        assert( dcReadHit[0] == FALSE );
        assert( dcMiss == TRUE );
        assert( dcMissAddr == 32'h00001000 );
        assert( dcReplace == FALSE );
        assert( dcVictimWayPtr == 1 );

        // Fill (addr:1000)
        @(posedge clk);
        #HOLD;
        dcFillReq = TRUE;
        dcFillAddr = 32'h00001000;
        dcFillData = 128'h08080808_07070707_06060606_05050505;
        dcFillWayPtr = 1;
        #WAIT;
        assert( dcFillAck == TRUE );
        @(posedge clk);
        #HOLD;
        dcFillReq = FALSE;
        #WAIT;
        assert( dcReadHit[0] == TRUE );
        
        // Cache Read (Miss) - cause replace (addr:2000)
        @(posedge clk);
        #HOLD;
        dcWE = FALSE;
        dcFillReq = FALSE;
        dcRE[0] = TRUE;
        dcRE[1] = FALSE;
        dcReadAddrIn[0] = 32'h00002000;
        #WAIT;
        assert( dcReadHit[0] == FALSE );
        assert( dcMiss == TRUE );
        assert( dcMissAddr == 32'h00002000 );
        assert( dcReplace == TRUE );
        assert( dcReplaceAddr == 32'h00000000 );
        assert( dcReplaceData == 128'h04040404_03030303_02020202_01010101 );
        assert( dcVictimWayPtr == 0 );

        // Fill (addr:2000)
        @(posedge clk);
        #HOLD;
        dcFillReq = TRUE;
        dcFillAddr = 32'h00002000;
        dcFillData = 128'h0c0c0c0c_0b0b0b0b_0a0a0a0a_09090909;
        dcFillWayPtr = 1;
        #WAIT;
        assert( dcFillAck == TRUE );
        @(posedge clk);
        #HOLD;
        dcFillReq = FALSE;
        #WAIT;
        assert( dcReadHit[0] == TRUE );

        @(posedge clk);
        @(posedge clk);

        $finish;
    end

endmodule
