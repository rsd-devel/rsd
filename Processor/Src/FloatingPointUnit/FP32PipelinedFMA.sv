// Pipeline types are local to this file so the FMA can be compiled independently of RSD.
package FP32PipelinedFMATypes;
    typedef struct packed {
        logic [2:0] rm;
        logic [9:0] mulres_expo;
        logic result_is_inf;
        logic result_is_nan;
        logic invalid;
        logic res_is_addend;
        logic addend_inexact;
        logic mul_sign;
        logic prop_inf_sign;
        logic addend_sign;
        logic is_subtract;
        logic [31:0] nan;
        logic [31:0] addend;
    } FMAStage1RegPath;

    typedef struct packed {
        logic [2:0] rm;
        logic [9:0] mulres_expo;
        logic result_is_inf;
        logic result_is_nan;
        logic invalid;
        logic res_is_addend;
        logic addend_inexact;
        logic mul_sign;
        logic prop_inf_sign;
        logic addend_sign;
        logic is_subtract;
        logic [31:0] nan;
        logic [31:0] addend;
    } FMAStage2RegPath;

    typedef struct packed {
        logic [2:0] rm;
        logic [75:0] abs_fma_result;
        logic [9:0] mulres_expo;
        logic res_is_negative;
        logic result_is_inf;
        logic result_is_nan;
        logic invalid;
        logic res_is_zero;
        logic result_sign;
        logic prop_inf_sign;
        logic addend_sign;
        logic is_subtract;
        logic [31:0] nan;
    } FMAStage3RegPath;

    typedef struct packed {
        logic [2:0] rm;
        logic [75:0] abs_fma_result;
        logic signed [9:0] fmares_shift;
        logic [9:0] virtual_expo;
        logic subnormal;
        logic round_sticky;
        logic result_is_inf;
        logic result_is_nan;
        logic invalid;
        logic res_is_zero;
        logic result_sign;
        logic prop_inf_sign;
        logic addend_sign;
        logic is_subtract;
        logic [31:0] nan;
    } FMAStage4RegPath;
endpackage

