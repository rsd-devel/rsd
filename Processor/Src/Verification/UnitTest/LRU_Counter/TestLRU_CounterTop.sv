// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;
import CacheSystemTypes::*;

module TestLRU_CounterTop #(
    parameter PORT_WIDTH = 2
)(
input
    logic clk_p, clk_n, rst,
    logic [ PORT_WIDTH-1:0 ][ INDEX_BIT_WIDTH-1:0 ] index,
    logic [ PORT_WIDTH-1:0 ] access,
    logic [ PORT_WIDTH-1:0 ][ $clog2(WAY_NUM)-1:0 ] accessWay,
output
    logic [ PORT_WIDTH-1:0 ][ $clog2(WAY_NUM)-1:0 ] leastRecentlyAccessedWay
);
    
    logic clk;

    logic [ INDEX_BIT_WIDTH-1:0 ] unpackedIndex [ PORT_WIDTH ];
    logic unpackedAccess [ PORT_WIDTH ];
    logic [ $clog2(WAY_NUM)-1:0 ] unpackedAccessWay [ PORT_WIDTH ];
    logic [ $clog2(WAY_NUM)-1:0 ] unpackedLeastRecentlyAccessedWay [ PORT_WIDTH ];

    `ifdef RSD_SYNTHESIS
        SingleClock clkgen( clk_p, clk_n, clk );
    `else
        assign clk = clk_p;
    `endif
    
    LRU_Counter #(
        .WAY_NUM( WAY_NUM ),
        .INDEX_BIT_WIDTH( INDEX_BIT_WIDTH ),
        .PORT_WIDTH( PORT_WIDTH )
    ) lruCounter (
        .index( unpackedIndex ),
        .access( unpackedAccess ),
        .accessWay( unpackedAccessWay ),
        .leastRecentlyAccessedWay( unpackedLeastRecentlyAccessedWay ),
        .*
    );
    
    always_comb begin
        for ( int i = 0; i < PORT_WIDTH; i++ ) begin
            unpackedIndex[i] = index[i];
            unpackedAccess[i] = access[i];
            unpackedAccessWay[i] = accessWay[i];
            leastRecentlyAccessedWay[i] = unpackedLeastRecentlyAccessedWay[i];
        end
    end
    
endmodule
