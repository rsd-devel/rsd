// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.



//
// MemoryRequestQueue
//

import BasicTypes::*;
import MemoryTypes::*;

module MemoryRequestQueue( 
input 
    logic clk,
    logic rst,
    logic push,
    MemoryRequestData pushedData,
output
    logic hasRequest,
    MemoryRequestData requestData
);

    typedef logic [$clog2(MEM_REQ_QUEUE_SIZE)-1:0] IndexPath;
    logic pop;
    logic full, empty;

    IndexPath headPtr;
    IndexPath tailPtr;
    LatencyCountPath count, countReg;
    integer RANDOM_VALUE;

    // size, initial head, initial tail, initial count
    QueuePointer #( MEM_REQ_QUEUE_SIZE, 0, 0, 0 )
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
        
    MemoryRequestData memoryRequestQueue[ MEM_REQ_QUEUE_SIZE ];

    always_ff @(posedge clk) begin
        if (push) begin
            memoryRequestQueue[ tailPtr ] <= pushedData;
        end

        if (rst) begin
            countReg <= '0;
        end
        else begin
            countReg <= count;
        end
    end

    always_comb begin
        if (rst) begin
`ifndef RSD_SYNTHESIS
    `ifndef RSD_FUNCTIONAL_SIMULATION_VERILATOR
            // Pass seed value first
            // NOTE: this cannot be done in initial begin,
            // because $urandom is thread local
            RANDOM_VALUE = $urandom(RANDOM_LATENCY_SEED) % VARIAVBLE_WIDTH;
    `else
            RANDOM_VALUE = 0;
    `endif
`else
            RANDOM_VALUE = 0;
`endif
        end
        
        count = countReg;

        if (!empty) begin
            // There is some request in the queue
            if (count == RANDOM_VALUE) begin
                // Issue memory request
                pop = TRUE;
                count = '0;
`ifndef RSD_SYNTHESIS
    `ifndef RSD_FUNCTIONAL_SIMULATION_VERILATOR
                // Set next memory latency
                RANDOM_VALUE = $urandom() % VARIAVBLE_WIDTH; 
    `endif
`endif
                // for debug
                // $display("Latency set to %d", RANDOM_VALUE);
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

    assert property(@(posedge clk) !( full ))
        else $error("Cannot response so many memory request.");

endmodule : MemoryRequestQueue
