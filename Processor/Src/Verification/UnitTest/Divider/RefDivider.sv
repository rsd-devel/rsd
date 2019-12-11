// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- Reference Divider Unit
// This unit performs signed/unsigned divisiton
//

import BasicTypes::*;
 
module RefDivider(
input
    logic clk, rst,         // clock, reset
    logic req,              // request a new operation
    DataPath dividend,
    DataPath divisor,
    logic isSigned,          // operation is performed in a singed mode
output
    logic finished,
    DataPath quotient,
    DataPath remainder
);
    // Internal registers
    DataPath regZ, nextZ;  // dividend
    DataPath regD, nextD;  // divisor
    DataPath regQ, nextQ;  // quotient
    DataPath regR, nextR;  // remainder
    logic regSigned, nextSigned; // signed or unsigned

    logic [DATA_BYTE_WIDTH_BIT_SIZE-1+1:0] regCounter, nextCounter;
    parameter DATA_MINUS_ONE = (1 << DATA_WIDTH) - 1;
    parameter DATA_MINIMUM = (1 << (DATA_WIDTH - 1));

    typedef enum logic[1:0]
    {
        PHASE_FINISHED = 0,     // Division is finished. It outputs results to quotient, remainder 
        PHASE_PROCESSING = 1,   // In processing
        PHASE_COMPENSATING = 2  // In processing for compensating results
    } Phase;
    Phase regPhase, nextPhase;

     always_ff @(posedge clk) begin
        if (rst) begin
            regZ <= 0;
            regD <= 0;
            regQ <= 0;
            regR <= 0;
            regPhase <= PHASE_FINISHED;
            regCounter <= 0;
            regSigned <= FALSE;
        end
        else begin
            regZ <= nextZ;
            regD <= nextD;
            regQ <= nextQ;
            regR <= nextR;
            regPhase <= nextPhase;
            regCounter <= nextCounter;
            regSigned <= nextSigned;
        end
     end


     always_comb begin
        finished = (regPhase == PHASE_FINISHED) ? TRUE : FALSE;

        if (req) begin
            // A request is accepted regardless of the current phase
            nextZ = dividend;
            nextD = divisor;
            nextQ = 0;
            nextR = 0;
            nextSigned = isSigned;
            nextPhase = PHASE_PROCESSING;
            nextCounter = 0;
        end
        else begin 
            nextZ = regZ;
            nextD = regD;
            nextQ = regQ;
            nextR = regR;
            nextSigned = regSigned;
            nextCounter = regCounter;

            if (regPhase == PHASE_PROCESSING) begin
                nextCounter = regCounter + 1;
                nextPhase = (nextCounter > 4) ? PHASE_COMPENSATING : PHASE_PROCESSING;
            end
            else if (regPhase == PHASE_COMPENSATING) begin
                // Results on division by zero or overflow are difined by 
                // RISC-V specification.
                if (regD == 0) begin
                    // Division by zero
                    nextQ = -1;
                    nextR = regZ;
                end
                else begin
                    if (regSigned) begin
                        if (regZ == DATA_MINIMUM && regD == DATA_MINUS_ONE) begin 
                            // Sigined division can cause overflow
                            // ex. 8 bits signed division "-0x80 / -1 = 0x80"
                            // causes overflow because the resulst 0x80 > 0x7f
                            nextQ = regZ;
                            nextR = 0;
                        end
                        else begin
                            nextQ = $signed(regZ) / $signed(regD);
                            nextR = $signed(regZ) % $signed(regD);
                        end
                    end
                    else begin
                        nextQ = regZ / regD;
                        nextR = regZ % regD;
                    end
                end
                nextPhase = PHASE_FINISHED;
            end
            else begin  // PHASE_FINISHED
                nextPhase = regPhase;
            end
        end

        // Output results
        quotient = regQ;
        remainder = regR;

     end

endmodule : RefDivider


// This unit performs signed/unsigned divisiton with arbitrary cycles
module PipelinedRefDivider # (
    parameter PIPELINE_DEPTH = 3
)(
input
    logic clk, rst,         // clock, reset
    logic req,              // request a new operation
    DataPath dividend,
    DataPath divisor,
    logic isSigned,          // operation is performed in a singed mode
output
    logic finished,
    DataPath quotient,
    DataPath remainder
);

    parameter DATA_MINUS_ONE = (1 << DATA_WIDTH) - 1;
    parameter DATA_MINIMUM = (1 << (DATA_WIDTH - 1));

    typedef enum logic
    {
        PHASE_FINISHED = 0,     // Division is finished. It outputs results to quotient, remainder
        PHASE_NOP = 1           // Did not process division in this cycle
    } Phase;

    typedef struct packed { // PipeReg
        DataPath dividend;
        DataPath divisor;
        logic isSigned;          // operation is performed in a singed mode
        DataPath quotient;
        DataPath remainder;
        Phase phase;
    } PipeReg;

    PipeReg pipeReg[ PIPELINE_DEPTH-1 ], nextReg, lastReg;

    logic nextFinished;
    DataPath nextQuotient, nextRemainder;

    always_ff @(posedge clk) begin
        if (req) begin
            finished <= FALSE;
        end
        else if (nextFinished) begin
            finished <= TRUE;
            quotient <= nextQuotient;
            remainder <= nextRemainder;
        end
    end

    always_ff @(posedge clk) begin
        // Pipeline
        pipeReg[0] <= nextReg;
        for ( int i = 1; i < PIPELINE_DEPTH-1; i++) begin
            pipeReg[i] <= pipeReg[i-1];
        end
    end

    always_comb begin
        // Take pipeline register from last entry
        lastReg = pipeReg[PIPELINE_DEPTH-2];

        // Output result
        nextFinished = (lastReg.phase == PHASE_FINISHED) ? TRUE : FALSE;
        nextQuotient = lastReg.quotient;
        nextRemainder = lastReg.remainder;

        if (req) begin
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
                if (isSigned) begin
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
        end
        else begin 
            nextReg.dividend = '0;
            nextReg.divisor = '0;
            nextReg.isSigned = '0;
            nextReg.quotient = '0;
            nextReg.remainder = '0;
            nextReg.phase = PHASE_NOP;
        end
    end


`ifndef RSD_SYNTHESIS
    initial begin
        for ( int i = 0; i < PIPELINE_DEPTH-1; i++) begin
            pipeReg[i] <= '0;
        end
    end
`endif

endmodule : PipelinedRefDivider
