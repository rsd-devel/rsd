// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;

parameter STEP = 10;

module TestBlockMultiPortRAM_Top #(
    parameter ENTRY_NUM = 4,
    parameter ENTRY_BIT_SIZE = 4,
    parameter READ_NUM = 2,
    parameter WRITE_NUM = 2
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
    logic we [ WRITE_NUM ],
    logic [ $clog2(ENTRY_NUM)-1:0 ] wa [ WRITE_NUM ],
    logic [ ENTRY_BIT_SIZE-1:0 ] wv [ WRITE_NUM ],
    logic [ $clog2(ENTRY_NUM)-1:0 ] ra [ READ_NUM ],
output
    logic [ ENTRY_BIT_SIZE-1:0 ] rv [ READ_NUM ]
`endif
);

    parameter INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    `ifdef RSD_SYNTHESIS_VIVADO
        localparam INPUT_BIT_SIZE = WRITE_NUM+
                                    INDEX_BIT_SIZE*WRITE_NUM+
                                    ENTRY_BIT_SIZE*WRITE_NUM+
                                    INDEX_BIT_SIZE*READ_NUM;

        logic [ INPUT_BIT_SIZE-1:0 ] ishift;
        logic [ ENTRY_BIT_SIZE-1:0 ] rvreg [ READ_NUM ];
        logic we [ WRITE_NUM ];
        logic [ INDEX_BIT_SIZE-1:0 ] wa [ WRITE_NUM ];
        logic [ ENTRY_BIT_SIZE-1:0 ] wv [ WRITE_NUM ];
        logic [ INDEX_BIT_SIZE-1:0 ] ra [ READ_NUM ];
        logic [ ENTRY_BIT_SIZE-1:0 ] rv [ READ_NUM ];
        logic [ READ_NUM-1:0 ] obit0;


        always_ff @(posedge clk) begin
            if(rst) begin
                ishift <= 0;
                for ( int i = 0; i < READ_NUM; i++ ) begin
                    rvreg[i] <= 0;
                    ra[i]    <= 0;
                end
                for ( int i = 0; i < WRITE_NUM; i++ ) begin
                    we[i]    <= 0;
                    wa[i]    <= 0;
                    wv[i]    <= 0;
                end
            end else begin
                ishift   <= {ishift[0 +: INPUT_BIT_SIZE-1], ibit};
                for ( int i = 0; i < READ_NUM; i++ ) begin
                    rvreg[i] <= rv[i];
                    ra[i]    <= ishift[ i*INDEX_BIT_SIZE +: INDEX_BIT_SIZE ];
                end
                for ( int i = 0; i < WRITE_NUM; i++ ) begin
                    we[i]    <= ishift[ i+READ_NUM*INDEX_BIT_SIZE +: 1 ];
                    wa[i]    <= ishift[ i*INDEX_BIT_SIZE+WRITE_NUM+READ_NUM*INDEX_BIT_SIZE +: INDEX_BIT_SIZE ];
                    wv[i]    <= ishift[ i*ENTRY_BIT_SIZE+WRITE_NUM*INDEX_BIT_SIZE+WRITE_NUM+READ_NUM*INDEX_BIT_SIZE +: ENTRY_BIT_SIZE ];
                end
            end
        end

        always_comb begin
            for ( int i = 0; i < READ_NUM; i++ ) begin
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
    
    BlockMultiPortRAM #( 
        .ENTRY_NUM( ENTRY_NUM ),
        .ENTRY_BIT_SIZE( ENTRY_BIT_SIZE ),
        .READ_NUM( READ_NUM ),
        .WRITE_NUM( WRITE_NUM )
    ) blockRAM (
        .*
    );
endmodule
