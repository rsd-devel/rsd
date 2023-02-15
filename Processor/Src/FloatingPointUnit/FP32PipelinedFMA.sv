import FPUTypes::*;
module FP32PipelinedFMA(
    input  logic clk,
    input  logic [31:0] mullhs,
    input  logic [31:0] mulrhs,
    input  logic [31:0] addend,
    output logic [31:0] result
);

    FMAStage1RegPath stg0Out;
    FMAStage2RegPath stg1Out;
    FMAStage3RegPath stg2Out;
    FMAStage4RegPath stg3Out;
    
    // Fused-multiply-adder (24bit*24bit<<3+76bit+sign)
    // The multiplication result is shifted by 2 bits for the guard bit and the sticky bit.
    // The adder is sufficient for 76 bits + 1 sign bit because |lhs*rhs<<3| ~ 2^51 is <0.5 ULP when subtracted from 2^76. Note: ULP(1-eps) = 2^-24 while ULP(1+eps) = 2^-23.
    logic [76:0] multiplier_lhs, multiplier_rhs, multiplier_addend, fma_result;
    logic [76:0] mlhs, mrhs, maddend;
    logic is_subtract, is_sub;
    always_ff @(posedge clk) begin
        multiplier_lhs    <= mlhs;
        multiplier_rhs    <= mrhs;
        multiplier_addend <= maddend;
        is_subtract <= is_sub;
        fma_result <= is_subtract ? multiplier_lhs * multiplier_rhs - multiplier_addend
                                  : multiplier_lhs * multiplier_rhs + multiplier_addend;
    end

    FMAStage0 stg0(clk, stg0Out, mullhs, mulrhs, addend, is_sub, mlhs, mrhs, maddend);
    FMAStage1 stg1(clk, stg0Out, stg1Out);
    FMAStage2 stg2(clk, stg1Out, stg2Out, fma_result);
    FMAStage3 stg3(clk, stg2Out, stg3Out);
    FMAStage4 stg4(clk, stg3Out, result);
endmodule

