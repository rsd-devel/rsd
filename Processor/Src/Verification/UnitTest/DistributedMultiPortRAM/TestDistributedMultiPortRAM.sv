// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;

module TestDistributedMultiPortRAM;
    localparam STEP = 10;
    localparam HOLD = 2;
    localparam ENTRY_NUM = 4;
    localparam ENTRY_BIT_SIZE = 4;
    localparam READ_NUM = 2;
    localparam WRITE_NUM = 2;

    typedef logic [$clog2(ENTRY_NUM)-1:0] Address;
    typedef logic [ENTRY_BIT_SIZE-1:0] Value;

    logic clk, rst;
    TestBenchClockGenerator #( .STEP(STEP) ) clkgen ( .rstOut(FALSE), .* );

    logic we[WRITE_NUM];
    Address wa[WRITE_NUM], ra[READ_NUM];
    Value wv[WRITE_NUM], rv[READ_NUM];

    DistributedMultiPortRAM #(
        .ENTRY_NUM(ENTRY_NUM), .ENTRY_BIT_SIZE(ENTRY_BIT_SIZE),
        .READ_NUM(READ_NUM), .WRITE_NUM(WRITE_NUM)
    ) distributedRAM (.*);

    task Check(input Value expectedValue[READ_NUM]);
        for (int i = 0; i < READ_NUM; i++) begin
            assert (rv[i] === expectedValue[i])
                else $fatal(1, "Read port %0d: expected %h, got %h (ra=%0d)",
                            i, expectedValue[i], rv[i], ra[i]);
        end
    endtask

    task Step(input logic nextWE[WRITE_NUM], input Address nextWA[WRITE_NUM],
              input Value nextWV[WRITE_NUM], input Address nextRA[READ_NUM],
              input Value expectedBefore[READ_NUM], expectedAfter[READ_NUM]);
        @(negedge clk);
        we = nextWE;
        wa = nextWA;
        wv = nextWV;
        ra = nextRA;
        #HOLD;
        // Both reads are asynchronous; writes take effect at the rising edge.
        Check(expectedBefore);
        @(posedge clk);
        #HOLD;
        Check(expectedAfter);
    endtask

    initial begin
        #(STEP * 2 * 100);
        $fatal(1, "DistributedMultiPortRAM test timed out");
    end

    initial begin
        we = '{default: FALSE};
        wa = '{default: 0};
        wv = '{default: 0};
        ra = '{default: 0};
        @(negedge rst);
        $display("========== Test Start ==========");

        // Initialize every entry through port 0 before checking stored values.
        // Addresses 0..3 receive 1, 4, 7, and a, respectively.
        for (int i = 0; i < ENTRY_NUM; i++) begin
            @(negedge clk);
            we[0] = TRUE;
            wa[0] = Address'(i);
            wv[0] = Value'(3 * i + 1);
            @(posedge clk);
            #HOLD;
        end
        Check('{4'h1, 4'h1});

        // Array entries are port 0, then port 1. Active writes use distinct addresses.
        // Check independent asynchronous reads across all addresses.
        Step('{0, 0}, '{0, 0}, '{0, 0}, '{1, 2}, '{4'h4, 4'h7}, '{4'h4, 4'h7});
        Step('{0, 0}, '{0, 0}, '{0, 0}, '{3, 0}, '{4'ha, 4'h1}, '{4'ha, 4'h1});

        // Write through both ports simultaneously, then exchange the writing ports.
        Step('{1, 1}, '{1, 2}, '{4'h3, 4'h6}, '{1, 2}, '{4'h4, 4'h7}, '{4'h3, 4'h6});
        Step('{1, 1}, '{2, 1}, '{4'hc, 4'h9}, '{2, 1}, '{4'h6, 4'h3}, '{4'hc, 4'h9});

        // Alternate writes to address 1. A disabled port at that address must not interfere.
        // Both read ports must see the same old/new value when reading the same address.
        Step('{1, 0}, '{1, 1}, '{4'hf, 0}, '{1, 1}, '{4'h9, 4'h9}, '{4'hf, 4'hf});
        Step('{0, 1}, '{1, 1}, '{0, 4'h5}, '{1, 2}, '{4'hf, 4'hc}, '{4'h5, 4'hc});

        // Disabling both writes preserves data, including the latest writer selection.
        Step('{0, 0}, '{1, 2}, '{0, 0}, '{1, 2}, '{4'h5, 4'hc}, '{4'h5, 4'hc});
        Step('{0, 0}, '{0, 0}, '{0, 0}, '{1, 1}, '{4'h5, 4'h5}, '{4'h5, 4'h5});
        // Other entries remain unchanged.
        Step('{0, 0}, '{0, 0}, '{0, 0}, '{0, 3}, '{4'h1, 4'ha}, '{4'h1, 4'ha});

        // Zero is valid write data; later writes from the other ports must replace it.
        Step('{1, 1}, '{1, 2}, '{0, 0}, '{1, 2}, '{4'h5, 4'hc}, '{0, 0});
        Step('{0, 0}, '{0, 0}, '{0, 0}, '{2, 1}, '{0, 0}, '{0, 0});
        Step('{1, 1}, '{2, 1}, '{4'ha, 4'h3}, '{1, 2}, '{0, 0}, '{4'h3, 4'ha});

        $display("========== Test Passed ==========");
        $finish;
    end
endmodule : TestDistributedMultiPortRAM
