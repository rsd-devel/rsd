// Copyright 2026- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;
import FetchUnitTypes::*;

module TestBranchPredictorQueue;
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

    // Two results compete for one update port. The second must be retained
    // while new results use that port, then applied in FIFO order.
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
            #1;
            assert (btb.btbWE[0] &&
                    btb.btbWA[0] === ToBTB_Index(expected.brAddr) &&
                    btb.btbWV[0] === BTB_Entry'({1'b1,
                        ToBTB_Tag(expected.brAddr), ToBTB_Addr(expected.nextAddr), 1'b1}))
                else $fatal(1, "BTB queued update %0d was lost or reordered", firstIndex + i);
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
        assert (btb.empty && gshare.empty && bimodal.empty &&
                !btb.btbWE[0] && !gshare.phtWE[0] && !bimodal.phtWE[0])
            else $fatal(1, "Update queues did not drain");

        // Check the resulting table contents through the normal read ports.
        for (int i = 0; i < count; i++) begin
            expected = MakeResult(firstIndex + i);
            @(negedge clk);
            port.predNextPC = expected.brAddr;
            @(posedge clk);
            #1;
            assert (next.btbHit[0] === TRUE && next.btbOut[0] === expected.nextAddr)
                else $fatal(1, "BTB readback mismatch at %0d", firstIndex + i);
            assert (next.phtPrevValue[0] === PHT_EntryPath'(expected.phtPrevValue + 1) &&
                    bimodalNext.phtPrevValue[0] === PHT_EntryPath'(expected.phtPrevValue + 1))
                else $fatal(1, "PHT readback mismatch at %0d", firstIndex + i);
        end
    endtask

    initial begin
        #100000;
        $fatal(1, "Branch predictor queue test timed out");
    end

    initial begin
        ClearResults();
        port.predNextPC = '0;
        ctrl.ifStage = '0;
        foreach (next.updateBrHistory[i]) begin
            next.updateBrHistory[i] = FALSE;
            bimodalNext.btbHit[i] = FALSE;
            bimodalNext.readIsCondBr[i] = FALSE;
            bimodalNext.updateBrHistory[i] = FALSE;
            bimodalNext.btbOut[i] = '0;
        end
        @(negedge clk);
        rstStart = FALSE;
        repeat ((BTB_ENTRY_NUM > PHT_ENTRY_NUM ? BTB_ENTRY_NUM : PHT_ENTRY_NUM) + 1)
            @(negedge clk);
        rst = FALSE;

        CheckBurst(1, 1);
        CheckBurst(7, 2);
        // Fill and wrap both head and tail, then reuse their previous slots.
        CheckBurst(BTB_QUEUE_SIZE, 9);
        CheckBurst(5, 9 + BTB_QUEUE_SIZE);
        $display("========== Test Passed ==========");
        $finish;
    end
endmodule
