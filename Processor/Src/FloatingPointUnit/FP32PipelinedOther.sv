import OpFormatTypes::*;
import BasicTypes::*;

function automatic [5:0] leading_zeros_count(
    input logic [31:0] x
);
    for(leading_zeros_count = 0; leading_zeros_count <= 31; leading_zeros_count = leading_zeros_count + 1)
        if(x >> (31-leading_zeros_count) != 0) break;
endfunction

function automatic void FP32CVT_I2F(
input
    logic [31:0] lhs,
    logic fmt_unsigned,
    Rounding_Mode rm,
output
    logic [31:0] result,
    FFlags_Path fflags
);
    logic is_exact, is_valid, lhs_is_neg;
    logic [5:0] lzc;
    logic [31:0] abs_lhs, shifted_lhs; // hidden 1(1) + mantissa(23) + lower_bits(8)
    logic [7:0]  expo;
    logic [22:0] mant;
    logic round_up, exp_plus_one;
    logic lsb, guard, sticky;
    lhs_is_neg =  ~fmt_unsigned & lhs[31];
    abs_lhs = lhs_is_neg ? -lhs : lhs;
    lzc = leading_zeros_count(abs_lhs);
    shifted_lhs = abs_lhs << lzc;
    mant = shifted_lhs[30:8];
    expo = (abs_lhs == '0) ? 0 : 8'd127 + 8'd31 - lzc;
    {lsb, guard, sticky} = {shifted_lhs[8:7], |shifted_lhs[6:0]};
    case (rm)
        RM_RNE:  round_up = guard & (lsb | sticky);
        RM_RTZ:  round_up = FALSE;
        RM_RDN:  round_up = (guard | sticky) & lhs_is_neg;
        RM_RUP:  round_up = (guard | sticky) & ~lhs_is_neg;
        RM_RMM:  round_up = guard;
        default: round_up = FALSE; // RTZ
    endcase
    exp_plus_one = round_up & (&mant); // 1.111111.. + round_up
    expo = expo + {7'h0, exp_plus_one};
    mant = mant + {22'h0, round_up};
    result = {lhs_is_neg, expo, mant};

    // fflag update
    fflags = '0;
    if (guard | sticky) begin
        fflags.NX = TRUE;
    end
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
    PipeRegPath pipeReg[PIPELINE_DEPTH - 1];

    // just a buffer
    always_comb begin
        if( PIPELINE_DEPTH > 1) begin
            {result, fflags} = pipeReg[0];
        end else begin
            {result, fflags} = {resultOut, fflagsOut};
        end
    end
    always_ff @(posedge clk) begin
        if (PIPELINE_DEPTH > 1) begin
            pipeReg[PIPELINE_DEPTH-2] <= {resultOut, fflagsOut};
            for (int i=1; i < PIPELINE_DEPTH - 1; ++i) begin
                pipeReg[i-1] <= pipeReg[i];
            end
        end
    end

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
                FP32CVT_I2F(lhs, fmt_unsigned, rm, resultOut, fflagsOut);
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
