import FPUTypes::*;
module FP32PipelinedAdder #(parameter PIPELINE_DEPTH = 5) (
input
    logic clk,
    logic [31:0] lhs,
    logic [31:0] rhs,
output 
    logic [31:0] result
);
    FAddStage1RegPath stg0Out;
    FAddStage2RegPath stg1Out;
    logic [31:0] stg2Out;

    FAddStage0 stg0(lhs, rhs, stg0Out);
    FAddStage1 stg1(clk, stg0Out, stg1Out);
    FAddStage2 stg2(clk, stg1Out, stg2Out);

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

module FAddStage0(
    input logic [31:0] lhs,
    input logic [31:0] rhs,
    output FAddStage1RegPath stg0Out
);

    logic lhs_sign, rhs_sign;
    logic [7:0] lhs_expo, rhs_expo;
    logic [22:0] lhs_mant, rhs_mant;
    logic lhs_is_nan, rhs_is_nan, lhs_is_inf, rhs_is_inf, res_is_nan;
    logic [31:0] s_lhs, s_rhs;
    logic [7:0] s_lhs_expo, s_rhs_expo, s_lhs_offs, s_rhs_offs;
    logic [23:0] s_lhs_mant, s_rhs_mant;
    logic swap_is_needed, prec_loss, is_subtraction;
    logic [31:0] nan;

    always_comb begin
        {lhs_sign, lhs_expo, lhs_mant} = lhs;
        {rhs_sign, rhs_expo, rhs_mant} = rhs;

        // Nan handling
        lhs_is_nan = lhs_expo == 8'hff & lhs_mant != 0;
        rhs_is_nan = rhs_expo == 8'hff & rhs_mant != 0;
        lhs_is_inf = lhs_expo == 8'hff & lhs_mant == 0;
        rhs_is_inf = rhs_expo == 8'hff & rhs_mant == 0;
        res_is_nan = lhs_is_nan | rhs_is_nan | (lhs_sign != rhs_sign & lhs_is_inf & rhs_is_inf);
        //nan = lhs_is_nan ? lhs | 32'h00400000 : rhs_is_nan ? rhs | 32'h00400000: 32'hffc00000; // qNan
        nan = 32'h7fc00000;

        // Preparation
        swap_is_needed   = lhs[30:0] < rhs[30:0];
        is_subtraction   = lhs_sign != rhs_sign;
        s_lhs = swap_is_needed ? rhs : lhs;
        s_rhs = swap_is_needed ? lhs : rhs;
        s_lhs_expo = s_lhs[30:23];
        s_rhs_expo = s_rhs[30:23];
        s_lhs_offs = s_lhs_expo == 0 ? 1 : s_lhs_expo;
        s_rhs_offs = s_rhs_expo == 0 ? 1 : s_rhs_expo;
        s_lhs_mant = { s_lhs_expo != 8'h00, s_lhs[22:0] }; // s_lhs_expo != 8'h00 is the hidden bit of a normalized number
        s_rhs_mant = { s_rhs_expo != 8'h00, s_rhs[22:0] }; // s_rhs_expo != 8'h00 is the hidden bit of a normalized number
        prec_loss = is_subtraction & s_lhs_expo - s_rhs_expo <= 1 & s_lhs_expo != 8'hff;

        // to next stage
        stg0Out ={{s_lhs[31], s_lhs_expo, s_lhs_offs, s_lhs_mant}, {s_rhs[31], s_rhs_expo, s_rhs_offs, s_rhs_mant}, is_subtraction, prec_loss, res_is_nan, nan};
    end
endmodule

module FAddStage1(
    input logic clk,
    input FAddStage1RegPath stg1In,
    output FAddStage2RegPath stg1Out
);

    function automatic logic [4:0] LeadingZeroCounter (input logic [24:0] x);
        logic [4:0] i;
        for (i = 0; i <= 24; i++) begin
            if (x[24-i]) break;
        end
        return i;
    endfunction
    
    FAddStage1RegPath pipeReg;
    always_ff @( posedge clk ) begin
        pipeReg <= stg1In;
    end

    FAddDataPath lhs, rhs;
    logic is_subtraction;
    logic prec_loss;
    logic res_is_nan;
    logic [31:0] nan;
    logic [26:0] adder_lhs, adder_rhs;
    logic large_diff;
    logic [4:0] offs_diff;
    logic [48:0] shifted_rhs;

    logic [24:0] suber_lhs, suber_rhs, suber_result;
    logic [4:0] lz_count;
    always_comb begin
        {lhs, rhs, is_subtraction, prec_loss, res_is_nan, nan} = pipeReg;

        // When precision loss does not occur
        adder_lhs   = is_subtraction ? { lhs.mant, 1'b0, 2'b0 } : { 1'b0, lhs.mant, 2'b0 };
        large_diff  = lhs.expo - rhs.expo > 31;
        offs_diff   = large_diff ? 31 : lhs.offs[4:0] - rhs.offs[4:0];
        shifted_rhs = { rhs.mant, 25'h0 } >> offs_diff >> !is_subtraction;
        adder_rhs   = { shifted_rhs[48:24], shifted_rhs[23], shifted_rhs[22:0] != 0 }; // Last 2 bits are the guard bit and the sticky bit.

        // When precision loss occurs
        suber_lhs = {lhs.mant, 1'b0};
        suber_rhs = { rhs.mant, 1'b0 } >> (lhs.offs[0] != rhs.offs[0]); // s_lhs_offs[0] != s_rhs_offs[0] is equal to s_lhs_expo - s_rhs_expo because s_lhs_expo - s_rhs_expo <= 1.
        suber_result = suber_lhs - suber_rhs;
        lz_count = LeadingZeroCounter(suber_result);

        // to next stage
        stg1Out = {is_subtraction, adder_lhs, adder_rhs, lhs.sign, lhs.expo, lhs.offs, suber_result, lz_count, prec_loss, res_is_nan, nan};
    end
endmodule

module FAddStage2(
    input logic clk,
    input FAddStage2RegPath stg2In,
    output logic [31:0] result
);
    FAddStage2RegPath pipeReg;
    always_ff @( posedge clk ) begin
        pipeReg <= stg2In;
    end

    logic [26:0] adder_lhs, adder_rhs;
    logic lhs_sign;
    logic [7:0] lhs_expo, lhs_offs;
    logic [24:0] suber_result;
    logic [4:0] lz_count;
    logic is_subtraction;
    logic prec_loss;
    logic res_is_nan;
    logic [31:0] nan;
    
    logic [26:0] adder_result;
    logic round_to_away, exp_plus_one, round_away, subnormal;
    logic res_is_zero, res_is_inf;
    logic [31:0] inf, zero;
    logic [22:0] final_mant_a, final_mant_s;
    logic [7:0] final_expo_a, final_expo_s;
    logic [31:0] final_result_a, final_result_s;

    always_comb begin
        {is_subtraction, adder_lhs, adder_rhs, lhs_sign, lhs_expo, lhs_offs, suber_result, lz_count, prec_loss, res_is_nan, nan} = pipeReg;
    
        // When precision loss does not occur
        adder_result  = is_subtraction ? adder_lhs - adder_rhs : adder_lhs + adder_rhs;
        round_to_away = adder_result[26] ? adder_result[2] & (adder_result[3] | adder_result[1] | adder_result[0])
                                         : adder_result[1] & (adder_result[2] |                   adder_result[0]); // round to nearest, ties to even
        exp_plus_one  = (lhs_expo == 8'h00 & adder_result[25]) | adder_result >= 27'h3fffffe; // when the sum of two subnormal number is a normal number or a carry is generated with rounding taken into account

        final_mant_a  = (adder_result[26] ? adder_result[25:3] : adder_result[24:2]) + { 22'h0, round_to_away }; // No special treatment is required even if a overflow occurs since the answer will be 0 and it will be correct.
        final_expo_a  = lhs_expo + { 7'h0, exp_plus_one } - { 7'h0, is_subtraction }; // No overflow occurs because 2 <= s_lhs_expo <= 254.
        res_is_inf    = lhs_expo == 8'hff | final_expo_a == 8'hff;
        inf           = { lhs_sign, 8'hff, 23'h0 };
        
        final_result_a = res_is_inf ? inf : { lhs_sign, final_expo_a, final_mant_a };

        // When precision loss occurs
        round_away = suber_result[1] & suber_result[0]; // round to nearest, ties to even
        subnormal  = { 3'b0, lz_count } >= lhs_offs;
        
        final_mant_s = lhs_offs == 1 ? suber_result[23:1] :
                     subnormal       ? suber_result[22:0] << (lhs_offs-2) :
                     lz_count == 0   ? suber_result[23:1] + { 22'h0, round_away }
                                     : suber_result[22:0] << (lz_count-1);
        final_expo_s = subnormal ? 0 : lhs_offs - { 3'b0, lz_count };
        res_is_zero  = suber_result == 0;
        zero         = 32'h00000000;

        final_result_s = res_is_zero ? zero : { lhs_sign, final_expo_s, final_mant_s };

        // Ouptut result
        result = res_is_nan ? nan :
                 prec_loss  ? final_result_s  : final_result_a;
    end
endmodule

