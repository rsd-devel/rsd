
module FP32DivSqrter(
input
    logic clk, rst,
    logic [31:0] input_lhs, 
    logic [31:0] input_rhs,
    logic input_is_divide, 
    logic [2:0] input_round_mode,
    logic req, 
output
    logic [31:0] result,
    logic [4:0] fflags,
    logic finished
);

    function round_to_away;
        input[2:0] round_mode;
        input      sign;
        input      last_place;
        input      guard_bit;
        input      sticky_bit;
        input      reminder_is_positive;
        input      reminder_is_zero;

        case(round_mode)
            3'b000:  round_to_away = guard_bit & (sticky_bit | reminder_is_positive | (reminder_is_zero & last_place)); // round to nearest, ties to even
            3'b100:  round_to_away = guard_bit & (sticky_bit | reminder_is_positive | reminder_is_zero);                // round to nearest, ties to away
            3'b010:  round_to_away = sign & (guard_bit | sticky_bit | reminder_is_positive);  // round downward
            3'b011:  round_to_away = !sign & (guard_bit | sticky_bit | reminder_is_positive); // round upward
            default: round_to_away = 0; // round towards zero
        endcase
    endfunction

    function[2:0] srt_table;
        input[5:0] rem;
        input[3:0] div;

        reg[5:0] th12;
        reg[5:0] th01;
        th12 = div < 1 ? 6 : div < 2 ? 7 : div < 4 ? 8 : div < 5 ? 9 : div < 6 ? 10 : 11;
        th01 =               div < 2 ? 2 :                             div < 6 ?  3 :  4;

            if($signed(rem) < $signed(-th12)) srt_table = -2;
        else if($signed(rem) < $signed(-th01)) srt_table = -1;
        else if($signed(rem) < $signed( th01)) srt_table =  0;
        else if($signed(rem) < $signed( th12)) srt_table =  1;
        else                                   srt_table =  2;
    endfunction

    reg [31:0] lhs;
    reg [31:0] rhs;
    reg        is_divide;
    reg  [2:0] round_mode;

    function [9:0] leading_zeros_count;
        input[22:0] x;
        for(leading_zeros_count = 0; leading_zeros_count <= 22; leading_zeros_count = leading_zeros_count + 1)
            if(x[22-leading_zeros_count]) break;
    endfunction

    wire       lhs_sign = lhs[31];
    wire       rhs_sign = rhs[31];
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
    wire lhs_is_snan = lhs_is_nan & lhs_mant[22] == 0;
    wire rhs_is_snan = rhs_is_nan & rhs_mant[22] == 0;
    wire lhs_is_neg  = !lhs_is_nan & lhs_sign & lhs != 32'h80000000;
    wire res_is_nan  = is_divide ? lhs_is_nan | rhs_is_nan | (lhs_is_zero & rhs_is_zero) | (lhs_is_inf & rhs_is_inf)
                                 : lhs_is_nan | lhs_is_neg;
    // === About handling NaN ===
    // x86 returns the following qNaN:
    //  mullhs_is_nan ? mullhs | 32'h00400000 :
    //  mulrhs_is_nan ? mulrhs | 32'h00400000 :
    //  addend_is_nan ? addend | 32'h00400000 : 32'hffc00000
    // RISC-V always returns canonical NaN (32'h7fc00000).
    // --- The RISC-V Instruction Set Manual 20240411 Volume I p.114
    wire[31:0]  nan  = 32'h7fc00000;
    wire invalid_operation = is_divide ? lhs_is_snan | rhs_is_snan | (lhs_is_zero & rhs_is_zero) | (lhs_is_inf & rhs_is_inf)
                                       : lhs_is_snan | lhs_is_neg;

    // Preparation
    wire       result_sign  = is_divide ? lhs_sign ^ rhs_sign : lhs_sign;
    wire [9:0] v_lhs_expo   = lhs_expo == 0 ? -leading_zeros_count(lhs_mant) : { 2'b0, lhs_expo }; // biased virtual exponent (ignores subnormals)
    wire [9:0] v_rhs_expo   = rhs_expo == 0 ? -leading_zeros_count(rhs_mant) : { 2'b0, rhs_expo }; // biased virtual exponent (ignores subnormals)
    wire[23:0] v_lhs_mant_w = lhs_expo == 0 ? { lhs_mant, 1'b0 } << leading_zeros_count(lhs_mant) : { 1'b1, lhs_mant };
    wire[23:0] v_rhs_mant_w = rhs_expo == 0 ? { rhs_mant, 1'b0 } << leading_zeros_count(rhs_mant) : { 1'b1, rhs_mant };
    reg [23:0] v_lhs_mant, v_rhs_mant;
    wire dividend_normalize = v_lhs_mant < v_rhs_mant;
    wire [9:0] virtual_expo_w = v_lhs_expo - v_rhs_expo + 127 - { 8'h0, dividend_normalize }; // new biased virtual exponent (ignores subnormals)
    wire       subnormal_w  = is_divide & $signed(virtual_expo_w) <= 0;

    // The SRT loop. rem needs 27 bits. 24(mantissa)+2(x8/3,SRT)+1(sign)
    wire[26:0] rem_0 = is_divide ? dividend_normalize ? { 2'b00, v_lhs_mant, 1'b0 } : { 3'b000, v_lhs_mant }
                                 : v_lhs_expo[0] ? { 2'b0, v_lhs_mant_w, 1'b0 } - 27'h1e40000 : { 1'b0, v_lhs_mant_w, 2'b0 } - 27'h2400000; // 2 * (x - 1.375^2 or 1.5^2)
    wire[25:0] quo_0 = is_divide ? 26'h0
                                 : v_lhs_expo[0] ? 26'h1600000 : 26'h1800000; // magical initial guess: 1.375 or 1.5; this avoids SRT-table defects at ([-4.5,-4-11/36], 1.5) and ([-4,-4+1/144], 1.25)

    reg  [3:0] stage;
    reg [26:0] rem;
    reg [25:0] quo;
    reg  [9:0] virtual_expo;
    reg        subnormal;

    reg[3:0] div;
    reg[2:0] q;
    always@(posedge clk) begin
        if (rst) begin
            lhs <= '0;
            rhs <= '0;
            stage <= '0;
            rem <= '0;
            quo <= '0;
            v_lhs_mant <= '0;
            v_rhs_mant <= '0;
        end
        else if (stage == 13) begin
            if (req) begin
                lhs <= input_lhs;
                rhs <= input_rhs;
                is_divide <= input_is_divide;
                round_mode <= input_round_mode;
                stage <= input_is_divide ? 14 : 15;
            end
        end else if (stage == 14) begin
            v_lhs_mant <= v_lhs_mant_w;
            v_rhs_mant <= v_rhs_mant_w;
            stage <= 15;
        end else if (stage == 15) begin
            rem <= rem_0;
            quo <= quo_0;
            stage <= is_divide ? 0 : 1;
            virtual_expo <= virtual_expo_w;
            subnormal <= subnormal_w;
        end else begin
            div = is_divide ? { 1'b0, v_rhs_mant[22:20] }
                                     : { quo[25], quo[23:21] };
            q = srt_table( rem[26:21], div );
            case(q)
            3'b010: rem <= is_divide ? (rem << 2) - { v_rhs_mant, 3'b000 }
                                     : (rem << 2) - { quo[24:0], 2'b00 } - (27'd4 << (24-stage*2));
            3'b001: rem <= is_divide ? (rem << 2) - { 1'b0, v_rhs_mant, 2'b00 }
                                     : (rem << 2) - { quo, 1'b0 } - (27'd1 << (24-stage*2));
            3'b111: rem <= is_divide ? (rem << 2) + { 1'b0, v_rhs_mant, 2'b00 }
                                     : (rem << 2) + { quo, 1'b0 } - (27'd1 << (24-stage*2));
            3'b110: rem <= is_divide ? (rem << 2) + { v_rhs_mant, 3'b000 }
                                     : (rem << 2) + { quo[24:0], 2'b00 } - (27'd4 << (24-stage*2));
            default: rem <= rem << 2;
            endcase
            quo <= quo + ({ {23{q[2]}}, q } << (24-stage*2));
            stage <= stage + 1;
        end
    end
    assign finished = stage == 13; // Here, quo has a <1/3ULP error.

    wire[47:0] before_round = subnormal ? { 1'b1, quo[23:0], 23'h0 } >> -virtual_expo : { quo[23:0], 24'h0 };
    wire       round_away   = round_to_away(round_mode, result_sign, before_round[25], before_round[24], before_round[23:0] != 0, $signed(rem) > 0, rem == 0);
    wire       round_fall   = round_mode == 2 ? !result_sign & before_round[24:0] == 0 & $signed(rem) < 0 : // ronud downward
                              round_mode == 3 ? result_sign & before_round[24:0] == 0 & $signed(rem) < 0 : // ronud upward
                              round_mode == 1 ? before_round[24:0] == 0 & $signed(rem) < 0 // round towards zero
                                              : 0;
    wire       exp_plus_one = before_round[47:25] == 23'h7fffff & round_away;
    // Since dividend is normalized, situations where before_round[24:0] == 0 & $signed(rem) < 0 do not happen; thus, `exp_minus_one' is always zero.
    // wire   exp_minus_one = before_round[47:25] == 23'h000000 & round_fall;
    wire[22:0] result_mant  = before_round[47:25] + { 22'h0, round_away } - { 22'h0, round_fall }; // No special treatment is required even if a overflow occurs since the answer will be correct.
    wire [7:0] result_expo  = is_divide ? (subnormal ? 8'h00 : virtual_expo[7:0]) + { 7'h0, exp_plus_one }
                                        : v_lhs_expo[8:1] + { 7'b0, v_lhs_expo[0] } + 63 + { 7'h0, exp_plus_one };

    // Treat p-127 as a normal for the underflow flag (rounding with unbounded exponent)
    wire       u_round_away = round_to_away(round_mode, result_sign, quo[1], quo[0], 1'b0, $signed(rem) > 0, rem == 0);
    wire     u_exp_plus_one = before_round[47:24] == 24'hffffff & u_round_away;

    // Special cases
    wire       res_is_huge  = is_divide & $signed(virtual_expo) >= 255;
    wire       res_is_tiny  = is_divide & !lhs_is_zero & !rhs_is_inf & $signed(virtual_expo) <= -24;
    wire       res_is_inf   = is_divide ? lhs_is_inf | rhs_is_zero
                                        : lhs_is_inf;
    wire       res_is_zero  = is_divide ? lhs_is_zero | rhs_is_inf
                                        : lhs_is_zero;
    wire       dir_is_away  = (round_mode == 2 & result_sign) | (round_mode == 3 & !result_sign);
    wire       huge_is_inf  = round_mode == 0 | round_mode == 4 | dir_is_away;

    wire[31:0] huge         = huge_is_inf ? { result_sign, 8'hff, 23'h0 } : { result_sign, 8'hfe, 23'h7fffff };
    wire[31:0] tiny         = dir_is_away ? { result_sign, 8'h00, 23'h1 } : { result_sign, 8'h00, 23'h0 };
    wire[31:0] inf          = { result_sign, 8'hff, 23'h0 };
    wire[31:0] zero         = { result_sign, 8'h00, 23'h0 };

    // Final result
    assign result = res_is_nan  ? nan  :
                    res_is_inf  ? inf  :
                    res_is_huge ? huge :
                    res_is_tiny ? tiny :
                    res_is_zero ? zero : { result_sign, result_expo, result_mant };
    // Exception flags
    wire divide_by_zero     = is_divide & !res_is_nan & !lhs_is_inf & rhs_is_zero;
    wire overflow           = is_divide & !res_is_nan & !lhs_is_inf & !rhs_is_zero & (res_is_huge | (virtual_expo == 254 & exp_plus_one));
    wire inexact            = !res_is_nan & !(is_divide ? lhs_is_zero | lhs_is_inf | rhs_is_zero | rhs_is_inf : lhs_is_zero) & (overflow | res_is_tiny | before_round[24:0] != 0 | rem != 0);
    // === About underflow (UF) flag
    // RISC-V sets the UF flag when the absolute value of the result after rounding is less than FLT_MIN and the result is inexact. (same as x86)
    // --- The RISC-V Instruction Set Manual 20240411 Volume I p.114
    wire underflow          = inexact & subnormal & !u_exp_plus_one;
    //                NV                 DZ              OF        UF         NX
    assign fflags = { invalid_operation, divide_by_zero, overflow, underflow, inexact };
endmodule
