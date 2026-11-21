// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;

module TestBlockDualPortRAM;
    localparam STEP = 20;
    localparam HOLD = 4;
    localparam ENTRY_NUM = 4;
    localparam ENTRY_BIT_SIZE = 4;

    typedef logic [$clog2(ENTRY_NUM)-1:0] Address;
    typedef logic [ENTRY_BIT_SIZE-1:0] Value;

    logic clk, rst;
    TestBenchClockGenerator #( .STEP(STEP) ) clkgen ( .rstOut(FALSE), .* );

    logic we;
    Address wa, ra;
    Value wv, rv;

    BlockDualPortRAM #(
        .ENTRY_NUM(ENTRY_NUM), .ENTRY_BIT_SIZE(ENTRY_BIT_SIZE)
    ) blockRAM (.*);

    task Check(input Value expectedValue);
        assert (rv === expectedValue)
            else $fatal(1, "Read output: expected %h, got %h (ra=%0d, wa=%0d, we=%b)",
                        expectedValue, rv, ra, wa, we);
    endtask

    task Step(input logic nextWE, input Address nextWA, input Value nextWV,
              input Address nextRA, input Value expectedBefore, expectedAfter);
        @(negedge clk);
        we = nextWE;
        wa = nextWA;
        wv = nextWV;
        ra = nextRA;
        #HOLD;
        // The registered output must hold its value until the next rising edge.
        Check(expectedBefore);
        @(posedge clk);
        #HOLD;
        Check(expectedAfter);
    endtask

    initial begin
        #(STEP * 2 * 100);
        $fatal(1, "BlockDualPortRAM test timed out");
    end

    initial begin
        we = FALSE;
        wa = 0;
        ra = 0;
        wv = 0;
        @(negedge rst);
        $display("========== Test Start ==========");

        // RAM has no reset: explicitly initialize every entry before checking it.
        // Addresses 0..3 receive 1, 4, 7, and a, respectively.
        for (int i = 0; i < ENTRY_NUM; i++) begin
            @(negedge clk);
            we = TRUE;
            wa = Address'(i);
            wv = Value'(3 * i + 1);
            @(posedge clk);
            #HOLD;
        end
        Check(4'h1);

        // Read every address, checking the synchronous read latency.
        Step(FALSE, 0, 0, 1, 4'h1, 4'h4);
        Step(FALSE, 0, 0, 2, 4'h4, 4'h7);
        Step(FALSE, 0, 0, 3, 4'h7, 4'ha);
        Step(FALSE, 0, 0, 0, 4'ha, 4'h1);

        // A write and a read at different addresses operate independently.
        Step(TRUE,  1, 4'hc, 2, 4'h1, 4'h7);
        // Disabling writes must preserve the stored value despite new write data.
        Step(FALSE, 1, 4'h9, 1, 4'h7, 4'hc);
        Step(FALSE, 0, 0,    1, 4'hc, 4'hc);

        // READ_FIRST: a same-address read/write returns the old value at that edge.
        Step(TRUE,  1, 4'hf, 1, 4'hc, 4'hc);
        Step(FALSE, 0, 0,    1, 4'hc, 4'hf);
        // Writes to address 1 must not affect other entries.
        Step(FALSE, 0, 0,    0, 4'hf, 4'h1);
        Step(FALSE, 0, 0,    2, 4'h1, 4'h7);
        Step(FALSE, 0, 0,    3, 4'h7, 4'ha);

        $display("========== Test Passed ==========");
        $finish;
    end
endmodule : TestBlockDualPortRAM
