package FPUTypes;

typedef struct packed {
    logic sign;
    logic [7:0] expo;
    logic [7:0] offs;
    logic [23:0] mant;
} FAddDataPath;

typedef struct packed {
    FAddDataPath lhs;
    FAddDataPath rhs;
    logic is_subtraction;
    logic prec_loss;
    logic res_is_nan;
    logic [31:0] nan;
} FAddStage1RegPath;

typedef struct packed {
    logic is_subtraction;
    logic [26:0] adder_lhs;
    logic [26:0] adder_rhs;
    logic lhs_sign;
    logic [7:0] lhs_expo;
    logic [7:0] lhs_offs;
    logic [24:0] suber_result;
    logic [4:0] lz_count;
    logic prec_loss;
    logic res_is_nan;
    logic [31:0] nan;
} FAddStage2RegPath;

typedef struct packed {
    //logic sign;
    logic [7:0] expo;
    logic [9:0] v_expo;
    logic [22:0] mant;
} FMulDataPath;

typedef struct packed {
    FMulDataPath lhs;
    FMulDataPath rhs;
    logic [9:0] virtual_expo;
    logic result_sign;
    logic subnormal;
    logic res_is_zero;
    logic res_is_nan;
    logic res_is_inf;
    logic [31:0] nan;
} FMulStage1RegPath;

typedef struct packed {
    logic [47:0] multiplier_result;
    logic [5:0] subnormal_shift;
    logic [9:0] virtual_expo;
    logic result_sign;
    logic subnormal;
    logic res_is_zero;
    logic res_is_nan;
    logic res_is_inf;
    logic [31:0] nan;
} FMulStage2RegPath;

typedef struct packed {
    logic [9:0] v_expo;
    logic [22:0] v_mant;
} FDivDataPath;

typedef struct packed {
    FDivDataPath lhs;
    FDivDataPath rhs;
    logic [9:0] virtual_expo;
    logic result_sign;
    logic subnormal;
    logic dividend_normalize;
    logic res_is_zero;
    logic res_is_nan;
    logic res_is_inf;
    logic [31:0] nan;
    logic [26:0] rem;
    logic [23:0] quo;
} FDivRegPath;

typedef struct packed {
    logic inp_sign;
    logic [8:0] v_expo;
    logic [23:0] v_mant;
    logic res_is_zero;
    logic res_is_nan;
    logic res_is_inf;
    logic [31:0] nan;
    logic [26:0] rem;
    logic [25:0] quo;
} FSQRTRegPath;

typedef struct packed {
    logic [9:0]  v_lhs_expo;
    logic [9:0]  v_rhs_expo;
    logic [23:0] v_lhs_mant;
    logic [23:0] v_rhs_mant;
    logic [9:0] virtual_expo;
    logic is_divide;
    logic result_sign;
    logic lhs_sign;
    logic subnormal;
    logic res_is_zero;
    logic res_is_nan;
    logic res_is_inf;
    logic [31:0] nan;
    logic [26:0] rem;
    logic [25:0] quo;
} FDivSqrtRegPath;

typedef struct packed {
    logic [9:0] mulres_expo;
    logic result_is_inf;
    logic result_is_nan;
    logic res_is_addend;
    logic mul_sign;
    logic prop_inf_sign;
    logic addend_sign;
    logic is_subtract;
    logic [31:0] nan;
    logic [31:0] addend;
} FMAStage1RegPath;

typedef struct packed {
    logic [9:0] mulres_expo;
    logic result_is_inf;
    logic result_is_nan;
    logic res_is_addend;
    logic mul_sign;
    logic prop_inf_sign;
    logic addend_sign;
    logic is_subtract;
    logic [31:0] nan;
    logic [31:0] addend;
} FMAStage2RegPath;

typedef struct packed {
    logic [75:0] abs_fma_result;
    logic [9:0] mulres_expo;
    logic res_is_negative;
    logic result_is_inf;
    logic result_is_nan;
    logic res_is_zero;
    logic res_is_addend;
    logic result_sign;
    logic prop_inf_sign;
    logic addend_sign;
    logic is_subtract;
    logic [31:0] nan;
    logic [31:0] addend;
} FMAStage3RegPath;

typedef struct packed {
    logic [75:0] abs_fma_result;
    logic [7:0] fmares_shift;
    logic [9:0] virtual_expo;
    logic subnormal;
    logic res_is_negative;
    logic result_is_inf;
    logic result_is_nan;
    logic res_is_zero;
    logic res_is_addend;
    logic result_sign;
    logic prop_inf_sign;
    logic addend_sign;
    logic is_subtract;
    logic [31:0] nan;
    logic [31:0] addend;
} FMAStage4RegPath;

endpackage