// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- Multiplier Unit
// This unit performs 32bit*32bit = 32bit,
// and return upper or lower 32 bit
//

import BasicTypes::*;
import MicroOpTypes::*;
import OpFormatTypes::*;

// Multiplier Unit
module MultiplierUnit (
input
    DataPath fuOpA_In,
    DataPath fuOpB_In,
    logic getUpper, // If TRUE, the multiplication result 33-64 bit is set to mulDataOut
output
    DataPath dataOut
);
    logic [ 2*DATA_WIDTH-1:0 ] mulResult;
    
    Multiplier #( 
        .BIT_WIDTH( $bits(DataPath) )
    ) mul ( 
        .srcA(fuOpA_In),
        .srcB(fuOpB_In),
        .dst(mulResult)
    );
    
    always_comb begin
        if (getUpper)
            dataOut = mulResult[ 2*DATA_WIDTH-1:DATA_WIDTH ];
        else
            dataOut = mulResult[ DATA_WIDTH-1:0 ];
    end
    
endmodule : MultiplierUnit


// Pipelined Multiplier Unit
module PipelinedMultiplierUnit #( 
    parameter BIT_WIDTH = 32,
    parameter PIPELINE_DEPTH = 3
)( 
input
    logic clk, stall,
    DataPath fuOpA_In,
    DataPath fuOpB_In,
    logic getUpper, // If TRUE, the multiplication result 33-64 bit is set to mulDataOut
    IntMUL_Code mulCode,
output
    DataPath dataOut
);
    
    typedef struct packed { // PipeReg
        logic getUpper;
        IntMUL_Code mulCode;
        logic fuOpA_sign;
        logic fuOpB_sign;
    } PipeReg;
    
    PipeReg pipeReg[ PIPELINE_DEPTH-1 ];
    
    logic [ 2*DATA_WIDTH-1:0 ] mulResult;
    //logic signed [ 2*DATA_WIDTH-1:0 ] mulResult_signed;
    //logic signed [ 2*DATA_WIDTH-1:0 ] dataOut_signed;
    logic signed [ DATA_WIDTH-1:0 ] fuOpA_signed;
    logic signed [ DATA_WIDTH-1:0 ] fuOpB_signed;
    logic fuOpA_sign;
    logic fuOpB_sign;
    //logic signed [ DATA_WIDTH-1:0 ] srcA_signed;
    //logic signed [ DATA_WIDTH-1:0 ] srcB_signed;
    logic signA;
    logic signB;
    logic [ DATA_WIDTH-1:0 ] srcA;
    logic [ DATA_WIDTH-1:0 ] srcB;

    PipelinedMultiplier #( 
        .BIT_WIDTH( $bits(DataPath) ),
        .PIPELINE_DEPTH( PIPELINE_DEPTH )
    ) mul (
        .clk( clk ),
        .stall( stall ),
        .srcA(srcA),
        .srcB(srcB),
        .signA(signA),
        .signB(signB),
        .dst(mulResult)
    );

    // Make src operands unsigned(plus) value.
    always_comb begin
        // fuOpA_signed = fuOpA_In;
        // fuOpB_signed = fuOpB_In;
        // fuOpA_sign = (fuOpA_signed < 0);
        // fuOpB_sign = (fuOpB_signed < 0);

        if ( mulCode == AC_MULHU ) begin
            // // MULHU takes srcA as unsigned.
            // srcA_signed = fuOpA_signed;
            signA = '0;
        end
        else begin
            // // Make fuOpA_In plus value when it is minus value. 
            // if (fuOpA_sign) begin
            //     srcA_signed = -fuOpA_signed;
            // end
            // else begin
            //     srcA_signed = fuOpA_signed;
            // end
            signA = '1;
        end

        if ( (mulCode == AC_MULHU) || (mulCode == AC_MULHSU) ) begin
            // // MULHU and MULHSU take srcB as unsigned.
            // srcB_signed = fuOpB_signed;
            signB = '0;
        end
        else begin
            // // Make fuOpB_In plus value when it is minus value. 
            // if (fuOpB_sign) begin
            //     srcB_signed = -fuOpB_signed;
            // end
            // else begin
            //     srcB_signed = fuOpB_signed;
            // end
            signB = '1;
        end

        // srcA = srcA_signed;
        // srcB = srcB_signed;
        srcA = fuOpA_In;
        srcB = fuOpB_In;
    end

    always_comb begin
        // mulResult_signed = mulResult;

        // case (pipeReg[ PIPELINE_DEPTH-2 ].mulCode)
        //     AC_MUL, AC_MULH: begin
        //         if (pipeReg[ PIPELINE_DEPTH-2 ].fuOpA_sign ^ pipeReg[ PIPELINE_DEPTH-2 ].fuOpA_sign) begin
        //             dataOut_signed = -mulResult_signed;
        //         end
        //         else begin
        //             dataOut_signed = mulResult_signed;
        //         end
        //     end
        //     AC_MULHSU: begin
        //         if (pipeReg[ PIPELINE_DEPTH-2 ].fuOpA_sign) begin
        //             dataOut_signed = -mulResult_signed;
        //         end
        //         else begin
        //             dataOut_signed = mulResult_signed;
        //         end
        //     end
        //     AC_MULHU: begin
        //         dataOut_signed = mulResult_signed;
        //     end
        //     default: begin
        //         dataOut_signed = mulResult_signed;
        //     end
        // endcase

        // if ( pipeReg[ PIPELINE_DEPTH-2 ].getUpper ) begin
        //     dataOut = dataOut_signed[ 2*DATA_WIDTH-1:DATA_WIDTH ];
        // end
        // else begin
        //     dataOut = dataOut_signed[ DATA_WIDTH-1:0 ];
        // end

        if ( pipeReg[ PIPELINE_DEPTH-2 ].getUpper ) begin
            dataOut = mulResult[ 2*DATA_WIDTH-1:DATA_WIDTH ];
        end
        else begin
            dataOut = mulResult[ DATA_WIDTH-1:0 ];
        end
    end
    
    always_ff @(posedge clk) begin
        if ( stall ) begin
            for ( int i = 0; i < PIPELINE_DEPTH-1; i++)
                pipeReg[i] <= pipeReg[i];
        end
        else begin
            pipeReg[0].getUpper <= getUpper;
            pipeReg[0].mulCode  <= mulCode;
            pipeReg[0].fuOpA_sign <= fuOpA_sign;
            pipeReg[0].fuOpB_sign <= fuOpB_sign;
            for ( int i = 1; i < PIPELINE_DEPTH-1; i++)
                pipeReg[i] <= pipeReg[i-1];
        end
    end
    
`ifndef RSD_SYNTHESIS
    initial begin
        for ( int i = 0; i < PIPELINE_DEPTH-1; i++)
            pipeReg[i] <= '0;
    end
`endif

endmodule : PipelinedMultiplierUnit
