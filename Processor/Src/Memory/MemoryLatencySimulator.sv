// Copyright 2021- RSD contributors.
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
    generate 
        if (MEM_LATENCY_SIM_TYPE == MEM_LATENCY_SIM_TYPE_FIXED) begin 
            FixedMemoryLatencySimulator sim(clk, rst, push, pushedData, hasRequest, requestData);
        end 
        else begin
            RandomMemoryLatencySimulator sim(clk, rst, push, pushedData, hasRequest, requestData);
        end
    endgenerate
endmodule


module FixedMemoryLatencySimulator( 
input 
    logic clk,
    logic rst,
    logic push,
    MemoryLatencySimRequestPath pushedData,
output
    logic hasRequest,
    MemoryLatencySimRequestPath requestData
);
    localparam LATENCY = FIXED_MEM_LATENCY_SIM_LATENCY_CYCLES;
    typedef struct packed { // MemoryShiftReg
        logic valid;
        MemoryLatencySimRequestPath req;
    } MemoryShiftReg;
    MemoryShiftReg memShiftReg[LATENCY];
    MemoryShiftReg nextMemShiftReg;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < LATENCY; i++) begin
                memShiftReg[i].valid <= '0;
                memShiftReg[i].req <= '0;
            end
        end
        else begin
            memShiftReg[0] <= nextMemShiftReg;
            for (int i = 0; i < LATENCY - 1; i++) begin
                memShiftReg[i + 1] <= memShiftReg[i];
            end
        end
    end

    always_comb begin
        //nextMemShiftReg = '0;
        nextMemShiftReg.valid = push;
        nextMemShiftReg.req = pushedData;

        hasRequest  = memShiftReg[LATENCY - 1].valid;
        requestData = memShiftReg[LATENCY - 1].req;
    end


`ifdef RSD_SYNTHESIS
    `RSD_STATIC_ASSERT(FALSE, "This module must not be used in synthesis.");
`endif

endmodule : FixedMemoryLatencySimulator



module RandomMemoryLatencySimulator( 
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

endmodule : RandomMemoryLatencySimulator
