// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- Multiplier implementation.
//

`include "BasicMacros.sv"

// 符号付き乗算器を生成するモジュール
module Multiplier #(
    parameter BIT_WIDTH = 32
)(
    input  logic signed [   BIT_WIDTH-1:0 ] srcA,
    input  logic signed [   BIT_WIDTH-1:0 ] srcB,
    output logic signed [ 2*BIT_WIDTH-1: 0] dst
);

    assign dst = srcA * srcB;   // synthesis syn_dspstyle = "dsp48"
    
endmodule : Multiplier

module SignExtender #( 
    parameter BIT_WIDTH = 32
)(
    input  logic [   BIT_WIDTH-1:0 ] in, 
    input  logic sign,
    output logic [   BIT_WIDTH:0 ] out
);
    always_comb begin
        if (sign) begin
            out = {in[BIT_WIDTH-1], in};
        end
        else begin
            out = {1'b0, in};
        end
    end    
endmodule : SignExtender


// パイプライン化された乗算器
// PIPELINE_DEPTHは2以上でなければならない
module PipelinedMultiplier #(
    parameter BIT_WIDTH = 32,
    parameter PIPELINE_DEPTH = 3
)(
    input  logic clk, stall,
    input  logic [   BIT_WIDTH-1:0 ] srcA,
    input  logic [   BIT_WIDTH-1:0 ] srcB,
    input  logic signA,
    input  logic signB,
    output logic [ 2*BIT_WIDTH-1:0 ] dst
);
    localparam RESULT_PIPELINE_DEPTH = PIPELINE_DEPTH - 2;
    logic signed [ 2*BIT_WIDTH+1:0 ] pipeReg [RESULT_PIPELINE_DEPTH]; // synthesis syn_pipeline = 1
    logic signed [ 2*BIT_WIDTH+1:0 ] mulResult;

    logic signed [ BIT_WIDTH:0 ] exSrcA;
    logic signed [ BIT_WIDTH:0 ] exSrcB;
    logic signed [ BIT_WIDTH:0 ] exSrcA_Reg;
    logic signed [ BIT_WIDTH:0 ] exSrcB_Reg;

    SignExtender #( 
        .BIT_WIDTH(BIT_WIDTH) 
    ) signExtenderA (
        .in(srcA),
        .sign(signA),
        .out(exSrcA)
    );

    SignExtender #( 
        .BIT_WIDTH(BIT_WIDTH) 
    ) signExtenderB (
        .in(srcB),
        .sign(signB),
        .out(exSrcB)
    );

    
    `RSD_STATIC_ASSERT(
        PIPELINE_DEPTH > 2,
        "A pipeline depth of a PipelinedMultiplier module must be more than 2."
    );
    
    always_comb begin
        (* use_dsp48 = "yes" *)
        mulResult = exSrcA_Reg * exSrcB_Reg;   // synthesis syn_dspstyle = "dsp48"
        dst = pipeReg[RESULT_PIPELINE_DEPTH-1][2*BIT_WIDTH-1:0];
    end

    always_ff @(posedge clk) begin
        if (stall) begin
            exSrcA_Reg <= exSrcA_Reg;
            exSrcB_Reg <= exSrcB_Reg;
            for ( int i = 0; i < RESULT_PIPELINE_DEPTH; i++) begin
                pipeReg[i] <= pipeReg[i];
            end
        end
        else begin
            // At the first stage, only sign extension is performed,
            // because automatic pipeline synthesize may be applicable to 
            // pure multiplication operation.
            exSrcA_Reg <= exSrcA;
            exSrcB_Reg <= exSrcB;

            pipeReg[0] <= mulResult;
            for ( int i = 1; i < RESULT_PIPELINE_DEPTH; i++) begin
                pipeReg[i] <= pipeReg[i-1];
            end
        end
    end

`ifndef RSD_SYNTHESIS
    initial begin
        for ( int i = 0; i < PIPELINE_DEPTH-1; i++)
            pipeReg[i] <= '0;
    end
`endif
    
endmodule : PipelinedMultiplier
