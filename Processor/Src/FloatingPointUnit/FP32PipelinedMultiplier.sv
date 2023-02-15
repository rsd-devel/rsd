import FPUTypes::*;
module FP32PipelinedMultiplier #(parameter PIPELINE_DEPTH = 5) (
input
    logic clk,
    logic [31:0] lhs,
    logic [31:0] rhs,
output
    logic [31:0] result
);

    FMulStage1RegPath stg0Out;
    FMulStage2RegPath stg1Out;
    logic [31:0] stg2Out;

    FMulStage0 stg0(lhs, rhs, stg0Out);
    FMulStage1 stg1(clk, stg0Out, stg1Out);
    FMulStage2 stg2(clk, stg1Out, stg2Out);
    
    logic [31:0] pipeReg[PIPELINE_DEPTH - 3];
    always_comb begin
        if( PIPELINE_DEPTH > 3) begin
            result = pipeReg[0];
        end else begin
            result = stg2Out;
        end
    end
    always_ff @(posedge clk) begin
        if (PIPELINE_DEPTH > 3) begin
            pipeReg[PIPELINE_DEPTH-4] <= stg2Out;
            for (int i=1; i < PIPELINE_DEPTH - 3; ++i) begin
                pipeReg[i-1] <= pipeReg[i];
            end
        end
    end
endmodule

