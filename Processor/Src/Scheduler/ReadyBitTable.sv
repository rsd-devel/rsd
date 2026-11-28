// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Ready bit table.
// This table is used for checking already ready source operands on dispatch.
//
`ifndef REF
    `define REF ref
`endif

import BasicTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import MicroOpTypes::*;


module ReadyBitTable #(
    parameter SRC_OP_NUM = 2,
    parameter REG_NUM_BIT_WIDTH = 5,
    parameter ENTRY_NUM = 32
)(
    // input
    input   logic clk, rst, rstStart,
    input   logic wakeup[ WAKEUP_WIDTH ],
    input   logic wakeupDstValid [ WAKEUP_WIDTH ],
    input   logic [REG_NUM_BIT_WIDTH-1:0] wakeupDstRegNum [ WAKEUP_WIDTH ],
    input   logic dispatch[ DISPATCH_WIDTH ],
    input   logic dispatchedDstValid [ DISPATCH_WIDTH ],
    input   logic [REG_NUM_BIT_WIDTH-1:0] dispatchedDstRegNum [ DISPATCH_WIDTH ],
    input   logic dispatchedSrcValid [ DISPATCH_WIDTH ][ SRC_OP_NUM ],
    input   logic [REG_NUM_BIT_WIDTH-1:0] dispatchedSrcRegNum [ DISPATCH_WIDTH ][ SRC_OP_NUM ],
    // output
    output  logic dispatchedSrcReady[ DISPATCH_WIDTH ][ SRC_OP_NUM ]
);

    localparam READY_WRITE_NUM = WAKEUP_WIDTH + DISPATCH_WIDTH;
    localparam READY_READ_NUM = DISPATCH_WIDTH * SRC_OP_NUM;

    typedef logic [REG_NUM_BIT_WIDTH-1:0] RegNumPath;

    logic readyWE[READY_WRITE_NUM];
    logic readyWV[READY_WRITE_NUM];
    RegNumPath readyWA[READY_WRITE_NUM];
    logic readyRV[READY_READ_NUM];
    RegNumPath readyRA[READY_READ_NUM];

    // All source operands start ready.
    ResettableDistributedMultiPortRAM #(
        .ENTRY_NUM(1 << REG_NUM_BIT_WIDTH),
        .ENTRY_BIT_SIZE(1),
        .READ_NUM(READY_READ_NUM),
        .WRITE_NUM(READY_WRITE_NUM),
        .RESET_VALUE('1)
    ) readyBitTable (
        .clk(clk),
        .rst(rst),
        .rstStart(rstStart),
        .we(readyWE),
        .wa(readyWA),
        .wv(readyWV),
        .ra(readyRA),
        .rv(readyRV)
    );

    always_comb begin

        for (int i = 0; i < WAKEUP_WIDTH; i++) begin
            readyWA[i] = wakeupDstRegNum[i];
            readyWV[i] = TRUE;
            readyWE[i] = wakeup[i] && wakeupDstValid[i];
            //if(wakeup[i] && wakeupDstValid[i]) begin
            //    ready[ wakeupDstRegNum[i] ] <= TRUE;
        end

        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
            readyWA[i+WAKEUP_WIDTH] = dispatchedDstRegNum[i];
            readyWV[i+WAKEUP_WIDTH] = FALSE;
            readyWE[i+WAKEUP_WIDTH] = (dispatch[i] && dispatchedDstValid[i]);
            //if( dispatch[i] && dispatchedDstValid[i] ) begin
            //    ready[ dispatchedDstRegNum[i] ] <= FALSE;
        end

        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
            for (int j = 0; j < SRC_OP_NUM; j++) begin

                readyRA[i*SRC_OP_NUM + j] = dispatchedSrcRegNum[i][j];

                if ( dispatchedSrcValid[i][j] == FALSE ) begin
                    dispatchedSrcReady[i][j] = TRUE;
                end
                else begin
                    //dispatchedSrcReady[i][j] = ready[ dispatchedSrcRegNum[i][j] ];
                    dispatchedSrcReady[i][j] = readyRV[i*SRC_OP_NUM + j];

                    // Bypass wakeup signals.
                    for (int k = 0; k < WAKEUP_WIDTH; k++) begin
                        if (wakeup[k] &&
                            wakeupDstValid[k] &&
                            wakeupDstRegNum[k] == dispatchedSrcRegNum[i][j]
                        ) begin
                            dispatchedSrcReady[i][j] = TRUE;
                        end
                    end

                    // Bypass dispatched instruction's destination registers
                    for (int k = 0; k < i; k++) begin
                        if (dispatch[k] &&
                            dispatchedDstValid[k] &&
                            dispatchedSrcRegNum[i][j] == dispatchedDstRegNum[k]
                        ) begin
                            dispatchedSrcReady[i][j] = FALSE;
                        end
                    end
                end
            end
        end
    end

endmodule : ReadyBitTable

