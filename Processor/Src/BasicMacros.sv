// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.




// On each clock edge, it evaluates "exp" and if its result is false, it shows "msg".
// You can use a formatted string with parentheses in "msg" as follows:
// `RSD_ASSERT_CLK_FMT(clk, some_expression, ("%d", i))
/*
`define RSD_ASSERT_CLK_FMT(clk, exp, msg) \
    assert property (@(posedge clk) (exp)) \
        else $error msg;
*/

// NOT_TRANSPILED_TO_VERYL
// Assertion macros are disabled because the macro-expanded assertion blocks are not transpilable to Veryl.
`define RSD_ASSERT_CLK_FMT(clk, exp, msg)
`define RSD_ASSERT_CLK(clk, exp, msg)

// RSD_STATIC_ASSERT_FMT must be used from outside always_comb/always_ff blocks.
// NOT_TRANSPILED_TO_VERYL
// Static assertion macros are disabled because generate-time assertion macros are not transpilable to Veryl.
`define RSD_STATIC_ASSERT_FMT(exp, msg)
`define RSD_STATIC_ASSERT(exp, msg)
