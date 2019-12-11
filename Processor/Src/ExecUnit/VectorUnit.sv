// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- Vector Unit
//
// - SIMD命令のために、ベクトル演算を行うユニット
//
import BasicTypes::*;
import MicroOpTypes::*;
import OpFormatTypes::*;

// パイプライン化されたベクトル加算ユニット
// PIPELINE_DEPTHは2以上でなければならない
module PipelinedVectorAdder #(
    parameter PIPELINE_DEPTH = 3
)(
input
    logic clk, stall,
    VectorPath fuOpA_In,
    VectorPath fuOpB_In,
output
    VectorPath dataOut
);
    VectorPath pipeReg[ PIPELINE_DEPTH-1 ]; // synthesis syn_pipeline = 1
    DataPath [ VEC_WORD_WIDTH-1:0 ] srcA, srcB, dst;

    always_comb begin
        // `RSD_ASSERT_CLK(clk, PIPELINE_DEPTH > 1, "A pipeline depth of a PipelinedVectorAdder module must be more than 1.");

        srcA = fuOpA_In;
        srcB = fuOpB_In;

        for( int i = 0; i < VEC_WORD_WIDTH; i++ ) begin
            dst[i] = srcA[i] + srcB[i];
        end

        dataOut = pipeReg[ PIPELINE_DEPTH-2 ];
    end

    always_ff @(posedge clk) begin
        if ( stall ) begin
            for ( int i = 0; i < PIPELINE_DEPTH-1; i++)
                pipeReg[i] <= pipeReg[i];
        end
        else begin
        pipeReg[0] <= dst;
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
endmodule


// パイプライン化されたベクトル乗算ユニット
module PipelinedVectorMultiplier #(
    parameter PIPELINE_DEPTH = 3
)(
input
    logic clk, stall,
    VectorPath fuOpA_In,
    VectorPath fuOpB_In,
    logic getUpper, // TRUEなら、乗算結果の33-64bit目をmulDataOutにセット
    IntMUL_Code mulCode,
output
    VectorPath dataOut
);
    DataPath [ VEC_WORD_WIDTH-1:0 ] srcA, srcB, dst;

    for ( genvar i = 0; i < VEC_WORD_WIDTH; i++ ) begin : mulUnit
        PipelinedMultiplierUnit #(
            .BIT_WIDTH( DATA_WIDTH ),
            .PIPELINE_DEPTH( PIPELINE_DEPTH )
        ) mulUnit (
            .clk( clk ),
            .stall( stall ),
            .fuOpA_In( srcA[i] ),
            .fuOpB_In( srcB[i] ),
            .getUpper( getUpper ),
            .mulCode( mulCode ),
            .dataOut( dst[i] )
        );
    end

    always_comb begin
        srcA = fuOpA_In;
        srcB = fuOpB_In;
        dataOut = dst;
    end
endmodule
