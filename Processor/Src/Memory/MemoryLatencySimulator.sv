// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`include "BasicMacros.sv"

//
// MemoryLatencySimulator
//

import BasicTypes::*;
import MemoryTypes::*;

module MemoryLatencySimulator( 
input 
    logic clk,
    logic rst,
    logic push,
    MemoryLatencySimRequestPath pushedData,
output
    logic hasRequest,
    MemoryLatencySimRequestPath requestData
);

    typedef logic [$clog2(MEM_LATENCY_SIM_QUEUE_SIZE)-1:0] IndexPath;
    logic pop;
    logic full, empty;

    IndexPath headPtr;
    IndexPath tailPtr;
    LatencyCountPath count, countReg;
    MemoryRandPath randReg, randNext;
    integer RANDOM_VALUE;

    // size, initial head, initial tail, initial count
    QueuePointer #( MEM_LATENCY_SIM_QUEUE_SIZE, 0, 0, 0 )
        pointer(
            .clk( clk ),
            .rst( rst ),
            .push( push ),
            .pop( pop ),
            .full( full ),
            .empty( empty ),
            .headPtr( headPtr ),
            .tailPtr( tailPtr )
        );
        
    MemoryLatencySimRequestPath memoryRequestQueue[ MEM_LATENCY_SIM_QUEUE_SIZE ];

    always_ff @(posedge clk) begin
        if (push) begin
            memoryRequestQueue[ tailPtr ] <= pushedData;
        end

        if (rst) begin
            countReg <= '0;
            randReg <= MEM_LATENCY_SIM_RAND_SEED;
        end
        else begin
            countReg <= count;
            randReg <= randNext;
        end
    end

    always_comb begin
        randNext = randReg;
        count = countReg;

        if (!empty) begin
            // There is some request in the queue
            if (count == (randReg % MEM_LATENCY_SIM_LATENCY_FLUCTUATION_RANGE)) begin
                // Issue memory request
                pop = TRUE;
                count = '0;
                randNext = randNext ^ (randNext << 13); 
                randNext = randNext ^ (randNext >> 17);
                randNext = randNext ^ (randNext << 5);

                // for debug
                //$display("Latency set to %d", randNext % MEM_LATENCY_SIM_LATENCY_FLUCTUATION_RANGE);
            end
            else begin
                // Wait until the determined latency has passed
                pop = FALSE;
                count++;
            end
        end
        else begin
            // There is no request in the queue
            pop = FALSE;
        end

        hasRequest = pop;
        requestData = memoryRequestQueue[ headPtr ];
    end

    `RSD_ASSERT_CLK(clk, !full, "Cannot response so many memory request.");

`ifdef RSD_SYNTHESIS
    `RSD_STATIC_ASSERT(FALSE, "This module must not be used in synthesis.");
`endif

endmodule : MemoryLatencySimulator
