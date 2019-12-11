// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;

module TestRegisterFileTop (
input
    logic clk_p, clk_n, rst,
    
    PRegNumPath [ INT_ISSUE_WIDTH-1:0 ] intSrcRegNumA ,
    PRegNumPath [ INT_ISSUE_WIDTH-1:0 ] intSrcRegNumB,
    PRegNumPath [ INT_ISSUE_WIDTH-1:0 ] intSrcFlagNum,
    
    logic [ INT_ISSUE_WIDTH-1:0 ] intDstRegWE,
    logic [ INT_ISSUE_WIDTH-1:0 ] intDstFlagWE,

    PRegNumPath [ INT_ISSUE_WIDTH-1:0 ] intDstRegNum ,
    PRegNumPath [ INT_ISSUE_WIDTH-1:0 ] intDstFlagNum,
    
    DataPath [ INT_ISSUE_WIDTH-1:0 ] intDstRegData,
    FlagPath [ INT_ISSUE_WIDTH-1:0 ] intDstFlagData,
    
    PRegNumPath [ MEM_ISSUE_WIDTH-1:0 ] memSrcRegNumA,
    PRegNumPath [ MEM_ISSUE_WIDTH-1:0 ] memSrcRegNumB,
    PRegNumPath [ MEM_ISSUE_WIDTH-1:0 ] memSrcFlagNum,
    
    logic [ MEM_ISSUE_WIDTH-1:0 ] memDstRegWE ,
    logic [ MEM_ISSUE_WIDTH-1:0 ] memDstFlagWE,

    PRegNumPath [ MEM_ISSUE_WIDTH-1:0 ] memDstRegNum ,
    PRegNumPath [ MEM_ISSUE_WIDTH-1:0 ] memDstFlagNum,
    
    DataPath [ MEM_ISSUE_WIDTH-1:0 ] memDstRegData ,
    FlagPath [ MEM_ISSUE_WIDTH-1:0 ] memDstFlagData,

output
    DataPath [ INT_ISSUE_WIDTH-1:0 ] intSrcRegDataA,
    DataPath [ INT_ISSUE_WIDTH-1:0 ] intSrcRegDataB,
    FlagPath [ INT_ISSUE_WIDTH-1:0 ] intSrcFlagData,

    DataPath [ MEM_ISSUE_WIDTH-1:0 ] memSrcRegDataA,
    DataPath [ MEM_ISSUE_WIDTH-1:0 ] memSrcRegDataB,
    FlagPath [ MEM_ISSUE_WIDTH-1:0 ] memSrcFlagData
);
    logic clk;
    
    `ifdef RSD_SYNTHESIS
        SingleClock clkgen( clk_p, clk_n, clk );
    `else
        assign clk = clk_p;
    `endif
    
    RegisterFileIF rfIF( clk , rst );
    RegisterFile registerFile( rfIF );
    
    always_comb begin
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            rfIF.intSrcRegNumA[i]  = intSrcRegNumA[i];
            rfIF.intSrcRegNumB[i]  = intSrcRegNumB[i];
            rfIF.intSrcFlagNum[i]  = intSrcFlagNum[i];
            rfIF.intDstRegWE[i]    = intDstRegWE[i];
            rfIF.intDstFlagWE[i]   = intDstFlagWE[i];
            rfIF.intDstRegNum[i]   = intDstRegNum[i];
            rfIF.intDstRegData[i]  = intDstRegData[i];
            rfIF.intDstFlagNum[i]  = intDstFlagNum[i];
            rfIF.intDstFlagData[i] = intDstFlagData[i];
        end
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            rfIF.memSrcRegNumA[i]  = memSrcRegNumA[i];
            rfIF.memSrcRegNumB[i]  = memSrcRegNumB[i];
            rfIF.memSrcFlagNum[i]  = memSrcFlagNum[i];
            rfIF.memDstRegWE[i]    = memDstRegWE[i];
            rfIF.memDstFlagWE[i]   = memDstFlagWE[i];
            rfIF.memDstRegNum[i]   = memDstRegNum[i];
            rfIF.memDstRegData[i]  = memDstRegData[i];
            rfIF.memDstFlagNum[i]  = memDstFlagNum[i];
            rfIF.memDstFlagData[i] = memDstFlagData[i];
        end
    end
    
    always_ff @ (posedge clk) begin
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            intSrcRegDataA[i] <= rfIF.intSrcRegDataA[i];
            intSrcRegDataB[i] <= rfIF.intSrcRegDataB[i];
            intSrcFlagData[i] <= rfIF.intSrcFlagData[i];
        end
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            memSrcRegDataA[i] <= rfIF.memSrcRegDataA[i];
            memSrcRegDataB[i] <= rfIF.memSrcRegDataB[i];
            memSrcFlagData[i] <= rfIF.memSrcFlagData[i];
        end
    end
endmodule
