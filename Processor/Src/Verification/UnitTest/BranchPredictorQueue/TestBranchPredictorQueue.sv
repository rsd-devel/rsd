// Copyright 2026- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;
import FetchUnitTypes::*;

module TestBranchPredictorQueue;
    localparam int PHT_ROWS = PHT_ENTRY_NUM / FETCH_WIDTH;
    localparam int RESET_CYCLES = (BTB_SET_NUM > PHT_ROWS ? BTB_SET_NUM : PHT_ROWS) + 1;
    logic clk = FALSE;
    logic rst = TRUE;
    logic rstStart = TRUE;
    always #5 clk = ~clk;

    FetchStageIF port(.*), bimodalPort(.*);
    ControllerIF ctrl(.*);
    BTB btb(.port(port));
    Gshare gshare(.port(port), .ctrl(ctrl));
    Bimodal bimodal(.port(bimodalPort));

    // Exercise both predictors with the same fetch addresses and training results.
    always_comb begin
        bimodalPort.fetchRequestPC = port.fetchRequestPC;
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
        port.fetchRequestPC = pc;
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

    // Model the counter tables as flat arrays. Sample every returned counter
    // before applying this edge's oldest write, including same-row collisions.
    PHT_EntryPath expectedGshare[PHT_ENTRY_NUM], expectedBimodal[PHT_ENTRY_NUM];
    BranchResult pendingPHT[$];
    function automatic PHT_IndexPath HashedIndex(input PHT_IndexPath index, input BranchGlobalHistoryPath history);
        return index ^ (PHT_IndexPath'(history) << (PHT_ENTRY_NUM_BIT_WIDTH - BRANCH_GLOBAL_HISTORY_BIT_WIDTH));
    endfunction

    always @(posedge clk) begin
        BranchResult samples[INT_ISSUE_WIDTH], oldest;
        PHT_IndexPath base, index;
        PHT_EntryPath updated;
        bit wasFull;
        if (rst) begin
            pendingPHT.delete();
            if (rstStart) begin
                foreach (expectedGshare[i]) begin
                    expectedGshare[i] = PHT_ENTRY_MAX / 2 + 1;
                    expectedBimodal[i] = PHT_ENTRY_MAX / 2 + 1;
                end
            end
        end
        else begin
            base = PHT_IndexPath'((port.fetchRequestPC >> INSN_ADDR_BIT_WIDTH) & ~(FETCH_WIDTH - 1));
            samples = port.brResult;
            #1;
            foreach (port.phtPrevValue[i]) begin
                index = base + i;
                assert (bimodalPort.phtPrevValue[i] === expectedBimodal[index])
                    else $fatal(1, "Bimodal counter mismatch at %0d", index);
                index = HashedIndex(index, port.brGlobalHistory);
                assert (port.phtPrevValue[i] === expectedGshare[index])
                    else $fatal(1, "Gshare counter mismatch at %0d (history %h)", index, port.brGlobalHistory);
            end
            wasFull = pendingPHT.size() == PHT_QUEUE_SIZE;
            if (pendingPHT.size() != 0) begin
                oldest = pendingPHT.pop_front();
                updated = oldest.phtPrevValue;
                if (oldest.execTaken && updated < PHT_ENTRY_MAX) updated++;
                if (!oldest.execTaken && updated > 0) updated--;
                index = PHT_IndexPath'(oldest.brAddr >> INSN_ADDR_BIT_WIDTH);
                expectedBimodal[index] = updated;
                expectedGshare[HashedIndex(index, oldest.globalHistory)] = updated;
            end
            foreach (samples[i])
                if (!wasFull && samples[i].valid) pendingPHT.push_back(samples[i]);
        end
    end

    task CheckPHTQueue;
        localparam int RESULTS = 2 * PHT_QUEUE_SIZE * INT_ISSUE_WIDTH;
        BranchResult result;
        // Keep reading the first row while the first two updates enqueue and drain.
        // Distinct later addresses make dropped updates visible after the queue wraps.
        for (int i = 0; i < RESULTS; i += INT_ISSUE_WIDTH) begin
            @(negedge clk);
            foreach (port.brResult[lane]) begin
                result = MakeResult(i + lane);
                result.phtPrevValue = '0;
                result.execTaken = ((i + lane) % 2 == 1);
                port.brResult[lane] = result;
            end
        end
        @(negedge clk);
        ClearResults();
        repeat (PHT_QUEUE_SIZE) @(negedge clk);
        // The high issue lane also trains when it is the only valid result.
        result = MakeResult(RESULTS);
        result.phtPrevValue = PHT_ENTRY_MAX;
        port.brResult[INT_ISSUE_WIDTH-1] = result;
        @(negedge clk);
        ClearResults();
        for (int i = 0; i <= RESULTS; i++) begin
            result = MakeResult(i);
            ReadGroup(result.brAddr);
        end
    endtask

    task CheckPHTHistory;
        BranchResult result;
        PHT_IndexPath index;
        result = MakeResult(PHT_ENTRY_NUM - FETCH_WIDTH);
        result.globalHistory = '1;
        result.phtPrevValue = '0;
        result.execTaken = FALSE;
        result.isCondBr = FALSE;
        // Train under a saved nonzero history while the live history is zero.
        @(negedge clk);
        port.brResult[INT_ISSUE_WIDTH-1] = result;
        @(negedge clk);
        ClearResults();
        @(negedge clk);
        index = HashedIndex(PHT_IndexPath'(result.brAddr >> INSN_ADDR_BIT_WIDTH), result.globalHistory);
        ReadGroup(index * INSN_BYTE_WIDTH);
        ReadGroup(result.brAddr);
        // History recovery selects the new row for the request issued on this edge.
        @(negedge clk);
        result.mispred = TRUE;
        port.brResult[0] = result;
        port.fetchRequestPC = result.brAddr + (FETCH_WIDTH-1) * INSN_BYTE_WIDTH;
        @(posedge clk);
        #1;
        assert (port.brGlobalHistory === result.globalHistory)
            else $fatal(1, "Gshare did not restore the saved history");
        @(negedge clk);
        ClearResults();
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
        WriteBTB(first, last);
        if (BTB_SET_NUM > 1) WriteBTB(neighbor);
        ReadGroup(first.brAddr);
        CheckBTB(0, first);
        CheckBTB(FETCH_WIDTH-1, last);
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
        port.updateBrHistory[FETCH_WIDTH-1] = TRUE;
        bimodalPort.btbHit[0] = TRUE;
        bimodalPort.btbHit[FETCH_WIDTH-1] = TRUE;
        #1;
        assert (port.brPredTaken[0] && port.brPredTaken[FETCH_WIDTH-1] &&
                bimodalPort.brPredTaken[0] && bimodalPort.brPredTaken[FETCH_WIDTH-1] &&
                gshare.nextBrGlobalHistory === gshare.regBrGlobalHistory)
            else $fatal(1, "The branch before the fetch start changed the history or hid the later prediction");
        port.updateBrHistory[FETCH_WIDTH-1] = FALSE;
        bimodalPort.btbHit[0] = FALSE;
        bimodalPort.btbHit[FETCH_WIDTH-1] = FALSE;

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
        #((3 * RESET_CYCLES + 1000) * 10);
        $fatal(1, "Branch predictor queue test timed out");
    end

    initial begin
        ClearResults();
        port.fetchRequestPC = '0;
        ctrl.ifStage = '0;
        foreach (port.updateBrHistory[groupOffset]) begin
            port.updateBrHistory[groupOffset] = FALSE;
            bimodalPort.btbHit[groupOffset] = FALSE;
            bimodalPort.readIsCondBr[groupOffset] = FALSE;
            bimodalPort.updateBrHistory[groupOffset] = FALSE;
            bimodalPort.btbOut[groupOffset] = '0;
        end
        ResetTables();
        if (FETCH_WIDTH >= 2) CheckBTBWays();

        port.fetchRequestPC = '0;
        CheckPHTQueue();
        CheckPHTHistory();
        CheckBTBTraining();
        @(negedge clk);
        port.brResult[0] = MakeResult(4);
        port.brResult[1] = MakeResult(5);
        ResetTables();
        ClearResults();
        assert (btb.count == 0) else $fatal(1, "Reset must discard pending training requests");
        CheckOverlappingMisses();
        CheckFullBTBQueue();
        $display("========== Test Passed ==========");
        $finish;
    end
endmodule
