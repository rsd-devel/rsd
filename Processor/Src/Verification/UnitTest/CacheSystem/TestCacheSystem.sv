// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;
import CacheSystemTypes::*;
import OpFormatTypes::*;

parameter STEP = 200;
parameter HOLD = 40;
parameter SETUP = 10;
parameter WAIT = STEP*2-HOLD-SETUP;

parameter CYCLE_MISS = 6;
parameter CYCLE_MISS_WITH_REPLACE = 10;

`ifdef RSD_POST_SYNTHESIS_SIMULATION
    `define ASSERT_FILLER_PHASE_NONE
    `define ASSERT_FILLER_PHASE_REPLACE
`else
    `define ASSERT_FILLER_PHASE_NONE assert( top.dCacheFiller.phase == FILLER_PHASE_NONE );
    `define ASSERT_FILLER_PHASE_REPLACE assert( top.dCacheFiller.phase == FILLER_PHASE_REPLACE );
`endif

module TestCacheSystem;
    
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
    logic       [ MEM_ISSUE_WIDTH-1:0 ] dcRE;
    AddrPath    [ MEM_ISSUE_WIDTH-1:0 ] dcReadAddrIn;
    logic       dcWE;
    DataPath    dcWriteDataIn;
    AddrPath    dcWriteAddrIn;
    MemAccessSizeType dcWriteAccessSize;
    logic       [ FETCH_WIDTH-1:0 ] icReadHit;
    DataPath    [ FETCH_WIDTH-1:0 ] icReadDataOut;
    logic       [ MEM_ISSUE_WIDTH-1:0 ] dcReadHit;
    DataPath    [ MEM_ISSUE_WIDTH-1:0 ] dcReadDataOut;
    logic       dcWriteHit;
    
    // Debug
    MemAccessResult dcMemAccessResult;
    logic dcFillReq, dcFillAck;
    logic dcMiss, dcReplace;
    logic dcFillerBusy;
    AddrPath dcFillAddr, dcMissAddr, dcReplaceAddr;
    WayPtr dcFillWayPtr, dcVictimWayPtr;
    LineDataPath dcFillData, dcReplaceData;

    `ifdef RSD_POST_SYNTHESIS_SIMULATION
        TestCacheSystemTop top (
            .clk_p( clk ),
            .clk_n( ~clk ),
            .rstOut( rstOut ),
            .rstTrigger( rst ),
            .*
        );
    `else
        TestCacheSystemTop #( .INIT_HEX_FILE( "../../TestCode/C/Dhrystone/code-100k.hex" ) )
            top(
                .clk_p ( clk ),
                .clk_n ( ~clk ),
                .rstOut( rstOut ),
                .rstTrigger( rst ),
                .*
            );
    `endif
    //
    // Test Data
    //
    initial begin
        assert( FETCH_WIDTH == 4 );
        assert( WAY_NUM == 2 );
        assert( LINE_WORD_WIDTH_BIT_SIZE == 2 );
        assert( INDEX_BIT_WIDTH == 4 );
        assert( DCACHE_PORT_WIDTH == 2 );
        assert( DCACHE_STORE_PORT_ID == 0 );
        assert( DCACHE_FILL_PORT_ID == 1 );
        
        // Initialize
        dcReadAddrIn[0] = '1;
        dcReadAddrIn[1] = '1;
        dcWriteAddrIn = '1;
        dcRE[0] = FALSE;
        dcRE[1] = FALSE;
        dcWE = FALSE;
        icRE = FALSE;
        icNextReadAddrIn = '1;
        dcWriteAccessSize = MEM_ACCESS_SIZE_WORD;

        // Wait during reset sequence
        #WAIT;
        @(negedge rstOut);

        //
        // Read/Write DCache
        //
        
        // 1st Read
        clkgen.WaitCycle(1);
        #HOLD;
        dcRE[0] = TRUE;
        dcReadAddrIn[0] = 32'h00000000;
        #WAIT;
        assert( !dcReadHit[0] );
        `ASSERT_FILLER_PHASE_NONE
        
        // 2nd Read (Cache Hit)
        clkgen.WaitCycle( CYCLE_MISS - 1 );
        #HOLD;
        dcRE[0] = TRUE;
        dcRE[1] = TRUE;
        dcReadAddrIn[0] = 32'h00000000;
        dcReadAddrIn[1] = 32'h00000004; // Same line
        #WAIT;
        assert( dcReadHit[0] );
        assert( dcReadHit[1] );
        `ASSERT_FILLER_PHASE_NONE

        // Another line
        clkgen.WaitCycle(1);
        #HOLD;
        dcRE[0] = TRUE;
        dcRE[1] = TRUE;
        dcReadAddrIn[0] = 32'h00000040;
        dcReadAddrIn[1] = 32'h00000008;
        #WAIT;
        assert( !dcReadHit[0] );
        assert( dcReadHit[1] );
        `ASSERT_FILLER_PHASE_NONE

        clkgen.WaitCycle( 1 );
        #HOLD;
        dcRE[0] = FALSE;
        dcRE[1] = FALSE;

        clkgen.WaitCycle( CYCLE_MISS - 1 );
        #HOLD;
        dcRE[0] = TRUE;
        dcReadAddrIn[0] = 32'h00000040;
        #WAIT;
        assert( dcReadHit[0] );

        // cause replace
        clkgen.WaitCycle(1);
        #HOLD;
        dcRE[0] = TRUE;
        dcReadAddrIn[0] = 32'h00000100;
        #WAIT;
        `ASSERT_FILLER_PHASE_NONE

        clkgen.WaitCycle( CYCLE_MISS );
        #HOLD;
        dcReadAddrIn[0] = 32'h00000200;
        #WAIT;
        `ASSERT_FILLER_PHASE_NONE

        clkgen.WaitCycle( CYCLE_MISS_WITH_REPLACE );
        #HOLD;
        dcReadAddrIn[0] = 32'h00000000;
        #WAIT;
        assert( !dcReadHit[0] );
        `ASSERT_FILLER_PHASE_NONE

        // Another line (2nd Read)
        clkgen.WaitCycle( CYCLE_MISS_WITH_REPLACE );
        #HOLD;
        dcRE[0] = TRUE;
        dcRE[1] = TRUE;
        dcReadAddrIn[0] = 32'h00000040;
        dcReadAddrIn[1] = 32'h00000000;
        #WAIT;
        assert( dcReadHit[0] );
        assert( dcReadHit[1] );
        `ASSERT_FILLER_PHASE_NONE

        // Cache Write (Hit)
        clkgen.WaitCycle( CYCLE_MISS );
        #HOLD;
        dcRE[0] = FALSE;
        dcRE[1] = FALSE;
        dcWE = TRUE;
        dcWriteAddrIn = 32'h00000000;
        dcWriteDataIn = 32'h01010101;
        #WAIT;
        assert( dcWriteHit );
        `ASSERT_FILLER_PHASE_NONE

        clkgen.WaitCycle(1);
        #HOLD;
        dcWriteAddrIn = 32'h00000004;
        dcWriteDataIn = 32'h02020202;
        dcRE[1] = TRUE;
        dcReadAddrIn[1] = 32'h00000000;
        #WAIT;
        assert( dcWriteHit );
        assert( dcReadHit[1] );
        assert( dcReadDataOut[1] == 32'h01010101 );
        assert( dcWriteHit );
        `ASSERT_FILLER_PHASE_NONE

        clkgen.WaitCycle(1);
        #HOLD;
        dcRE[1] = FALSE;
        dcWriteAddrIn = 32'h00000040;
        dcWriteDataIn = 32'h03030303;
        #WAIT;
        assert( dcWriteHit );
        `ASSERT_FILLER_PHASE_NONE
        
        // Cache Write (Miss)
        clkgen.WaitCycle(1);
        #HOLD;
        dcWriteAddrIn = 32'h00000100;
        dcWriteDataIn = 32'h04040404;
        #WAIT;
        assert( !dcWriteHit );
        `ASSERT_FILLER_PHASE_NONE

        clkgen.WaitCycle( CYCLE_MISS_WITH_REPLACE );
        #HOLD;
        dcWriteAddrIn = 32'h00000200;
        dcWriteDataIn = 32'h05050505;
        #WAIT;
        assert( !dcWriteHit );
        `ASSERT_FILLER_PHASE_NONE

        // Read written data
        clkgen.WaitCycle( CYCLE_MISS_WITH_REPLACE );
        #HOLD;
        dcWE = FALSE;
        dcRE[0] = TRUE;
        dcReadAddrIn[0] = 32'h00000000;
        #WAIT;
        assert( !dcReadHit[0] );
        `ASSERT_FILLER_PHASE_NONE

        clkgen.WaitCycle( CYCLE_MISS_WITH_REPLACE );
        #HOLD;
        dcRE[1] = TRUE;
        dcReadAddrIn[1] = 32'h00000004;
        #WAIT;
        assert( dcReadHit[0] );
        assert( dcReadHit[1] );
        assert( dcReadDataOut[0] == 32'h01010101 );
        assert( dcReadDataOut[1] == 32'h02020202 );
        `ASSERT_FILLER_PHASE_NONE

        clkgen.WaitCycle(1);
        #HOLD;
        dcReadAddrIn[0] = 32'h00000040;
        dcReadAddrIn[1] = 32'h00000100;
        #WAIT;
        assert( dcReadHit[0] );
        assert( !dcReadHit[1] );
        assert( dcReadDataOut[0] == 32'h03030303 );
        `ASSERT_FILLER_PHASE_NONE

        clkgen.WaitCycle(1);
        #HOLD;
        dcRE[0] = FALSE;
        dcRE[1] = FALSE;

        clkgen.WaitCycle( CYCLE_MISS_WITH_REPLACE );
        #HOLD;
        dcRE[0] = TRUE;
        dcReadAddrIn[0] = 32'h00000100;

        clkgen.WaitCycle(1);
        #HOLD;
        dcRE[0] = TRUE;
        dcRE[1] = TRUE;
        dcReadAddrIn[0] = 32'h00000200;
        dcReadAddrIn[1] = 32'h00000100;
        #WAIT;
        assert( !dcReadHit[0] );
        assert( dcReadHit[1] );
        assert( dcReadDataOut[1] == 32'h04040404 );
        `ASSERT_FILLER_PHASE_NONE
        
        clkgen.WaitCycle(1);
        #HOLD;
        dcRE[0] = FALSE;
        dcRE[1] = FALSE;

        clkgen.WaitCycle( CYCLE_MISS_WITH_REPLACE );
        #HOLD;
        dcRE[1] = TRUE;
        dcReadAddrIn[1] = 32'h00000200;
        #WAIT;
        assert( dcReadHit[1] );
        assert( dcReadDataOut[1] == 32'h05050505 );
        `ASSERT_FILLER_PHASE_NONE
        
        // hit under miss
        clkgen.WaitCycle(1);
        #HOLD;
        dcRE[0] = TRUE;
        dcRE[1] = FALSE;
        dcWE = FALSE;
        dcReadAddrIn[0] = 32'h00000000;
        #WAIT;
        assert( !dcReadHit[0] );
        `ASSERT_FILLER_PHASE_NONE

        clkgen.WaitCycle(1);
        #HOLD;
        dcReadAddrIn[0] = 32'h00000040;
        #WAIT;
        assert( dcReadHit[0] );
        assert( dcReadDataOut[0] == 32'h03030303 );
        `ASSERT_FILLER_PHASE_REPLACE

        clkgen.WaitCycle(1);
        #HOLD;
        dcRE[0] = FALSE;

        clkgen.WaitCycle( CYCLE_MISS_WITH_REPLACE );
        #HOLD;
        dcRE[0] = TRUE;
        dcReadAddrIn[0] = 32'h00000000;
        #WAIT;
        assert( dcReadHit[0] );
        assert( dcReadDataOut[0] == 32'h01010101 );
        `ASSERT_FILLER_PHASE_NONE

        clkgen.WaitCycle( CYCLE_MISS_WITH_REPLACE );
        #HOLD;
        dcRE[0] = FALSE;
        dcRE[1] = FALSE;
        dcWE = FALSE;
         
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
        assert( !icReadHit[0] );
        assert( !icReadHit[1] );
        assert( !icReadHit[2] );
        assert( !icReadHit[3] );
        
        clkgen.WaitCycle( CYCLE_MISS );

        // 2nd Read (Cache Hit)
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( icReadHit[0] );
        assert( icReadHit[1] );
        assert( icReadHit[2] );
        assert( icReadHit[3] );
        assert( icReadDataOut[0] == 32'hea000000 );
        assert( icReadDataOut[1] == 32'heafffffe );
        assert( icReadDataOut[2] == 32'he3a00000 );
        assert( icReadDataOut[3] == 32'he3a01000 );

        // Same line (Cache Hit)
        @(posedge clk);
        #HOLD;
        icNextReadAddrIn = 32'h00004004;
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( icReadHit[0] );
        assert( icReadHit[1] );
        assert( icReadHit[2] );
        assert( !icReadHit[3] );
        assert( icReadDataOut[0] == 32'heafffffe );
        assert( icReadDataOut[1] == 32'he3a00000 );
        assert( icReadDataOut[2] == 32'he3a01000 );

        // Another line (Cache Miss)
        @(posedge clk);
        #HOLD;
        icNextReadAddrIn = 32'h00004040;
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( !icReadHit[0] );
        assert( !icReadHit[1] );
        assert( !icReadHit[2] );
        assert( !icReadHit[3] );
        
        clkgen.WaitCycle( CYCLE_MISS );
        
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( icReadHit[0] );
        assert( icReadHit[1] );
        assert( icReadHit[2] );
        assert( icReadHit[3] );
        assert( icReadDataOut[0] == 32'he3a0e000 );
        assert( icReadDataOut[1] == 32'heb00017c );
        assert( icReadDataOut[2] == 32'heaffffed );
        assert( icReadDataOut[3] == 32'he3a00000 );
        
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

        clkgen.WaitCycle( CYCLE_MISS );
        
        // Read 4100 (Cache Hit)
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( icReadHit[0] );
        assert( icReadHit[1] );
        assert( icReadHit[2] );
        assert( icReadHit[3] );

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

        clkgen.WaitCycle( CYCLE_MISS );
        
        // Read 4200 (Cache Hit)
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( icReadHit[0] );
        assert( icReadHit[1] );
        assert( icReadHit[2] );
        assert( icReadHit[3] );

        // Read 4000 (Cache Miss)
        @(posedge clk);
        #HOLD;
        icNextReadAddrIn = 32'h00004000;
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( !icReadHit[0] );
        assert( !icReadHit[1] );
        assert( !icReadHit[2] );
        assert( !icReadHit[3] );
        
        clkgen.WaitCycle( CYCLE_MISS );

        #HOLD;
        #WAIT;
        assert( icReadHit[0] );
        assert( icReadHit[1] );
        assert( icReadHit[2] );
        assert( icReadHit[3] );
        assert( icReadDataOut[0] == 32'hea000000 );
        assert( icReadDataOut[1] == 32'heafffffe );
        assert( icReadDataOut[2] == 32'he3a00000 );
        assert( icReadDataOut[3] == 32'he3a01000 );

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
        assert( icReadHit[0] );
        assert( icReadHit[1] );
        assert( icReadHit[2] );
        assert( icReadHit[3] );
        assert( icReadDataOut[0] == 32'he3a0e000 );
        assert( icReadDataOut[1] == 32'heb00017c );
        assert( icReadDataOut[2] == 32'heaffffed );
        assert( icReadDataOut[3] == 32'he3a00000 );

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        //
        // Cause memory read access simultaneously
        //

        @(posedge clk);
        #HOLD;
        icNextReadAddrIn = 32'h00004020;
        @(posedge clk);
        #HOLD;
        icRE = TRUE;
        dcRE[0] = TRUE;
        dcRE[1] = FALSE;
        dcWE = FALSE;
        dcReadAddrIn[0] = 32'h00004030;
        #WAIT;
        assert( !icReadHit[0] );
        assert( !icReadHit[1] );
        assert( !icReadHit[2] );
        assert( !icReadHit[3] );
        assert( !dcReadHit[0] );

        clkgen.WaitCycle( CYCLE_MISS );
        
        #HOLD;
        #WAIT;
        assert( icReadHit[0] );
        assert( icReadHit[1] );
        assert( icReadHit[2] );
        assert( icReadHit[3] );
        assert( icReadDataOut[0] == 32'he3a06000 );
        assert( icReadDataOut[1] == 32'he3a07000 );
        assert( icReadDataOut[2] == 32'he3a08000 );
        assert( icReadDataOut[3] == 32'he3a09000 );

        clkgen.WaitCycle( CYCLE_MISS );
        
        #HOLD;
        #WAIT;
        assert( dcReadHit[0] );
        `ASSERT_FILLER_PHASE_NONE
        assert( dcReadDataOut[0] == 32'he3a0a000 );

        $finish;
    end

endmodule
