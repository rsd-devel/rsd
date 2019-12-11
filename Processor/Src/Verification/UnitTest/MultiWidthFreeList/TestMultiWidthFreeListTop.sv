// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;

module TestMultiWidthFreeListTop #(
    SIZE = 8,
    PUSH_WIDTH = 2,
    POP_WIDTH = 2,
    ENTRY_WIDTH = $clog2(SIZE)
)( 
input
    logic clk_p,
    logic clk_n,
    logic rst,
    logic [ PUSH_WIDTH-1:0 ] push,
    logic [ POP_WIDTH-1:0 ] pop,
    logic [ PUSH_WIDTH-1:0 ][ ENTRY_WIDTH-1:0 ] pushedData,
output
    logic full,
    logic empty,
    logic [ POP_WIDTH-1:0 ][ ENTRY_WIDTH-1:0 ] poppedData
);
    
    logic clk;
    logic [ $clog2(SIZE):0 ] count;
    logic unpackedPush [ PUSH_WIDTH ];
    logic unpackedPop [ POP_WIDTH ];
    logic [ ENTRY_WIDTH-1:0 ] unpackedPushedData [ PUSH_WIDTH ];
    logic [ ENTRY_WIDTH-1:0 ] unpackedPoppedData [ POP_WIDTH ];

    `ifdef RSD_SYNTHESIS
        TED_ClockGenerator clkgen( clk_p, clk_n, clk );
    `else
        assign clk = clk_p;
    `endif
    
    MultiWidthFreeList #(
        .INDEX_BIT_SIZE( $clog2(SIZE) ),
        .PUSH_WIDTH( PUSH_WIDTH ),
        .POP_WIDTH( POP_WIDTH ),
        .ENTRY_BIT_SIZE( ENTRY_WIDTH )
    ) freeList (
        .push(unpackedPush),
        .pop(unpackedPop),
        .pushedData(unpackedPushedData),
        .poppedData(unpackedPoppedData),
        .*
    );
    
    always_comb begin
        for ( int i = 0; i < PUSH_WIDTH; i++ ) begin
            unpackedPush[i] = push[i];
            unpackedPushedData[i] = pushedData[i];
        end
        for ( int i = 0; i < POP_WIDTH; i++ ) begin
            unpackedPop[i] = pop[i];
            poppedData[i] = unpackedPoppedData[i];
        end
    end
    
endmodule
