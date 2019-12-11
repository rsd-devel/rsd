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

parameter CYCLE_MISS = 6;

module TestICacheSystem;
    
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
    MemAccessReq    dcMemAccessReq;
    MemAccessResult dcMemAccessResult;
    
    `ifdef RSD_POST_SYNTHESIS_SIMULATION
        TestICacheSystemTop top (
            .clk_p( clk ),
            .clk_n( ~clk ),
            .rstOut( rstOut ),
            .rstTrigger( rst ),
            .*
        );
    `else
        TestICacheSystemTop #( .INIT_HEX_FILE( "../../TestCode/C/Dhrystone/code-100k.hex" ) )
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
        
        // Initialize
        icRE = FALSE;
        icNextReadAddrIn = '0;
        dcMemAccessReq = '0;

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

        $finish(0);
    end

endmodule
