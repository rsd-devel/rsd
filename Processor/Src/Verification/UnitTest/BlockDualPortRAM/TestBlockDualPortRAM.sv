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

    logic [3:0] maskedDone;
    TestBlockDualPortRAMMasked #(8, 4) masked32(clk, rst, maskedDone[0]);
    TestBlockDualPortRAMMasked #(9, 4) masked36(clk, rst, maskedDone[1]);
    TestBlockDualPortRAMMasked #(8, 6) masked48(clk, rst, maskedDone[2]);
    TestBlockDualPortRAMMasked #(9, 6) masked54(clk, rst, maskedDone[3]);

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
        #(STEP * 2 * 10000);
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

        $display("Legacy whole-word RAM checks passed");
        wait (&maskedDone);
        $display("========== Test Passed ==========");
        $finish;
    end
endmodule : TestBlockDualPortRAM

module TestBlockDualPortRAMMasked #(
    parameter SLICE_BIT_SIZE = 8,
    parameter SLICE_NUM = 4
)(
    input logic clk, rst,
    output logic done
);
    localparam ENTRY_NUM = 8;
    localparam ENTRY_BIT_SIZE = SLICE_BIT_SIZE * SLICE_NUM;
    localparam HOLD = 4;
    localparam MASK_NUM = 1 << SLICE_NUM;
    typedef logic [$clog2(ENTRY_NUM)-1:0] Address;
    typedef logic [ENTRY_BIT_SIZE-1:0] Value;
    typedef logic [SLICE_NUM-1:0] Mask;

    Mask we;
    Address wa, ra;
    Value wv, rv;
    Value model[ENTRY_NUM];
    logic [ENTRY_NUM-1:0] initialized;
    logic [MASK_NUM-1:0] masksSeen;
    Value expectedOutput;
    logic outputValid;
    int cycles = 0, checks = 0, collisions = 0;
    int unsigned rngState = 32'h5a28d103 ^ ENTRY_BIT_SIZE;
    Address target, readAddress;
    Mask nextMask, lowWay;
    Value nextValue;

    BlockDualPortMaskedRAM #(
        .ENTRY_NUM(ENTRY_NUM), .ENTRY_BIT_SIZE(ENTRY_BIT_SIZE),
        .WRITE_SLICE_BIT_SIZE(SLICE_BIT_SIZE)
    ) blockRAM (.*);

    function automatic int unsigned RandomWord();
        rngState ^= rngState << 13;
        rngState ^= rngState >> 17;
        rngState ^= rngState << 5;
        return rngState;
    endfunction

    function automatic Value RandomValue();
        logic [31:0] lowBits, highBits;
        lowBits = RandomWord();
        highBits = RandomWord();
        return Value'({highBits, lowBits});
    endfunction

    task automatic Check(input Value expected, input string phase);
        checks++;
        assert (rv === expected)
            else $fatal(1, "Masked RAM width=%0d slice=%0d cycle=%0d %s: expected=%h actual=%h ra=%0d wa=%0d mask=%b",
                        ENTRY_BIT_SIZE, SLICE_BIT_SIZE, cycles, phase,
                        expected, rv, ra, wa, we);
    endtask

    task automatic Step(input Mask nextWE, input Address nextWA,
                        input Value nextWV, input Address nextRA);
        Value oldRead;
        logic oldReadValid;
        @(negedge clk);
        we = nextWE;
        wa = nextWA;
        wv = nextWV;
        ra = nextRA;
        #HOLD;
        if (outputValid) Check(expectedOutput, "before edge");
        oldRead = model[nextRA];
        oldReadValid = initialized[nextRA];
        @(posedge clk);
        // Update by individual bits, independently of the DUT's slice loop.
        for (int bitIndex = 0; bitIndex < ENTRY_BIT_SIZE; bitIndex++)
            if (nextWE[bitIndex / SLICE_BIT_SIZE])
                model[nextWA][bitIndex] = nextWV[bitIndex];
        if (&nextWE) initialized[nextWA] = TRUE;
        if ((|nextWE) && nextWA == nextRA && oldReadValid) collisions++;
        masksSeen[nextWE] = TRUE;
        cycles++;
        #HOLD;
        // A collision returns the complete old row, including enabled slices.
        if (oldReadValid) Check(oldRead, "after edge");
        expectedOutput = oldRead;
        outputValid = oldReadValid;
    endtask

    task automatic ReadAll();
        for (int address = 0; address < ENTRY_NUM; address++)
            Step('0, Address'(0), RandomValue(), Address'(address));
    endtask

    initial begin
        done = FALSE;
        we = '0;
        wa = '0;
        ra = '0;
        wv = '0;
        initialized = '0;
        masksSeen = '0;
        outputValid = FALSE;
        expectedOutput = '0;
        for (int address = 0; address < ENTRY_NUM; address++) model[address] = '0;
        @(negedge rst);

        // RAM has no reset: full writes establish known contents first.
        for (int address = 0; address < ENTRY_NUM; address++)
            Step('1, Address'(address), RandomValue(), Address'(0));
        ReadAll();

        // Check every individual slice and each half-row (one BTB way).
        for (int slice = 0; slice < SLICE_NUM; slice++) begin
            Step(Mask'(1 << slice), Address'(2), ~model[2], Address'(2));
            Step('0, Address'(2), '0, Address'(2));
            Step('0, Address'(2), '1, Address'(3));
        end
        lowWay = Mask'((1 << (SLICE_NUM / 2)) - 1);
        Step(lowWay, Address'(4), ~model[4], Address'(4));
        Step(~lowWay, Address'(4), ~model[4], Address'(4));
        Step('1, Address'(4), ~model[4], Address'(4));
        ReadAll();

        // Every mask changes selected bits and preserves every unselected bit.
        // Reading all addresses also detects unintended neighboring-row writes.
        for (int mask = 0; mask < MASK_NUM; mask++) begin
            target = Address'(mask % ENTRY_NUM);
            Step(Mask'(mask), target, ~model[target], target);
            ReadAll();
        end

        // Keep writing the same address on consecutive cycles.
        for (int n = 0; n < 2 * SLICE_NUM; n++)
            Step(Mask'(1 << (n % SLICE_NUM)), Address'(1), RandomValue(), Address'(1));
        ReadAll();

        // Independent addresses, collisions and zero/full/partial masks mixed.
        for (int n = 0; n < 1024; n++) begin
            target = Address'(RandomWord());
            readAddress = n % 4 == 0 ? target : Address'(RandomWord());
            nextMask = Mask'(RandomWord());
            nextValue = RandomValue();
            Step(nextMask, target, nextValue, readAddress);
            if (n % 32 == 31) ReadAll();
        end
        ReadAll();
        assert (&masksSeen) else $fatal(1, "Incomplete mask coverage width=%0d", ENTRY_BIT_SIZE);
        $display("MASKED_RAM_PASS width=%0d slice=%0d masks=%0d cycles=%0d checks=%0d read_first=%0d",
                 ENTRY_BIT_SIZE, SLICE_BIT_SIZE, MASK_NUM, cycles, checks, collisions);
        done = TRUE;
    end
endmodule : TestBlockDualPortRAMMasked
