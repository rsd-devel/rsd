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
    RegisterFileIF registerFile(.*);
    ActiveListIF activeList(.*);
    MulDivUnit dut(port, recovery, registerFile, activeList);

    OpDst expectedDst[MULDIV_ISSUE_WIDTH];
    ActiveListIndexPath expectedPtr[MULDIV_ISSUE_WIDTH];
    DataPath expectedResult[MULDIV_ISSUE_WIDTH];
    bit pending[MULDIV_ISSUE_WIDTH], started[MULDIV_ISSUE_WIDTH];
    int invalidations[MULDIV_ISSUE_WIDTH], completions[MULDIV_ISSUE_WIDTH];
    int cases = 0;

    // Check the externally visible writes at the edge where RF/AL would accept
    // them. No internal state is forced or used to decide when DIV has finished.
    task automatic Tick;
        #4;
        for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin
            assert (!$isunknown({registerFile.divDstRegWE[i], activeList.divWrite[i]}))
                else $fatal(1, "Unknown write enable on divider lane %0d", i);
            if (rst) begin
                assert (!registerFile.divDstRegWE[i] && !activeList.divWrite[i])
                    else $fatal(1, "Divider wrote during reset");
            end
            else begin
                if (registerFile.divDstRegWE[i]) begin
                    assert (pending[i] && expectedDst[i].writeReg &&
                            registerFile.divDstRegNum[i] === expectedDst[i].phyDstRegNum)
                        else $fatal(1, "Unexpected RF destination on lane %0d", i);
                    if (registerFile.divDstRegData[i].valid === FALSE) begin
                        assert (!started[i] && invalidations[i] == 0 && !activeList.divWrite[i])
                            else $fatal(1, "Late or repeated invalidation on lane %0d", i);
                        invalidations[i]++;
                    end
                    else begin
                        assert (registerFile.divDstRegData[i].valid === TRUE &&
                                activeList.divWrite[i] &&
                                registerFile.divDstRegData[i].data === expectedResult[i])
                            else $fatal(1, "Bad DIV result on lane %0d: expected %h, got %h",
                                        i, expectedResult[i], registerFile.divDstRegData[i]);
                    end
                end
                if (activeList.divWrite[i]) begin
                    assert (pending[i] && started[i] && !port.stall &&
                            activeList.divWritePtr[i] === expectedPtr[i] &&
                            registerFile.divDstRegWE[i] === expectedDst[i].writeReg)
                        else $fatal(1, "Unexpected completion on lane %0d", i);
                    pending[i] = FALSE;
                    completions[i]++;
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
        invalidations[lane] = 0;
        completions[lane] = 0;
        port.divAcquire[lane] = TRUE;
        port.acquireActiveListPtr[lane] = expectedPtr[lane];
        port.acquireOpDst[lane] = expectedDst[lane];
        Tick();
        assert (port.divReserved[lane] === TRUE && port.divFree[lane] === FALSE &&
                invalidations[lane] == int'(writeReg) &&
                port.divPendingDst[lane] === expectedDst[lane])
            else $fatal(1, "DIV reservation/invalidation failed on lane %0d", lane);
        port.divAcquire[lane] = FALSE;
        // Later issues must not replace the retained destination/ActiveList tag.
        port.acquireActiveListPtr[lane] = '1;
        port.acquireOpDst[lane] = '0;
    endtask

    task automatic Start(input int lane, input DataPath a, input DataPath b,
                         input IntDIV_Code code, input DataPath result);
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
    endtask

    task automatic WaitForWrite(input int lane);
        for (int cycle = 0; cycle < MAX_CYCLES; cycle++) begin
            if (activeList.divWrite[lane] === TRUE)
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
        assert (!activeList.divWrite[lane] && !registerFile.divDstRegWE[lane])
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
            invalidations[i] = 0;
            completions[i] = 0;
            port.divAcquire[i] = FALSE;
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
                assert (port.divReserved[lane] && !port.divBusy[lane] && !activeList.divWrite[lane])
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

            // rd=x0 still completes the instruction but never writes the RF.
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
