// Copyright 2026- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;
import FetchUnitTypes::*;

module TestBranchPredictorQueue;
    localparam int PHT_ROWS = PHT_ENTRY_NUM / FETCH_WIDTH;
    // Both PHT banks initialize one row per cycle.
    localparam int PHT_BANK_ROWS = PHT_ROWS / 2;
    localparam int RESET_CYCLES = (BTB_SET_NUM > PHT_BANK_ROWS ? BTB_SET_NUM : PHT_BANK_ROWS) + 1;
    logic clk = FALSE;
    logic rst = TRUE;
    logic rstStart = TRUE;
    always #5 clk = ~clk;

    FetchStageIF port(.*), bimodalPort(.*);
    ControllerIF ctrl(.*);
    RecoveryManagerIF recovery(.*);
    DebugIF debug(.*);
    PerformanceCounterIF perfCounter(.*);
    FetchStage fetch(.*);
    BTB btb(.port(port));
    RAS ras(.port(port), .recovery(recovery));
    Gshare gshare(.port(port), .ctrl(ctrl));
    Bimodal bimodal(.port(bimodalPort));

    // Exercise both predictors with the same fetch addresses and training results.
    always_comb begin
        bimodalPort.pcOut = port.pcOut;
        bimodalPort.phtReadRow = port.phtReadRow;
        bimodalPort.brLookupValid = port.brLookupValid;
        bimodalPort.capturePredRows = port.capturePredRows;
        bimodalPort.brResult = port.brResult;
    end

    function automatic BranchResult MakeResult(input int index, input bit btbHit = FALSE);
        BranchResult result;
        result = '0;
        result.valid = TRUE;
        result.btbHit = btbHit;
        result.execTaken = TRUE;
        result.brType = BTB_COND;
        result.brAddr = 32'h80000000 + index * INSN_BYTE_WIDTH;
        // Use a sequential predecessor by default. Non-sequential edges specify theirs below.
        result.brLookup.valid = TRUE;
        result.brLookup.ctx = MakeBranchHistoryContext(result.brAddr - FETCH_GROUP_BYTE_NUM, '0, FALSE);
        result.nextAddr = result.brAddr + 128;
        result.phtPrevValue = PHT_EntryPath'(index % PHT_ENTRY_MAX);
        return result;
    endfunction

    task ClearResults;
        foreach (port.brResult[i]) port.brResult[i] = '0;
    endtask

    task automatic CheckRecoveryRows;
        MemoryMapTypes::PC_Path pc, predecessor, expectedSource;
        BranchGlobalHistoryPath predecessorHistory, history, expectedRowHistory, expectedHistory;
        BranchLookupPath lookup;
        BranchHistoryContextPath recoveryCtx;
        predecessor = 32'h80001500 + FETCH_GROUP_BYTE_NUM + (FETCH_WIDTH - 1) * INSN_BYTE_WIDTH;
        predecessorHistory = USE_GSHARE ? BranchGlobalHistoryPath'(12'h535) : '0;
        for (int prevTaken = 0; prevTaken < 2; prevTaken++) begin
            lookup.ctx = MakeBranchHistoryContext(predecessor, predecessorHistory, prevTaken[0]);
            history = prevTaken ? ExpectedTakenHistory(predecessorHistory, predecessor) : predecessorHistory;
            for (int slot = 0; slot < FETCH_WIDTH; slot++) begin
                pc = 32'h800034e0 + slot * INSN_BYTE_WIDTH;
                for (int v = 0; v < 2; v++) begin
                    lookup.valid = v[0];
                    for (int resumeTaken = 0; resumeTaken < 2; resumeTaken++) begin
                        recoveryCtx = RecoverBranchHistory(pc, lookup, resumeTaken[0]);
                        if (lookup.valid && !resumeTaken && slot + 1 < FETCH_WIDTH) begin
                            // The suffix keeps the same entry history even if the predecessor was taken.
                            expectedSource = predecessor;
                            expectedRowHistory = predecessorHistory;
                        end
                        else begin
                            expectedSource = pc;
                            expectedRowHistory = history;
                        end
                        expectedHistory = resumeTaken ? ExpectedTakenHistory(history, pc) : history;
                        assert (BranchContextBTB_Set(recoveryCtx) == ToBTB_Set(expectedSource) &&
                                BranchContextPHT_Row(recoveryCtx) == ToPHT_Row(expectedSource, expectedRowHistory) &&
                                (!USE_GSHARE || BranchContextHistory(recoveryCtx) == expectedHistory))
                            else $fatal(1, "Recovery rows/history mismatch at slot %0d, valid %d, resume taken %d, predecessor taken %d",
                                        slot, lookup.valid, resumeTaken, prevTaken);
                    end
                end
            end
        end
    endtask

    // A warm redirect first reads the saved predecessor set. On the next edge the
    // target captures that row and starts the read for its own successor.
    task CompleteWarmRedirect;
        @(posedge clk);
        #1;
        assert (!fetch.pipeReg.valid) else $fatal(1, "A warm redirect must wait for its predecessor row");
        @(negedge clk);
        recovery.fetchRedirect.valid = FALSE;
        @(posedge clk);
        #1;
        recovery.fetchRedirect.valid = TRUE;
    endtask

    task ReadGroupFrom(input MemoryMapTypes::PC_Path pc, input MemoryMapTypes::PC_Path predecessor,
                       input BranchGlobalHistoryPath predecessorHistory = '0, input logic predecessorTaken = FALSE);
        @(negedge clk);
        recovery.fetchRedirect.pc = pc;
        recovery.fetchRedirect.restorePredCtx = TRUE;
        recovery.fetchRedirect.valid = TRUE;
        recovery.fetchRedirect.predCtx.ctx = MakeBranchHistoryContext(predecessor, predecessorHistory, predecessorTaken);
        CompleteWarmRedirect();
    endtask

    task ReadGroup(input MemoryMapTypes::PC_Path pc);
        ReadGroupFrom(pc, pc - FETCH_GROUP_BYTE_NUM);
    endtask

    task SendResults(input BranchResult first, input BranchResult second = '0);
        @(negedge clk);
        port.brResult[0] = first;
        port.brResult[1] = second;
        @(negedge clk);
        ClearResults();
        // Leave time for the PHT to service a free bank.
        @(negedge clk);
        if (second.valid) @(negedge clk);
    endtask

    // Hold the controller stall long enough for every queued update to reach the RAM.
    task DrainBTB;
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.stall = TRUE;
        repeat (BTB_QUEUE_SIZE + 1) @(negedge clk);
        assert (!btb.updatePending) else $fatal(1, "BTB queue did not drain during a sustained stall");
        ctrl.ifStage.stall = FALSE;
        recovery.fetchRedirect.valid = TRUE;
    endtask

    task WriteBTB(input BranchResult first, input BranchResult second = '0);
        SendResults(first, second);
        DrainBTB();
    endtask

    task CheckBTB(input int groupOffset, input BranchResult expected);
        assert (port.btbHit[groupOffset] === expected.valid &&
                (!expected.valid || (port.btbOut[groupOffset] === expected.nextAddr &&
                                     port.readBrType[groupOffset] === expected.brType)))
            else $fatal(1, "BTB PC %h group offset %0d expected hit %b target %h type %d",
                        fetch.fetchRequestPC, groupOffset, expected.valid, expected.nextAddr, expected.brType);
    endtask

    task CheckFetchRAS;
        BranchResult callOp, retOp;
        localparam CALL_STRIDE = 3 * FETCH_GROUP_BYTE_NUM;
        BranchResult firstCall;
        // Use a nonzero block tag to avoid aliasing the reset contents.
        callOp = MakeResult((BTB_SET_NUM + 12) * FETCH_WIDTH + FETCH_WIDTH - 1);
        retOp = MakeResult((BTB_SET_NUM + 17) * FETCH_WIDTH);
        callOp.brType = BTB_CALL;
        callOp.nextAddr = retOp.brAddr;
        retOp.brType = BTB_RETURN;
        retOp.brLookup.ctx = MakeBranchHistoryContext(callOp.brAddr, '0, TRUE);
        WriteBTB(callOp, retOp);

        ReadGroupFrom(retOp.brAddr, callOp.brAddr, '0, TRUE);
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.clear = FALSE;
        #1;
        assert (port.nextStage.brPred[0].usedRAS && fetch.fetchRequestPC === MemoryMapTypes::PC_Path'(32'h80000000))
            else $fatal(1, "A reset RAS entry must predict the base of the return's 256 KiB region");

        recovery.fetchRedirect.valid = TRUE;
        ReadGroup(callOp.brAddr);
        recovery.fetchRedirect.valid = FALSE;
        #1;
        assert (port.nextStage.valid[0] && fetch.fetchRequestPC == retOp.brAddr)
            else $fatal(1, "The call must fetch its target");
        @(posedge clk);
        #1;
        assert (port.nextStage.valid[0] && port.nextStage.brPred[0].usedRAS &&
                fetch.fetchRequestPC == callOp.brAddr + INSN_BYTE_WIDTH)
            else $fatal(1, "Back-to-back call and return must use the new stack top without a bubble");
        recovery.fetchRedirect.valid = TRUE;
        ctrl.ifStage.clear = TRUE;

        // Decode supplies a link in the next 256 KiB region. Fetch takes bits [31:18]
        // from the return instruction and retains all stored word-address bits [17:2].
        recovery.fetchRedirect.predCtx.rasPtr = RecoverRAS_Ptr(RAS_IndexPath'(2), BTB_CALL, TRUE);
        recovery.fetchRedirect.rasPush = TRUE;
        recovery.fetchRedirect.rasReturnPC = 32'h8007fffc;
        ReadGroupFrom(retOp.brAddr, callOp.brAddr, '0, TRUE);
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.clear = FALSE;
        #1;
        assert (port.nextStage.brPred[0].rasPtr == RAS_IndexPath'(3) && port.nextStage.brPred[0].usedRAS &&
                fetch.fetchRequestPC == MemoryMapTypes::PC_Path'(32'h8003fffc))
            else $fatal(1, "The repaired RAS entry must predict the last word in the return's region");
        recovery.fetchRedirect.rasPush = FALSE;
        ctrl.ifStage.stall = TRUE;
        repeat (3) begin
            @(posedge clk);
            #1;
            assert (port.rasPtr == RAS_IndexPath'(3)) else $fatal(1, "A held return changed the RAS");
        end
        ctrl.ifStage.stall = FALSE;
        #1;
        assert (port.nextStage.brPred[0].rasPtr == RAS_IndexPath'(3)) else $fatal(1, "Held return checkpoint changed");
        @(posedge clk);
        #1;
        assert (port.rasPtr == RAS_IndexPath'(2)) else $fatal(1, "A return must pop its checkpoint once");
        // Without a branch checkpoint an interrupt or cold redirect must leave that pointer alone.
        recovery.fetchRedirect.valid = TRUE;
        recovery.fetchRedirect.restorePredCtx = FALSE;
        port.interruptAddrIn = callOp.brAddr;
        port.interruptAddrWE = TRUE;
        ctrl.ifStage.clear = TRUE;
        @(posedge clk);
        #1;
        assert (port.rasPtr == RAS_IndexPath'(2)) else $fatal(1, "Interrupt entry changed the RAS pointer");
        port.interruptAddrWE = FALSE;
        @(posedge clk);
        #1;
        assert (port.rasPtr == RAS_IndexPath'(2)) else $fatal(1, "A cold redirect changed the RAS pointer");
        recovery.fetchRedirect.predCtx.rasPtr = RecoverRAS_Ptr(RAS_IndexPath'(2), BTB_RETURN_OFFSET, TRUE);
        recovery.fetchRedirect.restorePredCtx = TRUE;
        @(posedge clk);
        #1;
        assert (port.rasPtr == RAS_IndexPath'(1)) else $fatal(1, "An offset return must restore one pop");
        recovery.fetchRedirect.predCtx.rasPtr = '0;

        // One more call than slots overwrites the oldest target. Each call returns to a ret.
        firstCall = MakeResult((BTB_SET_NUM + 24) * FETCH_WIDTH + FETCH_WIDTH - 1);
        for (int i = 0; i <= RAS_ENTRY_NUM; i++) begin
            callOp.brAddr = firstCall.brAddr + i * CALL_STRIDE;
            retOp.brAddr = callOp.brAddr + INSN_BYTE_WIDTH;
            callOp.nextAddr = i == RAS_ENTRY_NUM ? retOp.brAddr : callOp.brAddr + CALL_STRIDE;
            callOp.brLookup.ctx = i == 0 ? firstCall.brLookup.ctx :
                MakeBranchHistoryContext(callOp.brAddr - CALL_STRIDE, '0, TRUE);
            // Returns are reached from the next deeper return, except at the innermost call.
            retOp.brLookup.ctx = MakeBranchHistoryContext(i == RAS_ENTRY_NUM ? callOp.brAddr : retOp.brAddr + CALL_STRIDE, '0, TRUE);
            WriteBTB(callOp, retOp);
        end
        // The deepest call returns to its own return instruction for the first pop.
        retOp.brLookup.ctx = MakeBranchHistoryContext(retOp.brAddr, '0, TRUE);
        WriteBTB(retOp);
        // When the RAS wraps, the oldest surviving return leads back to the innermost one.
        retOp.brLookup.ctx = MakeBranchHistoryContext(firstCall.brAddr + CALL_STRIDE + INSN_BYTE_WIDTH, '0, TRUE);
        WriteBTB(retOp);
        ReadGroup(firstCall.brAddr);
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.clear = FALSE;
        for (int i = 0; i <= RAS_ENTRY_NUM; i++) begin
            #1;
            assert (port.nextStage.valid[0] && port.nextStage.pc == firstCall.brAddr + i * CALL_STRIDE)
                else $fatal(1, "Unexpected call PC at nesting depth %0d", i + 1);
            @(posedge clk);
        end
        for (int i = 0; i < 2 * RAS_ENTRY_NUM; i++) begin
            #1;
            assert (port.nextStage.valid[0] && port.nextStage.brPred[0].usedRAS &&
                    fetch.fetchRequestPC == retOp.brAddr - (i % RAS_ENTRY_NUM) * CALL_STRIDE)
                else $fatal(1, "Unexpected circular RAS target on return %0d", i + 1);
            @(posedge clk);
        end
        #1;
        recovery.fetchRedirect.valid = TRUE;
        ctrl.ifStage.clear = TRUE;
    endtask

    task CheckBTBTraining;
        BranchResult hit, miss, notTaken;
        DrainBTB();
        hit = MakeResult(0, TRUE);
        miss = MakeResult(1);
        notTaken = miss;
        notTaken.execTaken = FALSE;
        hit.btbEntryCorrect = TRUE;
        hit.predTaken = TRUE;
        @(negedge clk);
        port.brResult[0] = hit;
        port.brResult[1] = notTaken;
        #1;
        assert (btb.btbEntryArray.we === '0 && !btb.updateValid[0] && !btb.updateValid[1])
            else $fatal(1, "Correct targets and untaken branches must leave the BTB unchanged");
        for (int i = 0; i < 2; i++) begin
            @(negedge clk);
            port.brResult[i] = hit;
            port.brResult[1-i] = miss;
            #1;
            assert (!btb.updateValid[i] && btb.updateValid[1-i] && btb.btbEntryArray.we == '0)
                else $fatal(1, "Only the miss should enqueue while the prediction port is busy");
        end
        @(negedge clk);
        ClearResults();
        DrainBTB();
        ReadGroup(miss.brAddr);
        CheckBTB(ToFetchGroupOffset(miss.brAddr), miss);
    endtask

    function automatic PHT_EntryPath NextCounter(PHT_EntryPath v, bit taken);
        if (taken && v != PHT_ENTRY_MAX) return v + 1'b1;
        if (!taken && v != 0) return v - 1'b1;
        return v;
    endfunction
    // The byte PC selects the counter in each adjacent pair of the predecessor's row.
    function automatic PHT_IndexPath CounterIndex(PHT_RowIndexPath row, MemoryMapTypes::PC_Path pc, int offset);
        return PHT_IndexPath'(row * FETCH_WIDTH + (offset ^ int'(FETCH_WIDTH > 1 && pc[11])));
    endfunction

    // A flat counter table and one FIFO per predictor model the two independent
    // instances. Only the oldest update can use the bank left free by fetch.
    for (genvar useGshare = 0; useGshare <= 1; useGshare++) begin : phtModel
        PHT_EntryPath counters[PHT_ENTRY_NUM];
        BranchResult pending[$];
        bit rowReady, acceptedWhileFull;
        PHT_EntryPath [FETCH_WIDTH-1:0] ramCounters, capturedCounters;
        PHT_RowIndexPath ramIndex, capturedIndex;
        bit ramValid, capturedValid;
        PHT_RowIndexPath bankAddr[2];
        logic bankWE[2];
        for (genvar b = 0; b < 2; b++) begin
            always_comb begin
                bankAddr[b] = useGshare ? gshare.bank[b].counterArray.rwa : bimodal.bank[b].counterArray.rwa;
                bankWE[b] = useGshare ? gshare.bank[b].counterArray.we : bimodal.bank[b].counterArray.we;
            end
        end
        always @(posedge clk) begin
            BranchResult samples[INT_ISSUE_WIDTH], oldest;
            PHT_RowIndexPath readRow;
            PHT_IndexPath index, headIndex;
            PHT_EntryPath expected;
            logic enqueue[INT_ISSUE_WIDTH];
            bit readTraining, writeEnable, headCanRun;
            int freeSlots, count;
            samples = port.brResult;
            readRow = port.phtReadRow;
            enqueue = useGshare ? gshare.trainingQueue.writeEnable : bimodal.trainingQueue.writeEnable;
            count = useGshare ? gshare.trainingQueue.count : bimodal.trainingQueue.count;
            readTraining = useGshare ? gshare.readTraining : bimodal.readTraining;
            writeEnable = useGshare ? gshare.writeEnable : bimodal.writeEnable;
            if (rst) begin
                pending.delete();
                acceptedWhileFull = FALSE;
                rowReady = FALSE;
                ramValid = FALSE;
                capturedValid = FALSE;
                if (rstStart)
                    foreach (counters[i]) counters[i] = PHT_ENTRY_MAX / 2 + 1;
            end
            else begin
                // Sample the physical bank request, but only the previous RAM output can enter the row FF.
                if (port.capturePredRows) begin
                    capturedIndex = ramIndex;
                    capturedValid = ramValid;
                    capturedCounters = ramCounters;
                end
                ramIndex = (bankAddr[readRow[0]] << 1) | PHT_RowIndexPath'(readRow[0]);
                ramValid = !bankWE[readRow[0]];
                assert (ramValid && ramIndex === readRow) else $fatal(1, "PHT %m read port lost row %h", readRow);
                for (int s = 0; s < FETCH_WIDTH; s++)
                    ramCounters[s] = counters[ramIndex * FETCH_WIDTH + s];
                #1;
                if (port.brLookupValid) begin
                    assert (capturedValid && capturedIndex === BranchContextPHT_Row(fetch.regBrLookup.ctx))
                        else $fatal(1, "PHT %m captured row %h but Fetch used row %h", capturedIndex, BranchContextPHT_Row(fetch.regBrLookup.ctx));
                    assert ((useGshare ? gshare.readRow : bimodal.readRow) === capturedCounters)
                        else $fatal(1, "PHT %m row %h returned raw counters %h, expected %h", capturedIndex,
                                    useGshare ? gshare.readRow : bimodal.readRow, capturedCounters);
                end
                headCanRun = FALSE;
                if (pending.size() != 0) begin
                    oldest = pending[0];
                    headIndex = CounterIndex(BranchContextPHT_Row(oldest.brLookup.ctx), oldest.brAddr, ToFetchGroupOffset(oldest.brAddr));
                    headCanRun = (headIndex / FETCH_WIDTH) % 2 != readRow[0];
                end
                assert (count == pending.size() && readTraining == (headCanRun && !rowReady) &&
                        writeEnable == (headCanRun && rowReady))
                    else $fatal(1, "PHT %m queue occupancy or head service mismatch");

                foreach (port.phtPrevValue[i]) begin
                    index = CounterIndex(capturedIndex, port.pcOut, i);
                    expected = port.brLookupValid ? capturedCounters[index % FETCH_WIDTH] : '0;
                    assert ((useGshare ? port.phtPrevValue[i] : bimodalPort.phtPrevValue[i]) === expected &&
                            (useGshare ? port.brPredTaken[i] : bimodalPort.brPredTaken[i]) ===
                                (expected > PHT_ENTRY_MAX / 2))
                        else $fatal(1, "PHT %m prediction mismatch at %0d", index);
                end
                freeSlots = PHT_QUEUE_SIZE - pending.size();
                if (writeEnable) begin
                    oldest = pending.pop_front();
                    counters[headIndex] = NextCounter(counters[headIndex], oldest.execTaken);
                    rowReady = FALSE;
                    freeSlots++;
                end
                if (readTraining) rowReady = TRUE;
                foreach (samples[i]) begin
                    bit accept;
                    accept = freeSlots > 0 && samples[i].valid && samples[i].brLookup.valid && samples[i].brType == BTB_COND &&
                        (samples[i].btbHit || samples[i].execTaken) &&
                        NextCounter(samples[i].phtPrevValue, samples[i].execTaken) != samples[i].phtPrevValue;
                    assert (enqueue[i] === accept) else $fatal(1, "PHT %m queue write mismatch on lane %0d", i);
                    if (accept) begin
                        if (count == PHT_QUEUE_SIZE) acceptedWhileFull = TRUE;
                        freeSlots--;
                        pending.push_back(samples[i]);
                    end
                end
            end
        end
    end

    // Isolate bank arbitration from the extra edge needed to present the BTB/PHT response.
    task ReadPHTGroup(input MemoryMapTypes::PC_Path pc);
        @(negedge clk);
        recovery.fetchRedirect.pc = pc;
        recovery.fetchRedirect.predCtx.ctx = MakeBranchHistoryContext(pc - FETCH_GROUP_BYTE_NUM, '0, FALSE);
        @(posedge clk);
        #1;
    endtask

    // Offer both banks enough idle cycles to read and write every queued update.
    task DrainPHT;
        repeat (PHT_QUEUE_SIZE) begin
            repeat (2) ReadPHTGroup(0);
            repeat (2) ReadPHTGroup(FETCH_WIDTH * INSN_BYTE_WIDTH);
        end
        assert (!bimodal.updatePending && !gshare.updatePending) else $fatal(1, "PHT queues did not drain");
    endtask

    task CheckPHTHeadConflict;
        BranchResult first, second;
        first = MakeResult(0, TRUE);
        second = MakeResult(FETCH_WIDTH, TRUE);
        first.execTaken = FALSE;
        second.execTaken = FALSE;
        first.phtPrevValue = PHT_ENTRY_MAX;
        second.phtPrevValue = PHT_ENTRY_MAX;
        // Distinguish the head row from other rows in its bank before forcing a stall.
        SendResults(first);
        DrainPHT();
        ReadPHTGroup(first.brAddr);
        SendResults(first, second);
        // A younger request to the free bank cannot pass the blocked head.
        repeat (3) ReadPHTGroup(first.brAddr);
        assert (bimodal.trainingQueue.count == 2 && gshare.trainingQueue.count == 2) else $fatal(1, "Blocked PHT head was bypassed");
        // Allow only the training read, then use its bank for several fetches.
        ReadPHTGroup(second.brAddr);
        repeat (3) ReadPHTGroup(first.brAddr + 2 * FETCH_WIDTH * INSN_BYTE_WIDTH);
        assert (bimodal.trainingQueue.count == 2 && gshare.trainingQueue.count == 2) else $fatal(1, "PHT wrote a busy bank");
        ReadPHTGroup(second.brAddr); // Write the saved row while a different row is still on its bank output.
        ReadPHTGroup(first.brAddr);
        DrainPHT();
        ReadPHTGroup(first.brAddr);
        ReadPHTGroup(second.brAddr);
    endtask

    task CheckPHTQueue;
        localparam int RESULTS = 2 * PHT_QUEUE_SIZE * INT_ISSUE_WIDTH;
        BranchResult result, other;
        // Use non-saturated counters to isolate BTB eligibility for both outcomes.
        for (int taken = 0; taken <= 1; taken++) begin
            result = MakeResult(RESULTS);
            result.execTaken = taken;
            result.phtPrevValue = PHT_ENTRY_MAX / 2 + 1;
            other = result;
            other.btbHit = TRUE;
            SendResults(result, other);
        end
        // A saturated snapshot skips the first lane while the opposite outcome
        // on the same snapshot can still use the first available queue slot.
        for (int taken = 0; taken <= 1; taken++) begin
            result = MakeResult(RESULTS, TRUE);
            result.phtPrevValue = taken ? PHT_ENTRY_MAX : '0;
            result.execTaken = taken;
            other = result;
            other.execTaken = !result.execTaken;
            SendResults(result, other);
        end
        // Alternate fetch banks during the burst to exercise simultaneous pushes and pops.
        // Distinct later addresses make dropped updates visible after the queue wraps.
        for (int i = 0; i < RESULTS; i += INT_ISSUE_WIDTH) begin
            @(negedge clk);
            recovery.fetchRedirect.pc = ((i / INT_ISSUE_WIDTH) % 2) * FETCH_WIDTH * INSN_BYTE_WIDTH;
            recovery.fetchRedirect.predCtx.ctx = MakeBranchHistoryContext(recovery.fetchRedirect.pc - FETCH_GROUP_BYTE_NUM, '0, FALSE);
            foreach (port.brResult[lane]) begin
                result = MakeResult(i + lane, TRUE);
                result.phtPrevValue = PHT_ENTRY_MAX / 2 + 1;
                result.execTaken = ((i + lane) % 2 == 1);
                port.brResult[lane] = result;
            end
        end
        @(negedge clk);
        ClearResults();
        DrainPHT();
        assert (phtModel[0].acceptedWhileFull && phtModel[1].acceptedWhileFull)
            else $fatal(1, "Both full PHT queues must accept a result while writing their head");
        // The high issue lane also trains when it is the only valid result.
        @(negedge clk);
        result = MakeResult(RESULTS, TRUE);
        result.phtPrevValue = '0;
        port.brResult[INT_ISSUE_WIDTH-1] = result;
        @(negedge clk);
        ClearResults();
        for (int i = 0; i <= RESULTS; i++) begin
            result = MakeResult(i, TRUE);
            ReadPHTGroup(result.brAddr);
        end
    endtask

    // Alternate rows and repeatedly update one row across both issue lanes.
    // Deliberately supply stale lookup counters for every training request.
    task CheckPackedCounterUpdates;
        BranchResult first, adjacent, otherRow;
        first = MakeResult(4 * FETCH_WIDTH, TRUE);
        adjacent = MakeResult(5 * FETCH_WIDTH - 1, TRUE);
        otherRow = MakeResult(6 * FETCH_WIDTH, TRUE);
        first.phtPrevValue = PHT_ENTRY_MAX;
        adjacent.phtPrevValue = PHT_ENTRY_MAX;
        first.execTaken = FALSE;
        adjacent.execTaken = FALSE;
        // Fetch the opposite bank so these repeated updates reach the counters.
        ReadPHTGroup(first.brAddr + FETCH_GROUP_BYTE_NUM);
        SendResults(first, adjacent);
        SendResults(first, first);
        SendResults(otherRow, adjacent);
        first.execTaken = TRUE;
        adjacent.execTaken = TRUE;
        first.phtPrevValue = '0;
        SendResults(first, first);
        SendResults(adjacent, adjacent);
        SendResults(first, first);
        DrainPHT();
        ReadPHTGroup(first.brAddr);
        ReadPHTGroup(otherRow.brAddr);
    endtask

    // Read every slot through the predictor ports; the flat reference tables check the values.
    task ReadAllPHTRows;
        for (int row = 0; row < PHT_ROWS; row++)
            ReadGroup(row * FETCH_GROUP_BYTE_NUM);
    endtask

    task CheckUpperPHTRows;
        BranchResult penultimate, last;
        penultimate = MakeResult(PHT_ENTRY_NUM - FETCH_WIDTH - 1, TRUE);
        last = MakeResult(PHT_ENTRY_NUM - 1, TRUE);
        // Distinguish the last word of each bank from its neighbors and from each other.
        penultimate.phtPrevValue = PHT_ENTRY_MAX;
        penultimate.execTaken = FALSE;
        last.phtPrevValue = '0;
        last.btbEntryCorrect = TRUE;
        DrainPHT();
        SendResults(penultimate, last);
        DrainPHT();
        ReadAllPHTRows();
    endtask

    function automatic BranchGlobalHistoryPath ExpectedTakenHistory(
        BranchGlobalHistoryPath history, MemoryMapTypes::PC_Path pc);
        if (!USE_GSHARE) return '0;
        return (history << 1) ^ BranchGlobalHistoryPath'((pc >> INSN_ADDR_BIT_WIDTH) & 31);
    endfunction

    task CheckPHTHistory;
        BranchResult result;
        BranchGlobalHistoryPath history;
        result = MakeResult(PHT_ENTRY_NUM - FETCH_WIDTH, TRUE);
        history = USE_GSHARE ? '1 : '0;
        result.phtPrevValue = PHT_ENTRY_MAX;
        result.execTaken = FALSE;
        result.brLookup.ctx = MakeBranchHistoryContext(result.brAddr - FETCH_GROUP_BYTE_NUM, history, FALSE);
        @(negedge clk);
        port.brResult[INT_ISSUE_WIDTH-1] = result;
        @(negedge clk);
        ClearResults();
        DrainPHT();
        ReadGroupFrom(result.brAddr, result.brAddr - FETCH_GROUP_BYTE_NUM, history);
        ReadGroup(result.brAddr);
        // Fetch receives the selected redirect together with its history policy.
        @(negedge clk);
        recovery.fetchRedirect.predCtx.ctx = MakeBranchHistoryContext(result.brAddr - FETCH_GROUP_BYTE_NUM, history, FALSE);
        @(posedge clk);
        #1;
        assert (BranchContextHistory(port.nextStage.brPred[0].brLookup.ctx) === history)
            else $fatal(1, "Fetch did not restore the selected branch history");
        @(negedge clk);
        recovery.fetchRedirect.pc = result.brAddr + FETCH_WIDTH * INSN_BYTE_WIDTH;
        recovery.fetchRedirect.restorePredCtx = FALSE;
        recovery.fetchRedirect.predCtx.ctx = MakeBranchHistoryContext(result.brAddr,
            USE_GSHARE ? BranchGlobalHistoryPath'(1) : '0, FALSE);
        @(posedge clk);
        #1;
        assert (port.nextStage.pc === recovery.fetchRedirect.pc && !port.nextStage.brPred[0].brLookup.valid &&
                BranchContextHistory(port.nextStage.brPred[0].brLookup.ctx) === history)
            else $fatal(1, "Fetch must redirect to the supplied PC while keeping its history");
        @(negedge clk);
        recovery.fetchRedirect.restorePredCtx = TRUE;
        CompleteWarmRedirect();
        assert (port.nextStage.pc === recovery.fetchRedirect.pc &&
                BranchContextHistory(port.nextStage.brPred[0].brLookup.ctx) === (USE_GSHARE ? BranchGlobalHistoryPath'(1) : '0) &&
                port.nextStage.brPred[0].brLookup.valid &&
                BranchContextBTB_Set(port.nextStage.brPred[0].brLookup.ctx) === ToBTB_Set(result.brAddr))
            else $fatal(1, "The redirected group must carry its restored history and predecessor set together");
        @(negedge clk);
        recovery.fetchRedirect.predCtx.ctx = '0;
    endtask

    // Track the physical RAM request through both edges, independently of Fetch's lookup metadata.
    struct packed { logic valid; BTB_SetIndexPath setIndex; } ramLookup, capturedLookup;
    always @(posedge clk) begin
        logic [$bits(btb.readRow)-1:0] expectedRow;
        if (rst) begin
            ramLookup = '0;
            capturedLookup = '0;
        end
        else begin
            if (port.capturePredRows) capturedLookup = ramLookup;
            ramLookup = '{valid: btb.btbEntryArray.we == '0, setIndex: btb.btbEntryArray.rwa};
            expectedRow = port.capturePredRows ? btb.readRow : btb.regReadRow;
            #1;
            assert (btb.regReadRow === expectedRow)
                else $fatal(1, "BTB raw row was not captured or held at the fetch edge");
            assert (!port.brLookupValid || (capturedLookup.valid && capturedLookup.setIndex === BranchContextBTB_Set(fetch.regBrLookup.ctx)))
                else $fatal(1, "BTB used set %h with a captured RAM request valid=%b set=%h",
                            BranchContextBTB_Set(fetch.regBrLookup.ctx), capturedLookup.valid, capturedLookup.setIndex);
        end
    end

    // Check the physical write, FIFO order and lane acceptance on every clock.
    BranchResult pending[$];
    bit previousStall;
    always @(posedge clk) begin
        BranchResult oldest;
        bit canWrite, accept;
        if (rst) begin
            pending.delete();
            previousStall = FALSE;
        end
        else begin
            canWrite = pending.size() != 0 && !recovery.fetchRedirect.valid &&
                       ((previousStall && ctrl.ifStage.stall) || ctrl.drainFetchForInterrupt);
            assert (btb.trainingQueue.count == pending.size() && (|btb.btbEntryArray.we) == canWrite)
                else $fatal(1, "BTB queue occupancy or table write enable mismatch");
            if (canWrite) begin
                BTB_Entry entry;
                oldest = pending.pop_front();
                entry = BTB_Entry'(btb.writeRow[btb.writeWay]);
                assert (btb.writeSet == BranchContextBTB_Set(oldest.brLookup.ctx) &&
                        entry.tag == ToBTB_Tag(oldest.brAddr) && entry.data == ToBTB_Addr(oldest.nextAddr) &&
                        entry.brType == oldest.brType && (!oldest.btbHit || btb.writeWay == oldest.btbHitWay))
                    else $fatal(1, "BTB table write did not match the oldest training request");
            end
            foreach (port.brResult[i]) begin
                accept = port.brResult[i].valid && port.brResult[i].brLookup.valid && port.brResult[i].execTaken &&
                         !port.brResult[i].btbEntryCorrect && pending.size() < BTB_QUEUE_SIZE;
                assert (btb.trainingQueue.writeEnable[i] === accept) else $fatal(1, "BTB queue write mismatch on lane %0d", i);
                if (accept) pending.push_back(port.brResult[i]);
            end
            previousStall = ctrl.ifStage.stall;
        end
    end

    task CheckFullBTBQueue;
        // Leave a single slot for a pair while ordinary fetches keep the RAM busy.
        for (int i = 0; i < BTB_QUEUE_SIZE-1; i++) begin
            @(negedge clk);
            port.brResult[0] = MakeResult(i);
        end
        @(negedge clk);
        port.brResult[0] = MakeResult(BTB_QUEUE_SIZE-1);
        port.brResult[1] = MakeResult(BTB_QUEUE_SIZE);
        #1;
        assert (btb.trainingQueue.writeEnable[0] && !btb.trainingQueue.writeEnable[1]) else $fatal(1, "The last slot belongs to lane 0");
        @(negedge clk);
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.stall = TRUE;
        #1;
        assert (btb.trainingQueue.count == BTB_QUEUE_SIZE && btb.trainingQueue.pushCount == 0 && !btb.writeEnable)
            else $fatal(1, "Entering a stall must preserve the prediction read");
        @(negedge clk);
        port.brResult[0] = '0;
        #1;
        assert (btb.writeEnable && btb.trainingQueue.pushCount == 1 && btb.trainingQueue.writeEnable[1])
            else $fatal(1, "Lane 1 can use the slot freed by a simultaneous write");
        @(negedge clk);
        ClearResults();
        recovery.fetchRedirect.valid = TRUE;
        #1;
        assert (!btb.writeEnable) else $fatal(1, "A redirect must preempt BTB training");
        @(negedge clk);
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.stall = FALSE;
        #1;
        assert (!btb.writeEnable) else $fatal(1, "Releasing a stall must restore the prediction read");
        @(negedge clk);
        // An interrupt drain can train the BTB even if the controller never stalls.
        // A simultaneous branch redirect still needs its target lookup.
        ctrl.drainFetchForInterrupt = TRUE;
        recovery.fetchRedirect.valid = TRUE;
        #1;
        assert (!btb.writeEnable && btb.trainingQueue.count == BTB_QUEUE_SIZE)
            else $fatal(1, "A redirect must retain the RAM port during interrupt drain");
        @(negedge clk);
        recovery.fetchRedirect.valid = FALSE;
        repeat (BTB_QUEUE_SIZE) @(negedge clk);
        assert (!btb.updatePending) else $fatal(1, "An interrupt drain must service pending updates");
        ctrl.drainFetchForInterrupt = FALSE;
        recovery.fetchRedirect.valid = TRUE;
    endtask

    task CheckRAS_Entries(input bit expectZero);
        // Restore each pointer with the fetch PC in region zero to observe the stored offset.
        recovery.fetchRedirect.pc = '0;
        recovery.fetchRedirect.valid = TRUE;
        recovery.fetchRedirect.restorePredCtx = TRUE;
        recovery.fetchRedirect.rasPush = FALSE;
        for (int i = RAS_ENTRY_NUM - 1; i >= 0; i--) begin
            @(negedge clk);
            recovery.fetchRedirect.predCtx.rasPtr = RAS_IndexPath'(i);
            @(posedge clk);
            #1;
            assert (port.rasPtr === RAS_IndexPath'(i) && ((port.rasTopPC == '0) == expectZero))
                else $fatal(1, "RAS entry %0d returned %h, expected zero = %b", i, port.rasTopPC, expectZero);
        end
    endtask

    task ResetTables;
        @(negedge clk);
        rst = TRUE;
        rstStart = TRUE;
        @(negedge clk);
        assert (port.rasPtr === '0) else $fatal(1, "Reset did not restore the initial RAS pointer");
        rstStart = FALSE;
        repeat (RESET_CYCLES) @(negedge clk);
        rst = FALSE;
    endtask

    task CheckBTBWays;
        localparam int ALIAS_STRIDE = FETCH_WIDTH * BTB_SET_NUM;
        localparam int FIRST = ALIAS_STRIDE; // Keep the replacement checks clear of the reset tag.
        BranchResult first, last, neighbor, aliasBranch, updated, cold;
        BranchGlobalHistoryPath beforeBranch, afterBranch;
        first = MakeResult(FIRST);
        last = MakeResult(FIRST + FETCH_WIDTH - 1);
        neighbor = MakeResult(FIRST + FETCH_WIDTH);
        aliasBranch = MakeResult(FIRST + ALIAS_STRIDE);
        first.phtPrevValue = PHT_ENTRY_MAX;
        last.phtPrevValue = PHT_ENTRY_MAX;
        last.brType = BTB_JUMP;

        // Both reset entries match this PC's zero block tag and offset.
        cold = MakeResult(0);
        cold.nextAddr = ToRawAddrFromBTB_Addr('0, cold.brAddr);
        cold.brType = BTB_JUMP;
        ReadGroup(cold.brAddr);
        CheckBTB(0, cold);
        assert (port.btbHitWay[0] === BTB_WayIndexPath'(BTB_WAY_NUM-1))
            else $fatal(1, "Expected the highest way on a duplicate reset tag");
        CheckBTB(FETCH_WIDTH-1, '0);
        ReadGroup(first.brAddr);
        CheckBTB(0, '0);
        assert (!port.nextStage.brPred[0].predTaken) else $fatal(1, "A BTB miss predicted taken");
        // Leave a strongly not-taken counter at the address of the upcoming jump.
        updated = last;
        updated.btbHit = TRUE;
        updated.brType = BTB_COND;
        updated.execTaken = FALSE;
        updated.phtPrevValue = PHT_ENTRY_MAX;
        WriteBTB(updated, updated);
        WriteBTB(first, last);
        if (BTB_SET_NUM > 1) WriteBTB(neighbor);
        DrainPHT();
        ReadGroup(first.brAddr);
        CheckBTB(0, first);
        CheckBTB(FETCH_WIDTH-1, last);
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.clear = FALSE;
        #1;
        assert (port.nextStage.brPred[0].predTaken && port.nextStage.brPred[0].takenAddr == first.nextAddr &&
                fetch.fetchRequestPC == first.nextAddr &&
                fetch.fetchRequestHistory == ExpectedTakenHistory(BranchContextHistory(port.nextStage.brPred[0].brLookup.ctx), first.brAddr))
            else $fatal(1, "Fetch did not select the first taken conditional branch");
        recovery.fetchRedirect.valid = TRUE;
        ctrl.ifStage.clear = TRUE;
        first.btbHit = port.btbHit[0];
        first.btbHitWay = port.btbHitWay[0];
        last.btbHit = port.btbHit[FETCH_WIDTH-1];
        last.btbHitWay = port.btbHitWay[FETCH_WIDTH-1];
        assert (first.btbHitWay != last.btbHitWay) else $fatal(1, "Expected hits in distinct ways");
        if (BTB_SET_NUM > 1) begin
            ReadGroup(neighbor.brAddr);
            CheckBTB(0, neighbor);
        end
        ReadGroup(last.brAddr);
        // Both predictions keep their group offsets when fetch lane zero starts at the last instruction.
        CheckBTB(0, first);
        CheckBTB(FETCH_WIDTH-1, last);
        // The skipped conditional branch predicts taken but must not shift history.
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.clear = FALSE;
        #1;
        assert (port.nextStage.valid[0] && port.nextStage.brPred[0].predTaken &&
                port.nextStage.brPred[0].takenAddr == last.nextAddr &&
                port.phtPrevValue[FETCH_WIDTH-1] == 0 && bimodalPort.phtPrevValue[FETCH_WIDTH-1] == 0 &&
                fetch.fetchRequestPC == last.nextAddr &&
                fetch.fetchRequestHistory == ExpectedTakenHistory(BranchContextHistory(port.nextStage.brPred[0].brLookup.ctx), last.brAddr))
            else $fatal(1, "Fetch must skip the earlier branch and take the jump independently of its counter");
        recovery.fetchRedirect.valid = TRUE;
        ctrl.ifStage.clear = TRUE;

        // Active fetches keep seeing the old target until a stall permits the update.
        // Updating the first branch makes its way the newest.
        updated = first;
        updated.nextAddr += INSN_BYTE_WIDTH;
        updated.brType = BTB_JUMP;
        SendResults(updated);
        ReadGroup(first.brAddr);
        CheckBTB(0, first);
        DrainBTB();
        ReadGroup(first.brAddr);
        CheckBTB(0, updated);
        CheckBTB(FETCH_WIDTH-1, last);
        // Repeated training of the same key must stay in that way.
        updated.nextAddr += INSN_BYTE_WIDTH;
        WriteBTB(updated);
        ReadGroup(first.brAddr);
        CheckBTB(0, updated);
        CheckBTB(FETCH_WIDTH-1, last);
        // A different block in the same set replaces the older branch.
        WriteBTB(aliasBranch);
        ReadGroup(aliasBranch.brAddr);
        CheckBTB(0, aliasBranch);
        CheckBTB(FETCH_WIDTH-1, '0);
        ReadGroup(first.brAddr);
        CheckBTB(0, updated);
        CheckBTB(FETCH_WIDTH-1, '0);

        // The delayed hit for last still uses its Fetch way, now occupied by aliasBranch.
        // The earlier queued write uses that way first, leaving the other way as the miss victim.
        ReadGroup(aliasBranch.brAddr);
        aliasBranch.btbHit = port.btbHit[0];
        aliasBranch.btbHitWay = port.btbHitWay[0];
        assert (aliasBranch.btbHit && aliasBranch.btbHitWay == last.btbHitWay)
            else $fatal(1, "Alias did not evict the saved hit");
        aliasBranch.nextAddr += INSN_BYTE_WIDTH;
        last.nextAddr += 2 * INSN_BYTE_WIDTH;
        WriteBTB(aliasBranch, last);
        ReadGroup(first.brAddr);
        CheckBTB(0, updated);
        CheckBTB(FETCH_WIDTH-1, last);
        ReadGroup(aliasBranch.brAddr);
        CheckBTB(0, '0);

        // A weakly not-taken first branch lets the later unconditional jump win.
        WriteBTB(first);
        updated = first;
        updated.execTaken = FALSE;
        WriteBTB(updated, updated);
        DrainPHT();
        ReadGroup(first.brAddr);
        assert (!port.nextStage.brPred[0].predTaken && port.nextStage.brPred[FETCH_WIDTH-1].predTaken &&
                port.nextStage.brPred[FETCH_WIDTH-1].takenAddr == last.nextAddr)
            else $fatal(1, "Fetch did not skip the not-taken conditional branch");

        // The taken jump discards the conditional hit after it, including its history update.
        first.brType = BTB_JUMP;
        last.brType = BTB_COND;
        WriteBTB(first, last);
        ReadGroup(first.brAddr);
        CheckBTB(0, first);
        CheckBTB(FETCH_WIDTH-1, last);
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.clear = FALSE;
        #1;
        assert (port.nextStage.brPred[0].predTaken && port.nextStage.brPred[0].takenAddr == first.nextAddr &&
                fetch.fetchRequestPC == first.nextAddr &&
                fetch.fetchRequestHistory == ExpectedTakenHistory(BranchContextHistory(port.nextStage.brPred[0].brLookup.ctx), first.brAddr))
            else $fatal(1, "A conditional hit after a taken jump updated the history");
        recovery.fetchRedirect.valid = TRUE;
        ctrl.ifStage.clear = TRUE;

        // On a cache miss the predictor can reach the target while I-cache repeats the source.
        last.brType = BTB_JUMP;
        WriteBTB(last);
        // Capture a known target on stall entry, then train the very same entry
        // while the single port is free. The held prediction still uses the old row.
        neighbor = MakeResult(0);
        neighbor.brAddr = last.nextAddr;
        neighbor.brLookup.ctx = MakeBranchHistoryContext(last.brAddr, '0, TRUE);
        neighbor.nextAddr = last.nextAddr + FETCH_GROUP_BYTE_NUM;
        neighbor.brType = BTB_JUMP;
        WriteBTB(neighbor);
        ReadGroupFrom(neighbor.brAddr, last.brAddr);
        CheckBTB(ToFetchGroupOffset(neighbor.brAddr), neighbor);
        updated = neighbor;
        updated.btbHit = TRUE;
        updated.btbHitWay = port.btbHitWay[ToFetchGroupOffset(neighbor.brAddr)];
        updated.nextAddr += FETCH_GROUP_BYTE_NUM;
        SendResults(updated);
        ReadGroup(last.brAddr);
        beforeBranch = BranchContextHistory(port.nextStage.brPred[0].brLookup.ctx);
        afterBranch = ExpectedTakenHistory(beforeBranch, last.brAddr);
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.clear = FALSE;
        ctrl.ifStage.stall = TRUE;
        port.icReadHit = FALSE;
        repeat (3) begin
            #1;
            assert (fetch.fetchRequestPC == last.nextAddr && fetch.fetchRequestHistory == afterBranch &&
                    port.icNextReadAddrIn == MemoryMapTypes::ToAddrFromPC(last.brAddr) && port.nextStage.valid == '0)
                else $fatal(1, "Fetch lost the target PC/history or advanced the missed I-cache lookup");
            @(posedge clk);
        end
        @(negedge clk);
        ctrl.ifStage.stall = FALSE;
        port.icReadHit = TRUE;
        #1;
        assert (fetch.fetchRequestPC == last.nextAddr && fetch.fetchRequestHistory == afterBranch &&
                port.nextStage.valid[0] && port.nextStage.pc == last.brAddr &&
                BranchContextHistory(port.nextStage.brPred[0].brLookup.ctx) == beforeBranch)
            else $fatal(1, "Fetch lost the held source group checkpoint on stall release");
        @(posedge clk);
        #1;
        assert (port.nextStage.valid[0] && port.nextStage.pc == neighbor.brAddr &&
                port.nextStage.brPred[0].predTaken && fetch.fetchRequestPC == neighbor.nextAddr)
            else $fatal(1, "Fetch did not preserve the successor's captured target through the stall");
        recovery.fetchRedirect.valid = TRUE;
        ctrl.ifStage.clear = TRUE;
        ReadGroupFrom(neighbor.brAddr, last.brAddr);
        CheckBTB(ToFetchGroupOffset(neighbor.brAddr), updated);

        ResetTables();
        ReadGroup(cold.brAddr);
        CheckBTB(0, cold);
        ReadGroup(first.brAddr);
        CheckBTB(0, '0);
        ReadGroup(aliasBranch.brAddr);
        CheckBTB(0, '0);
    endtask

    task CheckAheadPHT;
        localparam MemoryMapTypes::PC_Path SOURCE = 32'h80000000 + 3 * FETCH_GROUP_BYTE_NUM;
        localparam MemoryMapTypes::PC_Path SUCCESSOR = SOURCE + FETCH_GROUP_BYTE_NUM;
        BranchGlobalHistoryPath history;
        BranchResult result;
        PHT_IndexPath sourceIndex;
        PHT_RowIndexPath sourceRow;
        history = USE_GSHARE ? BranchGlobalHistoryPath'(5) : '0;
        sourceIndex = PHT_IndexPath'(SOURCE >> INSN_ADDR_BIT_WIDTH) ^
                      (PHT_IndexPath'(history) << (PHT_ENTRY_NUM_BIT_WIDTH - BRANCH_GLOBAL_HISTORY_BIT_WIDTH));
        sourceRow = PHT_RowIndexPath'(sourceIndex / FETCH_WIDTH);

        // Let Fetch issue A's lookup. B must carry a row formed with A's PC and pre-branch history.
        ReadGroupFrom(SOURCE, SOURCE - FETCH_GROUP_BYTE_NUM, history);
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.clear = FALSE;
        @(posedge clk);
        #1;
        assert (port.nextStage.pc == SUCCESSOR && port.nextStage.brPred[0].brLookup.valid &&
                BranchContextPHT_Row(port.nextStage.brPred[0].brLookup.ctx) == sourceRow)
            else $fatal(1, "Expected successor %h row %h, got PC %h valid %b row %h",
                        SUCCESSOR, sourceRow, port.nextStage.pc, port.nextStage.brPred[0].brLookup.valid,
                        BranchContextPHT_Row(port.nextStage.brPred[0].brLookup.ctx));
        result = MakeResult(0, TRUE);
        result.brAddr = SUCCESSOR;
        result.brLookup = port.nextStage.brPred[0].brLookup;
        result.phtPrevValue = port.nextStage.brPred[0].phtPrevValue;
        result.execTaken = FALSE;
        // Train while Fetch reads a different row and history. The same B under another A stays cold.
        recovery.fetchRedirect.valid = TRUE;
        ctrl.ifStage.clear = TRUE;
        ReadGroupFrom(SUCCESSOR, SOURCE + FETCH_GROUP_BYTE_NUM, history);
        SendResults(result);
        DrainPHT();
        ReadGroupFrom(SUCCESSOR, SOURCE + FETCH_GROUP_BYTE_NUM, history);
        assert (port.phtPrevValue[0] == 2 && bimodalPort.phtPrevValue[0] == 2)
            else $fatal(1, "The update followed the live predecessor instead of the saved PHT row");
        ReadGroupFrom(SUCCESSOR, SOURCE, history, TRUE);
        assert (port.phtPrevValue[0] == 1 && bimodalPort.phtPrevValue[0] == 1 &&
                fetch.regFetchRequestHistory == ExpectedTakenHistory(history, SOURCE))
            else $fatal(1, "The taken predecessor must supply its trained row and advance the successor's history");

        // Keep A fixed and flip B.pc[11]. The trained counter moves to its adjacent group offset.
        ReadGroupFrom(SUCCESSOR ^ 32'h800, SOURCE, history);
        for (int offset = 0; offset < FETCH_WIDTH; offset++) begin
            PHT_EntryPath expected;
            expected = offset == (FETCH_WIDTH > 1 ? 1 : 0) ? 1 : 2;
            assert (port.phtPrevValue[offset] == expected && bimodalPort.phtPrevValue[offset] == expected)
                else $fatal(1, "B.pc[11] selected the wrong PHT counter at offset %0d", offset);
        end

        // A redirect without a predecessor must suppress both the prediction and its later update.
        @(negedge clk);
        recovery.fetchRedirect.restorePredCtx = FALSE;
        @(posedge clk);
        #1;
        assert (!port.nextStage.brPred[0].brLookup.valid && port.phtPrevValue[0] == 0 &&
                bimodalPort.phtPrevValue[0] == 0) else $fatal(1, "A cold redirect used a PHT prediction");
        result.brLookup = port.nextStage.brPred[0].brLookup;
        SendResults(result);
        DrainPHT();
        ReadGroupFrom(SUCCESSOR, SOURCE, history);
        assert (port.phtPrevValue[0] == 1 && bimodalPort.phtPrevValue[0] == 1)
            else $fatal(1, "A cold redirect trained a stale PHT row");
    endtask

    // While B is held, train a counter in the row already captured for C.
    task CheckStalledPHT;
        localparam MemoryMapTypes::PC_Path B = 32'h80000000 + 6 * FETCH_GROUP_BYTE_NUM;
        localparam MemoryMapTypes::PC_Path C = B + FETCH_GROUP_BYTE_NUM;
        BranchResult result;
        ReadGroup(B);
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.clear = FALSE;
        ctrl.ifStage.stall = TRUE;
        port.icReadHit = FALSE;
        @(posedge clk);
        #1;
        assert (port.pcOut == C && port.brLookupValid && port.phtPrevValue[0] != 0 &&
                bimodalPort.phtPrevValue[0] == port.phtPrevValue[0])
            else $fatal(1, "Stall entry did not capture B's counters for C");
        result = MakeResult(0, TRUE);
        result.brAddr = C;
        result.brLookup.ctx = MakeBranchHistoryContext(B, '0, FALSE);
        result.execTaken = FALSE;
        result.phtPrevValue = port.phtPrevValue[0];
        SendResults(result);
        repeat (3) @(negedge clk);
        assert (!gshare.updatePending && !bimodal.updatePending) else $fatal(1, "Stalled PHT training did not finish");
        ctrl.ifStage.stall = FALSE;
        port.icReadHit = TRUE;
        @(posedge clk);
        #1;
        assert (port.nextStage.valid[0] && port.nextStage.pc == C &&
                port.phtPrevValue[0] == result.phtPrevValue && bimodalPort.phtPrevValue[0] == result.phtPrevValue)
            else $fatal(1, "C did not see its original counter after the stall");
        ctrl.ifStage.clear = TRUE;
        ReadGroupFrom(C, B);
        assert (port.phtPrevValue[0] == NextCounter(result.phtPrevValue, FALSE) &&
                bimodalPort.phtPrevValue[0] == port.phtPrevValue[0])
            else $fatal(1, "The next read did not see the counter trained during the stall");
    endtask

    task CheckAheadRows;
        BranchResult first, second;
        MemoryMapTypes::PC_Path predecessor1, predecessor2;
        first = MakeResult((BTB_SET_NUM + 20) * FETCH_WIDTH);
        second = first;
        second.nextAddr += FETCH_GROUP_BYTE_NUM;
        predecessor1 = first.brAddr - 3 * FETCH_GROUP_BYTE_NUM;
        predecessor2 = first.brAddr + 5 * FETCH_GROUP_BYTE_NUM;
        first.brLookup.ctx = MakeBranchHistoryContext(predecessor1, '0, FALSE);
        second.brLookup.ctx = MakeBranchHistoryContext(predecessor2, '0, FALSE);
        WriteBTB(first, second);
        ReadGroupFrom(first.brAddr, predecessor1);
        CheckBTB(0, first);
        assert (port.nextStage.brPred[0].brLookup == first.brLookup)
            else $fatal(1, "First predecessor context did not reach the predicted branch");
        ReadGroupFrom(second.brAddr, predecessor2);
        CheckBTB(0, second);
        assert (port.nextStage.brPred[0].brLookup == second.brLookup)
            else $fatal(1, "Second predecessor context did not reach the predicted branch");

        // A second redirect can arrive before the first raw row reaches its FF.
        // Both edges name the same B, but only the later predecessor's target is valid.
        @(negedge clk);
        recovery.fetchRedirect.predCtx.ctx = MakeBranchHistoryContext(predecessor1, '0, FALSE);
        @(posedge clk);
        #1;
        assert (!fetch.pipeReg.valid) else $fatal(1, "An unfinished warm redirect delivered a group");
        @(negedge clk);
        recovery.fetchRedirect.predCtx.ctx = MakeBranchHistoryContext(predecessor2, '0, FALSE);
        CompleteWarmRedirect();
        CheckBTB(0, second);

        // Reuse the same PC and stale set on a redirect without a predecessor.
        @(negedge clk);
        recovery.fetchRedirect.restorePredCtx = FALSE;
        @(posedge clk);
        #1;
        CheckBTB(0, '0);
        assert (!port.nextStage.brPred[0].brLookup.valid) else $fatal(1, "A cold redirect reused a predecessor");
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.clear = FALSE;
        @(posedge clk);
        #1;
        assert (port.nextStage.valid[0] && port.nextStage.pc == first.brAddr + FETCH_GROUP_BYTE_NUM &&
                port.nextStage.brPred[0].brLookup.valid &&
                BranchContextBTB_Set(port.nextStage.brPred[0].brLookup.ctx) == ToBTB_Set(first.brAddr))
            else $fatal(1, "The first sequential successor must have a known predecessor");
        recovery.fetchRedirect.valid = TRUE;
        ctrl.ifStage.clear = TRUE;
        first.brLookup.valid = FALSE;
        SendResults(first);
        assert (!btb.updatePending) else $fatal(1, "A cold lookup must not train an unrelated BTB set");
        ReadGroupFrom(second.brAddr, predecessor2);
        CheckBTB(0, second);

        // These successors use the same row and differ only in the top bit of the low tag field.
        second.brAddr = first.brAddr ^ MemoryMapTypes::PC_Path'(FETCH_GROUP_BYTE_NUM << (BTB_TAG_LOW_WIDTH - 1));
        second.brLookup.ctx = first.brLookup.ctx;
        WriteBTB(second);
        ReadGroupFrom(first.brAddr, predecessor1);
        CheckBTB(0, first);
        ReadGroupFrom(second.brAddr, predecessor1);
        CheckBTB(0, second);
    endtask

    task CheckAheadSequence;
        BranchResult jumps[4];
        BranchGlobalHistoryPath entryHistory[4];
        entryHistory[0] = '0;
        for (int i = 0; i < 4; i++) begin
            jumps[i] = MakeResult((BTB_SET_NUM + 6 + i*3) * FETCH_WIDTH);
            jumps[i].brType = BTB_JUMP;
            if (i != 0) begin
                jumps[i-1].nextAddr = jumps[i].brAddr;
                jumps[i].brLookup.ctx = MakeBranchHistoryContext(jumps[i-1].brAddr, entryHistory[i-1], TRUE);
                entryHistory[i] = ExpectedTakenHistory(entryHistory[i-1], jumps[i-1].brAddr);
            end
        end
        WriteBTB(jumps[0], jumps[1]);
        WriteBTB(jumps[2], jumps[3]);
        ReadGroup(jumps[0].brAddr);
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.clear = FALSE;
        // While A predicts B using the captured predecessor row, the RAM samples B's
        // set. At that edge B must select from A's row, even though B's row is now read.
        for (int i = 0; i < 3; i++) begin
            #1;
            CheckBTB(0, jumps[i]);
            assert (port.nextStage.valid[0] && port.pcOut == jumps[i].brAddr &&
                    port.nextStage.brPred[0].brLookup.valid &&
                    port.nextStage.brPred[0].brLookup.ctx == jumps[i].brLookup.ctx &&
                    fetch.fetchRequestHistory == entryHistory[i+1] &&
                    port.phtReadRow == ToPHT_Row(jumps[i+1].brAddr, entryHistory[i+1]) &&
                    fetch.fetchRequestPC == jumps[i+1].brAddr &&
                    btb.btbEntryArray.rwa == ToBTB_Set(jumps[i+1].brAddr))
                else $fatal(1, "BTB lookahead at PC %h: predicted %h, RAM set %h, expected next PC %h set %h",
                            port.pcOut, fetch.fetchRequestPC, btb.btbEntryArray.rwa,
                            jumps[i+1].brAddr, ToBTB_Set(jumps[i+1].brAddr));
            @(posedge clk);
        end
        #1;
        CheckBTB(0, jumps[3]);
        recovery.fetchRedirect.valid = TRUE;
        ctrl.ifStage.clear = TRUE;
    endtask

    // Two instances fetched before either was trained can both report a miss.
    task CheckOverlappingMisses;
        BranchResult first, second;
        first = MakeResult(0);
        second = first;
        second.nextAddr += INSN_BYTE_WIDTH;
        WriteBTB(first, second); // The two requests allocate ways 0 then 1 after reset.
        ReadGroup(first.brAddr);
        CheckBTB(0, second);
        second.btbHit = port.btbHit[0];
        second.btbHitWay = port.btbHitWay[0];
        assert (second.btbHitWay) else $fatal(1, "Duplicate tag must report the way that supplied the target");
        second.nextAddr += INSN_BYTE_WIDTH;
        WriteBTB(second);
        ReadGroup(first.brAddr);
        CheckBTB(0, second);
    endtask

    initial begin
        #((3 * RESET_CYCLES + 4 * PHT_ROWS + 1000) * 10);
        $fatal(1, "Branch predictor queue test timed out");
    end

    initial begin
        ClearResults();
        // Redirect each lookup to the test address and suppress speculative history
        // updates until the directed fetch check releases clear.
        recovery.fetchRedirect = '{valid: TRUE, restorePredCtx: TRUE, default: '0};
        port.icReadHit = TRUE;
        port.interruptAddrWE = FALSE;
        ctrl.ifStage = '0;
        ctrl.ifStage.clear = TRUE;
        ctrl.drainFetchForInterrupt = FALSE;
        ResetTables();
        if (FETCH_WIDTH >= 2) CheckBTBWays();
        CheckFetchRAS();

        recovery.fetchRedirect.pc = '0;
        CheckPHTHeadConflict();
        CheckPackedCounterUpdates();
        CheckPHTQueue();
        CheckPHTHistory();
        CheckBTBTraining();
        CheckUpperPHTRows();
        CheckRAS_Entries(FALSE);
        @(negedge clk);
        port.brResult[0] = MakeResult(4);
        port.brResult[1] = MakeResult(5);
        ResetTables();
        ClearResults();
        assert (!btb.updatePending) else $fatal(1, "Reset must discard pending training requests");
        CheckRAS_Entries(TRUE);
        ReadAllPHTRows(); // A warm reset must restore both banks, including the trained high addresses.
        CheckAheadPHT();
        CheckStalledPHT();
        CheckRecoveryRows();
        CheckAheadRows();
        CheckAheadSequence();
        CheckOverlappingMisses();
        CheckFullBTBQueue();
        $display("========== Test Passed ==========");
        $finish;
    end
endmodule
