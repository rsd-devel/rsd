// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

import BasicTypes::*;
import MemoryMapTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import FetchUnitTypes::*;
import PipelineTypes::*;
import ActiveListIndexTypes::*;

module TestBranchRecovery;
    bit clk, rst, rstStart;
    IntegerExecutionStageIF ex(.*);
    SchedulerIF scheduler(.*);
    FetchStageIF fetch(.*);
    RegisterFileIF rf(.*);
    ActiveListIF al(.*);
    RecoveryManagerIF rec(.*);
    ControllerIF ctrl(.*);
    DebugIF dbg(.*);
    CommitStageIF cm(.*);
    RenameLogicIF renameLogic(.*);
    LoadStoreUnitIF lsu(.*);
    CSR_UnitIF csr(.*);
    DecodeStageIF idStage(.*);
    PerformanceCounterIF perf(.*);

    IntegerRegisterWriteStage rw(ex, scheduler, fetch, rf, al, rec, ctrl, dbg);
    ActiveList activeList(al, rec, ctrl, dbg);
    CommitStage commitStage(cm, renameLogic, al, lsu, rec, csr, dbg);
    RecoveryManager recovery(rec, al, csr, idStage, ctrl, perf);

    always_comb al.popHeadNum = renameLogic.commitNum;

    task automatic Tick();
        #5 clk = 1;
        #5 clk = 0;
        #1;
    endtask

    // Two consecutive active-list entries may belong to distant instruction addresses.
    localparam PC_Path PC0 = 'h80001640, PC1 = 'h800028ac;
    localparam PC_Path TARGET0 = 'h80003ab0, TARGET1 = 'h80004318;
    localparam LAST_RW_LANE = INT_ISSUE_WIDTH - 1;

    task automatic ResetAndAllocate();
        rst = TRUE;
        rec.replayQueueFlushedOpExist = FALSE;
        foreach (ex.nextStage[i]) ex.nextStage[i] = '0;
        foreach (al.pushTail[i]) al.pushTail[i] = FALSE;
        Tick();
        rst = FALSE;
        al.pushTail[0] = TRUE;
        for (int i = 0; i < 2; i++) begin
            al.pushedTailData[0] = '0;
            al.pushedTailData[0].pc = i == 0 ? PC0 : PC1;
            al.pushedTailData[0].isBranch = TRUE;
            al.pushedTailData[0].last = TRUE;
            Tick();
        end
        al.pushTail[0] = FALSE;
    endtask

    task automatic Complete(input int lane, input int entry, input bit mispred);
        ex.nextStage[lane] = '0;
        ex.nextStage[lane].valid = TRUE;
        ex.nextStage[lane].dataOut.valid = TRUE;
        ex.nextStage[lane].intQueueData.activeListPtr = ActiveListIndexPath'(entry);
        ex.nextStage[lane].intQueueData.opType = INT_MOP_TYPE_RIJ;
        ex.nextStage[lane].intQueueData.pc = entry == 0 ? PC0 : PC1;
        ex.nextStage[lane].brResult.brAddr = entry == 0 ? PC0 : PC1;
        ex.nextStage[lane].brResult.nextAddr = entry == 0 ? TARGET0 : TARGET1;
        ex.nextStage[lane].brResult.brType = BTB_CALL;
        ex.nextStage[lane].brResult.execTaken = TRUE;
        ex.nextStage[lane].brResult.valid = TRUE;
        ex.nextStage[lane].brResult.rasPtr = RAS_IndexPath'(entry + 1);
        ex.nextStage[lane].brMissPred = mispred;
    endtask

    task automatic CheckRedirect(input PC_Path target, input RAS_IndexPath ptr);
        assert (rec.fetchRedirect.valid && rec.fetchRedirect.restorePredCtx &&
                rec.fetchRedirect.pc == target && rec.fetchRedirect.predCtx.rasPtr == ptr &&
                !rec.fetchRedirect.rasPush && rec.fetchRedirect.rasReturnPC == '0)
            else $fatal(1, "Expected redirect to %h with RAS pointer %0d and no RAS write", target, ptr);
    endtask

    initial begin
        ctrl.backEnd = '0;
        rec.renameLogicRecoveryRMT = FALSE;
        rec.issueQueueReturnIndex = FALSE;
        rec.wakeupPipelineRegFlushedOpExist = FALSE;
        rec.redirectFromRename = '0;
        al.popTailNum = '0;
        foreach (al.memWrite[i]) al.memWrite[i] = FALSE;
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        foreach (al.complexWrite[i]) al.complexWrite[i] = FALSE;
`endif
`ifdef RSD_MARCH_FP_PIPE
        foreach (al.fpWrite[i]) al.fpWrite[i] = FALSE;
`endif
        // Immediate recovery must use the older call on the last RW lane.
        ResetAndAllocate();
        if (INT_ISSUE_WIDTH > 1)
            Complete(0, 1, TRUE);
        Complete(LAST_RW_LANE, 0, TRUE);
        Tick();
        assert (rec.exceptionDetectedInRwStage && !rec.exceptionDetectedInCommitStage)
            else $fatal(1, "Expected immediate RW recovery");
        foreach (ex.nextStage[i]) ex.nextStage[i] = '0;
        Tick();
        // A younger Decode call requests a RAS write in the same cycle as the RW redirect.
        rec.redirectFromRename.valid = TRUE;
        rec.redirectFromRename.pc = TARGET1;
        rec.redirectFromRename.restorePredCtx = TRUE;
        rec.redirectFromRename.predCtx.rasPtr = RAS_IndexPath'(3);
        rec.redirectFromRename.rasPush = TRUE;
        rec.redirectFromRename.rasReturnPC = PC1 + INSN_BYTE_WIDTH;
        #1;
        CheckRedirect(TARGET0, 2);
        rec.redirectFromRename = '0;

        // Delay the second call's recovery until both entries reach the commit frontier.
        ResetAndAllocate();
        rec.replayQueueFlushedOpExist = TRUE;
        Complete(0, 1, TRUE);
        Tick();
        assert (!rec.exceptionDetectedInRwStage) else $fatal(1, "RW recovery should be blocked");
        ex.nextStage[0] = '0;
        Tick();
        rec.replayQueueFlushedOpExist = FALSE;
        Complete(LAST_RW_LANE, 0, FALSE);
        Tick();
        ex.nextStage[LAST_RW_LANE] = '0;
        Tick();
        if (COMMIT_WIDTH == 1)
            Tick(); // Retire the older instruction before the call reaches the head.
        assert (rec.exceptionDetectedInCommitStage && rec.recoveryOpIndex == (COMMIT_WIDTH > 1) &&
                !rec.exceptionDetectedInRwStage) else $fatal(1, "Expected recovery from the deferred call");
        Tick();
        CheckRedirect(TARGET1, 3);

        // A misaligned JALR traps at its source PC with the bad target in mtval.
        ResetAndAllocate();
        csr.excptTargetAddr = 'h8000c000;
        Complete(LAST_RW_LANE, 0, TRUE);
        ex.nextStage[LAST_RW_LANE].brResult.nextAddr = TARGET0 + 2;
        Tick();
        ex.nextStage[LAST_RW_LANE] = '0;
        Tick();
        assert (rec.exceptionDetectedInCommitStage) else $fatal(1, "Expected a commit-time fault");
        Tick();
        assert (csr.triggerExcpt && csr.excptCause == EXEC_STATE_FAULT_INSN_MISALIGNED &&
                csr.excptCauseAddr == PC0 && csr.excptCauseDataAddr == TARGET0 + 2 &&
                rec.fetchRedirect.valid && rec.fetchRedirect.pc == csr.excptTargetAddr &&
                !rec.fetchRedirect.restorePredCtx && !rec.fetchRedirect.rasPush)
            else $fatal(1, "A misaligned JALR must report the faulting instruction and its target");
        $display("BranchRecovery: immediate RW, deferred commit and JALR trap passed");
        $finish;
    end
endmodule
