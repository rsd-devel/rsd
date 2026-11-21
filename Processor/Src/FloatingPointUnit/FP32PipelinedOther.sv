import OpFormatTypes::*;
import BasicTypes::*;

function automatic [5:0] leading_zeros_count(
    input logic [31:0] x
);
    for(leading_zeros_count = 0; leading_zeros_count <= 31; leading_zeros_count = leading_zeros_count + 1)
        if(x >> (31-leading_zeros_count) != 0) break;
endfunction

module FP32PipelinedOther #(parameter PIPELINE_DEPTH = 5)(
input
    logic clk,
    logic [31:0] lhs,
    logic [31:0] rhs,
    FPU_Code fpuCode,
    Rounding_Mode rm,
output 
    logic [31:0] result,
    FFlags_Path fflags
);
    typedef struct packed {
        logic [31:0] data;
        FFlags_Path fflags;
        logic isI2F;
        logic [3:0] control;
    } FirstRegPath;

    typedef struct packed {
        logic [31:0] result;
        FFlags_Path fflags;
    } PipeRegPath;

    // Stage 1: classify inputs and prepare both conversions before rounding.
    wire lhs_sign = lhs[31];
    wire rhs_sign = rhs[31];
    wire [7:0] lhs_expo = lhs[30:23];
    wire [7:0] rhs_expo = rhs[30:23];
    wire [22:0] lhs_mant = lhs[22:0];
    wire [22:0] rhs_mant = rhs[22:0];
    wire lhs_is_zero = lhs_expo == 8'h00 & lhs_mant == 0;
    wire rhs_is_zero = rhs_expo == 8'h00 & rhs_mant == 0;
    wire lhs_is_inf = lhs_expo == 8'hff & lhs_mant == 0;
    wire rhs_is_inf = rhs_expo == 8'hff & rhs_mant == 0;
    wire lhs_is_nan = lhs_expo == 8'hff & lhs_mant != 0;
    wire rhs_is_nan = rhs_expo == 8'hff & rhs_mant != 0;
    wire lhs_is_snan = lhs_is_nan & lhs_mant[22] == 0;
    wire rhs_is_snan = rhs_is_nan & rhs_mant[22] == 0;
    wire lhs_is_subnormal = lhs_expo == 0 & lhs_mant != 0;
    wire lhs_is_normal = ~(lhs_is_zero | lhs_is_inf | lhs_is_nan | lhs_is_subnormal);
    wire lhs_is_smaller = (lhs < rhs) ^ (lhs_sign | rhs_sign);
    // +0 normally compares as equal to -0
    wire lhs_equal_rhs = (lhs == rhs) | (lhs_is_zero && rhs_is_zero);
    wire fmt_unsigned = fpuCode inside {FC_FCVT_SWU, FC_FCVT_WUS};

    // As in FMA, locate |lhs|-1 for negative inputs without a carry chain.
    wire i2f_sign = fpuCode == FC_FCVT_SW && lhs_sign;
    wire [31:0] i2f_transitions = lhs ^ {i2f_sign, lhs[31:1]};
    wire [5:0] i2f_lzc = leading_zeros_count(i2f_transitions);
    // Keep -1 distinct from zero and leave its late +1 in the significand.
    wire [5:0] i2f_leading_zeros = i2f_sign && i2f_lzc == 6'd32 ? 6'd31 : i2f_lzc;
    wire [31:0] i2f_shifted = lhs << i2f_leading_zeros;

    wire f2i_small = lhs_expo <= 126;
    wire f2i_shift_range = lhs_expo >= 127 && lhs_expo <= 157;
    /* verilator lint_off WIDTH */
    wire [4:0] f2i_shift_amount = 158 - lhs_expo;
    /* verilator lint_on WIDTH */
    wire [54:0] f2i_shifted = {1'b1, lhs_mant, 31'h0} >> f2i_shift_amount;
    // Large exact conversions discard no bits; saturation reports NV only.
    wire f2i_lsb = f2i_shift_range && f2i_shifted[23];
    wire f2i_guard = lhs_expo == 126 || (f2i_shift_range && f2i_shifted[22]);
    wire f2i_small_sticky = (lhs_expo == 0 || lhs_expo == 126) ? |lhs_mant : 1'b1;
    wire f2i_sticky = (f2i_small && f2i_small_sticky) ||
                      (f2i_shift_range && |f2i_shifted[21:0]);
    logic f2i_round_up;
    always_comb begin
        case (rm)
            RM_RNE:  f2i_round_up = f2i_guard & (f2i_lsb | f2i_sticky);
            RM_RTZ:  f2i_round_up = FALSE;
            RM_RDN:  f2i_round_up = (f2i_guard | f2i_sticky) & lhs_sign;
            RM_RUP:  f2i_round_up = (f2i_guard | f2i_sticky) & ~lhs_sign;
            RM_RMM:  f2i_round_up = f2i_guard;
            default: f2i_round_up = FALSE; // RTZ
        endcase
    end

    logic [31:0] f2i_int_result;
    always_comb begin
        if (f2i_small) begin // e < 0
            f2i_int_result = 0;
        end
        else if (f2i_shift_range) begin // 0 <= e <= 30
            f2i_int_result = f2i_shifted[54:23];
        end
        else if (lhs_expo == 158) begin // e = 31
            if (fmt_unsigned) begin
                f2i_int_result = lhs_sign ? 32'h00000000 : {1'b1, lhs_mant, 8'h0};
            end
            else begin
                f2i_int_result = lhs_sign ? 32'h80000000 : 32'h7fffffff;
            end
        end
        else begin // e > 31 (overflow or NaN/Inf)
            if (fmt_unsigned) begin
                f2i_int_result = (~lhs_is_nan & lhs_sign) ? 32'h00000000 : 32'hffffffff;
            end
            else begin
                f2i_int_result = (~lhs_is_nan & lhs_sign) ? 32'h80000000 : 32'h7fffffff;
            end
        end
    end
    wire f2i_negative_unsigned = fmt_unsigned && lhs_sign;
    wire f2i_needs_round = lhs_expo <= 157 && !f2i_negative_unsigned;
    wire [31:0] f2i_prepared = lhs_expo <= 157 && f2i_negative_unsigned ? 32'b0 : f2i_int_result;
    wire f2i_invalid = lhs_expo >= 159 |
        (~fmt_unsigned & lhs_expo == 158 & (~lhs_sign | (lhs_sign & lhs_mant != 0))) |
        (fmt_unsigned & lhs_sign & (lhs_expo >= 127 | f2i_round_up));
    wire f2i_inexact = !f2i_invalid && (f2i_guard | f2i_sticky);

    // I2F data: {significand[23:0], guard, sticky, leadingZeros[5:0]}.
    // Control: I2F {sign, rm[2:0]}, F2I {needsRound, roundUp, sign, 1'b0}.
    // Completed F2I and other operations use zero control and pass through.
    FirstRegPath firstInput;
    always_comb begin
        firstInput = '0;
        unique case(fpuCode)
            FC_SGNJ: begin
                firstInput.data = {rhs_sign, lhs_expo, lhs_mant};
            end
            FC_SGNJN: begin
                firstInput.data = {~rhs_sign, lhs_expo, lhs_mant};
            end
            FC_SGNJX: begin
                firstInput.data = {lhs_sign ^ rhs_sign, lhs_expo, lhs_mant};
            end
            FC_FMIN: begin
                if (lhs_is_nan & rhs_is_nan) begin
                    firstInput.data = 32'h7fc00000;
                end
                else if (lhs_is_nan) begin
                    firstInput.data = rhs;
                end 
                else if (rhs_is_nan) begin
                    firstInput.data = lhs;
                end
                else begin
                    firstInput.data = lhs_is_smaller ? lhs : rhs;
                end
                // update fflags
                if (lhs_is_snan || rhs_is_snan) begin
                    firstInput.fflags.NV = TRUE;
                end
            end
            FC_FMAX: begin
                if (lhs_is_nan & rhs_is_nan) begin
                    firstInput.data = 32'h7fc00000;
                end
                else if (lhs_is_nan) begin
                    firstInput.data = rhs;
                end 
                else if (rhs_is_nan) begin
                    firstInput.data = lhs;
                end
                else begin
                    firstInput.data = lhs_is_smaller ? rhs : lhs;
                end

                if (lhs_is_snan || rhs_is_snan) begin
                    firstInput.fflags.NV = TRUE;
                end
            end
            FC_FMV_WX, FC_FMV_XW: begin
                firstInput.data = lhs;
            end
            FC_FCVT_SW, FC_FCVT_SWU: begin
                firstInput.data = {i2f_shifted[31:8], i2f_shifted[7],
                                   |i2f_shifted[6:0], i2f_leading_zeros};
                firstInput.isI2F = TRUE;
                firstInput.control = {i2f_sign, rm};
            end
            FC_FCVT_WS, FC_FCVT_WUS: begin
                firstInput.data = f2i_prepared;
                firstInput.fflags.NV = f2i_invalid;
                firstInput.fflags.NX = f2i_inexact;
                if (f2i_needs_round) begin
                    firstInput.control = {1'b1, f2i_round_up, lhs_sign, 1'b0};
                end
            end
            FC_FEQ: begin
                if (lhs_is_nan || rhs_is_nan) begin
                    firstInput.data = 0;
                end
                else begin
                    firstInput.data = lhs_equal_rhs;
                end
                // quiet comparsion
                if (lhs_is_snan || rhs_is_snan) begin
                    firstInput.fflags.NV = TRUE;
                end
            end
            FC_FLT: begin
                if (lhs_is_nan || rhs_is_nan) begin
                    firstInput.data = 0;
                    firstInput.fflags.NV = TRUE;
                end
                else begin
                    //flt.s -0, +0 = 0
                    firstInput.data = lhs_is_smaller & ~lhs_equal_rhs;
                end
            end
            FC_FLE: begin
                if (lhs_is_nan || rhs_is_nan) begin
                    firstInput.data = 0;
                    firstInput.fflags.NV = TRUE;
                end
                else begin
                    firstInput.data = lhs_is_smaller | lhs_equal_rhs;
                end
            end
            FC_FCLASS: begin
                firstInput.data = {
                    22'h0, 
                    lhs_is_nan & ~lhs_is_snan,     // quiet NaN
                    lhs_is_snan,                   // signaling NaN
                    ~lhs_sign & lhs_is_inf,        // +inf
                    ~lhs_sign & lhs_is_normal,     // +subnormal
                    ~lhs_sign & lhs_is_subnormal,  // +normal
                    ~lhs_sign & lhs_is_zero,       // +0
                    lhs_sign & lhs_is_zero,        // -0
                    lhs_sign & lhs_is_subnormal,   // -subnormal
                    lhs_sign & lhs_is_normal,      // -normal
                    lhs_sign & lhs_is_inf          // -inf
                };
            end
            default: begin
                firstInput.data = '0;
                firstInput.fflags = '0;
            end

        endcase
    end

    FirstRegPath firstStage;
    generate
        if (PIPELINE_DEPTH >= 3) begin : splitConversion
            always_ff @(posedge clk) begin
                firstStage <= firstInput;
            end
        end
        else begin : directConversion
            assign firstStage = firstInput;
        end
    endgenerate

    // Stage 2: finish the saved conversion; shallow configurations use the
    // same arithmetic with a direct connection across the first boundary.
    wire [23:0] i2f_raw_significand;
    wire i2f_raw_guard, i2f_raw_sticky;
    wire [5:0] i2f_leading_zeros_out;
    assign {i2f_raw_significand, i2f_raw_guard, i2f_raw_sticky, i2f_leading_zeros_out} = firstStage.data;
    wire i2f_result_sign;
    wire [2:0] i2f_rm;
    assign {i2f_result_sign, i2f_rm} = firstStage.control;
    // Zero-fill before inversion leaves |lhs|*2^shift-1 on the negative
    // path. Fold its +1 into rounding, as in FMA's RoundIncrement.
    wire [23:0] i2f_significand = i2f_raw_significand ^ {24{i2f_result_sign}};
    wire i2f_guard = i2f_raw_guard ^ i2f_result_sign;
    wire i2f_tail = i2f_result_sign ? !i2f_raw_sticky : i2f_raw_sticky;
    logic i2f_round_up;
    always_comb begin
        case (i2f_rm)
            RM_RNE: i2f_round_up = i2f_result_sign ? i2f_guard || (i2f_significand[0] && i2f_tail)
                                                  : i2f_guard && (i2f_significand[0] || i2f_tail);
            RM_RTZ: i2f_round_up = i2f_result_sign && i2f_guard && i2f_tail;
            RM_RDN: i2f_round_up = i2f_result_sign;
            RM_RUP: i2f_round_up = i2f_result_sign ? i2f_guard && i2f_tail : i2f_guard || i2f_tail;
            RM_RMM: i2f_round_up = i2f_guard || (i2f_result_sign && i2f_tail);
            default: i2f_round_up = i2f_result_sign && i2f_guard && i2f_tail; // Preserve I2F's RTZ fallback.
        endcase
    end
    wire [24:0] i2f_rounded = {1'b0, i2f_significand} + {24'b0, i2f_round_up};
    wire [7:0] i2f_expo = i2f_leading_zeros_out == 6'd32 ? 8'd0
        : 8'd158 - {2'b0, i2f_leading_zeros_out} + {7'b0, i2f_rounded[24]};
    wire [31:0] i2f_result = {i2f_result_sign, i2f_expo, i2f_rounded[22:0]};

    wire f2i_needs_round_out, f2i_round_up_out, f2i_result_sign;
    // The low control bit is padding for F2I.
    assign {f2i_needs_round_out, f2i_round_up_out, f2i_result_sign} = firstStage.control[3:1];
    wire [31:0] f2i_rounded = firstStage.data + {31'h0, f2i_round_up_out};
    wire [31:0] f2i_signed_result = f2i_result_sign ? -f2i_rounded : f2i_rounded;
    wire [31:0] f2i_result = f2i_needs_round_out ? f2i_signed_result : firstStage.data;
    PipeRegPath nextResult;
    always_comb begin
        nextResult = {f2i_result, firstStage.fflags};
        if (firstStage.isI2F) begin
            nextResult.result = i2f_result;
            nextResult.fflags = '0;
            nextResult.fflags.NX = i2f_raw_guard || i2f_raw_sticky;
        end
    end

    // The first register replaces one result-delay stage, keeping D-1 clocks.
    localparam RESULT_DELAY = PIPELINE_DEPTH >= 3 ? PIPELINE_DEPTH - 2 : PIPELINE_DEPTH - 1;
    generate
        if (RESULT_DELAY > 0) begin : delayResult
            PipeRegPath pipeReg[RESULT_DELAY];
            always_ff @(posedge clk) begin
                pipeReg[RESULT_DELAY-1] <= nextResult;
                for (int i = 1; i < RESULT_DELAY; ++i) begin
                    pipeReg[i-1] <= pipeReg[i];
                end
            end
            assign {result, fflags} = pipeReg[0];
        end
        else begin : combinationalResult
            assign {result, fflags} = nextResult;
        end
    endgenerate
endmodule
