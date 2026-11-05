// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;
import OpFormatTypes::*;
import ActiveListIndexTypes::*;

module TestFPDivSqrtUnit;
    localparam MAX_CYCLES = 48;
    logic clk = FALSE, rst = TRUE, rstStart = TRUE;
    FPDivSqrtUnitIF port(.*);
    RecoveryManagerIF recovery(.*);
    FPDivSqrtUnit dut(port, recovery);

    OpDst expectedDst[FP_DIVSQRT_ISSUE_WIDTH];
    ActiveListIndexPath expectedPtr[FP_DIVSQRT_ISSUE_WIDTH];
    DataPath expectedResult[FP_DIVSQRT_ISSUE_WIDTH];
    FFlags_Path expectedFlags[FP_DIVSQRT_ISSUE_WIDTH];
    bit pending[FP_DIVSQRT_ISSUE_WIDTH], started[FP_DIVSQRT_ISSUE_WIDTH];
    bit passedRW[FP_DIVSQRT_ISSUE_WIDTH];
    int completions[FP_DIVSQRT_ISSUE_WIDTH];
    int cases = 0;

    // Check only the externally visible request/accept interface. The ordinary
    // RW stage owns invalidation and RF/AL writes; this unit retains a result
    // until that stage accepts it. No internal state is inspected or forced.
    task automatic Tick;
        #4;
        for (int i = 0; i < FP_DIVSQRT_ISSUE_WIDTH; i++) begin
            assert (!$isunknown(port.writeValid[i]))
                else $fatal(1, "Unknown divider control on lane %0d", i);
            if (!rst) begin
                assert (!$isunknown({port.Busy[i], port.Reserved[i], port.Free[i]}))
                    else $fatal(1, "Unknown divider state on lane %0d", i);
            end
            if (rst || port.stall) begin
                assert (!port.writeValid[i])
                    else $fatal(1, "Divider offered a result during reset/stall");
            end
            if (port.writeValid[i]) begin
                assert (pending[i] && started[i] && passedRW[i] &&
                        port.writePtr[i] === expectedPtr[i] &&
                        port.pendingDst[i] === expectedDst[i] &&
                        port.DataOut[i] === expectedResult[i] &&
                        port.FFlagsOut[i] === expectedFlags[i])
                    else $fatal(1, "Unexpected completion on lane %0d: result=%h flags=%b, expected %h/%b",
                                i, port.DataOut[i], port.FFlagsOut[i], expectedResult[i], expectedFlags[i]);
                if (port.writeReady[i]) begin
                    assert (!port.Busy[i] && port.Free[i])
                        else $fatal(1, "Accepted completion did not release divider");
                    pending[i] = FALSE;
                    completions[i]++;
                end
                else begin
                    assert (port.Busy[i] && !port.Free[i])
                        else $fatal(1, "Unaccepted completion released divider");
                end
            end
        end
        clk = TRUE;
        #1; clk = FALSE;
        #1;
    endtask

    task automatic Acquire(input int lane, input int ptr, input int dst, input bit writeReg = TRUE);
        assert (port.Free[lane] === TRUE && !pending[lane])
            else $fatal(1, "Divider lane %0d was not free", lane);
        expectedPtr[lane] = ActiveListIndexPath'(ptr);
        expectedDst[lane] = '0;
        expectedDst[lane].phyDstRegNum.regNum = PScalarRegNumPath'(dst);
