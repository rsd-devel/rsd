import FPUTypes::*;

module FP32DivSqrter (
input
    logic clk, rst,
    logic [31:0] lhs,
    logic [31:0] rhs,
    logic [2:0] rm,
    logic is_divide,
    logic req,
output
    logic finished,
    logic [31:0] result,
    FFlags fflags
);

    function automatic [2:0] srt_table;
        input[5:0] rem;
        input[3:0] div;

        reg[5:0] th12 = div < 1 ? 6 : div < 2 ? 7 : div < 4 ? 8 : div < 5 ? 9 : div < 6 ? 10 : 11;
        reg[5:0] th01 =               div < 2 ? 2 :                             div < 6 ?  3 :  4;

             if($signed(rem) < $signed(-th12)) srt_table = -2;
        else if($signed(rem) < $signed(-th01)) srt_table = -1;
        else if($signed(rem) < $signed( th01)) srt_table =  0;
        else if($signed(rem) < $signed( th12)) srt_table =  1;
        else                                   srt_table =  2;
    endfunction
    function automatic [9:0] leading_zeros_count;
        input[22:0] x;
        for(leading_zeros_count = 0; leading_zeros_count <= 22; leading_zeros_count = leading_zeros_count + 1)
            if(x >> (22-leading_zeros_count) != 0) break;
    endfunction

    // The SRT quotient can lie on either side of the exact value. A negative
    // remainder just below a grid point needs a decrement when truncating.
    function automatic logic [1:0] RoundAdjustment(
        input logic [2:0] mode,
        input logic sign, lsb, guard_bit, sticky_bit, rem_negative, rem_positive
    );
        RoundAdjustment = '0; // {decrement, increment}
        case (mode)
            3'b001, 3'b010, 3'b011: begin // RTZ, RDN, RUP
                if ((mode == 3'b010 && sign) || (mode == 3'b011 && !sign))
                    RoundAdjustment[0] = guard_bit || sticky_bit || rem_positive;
                else
                    RoundAdjustment[1] = !guard_bit && !sticky_bit && rem_negative;
            end
            3'b100: RoundAdjustment[0] = guard_bit && (sticky_bit || !rem_negative); // RMM
            default: RoundAdjustment[0] = guard_bit &&
                         (sticky_bit || rem_positive || (!rem_negative && lsb)); // RNE
        endcase
    endfunction
    typedef enum logic[1:0]
    {
        PHASE_FINISHED = 0,      // Division is finished. It outputs results.
        PHASE_PREPARATION = 1,   // In preparation
        PHASE_PROCESSING = 2,    // In processing (SRT loop)
        PHASE_ROUNDING = 3       // In rounding & arrangement
    } Phase;

    Phase regPhase, nextPhase; 
    logic [4:0] regCounter, nextCounter;
    FDivSqrtRegPath regData, nextData;
    logic [31:0] regResult, nextResult;
    FFlags regFFlags, nextFFlags;

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
    wire lhs_is_neg  = lhs_sign & lhs != 32'h80000000;
    // Square root has only one operand; quiet NaNs and -0 are not invalid.
    wire invalid = is_divide ? (lhs_is_nan & ~lhs_mant[22]) | (rhs_is_nan & ~rhs_mant[22]) |
                               (lhs_is_zero & rhs_is_zero) | (lhs_is_inf & rhs_is_inf)
                             : (lhs_is_nan & ~lhs_mant[22]) | (lhs_is_neg & ~lhs_is_nan);
    // DZ applies only to a finite, nonzero numerator divided by zero.
    wire divide_by_zero = is_divide & rhs_is_zero & ~lhs_is_zero & ~lhs_is_inf & ~lhs_is_nan;
    wire res_is_nan  = is_divide ? lhs_is_nan | rhs_is_nan | (lhs_is_zero & rhs_is_zero) | (lhs_is_inf & rhs_is_inf)
                                 : lhs_is_nan | lhs_is_neg;
    //wire[31:0]  nan  = is_divide ? lhs_is_nan ? lhs | 32'h00400000 : rhs_is_nan ? rhs | 32'h00400000 : 32'hffc00000
    //                             : lhs_is_nan ? lhs | 32'h00400000 : 32'hffc00000; // qNaN
    wire[31:0]   nan = 32'h7fc00000;

    // Preparation
    wire       result_sign  = is_divide & (lhs_sign ^ rhs_sign);
    wire [9:0] v_lhs_expo   = lhs_expo == 0 ? -leading_zeros_count(lhs_mant) : { 2'b0, lhs_expo }; // virtual exponent (ignores subnormals, but is biased)
    wire [9:0] v_rhs_expo   = rhs_expo == 0 ? -leading_zeros_count(rhs_mant) : { 2'b0, rhs_expo }; // virtual exponent (ignores subnormals, but is biased)
    wire[23:0] v_lhs_mant = lhs_expo == 0 ? { lhs_mant, 1'b0 } << leading_zeros_count(lhs_mant) : { 1'b1, lhs_mant };
    wire[23:0] v_rhs_mant = rhs_expo == 0 ? { rhs_mant, 1'b0 } << leading_zeros_count(rhs_mant) : { 1'b1, rhs_mant };

    wire dividend_normalize = regData.v_lhs_mant < regData.v_rhs_mant;
    wire [9:0] virtual_expo = regData.v_lhs_expo - regData.v_rhs_expo + 127 - { 8'h0, dividend_normalize }; // new biased virtual exponent (ignores subnormals)
    wire       subnormal    = regData.is_divide & $signed(virtual_expo) <= 0;

    // The SRT loop. rem needs 27 bits. 24(mantissa)+2(x8/3,SRT)+1(sign)
    wire[26:0] rem_0 = regData.is_divide ? dividend_normalize ? { 2'b00, regData.v_lhs_mant, 1'b0 } : { 3'b000, regData.v_lhs_mant }
                                 : regData.v_lhs_expo[0] ? { 2'b0, regData.v_lhs_mant, 1'b0 } - 27'h1e40000 : { 1'b0, regData.v_lhs_mant, 2'b0 } - 27'h2400000; // 2 * (x - 1.375^2 or 1.5^2)
    wire[25:0] quo_0 = regData.is_divide ? 26'h0
                                 : regData.v_lhs_expo[0] ? 26'h1600000 : 26'h1800000; // magical initial guess: 1.375 or 1.5; this avoids SRT-table defects at ([-4.5,-4-11/36], 1.5) and ([-4,-4+1/144], 1.25)

    logic [2:0] q;
    logic [3:0] div;
    logic [26:0] rem;
    logic [25:0] quo;
    always_comb begin
        rem = regData.rem;
        quo = regData.quo;
        div = regData.is_divide ? { 1'b0, regData.v_rhs_mant[22:20] } : { quo[25], quo[23:21] };
        q = srt_table( rem[26:21], div );
        case(q)
            3'b010: rem = regData.is_divide ? (rem << 2) - { regData.v_rhs_mant, 3'b000 }
                                             : (rem << 2) - { quo[24:0], 2'b00 } - (27'd4 << (regCounter));
            3'b001: rem = regData.is_divide ? (rem << 2) - { 1'b0, regData.v_rhs_mant, 2'b00 }
                                             : (rem << 2) - { quo, 1'b0 } - (27'd1 << (regCounter));
            3'b111: rem = regData.is_divide ? (rem << 2) + { 1'b0, regData.v_rhs_mant, 2'b00 }
                                             : (rem << 2) + { quo, 1'b0 } - (27'd1 << (regCounter));
            3'b110: rem = regData.is_divide ? (rem << 2) + { regData.v_rhs_mant, 3'b000 }
                                             : (rem << 2) + { quo[24:0], 2'b00 } - (27'd4 << (regCounter));
            default: rem = rem << 2;
        endcase
        quo = quo + ({ {23{q[2]}}, q } << (regCounter));
    end
    
    // Values below half the minimum subnormal still round up in an outward
    // directed mode. Preserve a sticky bit instead of forcing them to zero.
    wire very_tiny = regData.is_divide && $signed(regData.virtual_expo) <= -24;
    wire [47:0] before_round = very_tiny ? 48'd1 : regData.subnormal ?
        {1'b1, regData.quo[23:0], 23'b0} >> -regData.virtual_expo : {regData.quo[23:0], 24'b0};
    wire rem_negative = regData.rem[26];
    wire rem_positive = !rem_negative && regData.rem != 0;
    wire [1:0] round_adjustment = RoundAdjustment(regData.rm, regData.result_sign,
        before_round[25], before_round[24], |before_round[23:0], rem_negative, rem_positive);
    // Compute exponent carry independently of the significand adder.
    wire exp_plus_one = (round_adjustment[0] && (&before_round[47:25])) ||
        (regData.subnormal && round_adjustment[1] && !(|before_round[47:25]));
    // Form each carry/borrow prefix before the rounding decision arrives.
    wire [22:0] result_mant;
    for (genvar i = 0; i < 23; i++) begin : g_round
        if (i == 0) begin
            assign result_mant[i] = before_round[25] ^ (|round_adjustment);
        end
        else begin
            assign result_mant[i] = before_round[i+25] ^
                ((round_adjustment[0] && (&before_round[i+24:25])) ||
                 (round_adjustment[1] && !(|before_round[i+24:25])));
        end
    end
    wire [7:0] result_expo = (regData.is_divide ?
        (regData.subnormal ? 8'b0 : regData.virtual_expo[7:0]) :
        regData.v_lhs_expo[8:1] + {7'b0, regData.v_lhs_expo[0]} + 8'd63) + {7'b0, exp_plus_one};
    wire[31:0] inf          = { regData.result_sign, 8'hff, 23'h0 };
    wire[31:0] zero         = {{ regData.is_divide ? regData.result_sign : regData.lhs_sign }, 8'h00, 23'h0 };

    // Only finite, nonzero arithmetic can raise rounding exceptions.
    wire finite_nonzero = !regData.res_is_nan && !regData.res_is_inf &&
                          regData.v_lhs_mant != 0 &&
                          (!regData.is_divide || regData.v_rhs_expo != 255);
    wire overflow = finite_nonzero && regData.is_divide &&
        ($signed(regData.virtual_expo) >= 255 ||
         (regData.virtual_expo == 254 && exp_plus_one));
    wire overflow_to_inf = regData.rm == 3'b000 || regData.rm == 3'b100 ||
        (regData.rm == 3'b010 && regData.result_sign) ||
        (regData.rm == 3'b011 && !regData.result_sign);
    wire [31:0] overflow_result = overflow_to_inf ? inf : {regData.result_sign, 31'h7f7fffff};
    wire [31:0] final_result = regData.res_is_nan ? regData.nan :
        regData.res_is_zero ? zero : regData.res_is_inf ? inf :
        overflow ? overflow_result : {regData.result_sign, result_expo, result_mant};

    // The signed SRT remainder contributes to NX even when the quotient's
    // discarded bits are zero. Very small quotients may lose every bit.
    wire inexact = finite_nonzero && (overflow || before_round[24:0] != 0 || regData.rem != 0);
    // Detect tininess after rounding to 24-bit precision with an unbounded
    // exponent, before the separate rounding onto the subnormal grid.
    wire [1:0] normal_round_adjustment = RoundAdjustment(regData.rm, regData.result_sign,
        regData.quo[1], regData.quo[0], 1'b0, rem_negative, rem_positive);
    wire normal_exp_plus_one = regData.quo[23:1] == 23'h7fffff && normal_round_adjustment[0];
    wire tiny = regData.is_divide && ($signed(regData.virtual_expo) < 0 ||
                                   (regData.virtual_expo == 0 && !normal_exp_plus_one));
    
    always_ff @(posedge clk) begin
        if (rst) begin
            regPhase <= PHASE_FINISHED;
            regCounter <= '0;
            regData <= '0;
            regResult <= '0; 
            regFFlags <= '0;
        end
        else begin
            regPhase <= nextPhase;
            regCounter <= nextCounter;
            regData <= nextData;
            regResult <= nextResult; 
            regFFlags <= nextFFlags;
        end
    end
    always_comb begin
        nextCounter = regCounter;
        nextData = regData;
        nextResult = regResult;
        nextFFlags = regFFlags;
        if (req && regPhase == PHASE_FINISHED) begin
            nextData.v_lhs_expo = v_lhs_expo;
            nextData.v_lhs_mant = v_lhs_mant;
            nextData.v_rhs_expo = v_rhs_expo;
            nextData.v_rhs_mant = v_rhs_mant;
            // Capture the resolved mode once; later requests must not change it.
            nextData.rm = rm;
            nextData.result_sign = result_sign;
            nextData.lhs_sign = lhs_sign;
            nextData.is_divide = is_divide;
            nextData.res_is_nan = res_is_nan;
            nextData.res_is_inf = is_divide ? (lhs_is_inf | rhs_is_zero) : (!lhs_sign & lhs_is_inf);
            nextData.res_is_zero = is_divide ? (lhs_is_zero | rhs_is_inf) : lhs_is_zero;
            nextData.invalid = invalid;
            nextData.divide_by_zero = divide_by_zero;
            nextData.nan = nan;
            nextPhase = PHASE_PREPARATION;
        end
        else if (regPhase == PHASE_PREPARATION) begin
            nextData.virtual_expo = virtual_expo; 
            nextData.subnormal = subnormal;
            nextData.rem = rem_0;
            nextData.quo = quo_0;
            nextPhase = PHASE_PROCESSING;
            nextCounter = regData.is_divide ? 24 : 22;
        end
        else if (regPhase == PHASE_PROCESSING) begin
            nextData.rem = rem;
            nextData.quo = quo;
            nextCounter = regCounter - 2;
            nextPhase = (regCounter == 0) ? PHASE_ROUNDING : PHASE_PROCESSING;
        end
        // Here, quo has a <1/3ULP error.
        else if (regPhase == PHASE_ROUNDING) begin
            nextResult = final_result;
            // Keep flags with the completed result until the next completion.
            nextFFlags = '0;
            nextFFlags.NV = regData.invalid;
            nextFFlags.DZ = regData.divide_by_zero;
            nextFFlags.OF = overflow;
            nextFFlags.UF = tiny && inexact;
            nextFFlags.NX = inexact;
            nextPhase = PHASE_FINISHED;
            nextCounter = '0;
            nextData = '0;
        end
        else begin
            nextPhase = regPhase;
        end
        finished = regPhase == PHASE_FINISHED;
        result = regResult;
        fflags = regFFlags;
    end

endmodule







