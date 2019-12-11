// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- Divider Unit
//
// - 32bit/32bit=32bitを行うモジュール
//

import BasicTypes::*;
import MicroOpTypes::*;
import OpFormatTypes::*;

// 除算ユニット
module DividerUnit (
input
    logic clk, rst,
    logic req,
    DataPath fuOpA_In,
    DataPath fuOpB_In,
    IntDIV_Code divCode,
output
    logic finished,
    DataPath dataOut
);

    logic regIsSigned, nextIsSigned;
    DataPath regDividend, nextDividend;
    DataPath regDivisor, nextDivisor;
    IntDIV_Code regDivCode, nextDivCode;
    DataPath quotient, remainder;
    
    QuickDivider div ( 
        .clk( clk ),
        .rst( rst ),
        .req ( req ),
        .dividend ( nextDividend ),
        .divisor ( nextDivisor ),
        .isSigned ( nextIsSigned ),
        .finished ( finished ),
        .quotient ( quotient ),
        .remainder ( remainder )
    );
    
// IntDIV code
/*
typedef enum logic [1:0]    // enum IntDIV_Code
{
    AC_DIV    = 2'b00,    // DIV    
    AC_DIVU   = 2'b01,    // DIVU
    AC_REM    = 2'b10,    // REM 
    AC_REMU   = 2'b11     // REMU  
} IntDIV_Code;
*/

    always_ff @(posedge clk) begin
        if (rst) begin
            regIsSigned <= FALSE;
            regDividend <= '0;
            regDivisor <= '0;
            regDivCode <= AC_DIV;
        end
        else begin
            regIsSigned <= nextIsSigned;
            regDividend <= nextDividend;
            regDivisor <= nextDivisor;
            regDivCode <= nextDivCode;
        end
    end

    // Make src operands unsigned(plus) value.
    always_comb begin
        if (req) begin
            if (divCode == AC_DIVU || divCode == AC_REMU) begin
                // DIVU and REMU take srcs as unsigned.
                nextIsSigned = FALSE;
            end
            else begin
                // DIV and REM take srcs as signed.
                nextIsSigned = TRUE;
            end
            nextDividend = fuOpA_In;
            nextDivisor = fuOpB_In;
            nextDivCode = divCode;
        end
        else begin
            // Keep the value 
            nextIsSigned = regIsSigned;
            nextDividend = regDividend;
            nextDivisor = regDivisor;
            nextDivCode = regDivCode;
        end

        // Choose output from div or rem.
        if (regDivCode == AC_DIV || regDivCode == AC_DIVU) begin
            dataOut = quotient;
        end
        else begin
            dataOut = remainder;
        end
    end

endmodule : DividerUnit


// パイプライン化された除算ユニット
module PipelinedDividerUnit #( 
    parameter BIT_WIDTH = 32,
    parameter PIPELINE_DEPTH = 3
)( 
input
    logic clk, 
    logic stall,
    logic req,
    DataPath fuOpA_In,
    DataPath fuOpB_In,
    IntDIV_Code divCode,
output
    logic finished,
    DataPath dataOut
);
    
    typedef struct packed { // PipeReg
        logic valid;
        logic isSigned;
        IntDIV_Code divCode;
    } PipeReg;
    
    PipeReg pipeReg[ PIPELINE_DEPTH-1 ], nextReg;
    
    DataPath quotient, remainder;
    logic isSigned;
    DataPath dividend;
    DataPath divisor;

    PipelinedRefDivider #( 
        .BIT_WIDTH( $bits(DataPath) ),
        .PIPELINE_DEPTH( PIPELINE_DEPTH )
    ) div (
        .clk( clk ),
        .stall( stall ),
        .dividend(dividend),
        .divisor(divisor),
        .isSigned(isSigned),
        .quotient(quotient),
        .remainder(remainder)
    );

    always_ff @(posedge clk) begin
        if (!stall) begin
            pipeReg[0] <= nextReg;
            for (int i = 1; i < PIPELINE_DEPTH-1; i++) begin
                pipeReg[i] <= pipeReg[i-1];
            end
        end
    end

    // Make src operands unsigned(plus) value.
    always_comb begin
        if (divCode == AC_DIVU || divCode == AC_REMU) begin
            // // MULHU takes srcA as unsigned.
            // srcA_signed = fuOpA_signed;
            isSigned = TRUE;
        end
        else begin
            isSigned = FALSE;
        end


        dividend = fuOpA_In;
        divisor = fuOpB_In;

        nextReg.isSigned = isSigned;
        nextReg.divCode = divCode;
        nextReg.valid = req;

        if (pipeReg[PIPELINE_DEPTH-2].valid) begin
            if (pipeReg[PIPELINE_DEPTH-2].divCode == AC_DIV || pipeReg[PIPELINE_DEPTH-2].divCode == AC_DIVU) begin
                dataOut = quotient;
            end
            else begin
                dataOut = remainder;
            end

            finished = TRUE;
        end
        else begin
            dataOut = '0;
            finished = FALSE;
        end
    end

    
`ifndef RSD_SYNTHESIS
    initial begin
        for (int i = 0; i < PIPELINE_DEPTH-1; i++) begin
            pipeReg[i] <= '0;
        end
    end
`endif

endmodule : PipelinedDividerUnit
