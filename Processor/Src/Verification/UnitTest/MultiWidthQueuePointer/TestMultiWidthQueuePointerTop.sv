// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;

module TestMultiWidthQueuePointerTop #(
    SIZE = 8,
    INITIAL_HEAD_PTR = 0,
    INITIAL_TAIL_PTR = 0,
    INITIAL_COUNT = 0,
    PUSH_WIDTH = 2,
    POP_WIDTH = 2
)( 
input 
    logic clk_p,
    logic clk_n,
    logic rst,
    logic push,
    logic pop,
    logic [ $clog2(PUSH_WIDTH):0 ] pushCount,
    logic [ $clog2(POP_WIDTH):0 ] popCount,
output
    logic full,
    logic empty,
    logic [ $clog2(SIZE)-1:0 ] headPtr,
    logic [ $clog2(SIZE)-1:0 ] tailPtr,
    logic [ $clog2(SIZE):0 ] count
);
    
    logic clk;

    `ifdef RSD_SYNTHESIS
        SingleClock clkgen( clk_p, clk_n, clk );
    `else
        assign clk = clk_p;
    `endif
    
    MultiWidthQueuePointer #(
        .SIZE(SIZE),
        .INITIAL_HEAD_PTR(INITIAL_HEAD_PTR),
        .INITIAL_TAIL_PTR(INITIAL_TAIL_PTR),
        .INITIAL_COUNT(INITIAL_COUNT),
        .PUSH_WIDTH(PUSH_WIDTH),
        .POP_WIDTH(POP_WIDTH)
    ) queuePointer (
        .*
    );
    
endmodule
