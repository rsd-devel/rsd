// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;
import MemoryTypes::*;
import OpFormatTypes::*;

parameter STEP = 20;
parameter HOLD = 4;
parameter SETUP = 1;
parameter WAIT = STEP*2-HOLD-SETUP;

module TestDRAM_Controller;
    
    //
    // Clock and Reset
    //
    logic clk, rst, rstOut;
    TestBenchClockGenerator #( .STEP(STEP) ) clkgen (.*);
    logic txd, rxd;
    logic [7:0] ledOut;
    
    TestDRAM_ControllerTop top (
        .clk_p( clk ),
        .clk_n( ~clk ),
        .negResetIn( ~rst ),
        .posResetOut( rstOut ),
        .*
    );
    
    //
    // Test Data
    //
    initial begin
        
        // Wait during reset sequence
        #WAIT;
        @(negedge rstOut);
        
        for ( int i = 0; i < 10000; i++ ) begin
            @(posedge clk);
            #WAIT;
            $write( "%08b", ledOut );
        end
        
        $finish;
    end

endmodule
