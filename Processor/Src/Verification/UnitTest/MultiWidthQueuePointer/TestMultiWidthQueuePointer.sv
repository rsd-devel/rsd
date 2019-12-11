// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps
import BasicTypes::*;

parameter STEP = 20;
parameter HOLD = 4;
parameter SETUP = 1;
parameter WAIT = STEP*2-HOLD-SETUP;

module TestMultiWidthQueuePointer;
    //
    // Clock and Reset
    //
    logic clk, rst;
    TestBenchClockGenerator #( .STEP(STEP) ) clkgen ( .rstOut(FALSE), .* );
    
    //
    // Top Module
    //

    parameter SIZE = 8;
    parameter INDEX_BIT_WIDTH = $clog2( SIZE );
    parameter DELTA_WIDTH = 2;
    parameter WIDTH_BIT_WIDTH = $clog2( DELTA_WIDTH );
    
    typedef logic [INDEX_BIT_WIDTH-1:0] IndexPath;
    typedef logic [INDEX_BIT_WIDTH:0] CountPath;
    typedef logic [WIDTH_BIT_WIDTH:0] WidthPath;

    logic push;
    logic pop;
    logic full;
    logic empty;
    IndexPath headPtr;
    IndexPath tailPtr;
    WidthPath pushCount;
    WidthPath popCount;
    CountPath count;
    
    TestMultiWidthQueuePointerTop top(
        .clk_p( clk ),
        .clk_n( ~clk ),
        .*
    );

    initial begin
        `ifndef RSD_POST_SYNTHESIS_SIMULATION
            assert( top.SIZE == 8 );
            assert( top.PUSH_WIDTH == 2 );
            assert( top.POP_WIDTH == 2 );
        `endif
        
        push = 0;
        pop = 0;
        pushCount = 0;
        popCount = 0;
        
        // Wait during reset sequence
        #WAIT;
        while(rst) @(posedge clk);
        $display( "========== Test Start ==========" );
        
        #HOLD;
        push = TRUE;
        pushCount = 2;
        #WAIT;
        assert( count == 0 );
        assert( !full );
        @(posedge clk);

        #HOLD;
        #WAIT;
        assert( count == 2 );
        assert( !full );
        @(posedge clk);

        #HOLD;
        #WAIT;
        assert( count == 4 );
        assert( !full );
        @(posedge clk);

        #HOLD;
        #WAIT;
        assert( count == 6 );
        assert( !full );
        @(posedge clk);

        #HOLD;
        push = FALSE;
        #WAIT;
        assert( count == 8 );
        assert( full );
        @(posedge clk);


        #HOLD;
        pop = TRUE;
        popCount = 1;
        #WAIT;
        assert( count == 8 );
        assert( full );
        @(posedge clk);

        #HOLD;
        pop = TRUE;
        popCount = 2;
        #WAIT;
        assert( count == 7 );
        assert( full );
        @(posedge clk);

        #HOLD;
        pop = TRUE;
        popCount = 2;
        push = TRUE;
        pushCount = 1;
        #WAIT;
        assert( count == 5 );
        assert( !full );
        @(posedge clk);

        #HOLD;
        pop = TRUE;
        popCount = 1;
        push = TRUE;
        pushCount = 2;
        #WAIT;
        assert( count == 4 );
        assert( !full );
        @(posedge clk);

        #HOLD;
        pop = FALSE;
        push = FALSE;
        #WAIT;
        assert( count == 5 );
        assert( !full );
        @(posedge clk);

        $display( "==========  Test End  ==========" );
        $finish(0);
    end

endmodule

