// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;

module TestDivider;
    localparam STEP = 20;
    localparam HOLD = 4;
    localparam MAX_CYCLES = DATA_WIDTH + 4;
    localparam DUT_NUM = 3;
    localparam string DUT_NAMES[DUT_NUM] = '{"Divider", "QuickDivider", "RefDivider"};
    localparam DataPath BOUNDARIES[12] = '{
        32'h00000000, 32'h00000001, 32'h00000002, 32'h00000003,
        32'h7fffffff, 32'h80000000, 32'h80000001, 32'hfffffffe,
        32'hffffffff, 32'h40000000, 32'h55555555, 32'haaaaaaaa
    };

    logic clk, rst, initialReset;
    logic resetRequest = FALSE;
    TestBenchClockGenerator #(.STEP(STEP)) clkgen (
        .rstOut(FALSE), .clk(clk), .rst(initialReset)
    );
    assign rst = initialReset || resetRequest;

    logic req, isSigned;
    DataPath dividend, divisor;
    logic finished[DUT_NUM];
    DataPath quotient[DUT_NUM], remainder[DUT_NUM];
    // Test the interchangeable implementations with the same requests, allowing different latencies.
    Divider divider (.finished(finished[0]), .quotient(quotient[0]), .remainder(remainder[0]), .*);
    QuickDivider quickDivider (.finished(finished[1]), .quotient(quotient[1]), .remainder(remainder[1]), .*);
    RefDivider refDivider (.finished(finished[2]), .quotient(quotient[2]), .remainder(remainder[2]), .*);

    int testCount = 0;
    int randomSeed = 32'h12345678;
    DataPath randomDividend, randomDivisor, powerOfTwo;

    task CheckReset;
        for (int i = 0; i < DUT_NUM; i++) begin
            assert (finished[i] === TRUE && quotient[i] === '0 && remainder[i] === '0)
                else $fatal(1, "%s did not return to idle with zero outputs after reset", DUT_NAMES[i]);
        end
    endtask

    task Start(input DataPath a, input DataPath b, input logic signedMode);
        @(negedge clk);
        req = TRUE;
        dividend = a;
        divisor = b;
        isSigned = signedMode;
        @(posedge clk);
        #HOLD;
        for (int i = 0; i < DUT_NUM; i++) begin
            assert (finished[i] === FALSE)
                else $fatal(1, "%s did not accept signed=%b %h / %h", DUT_NAMES[i], signedMode, a, b);
        end
        @(negedge clk);
        req = FALSE;
        // Inputs may change after acceptance; each divider must retain the accepted operands and mode.
        dividend = ~a;
        divisor = ~b;
        isSigned = !signedMode;
    endtask

    task CheckResult(input int index, input DataPath a, input DataPath b, input logic signedMode,
                     input DataPath expectedQ, input DataPath expectedR);
        assert (quotient[index] === expectedQ && remainder[index] === expectedR)
            else $fatal(1, "%s signed=%b %h / %h: expected Q=%h R=%h, got Q=%h R=%h",
                        DUT_NAMES[index], signedMode, a, b, expectedQ, expectedR, quotient[index], remainder[index]);
    endtask

    task Finish(input DataPath a, input DataPath b, input logic signedMode);
        DataPath expectedQ, expectedR;
        logic [DUT_NUM-1:0] completed;
        // Use language operators as an independent oracle, with the RISC-V special cases explicit.
        if (b == 0) begin
            expectedQ = '1;
            expectedR = a;
        end
        else if (signedMode && a == 32'h80000000 && b == 32'hffffffff) begin
            expectedQ = a;
            expectedR = '0;
        end
        else if (signedMode) begin
            expectedQ = $signed(a) / $signed(b);
            expectedR = $signed(a) % $signed(b);
        end
        else begin
            expectedQ = a / b;
            expectedR = a % b;
        end

        completed = '0;
        for (int cycle = 0; cycle < MAX_CYCLES; cycle++) begin
            @(posedge clk);
            #HOLD;
            for (int i = 0; i < DUT_NUM; i++) begin
                if (finished[i] === TRUE) begin
                    CheckResult(i, a, b, signedMode, expectedQ, expectedR);
                    completed[i] = TRUE;
                end
                else begin
                    assert (finished[i] === FALSE && !completed[i])
                        else $fatal(1, "%s finished became unknown or dropped after completion", DUT_NAMES[i]);
                end
            end
            if (&completed)
                break;
        end
        assert (&completed)
            else $fatal(1, "Division timed out: signed=%b %h / %h, Divider done=%b QuickDivider done=%b RefDivider done=%b",
                        signedMode, a, b, completed[0], completed[1], completed[2]);
        // Results and completion must remain stable until the next request.
        repeat (2) begin
            @(posedge clk);
            #HOLD;
            for (int i = 0; i < DUT_NUM; i++) begin
                assert (finished[i] === TRUE)
                    else $fatal(1, "%s did not hold completion", DUT_NAMES[i]);
                CheckResult(i, a, b, signedMode, expectedQ, expectedR);
            end
        end
        testCount++;
    endtask

    task Divide(input DataPath a, input DataPath b, input logic signedMode);
        Start(a, b, signedMode);
        Finish(a, b, signedMode);
    endtask

    task WaitWhileBusy;
        repeat (5) begin
            @(posedge clk);
            #HOLD;
            for (int i = 0; i < DUT_NUM; i++) begin
                assert (finished[i] === FALSE)
                    else $fatal(1, "%s completed before the restart/reset test could interrupt it", DUT_NAMES[i]);
            end
        end
    endtask

    initial begin
        #(STEP * 2 * 100000);
        $fatal(1, "Divider test timed out after %0d cases", testCount);
    end

    initial begin
        assert (DATA_WIDTH == 32)
            else $fatal(1, "This test requires 32-bit operands");
        req = FALSE;
        dividend = '0;
        divisor = '0;
        isSigned = FALSE;
        @(negedge initialReset);
        #HOLD;
        CheckReset();
        $display("========== Test Start ==========");

        // Exhaust all pairs in small signed and unsigned ranges, including zero divisors.
        for (int a = -8; a < 8; a++)
            for (int b = -8; b < 8; b++)
                Divide(DataPath'(a), DataPath'(b), TRUE);
        for (int a = 0; a < 16; a++)
            for (int b = 0; b < 16; b++)
                Divide(DataPath'(a), DataPath'(b), FALSE);

        for (int mode = 0; mode < 2; mode++) begin
            foreach (BOUNDARIES[a])
                foreach (BOUNDARIES[b])
                    Divide(BOUNDARIES[a], BOUNDARIES[b], mode == 1);
            // Exercise every leading-bit boundary used by QuickDivider's shortened iteration count.
            for (int bitIndex = 0; bitIndex < DATA_WIDTH; bitIndex++) begin
                powerOfTwo = DataPath'(1) << bitIndex;
                Divide(powerOfTwo - 1, 3, mode == 1);
                Divide(powerOfTwo, 3, mode == 1);
                Divide(powerOfTwo + 1, 3, mode == 1);
            end
        end
        // A fixed seed keeps full-width random cases reproducible.
        repeat (128) begin
            randomDividend = $random(randomSeed);
            randomDivisor = $random(randomSeed);
            Divide(randomDividend, randomDivisor, FALSE);
            Divide(randomDividend, randomDivisor, TRUE);
        end

        // A new request replaces an in-flight operation, including its signedness.
        Start(32'h80000000, 3, FALSE);
        WaitWhileBusy();
        Divide(DataPath'(-33), 7, TRUE);
        Start(32'h80000000, DataPath'(-3), TRUE);
        WaitWhileBusy();
        Divide(25, 4, FALSE);

        // Reset must discard an in-flight operation and permit a fresh request.
        Start(32'h80000000, 3, FALSE);
        WaitWhileBusy();
        @(negedge clk);
        resetRequest = TRUE;
        @(posedge clk);
        #HOLD;
        CheckReset();
        @(negedge clk);
        resetRequest = FALSE;
        repeat (MAX_CYCLES) begin
            @(posedge clk);
            #HOLD;
            CheckReset();
        end
        Divide(7, DataPath'(-3), TRUE);

        $display("========== Test Passed: %0d cases on Divider, QuickDivider, and RefDivider ==========", testCount);
        $finish;
    end
endmodule
