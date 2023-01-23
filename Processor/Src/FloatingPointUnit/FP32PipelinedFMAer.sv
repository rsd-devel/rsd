module FP32PipelinedFMAer #(parameter PIPELINE_DEPTH = 5)(
input
    logic clk,
    logic [31:0] mullhs,
    logic [31:0] mulrhs,
    logic [31:0] addend,
    FPU_Code fpuCode,
    Rounding_Mode rm,
output 
    logic [31:0] result
);
assign result = 32'h98765432;
endmodule
