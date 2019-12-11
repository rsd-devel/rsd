// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;

parameter STEP = 10;

module TestInitializedBlockRAM_Top #(
    parameter ENTRY_NUM = 128, 
    parameter ENTRY_BIT_SIZE = 64,
    parameter INIT_HEX_FILE = "code.hex"
)(
`ifdef RSD_SYNTHESIS_VIVADO
input
    logic clk, 
    logic rst, 

input
    logic ibit,
output
    logic obit
`else
input
    logic clk_p, clk_n,
    logic we,
    logic [ $clog2(ENTRY_NUM)-1:0 ] ra, wa,
    logic [ ENTRY_BIT_SIZE-1:0 ] wv,
output
    logic [ ENTRY_BIT_SIZE-1:0 ] rv
`endif
    

);
    parameter INDEX_BIT_SIZE = $clog2(ENTRY_NUM);

    `ifdef RSD_SYNTHESIS_VIVADO
        localparam INPUT_BIT_SIZE = 1+2*INDEX_BIT_SIZE+ENTRY_BIT_SIZE;

        logic [ INPUT_BIT_SIZE-1:0 ] ishift;
        logic [ ENTRY_BIT_SIZE-1:0 ] rvreg;
        logic we;
        logic [ INDEX_BIT_SIZE-1:0 ] ra, wa;
        logic [ ENTRY_BIT_SIZE-1:0 ] wv;
        logic [ ENTRY_BIT_SIZE-1:0 ] rv;


        always_ff @(posedge clk) begin
            if(rst) begin
                {ishift, rvreg, we, ra, wa, wv} <= 0;
            end else begin
                ishift   <= {ishift[0 +: INPUT_BIT_SIZE-1], ibit};
                rvreg <= rv;
                we <= ishift[ 0 +: 1 ];
                ra <= ishift[ 1 +: INDEX_BIT_SIZE ];
                wa <= ishift[ INDEX_BIT_SIZE+1 +: INDEX_BIT_SIZE ];
                wv <= ishift[ 2*INDEX_BIT_SIZE+1 +: ENTRY_BIT_SIZE ];
            end
        end

        always_comb begin
            obit = ^{rvreg};
        end
    `else
        logic clk;
        `ifdef RSD_SYNTHESIS
            SingleClock clkgen( clk_p, clk_n, clk );
        `else
            assign clk = clk_p;
        `endif
    `endif

    InitializedBlockRAM #( 
        .ENTRY_NUM( ENTRY_NUM ),
        .ENTRY_BIT_SIZE( ENTRY_BIT_SIZE ),
        .INIT_HEX_FILE( INIT_HEX_FILE )
    ) blockRAM (
        .clk( clk ),
        .*
    );

endmodule
