// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;

parameter STEP = 10;
parameter HOLD = 2;

module TestDistributedDualPortRAM;
    
    //
    // Clock and Reset
    //
    logic clk, rst;
    TestBenchClockGenerator #( .STEP(STEP) ) clkgen ( .rstOut(FALSE), .* );
    
    //
    // Modules for test
    //
    parameter ENTRY_NUM = 4;
    parameter INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    parameter ENTRY_BIT_SIZE = 4;

    logic we;
    logic [ INDEX_BIT_SIZE-1:0 ] wa, ra;
    logic [ ENTRY_BIT_SIZE-1:0 ] wv, rv;
    
    `ifdef RSD_POST_SYNTHESIS_SIMULATION
        TestDistributedDualPortRAM_Top top (
            .clk_p( clk ),
            .clk_n( ~clk ),
            .*
        );
    `else
        TestDistributedDualPortRAM_Top #(
            .ENTRY_NUM(ENTRY_NUM),
            .ENTRY_BIT_SIZE(ENTRY_BIT_SIZE)
        ) top (
            .clk_p( clk ),
            .clk_n( ~clk ),
            .*
        );
    `endif
    
    //
    // Test data
    //
    initial begin
        // Initialize logic
        we = FALSE;
        wa = 0;
        ra = 0;
        wv = 0;
        
        // Wait during reset sequence
        #STEP;
        while(rst) @(posedge clk);
        
        // cycle 1
        #HOLD;
        we = TRUE;
        wa = 1;
        wv = 4'h3;
        @(posedge clk);
        
        // cycle 2
        #HOLD;
        we = TRUE;
        wa = 2;
        wv = 4'h6;
        ra = 1;
        #STEP; assert( rv == 4'h3 );
        
        @(posedge clk);

        // cycle 3
        #HOLD;
        we = FALSE;
        wa = 2;
        wv = 4'h9;
        ra = 1;
        #STEP; assert( rv == 4'h3 );
        
        @(posedge clk);

        // cycle 4
        #HOLD;
        we = TRUE;
        wa = 2;
        wv = 4'hc;
        ra = 2;
        #STEP; assert( rv == 4'h6 );
        
        @(posedge clk);

        // cycle 5
        #HOLD;
        we = FALSE;
        ra = 2;
        #STEP; assert( rv == 4'hc );
        
        @(posedge clk);

        $finish;
    end

endmodule : TestDistributedDualPortRAM
