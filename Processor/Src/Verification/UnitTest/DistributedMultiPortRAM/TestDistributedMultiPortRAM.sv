// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;

parameter STEP = 10;
parameter HOLD = 2;

module TestDistributedMultiPortRAM;

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
    parameter READ_NUM = 2;
    parameter WRITE_NUM = 2;
    
    logic we [ WRITE_NUM ];
    logic [ INDEX_BIT_SIZE-1:0 ] wa [ WRITE_NUM ];
    logic [ ENTRY_BIT_SIZE-1:0 ] wv [ WRITE_NUM ];
    logic [ INDEX_BIT_SIZE-1:0 ] ra [ READ_NUM ];
    logic [ ENTRY_BIT_SIZE-1:0 ] rv [ READ_NUM ];
    
    `ifdef RSD_POST_SYNTHESIS_SIMULATION
        logic [ WRITE_NUM-1:0 ] packedWE;
        logic [ WRITE_NUM-1:0 ] [ INDEX_BIT_SIZE-1:0 ] packedWA;
        logic [ WRITE_NUM-1:0 ] [ ENTRY_BIT_SIZE-1:0 ] packedWV;
        logic [ READ_NUM-1:0 ] [ INDEX_BIT_SIZE-1:0 ] packedRA;
        logic [ READ_NUM-1:0 ] [ ENTRY_BIT_SIZE-1:0 ] packedRV;
        
        TestDistributedMultiPortRAM_Top top (
            .clk_p( clk ),
            .clk_n( ~clk ),
            .we( packedWE ),
            .wa( packedWA ),
            .wv( packedWV ),
            .ra( packedRA ),
            .rv( packedRV )
        );
        
        always_comb begin
            for ( int i = 0; i < WRITE_NUM; i++ ) begin
                packedWE[i] = we[i];
                packedWA[i] = wa[i];
                packedWV[i] = wv[i];
            end
            for ( int i = 0; i < READ_NUM; i++ ) begin
                packedRA[i] = ra[i];
                rv[i] = packedRV[i];
            end
        end
    `else
        TestDistributedMultiPortRAM_Top #(
            .ENTRY_NUM(ENTRY_NUM),
            .ENTRY_BIT_SIZE(ENTRY_BIT_SIZE),
            .READ_NUM(READ_NUM),
            .WRITE_NUM(WRITE_NUM)
        ) top (
            .clk_p( clk ),
            .clk_n( ~clk ),
            .we( we ),
            .*
        );
    `endif
    
    
    //
    // Test data
    //
    initial begin
        // Initialize logic
        we[0] = FALSE;
        we[1] = FALSE;
        wa[0] = 0;
        wa[1] = 0;
        wv[0] = 0;
        wv[1] = 0;
        ra[0] = 0;
        ra[1] = 0;
        
        // Wait during reset sequence
        #STEP;
        while(rst) @(posedge clk);
        
        // cycle 1
        #HOLD;
        we[0] = TRUE;
        wa[0] = 1;
        wv[0] = 4'h1;
        we[1] = TRUE;
        wa[1] = 2;
        wv[1] = 4'h2;
        @(posedge clk);
        
        // cycle 2
        #HOLD;
        we[0] = TRUE;
        wa[0] = 2;
        wv[0] = 4'h3;
        we[1] = FALSE;
        wa[1] = 2;
        wv[1] = 4'h4;

        ra[0] = 1;
        ra[1] = 2;
        #STEP;
        assert( rv[0] == 4'h1 );
        assert( rv[1] == 4'h2 );
        
        @(posedge clk);

        // cycle 3
        #HOLD;
        we[0] = FALSE;
        wa[0] = 2;
        wv[0] = 4'h5;
        we[1] = FALSE;
        wa[1] = 2;
        wv[1] = 4'h6;

        ra[0] = 2;
        ra[1] = 1;
        #STEP;
        assert( rv[0] == 4'h3 );
        assert( rv[1] == 4'h1 );
        
        @(posedge clk);

        // cycle 4
        #HOLD;
        we[0] = TRUE;
        wa[0] = 2;
        wv[0] = 4'h7;
        we[1] = TRUE;
        wa[1] = 3;
        wv[1] = 4'h8;

        ra[0] = 2;
        ra[1] = 2;
        #STEP;
        assert( rv[0] == 4'h3 );
        assert( rv[1] == 4'h3 );
        
        @(posedge clk);

        // cycle 5
        #HOLD;
        we[0] = FALSE;
        we[1] = FALSE;

        ra[0] = 2;
        ra[1] = 3;
        #STEP;
        assert( rv[0] == 4'h7 );
        assert( rv[1] == 4'h8 );
        
        @(posedge clk);

        $finish;
    end

endmodule : TestDistributedMultiPortRAM
