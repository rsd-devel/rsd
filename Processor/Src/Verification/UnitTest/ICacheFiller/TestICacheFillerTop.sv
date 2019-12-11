// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;
import CacheSystemTypes::*;
import OpFormatTypes::*;

module TestICacheFillerTop #(
    parameter INIT_HEX_FILE = "../../Src/Verification/TestCode/C/Dhrystone/code-100k.hex"
)(
    input
        logic clk_p, clk_n, rstTrigger,
    output
        logic rstOut,
    input
        logic icMiss,
        AddrPath icMissAddr,
        WayPtr icVictimWayPtr,
        MemAccessResult icMemAccessResult,
    output
        logic icFill,
        logic icFillerBusy,
        AddrPath icFillAddr,
        WayPtr icFillWayPtr,
        LineDataPath icFillData,
        MemReadAccessReq icMemAccessReq
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
    
    // interfaces
    CacheSystemIF cacheSystemIF( clk, rst, memCLK );
    
    // processor modules
    ICacheFiller iCacheFiller( cacheSystemIF );
    
    always_comb begin
        // Input of this module.
        cacheSystemIF.icMiss = icMiss;
        cacheSystemIF.icMissAddr = icMissAddr;
        cacheSystemIF.icVictimWayPtr = icVictimWayPtr;
        cacheSystemIF.icMemAccessResult = icMemAccessResult;
        
        // Output of this module.
        icFill = cacheSystemIF.icFill;
        icFillerBusy = cacheSystemIF.icFillerBusy;
        icFillAddr = cacheSystemIF.icFillAddr;
        icFillWayPtr = cacheSystemIF.icFillWayPtr;
        icFillData = cacheSystemIF.icFillData;
        icMemAccessReq = cacheSystemIF.icMemAccessReq;
    end
endmodule
