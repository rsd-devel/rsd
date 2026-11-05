// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;
import OpFormatTypes::*;
import ActiveListIndexTypes::*;

module TestMulDivUnit;
    localparam MAX_CYCLES = DATA_WIDTH + 8;
    logic clk = FALSE, rst = TRUE, rstStart = TRUE;
    MulDivUnitIF port(.*);
    RecoveryManagerIF recovery(.*);
    MulDivUnit dut(port, recovery);

    OpDst expectedDst[MULDIV_ISSUE_WIDTH];
    ActiveListIndexPath expectedPtr[MULDIV_ISSUE_WIDTH];
    DataPath expectedResult[MULDIV_ISSUE_WIDTH];
    bit pending[MULDIV_ISSUE_WIDTH], started[MULDIV_ISSUE_WIDTH];
    bit passedRW[MULDIV_ISSUE_WIDTH];
    int completions[MULDIV_ISSUE_WIDTH];
    int cases = 0;

    // Check only the externally visible request/accept interface. The ordinary
    // RW stage owns invalidation and RF/AL writes; this unit retains a result
    // until that stage accepts it. No internal state is inspected or forced.
    task automatic Tick;
        #4;
        for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin
            assert (!$isunknown(port.divWriteValid[i]))
                else $fatal(1, "Unknown divider control on lane %0d", i);
            if (!rst) begin
                assert (!$isunknown({port.divBusy[i], port.divReserved[i], port.divFree[i]}))
                    else $fatal(1, "Unknown divider state on lane %0d", i);
            end
            if (rst || port.stall) begin
                assert (!port.divWriteValid[i])
                    else $fatal(1, "Divider offered a result during reset/stall");
            end
            if (port.divWriteValid[i]) begin
                assert (pending[i] && started[i] && passedRW[i] &&
                        port.divWritePtr[i] === expectedPtr[i] &&
                        port.divPendingDst[i] === expectedDst[i] &&
                        port.divWriteData[i] === expectedResult[i])
                    else $fatal(1, "Unexpected completion on lane %0d: expected %h, got %h",
                                i, expectedResult[i], port.divWriteData[i]);
                if (port.divWriteReady[i]) begin
                    assert (!port.divBusy[i] && port.divFree[i])
                        else $fatal(1, "Accepted completion did not release divider");
                    pending[i] = FALSE;
                    completions[i]++;
                end
                else begin
                    assert (port.divBusy[i] && !port.divFree[i])
                        else $fatal(1, "Unaccepted completion released divider");
                end
            end
        end
        clk = TRUE;
        #1; clk = FALSE;
        #1;
    endtask

    task automatic Acquire(input int lane, input int ptr, input int dst, input bit writeReg = TRUE);
        assert (port.divFree[lane] === TRUE && !pending[lane])
            else $fatal(1, "Divider lane %0d was not free", lane);
        expectedPtr[lane] = ActiveListIndexPath'(ptr);
        expectedDst[lane] = '0;
        expectedDst[lane].phyDstRegNum.regNum = PScalarRegNumPath'(dst);
        expectedDst[lane].writeReg = writeReg;
        pending[lane] = TRUE;
        started[lane] = FALSE;
        passedRW[lane] = FALSE;
        completions[lane] = 0;
        port.divAcquire[lane] = TRUE;
        port.acquireActiveListPtr[lane] = expectedPtr[lane];
        port.acquireOpDst[lane] = expectedDst[lane];
        Tick();
        assert (port.divReserved[lane] === TRUE && port.divFree[lane] === FALSE &&
                port.divPendingDst[lane] === expectedDst[lane])
            else $fatal(1, "DIV reservation failed on lane %0d", lane);
        port.divAcquire[lane] = FALSE;
        // Later issues must not replace the retained destination/ActiveList tag.
        port.acquireActiveListPtr[lane] = '1;
        port.acquireOpDst[lane] = '0;
    endtask

    task automatic PassRW(input int lane);
        // The successful pipeline attempt reached normal RW. Its invalidation
        // is sampled on this edge, so completion must wait until a later edge.
        port.divPassedRW[lane] = TRUE;
        Tick();
        passedRW[lane] = TRUE;
        port.divPassedRW[lane] = FALSE;
    endtask

    task automatic Start(input int lane, input DataPath a, input DataPath b,
                         input IntDIV_Code code, input DataPath result, input bit passRW = TRUE);
        expectedResult[lane] = result;
        started[lane] = TRUE;
        port.dataInA[lane] = a;
        port.dataInB[lane] = b;
        port.divCode[lane] = code;
        port.divReq[lane] = TRUE;
        Tick();
        assert (port.divBusy[lane] === TRUE && port.divReserved[lane] === FALSE)
            else $fatal(1, "DIV request was not accepted on lane %0d", lane);
        port.divReq[lane] = FALSE;
        port.dataInA[lane] = ~a;
        port.dataInB[lane] = ~b;
        port.divCode[lane] = AC_REMU;
        if (passRW) PassRW(lane);
    endtask

    task automatic WaitForWrite(input int lane);
        for (int cycle = 0; cycle < MAX_CYCLES; cycle++) begin
            if (port.divWriteValid[lane] === TRUE)
                return;
            Tick();
        end
        $fatal(1, "DIV completion timed out on lane %0d", lane);
    endtask

    task automatic Finish(input int lane);
        WaitForWrite(lane);
        Tick();
        assert (completions[lane] == 1 && port.divFree[lane] === TRUE)
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
        assert (!port.divWriteValid[lane])
            else $fatal(1, "Flushed DIV still writes on lane %0d", lane);
        Tick();
        pending[lane] = FALSE;
        recovery.toRecoveryPhase = FALSE;
        recovery.flushAllInsns = FALSE;
        repeat (MAX_CYCLES) Tick();
        assert (completions[lane] == 0 && port.divFree[lane] === TRUE)
            else $fatal(1, "Cancelled DIV completed or stayed busy on lane %0d", lane);
        cases++;
    endtask

    initial begin
        #100000;
        $fatal(1, "MulDivUnit protocol test timed out");
    end

    initial begin
        port.stall = FALSE;
        recovery.toRecoveryPhase = FALSE;
        recovery.flushRangeHeadPtr = '0;
        recovery.flushRangeTailPtr = '0;
        recovery.flushAllInsns = FALSE;
        for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin
            pending[i] = FALSE;
            started[i] = FALSE;
            passedRW[i] = FALSE;
            completions[i] = 0;
            port.divAcquire[i] = FALSE;
            port.divPassedRW[i] = FALSE;
            port.divWriteReady[i] = TRUE;
            port.divReq[i] = FALSE;
            port.acquireActiveListPtr[i] = '0;
            port.acquireOpDst[i] = '0;
            port.dataInA[i] = '0;
            port.dataInB[i] = '0;
            port.divCode[i] = AC_DIV;
            port.mulCode[i] = AC_MUL;
            port.mulGetUpper[i] = FALSE;
        end
        repeat (2) Tick();
        rst = FALSE;
        rstStart = FALSE;
        Tick();

        for (int lane = 0; lane < MULDIV_ISSUE_WIDTH; lane++) begin
            // Missing operands reserve the divider without starting computation.
            Acquire(lane, 10, 7);
            repeat (4) begin
                Tick();
                assert (port.divReserved[lane] && !port.divBusy[lane] && !port.divWriteValid[lane])
                    else $fatal(1, "DIV did not wait for operands");
            end
            Start(lane, 84, 7, AC_DIV, 12);
            Finish(lane);

            // The stale tag of a FREE divider must not cancel a new reservation.
            SetFlush(8, 12);
            Acquire(lane, 20, 8);
            recovery.toRecoveryPhase = FALSE;
            Start(lane, DataPath'(-29), 6, AC_REM, DataPath'(-5));
            Finish(lane);
            Acquire(lane, 21, 9);
            Start(lane, 32'hffffffff, 3, AC_DIVU, 32'h55555555);
            Finish(lane);
            Acquire(lane, 22, 10);
            Start(lane, 32'h80000000, 0, AC_REMU, 32'h80000000);
            Finish(lane);

            // rd=x0 must still request completion; only the RW stage suppresses RF WE.
            Acquire(lane, 23, 0, FALSE);
            Start(lane, 19, 0, AC_DIV, 32'hffffffff);
            Finish(lane);

            Acquire(lane, 24, 11);
            Cancel(lane, 24, 25); // Reserved, before operands arrive.
            Acquire(lane, 2, 12);
            Start(lane, 32'h80000000, 3, AC_DIVU, 32'h2aaaaaaa);
            repeat (2) Tick();
            Cancel(lane, ACTIVE_LIST_ENTRY_NUM - 4, 4); // Circular flush range.
            Acquire(lane, 26, 13);
            Start(lane, 21, 3, AC_DIV, 7);
            WaitForWrite(lane);
            Cancel(lane, 0, 0, TRUE); // Flush wins over ready writeback.

            // Computation may finish during a backend stall; the result must be
            // held and written once after the stall, with its original metadata.
            Acquire(lane, 28, 14);
            Start(lane, 17, 3, AC_REMU, 2);
            port.stall = TRUE;
            repeat (MAX_CYCLES) Tick();
            assert (port.divBusy[lane] && !port.divFree[lane] && completions[lane] == 0)
                else $fatal(1, "DIV did not retain completion during stall");
            port.stall = FALSE;
            #1;
            Finish(lane);

            // Even the shortest computation must wait for its successful
            // pipeline attempt to leave RW. A late invalidation must never
            // overwrite the final value, including after reuse of the unit.
            Acquire(lane, 29, 18);
            Start(lane, 0, 7, AC_DIVU, 0, FALSE);
            repeat (MAX_CYCLES) begin
                Tick();
                assert (!port.divWriteValid[lane] && port.divBusy[lane] &&
                        !port.divFree[lane] && completions[lane] == 0)
                    else $fatal(1, "DIV completed before passing normal RW");
            end
            PassRW(lane);
            Finish(lane);

            // Normal RW can be occupied for an arbitrarily long burst. The
            // request, data and tags remain stable and only one accept occurs.
            Acquire(lane, 30, 19);
            port.divWriteReady[lane] = FALSE;
            Start(lane, 99, 4, AC_DIVU, 24);
            WaitForWrite(lane);
            repeat (2 * MAX_CYCLES) begin
                Tick();
                assert (port.divWriteValid[lane] && port.divBusy[lane] &&
                        completions[lane] == 0)
                    else $fatal(1, "DIV lost its pending result while RW was busy");
            end
            port.divWriteReady[lane] = TRUE;
            #1;
            Finish(lane);

            // A flush also cancels an already completed but unaccepted result.
            Acquire(lane, 31, 0, FALSE);
            port.divWriteReady[lane] = FALSE;
            Start(lane, 7, 2, AC_REMU, 1);
            WaitForWrite(lane);
            Cancel(lane, 31, 32);
            port.divWriteReady[lane] = TRUE;

            // A younger branch recovery must not discard an older division.
            Acquire(lane, 10, 15);
            Start(lane, 32'h80000000, 3, AC_DIVU, 32'h2aaaaaaa);
            SetFlush(20, 30);
            Tick();
            recovery.toRecoveryPhase = FALSE;
            Finish(lane);

            // Reset also cancels an in-flight operation without a later write.
            Acquire(lane, 31, 16);
            Start(lane, 32'h80000000, 3, AC_DIVU, 32'h2aaaaaaa);
            rst = TRUE;
            Tick();
            pending[lane] = FALSE;
            rst = FALSE;
            repeat (MAX_CYCLES) Tick();
            assert (completions[lane] == 0 && port.divFree[lane])
                else $fatal(1, "Reset did not cancel DIV");
            cases++;
            Acquire(lane, 32, 17);
            Start(lane, 32'h80000000, 32'hffffffff, AC_DIV, 32'h80000000);
            Finish(lane);
        end

        $display("========== Test Passed: MulDivUnit %0d protocol cases ==========" , cases);
        $finish;
    end
endmodule
