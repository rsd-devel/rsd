module FP32PipelinedOther #(parameter PIPELINE_DEPTH = 5)(
input
    logic clk,
    logic [31:0] lhs,
    logic [31:0] rhs,
    FPU_Code fpuCode,
    Rounding_Mode rm,
output 
    logic [31:0] result
);
assign result = 32'h98765432;
endmodule
