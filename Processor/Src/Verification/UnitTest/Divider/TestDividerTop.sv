// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;

module TestRefDividerTop(
input
    logic clk_p, clk_n, rst,
    logic req,                  // request a new operation
    DataPath dividend,
    DataPath divisor,
    logic isSigned,             // operation is performed in a singed mode
output
    logic finished,      // Asserted when a result is obtained.
    DataPath quotient,
    DataPath remainder,
    logic refFinished,      
    DataPath refQuotient,
    DataPath refRemainder
);
    
    logic clk;
`ifdef RSD_SYNTHESIS
    SingleClock clkgen(clk_p, clk_n, clk);
`else
    assign clk = clk_p;
`endif

    Divider divider(
        .quotient(quotient),
        .remainder(remainder),
        .finished(finished),
        .*
    );

    RefDivider refDivider(
        .quotient(refQuotient),
        .remainder(refRemainder),
        .finished(refFinished),
        .*
    );
    
endmodule
