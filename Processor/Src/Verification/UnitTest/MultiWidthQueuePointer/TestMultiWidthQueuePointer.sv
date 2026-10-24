// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;

module TestMultiWidthQueuePointer;
    localparam STEP = 20;
    localparam HOLD = 4;
    localparam SIZE = 8;
    localparam DELTA_WIDTH = 2;

    typedef logic [$clog2(SIZE)-1:0] IndexPath;
    typedef logic [$clog2(SIZE):0] CountPath;
    typedef logic [$clog2(DELTA_WIDTH):0] WidthPath;

    logic clk, rst;
    TestBenchClockGenerator #( .STEP(STEP) ) clkgen ( .rstOut(FALSE), .* );

    logic push, pop;
    IndexPath headPtr, tailPtr;
    WidthPath pushCount, popCount;
    CountPath count;

    MultiWidthQueuePointer #(
        .SIZE(SIZE), .PUSH_WIDTH(DELTA_WIDTH), .POP_WIDTH(DELTA_WIDTH)
    ) queuePointer (.*);

    task Check(input CountPath expectedCount,
               input IndexPath expectedHead, expectedTail);
        assert ({count, headPtr, tailPtr} === {expectedCount, expectedHead, expectedTail})
            else $fatal(1, "count/head/tail: expected %0d/%0d/%0d, got %0d/%0d/%0d",
                        expectedCount, expectedHead, expectedTail, count, headPtr, tailPtr);
    endtask

    task Step(input logic nextPush, input WidthPath nextPushCount,
              input logic nextPop, input WidthPath nextPopCount,
              input CountPath expectedCount, input IndexPath expectedHead, expectedTail);
        // Drive away from the active edge and check after register updates settle.
        @(negedge clk);
        push = nextPush;
        pushCount = nextPushCount;
        pop = nextPop;
        popCount = nextPopCount;
        @(posedge clk);
        #HOLD;
        Check(expectedCount, expectedHead, expectedTail);
    endtask

    initial begin
        #(STEP * 2 * 100);
        $fatal(1, "MultiWidthQueuePointer test timed out");
    end

    initial begin
        push = FALSE;
        pop = FALSE;
        pushCount = 0;
        popCount = 0;
        @(negedge rst);
        #HOLD;
        $display("========== Test Start ==========");
        Check(0, 0, 0);

        // Fill the queue and wrap the tail pointer.
        Step(TRUE, 2, FALSE, 0, 2, 0, 2);
        Step(TRUE, 2, FALSE, 0, 4, 0, 4);
        Step(TRUE, 2, FALSE, 0, 6, 0, 6);
        Step(TRUE, 2, FALSE, 0, 8, 0, 0);
        Step(FALSE, 2, FALSE, 2, 8, 0, 0);

        // Mix push/pop widths, wrap the head pointer, and drain the queue.
        Step(FALSE, 0, TRUE, 1, 7, 1, 0);
        Step(FALSE, 0, TRUE, 2, 5, 3, 0);
        Step(TRUE, 1, TRUE, 2, 4, 5, 1);
        Step(TRUE, 2, TRUE, 1, 5, 6, 3);
        Step(FALSE, 0, TRUE, 2, 3, 0, 3);
        Step(FALSE, 0, TRUE, 2, 1, 2, 3);
        Step(FALSE, 0, TRUE, 1, 0, 3, 3);

        // Equal pushes/pops preserve the count while advancing both pointers.
        Step(TRUE, 2, FALSE, 0, 2, 3, 5);
        Step(TRUE, 2, TRUE, 2, 2, 5, 7);
        Step(TRUE, 2, TRUE, 2, 2, 7, 1);
        Step(TRUE, 2, TRUE, 2, 2, 1, 3);
        // Disabled operations and zero widths must leave all state unchanged.
        Step(FALSE, 2, FALSE, 2, 2, 1, 3);
        Step(TRUE, 0, TRUE, 0, 2, 1, 3);
        Step(FALSE, 0, TRUE, 2, 0, 3, 3);

        $display("========== Test Passed ==========");
        $finish;
    end
endmodule
