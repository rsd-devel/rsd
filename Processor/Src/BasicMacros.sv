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

`ifdef RSD_SYNTHESIS
    // These macros are disabled in synthesys
    `define RSD_ASSERT_CLK_FMT(clk, exp, msg) 
    `define RSD_ASSERT_CLK(clk, exp, msg) 
`else
    `define RSD_ASSERT_CLK_FMT(clk, exp, msg) \
        always @(posedge clk) begin \
            if (!(exp)) begin \
                $display msg; \
            end \
        end 
    `define RSD_ASSERT_CLK(clk, exp, msg) `RSD_ASSERT_CLK_FMT(clk, exp, (msg))
`endif

// RSD_STATIC_ASSERT_FMT must be used from outside always_comb/always_ff blocks.
`define RSD_STATIC_ASSERT_FMT(exp, msg) \
    generate \
        if (!(exp)) begin \
            RSD_STATIC_ASSERT_FAILED non_existing_module(); \
        end \
    endgenerate \

//$error msg; \

`define RSD_STATIC_ASSERT(exp, msg) `RSD_STATIC_ASSERT_FMT(exp, (msg))

