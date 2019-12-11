// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;
import CacheSystemTypes::*;
import OpFormatTypes::*;

module TestICacheSystemTop #(
    parameter INIT_HEX_FILE = "../../Src/Verification/TestCode/C/Dhrystone/code-100k.hex"
)(
    input
        logic clk_p, clk_n, rstTrigger,
    output
        logic rstOut,
    input
        logic        icRE,
        AddrPath     icNextReadAddrIn,
        MemAccessReq dcMemAccessReq,
    output
        logic    [ FETCH_WIDTH-1:0 ] icReadHit,
        DataPath [ FETCH_WIDTH-1:0 ] icReadDataOut,
        MemAccessResult              dcMemAccessResult
    );

    // Clock and Reset
    logic clk, memCLK, rst, mmcmLocked;
    `ifdef RSD_SYNTHESIS
        MultiClock clkgen(
            .CLK_IN1_P(clk_p),
            .CLK_IN1_N(clk_n),
            .CLK_OUT1(clk),
            .CLK_OUT2(memCLK),
            .RESET(rstTrigger),
            .LOCKED(mmcmLocked)
        );
    `else
        assign clk = clk_p;
        initial memCLK <= FALSE;
        always_ff @ (posedge clk) memCLK <= ~memCLK;
    `endif
    
    ResetController rstController(.*);
    assign rstOut = rst;
    
    // signals
    AddrPath icReadAddrIn;

    // interfaces
    FetchStageIF ifStageIF( clk, rst );
    CacheSystemIF cacheSystemIF( clk, rst, memCLK );
    
    // processor modules
    ICache iCache( ifStageIF, cacheSystemIF );
    ICacheFiller iCacheFiller( cacheSystemIF );
    Memory #( .INIT_HEX_FILE(INIT_HEX_FILE) ) memory ( cacheSystemIF );
    
    always_comb begin
        // Input of this module.
        ifStageIF.icRE = icRE;
        ifStageIF.icReadAddrIn = icReadAddrIn;
        ifStageIF.icNextReadAddrIn = icNextReadAddrIn;
        cacheSystemIF.dcMemAccessReq = dcMemAccessReq;
        
        // Output of this module.
        for ( int i = 0; i < FETCH_WIDTH; i++ ) begin
            icReadHit[i] = ifStageIF.icReadHit[i];
            icReadDataOut[i] = ifStageIF.icReadDataOut[i];
        end
        dcMemAccessResult = cacheSystemIF.dcMemAccessResult;
    end
    
    always_ff @(posedge clk) begin
        icReadAddrIn <= icNextReadAddrIn;
    end
endmodule
