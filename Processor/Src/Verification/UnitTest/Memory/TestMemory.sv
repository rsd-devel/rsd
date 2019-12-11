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

module TestMemory;
    
    //
    // Clock and Reset
    //
    logic clk, rst, rstOut;
    TestBenchClockGenerator #( .STEP(STEP) ) clkgen (.*);
    
    //
    // Top Module
    //
    MemReadAccessReq icMemAccessReq;
    MemAccessReq dcMemAccessReq;
    MemAccessResult icMemAccessResult;
    MemAccessResult dcMemAccessResult;
    
    `ifdef RSD_POST_SYNTHESIS_SIMULATION
        TestMemoryTop top (
            .clk_p( clk ),
            .clk_n( ~clk ),
            .rstOut( rstOut ),
            .rstTrigger( rst ),
            .*
        );
    `else
        TestMemoryTop #( .INIT_HEX_FILE( "../../TestCode/C/Dhrystone/code-100k.hex" ) )
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
        
        // Initialize
        icMemAccessReq = '0;
        dcMemAccessReq = '0;

        // Wait during reset sequence
        #WAIT;
        @(negedge rstOut);
        
        // Read by ICache
        @(posedge clk);
        #HOLD;
        icMemAccessReq.valid = TRUE;
        icMemAccessReq.serial = 2;
        icMemAccessReq.addr = 32'h00004000;
        
        @(posedge clk);
        @(posedge clk);
        #HOLD;
        icMemAccessReq.valid = FALSE;
        #WAIT;
        assert( icMemAccessResult.valid == TRUE );
        assert( icMemAccessResult.serial == 2 );
        assert( icMemAccessResult.data == 128'he3a01000e3a00000eafffffeea000000 );
        assert( dcMemAccessResult.valid == FALSE );
        
        // Write by DCache
        @(posedge clk);
        #HOLD;
        dcMemAccessReq.valid = TRUE;
        dcMemAccessReq.we = TRUE;
        dcMemAccessReq.serial = 3;
        dcMemAccessReq.addr = 32'h00001000;
        dcMemAccessReq.data = 128'h12345678_12345678_12345678_12345678;
        
        @(posedge clk);
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( icMemAccessResult.valid == FALSE );
        assert( dcMemAccessResult.valid == TRUE );
        assert( dcMemAccessResult.serial == 3 );
        
        // Read by DCache
        @(posedge clk);
        #HOLD;
        dcMemAccessReq.valid = TRUE;
        dcMemAccessReq.we = FALSE;
        dcMemAccessReq.serial = 5;
        dcMemAccessReq.addr = 32'h00001000;
        dcMemAccessReq.data = '0;
        
        @(posedge clk);
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( icMemAccessResult.valid == FALSE );
        assert( dcMemAccessResult.valid == TRUE );
        assert( dcMemAccessResult.serial == 5 );
        assert( dcMemAccessResult.data == 128'h12345678_12345678_12345678_12345678 );
        
        // Read by ICache and DCache simultaneously
        @(posedge clk);
        #HOLD;
        icMemAccessReq.valid = TRUE;
        dcMemAccessReq.valid = TRUE;
        @(posedge clk);
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( icMemAccessResult.valid == TRUE );
        assert( dcMemAccessResult.valid == FALSE );
        
        
        $finish(0);
    end

endmodule
