// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;
import CacheSystemTypes::*;

parameter STEP = 10;
parameter HOLD = 3;
parameter SETUP = 2;
parameter WAIT = STEP*2-HOLD-SETUP;

module TestLRU_Counter;
    
    //
    // Clock and Reset
    //
    logic clk, rst;
    TestBenchClockGenerator #( .STEP(STEP) ) clkgen ( .rstOut(FALSE), .* );
    
    //
    // Top Module
    //
    parameter PORT_WIDTH = 2;
    
    logic [ PORT_WIDTH-1:0 ][ INDEX_BIT_WIDTH-1:0 ] index;
    logic [ PORT_WIDTH-1:0 ] access;
    logic [ PORT_WIDTH-1:0 ][ $clog2(WAY_NUM)-1:0 ] accessWay;
    logic [ PORT_WIDTH-1:0 ][ $clog2(WAY_NUM)-1:0 ] leastRecentlyAccessedWay;
    
    `ifdef RSD_POST_SYNTHESIS_SIMULATION
        TestLRU_CounterTop
            top(
                .clk_p ( clk ),
                .clk_n ( ~clk ),
                .*
            );
    `else
        TestLRU_CounterTop #( .PORT_WIDTH( PORT_WIDTH ) )
            top(
                .clk_p ( clk ),
                .clk_n ( ~clk ),
                .*
            );
    `endif
    
    //
    // Test Data
    //
    initial begin
        assert( WAY_NUM == 2 );
        assert( INDEX_BIT_WIDTH == 4 );
        
        // Initialize
        index[0] = '0;
        index[1] = '0;
        access[0] = FALSE;
        access[1] = FALSE;
        accessWay[0] = '0;
        accessWay[1] = '0;
        
        // Wait during reset sequence
        #WAIT;
        while(rst) @(posedge clk);

        //
        // Read/Write DCache
        //
        #HOLD;
        index[0] = 1;
        index[1] = 2;

        clkgen.WaitCycle(1);
        #HOLD;
        access[0] = TRUE;
        access[1] = TRUE;
        accessWay[0] = 0;
        accessWay[1] = 1;
        #WAIT;
        
        clkgen.WaitCycle(1);
        #HOLD;
        accessWay[0] = 1;
        accessWay[1] = 0;
        #WAIT;

        clkgen.WaitCycle(1);
        #HOLD;
        access[0] = FALSE;
        access[1] = FALSE;
        accessWay[0] = 0;
        accessWay[1] = 1;
        #WAIT;
        assert( leastRecentlyAccessedWay[0] == 0 );
        assert( leastRecentlyAccessedWay[1] == 1 );

        clkgen.WaitCycle(1);
        #HOLD;
        #WAIT;
        assert( leastRecentlyAccessedWay[0] == 0 );
        assert( leastRecentlyAccessedWay[1] == 1 );

        clkgen.WaitCycle(1);
        #HOLD;
        index[0] = 2;
        index[1] = 1;
        #WAIT;
        assert( leastRecentlyAccessedWay[0] == 1 );
        assert( leastRecentlyAccessedWay[1] == 0 );

        // Access the same line.
        #HOLD;
        index[0] = 3;
        index[1] = 3;
        
        clkgen.WaitCycle(1);
        #HOLD;
        access[0] = TRUE;
        access[1] = TRUE;
        accessWay[0] = 0;
        accessWay[1] = 0;
        #WAIT;

        clkgen.WaitCycle(1);
        #HOLD;
        access[0] = TRUE;
        access[1] = TRUE;
        accessWay[0] = 1;
        accessWay[1] = 1;
        #WAIT;

        clkgen.WaitCycle(1);
        #HOLD;
        access[0] = TRUE;
        access[1] = TRUE;
        accessWay[0] = 0;
        accessWay[1] = 0;
        #WAIT;
        assert( leastRecentlyAccessedWay[0] == 0 );
        assert( leastRecentlyAccessedWay[1] == 0 );

        clkgen.WaitCycle(1);
        #HOLD;
        access[0] = TRUE;
        access[1] = TRUE;
        accessWay[0] = 1;
        accessWay[1] = 1;
        #WAIT;
        assert( leastRecentlyAccessedWay[0] == 1 );
        assert( leastRecentlyAccessedWay[1] == 1 );

        $finish;
    end

endmodule