import FP32PipelinedFMATypes::*;
module FP32PipelinedFMA(
    input  logic clk,
    input  logic [31:0] mullhs,
    input  logic [31:0] mulrhs,
    input  logic [31:0] addend,
    input  logic [2:0] rm,
    output logic [31:0] result,
    output FPUTypes::FFlags fflags
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

    FMAStage0 stg0(clk, stg0Out, mullhs, mulrhs, addend, rm, is_sub, mlhs, mrhs, maddend);
    FMAStage1 stg1(clk, stg0Out, stg1Out);
    FMAStage2 stg2(clk, stg1Out, stg2Out, fma_result);
    FMAStage3 stg3(clk, stg2Out, stg3Out);
    FMAStage4 stg4(clk, stg3Out, result, fflags);
endmodule

module FMAStage0(
    input logic clk,
    output FMAStage1RegPath stg0Out,
    input logic [31:0] mullhs,
    input logic [31:0] mulrhs,
    input logic [31:0] addend,
    input logic [2:0] rm,
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
    wire invalid_product = (mullhs_is_zero & mulrhs_is_inf) | (mullhs_is_inf & mulrhs_is_zero);
    // A quiet NaN multiplicand does not make an infinite-sum operation invalid.
    wire invalid_sum = is_subtract & (mullhs_is_inf | mulrhs_is_inf) & addend_is_inf
                       & ~mullhs_is_nan & ~mulrhs_is_nan;
    wire invalid = (mullhs_is_nan & ~mullhs_mant[22]) | (mulrhs_is_nan & ~mulrhs_mant[22])
                   | (addend_is_nan & ~addend_mant[22]) | invalid_product | invalid_sum;
    wire result_is_nan = mullhs_is_nan | mulrhs_is_nan | addend_is_nan | invalid;
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
    wire       res_is_addend = ($signed(addend_shift) > 49 | mullhs_is_zero | mulrhs_is_zero) & !addend_is_zero; // The addend dominates; preserve the tiny product when rounding.
    // A nonzero product below the addend's rounding threshold is still inexact.
    wire       addend_inexact = !mullhs_is_zero & !mulrhs_is_zero;
    wire       addend_sticky = $signed(addend_shift) >=  0 ? 1'b0 :
                               $signed(addend_shift) < -26 ? { addend_expo != 8'h00, addend_mant } != 0
                                                           : { addend_expo != 8'h00, addend_mant } << (10'd26 + addend_shift) != 24'h000000; // shifted out part of { mantissa(24bit), guard(1bit), round(1bit) } >> -addend_shift
    assign maddend = { 1'b0, { addend_expo != 8'h00, addend_mant, 2'b00, 49'b0 } >> (10'd49 - addend_shift), addend_sticky }; // The 1'b0 is the sign bit. The 2'b0 are the gaurd bit and the round bit.
    assign mlhs    = { 51'b0, mullhs_expo != 8'h00, mullhs_mant, 2'b0 }; // lhs_expo != 8'h00 is the hidden bit of a normalized number
    assign mrhs    = { 52'b0, mulrhs_expo != 8'h00, mulrhs_mant, 1'b0 }; // rhs_expo != 8'h00 is the hidden bit of a normalized number

    // The caller resolves dynamic rounding; carry that mode with these operands.
    assign stg0Out = {rm, mulres_expo, result_is_inf, result_is_nan, invalid,
                      res_is_addend, addend_inexact, mul_sign, prop_inf_sign, addend_sign, is_subtract, nan, addend};
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
    wire       res_is_negative = fma_result[76];
    // A dominant addend still moves by one ULP under directed rounding. Rebase
    // it onto the accumulator scale and represent the nonzero product by a
    // signed sticky bit, below half an ULP on either side of a power of two.
    wire [26:0] addend_result = {pipeReg.addend[30:23] != 0, pipeReg.addend[22:0], 3'b0}
                              + (pipeReg.addend_inexact ? (pipeReg.is_subtract ? -27'd1 : 27'd1) : 27'd0);
    wire [9:0] addend_expo = {2'b0, pipeReg.addend[30:23] == 0 ? 8'd1 : pipeReg.addend[30:23]};
    wire [9:0] mulres_expo = pipeReg.res_is_addend ? addend_expo + 23 : pipeReg.mulres_expo;
    wire[75:0] abs_fma_result = pipeReg.res_is_addend ? {49'b0, addend_result} :
                                res_is_negative ? -fma_result[75:0] : fma_result[75:0];
    wire       res_is_zero = abs_fma_result == 0;
    wire       result_sign = pipeReg.res_is_addend ? pipeReg.addend_sign : mul_sign ^ res_is_negative;

    assign stg2Out = {pipeReg.rm, abs_fma_result, mulres_expo, res_is_negative, pipeReg.result_is_inf,
                      pipeReg.result_is_nan, pipeReg.invalid, res_is_zero, result_sign,
                      pipeReg.prop_inf_sign, pipeReg.addend_sign, pipeReg.is_subtract, pipeReg.nan};
endmodule

module FMAStage3(
    input logic clk,
    input FMAStage3RegPath stg3In,
    output FMAStage4RegPath stg3Out
);
    function automatic [6:0] leading_zeros_count;
        input[75:0] x;
        for(leading_zeros_count = 0; leading_zeros_count <= 75; leading_zeros_count = leading_zeros_count + 1)
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
    // Retain two rounding bits: the extra bit also distinguishes tininess
    // rounded at full precision from rounding onto the subnormal grid.
    wire signed [9:0] fmares_shift = subnormal ? 10'sd25 - $signed(mulres_expo)
                                              : 10'sd50 - $signed({2'b00, leading_zeros});
    wire round_sticky = fmares_shift <= 0 ? 1'b0 :
                        fmares_shift >= 76 ? abs_fma_result != 0 :
                        abs_fma_result << (10'sd76 - fmares_shift) != 0;

    assign stg3Out = {pipeReg.rm, abs_fma_result, fmares_shift, virtual_expo, subnormal, round_sticky, pipeReg.result_is_inf,
                      pipeReg.result_is_nan, pipeReg.invalid, pipeReg.res_is_zero, pipeReg.result_sign,
                      pipeReg.prop_inf_sign, pipeReg.addend_sign, pipeReg.is_subtract, pipeReg.nan};
endmodule

module FMAStage4(
    input logic clk,
    input FMAStage4RegPath stg4In,
    output logic [31:0] result,
    output FPUTypes::FFlags fflags
);
    FMAStage4RegPath pipeReg;
    always_ff @(posedge clk) begin
        pipeReg <= stg4In; 
    end
    wire[75:0] abs_fma_result  = pipeReg.abs_fma_result;
    wire signed [9:0] fmares_shift = pipeReg.fmares_shift;
    wire [9:0] virtual_expo    = pipeReg.virtual_expo;
    wire[31:0] nan             = pipeReg.nan;
    wire result_is_inf         = pipeReg.result_is_inf;
    wire result_is_nan         = pipeReg.result_is_nan;
    wire res_is_zero           = pipeReg.res_is_zero;
    wire result_sign           = pipeReg.result_sign;
    wire prop_inf_sign         = pipeReg.prop_inf_sign;
    wire addend_sign           = pipeReg.addend_sign;
    wire subnormal             = pipeReg.subnormal;
    wire is_subtract           = pipeReg.is_subtract;
    
    function automatic logic RoundIncrement(
        input logic [2:0] rm,
        input logic sign, lsb, guard_bit, sticky_bit
    );
        case (rm)
            3'b001: RoundIncrement = 1'b0; // RTZ
            3'b010: RoundIncrement = sign && (guard_bit || sticky_bit); // RDN
            3'b011: RoundIncrement = !sign && (guard_bit || sticky_bit); // RUP
            3'b100: RoundIncrement = guard_bit; // RMM
            default: RoundIncrement = guard_bit && (lsb || sticky_bit); // RNE
        endcase
    endfunction

    wire [25:0] shifter_result = fmares_shift >= 0 ? abs_fma_result >> fmares_shift
                                                   : abs_fma_result << -fmares_shift;
    wire sticky = pipeReg.round_sticky;
    wire discarded_bits = shifter_result[1:0] != 0 || sticky;
    wire round_to_away = RoundIncrement(pipeReg.rm, result_sign,
                                        shifter_result[2], shifter_result[1], shifter_result[0] || sticky);
    wire exp_plus_one = shifter_result[24:2] == 23'h7fffff && round_to_away;
    wire [22:0] result_mant = shifter_result[24:2] + {22'b0, round_to_away};
    wire [7:0] result_expo = (subnormal ? 8'h00 : virtual_expo[7:0]) + {7'b0, exp_plus_one};
    wire overflow = !subnormal && ($signed(virtual_expo) >= 255 ||
                                    (virtual_expo == 254 && exp_plus_one));
    wire overflow_to_inf = pipeReg.rm == 3'b000 || pipeReg.rm == 3'b100 ||
                            (pipeReg.rm == 3'b010 && result_sign) ||
                            (pipeReg.rm == 3'b011 && !result_sign);
    wire [31:0] overflow_result = {result_sign, overflow_to_inf ? 31'h7f800000 : 31'h7f7fffff};
    wire [31:0] inf = {prop_inf_sign, 8'hff, 23'h0};
    // Exact cancellation is negative zero only under RDN; same-sign zeros
    // preserve their sign. Nonzero values rounded to zero use result_sign.
    wire [31:0] zero = {is_subtract ? pipeReg.rm == 3'b010 : addend_sign, 31'b0};
    assign result = result_is_nan ? nan : result_is_inf ? inf : res_is_zero ? zero :
                    overflow ? overflow_result : {result_sign, result_expo, result_mant};

    // At virtual exponent zero, full-precision rounding retains one more bit
    // than the subnormal result. Its carry determines tininess after rounding.
    wire normal_carry = shifter_result[24:1] == 24'hffffff &&
                         RoundIncrement(pipeReg.rm, result_sign, shifter_result[1], shifter_result[0], sticky);
    wire tiny = $signed(virtual_expo) < 0 || (virtual_expo == 0 && !normal_carry);
    wire finite_nonzero = !result_is_nan && !result_is_inf && !res_is_zero;
    assign fflags = '{NV: pipeReg.invalid, DZ: 1'b0,
                      OF: finite_nonzero && overflow,
                      UF: finite_nonzero && tiny && discarded_bits,
                      NX: finite_nonzero && (discarded_bits || overflow)};
endmodule
