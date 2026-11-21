// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;

module TestMultiWidthFreeList;
    localparam STEP = 20;
    localparam HOLD = 4;
    localparam SIZE = 8;
    localparam ENTRY_BIT_SIZE = $clog2(SIZE);
    localparam PUSH_WIDTH = 2;
    localparam POP_WIDTH = 2;

    typedef logic [ENTRY_BIT_SIZE-1:0] Value;
    typedef logic [$clog2(SIZE):0] CountPath;

    logic clk, rst, rstStart;
    TestBenchClockGenerator #(
        .STEP(STEP), .INITIALIZATION_CYCLE(SIZE / PUSH_WIDTH + 2)
    ) clkgen ( .rstOut(FALSE), .* );

    logic push[PUSH_WIDTH], pop[POP_WIDTH];
    Value pushedData[PUSH_WIDTH], poppedData[POP_WIDTH];
    CountPath count;

    MultiWidthFreeList #(
        .SIZE(SIZE), .ENTRY_BIT_SIZE(ENTRY_BIT_SIZE),
        .PUSH_WIDTH(PUSH_WIDTH), .POP_WIDTH(POP_WIDTH)
    ) freeList (.*);

    task CheckCount(input CountPath expectedCount);
        assert (count === expectedCount)
            else $fatal(1, "Free entry count: expected %0d, got %0d", expectedCount, count);
    endtask

    task Step(input logic nextPush[PUSH_WIDTH], input logic nextPop[POP_WIDTH],
              input Value nextPushedData[PUSH_WIDTH], expectedPoppedData[POP_WIDTH],
              input CountPath expectedCount);
        @(negedge clk);
        push = nextPush;
        pop = nextPop;
        pushedData = nextPushedData;
        #HOLD;
        // Check allocations before the edge that consumes them, only on active lanes.
        for (int i = 0; i < POP_WIDTH; i++) begin
            if (pop[i]) begin
                assert (poppedData[i] === expectedPoppedData[i])
                    else $fatal(1, "Allocation lane %0d: expected %0d, got %0d (count=%0d)",
                                i, expectedPoppedData[i], poppedData[i], count);
            end
        end
        @(posedge clk);
        #HOLD;
        CheckCount(expectedCount);
    endtask

    initial begin
        #(STEP * 2 * 100);
        $fatal(1, "MultiWidthFreeList test timed out");
    end

    initial begin
        push = '{default: FALSE};
        pop = '{default: FALSE};
        pushedData = '{default: 0};
        // rstStart initializes the RAM reset counter; rst then initializes two entries per cycle.
        rstStart = TRUE;
        @(posedge clk);
        @(negedge clk);
        rstStart = FALSE;
        @(negedge rst);
        #HOLD;
        $display("========== Test Start ==========");
        CheckCount(SIZE);

        // Array entries are lane 0, then lane 1. push returns IDs; pop allocates them.
        // The initial free IDs are 0..7. Disabled pushes must not overwrite them.
        Step('{0, 0}, '{0, 0}, '{7, 7}, '{0, 0}, 8);
        Step('{0, 0}, '{1, 1}, '{0, 0}, '{0, 1}, 6);
        Step('{0, 0}, '{1, 1}, '{0, 0}, '{2, 3}, 4);
        Step('{0, 0}, '{1, 0}, '{0, 0}, '{4, 0}, 3);

        // Return IDs in a different order, then allocate and return simultaneously.
        Step('{1, 1}, '{0, 0}, '{4, 3}, '{0, 0}, 5);
        Step('{1, 0}, '{0, 0}, '{2, 0}, '{0, 0}, 6);
        Step('{1, 1}, '{1, 1}, '{1, 0}, '{5, 6}, 6);
        // A lone active lane must use the next entry without leaving a gap.
        Step('{0, 1}, '{1, 1}, '{0, 6}, '{7, 4}, 5);
        Step('{1, 1}, '{0, 1}, '{5, 7}, '{0, 3}, 6);
        // Both pointers have wrapped. Drain the returned IDs in FIFO order.
        Step('{0, 0}, '{1, 1}, '{0, 0}, '{2, 1}, 4);
        Step('{0, 0}, '{1, 1}, '{0, 0}, '{0, 6}, 2);
        Step('{0, 0}, '{1, 1}, '{0, 0}, '{5, 7}, 0);
        Step('{0, 0}, '{0, 0}, '{7, 7}, '{0, 0}, 0);

        // Return and allocate one ID using only lane 1 while the list is otherwise empty.
        Step('{0, 1}, '{0, 0}, '{0, 6}, '{0, 0}, 1);
        Step('{0, 0}, '{0, 1}, '{0, 0}, '{0, 6}, 0);

        // Refill to capacity and drain again, including a wrap from an odd pointer position.
        Step('{1, 1}, '{0, 0}, '{7, 6}, '{0, 0}, 2);
        Step('{1, 1}, '{0, 0}, '{5, 4}, '{0, 0}, 4);
        Step('{1, 1}, '{0, 0}, '{3, 2}, '{0, 0}, 6);
        Step('{1, 1}, '{0, 0}, '{1, 0}, '{0, 0}, 8);
        Step('{0, 0}, '{1, 1}, '{0, 0}, '{7, 6}, 6);
        Step('{0, 0}, '{1, 1}, '{0, 0}, '{5, 4}, 4);
        Step('{0, 0}, '{1, 1}, '{0, 0}, '{3, 2}, 2);
        Step('{0, 0}, '{1, 1}, '{0, 0}, '{1, 0}, 0);

        $display("========== Test Passed ==========");
        $finish;
    end
endmodule
