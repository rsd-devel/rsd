// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;

parameter STEP = 20;
parameter HOLD = 4; // When HOLD = 3ns, a X_RAMB18E1 causes hold time error!
parameter SETUP = 1;
parameter WAIT = STEP*2-HOLD-SETUP;

module TestBlockDualPortRAM;
    
    //
    // Clock and Reset
    //
    logic clk, rst;
    TestBenchClockGenerator #( .STEP(STEP) ) clkgen ( .rstOut(FALSE), .* );
    
    //
    // Modules for test
    //
    parameter INDEX_BIT_SIZE = 2;
    parameter ENTRY_BIT_SIZE = 4;
    
    parameter ENTRY_NUM = 1 << INDEX_BIT_SIZE;

    logic we;
    logic [ INDEX_BIT_SIZE-1:0 ] wa, ra;
    logic [ ENTRY_BIT_SIZE-1:0 ] wv, rv;
    
    `ifdef RSD_POST_SYNTHESIS_SIMULATION
        TestBlockDualPortRAM_Top top (
            .clk_p( clk ),
            .clk_n( ~clk ),
            .*
        );
    `else
        TestBlockDualPortRAM_Top #(
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
        @(posedge clk);

        // cycle 3
        #HOLD;
        we = FALSE;
        wa = 2;
        wv = 4'h9;
        ra = 1;
        #WAIT;
        assert( rv == 4'h3 ); // Result of read access in cycle 2
        
        @(posedge clk);

        // cycle 4
        #HOLD;
        we = TRUE;
        wa = 1;
        wv = 4'hc;
        ra = 2;
        #WAIT;
        assert( rv == 4'h3 ); // Result of read access in cycle 3
        
        @(posedge clk);

        // cycle 5
        #HOLD;
        we = TRUE;
        wa = 1;
        wv = 4'hf;
        ra = 1; // Check READ_FIRST mode is working.
        #WAIT;
        assert( rv == 4'h6 ); // Result of read access in cycle 4
        
        @(posedge clk);
        
        // cycle 6
        #HOLD;
        we = FALSE;
        ra = 1;
        #WAIT;
        assert( rv == 4'hc ); // Result of read access in cycle 5
        
        @(posedge clk);

        // cycle 7
        #HOLD;
        #WAIT;
        assert( rv == 4'hf ); // Result of read access in cycle 6
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        $finish;
    end

endmodule : TestBlockDualPortRAM
