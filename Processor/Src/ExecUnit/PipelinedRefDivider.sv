// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- Pipelined Reference Divider Unit
// This unit performs signed/unsigned divisiton with arbitrary cycles
//

import BasicTypes::*;
 
module PipelinedRefDivider # (
    parameter BIT_WIDTH = 32,
    parameter PIPELINE_DEPTH = 3
)(
input
    logic clk,         // clock, reset
    //logic req,              // request a new operation
    logic stall,
    DataPath dividend,
    DataPath divisor,
    logic isSigned,          // operation is performed in a singed mode
output
    //logic finished,
    DataPath quotient,
    DataPath remainder
);

    parameter DATA_MINUS_ONE = (1 << DATA_WIDTH) - 1;
    parameter DATA_MINIMUM = (1 << (DATA_WIDTH - 1));

    typedef enum logic[1:0]
    {
        PHASE_FINISHED = 0,     // Division is finished. It outputs results to quotient, remainder 
        PHASE_PROCESSING = 1,   // In processing
        PHASE_COMPENSATING = 2,  // In processing for compensating results
        PHASE_NOTHING_TO_DO = 3
    } Phase;
    Phase regPhase, nextPhase;


    typedef struct packed { // PipeReg
        DataPath dividend;
        DataPath divisor;
        logic isSigned;          // operation is performed in a singed mode
        DataPath quotient;
        DataPath remainder;
        Phase phase;
    } PipeReg;

    PipeReg pipeReg[ PIPELINE_DEPTH-1 ], nextReg;

    always_ff @(posedge clk) begin
        if (!stall) begin 
            pipeReg[0] <= nextReg;
            for ( int i = 1; i < PIPELINE_DEPTH-1; i++) begin
                pipeReg[i] <= pipeReg[i-1];
            end
        end
    end


    always_comb begin
        //finished = (pipeReg[PIPELINE_DEPTH-2].phase == PHASE_FINISHED) ? TRUE : FALSE;
        quotient = pipeReg[PIPELINE_DEPTH-2].quotient;
        remainder = pipeReg[PIPELINE_DEPTH-2].remainder;

        //if (req) begin
            // A request is accepted regardless of the current phase
            nextReg.dividend = dividend;
            nextReg.divisor = divisor;
            nextReg.isSigned = isSigned;

            if (divisor == 0) begin
                // Division by zero
                nextReg.quotient = -1;
                nextReg.remainder = dividend;
            end
            else begin
                if (!isSigned) begin
                    if (dividend == DATA_MINIMUM && divisor == DATA_MINUS_ONE) begin
                        // Sigined division can cause overflow
                        // ex. 8 bits signed division "-0x80 / -1 = 0x80"
                        // causes overflow because the resulst 0x80 > 0x7f
                        nextReg.quotient = dividend;
                        nextReg.remainder = '0;
                    end
                    else begin
                        nextReg.quotient = $signed(dividend) / $signed(divisor);
                        nextReg.remainder = $signed(dividend) % $signed(divisor);
                    end
                end
                else begin
                    nextReg.quotient = dividend / divisor;
                    nextReg.remainder = dividend % divisor;
                end
            end
            nextReg.phase = PHASE_FINISHED;
        /*end
        else begin 
            nextReg.dividend = '0;
            nextReg.divisor = '0;
            nextReg.isSigned = '0;
            nextReg.quotient = '0;
            nextReg.remainder = '0;
            nextReg.phase = PHASE_NOTHING_TO_DO;
        end*/
    end


`ifndef RSD_SYNTHESIS
    initial begin
        for ( int i = 0; i < PIPELINE_DEPTH-1; i++)
            pipeReg[i] <= '0;
    end
`endif

endmodule : PipelinedRefDivider