module FMulStage0(
    input logic [31:0] lhs,
    input logic [31:0] rhs,
    output FMulStage1RegPath stg0Out
);
    function automatic [9:0] leading_zeros_count;
        input[22:0] x;
        for(leading_zeros_count = 0; leading_zeros_count <= 22; leading_zeros_count = leading_zeros_count + 1)
            if(x >> (22-leading_zeros_count) != 0) break;
    endfunction

    wire lhs_sign = lhs[31];
    wire rhs_sign = rhs[31];
    wire [7:0] lhs_expo = lhs[30:23];
    wire [7:0] rhs_expo = rhs[30:23];
    wire[22:0] lhs_mant = lhs[22:0];
    wire[22:0] rhs_mant = rhs[22:0];

    // NaN handling
    wire lhs_is_zero = lhs_expo == 8'h00 & lhs_mant == 0;
    wire rhs_is_zero = rhs_expo == 8'h00 & rhs_mant == 0;
    wire lhs_is_inf  = lhs_expo == 8'hff & lhs_mant == 0;
    wire rhs_is_inf  = rhs_expo == 8'hff & rhs_mant == 0;
    wire lhs_is_nan  = lhs_expo == 8'hff & lhs_mant != 0;
    wire rhs_is_nan  = rhs_expo == 8'hff & rhs_mant != 0;
    wire res_is_nan  = lhs_is_nan | rhs_is_nan | (lhs_is_zero & rhs_is_inf) | (lhs_is_inf & rhs_is_zero);
    //wire[31:0]  nan  = lhs_is_nan ? lhs | 32'h00400000 : rhs_is_nan ? rhs | 32'h00400000 : 32'hffc00000; // qNan
    wire[31:0]   nan = 32'h7fc00000;  
    
    // Preparation
    wire       result_sign  = lhs_sign ^ rhs_sign;
    wire [9:0] v_lhs_expo   = lhs_expo == 0 ? -leading_zeros_count(lhs_mant) : { 2'b0, lhs_expo }; // virtual exponent (ignores subnormals, but is biased)
    wire [9:0] v_rhs_expo   = rhs_expo == 0 ? -leading_zeros_count(rhs_mant) : { 2'b0, rhs_expo }; // virtual exponent (ignores subnormals, but is biased)
    wire [9:0] virtual_expo = v_lhs_expo + v_rhs_expo - 127; // new biased exponent (ignores subnormals)
    wire       subnormal    = $signed(virtual_expo) <= 0;
    wire       res_is_zero  = $signed(virtual_expo) <= -25 | lhs_is_zero | rhs_is_zero;
    wire       res_is_inf   = $signed(virtual_expo) >= 255 | lhs_is_inf | rhs_is_inf;

    assign stg0Out = {{lhs_expo, v_lhs_expo, lhs_mant}, {rhs_expo, v_rhs_expo, rhs_mant}, virtual_expo, result_sign, subnormal, res_is_zero, res_is_nan, res_is_inf, nan};

endmodule

module FMulStage1(
    input clk,
    input FMulStage1RegPath stg1In,
    output FMulStage2RegPath stg1Out
);
    FMulStage1RegPath pipeReg;
    always_ff @(posedge clk) begin
        pipeReg <= stg1In; 
    end

    wire [7:0] lhs_expo, rhs_expo;
    wire [9:0] v_lhs_expo, v_rhs_expo;
    wire[22:0] lhs_mant, rhs_mant;
    assign {lhs_expo, v_lhs_expo, lhs_mant} = pipeReg.lhs;
    assign {rhs_expo, v_rhs_expo, rhs_mant} = pipeReg.rhs;
    wire [9:0] virtual_expo = pipeReg.virtual_expo;
    wire result_sign = pipeReg.result_sign;
    wire subnormal = pipeReg.subnormal;
    wire res_is_zero = pipeReg.res_is_zero;
    wire res_is_nan = pipeReg.res_is_nan;
    wire res_is_inf = pipeReg.res_is_inf;
    wire [31:0] nan = pipeReg.nan;

    // Determine shift amount
    wire       generate_subnormal  =  subnormal &  lhs_expo != 0 & rhs_expo != 0 ; // normal * normal -> subnormal
    wire       remaining_subnormal =  subnormal & (lhs_expo == 0 | rhs_expo == 0); // subnormal * normal -> subnormal
    wire       escape_subnormal    = !subnormal & (lhs_expo == 0 | rhs_expo == 0); // subnormal * normal -> normal
    /* verilator lint_off WIDTH */
    wire [5:0] generate_subnormal_shift  = -virtual_expo; // right shift
    wire [5:0] remaining_subnormal_shift = lhs_expo == 0 ? 126 - rhs_expo : 126 - lhs_expo; // right shift
    wire [5:0] escape_subnormal_shift    = lhs_expo == 0 ? 1 - v_lhs_expo : 1 - v_rhs_expo; // left shift
    /* verilator lint_on WIDTH */
    wire [5:0] subnormal_shift = generate_subnormal  ? 23 + generate_subnormal_shift :
                                 remaining_subnormal ? 23 + remaining_subnormal_shift :
                                 escape_subnormal    ? 23 - escape_subnormal_shift
                                                     : 23 ;

    // Multiplier
    wire[47:0] multiplier_lhs    = { 24'h0, lhs_expo != 8'h00, lhs_mant }; // lhs_expo != 8'h00 is the hidden bit of a normalized number
    wire[47:0] multiplier_rhs    = { 24'h0, rhs_expo != 8'h00, rhs_mant }; // rhs_expo != 8'h00 is the hidden bit of a normalized number
    wire[47:0] multiplier_result = multiplier_lhs * multiplier_rhs;

    assign stg1Out = {multiplier_result, subnormal_shift, virtual_expo, result_sign, subnormal, res_is_zero, res_is_nan, res_is_inf, nan};

endmodule

module FMulStage2(
    input clk,
    input FMulStage2RegPath stg2In,
    output logic [31:0] result
);

    FMulStage2RegPath pipeReg;
    always_ff @(posedge clk) begin
        pipeReg <= stg2In; 
    end

    wire[47:0] multiplier_result = pipeReg.multiplier_result;
    wire [5:0] subnormal_shift = pipeReg.subnormal_shift;
    wire [9:0] virtual_expo = pipeReg.virtual_expo;
    wire result_sign = pipeReg.result_sign;
    wire subnormal = pipeReg.subnormal;
    wire res_is_zero = pipeReg.res_is_zero;
    wire res_is_nan = pipeReg.res_is_nan;
    wire res_is_inf = pipeReg.res_is_inf;
    wire [31:0] nan = pipeReg.nan;

    /* verilator lint_off WIDTH */
    wire[25:0] shifter_result = { multiplier_result, 1'b0 } >> subnormal_shift;
    /* verilator lint_on WIDTH */
    wire       sticky         = multiplier_result << (49 - subnormal_shift) != 0; // the part shifted out above
    wire       round_to_away  = subnormal | shifter_result[25] ? shifter_result[1] & (shifter_result[2] | shifter_result[0] | sticky)
                                                               : shifter_result[0] & (shifter_result[1] |                     sticky); // round to nearest, ties to even
    wire       exp_plus_one   = subnormal ? shifter_result >= 26'h1fffffe
                                          : shifter_result >= 26'h1ffffff; // carry is generated with rounding taken into account

    wire[22:0] result_mant   = (subnormal | shifter_result[25] ? shifter_result[24:2] : shifter_result[23:1]) + { 22'h0, round_to_away };
    wire [7:0] result_expo   = subnormal ? { 7'h0, exp_plus_one } : virtual_expo[7:0] + { 7'h0, exp_plus_one };
    wire[31:0] inf           = { result_sign, 8'hff, 23'h0 };
    wire[31:0] zero          = { result_sign, 8'h00, 23'h0 };

    wire[31:0] final_result  = res_is_zero ? zero :
                               (res_is_inf | result_expo == 8'hff)  ? inf  : { result_sign, result_expo, result_mant };
    assign result = res_is_nan ? nan : final_result;

endmodule
