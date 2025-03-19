
import FPUTypes::*;

module FP32PipelinedFMA(
input
    logic clk,
    logic [31:0] mullhs, 
    logic [31:0] mulrhs,
    logic [31:0] addend, 
    logic [2:0] round_mode,
output
    logic [31:0] result,
    logic [4:0] fflags
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

    FMAStage0 stg0(clk, stg0Out, mullhs, mulrhs, addend, round_mode, is_sub, mlhs, mrhs, maddend);
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
    input logic [2:0] round_mode,
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

    assign is_subtract     = mullhs_sign ^ mulrhs_sign ^ addend_sign;

    // NaN handling
    wire mullhs_is_zero    = mullhs_expo == 8'h00 & mullhs_mant == 0;
    wire mulrhs_is_zero    = mulrhs_expo == 8'h00 & mulrhs_mant == 0;
    wire addend_is_zero    = addend_expo == 8'h00 & addend_mant == 0;
    wire mullhs_is_inf     = mullhs_expo == 8'hff & mullhs_mant == 0;
    wire mulrhs_is_inf     = mulrhs_expo == 8'hff & mulrhs_mant == 0;
    wire addend_is_inf     = addend_expo == 8'hff & addend_mant == 0;
    wire mullhs_is_nan     = mullhs_expo == 8'hff & mullhs_mant != 0;
    wire mulrhs_is_nan     = mulrhs_expo == 8'hff & mulrhs_mant != 0;
    wire addend_is_nan     = addend_expo == 8'hff & addend_mant != 0;
    wire mullhs_is_snan    = mullhs_is_nan & mullhs_mant[22] == 0;
    wire mulrhs_is_snan    = mulrhs_is_nan & mulrhs_mant[22] == 0;
    wire addend_is_snan    = addend_is_nan & addend_mant[22] == 0;
    wire mulres_is_inf     = (mullhs_is_inf & !mulrhs_is_nan) | (!mullhs_is_nan & mulrhs_is_inf); 
    wire mulres_is_zero    = mullhs_is_zero | mulrhs_is_zero;
    wire res_is_addend    = mulres_is_zero & !addend_is_zero;
    // === About setting invalid operation (NV) flag ===
    // x86 does not set the NV flag on ±0×±∞±qNaN.
    // RISC-V sets the NV flag on ±0×±∞±qNaN.
    // --- The RISC-V Instruction Set Manual 20240411 Volume I p.116
    wire invalid_operation = mullhs_is_snan | mulrhs_is_snan | addend_is_snan // One of the input values is sNaN
                             | (mullhs_is_zero & mulrhs_is_inf) | (mullhs_is_inf & mulrhs_is_zero) // Inf * Zero
                             | (is_subtract & mulres_is_inf & addend_is_inf); // Inf - Inf
    wire result_is_nan     = mullhs_is_nan | mulrhs_is_nan | addend_is_nan | invalid_operation; 
    // === About handling NaN ===
    // x86 returns the following qNaN:
    //  mullhs_is_nan ? mullhs | 32'h00400000 :
    //  mulrhs_is_nan ? mulrhs | 32'h00400000 :
    //  addend_is_nan ? addend | 32'h00400000 : 32'hffc00000
    // RISC-V always returns canonical NaN (32'h7fc00000).
    // --- The RISC-V Instruction Set Manual 20240411 Volume I p.114
    wire[31:0] nan         = 32'h7fc00000;

    // Inf handling
    wire res_is_inf = addend_is_inf | mullhs_is_inf | mulrhs_is_inf;
    wire mul_sign       = mullhs_sign ^ mulrhs_sign;
    wire inf_sign   = addend_is_inf ? addend_sign : mul_sign;

    // Main path (including subnormal handling)
    wire [9:0] v_mullhs_expo  = { 2'b0, mullhs_expo == 8'h00 ? 8'h01 : mullhs_expo };
    wire [9:0] v_mulrhs_expo  = { 2'b0, mulrhs_expo == 8'h00 ? 8'h01 : mulrhs_expo };
    wire [9:0] v_addend_expo  = { 2'b0, addend_expo == 8'h00 ? 8'h01 : addend_expo };
    wire[23:0] v_mullhs_mant  = { mullhs_expo != 8'h00, mullhs_mant };
    wire[23:0] v_mulrhs_mant  = { mulrhs_expo != 8'h00, mulrhs_mant };
    wire[23:0] v_addend_mant  = { addend_expo != 8'h00, addend_mant };
    wire [9:0] v_fmares_expo  = v_mullhs_expo + v_mulrhs_expo - 127 + 26; // See below: There are 26 bits above lhs*rhs<<3, assuming no carryover occurs in lhs*rhs.
    wire [9:0] addend_shift   = v_fmares_expo - v_addend_expo;
    wire[74:0] shifted_addend = { v_addend_mant, 2'b00, 49'b0 } >> addend_shift; // The 2'b00 are the guard bit and the round bit.
    wire       addend_sticky  = $signed(addend_shift) > 75 ? v_addend_mant != 0
                                                           : v_addend_mant << (10'd75 - addend_shift) != 24'h000000; // the part shifted out above
    // Special cases
    wire       mulres_is_tiny   = $signed(addend_shift) < 0 & !mulres_is_zero & !addend_is_zero; // |mullhs*mulrhs| < 0.5ULP(|addend|-eps)
    wire       res_is_tiny      = $signed(addend_shift) < 0 & !mulres_is_zero & addend_is_zero; // |mullhs*mulrhs+addend| < 0.5FLT_TRUE_MIN

    // Fused-multiply-adder (24bit*24bit<<3+76bit+sign)
    // The multiplication result is shifted by 3 bits for the guard bit, the round bit, and the sticky bit.
    // The adder is sufficient for 76 bits + 1 sign bit because |lhs*rhs<<3| < 2^51 is <0.5 ULP when subtracted from 2^76. Note: ULP(1-eps) = 2^-24 while ULP(1+eps) = 2^-23.
    assign mlhs    = { 51'b0, v_mullhs_mant, 2'b0 };
    assign mrhs    = { 52'b0, v_mulrhs_mant, 1'b0 };
    assign maddend = { 1'b0, shifted_addend, addend_sticky };
    assign stg0Out = {v_fmares_expo, res_is_inf, result_is_nan,
                      res_is_addend, mul_sign, inf_sign, addend_sign, is_subtract, nan, addend,
                      mulres_is_tiny, res_is_tiny, invalid_operation, round_mode};
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
    
    assign stg2Out = {abs_fma_result, pipeReg.mulres_expo, pipeReg.result_is_inf,
                      pipeReg.result_is_nan, res_is_zero, pipeReg.res_is_addend, result_sign,
                      pipeReg.prop_inf_sign, pipeReg.addend_sign, pipeReg.is_subtract, pipeReg.nan, pipeReg.addend,
                      pipeReg.mulres_is_tiny, pipeReg.res_is_tiny, pipeReg.invalid_operation, pipeReg.round_mode};
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

    wire [6:0] leading_zeros   = leading_zeros_count(abs_fma_result); // 0 <= leading_sign_bits <= 74 if !res_is_zero
    wire [9:0] virtual_expo    = mulres_expo - { 3'b00, leading_zeros }; // There are 26 bits above lhs*rhs<<3, assuming no carryover occurs in lhs*rhs.
    wire       subnormal       = $signed(virtual_expo) <= 0;
    wire [6:0] fmares_shift    = subnormal ? mulres_expo[6:0] // There are 3 bits below lhs*rhs<<3, and 23 bits will be lost due to rounding, assuming no carryover occurs in lhs*rhs.
                                           : leading_zeros + 1;   // (75 - addend_sticky(1bit)) - shifter_result(24bit)
    
    assign stg3Out = {abs_fma_result, fmares_shift, virtual_expo, subnormal, pipeReg.result_is_inf,
                      pipeReg.result_is_nan, pipeReg.res_is_zero, pipeReg.res_is_addend, pipeReg.result_sign,
                      pipeReg.prop_inf_sign, pipeReg.addend_sign, pipeReg.is_subtract, pipeReg.nan, pipeReg.addend,
                      pipeReg.mulres_is_tiny, pipeReg.res_is_tiny, pipeReg.invalid_operation, pipeReg.round_mode};
endmodule

module FMAStage4(
    input logic clk,
    input FMAStage4RegPath stg4In,
    output logic [31:0] result,
    output logic [4:0] fflags
);
    function round_to_away;
        input sign;
        input last_place;
        input guard_bit;
        input sticky_bit;
        input[2:0] round_mode;

        case(round_mode)
            3'b000:  round_to_away = guard_bit & (last_place | sticky_bit); // round to nearest, ties to even
            3'b100:  round_to_away = guard_bit;                             // round to nearest, ties to away
            3'b010:  round_to_away = sign & (guard_bit | sticky_bit);       // round downward
            3'b011:  round_to_away = !sign & (guard_bit | sticky_bit);      // round upward
            default: round_to_away = 0;                                     // round towards zero
        endcase
    endfunction

    FMAStage4RegPath pipeReg;
    always_ff @(posedge clk) begin
        pipeReg <= stg4In; 
    end

    wire[75:0] abs_fma_result  = pipeReg.abs_fma_result;
    wire [6:0] fmares_shift    = pipeReg.fmares_shift;
    wire [9:0] virtual_expo    = pipeReg.virtual_expo;
    wire[31:0] nan             = pipeReg.nan;
    wire[31:0] addend          = pipeReg.addend;
    wire result_is_inf         = pipeReg.result_is_inf;
    wire result_is_nan         = pipeReg.result_is_nan;
    wire res_is_zero           = pipeReg.res_is_zero;
    wire res_is_addend         = pipeReg.res_is_addend;
    wire result_sign           = pipeReg.result_sign;
    wire prop_inf_sign         = pipeReg.prop_inf_sign;
    wire addend_sign           = pipeReg.addend_sign;
    wire subnormal             = pipeReg.subnormal;
    wire is_subtract           = pipeReg.is_subtract;
    wire mulres_is_tiny        = pipeReg.mulres_is_tiny;
    wire res_is_tiny           = pipeReg.res_is_tiny;
    wire invalid_operation     = pipeReg.invalid_operation;
    wire [2:0] round_mode      = pipeReg.round_mode;
    

    // Normalize and rounding decision
    wire[24:0] shifter_result;
    wire       sticky;
    NormalizeShifter shifter (
        .fmares_shift (fmares_shift),
        .ifma_result (abs_fma_result),
        .shifter_result (shifter_result),
        .sticky (sticky)
    );

    wire       round_away      = round_to_away(result_sign, shifter_result[2], shifter_result[1], shifter_result[0] | sticky, round_mode);
    wire       exp_plus_one    = shifter_result >= 25'h1fffffc & round_away; // carry is generated with rounding taken into account
    // Treat p-127 as a normal for the underflow flag (rounding with unbounded exponent)
    wire       u_round_away    = round_to_away(result_sign, shifter_result[1], shifter_result[0], sticky, round_mode);
    wire       u_exp_plus_one  = shifter_result >= 25'h1fffffe & u_round_away; // 0x1.fffffep-127 <= |mullhs*mulrhs+addend| < 0x1p-126 and the after rounding result become a normal number, not raising the underflow flag.

    wire[22:0] result_mant = shifter_result[24:2] + { 22'h0, round_away }; // No special treatment is required even if an overflow occurs since the answer will be 0 and it will be correct.
    wire [7:0] result_expo = (subnormal ? 8'h00 : virtual_expo[7:0]) + { 7'b0, exp_plus_one };

    // Special cases
    wire       res_is_huge      = $signed(virtual_expo) >= 255;
    wire       dir_is_away      = (round_mode == 2 & result_sign) | (round_mode == 3 & !result_sign);
    wire       huge_is_inf      = round_mode == 0 | round_mode == 4 | dir_is_away;

    wire[31:0] addend_plus_tiny = round_mode == 1                &  is_subtract ? addend - 1 :
                                  round_mode == 2 & !addend_sign &  is_subtract ? addend - 1 :
                                  round_mode == 3 &  addend_sign &  is_subtract ? addend - 1 :
                                  round_mode == 2 &  addend_sign & !is_subtract ? addend + 1 :
                                  round_mode == 3 & !addend_sign & !is_subtract ? addend + 1
                                                                                : addend;
    wire[31:0] huge             = huge_is_inf ? { result_sign, 8'hff, 23'h0 } : { result_sign, 8'hfe, 23'h7fffff };
    wire[31:0] tiny             = dir_is_away ? { result_sign, 8'h00, 23'h1 } : { result_sign, 8'h00, 23'h0 };
    wire[31:0] zero             = { is_subtract ? round_mode == 2 : addend_sign, 8'h00, 23'h0 };
    wire[31:0] inf  = { prop_inf_sign, 8'hff, 23'h0 };

    // Final result
    assign result = result_is_nan  ? nan              :
                    result_is_inf  ? inf              :
                    res_is_huge    ? huge             :
                    res_is_tiny    ? tiny             :
                    mulres_is_tiny ? addend_plus_tiny :
                    res_is_addend  ? addend           :
                    res_is_zero    ? zero             : { result_sign, result_expo, result_mant };

    // Exception flags
    wire divide_by_zero    = 1'b0;
    wire overflow          = !result_is_nan & !result_is_inf & (mulres_is_tiny ? addend_plus_tiny[30:23] == 8'hff : res_is_huge | (virtual_expo == 254 & exp_plus_one));
    wire inexact           = !result_is_nan & !result_is_inf & (overflow | res_is_tiny | mulres_is_tiny | shifter_result[1] | shifter_result[0] | sticky);
    // === About underflow (UF) flag
    // RISC-V sets the UF flag when the absolute value of the result after rounding is less than FLT_MIN and the result is inexact. (same as x86) 
    // --- The RISC-V Instruction Set Manual 20240411 Volume I p.114
    wire underflow         = inexact & (mulres_is_tiny ? addend[30:23] == 8'h00 | addend_plus_tiny[30:23] == 8'h00 : res_is_tiny | (subnormal & !u_exp_plus_one));
    //                NV                 DZ              OF        UF         NX
    assign fflags = { invalid_operation, divide_by_zero, overflow, underflow, inexact };
endmodule

module NormalizeShifter(input[6:0] fmares_shift, input[75:0] ifma_result, output[24:0] shifter_result, output sticky);
    wire[75:0] shifter1_out = fmares_shift[6] ? { ifma_result[11:0], 64'b0 } : ifma_result[75:0];
    wire[55:0] shifter2_out = fmares_shift[5] ? { shifter1_out[43:0], 12'b0 } : shifter1_out[75:20];
    wire[39:0] shifter3_out = fmares_shift[4] ? shifter2_out[39:0] : shifter2_out[55:16];
    wire[31:0] shifter4_out = fmares_shift[3] ? shifter3_out[31:0] : shifter3_out[39: 8];
    wire[27:0] shifter5_out = fmares_shift[2] ? shifter4_out[27:0] : shifter4_out[31: 4];
    wire[25:0] shifter6_out = fmares_shift[1] ? shifter5_out[25:0] : shifter5_out[27: 2];
    wire[24:0] shifter7_out = fmares_shift[0] ? shifter6_out[24:0] : shifter6_out[25: 1];

    assign sticky =   (!fmares_shift[5] & shifter1_out[19:0] != 0)
                    | (!fmares_shift[4] & shifter2_out[15:0] != 0)
                    | (!fmares_shift[3] & shifter3_out[ 7:0] != 0)
                    | (!fmares_shift[2] & shifter4_out[ 3:0] != 0)
                    | (!fmares_shift[1] & shifter5_out[ 1:0] != 0)
                    | (!fmares_shift[0] & shifter6_out[ 0:0] != 0);
    assign shifter_result = shifter7_out;
endmodule
