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
    Gshare gshare(.port(port), .ctrl(ctrl));
    Bimodal bimodal(.port(bimodalPort));

    // Exercise both predictors with the same fetch addresses and training results.
    always_comb begin
        bimodalPort.fetchRequestPC = port.fetchRequestPC;
        bimodalPort.fetchRequestHistory = port.fetchRequestHistory;
        bimodalPort.brResult = port.brResult;
    end

    function automatic BranchResult MakeResult(input int index);
        BranchResult result;
        result = '0;
        result.valid = TRUE;
        result.execTaken = TRUE;
        result.isCondBr = TRUE;
        result.brAddr = 32'h80000000 + index * INSN_BYTE_WIDTH;
        result.nextAddr = result.brAddr + 128;
        result.phtPrevValue = PHT_EntryPath'(index % PHT_ENTRY_MAX);
        return result;
    endfunction

    task ClearResults;
        foreach (port.brResult[i]) port.brResult[i] = '0;
    endtask

    task ReadGroup(input MemoryMapTypes::PC_Path pc);
        @(negedge clk);
        recovery.recoveredPC_FromRename = pc;
        @(posedge clk);
        #1;
    endtask

    task WriteBTB(input BranchResult first, input BranchResult second = '0);
        @(negedge clk);
        port.brResult[0] = first;
        port.brResult[1] = second;
        @(negedge clk);
        ClearResults();
        // Let each queued request reach the table before checking READ_FIRST.
        @(negedge clk);
        if (second.valid) @(negedge clk);
    endtask

    task CheckBTB(input int groupOffset, input BranchResult expected);
        assert (port.btbHit[groupOffset] === expected.valid &&
                (!expected.valid || (port.btbOut[groupOffset] === expected.nextAddr &&
                                     port.readIsCondBr[groupOffset] === expected.isCondBr)))
            else $fatal(1, "BTB PC %h group offset %0d expected hit %b target %h conditional %b",
                        port.fetchRequestPC, groupOffset, expected.valid, expected.nextAddr, expected.isCondBr);
    endtask

    task CheckBTBTraining;
        BranchResult hit, miss, notTaken;
        hit = MakeResult(0);
        miss = MakeResult(1);
        notTaken = miss;
        notTaken.execTaken = FALSE;
        hit.btbTargetCorrect = TRUE;
        hit.predTaken = TRUE;
        @(negedge clk);
        port.brResult[0] = hit;
        port.brResult[1] = notTaken;
        #1;
        assert (btb.btbEntryArray.we === '0 && btb.pushCount == 0)
            else $fatal(1, "Correct targets and untaken branches must only train the PHT");
        for (int i = 0; i < 2; i++) begin
            @(negedge clk);
            port.brResult[i] = hit;
            port.brResult[1-i] = miss;
            #1;
            assert (btb.pushCount == 1 && btb.queueWE[1-i] && (|btb.btbEntryArray.we) == (i != 0))
                else $fatal(1, "Only the miss should enqueue; only a previous request may write");
        end
        @(negedge clk);
        ClearResults();
        ReadGroup(miss.brAddr);
        CheckBTB(ToFetchGroupOffset(miss.brAddr), miss);
    endtask

    function automatic PHT_EntryPath NextCounter(PHT_EntryPath v, bit taken);
        if (taken && v != PHT_ENTRY_MAX) return v + 1'b1;
        if (!taken && v != 0) return v - 1'b1;
        return v;
    endfunction
    function automatic PHT_IndexPath HashedIndex(input PHT_IndexPath index, input BranchGlobalHistoryPath history);
        return index ^ (PHT_IndexPath'(history) << (PHT_ENTRY_NUM_BIT_WIDTH - BRANCH_GLOBAL_HISTORY_BIT_WIDTH));
    endfunction

    // A flat counter table and one FIFO per predictor model the two independent
    // instances. Only the oldest update can use the bank left free by fetch.
    for (genvar useGshare = 0; useGshare <= 1; useGshare++) begin : phtModel
        PHT_EntryPath counters[PHT_ENTRY_NUM];
        BranchResult pending[$];
        bit rowReady;
        always @(posedge clk) begin
            BranchResult samples[INT_ISSUE_WIDTH], oldest;
            PHT_IndexPath base, index, headIndex;
            logic enqueue[INT_ISSUE_WIDTH];
            bit readTraining, writeEnable, headCanRun;
            int freeSlots, count;
            samples = port.brResult;
            base = PHT_IndexPath'((port.fetchRequestPC >> INSN_ADDR_BIT_WIDTH) & ~(FETCH_WIDTH - 1));
            if (useGshare) base = HashedIndex(base, port.fetchRequestHistory);
            enqueue = useGshare ? gshare.queueWE : bimodal.queueWE;
            count = useGshare ? gshare.count : bimodal.count;
            readTraining = useGshare ? gshare.readTraining : bimodal.readTraining;
            writeEnable = useGshare ? gshare.writeEnable : bimodal.writeEnable;
            if (rst) begin
                pending.delete();
                rowReady = FALSE;
                if (rstStart)
                    foreach (counters[i]) counters[i] = PHT_ENTRY_MAX / 2 + 1;
            end
            else begin
                // RAM outputs correspond to the PC and history sampled at the clock edge.
                #1;
                headCanRun = FALSE;
                if (pending.size() != 0) begin
                    oldest = pending[0];
                    headIndex = PHT_IndexPath'(oldest.brAddr >> INSN_ADDR_BIT_WIDTH);
                    if (useGshare) headIndex = HashedIndex(headIndex, oldest.globalHistory);
                    headCanRun = (headIndex / FETCH_WIDTH) % 2 != (base / FETCH_WIDTH) % 2;
                end
                assert (count == pending.size() && readTraining == (headCanRun && !rowReady) &&
                        writeEnable == (headCanRun && rowReady))
                    else $fatal(1, "PHT %m queue occupancy or head service mismatch");

                foreach (port.phtPrevValue[i]) begin
                    index = base ^ PHT_IndexPath'(i);
                    assert ((useGshare ? port.phtPrevValue[i] : bimodalPort.phtPrevValue[i]) === counters[index] &&
                            (useGshare ? port.brPredTaken[i] : bimodalPort.brPredTaken[i]) ===
                                (counters[index] > PHT_ENTRY_MAX / 2))
                        else $fatal(1, "PHT %m prediction mismatch at %0d", index);
                end
                freeSlots = PHT_QUEUE_SIZE - pending.size();
                if (writeEnable) begin
                    oldest = pending.pop_front();
                    counters[headIndex] = NextCounter(counters[headIndex], oldest.execTaken);
                    rowReady = FALSE;
                    if (freeSlots != 0) freeSlots++;
                end
                if (readTraining) rowReady = TRUE;
                foreach (samples[i]) begin
                    bit accept;
                    accept = freeSlots > 0 && samples[i].valid && samples[i].isCondBr &&
                        NextCounter(samples[i].phtPrevValue, samples[i].execTaken) != samples[i].phtPrevValue;
                    assert (enqueue[i] === accept) else $fatal(1, "PHT %m queue write mismatch on lane %0d", i);
                    if (accept) begin
                        freeSlots--;
                        pending.push_back(samples[i]);
                    end
                end
            end
        end
    end

    // Offer both banks enough idle cycles to read and write every queued update.
    task DrainPHT;
        repeat (PHT_QUEUE_SIZE) begin
            repeat (2) ReadGroup(0);
            repeat (2) ReadGroup(FETCH_WIDTH * INSN_BYTE_WIDTH);
        end
        assert (bimodal.count == 0 && gshare.count == 0) else $fatal(1, "PHT queues did not drain");
    endtask

    task CheckPHTHeadConflict;
        BranchResult first, second;
        first = MakeResult(0);
        second = MakeResult(FETCH_WIDTH);
        first.execTaken = FALSE;
        second.execTaken = FALSE;
        first.phtPrevValue = PHT_ENTRY_MAX;
        second.phtPrevValue = PHT_ENTRY_MAX;
        // Distinguish the head row from other rows in its bank before forcing a stall.
        WriteBTB(first);
        DrainPHT();
        ReadGroup(first.brAddr);
        WriteBTB(first, second);
        // A younger request to the free bank cannot pass the blocked head.
        repeat (3) ReadGroup(first.brAddr);
        assert (bimodal.count == 2 && gshare.count == 2) else $fatal(1, "Blocked PHT head was bypassed");
        // Allow only the training read, then use its bank for several fetches.
        ReadGroup(second.brAddr);
        repeat (3) ReadGroup(first.brAddr + 2 * FETCH_WIDTH * INSN_BYTE_WIDTH);
        assert (bimodal.count == 2 && gshare.count == 2) else $fatal(1, "PHT wrote a busy bank");
        ReadGroup(second.brAddr); // Write the saved row while a different row is still on its bank output.
        ReadGroup(first.brAddr);
        DrainPHT();
        ReadGroup(first.brAddr);
        ReadGroup(second.brAddr);
    endtask

    task CheckPHTQueue;
        localparam int RESULTS = 2 * PHT_QUEUE_SIZE * INT_ISSUE_WIDTH;
        BranchResult result, other;
        // A saturated snapshot skips the first lane while the opposite outcome
        // on the same snapshot can still use the first available queue slot.
        for (int taken = 0; taken <= 1; taken++) begin
            result = MakeResult(RESULTS);
            result.phtPrevValue = taken ? PHT_ENTRY_MAX : '0;
            result.execTaken = taken;
            other = result;
            other.execTaken = !result.execTaken;
            WriteBTB(result, other);
        end
        // Alternate fetch banks during the burst to exercise simultaneous pushes and pops.
        // Distinct later addresses make dropped updates visible after the queue wraps.
        for (int i = 0; i < RESULTS; i += INT_ISSUE_WIDTH) begin
            @(negedge clk);
            recovery.recoveredPC_FromRename = ((i / INT_ISSUE_WIDTH) % 2) * FETCH_WIDTH * INSN_BYTE_WIDTH;
            foreach (port.brResult[lane]) begin
                result = MakeResult(i + lane);
                result.phtPrevValue = PHT_ENTRY_MAX / 2 + 1;
                result.execTaken = ((i + lane) % 2 == 1);
                port.brResult[lane] = result;
            end
        end
        @(negedge clk);
        ClearResults();
        DrainPHT();
        // The high issue lane also trains when it is the only valid result.
        @(negedge clk);
        result = MakeResult(RESULTS);
        result.phtPrevValue = '0;
        port.brResult[INT_ISSUE_WIDTH-1] = result;
        @(negedge clk);
        ClearResults();
        for (int i = 0; i <= RESULTS; i++) begin
            result = MakeResult(i);
            ReadGroup(result.brAddr);
        end
    endtask

    // Alternate rows and repeatedly update one row across both issue lanes.
    // Deliberately supply stale lookup counters for every training request.
    task CheckPackedCounterUpdates;
        BranchResult first, adjacent, otherRow;
        first = MakeResult(4 * FETCH_WIDTH);
        adjacent = MakeResult(5 * FETCH_WIDTH - 1);
        otherRow = MakeResult(6 * FETCH_WIDTH);
        first.phtPrevValue = PHT_ENTRY_MAX;
        adjacent.phtPrevValue = PHT_ENTRY_MAX;
        first.execTaken = FALSE;
        adjacent.execTaken = FALSE;
        // Fetch the opposite bank so these repeated updates reach the counters.
        recovery.recoveredPC_FromRename = first.brAddr + FETCH_WIDTH * INSN_BYTE_WIDTH;
        WriteBTB(first, adjacent);
        WriteBTB(first, first);
        WriteBTB(otherRow, adjacent);
        first.execTaken = TRUE;
        adjacent.execTaken = TRUE;
        first.phtPrevValue = '0;
        WriteBTB(first, first);
        WriteBTB(adjacent, adjacent);
        WriteBTB(first, first);
        DrainPHT();
        ReadGroup(first.brAddr);
        ReadGroup(otherRow.brAddr);
    endtask

    // Read every slot through the predictor ports; the flat reference tables check the values.
    task ReadAllPHTRows;
        for (int row = 0; row < PHT_ROWS; row++)
            ReadGroup(row * FETCH_GROUP_BYTE_NUM);
    endtask

    task CheckUpperPHTRows;
        BranchResult penultimate, last;
        penultimate = MakeResult(PHT_ENTRY_NUM - FETCH_WIDTH - 1);
        last = MakeResult(PHT_ENTRY_NUM - 1);
        // Distinguish the last word of each bank from its neighbors and from each other.
        penultimate.phtPrevValue = PHT_ENTRY_MAX;
        penultimate.execTaken = FALSE;
        last.phtPrevValue = '0;
        last.btbTargetCorrect = TRUE;
        DrainPHT();
        WriteBTB(penultimate, last);
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
        PHT_IndexPath index;
        result = MakeResult(PHT_ENTRY_NUM - FETCH_WIDTH);
        result.globalHistory = '1;
        result.phtPrevValue = PHT_ENTRY_MAX;
        result.execTaken = FALSE;
        // Train under a saved nonzero history while the live history is zero.
        @(negedge clk);
        port.brResult[INT_ISSUE_WIDTH-1] = result;
        @(negedge clk);
        ClearResults();
        DrainPHT();
        index = HashedIndex(PHT_IndexPath'(result.brAddr >> INSN_ADDR_BIT_WIDTH), result.globalHistory);
        ReadGroup(index * INSN_BYTE_WIDTH);
        ReadGroup(result.brAddr);
        // Exercise the selected backend redirect while a younger Rename redirect is pending.
        @(negedge clk);
        recovery.toRecoveryPhase = TRUE;
        recovery.recoveredPC_FromRwCommit = result.brAddr;
        recovery.recoverBrHistory_FromRwCommit = TRUE;
        recovery.recoveredBrHistory_FromRwCommit = result.globalHistory;
        @(posedge clk);
        #1;
        assert (port.nextStage.brPred[0].globalHistory === (USE_GSHARE ? result.globalHistory : '0))
            else $fatal(1, "Fetch did not restore the selected branch history");
        @(negedge clk);
        recovery.recoverBrHistory_FromRwCommit = FALSE;
        recovery.recoveredBrHistory_FromRwCommit = '0;
        recovery.recoveredBrHistory_FromRename = BranchGlobalHistoryPath'(1);
        @(posedge clk);
        #1;
        assert (port.nextStage.brPred[0].globalHistory === (USE_GSHARE ? result.globalHistory : '0))
            else $fatal(1, "A nonbranch redirect changed history or accepted a younger correction");
        @(negedge clk);
        recovery.toRecoveryPhase = FALSE;
        @(posedge clk);
        #1;
        assert (port.nextStage.brPred[0].globalHistory === (USE_GSHARE ? BranchGlobalHistoryPath'(1) : '0))
            else $fatal(1, "Decode redirect did not restore its checkpoint");
        @(negedge clk);
        recovery.recoveredBrHistory_FromRename = '0;
    endtask

    // Compare the physical table write to the oldest request on every clock,
    // including pointer wrap and dropped requests when full at the start of a cycle.
    BranchResult pending[$];
    always @(posedge clk) begin
        BranchResult oldest;
        bit wasFull;
        if (rst) begin
            pending.delete();
        end
        else begin
            wasFull = pending.size() == BTB_QUEUE_SIZE;
            assert (btb.count == pending.size() && (|btb.writeMask) == (pending.size() != 0))
                else $fatal(1, "BTB queue occupancy or table write enable mismatch");
            if (pending.size() != 0) begin
                BTB_Entry entry;
                oldest = pending.pop_front();
                entry = BTB_Entry'(btb.writeRow[btb.writeWay]);
                assert (btb.writeSet == ToBTB_Set(oldest.brAddr) &&
                        entry.tag == ToBTB_Tag(oldest.brAddr) && entry.data == ToBTB_Addr(oldest.nextAddr) &&
                        entry.isCondBr == oldest.isCondBr && (!oldest.btbHit || btb.writeWay == oldest.btbHitWay))
                    else $fatal(1, "BTB table write did not match the oldest training request");
            end
            foreach (port.brResult[i])
                if (port.brResult[i].valid && port.brResult[i].execTaken &&
                    !port.brResult[i].btbTargetCorrect && !wasFull)
                    pending.push_back(port.brResult[i]);
        end
    end

    task CheckFullBTBQueue;
        // Starting empty, the BTB accepts two entries on the first cycle before it can pop.
        // Further pairs fill the queue while one entry drains per cycle.
        for (int i = 0; i < BTB_QUEUE_SIZE; i++) begin
            @(negedge clk);
            port.brResult[0] = MakeResult(2*i);
            port.brResult[1] = MakeResult(2*i+1);
        end
        #1;
        assert (btb.count == BTB_QUEUE_SIZE && !btb.queueWE[0] && !btb.queueWE[1])
            else $fatal(1, "A full BTB queue must drop both training requests");
        @(negedge clk);
        port.brResult[0] = '0;
        port.brResult[1] = MakeResult(2*BTB_QUEUE_SIZE);
        #1;
        assert (btb.pushCount == 1 && btb.queueWE[1])
            else $fatal(1, "Lane 1 can use the freed slot when lane 0 has no request");
        @(negedge clk);
        ClearResults();
        repeat (BTB_QUEUE_SIZE) @(negedge clk);
        assert (btb.count == 0) else $fatal(1, "BTB queue did not drain");
    endtask

    task ResetTables;
        @(negedge clk);
        rst = TRUE;
        rstStart = TRUE;
        @(negedge clk);
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
        last.isCondBr = FALSE;

        // Both reset entries match this PC's zero block tag and offset.
        cold = MakeResult(0);
        cold.nextAddr = ToRawAddrFromBTB_Addr('0, cold.brAddr);
        cold.isCondBr = FALSE;
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
        updated.isCondBr = TRUE;
        updated.execTaken = FALSE;
        updated.phtPrevValue = PHT_ENTRY_MAX;
        WriteBTB(updated, updated);
        WriteBTB(first, last);
        if (BTB_SET_NUM > 1) WriteBTB(neighbor);
        DrainPHT();
        ReadGroup(first.brAddr);
        CheckBTB(0, first);
        CheckBTB(FETCH_WIDTH-1, last);
        recovery.recoverFromRename = FALSE;
        ctrl.ifStage.clear = FALSE;
        #1;
        assert (port.nextStage.brPred[0].predTaken && port.nextStage.brPred[0].takenAddr == first.nextAddr &&
                port.fetchRequestPC == first.nextAddr &&
                port.fetchRequestHistory == ExpectedTakenHistory(port.nextStage.brPred[0].globalHistory, first.brAddr))
            else $fatal(1, "Fetch did not select the first taken conditional branch");
        recovery.recoverFromRename = TRUE;
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
        recovery.recoverFromRename = FALSE;
        ctrl.ifStage.clear = FALSE;
        #1;
        assert (port.nextStage.valid[0] && port.nextStage.brPred[0].predTaken &&
                port.nextStage.brPred[0].takenAddr == last.nextAddr &&
                port.phtPrevValue[FETCH_WIDTH-1] == 0 && bimodalPort.phtPrevValue[FETCH_WIDTH-1] == 0 &&
                port.fetchRequestPC == last.nextAddr &&
                port.fetchRequestHistory == ExpectedTakenHistory(port.nextStage.brPred[0].globalHistory, last.brAddr))
            else $fatal(1, "Fetch must skip the earlier branch and take the jump independently of its counter");
        recovery.recoverFromRename = TRUE;
        ctrl.ifStage.clear = TRUE;

        // On a same-row read/write the old target and branch kind are visible
        // for one cycle. Updating the first branch makes its way the newest.
        updated = first;
        updated.nextAddr += INSN_BYTE_WIDTH;
        updated.isCondBr = FALSE;
        ReadGroup(first.brAddr);
        WriteBTB(updated);
        CheckBTB(0, first);
        @(posedge clk);
        #1;
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
        first.isCondBr = FALSE;
        last.isCondBr = TRUE;
        WriteBTB(first, last);
        ReadGroup(first.brAddr);
        CheckBTB(0, first);
        CheckBTB(FETCH_WIDTH-1, last);
        recovery.recoverFromRename = FALSE;
        ctrl.ifStage.clear = FALSE;
        #1;
        assert (port.nextStage.brPred[0].predTaken && port.nextStage.brPred[0].takenAddr == first.nextAddr &&
                port.fetchRequestPC == first.nextAddr &&
                port.fetchRequestHistory == ExpectedTakenHistory(port.nextStage.brPred[0].globalHistory, first.brAddr))
            else $fatal(1, "A conditional hit after a taken jump updated the history");
        recovery.recoverFromRename = TRUE;
        ctrl.ifStage.clear = TRUE;

        // On a cache miss the predictor can reach the target while I-cache repeats the source.
        last.isCondBr = FALSE;
        WriteBTB(last);
        ReadGroup(last.brAddr);
        beforeBranch = port.nextStage.brPred[0].globalHistory;
        afterBranch = ExpectedTakenHistory(beforeBranch, last.brAddr);
        recovery.recoverFromRename = FALSE;
        ctrl.ifStage.clear = FALSE;
        ctrl.ifStage.stall = TRUE;
        port.icReadHit = FALSE;
        repeat (3) begin
            #1;
            assert (port.fetchRequestPC == last.nextAddr && port.fetchRequestHistory == afterBranch &&
                    port.icNextReadAddrIn == MemoryMapTypes::ToAddrFromPC(last.brAddr) && port.nextStage.valid == '0)
                else $fatal(1, "Fetch lost the target PC/history or advanced the missed I-cache lookup");
            @(posedge clk);
        end
        @(negedge clk);
        ctrl.ifStage.stall = FALSE;
        port.icReadHit = TRUE;
        #1;
        assert (port.fetchRequestPC == last.nextAddr && port.fetchRequestHistory == afterBranch &&
                port.nextStage.valid[0] && port.nextStage.pc == last.brAddr &&
                port.nextStage.brPred[0].globalHistory == beforeBranch)
            else $fatal(1, "Fetch lost the held source group checkpoint on stall release");
        recovery.recoverFromRename = TRUE;
        ctrl.ifStage.clear = TRUE;

        ResetTables();
        ReadGroup(cold.brAddr);
        CheckBTB(0, cold);
        ReadGroup(first.brAddr);
        CheckBTB(0, '0);
        ReadGroup(aliasBranch.brAddr);
        CheckBTB(0, '0);
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
        #((3 * RESET_CYCLES + 2 * PHT_ROWS + 1000) * 10);
        $fatal(1, "Branch predictor queue test timed out");
    end

    initial begin
        ClearResults();
        // Redirect each lookup to the test address and suppress speculative history
        // updates until the directed fetch check releases clear.
        recovery.toRecoveryPhase = FALSE;
        recovery.recoverFromRename = TRUE;
        recovery.recoveredPC_FromRename = '0;
        recovery.recoveredBrHistory_FromRename = '0;
        recovery.recoverBrHistory_FromRwCommit = FALSE;
        port.icReadHit = TRUE;
        port.interruptAddrWE = FALSE;
        ctrl.ifStage = '0;
        ctrl.ifStage.clear = TRUE;
        ctrl.drainFetchForInterrupt = FALSE;
        ResetTables();
        if (FETCH_WIDTH >= 2) CheckBTBWays();

        recovery.recoveredPC_FromRename = '0;
        CheckPHTHeadConflict();
        CheckPackedCounterUpdates();
        CheckPHTQueue();
        CheckPHTHistory();
        CheckBTBTraining();
        CheckUpperPHTRows();
        @(negedge clk);
        port.brResult[0] = MakeResult(4);
        port.brResult[1] = MakeResult(5);
        ResetTables();
        ClearResults();
        assert (btb.count == 0) else $fatal(1, "Reset must discard pending training requests");
        ReadAllPHTRows(); // A warm reset must restore both banks, including the trained high addresses.
        CheckOverlappingMisses();
        CheckFullBTBQueue();
        $display("========== Test Passed ==========");
        $finish;
    end
endmodule
