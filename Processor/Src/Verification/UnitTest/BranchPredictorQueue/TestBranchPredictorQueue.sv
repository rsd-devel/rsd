// Copyright 2026- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;
import FetchUnitTypes::*;

module TestBranchPredictorQueue;
    localparam int RESET_CYCLES = (BTB_SET_NUM > PHT_ENTRY_NUM ? BTB_SET_NUM : PHT_ENTRY_NUM) + 1;
    logic clk = FALSE;
    logic rst = TRUE;
    logic rstStart = TRUE;
    always #5 clk = ~clk;

    NextPCStageIF port(.*);
    FetchStageIF next(.*), bimodalNext(.*);
    ControllerIF ctrl(.*);
    BTB btb(.port(port), .next(next));
    Gshare gshare(.port(port), .next(next), .ctrl(ctrl));
    Bimodal bimodal(.port(port), .next(bimodalNext));

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

    task ReadBTB(input MemoryMapTypes::PC_Path pc);
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

    task CheckBTB(input int lane, input BranchResult expected);
        assert (next.btbHit[lane] === expected.valid &&
                (!expected.valid || (next.btbOut[lane] === expected.nextAddr &&
                                     next.readIsCondBr[lane] === expected.isCondBr)))
            else $fatal(1, "BTB PC %h lane %0d expected hit %b target %h conditional %b",
                        port.fetchRequestPC, lane, expected.valid, expected.nextAddr, expected.isCondBr);
    endtask

    task CheckBTBTraining;
        BranchResult hit, miss, notTaken;
        hit = MakeResult(0);
        miss = MakeResult(1);
        notTaken = miss;
        notTaken.execTaken = FALSE;
        hit.btbTargetCorrect = TRUE;
        // The direction can miss even when the BTB returned the right target.
        hit.predTaken = FALSE;
        hit.mispred = TRUE;
        @(negedge clk);
        port.brResult[0] = hit;
        port.brResult[1] = notTaken;
        #1;
        assert (btb.btbEntryArray.we === '0 && btb.pushCount == 0 && gshare.phtWE[0])
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
        ReadBTB(miss.brAddr);
        CheckBTB(ToFetchGroupOffset(miss.brAddr), miss);
    endtask

    // The PHTs defer the second result while the first lane keeps training.
    task CheckBurst(input int count, input int firstIndex);
        BranchResult expected;
        for (int i = 0; i < count; i++) begin
            @(negedge clk);
            port.brResult[0] = MakeResult(0);
            port.brResult[1] = MakeResult(firstIndex + i);
        end
        // A direct update delays the queue without discarding any entry.
        @(negedge clk);
        port.brResult[1] = '0;
        repeat (3) @(negedge clk);
        ClearResults();
        for (int i = 0; i < count; i++) begin
            expected = MakeResult(firstIndex + i);
            port.fetchRequestPC = expected.brAddr;
            #1;
            assert (gshare.phtWE[0] &&
                    gshare.phtWA[0] === PHT_IndexPath'(firstIndex + i) &&
                    gshare.phtWV[0] === PHT_EntryPath'(expected.phtPrevValue + 1))
                else $fatal(1, "Gshare queued update %0d was lost or reordered", firstIndex + i);
            assert (bimodal.phtWE[0] &&
                    bimodal.phtWA[0] === PHT_IndexPath'(firstIndex + i) &&
                    bimodal.phtWV[0] === PHT_EntryPath'(expected.phtPrevValue + 1))
                else $fatal(1, "Bimodal queued update %0d was lost or reordered", firstIndex + i);
            @(negedge clk);
        end
        #1;
        assert (gshare.empty && bimodal.empty && !gshare.phtWE[0] && !bimodal.phtWE[0])
            else $fatal(1, "PHT update queues did not drain");
        // Check the resulting table contents through the normal read ports.
        for (int i = 0; i < count; i++) begin
            int slot;
            expected = MakeResult(firstIndex + i);
            slot = (firstIndex + i) % FETCH_WIDTH;
            ReadBTB(expected.brAddr);
            assert (next.phtPrevValue[slot] === PHT_EntryPath'(expected.phtPrevValue + 1) &&
                    bimodalNext.phtPrevValue[slot] === PHT_EntryPath'(expected.phtPrevValue + 1))
                else $fatal(1, "PHT readback mismatch at %0d", firstIndex + i);
        end
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
        ReadBTB(cold.brAddr);
        CheckBTB(0, cold);
        assert (next.btbHitWay[0] === BTB_WayIndexPath'(BTB_WAY_NUM-1))
            else $fatal(1, "Expected the highest way on a duplicate reset tag");
        CheckBTB(FETCH_WIDTH-1, '0);
        ReadBTB(first.brAddr);
        CheckBTB(0, '0);
        WriteBTB(first, last);
        if (BTB_SET_NUM > 1) WriteBTB(neighbor);
        ReadBTB(first.brAddr);
        CheckBTB(0, first);
        CheckBTB(FETCH_WIDTH-1, last);
        first.btbHit = next.btbHit[0];
        first.btbHitWay = next.btbHitWay[0];
        last.btbHit = next.btbHit[FETCH_WIDTH-1];
        last.btbHitWay = next.btbHitWay[FETCH_WIDTH-1];
        assert (first.btbHitWay != last.btbHitWay) else $fatal(1, "Expected hits in distinct ways");
        if (BTB_SET_NUM > 1) begin
            ReadBTB(neighbor.brAddr);
            CheckBTB(0, neighbor);
        end
        ReadBTB(last.brAddr);
        // A request starting at the last word still returns the same complete group.
        CheckBTB(0, first);
        CheckBTB(FETCH_WIDTH-1, last);
        // The skipped conditional branch predicts taken but must not shift history.
        next.updateBrHistory[FETCH_WIDTH-1] = TRUE;
        bimodalNext.btbHit[0] = TRUE;
        bimodalNext.btbHit[FETCH_WIDTH-1] = TRUE;
        #1;
        assert (next.brPredTaken[0] && next.brPredTaken[FETCH_WIDTH-1] &&
                bimodalNext.brPredTaken[0] && bimodalNext.brPredTaken[FETCH_WIDTH-1] &&
                gshare.nextBrGlobalHistory === gshare.regBrGlobalHistory)
            else $fatal(1, "A skipped slot changed the history or hid the later prediction");
        next.updateBrHistory[FETCH_WIDTH-1] = FALSE;
        bimodalNext.btbHit[0] = FALSE;
        bimodalNext.btbHit[FETCH_WIDTH-1] = FALSE;

        // On a same-row read/write the old target and branch kind are visible
        // for one cycle. Updating the first branch makes its way the newest.
        updated = first;
        updated.nextAddr += INSN_BYTE_WIDTH;
        updated.isCondBr = FALSE;
        ReadBTB(first.brAddr);
        WriteBTB(updated);
        CheckBTB(0, first);
        @(posedge clk);
        #1;
        CheckBTB(0, updated);
        CheckBTB(FETCH_WIDTH-1, last);
        // Repeated training of the same key must stay in that way.
        updated.nextAddr += INSN_BYTE_WIDTH;
        WriteBTB(updated);
        ReadBTB(first.brAddr);
        CheckBTB(0, updated);
        CheckBTB(FETCH_WIDTH-1, last);
        // A different block in the same set replaces the older branch.
        WriteBTB(aliasBranch);
        ReadBTB(aliasBranch.brAddr);
        CheckBTB(0, aliasBranch);
        CheckBTB(FETCH_WIDTH-1, '0);
        ReadBTB(first.brAddr);
        CheckBTB(0, updated);
        CheckBTB(FETCH_WIDTH-1, '0);

        // The delayed hit for last still uses its Fetch way, now occupied by aliasBranch.
        // The earlier queued write uses that way first, leaving the other way as the miss victim.
        ReadBTB(aliasBranch.brAddr);
        aliasBranch.btbHit = next.btbHit[0];
        aliasBranch.btbHitWay = next.btbHitWay[0];
        assert (aliasBranch.btbHit && aliasBranch.btbHitWay == last.btbHitWay)
            else $fatal(1, "Alias did not evict the saved hit");
        aliasBranch.nextAddr += INSN_BYTE_WIDTH;
        last.nextAddr += 2 * INSN_BYTE_WIDTH;
        WriteBTB(aliasBranch, last);
        ReadBTB(first.brAddr);
        CheckBTB(0, updated);
        CheckBTB(FETCH_WIDTH-1, last);
        ReadBTB(aliasBranch.brAddr);
        CheckBTB(0, '0);

        ResetTables();
        ReadBTB(cold.brAddr);
        CheckBTB(0, cold);
        ReadBTB(first.brAddr);
        CheckBTB(0, '0);
        ReadBTB(aliasBranch.brAddr);
        CheckBTB(0, '0);
    endtask

    // Two instances fetched before either was trained can both report a miss.
    task CheckOverlappingMisses;
        BranchResult first, second;
        first = MakeResult(0);
        second = first;
        second.nextAddr += INSN_BYTE_WIDTH;
        WriteBTB(first, second); // The two requests allocate ways 0 then 1 after reset.
        ReadBTB(first.brAddr);
        CheckBTB(0, second);
        second.btbHit = next.btbHit[0];
        second.btbHitWay = next.btbHitWay[0];
        assert (second.btbHitWay) else $fatal(1, "Duplicate tag must report the way that supplied the target");
        second.nextAddr += INSN_BYTE_WIDTH;
        WriteBTB(second);
        ReadBTB(first.brAddr);
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
        foreach (next.updateBrHistory[i]) begin
            next.updateBrHistory[i] = FALSE;
            bimodalNext.btbHit[i] = FALSE;
            bimodalNext.readIsCondBr[i] = FALSE;
            bimodalNext.updateBrHistory[i] = FALSE;
            bimodalNext.btbOut[i] = '0;
        end
        ResetTables();
        if (FETCH_WIDTH >= 2) CheckBTBWays();

        CheckBurst(1, 1);
        // Exercise pointer wrap at the PHT queues' own depth.
        if (PHT_ENTRY_NUM >= 2*PHT_QUEUE_SIZE) begin
            CheckBurst(7, 2);
            // Fill and wrap both head and tail, then reuse their previous slots.
            CheckBurst(PHT_QUEUE_SIZE, 9);
            CheckBurst(5, 9 + PHT_QUEUE_SIZE);
        end
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