`ifdef RSD_MARCH_FP_PIPE
        expectedDst[lane].phyDstRegNum.isFP = TRUE;
`endif
        expectedDst[lane].writeReg = writeReg;
        pending[lane] = TRUE;
        started[lane] = FALSE;
        passedRW[lane] = FALSE;
        completions[lane] = 0;
        port.Acquire[lane] = TRUE;
        port.acquireActiveListPtr[lane] = expectedPtr[lane];
        port.acquireOpDst[lane] = expectedDst[lane];
        Tick();
        assert (port.Reserved[lane] === TRUE && port.Free[lane] === FALSE &&
                port.pendingDst[lane] === expectedDst[lane])
            else $fatal(1, "DIV reservation failed on lane %0d", lane);
        port.Acquire[lane] = FALSE;
        // Later issues must not replace the retained destination/ActiveList tag.
        port.acquireActiveListPtr[lane] = '1;
        port.acquireOpDst[lane] = '0;
    endtask

    task automatic PassRW(input int lane);
        // The successful pipeline attempt reached normal RW. Its invalidation
        // is sampled on this edge, so completion must wait until a later edge.
        port.passedRW[lane] = TRUE;
        Tick();
        passedRW[lane] = TRUE;
        port.passedRW[lane] = FALSE;
    endtask

    task automatic Start(input int lane, input DataPath a, input DataPath b,
                         input bit divide, input DataPath result, input FFlags_Path flags,
                         input bit passRW = TRUE, input Rounding_Mode rounding = RM_RNE);
        expectedResult[lane] = result;
        expectedFlags[lane] = flags;
        started[lane] = TRUE;
        port.dataInA[lane] = a;
        port.dataInB[lane] = b;
        port.is_divide[lane] = divide;
        port.rm[lane] = rounding;
        port.Req[lane] = TRUE;
        Tick();
        assert (port.Busy[lane] === TRUE && port.Reserved[lane] === FALSE)
            else $fatal(1, "FP operation was not accepted on lane %0d", lane);
        port.Req[lane] = FALSE;
        // A later operation's inputs must not change the retained result/flags.
        port.dataInA[lane] = ~a;
        port.dataInB[lane] = ~b;
        port.is_divide[lane] = !divide;
        port.rm[lane] = RM_RDN;
        if (passRW) PassRW(lane);
    endtask

    task automatic WaitForWrite(input int lane);
        for (int cycle = 0; cycle < MAX_CYCLES; cycle++) begin
            if (port.writeValid[lane] === TRUE)
                return;
            Tick();
        end
        $fatal(1, "DIV completion timed out on lane %0d", lane);
    endtask

    task automatic Finish(input int lane);
        WaitForWrite(lane);
        Tick();
        assert (completions[lane] == 1 && port.Free[lane] === TRUE)
            else $fatal(1, "DIV did not complete exactly once on lane %0d", lane);
        repeat (3) Tick();
        cases++;
    endtask

    task automatic SetFlush(input int headPtr, input int tailPtr, input bit all = FALSE);
        recovery.toRecoveryPhase = TRUE;
        recovery.flushRangeHeadPtr = ActiveListIndexPath'(headPtr);
        recovery.flushRangeTailPtr = ActiveListIndexPath'(tailPtr);
        recovery.flushAllInsns = all;
    endtask

    task automatic Cancel(input int lane, input int headPtr, input int tailPtr, input bit all = FALSE);
        SetFlush(headPtr, tailPtr, all);
        // Any result that was about to be written must lose to the flush.
        #1;
        assert (!port.writeValid[lane])
            else $fatal(1, "Flushed DIV still writes on lane %0d", lane);
        Tick();
        pending[lane] = FALSE;
        recovery.toRecoveryPhase = FALSE;
        recovery.flushAllInsns = FALSE;
        repeat (MAX_CYCLES) Tick();
        assert (completions[lane] == 0 && port.Free[lane] === TRUE)
            else $fatal(1, "Cancelled DIV completed or stayed busy on lane %0d", lane);
        cases++;
    endtask

    initial begin
        #100000;
        $fatal(1, "FPDivSqrtUnit protocol test timed out");
    end

    initial begin
        port.stall = FALSE;
        recovery.toRecoveryPhase = FALSE;
        recovery.flushRangeHeadPtr = '0;
        recovery.flushRangeTailPtr = '0;
        recovery.flushAllInsns = FALSE;
        for (int i = 0; i < FP_DIVSQRT_ISSUE_WIDTH; i++) begin
            pending[i] = FALSE;
            started[i] = FALSE;
            passedRW[i] = FALSE;
            completions[i] = 0;
            port.Acquire[i] = FALSE;
            port.passedRW[i] = FALSE;
            port.writeReady[i] = TRUE;
            port.Req[i] = FALSE;
            port.acquireActiveListPtr[i] = '0;
            port.acquireOpDst[i] = '0;
            port.dataInA[i] = '0;
            port.dataInB[i] = '0;
            port.is_divide[i] = TRUE;
            port.rm[i] = RM_RNE;
        end
        repeat (2) Tick();
        rst = FALSE;
        rstStart = FALSE;
        Tick();

        for (int lane = 0; lane < FP_DIVSQRT_ISSUE_WIDTH; lane++) begin
            // Reservation must not block the missing-operand replay that starts it.
            Acquire(lane, 10, 7);
            repeat (4) begin
                Tick();
                assert (port.Reserved[lane] && !port.Busy[lane] && !port.writeValid[lane])
                    else $fatal(1, "FP unit did not wait for operands");
            end
            Start(lane, 32'h40c00000, 32'h40000000, TRUE, 32'h40400000, '0); // 6/2
            Finish(lane);

            // The stale tag of a FREE unit must not cancel a new reservation.
            SetFlush(8, 12);
            Acquire(lane, 20, 8);
            recovery.toRecoveryPhase = FALSE;
            Start(lane, 32'h40800000, 0, FALSE, 32'h40000000, '0); // sqrt(4)
            Finish(lane);

            // f0 is a writable destination, unlike integer x0.
            Acquire(lane, 21, 0);
            Start(lane, 32'h3f800000, 0, TRUE, 32'h7f800000, FFlags_Path'(5'b01000));
            Finish(lane);
            Acquire(lane, 22, 9);
            Start(lane, 32'hbf800000, 0, FALSE, 32'h7fc00000, FFlags_Path'(5'b10000));
            Finish(lane);
            Acquire(lane, 23, 10);
            Start(lane, 32'h3f800000, 32'h40400000, TRUE, 32'h3eaaaaab, FFlags_Path'(5'b00001));
            Finish(lane);
            Acquire(lane, 23, 10);
            Start(lane, 32'h3f800000, 32'h40400000, TRUE, 32'h3eaaaaaa,
                  FFlags_Path'(5'b00001), TRUE, RM_RTZ);
            Finish(lane);
            Acquire(lane, 23, 10);
            Start(lane, 32'h7f7fffff, 32'h00800000, TRUE, 32'h7f800000, FFlags_Path'(5'b00101));
            Finish(lane);
            Acquire(lane, 23, 10);
            Start(lane, 32'h00000001, 32'h40000000, TRUE, 0, FFlags_Path'(5'b00011));
            Finish(lane);

            Acquire(lane, 24, 11);
            Cancel(lane, 24, 25); // Reserved, before operands arrive.
            Acquire(lane, 2, 12);
            Start(lane, 32'h40000000, 0, FALSE, 32'h3fb504f3, FFlags_Path'(5'b00001));
            repeat (2) Tick();
            Cancel(lane, ACTIVE_LIST_ENTRY_NUM - 4, 4); // Circular flush range.
            Acquire(lane, 26, 13);
            Start(lane, 32'h40c00000, 32'h40000000, TRUE, 32'h40400000, '0);
            WaitForWrite(lane);
            Cancel(lane, 0, 0, TRUE); // Flush wins over a ready completion.

            // Arithmetic may finish during a backend stall; keep both result
            // and flags until the original destination can accept them.
            Acquire(lane, 28, 14);
            Start(lane, 32'h40000000, 0, FALSE, 32'h3fb504f3, FFlags_Path'(5'b00001));
            port.stall = TRUE;
            repeat (MAX_CYCLES) Tick();
            assert (port.Busy[lane] && !port.Free[lane] && completions[lane] == 0)
                else $fatal(1, "FP unit lost completion during stall");
            port.stall = FALSE;
            #1;
            Finish(lane);

            // Delay pipeline RW artificially until computation has finished.
            // The result/flags must remain hidden until invalidation has passed.
            Acquire(lane, 29, 18);
            Start(lane, 32'h3f800000, 0, TRUE, 32'h7f800000, FFlags_Path'(5'b01000), FALSE);
            repeat (MAX_CYCLES) begin
                Tick();
                assert (!port.writeValid[lane] && port.Busy[lane] &&
                        !port.Free[lane] && completions[lane] == 0)
                    else $fatal(1, "FP operation completed before passing normal RW");
            end
            PassRW(lane);
            Finish(lane);

            // Keep a nonzero exception flag stable through an occupied RW port.
            Acquire(lane, 30, 19);
            port.writeReady[lane] = FALSE;
            Start(lane, 32'h3f800000, 32'h40400000, TRUE, 32'h3eaaaaab, FFlags_Path'(5'b00001));
            WaitForWrite(lane);
            repeat (2 * MAX_CYCLES) begin
                Tick();
                assert (port.writeValid[lane] && port.Busy[lane] && completions[lane] == 0)
                    else $fatal(1, "FP unit lost its pending result while RW was busy");
            end
            port.writeReady[lane] = TRUE;
            #1;
            Finish(lane);

            // Flush an already computed exception without leaking its flags.
            Acquire(lane, 31, 0);
            port.writeReady[lane] = FALSE;
            Start(lane, 32'hbf800000, 0, FALSE, 32'h7fc00000, FFlags_Path'(5'b10000));
            WaitForWrite(lane);
            Cancel(lane, 31, 32);
            port.writeReady[lane] = TRUE;

            // A younger branch recovery must preserve an older operation.
            Acquire(lane, 10, 15);
            Start(lane, 32'h40000000, 0, FALSE, 32'h3fb504f3, FFlags_Path'(5'b00001));
            SetFlush(20, 30);
            Tick();
            recovery.toRecoveryPhase = FALSE;
            Finish(lane);

            Acquire(lane, 31, 16);
            Start(lane, 32'h3f800000, 32'h40400000, TRUE, 32'h3eaaaaab, FFlags_Path'(5'b00001));
            rst = TRUE;
            Tick();
            pending[lane] = FALSE;
            rst = FALSE;
            repeat (MAX_CYCLES) Tick();
            assert (completions[lane] == 0 && port.Free[lane])
                else $fatal(1, "Reset did not cancel FP operation");
            cases++;

            // Reusing the unit must not inherit a previous exception flag.
            Acquire(lane, 32, 17);
            Start(lane, 32'h40800000, 0, FALSE, 32'h40000000, '0);
            Finish(lane);
        end

        $display("========== Test Passed: FPDivSqrtUnit %0d protocol cases ==========", cases);
        $finish;
    end
endmodule
