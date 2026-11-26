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
        result.brType = BTB_COND;
        result.brAddr = 32'h80000000 + index * INSN_BYTE_WIDTH;
        // Use a sequential predecessor by default. Non-sequential edges specify theirs below.
        result.btbLookup = '{valid: TRUE, setIndex: ToBTB_Set(result.brAddr - FETCH_GROUP_BYTE_NUM)};
        result.nextAddr = result.brAddr + 128;
        result.phtPrevValue = PHT_EntryPath'(index % PHT_ENTRY_MAX);
        return result;
    endfunction

    task ClearResults;
        foreach (port.brResult[i]) port.brResult[i] = '0;
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

    task ReadGroupFrom(input MemoryMapTypes::PC_Path pc, input MemoryMapTypes::PC_Path predecessor);
        @(negedge clk);
        recovery.fetchRedirect.pc = pc;
        recovery.fetchRedirect.restorePredCtx = TRUE;
        recovery.fetchRedirect.valid = TRUE;
        recovery.fetchRedirect.predCtx.btbSet = ToBTB_Set(predecessor);
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
        assert (btb.count == 0) else $fatal(1, "BTB queue did not drain during a sustained stall");
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
                        port.fetchRequestPC, groupOffset, expected.valid, expected.nextAddr, expected.brType);
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
        retOp.btbLookup.setIndex = ToBTB_Set(callOp.brAddr);
        WriteBTB(callOp, retOp);

        ReadGroupFrom(retOp.brAddr, callOp.brAddr);
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.clear = FALSE;
        #1;
        assert (!port.nextStage.brPred[0].usedRAS && port.fetchRequestPC == retOp.nextAddr)
            else $fatal(1, "An empty Fetch RAS must use the BTB fallback");

        recovery.fetchRedirect.valid = TRUE;
        ReadGroup(callOp.brAddr);
        recovery.fetchRedirect.valid = FALSE;
        #1;
        assert (port.nextStage.valid[0] && port.fetchRequestPC == retOp.brAddr)
            else $fatal(1, "The call must fetch its target");
        @(posedge clk);
        #1;
        assert (port.nextStage.valid[0] && port.nextStage.brPred[0].usedRAS &&
                port.fetchRequestPC == callOp.brAddr + INSN_BYTE_WIDTH)
            else $fatal(1, "Back-to-back call and return must use the new stack top without a bubble");
        recovery.fetchRedirect.valid = TRUE;
        ctrl.ifStage.clear = TRUE;

        // One more call than slots overwrites the oldest target. Each call returns to a ret.
        firstCall = MakeResult((BTB_SET_NUM + 24) * FETCH_WIDTH + FETCH_WIDTH - 1);
        for (int i = 0; i <= fetch.RAS_ENTRY_NUM; i++) begin
            callOp.brAddr = firstCall.brAddr + i * CALL_STRIDE;
            retOp.brAddr = callOp.brAddr + INSN_BYTE_WIDTH;
            callOp.nextAddr = i == fetch.RAS_ENTRY_NUM ? retOp.brAddr : callOp.brAddr + CALL_STRIDE;
            callOp.btbLookup.setIndex = i == 0 ? firstCall.btbLookup.setIndex : ToBTB_Set(callOp.brAddr - CALL_STRIDE);
            // Returns are reached from the next deeper return, except at the innermost call.
            retOp.btbLookup.setIndex = ToBTB_Set(i == fetch.RAS_ENTRY_NUM ? callOp.brAddr : retOp.brAddr + CALL_STRIDE);
            WriteBTB(callOp, retOp);
        end
        // The deepest call returns to its own return instruction for the first pop.
        retOp.btbLookup.setIndex = ToBTB_Set(retOp.brAddr);
        WriteBTB(retOp);
        // When the RAS wraps, the oldest surviving return leads back to the innermost one.
        retOp.btbLookup.setIndex = ToBTB_Set(firstCall.brAddr + CALL_STRIDE + INSN_BYTE_WIDTH);
        WriteBTB(retOp);
        ReadGroup(firstCall.brAddr);
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.clear = FALSE;
        for (int i = 0; i <= fetch.RAS_ENTRY_NUM; i++) begin
            #1;
            assert (port.nextStage.valid[0] && port.nextStage.pc == firstCall.brAddr + i * CALL_STRIDE)
                else $fatal(1, "Unexpected call PC at nesting depth %0d", i + 1);
            @(posedge clk);
        end
        for (int i = 0; i < 2 * fetch.RAS_ENTRY_NUM; i++) begin
            #1;
            assert (port.nextStage.valid[0] && port.nextStage.brPred[0].usedRAS &&
                    port.fetchRequestPC == retOp.brAddr - (i % fetch.RAS_ENTRY_NUM) * CALL_STRIDE)
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
        hit = MakeResult(0);
        miss = MakeResult(1);
        notTaken = miss;
        notTaken.execTaken = FALSE;
        hit.btbEntryCorrect = TRUE;
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
            assert (btb.pushCount == 1 && btb.queueWE[1-i] && btb.btbEntryArray.we == '0)
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
                    accept = freeSlots > 0 && samples[i].valid && samples[i].brType == BTB_COND &&
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
    // PHT bank arbitration still takes one fetch request per edge.
    task ReadPHTGroup(input MemoryMapTypes::PC_Path pc);
        @(negedge clk);
        recovery.fetchRedirect.pc = pc;
        @(posedge clk);
        #1;
    endtask

    task DrainPHT;
        repeat (PHT_QUEUE_SIZE) begin
            repeat (2) ReadPHTGroup(0);
            repeat (2) ReadPHTGroup(FETCH_WIDTH * INSN_BYTE_WIDTH);
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
        SendResults(first);
        DrainPHT();
        ReadPHTGroup(first.brAddr);
        SendResults(first, second);
        // A younger request to the free bank cannot pass the blocked head.
        repeat (3) ReadPHTGroup(first.brAddr);
        assert (bimodal.count == 2 && gshare.count == 2) else $fatal(1, "Blocked PHT head was bypassed");
        // Allow only the training read, then use its bank for several fetches.
        ReadPHTGroup(second.brAddr);
        repeat (3) ReadPHTGroup(first.brAddr + 2 * FETCH_WIDTH * INSN_BYTE_WIDTH);
        assert (bimodal.count == 2 && gshare.count == 2) else $fatal(1, "PHT wrote a busy bank");
        ReadPHTGroup(second.brAddr); // Write the saved row while a different row is still on its bank output.
        ReadPHTGroup(first.brAddr);
        DrainPHT();
        ReadPHTGroup(first.brAddr);
        ReadPHTGroup(second.brAddr);
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
            SendResults(result, other);
        end
        // Alternate fetch banks during the burst to exercise simultaneous pushes and pops.
        // Distinct later addresses make dropped updates visible after the queue wraps.
        for (int i = 0; i < RESULTS; i += INT_ISSUE_WIDTH) begin
            @(negedge clk);
            recovery.fetchRedirect.pc = ((i / INT_ISSUE_WIDTH) % 2) * FETCH_WIDTH * INSN_BYTE_WIDTH;
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
            ReadPHTGroup(result.brAddr);
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
        recovery.fetchRedirect.pc = first.brAddr + FETCH_WIDTH * INSN_BYTE_WIDTH;
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
            ReadPHTGroup(row * FETCH_GROUP_BYTE_NUM);
    endtask

    task CheckUpperPHTRows;
        BranchResult penultimate, last;
        penultimate = MakeResult(PHT_ENTRY_NUM - FETCH_WIDTH - 1);
        last = MakeResult(PHT_ENTRY_NUM - 1);
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
        ReadPHTGroup(index * INSN_BYTE_WIDTH);
        ReadPHTGroup(result.brAddr);
        // Fetch receives the selected redirect together with its history policy.
        @(negedge clk);
        recovery.fetchRedirect.predCtx.history = result.globalHistory;
        @(posedge clk);
        #1;
        assert (port.nextStage.brPred[0].globalHistory === (USE_GSHARE ? result.globalHistory : '0))
            else $fatal(1, "Fetch did not restore the selected branch history");
        @(negedge clk);
        recovery.fetchRedirect.pc = result.brAddr + FETCH_WIDTH * INSN_BYTE_WIDTH;
        recovery.fetchRedirect.restorePredCtx = FALSE;
        recovery.fetchRedirect.predCtx.history = BranchGlobalHistoryPath'(1);
        @(posedge clk);
        #1;
        assert (port.nextStage.pc === recovery.fetchRedirect.pc &&
                port.nextStage.brPred[0].globalHistory === (USE_GSHARE ? result.globalHistory : '0))
            else $fatal(1, "Fetch must redirect to the supplied PC while keeping its history");
        @(negedge clk);
        recovery.fetchRedirect.restorePredCtx = TRUE;
        recovery.fetchRedirect.predCtx.btbSet = ToBTB_Set(result.brAddr);
        CompleteWarmRedirect();
        assert (port.nextStage.pc === recovery.fetchRedirect.pc &&
                port.nextStage.brPred[0].globalHistory === (USE_GSHARE ? BranchGlobalHistoryPath'(1) : '0) &&
                port.nextStage.brPred[0].btbLookup.valid &&
                port.nextStage.brPred[0].btbLookup.setIndex === ToBTB_Set(result.brAddr))
            else $fatal(1, "The redirected group must carry its restored history and predecessor set together");
        @(negedge clk);
        recovery.fetchRedirect.predCtx.history = '0;
    endtask

    // Track the physical RAM request through both edges, independently of Fetch's lookup metadata.
    BTB_LookupPath ramLookup, capturedLookup;
    always @(posedge clk) begin
        logic [$bits(btb.readRow)-1:0] expectedRow;
        if (rst) begin
            ramLookup = '0;
            capturedLookup = '0;
        end
        else begin
            if (port.btbCaptureRow) capturedLookup = ramLookup;
            ramLookup = '{valid: btb.btbEntryArray.we == '0, setIndex: btb.btbEntryArray.rwa};
            expectedRow = port.btbCaptureRow ? btb.readRow : btb.regReadRow;
            #1;
            assert (btb.regReadRow === expectedRow)
                else $fatal(1, "BTB raw row was not captured or held at the fetch edge");
            assert (!port.btbLookupValid || (capturedLookup.valid && capturedLookup.setIndex === fetch.regBTB_Lookup.setIndex))
                else $fatal(1, "BTB used set %h with a captured RAM request valid=%b set=%h",
                            fetch.regBTB_Lookup.setIndex, capturedLookup.valid, capturedLookup.setIndex);
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
            assert (btb.count == pending.size() && (|btb.btbEntryArray.we) == canWrite)
                else $fatal(1, "BTB queue occupancy or table write enable mismatch");
            if (canWrite) begin
                BTB_Entry entry;
                oldest = pending.pop_front();
                entry = BTB_Entry'(btb.writeRow[btb.writeWay]);
                assert (btb.writeSet == oldest.btbLookup.setIndex &&
                        entry.tag == ToBTB_Tag(oldest.brAddr) && entry.data == ToBTB_Addr(oldest.nextAddr) &&
                        entry.brType == oldest.brType && (!oldest.btbHit || btb.writeWay == oldest.btbHitWay))
                    else $fatal(1, "BTB table write did not match the oldest training request");
            end
            foreach (port.brResult[i]) begin
                accept = port.brResult[i].valid && port.brResult[i].btbLookup.valid && port.brResult[i].execTaken &&
                         !port.brResult[i].btbEntryCorrect && pending.size() < BTB_QUEUE_SIZE;
                assert (btb.queueWE[i] === accept) else $fatal(1, "BTB queue write mismatch on lane %0d", i);
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
        assert (btb.queueWE[0] && !btb.queueWE[1]) else $fatal(1, "The last slot belongs to lane 0");
        @(negedge clk);
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.stall = TRUE;
        #1;
        assert (btb.count == BTB_QUEUE_SIZE && btb.pushCount == 0 && !btb.writeEnable)
            else $fatal(1, "Entering a stall must preserve the prediction read");
        @(negedge clk);
        port.brResult[0] = '0;
        #1;
        assert (btb.writeEnable && btb.pushCount == 1 && btb.queueWE[1])
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
        assert (!btb.writeEnable && btb.count == BTB_QUEUE_SIZE)
            else $fatal(1, "A redirect must retain the RAM port during interrupt drain");
        @(negedge clk);
        recovery.fetchRedirect.valid = FALSE;
        repeat (BTB_QUEUE_SIZE) @(negedge clk);
        assert (btb.count == 0) else $fatal(1, "An interrupt drain must service pending updates");
        ctrl.drainFetchForInterrupt = FALSE;
        recovery.fetchRedirect.valid = TRUE;
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
                port.fetchRequestPC == first.nextAddr &&
                port.fetchRequestHistory == ExpectedTakenHistory(port.nextStage.brPred[0].globalHistory, first.brAddr))
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
                port.fetchRequestPC == last.nextAddr &&
                port.fetchRequestHistory == ExpectedTakenHistory(port.nextStage.brPred[0].globalHistory, last.brAddr))
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
                port.fetchRequestPC == first.nextAddr &&
                port.fetchRequestHistory == ExpectedTakenHistory(port.nextStage.brPred[0].globalHistory, first.brAddr))
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
        neighbor.btbLookup.setIndex = ToBTB_Set(last.brAddr);
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
        beforeBranch = port.nextStage.brPred[0].globalHistory;
        afterBranch = ExpectedTakenHistory(beforeBranch, last.brAddr);
        recovery.fetchRedirect.valid = FALSE;
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
        @(posedge clk);
        #1;
        assert (port.nextStage.valid[0] && port.nextStage.pc == neighbor.brAddr &&
                port.nextStage.brPred[0].predTaken && port.fetchRequestPC == neighbor.nextAddr)
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

    task CheckAheadRows;
        BranchResult first, second;
        MemoryMapTypes::PC_Path predecessor1, predecessor2;
        first = MakeResult((BTB_SET_NUM + 20) * FETCH_WIDTH);
        second = first;
        second.nextAddr += FETCH_GROUP_BYTE_NUM;
        predecessor1 = first.brAddr - 3 * FETCH_GROUP_BYTE_NUM;
        predecessor2 = first.brAddr + 5 * FETCH_GROUP_BYTE_NUM;
        first.btbLookup.setIndex = ToBTB_Set(predecessor1);
        second.btbLookup.setIndex = ToBTB_Set(predecessor2);
        WriteBTB(first, second);
        ReadGroupFrom(first.brAddr, predecessor1);
        CheckBTB(0, first);
        assert (port.nextStage.brPred[0].btbLookup == first.btbLookup)
            else $fatal(1, "First predecessor context did not reach the predicted branch");
        ReadGroupFrom(second.brAddr, predecessor2);
        CheckBTB(0, second);
        assert (port.nextStage.brPred[0].btbLookup == second.btbLookup)
            else $fatal(1, "Second predecessor context did not reach the predicted branch");

        // A second redirect can arrive before the first raw row reaches its FF.
        // Both edges name the same B, but only the later predecessor's target is valid.
        @(negedge clk);
        recovery.fetchRedirect.predCtx.btbSet = ToBTB_Set(predecessor1);
        @(posedge clk);
        #1;
        assert (!fetch.pipeReg.valid) else $fatal(1, "An unfinished warm redirect delivered a group");
        @(negedge clk);
        recovery.fetchRedirect.predCtx.btbSet = ToBTB_Set(predecessor2);
        CompleteWarmRedirect();
        CheckBTB(0, second);

        // Reuse the same PC and stale set on a redirect without a predecessor.
        @(negedge clk);
        recovery.fetchRedirect.restorePredCtx = FALSE;
        @(posedge clk);
        #1;
        CheckBTB(0, '0);
        assert (!port.nextStage.brPred[0].btbLookup.valid) else $fatal(1, "A cold redirect reused a predecessor");
        recovery.fetchRedirect.valid = FALSE;
        ctrl.ifStage.clear = FALSE;
        @(posedge clk);
        #1;
        assert (port.nextStage.valid[0] && port.nextStage.pc == first.brAddr + FETCH_GROUP_BYTE_NUM &&
                port.nextStage.brPred[0].btbLookup.valid &&
                port.nextStage.brPred[0].btbLookup.setIndex == ToBTB_Set(first.brAddr))
            else $fatal(1, "The first sequential successor must have a known predecessor");
        recovery.fetchRedirect.valid = TRUE;
        ctrl.ifStage.clear = TRUE;
        first.btbLookup.valid = FALSE;
        SendResults(first);
        assert (btb.count == 0) else $fatal(1, "A cold lookup must not train an unrelated BTB set");
        ReadGroupFrom(second.brAddr, predecessor2);
        CheckBTB(0, second);

        // These successors use the same row and differ only in the top bit of the low tag field.
        second.brAddr = first.brAddr ^ MemoryMapTypes::PC_Path'(FETCH_GROUP_BYTE_NUM << (BTB_TAG_LOW_WIDTH - 1));
        second.btbLookup.setIndex = first.btbLookup.setIndex;
        WriteBTB(second);
        ReadGroupFrom(first.brAddr, predecessor1);
        CheckBTB(0, first);
        ReadGroupFrom(second.brAddr, predecessor1);
        CheckBTB(0, second);
    endtask

    task CheckAheadSequence;
        BranchResult jumps[4];
        for (int i = 0; i < 4; i++) begin
            jumps[i] = MakeResult((BTB_SET_NUM + 6 + i*3) * FETCH_WIDTH);
            jumps[i].brType = BTB_JUMP;
            if (i != 0) begin
                jumps[i-1].nextAddr = jumps[i].brAddr;
                jumps[i].btbLookup.setIndex = ToBTB_Set(jumps[i-1].brAddr);
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
                    port.nextStage.brPred[0].btbLookup == jumps[i].btbLookup &&
                    port.fetchRequestPC == jumps[i+1].brAddr &&
                    btb.btbEntryArray.rwa == ToBTB_Set(jumps[i+1].brAddr))
                else $fatal(1, "BTB lookahead at PC %h: predicted %h, RAM set %h, expected next PC %h set %h",
                            port.pcOut, port.fetchRequestPC, btb.btbEntryArray.rwa,
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
        #((3 * RESET_CYCLES + 2 * PHT_ROWS + 1000) * 10);
        $fatal(1, "Branch predictor queue test timed out");
    end

    initial begin
        ClearResults();
        // Redirect each lookup to the test address and suppress speculative history
        // updates until the directed fetch check releases clear.
        recovery.fetchRedirect = '{valid: TRUE, pc: '0, restorePredCtx: TRUE, predCtx: '0};
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
        @(negedge clk);
        port.brResult[0] = MakeResult(4);
        port.brResult[1] = MakeResult(5);
        ResetTables();
        ClearResults();
        assert (btb.count == 0) else $fatal(1, "Reset must discard pending training requests");
        ReadAllPHTRows(); // A warm reset must restore both banks, including the trained high addresses.
        CheckAheadRows();
        CheckAheadSequence();
        CheckOverlappingMisses();
        CheckFullBTBQueue();
        $display("========== Test Passed ==========");
        $finish;
    end
endmodule