module FMAStage0(
    input logic clk,
    output FMAStage1RegPath stg0Out,
    input logic [31:0] mullhs,
    input logic [31:0] mulrhs,
    input logic [31:0] addend,
    output logic is_subtract,
    output logic [76:0] mlhs,
    output logic [76:0] mrhs,
    output logic [76:0] maddend
);
    wire       mullhs_sign = mullhs[31];
    wire       mulrhs_sign = mulrhs[31];
    wire       addend_sign = addend[31];
    wire [7:0] mullhs_expo = mullhs[30:23];
    wire [7:0] mulrhs_expo = mulrhs[30:23];
    wire [7:0] addend_expo = addend[30:23];
    wire[22:0] mullhs_mant = mullhs[22:0];
    wire[22:0] mulrhs_mant = mulrhs[22:0];
    wire[22:0] addend_mant = addend[22:0];
    assign is_subtract = mullhs_sign ^ mulrhs_sign ^ addend_sign;

    // NaN handling
    wire mullhs_is_zero = mullhs_expo == 8'h00 & mullhs_mant == 0;
    wire mulrhs_is_zero = mulrhs_expo == 8'h00 & mulrhs_mant == 0;
    wire addend_is_zero = addend_expo == 8'h00 & addend_mant == 0;
    wire mullhs_is_inf  = mullhs_expo == 8'hff & mullhs_mant == 0;
    wire mulrhs_is_inf  = mulrhs_expo == 8'hff & mulrhs_mant == 0;
    wire addend_is_inf  = addend_expo == 8'hff & addend_mant == 0;
    wire mullhs_is_nan  = mullhs_expo == 8'hff & mullhs_mant != 0;
    wire mulrhs_is_nan  = mulrhs_expo == 8'hff & mulrhs_mant != 0;
    wire addend_is_nan  = addend_expo == 8'hff & addend_mant != 0;
    wire result_is_nan  = mullhs_is_nan | mulrhs_is_nan | addend_is_nan // One of the input is NaN
                          | (mullhs_is_zero & mulrhs_is_inf) | (mullhs_is_inf & mulrhs_is_zero) // Inf * Zero
                          | (is_subtract & (mullhs_is_inf | mulrhs_is_inf) & addend_is_inf); // Inf - Inf
    //wire[31:0]      nan = mullhs_is_nan ? mullhs | 32'h00400000 : mulrhs_is_nan ? mulrhs | 32'h00400000 : addend_is_nan ? addend | 32'h00400000 : 32'hffc00000; // qNan
    wire[31:0]      nan = 32'h7fc00000;

    // Inf handling
    wire result_is_inf  = addend_is_inf | mullhs_is_inf | mulrhs_is_inf;
    wire prop_inf_sign  = addend_is_inf ? addend_sign : mullhs_sign ^ mulrhs_sign;
    wire mul_sign       = mullhs_sign ^ mulrhs_sign;

    wire [9:0] v_mullhs_expo = { 2'b0, mullhs_expo == 8'h00 ? 8'h01 : mullhs_expo };
    wire [9:0] v_mulrhs_expo = { 2'b0, mulrhs_expo == 8'h00 ? 8'h01 : mulrhs_expo };
    wire [9:0] v_addend_expo = { 2'b0, addend_expo == 8'h00 ? 8'h01 : addend_expo };
    wire [9:0] mulres_expo   = v_mullhs_expo + v_mulrhs_expo - 127;
    wire [9:0] addend_shift  = v_addend_expo - mulres_expo + 23;
    wire       res_is_addend = ($signed(addend_shift) > 49 | mullhs_is_zero | mulrhs_is_zero) & !addend_is_zero; // |lhs*rhs| < 0.5ULP(|addend|-eps); assuming round to nearest, result is equal to the addend.
    wire       addend_sticky = $signed(addend_shift) >=  0 ? 1'b0 :
                               $signed(addend_shift) < -26 ? { addend_expo != 8'h00, addend_mant } != 0
                                                           : { addend_expo != 8'h00, addend_mant } << (10'd26 + addend_shift) != 24'h000000; // shifted out part of { mantissa(24bit), guard(1bit), round(1bit) } >> -addend_shift
    assign maddend = { 1'b0, { addend_expo != 8'h00, addend_mant, 2'b00, 49'b0 } >> (10'd49 - addend_shift), addend_sticky }; // The 1'b0 is the sign bit. The 2'b0 are the gaurd bit and the round bit.
    assign mlhs    = { 51'b0, mullhs_expo != 8'h00, mullhs_mant, 2'b0 }; // lhs_expo != 8'h00 is the hidden bit of a normalized number
    assign mrhs    = { 52'b0, mulrhs_expo != 8'h00, mulrhs_mant, 1'b0 }; // rhs_expo != 8'h00 is the hidden bit of a normalized number

    assign stg0Out = {mulres_expo, result_is_inf, result_is_nan,
                      res_is_addend, mul_sign, prop_inf_sign, addend_sign, is_subtract, nan, addend};
endmodule

module FMAStage1(
    input logic clk,
    input FMAStage1RegPath stg1In,
    output FMAStage2RegPath stg1Out
);
    FMAStage1RegPath pipeReg;
    always_ff @(posedge clk) begin
        pipeReg <= stg1In; 
    end
    assign stg1Out = pipeReg;
endmodule

module FMAStage2(
    input logic clk,
    input FMAStage2RegPath stg2In,
    output FMAStage3RegPath stg2Out,
    input logic [76:0] fma_result
);
    FMAStage2RegPath pipeReg;
    always_ff @(posedge clk) begin
        pipeReg <= stg2In; 
    end

    wire       mul_sign   = pipeReg.mul_sign;
    wire       res_is_zero     = fma_result == 77'h0;
    wire       res_is_negative = fma_result[76];
    wire[75:0] abs_fma_result  = res_is_negative ? -fma_result[75:0] : fma_result[75:0];
    wire       result_sign     = mul_sign ^ res_is_negative;
    
    assign stg2Out = {abs_fma_result, pipeReg.mulres_expo, res_is_negative, pipeReg.result_is_inf,
                      pipeReg.result_is_nan, res_is_zero, pipeReg.res_is_addend, result_sign,
                      pipeReg.prop_inf_sign, pipeReg.addend_sign, pipeReg.is_subtract, pipeReg.nan, pipeReg.addend};
endmodule

module FMAStage3(
    input logic clk,
    input FMAStage3RegPath stg3In,
    output FMAStage4RegPath stg3Out
);
    function automatic [6:0] leading_zeros_count;
        input[75:0] x;
        for(leading_zeros_count = 0; leading_zeros_count <= 76; leading_zeros_count = leading_zeros_count + 1)
            if(x[75-leading_zeros_count]) break;
    endfunction
    
    FMAStage3RegPath pipeReg;
    always_ff @(posedge clk) begin
        pipeReg <= stg3In; 
    end
    wire[75:0] abs_fma_result  = pipeReg.abs_fma_result;
    wire [9:0] mulres_expo     = pipeReg.mulres_expo;

    wire [7:0] leading_zeros   = { 1'b0, leading_zeros_count(abs_fma_result) }; // 0 <= leading_sign_bits <= 74 if !res_is_zero
    wire [9:0] virtual_expo    = mulres_expo - { 2'b00, leading_zeros } + 26; // There are 26 bits above lhs*rhs<<3, assuming no carryover occurs in lhs*rhs.
    wire       subnormal       = $signed(virtual_expo) <= 0;
    wire [7:0] fmares_shift    = subnormal ? 26 - mulres_expo[7:0] // There are 3 bits below lhs*rhs<<3, and 23 bits will be lost due to rounding, assuming no carryover occurs in lhs*rhs.
                                           : 51 - leading_zeros;   // (75 - addend_sticky(1bit)) - shifter_result(24bit)
    
    assign stg3Out = {abs_fma_result, fmares_shift, virtual_expo, subnormal, pipeReg.res_is_negative, pipeReg.result_is_inf,
                      pipeReg.result_is_nan, pipeReg.res_is_zero, pipeReg.res_is_addend, pipeReg.result_sign,
                      pipeReg.prop_inf_sign, pipeReg.addend_sign, pipeReg.is_subtract, pipeReg.nan, pipeReg.addend};
endmodule

module FMAStage4(
    input logic clk,
    input FMAStage4RegPath stg4In,
    output logic [31:0] result
);
    FMAStage4RegPath pipeReg;
    always_ff @(posedge clk) begin
        pipeReg <= stg4In; 
    end
    wire[75:0] abs_fma_result  = pipeReg.abs_fma_result;
    wire [7:0] fmares_shift    = pipeReg.fmares_shift;
    wire [9:0] virtual_expo    = pipeReg.virtual_expo;
    wire[31:0] nan             = pipeReg.nan;
    wire[31:0] addend          = pipeReg.addend;
    wire res_is_negative       = pipeReg.res_is_negative;
    wire result_is_inf         = pipeReg.result_is_inf;
    wire result_is_nan         = pipeReg.result_is_nan;
    wire res_is_zero           = pipeReg.res_is_zero;
    wire res_is_addend         = pipeReg.res_is_addend;
    wire result_sign           = pipeReg.result_sign;
    wire prop_inf_sign         = pipeReg.prop_inf_sign;
    wire addend_sign           = pipeReg.addend_sign;
    wire subnormal             = pipeReg.subnormal;
    wire is_subtract           = pipeReg.is_subtract;
    
    /* verilator lint_off WIDTH */
    wire[23:0] shifter_result = { abs_fma_result, 23'b0 } >> (7'd23 + fmares_shift);
    /* verilator lint_on WIDTH */
    wire       sticky         = abs_fma_result << (76 - fmares_shift) != 0; // the part shifted out above

    wire       round_to_away  = shifter_result[0] & (shifter_result[1] | sticky); // round to nearest, ties to even
    wire       exp_plus_one   = shifter_result >= 24'hffffff; // carry is generated with rounding taken into account

    wire[22:0] result_mant  = shifter_result[23:1] + { 22'h0, round_to_away }; // No special treatment is required even if a overflow occurs since the answer will be 0 and it will be correct.
    wire [7:0] result_expo  = (subnormal ? 8'h00 : virtual_expo[7:0]) + { 7'b0, exp_plus_one };
    wire       res_is_inf   = result_is_inf | $signed(virtual_expo) >= 255;
    wire[31:0] inf          = { result_is_inf ? prop_inf_sign : result_sign, 8'hff, 23'h0 };
    wire[31:0] zero         = { is_subtract ? 1'b0 : addend_sign, 8'h00, 23'h0 };

    wire[31:0] final_result = res_is_inf    ? inf    :
                              res_is_addend ? addend :
                              res_is_zero   ? zero   : { result_sign, result_expo, result_mant };
    assign result = result_is_nan ? nan : final_result;
endmodule
