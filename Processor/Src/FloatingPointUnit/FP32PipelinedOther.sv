import OpFormatTypes::*;
import BasicTypes::*;

function automatic [5:0] leading_zeros_count(
    input logic [31:0] x
);
    for(leading_zeros_count = 0; leading_zeros_count <= 31; leading_zeros_count = leading_zeros_count + 1)
        if(x >> (31-leading_zeros_count) != 0) break;
endfunction

function automatic void FP32CVT_F2I(
input
    logic [31:0] lhs,
    logic fmt_unsigned,
    Rounding_Mode rm,
output
    logic [31:0] result,
    FFlags_Path fflags
);
    logic sign;
    logic [7:0] expo;
    logic [22:0] mant;
    logic [4:0] shift_amount;
    logic [31:0] int_result, abs_result;
    logic [22:0] lower_bits;
    logic round_up;
    logic lsb, guard, sticky;
    logic is_invalid, lhs_is_neg, lhs_is_nan;
    
    {sign, expo, mant} = lhs;
    /* verilator lint_off WIDTH */
    shift_amount = 158 - expo;
    /* verilator lint_on WIDTH */
    lhs_is_neg = sign;
    lhs_is_nan = expo == 8'hff & mant != 0;
    if (expo <= 126) begin // e < 0
        int_result = 0;
        lsb = 0;
        guard = (expo == 126) ? 1 : 0;
        sticky = (expo == 0 || expo == 126) ? |mant : 1;
    end
    else if (expo <= 157) begin // 0 <= e <= 30
        {int_result, lower_bits} = {1'b1, mant, 31'h0} >> shift_amount;
        lsb = int_result[0];
        {guard, sticky} = {lower_bits[22], |lower_bits[21:0]};
    end
    else if (expo == 158) begin // e = 31
        if (fmt_unsigned) begin
            int_result = lhs_is_neg ? 32'h00000000 : {1'b1, mant, 8'h0};
        end 
        else begin
            int_result = lhs_is_neg ? 32'h80000000 : 32'h7fffffff;
        end
    end
    else begin // e > 31(overflow)
        if(fmt_unsigned) begin
            int_result = (~lhs_is_nan & lhs_is_neg) ? 32'h00000000 : 32'hffffffff;
        end
        else begin
            int_result = (~lhs_is_nan & lhs_is_neg) ? 32'h80000000 : 32'h7fffffff;
        end
    end
    // rounding
    case (rm)
            RM_RNE:  round_up = guard & (lsb | sticky);
            RM_RTZ:  round_up = FALSE;
            RM_RDN:  round_up = (guard | sticky) & lhs_is_neg;
            RM_RUP:  round_up = (guard | sticky) & ~lhs_is_neg;
            RM_RMM:  round_up = guard;
            default: round_up = FALSE; // RTZ
    endcase
    if (expo <= 157) begin
        int_result = int_result + {31'h0, round_up};
        result = lhs_is_neg ? (fmt_unsigned ? 32'h0 : -int_result): int_result;
    end
    else begin
        //result = (fmt_unsigned & lhs_is_neg & ~lhs_is_nan) ? 32'h0 : int_result;
        result = int_result;
    end

    fflags = '0;
    // fflag update
    is_invalid =  expo >= 159 |  // overflow or nan/inf
                (~fmt_unsigned & expo == 158 & (~lhs_is_neg | (lhs_is_neg & mant != 0))) |  // overflow in signed conversino
                (fmt_unsigned & lhs_is_neg & (expo >= 127 | round_up));                     // rounded result is negative in unsigned conversion
    if (is_invalid) begin
        fflags.NV = TRUE;
    end
    else if (guard | sticky) begin
        fflags.NX = TRUE;
    end
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
    logic [31:0] resultOut;
    FFlags_Path fflagsOut;

    typedef struct packed {
        logic [31:0] result;
        FFlags_Path fflags; 
    } PipeRegPath;

    typedef struct packed {
        logic [23:0] significand;
        logic guardBit;
        logic stickyBit;
        logic [5:0] leadingZeros;
    } I2FNormalizedPath;

    typedef union packed {
        logic [31:0] result;
        I2FNormalizedPath i2f;
    } FirstDataPath;

    function automatic void FP32CVT_I2F_Normalize(
        input logic [31:0] lhs,
        input logic sign,
        output I2FNormalizedPath normalized
    );
        logic [31:0] transitions, shifted;
        logic [5:0] lzc;
        // As in FMA, locate |lhs|-1 for negative inputs without a carry chain.
        transitions = lhs ^ {sign, lhs[31:1]};
        lzc = leading_zeros_count(transitions);
        // Keep -1 distinct from zero and leave its late +1 in the significand.
        if (sign && lzc == 6'd32) lzc = 6'd31;
        shifted = lhs << lzc;
        normalized.significand = shifted[31:8];
        normalized.guardBit = shifted[7];
        normalized.stickyBit = |shifted[6:0];
        normalized.leadingZeros = lzc;
    endfunction

    function automatic void FP32CVT_I2F_FromNormalized(
        input I2FNormalizedPath normalized,
        input logic sign,
        input Rounding_Mode rm,
        output logic [31:0] result,
        output FFlags_Path fflags
    );
        logic [23:0] significand;
        logic guardBit, tailBit, roundUp;
        logic [24:0] rounded;
        logic [7:0] expo;
        // Zero-fill before inversion leaves |lhs|*2^shift-1 on the negative
        // path. Fold its +1 into rounding, as in FMA's RoundIncrement.
        significand = normalized.significand ^ {24{sign}};
        guardBit = normalized.guardBit ^ sign;
        tailBit = sign ? !normalized.stickyBit : normalized.stickyBit;
        case (rm)
            RM_RNE: roundUp = sign ? guardBit || (significand[0] && tailBit)
                                   : guardBit && (significand[0] || tailBit);
            RM_RTZ: roundUp = sign && guardBit && tailBit;
            RM_RDN: roundUp = sign;
            RM_RUP: roundUp = sign ? guardBit && tailBit : guardBit || tailBit;
            RM_RMM: roundUp = guardBit || (sign && tailBit);
            default: roundUp = sign && guardBit && tailBit; // Preserve I2F's RTZ fallback.
        endcase
        rounded = {1'b0, significand} + {24'b0, roundUp};
        expo = normalized.leadingZeros == 6'd32 ? 8'd0
            : 8'd158 - {2'b0, normalized.leadingZeros} + {7'b0, rounded[24]};
        result = {sign, expo, rounded[22:0]};
        fflags = '0;
        fflags.NX = normalized.guardBit || normalized.stickyBit;
    endfunction

    function automatic void FP32CVT_I2F(
        input logic [31:0] lhs,
        input logic fmt_unsigned,
        input Rounding_Mode rm,
        output logic [31:0] result,
        output FFlags_Path fflags
    );
        I2FNormalizedPath normalized;
        logic sign;
        sign = !fmt_unsigned && lhs[31];
        FP32CVT_I2F_Normalize(lhs, sign, normalized);
        FP32CVT_I2F_FromNormalized(normalized, sign, rm, result, fflags);
    endfunction

    generate
        if (PIPELINE_DEPTH >= 3) begin : splitI2F
            typedef struct packed {
                FirstDataPath data;
                FFlags_Path fflags;
                logic isI2F;
                logic sign;
                Rounding_Mode rm;
            } FirstRegPath;
            FirstDataPath firstData;
            FirstRegPath firstReg;
            PipeRegPath nextResult;
            PipeRegPath pipeReg[PIPELINE_DEPTH - 2];

            // Share 32 bits between normalized I2F data and completed results;
            // only five metadata bits are added to the original result delay.
            always_comb begin
                firstData.result = resultOut;
                if (fpuCode inside {FC_FCVT_SW, FC_FCVT_SWU}) begin
                    FP32CVT_I2F_Normalize(
                        lhs, fpuCode == FC_FCVT_SW && lhs[31], firstData.i2f
                    );
                end
                nextResult = {firstReg.data.result, firstReg.fflags};
                if (firstReg.isI2F) begin
                    FP32CVT_I2F_FromNormalized(
                        firstReg.data.i2f, firstReg.sign, firstReg.rm,
                        nextResult.result, nextResult.fflags
                    );
                end
                {result, fflags} = pipeReg[0];
            end

            always_ff @(posedge clk) begin
                firstReg.data <= firstData;
                firstReg.fflags <= fflagsOut;
                firstReg.isI2F <= fpuCode inside {FC_FCVT_SW, FC_FCVT_SWU};
                firstReg.sign <= fpuCode == FC_FCVT_SW && lhs[31];
                firstReg.rm <= rm;
                // Consume one of the original delay stages for normalization.
                pipeReg[PIPELINE_DEPTH-3] <= nextResult;
                for (int i = 1; i < PIPELINE_DEPTH - 2; ++i) begin
                    pipeReg[i-1] <= pipeReg[i];
                end
            end
        end
        else if (PIPELINE_DEPTH == 2) begin : delayResult
            PipeRegPath pipeReg;
            always_ff @(posedge clk) begin
                pipeReg <= {resultOut, fflagsOut};
            end
            always_comb begin
                {result, fflags} = pipeReg;
            end
        end
        else begin : combinationalResult
            always_comb begin
                {result, fflags} = {resultOut, fflagsOut};
            end
        end
    endgenerate

    // exec unit
    logic lhs_sign, rhs_sign;
    logic [7:0] lhs_expo, rhs_expo;
    logic [22:0] lhs_mant, rhs_mant;
    logic lhs_is_zero, rhs_is_zero, lhs_is_inf, rhs_is_inf, lhs_is_nan, rhs_is_nan;
    logic lhs_is_snan, rhs_is_snan, lhs_is_subnormal, lhs_is_normal;
    logic lhs_is_smaller, lhs_equal_rhs;
    logic fmt_unsigned;


    always_comb begin
        {lhs_sign, lhs_expo, lhs_mant} = lhs;
        {rhs_sign, rhs_expo, rhs_mant} = rhs;

        lhs_is_zero = lhs_expo == 8'h00 & lhs_mant == 0;
        rhs_is_zero = rhs_expo == 8'h00 & rhs_mant == 0;
        lhs_is_inf  = lhs_expo == 8'hff & lhs_mant == 0;
        rhs_is_inf  = rhs_expo == 8'hff & rhs_mant == 0;
        lhs_is_nan  = lhs_expo == 8'hff & lhs_mant != 0;
        rhs_is_nan  = rhs_expo == 8'hff & rhs_mant != 0;
        lhs_is_snan = lhs_is_nan & lhs_mant[22] == 0;
        rhs_is_snan = rhs_is_nan & rhs_mant[22] == 0;
        lhs_is_subnormal = lhs_expo == 0 & lhs_mant != 0;
        lhs_is_normal = ~(lhs_is_zero | lhs_is_inf | lhs_is_nan | lhs_is_subnormal);
        lhs_is_smaller = (lhs < rhs) ^ ( lhs_sign | rhs_sign);
        // +0 normally compares as equal to -0
        lhs_equal_rhs = (lhs == rhs) | (lhs_is_zero && rhs_is_zero);
        fmt_unsigned = fpuCode inside {FC_FCVT_SWU, FC_FCVT_WUS};

        fflagsOut = '0;
        unique case(fpuCode)
            FC_SGNJ: begin
                resultOut = {rhs_sign, lhs_expo, lhs_mant};
            end
            FC_SGNJN: begin
                resultOut = {~rhs_sign, lhs_expo, lhs_mant};
            end
            FC_SGNJX: begin
                resultOut = {lhs_sign ^ rhs_sign, lhs_expo, lhs_mant};
            end
            FC_FMIN: begin
                if (lhs_is_nan & rhs_is_nan) begin
                    resultOut = 32'h7fc00000;
                end
                else if (lhs_is_nan) begin
                    resultOut = rhs;
                end 
                else if (rhs_is_nan) begin
                    resultOut = lhs;
                end
                else begin
                    resultOut = lhs_is_smaller ? lhs : rhs;
                end
                // update fflags
                if (lhs_is_snan || rhs_is_snan) begin
                    fflagsOut.NV = TRUE;
                end
            end
            FC_FMAX: begin
                if (lhs_is_nan & rhs_is_nan) begin
                    resultOut = 32'h7fc00000;
                end
                else if (lhs_is_nan) begin
                    resultOut = rhs;
                end 
                else if (rhs_is_nan) begin
                    resultOut = lhs;
                end
                else begin
                    resultOut = lhs_is_smaller ? rhs : lhs;
                end

                if (lhs_is_snan || rhs_is_snan) begin
                    fflagsOut.NV = TRUE;
                end
            end
            FC_FMV_WX, FC_FMV_XW: begin
                resultOut = lhs;
            end
            FC_FCVT_SW, FC_FCVT_SWU: begin
                if (PIPELINE_DEPTH >= 3) begin
                    resultOut = '0; // The first pipeline stage carries normalized I2F data.
                end
                else begin
                    FP32CVT_I2F(lhs, fmt_unsigned, rm, resultOut, fflagsOut);
                end
            end
            FC_FCVT_WS, FC_FCVT_WUS: begin
                FP32CVT_F2I(lhs, fmt_unsigned, rm, resultOut, fflagsOut);
            end
            FC_FEQ: begin
                if (lhs_is_nan || rhs_is_nan) begin
                    resultOut = 0;
                end
                else begin
                    resultOut = lhs_equal_rhs;
                end
                // quiet comparsion
                if (lhs_is_snan || rhs_is_snan) begin
                    fflagsOut.NV = TRUE;
                end
            end
            FC_FLT: begin
                if (lhs_is_nan || rhs_is_nan) begin
                    resultOut = 0;
                    fflagsOut.NV = TRUE;
                end
                else begin
                    //flt.s -0, +0 = 0
                    resultOut = lhs_is_smaller & ~lhs_equal_rhs;
                end
            end
            FC_FLE: begin
                if (lhs_is_nan || rhs_is_nan) begin
                    resultOut = 0;
                    fflagsOut.NV = TRUE;
                end
                else begin
                    resultOut = lhs_is_smaller | lhs_equal_rhs;
                end
            end
            FC_FCLASS: begin
                resultOut = {
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
                resultOut = '0;
                fflagsOut = '0;
            end

        endcase
    end
endmodule
