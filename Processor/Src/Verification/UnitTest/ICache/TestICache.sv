// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;
import MemoryMapTypes::*;
import CacheSystemTypes::*;

module TestICache;
    localparam STEP = 20;
    localparam HOLD = 4;
    localparam SET_STRIDE = ICACHE_INDEX_NUM * ICACHE_LINE_BYTE_NUM;
    localparam PhyAddrPath ADDR_A = PhyAddrPath'('h4000);
    localparam PhyAddrPath ADDR_B = PhyAddrPath'(ADDR_A + SET_STRIDE - ICACHE_LINE_BYTE_NUM);
    localparam PhyAddrPath ADDR_C = PhyAddrPath'(ADDR_A + SET_STRIDE);
    localparam PhyAddrPath ADDR_D = PhyAddrPath'(ADDR_A + 2 * SET_STRIDE);
    localparam ICacheLinePath LINE_A = 64'h01234567_89abcdef;
    localparam ICacheLinePath LINE_B = 64'hfedcba98_76543210;
    localparam ICacheLinePath LINE_C = 64'h11223344_55667788;
    localparam ICacheLinePath LINE_D = 64'h99aabbcc_ddeeff00;

    logic clk, rst, rstStart;
    TestBenchClockGenerator #(
        .STEP(STEP), .INITIALIZATION_CYCLE(ICACHE_INDEX_NUM + 2)
    ) clkgen ( .rstOut(FALSE), .* );
    NextPCStageIF nextPCStageIF(clk, rst, rstStart);
    FetchStageIF fetchStageIF(clk, rst, rstStart);
    CacheSystemIF cacheSystemIF(clk, rst);
    ICache iCache(nextPCStageIF, fetchStageIF, cacheSystemIF);

    // Match the address pipeline: supply the RAM index one cycle before the tag.
    always_ff @(posedge clk)
        fetchStageIF.icReadAddrIn <= nextPCStageIF.icNextReadAddrIn;

    int fillCount = 0;

    task CheckRead(input logic expectedHit, input ICacheLinePath expectedLine = '0);
        int wordIndex;
        logic laneHit;
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            wordIndex = (fetchStageIF.icReadAddrIn % ICACHE_LINE_BYTE_NUM) / INSN_BYTE_WIDTH + i;
            laneHit = expectedHit && wordIndex < ICACHE_LINE_INSN_NUM;
            assert (fetchStageIF.icReadHit[i] === laneHit)
                else $fatal(1, "Fetch at %h lane %0d: expected hit=%b, got %b",
                            fetchStageIF.icReadAddrIn, i, laneHit, fetchStageIF.icReadHit[i]);
            if (laneHit) begin
                assert (fetchStageIF.icReadDataOut[i] === expectedLine[wordIndex * INSN_WIDTH +: INSN_WIDTH])
                    else $fatal(1, "Fetch at %h lane %0d: expected %h, got %h",
                                fetchStageIF.icReadAddrIn, i,
                                expectedLine[wordIndex * INSN_WIDTH +: INSN_WIDTH], fetchStageIF.icReadDataOut[i]);
            end
        end
    endtask

    task CheckRequest(input logic expectedValid, input PhyAddrPath expectedAddr = '0);
        assert (cacheSystemIF.icMemAccessReq.valid === expectedValid)
            else $fatal(1, "Memory request: expected valid=%b, got %b",
                        expectedValid, cacheSystemIF.icMemAccessReq.valid);
        if (expectedValid) begin
            assert (cacheSystemIF.icMemAccessReq.addr === expectedAddr)
                else $fatal(1, "Memory request: expected address %h, got %h",
                            expectedAddr, cacheSystemIF.icMemAccessReq.addr);
        end
    endtask

    task Read(input PhyAddrPath addr, input logic expectedHit,
              input ICacheLinePath expectedLine = '0, input logic enable = TRUE);
        @(negedge clk);
        nextPCStageIF.icNextReadAddrIn = addr;
        fetchStageIF.icRE = FALSE;
        @(posedge clk);
        #HOLD;
        fetchStageIF.icRE = enable;
        #HOLD;
        CheckRead(expectedHit, expectedLine);
        // Let a hit update NRU, or a miss start the memory request.
        @(posedge clk);
        #HOLD;
        fetchStageIF.icRE = FALSE;
        if (expectedHit || !enable)
            CheckRequest(FALSE);
    endtask

    task Fill(input PhyAddrPath addr, input ICacheLinePath lineData);
        MemAccessSerial serial;
        serial = MemAccessSerial'(fillCount + 1);
        // The line request must remain stable until the memory accepts it.
        repeat (3) begin
            CheckRequest(TRUE, addr);
            @(posedge clk);
            #HOLD;
        end
        @(negedge clk);
        cacheSystemIF.icMemAccessReqAck = '{TRUE, serial, '0};
        @(posedge clk);
        #HOLD;
        CheckRequest(FALSE);
        @(negedge clk);
        cacheSystemIF.icMemAccessReqAck = '0;
        fetchStageIF.icRE = TRUE;

        // Ignore an invalid result and a valid result belonging to another request.
        for (int i = 0; i < 2; i++) begin
            cacheSystemIF.icMemAccessResult = '{i == 1, MemAccessSerial'(serial + i), ~lineData};
            repeat (3) begin
                @(posedge clk);
                #HOLD;
                CheckRead(FALSE);
                CheckRequest(FALSE);
            end
            @(negedge clk);
        end

        cacheSystemIF.icMemAccessResult = '{TRUE, serial, lineData};
        @(posedge clk);
        #HOLD;
        // The filled block RAM is not readable at the write edge.
        CheckRead(FALSE);
        @(negedge clk);
        cacheSystemIF.icMemAccessResult = '0;
        @(posedge clk);
        #HOLD;
        CheckRead(TRUE, lineData);
        CheckRequest(FALSE);
        @(posedge clk);
        #HOLD;
        fetchStageIF.icRE = FALSE;
        fillCount++;
    endtask

    initial begin
        #(STEP * 2 * (ICACHE_INDEX_NUM * 3 + 300));
        $fatal(1, "ICache test timed out after %0d fills", fillCount);
    end

    initial begin
        // The replacement sequence below exercises the default two-way configuration.
        assert (ICACHE_WAY_NUM == 2 && ICACHE_LINE_INSN_NUM == 2 && FETCH_WIDTH == 2)
            else $fatal(1, "This test requires two ways, two instructions per line, and two fetch lanes");
        nextPCStageIF.icNextReadAddrIn = ADDR_A;
        fetchStageIF.icRE = FALSE;
        cacheSystemIF.icMemAccessReqAck = '0;
        cacheSystemIF.icMemAccessResult = '0;
        cacheSystemIF.icFlushReq = FALSE;
        cacheSystemIF.flushComplete = FALSE;
        // Initialize every cache index before releasing reset.
        rstStart = TRUE;
        @(posedge clk);
        @(negedge clk);
        rstStart = FALSE;
        @(negedge rst);
        $display("========== Test Start ==========");

        // A miss in the middle of a line must request the aligned line address.
        Read(PhyAddrPath'(ADDR_A + INSN_BYTE_WIDTH), FALSE);
        Fill(ADDR_A, LINE_A);
        Read(ADDR_A, TRUE, LINE_A);
        Read(PhyAddrPath'(ADDR_A + INSN_BYTE_WIDTH), TRUE, LINE_A);
        // The first and last sets must retain their data independently.
        Read(ADDR_B, FALSE);
        Fill(ADDR_B, LINE_B);
        Read(ADDR_A, TRUE, LINE_A);
        Read(ADDR_C, FALSE);
        Fill(ADDR_C, LINE_C);

        // Touch A, then fill D into the same set: C must be evicted and A retained.
        Read(ADDR_A, TRUE, LINE_A);
        Read(ADDR_D, FALSE);
        Fill(ADDR_D, LINE_D);
        Read(ADDR_A, TRUE, LINE_A);
        Read(ADDR_B, TRUE, LINE_B);
        Read(ADDR_C, FALSE);
        Fill(ADDR_C, LINE_C);
        Read(ADDR_A, TRUE, LINE_A);

        // Disabled reads must not hit or request a missing line.
        Read(ADDR_A, FALSE, '0, FALSE);
        Read(ADDR_D, FALSE, '0, FALSE);
        repeat (3) begin
            @(posedge clk);
            #HOLD;
            CheckRead(FALSE);
            CheckRequest(FALSE);
        end

        // Flush all sets, and keep completion asserted until the manager releases it.
        @(negedge clk);
        cacheSystemIF.icFlushReq = TRUE;
        @(posedge clk);
        #HOLD;
        assert (cacheSystemIF.icFlushReqAck === FALSE)
            else $fatal(1, "Flush request was not accepted");
        @(negedge clk);
        cacheSystemIF.icFlushReq = FALSE;
        do begin
            @(posedge clk);
            #HOLD;
            CheckRequest(FALSE);
        end while (cacheSystemIF.icFlushComplete !== TRUE);
        repeat (2) begin
            @(posedge clk);
            #HOLD;
            assert (cacheSystemIF.icFlushComplete === TRUE && cacheSystemIF.icFlushReqAck === FALSE)
                else $fatal(1, "Flush completion was not held until manager acknowledgement");
        end
        @(negedge clk);
        cacheSystemIF.flushComplete = TRUE;
        @(posedge clk);
        #HOLD;
        assert (cacheSystemIF.icFlushComplete === FALSE && cacheSystemIF.icFlushReqAck === TRUE)
            else $fatal(1, "Flush did not return to the ready state");
        @(negedge clk);
        cacheSystemIF.flushComplete = FALSE;
        Read(ADDR_A, FALSE);
        Fill(ADDR_A, LINE_D);
        Read(ADDR_B, FALSE);
        Fill(ADDR_B, LINE_C);

        $display("========== Test Passed: %0d fills ==========", fillCount);
        $finish;
    end
endmodule : TestICache
