// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;

parameter STEP = 10;

module TestBlockTrueDualPortRAM_Top #(
    parameter ENTRY_NUM = 16, 
    parameter ENTRY_BIT_SIZE = 1,
    parameter PORT_NUM  = 2 // Do NOT change this parameter to synthesize True Dual Port RAM
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
    logic we[PORT_NUM],
    logic [ $clog2(ENTRY_NUM)-1:0 ] rwa[PORT_NUM],
    logic [ ENTRY_BIT_SIZE-1:0 ] wv[PORT_NUM],
output
    logic [ ENTRY_BIT_SIZE-1:0 ] rv[PORT_NUM]
`endif
    

);

    parameter INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    `ifdef RSD_SYNTHESIS_VIVADO
        localparam INPUT_BIT_SIZE = PORT_NUM+
                                    INDEX_BIT_SIZE*PORT_NUM+
                                    ENTRY_BIT_SIZE*PORT_NUM;

        logic [ INPUT_BIT_SIZE-1:0 ] ishift;
        logic [ ENTRY_BIT_SIZE-1:0 ] rvreg[PORT_NUM];
        logic we[PORT_NUM];
        logic [ INDEX_BIT_SIZE-1:0 ] rwa[PORT_NUM];
        logic [ ENTRY_BIT_SIZE-1:0 ] wv[PORT_NUM];
        logic [ ENTRY_BIT_SIZE-1:0 ] rv[PORT_NUM];
        logic [ PORT_NUM-1:0 ] obit0;


        always_ff @(posedge clk) begin
            if(rst) begin
                ishift <= 0;
                for ( int i = 0; i < PORT_NUM; i++ ) begin
                    rvreg[i] <= 0;
                    we[i]    <= 0;
                    rwa[i]   <= 0;
                    wv[i]    <= 0;
                end
            end else begin
                ishift   <= {ishift[0 +: INPUT_BIT_SIZE-1], ibit};
                for ( int i = 0; i < PORT_NUM; i++ ) begin
                    rvreg[i] <= rv[i];
                    we[i]    <= ishift[ i +: 1 ];
                    rwa[i]   <= ishift[ i*INDEX_BIT_SIZE+PORT_NUM +: INDEX_BIT_SIZE ];
                    wv[i]    <= ishift[ i*ENTRY_BIT_SIZE+PORT_NUM*INDEX_BIT_SIZE+PORT_NUM +: ENTRY_BIT_SIZE ];
                end
            end
        end

        always_comb begin
            for ( int i = 0; i < PORT_NUM; i++ ) begin
                obit0[i] = ^{rvreg[i]};
            end
            obit = ^{obit0};
        end
    `else
        logic clk;
        `ifdef RSD_SYNTHESIS
            SingleClock clkgen( clk_p, clk_n, clk );
        `else
            assign clk = clk_p;
        `endif
    `endif

    BlockTrueDualPortRAM #( 
        .ENTRY_NUM( ENTRY_NUM ),
        .ENTRY_BIT_SIZE( ENTRY_BIT_SIZE ),
        .PORT_NUM(PORT_NUM)
    ) blockRAM (
        .clk( clk ),
        .*
    );

endmodule
