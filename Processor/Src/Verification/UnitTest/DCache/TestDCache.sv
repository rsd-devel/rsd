// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;
import MemoryMapTypes::*;
import CacheSystemTypes::*;

module TestDCache;
    localparam STEP = 20;
    localparam HOLD = 4;
    localparam SET_STRIDE = DCACHE_INDEX_NUM * DCACHE_LINE_BYTE_NUM;
    localparam PhyAddrPath ADDR_A = PhyAddrPath'('h4000);
    localparam PhyAddrPath ADDR_B = PhyAddrPath'(ADDR_A + SET_STRIDE);
    localparam PhyAddrPath ADDR_C = PhyAddrPath'(ADDR_A + 2 * SET_STRIDE);
    localparam PhyAddrPath ADDR_D = PhyAddrPath'(ADDR_A + SET_STRIDE - DCACHE_LINE_BYTE_NUM);
    localparam DCacheLinePath LINE_A = 64'h01234567_89abcdef;
    localparam DCacheLinePath LINE_B = 64'hfedcba98_76543210;
    localparam DCacheLinePath LINE_C = 64'h11223344_55667788;
    localparam DCacheLinePath LINE_D = 64'h99aabbcc_ddeeff00;
    localparam DCacheLinePath MODIFIED_A = 64'hdeadbeef_11aa3344;
    localparam DCacheLinePath MODIFIED_D = 64'h99aabbcc_ddeeffee;

    logic clk, rst, rstStart;
    TestBenchClockGenerator #(
        .STEP(STEP), .INITIALIZATION_CYCLE(DCACHE_INDEX_NUM + 2)
    ) clkgen ( .rstOut(FALSE), .* );
    LoadStoreUnitIF loadStoreUnitIF(clk, rst, rstStart);
    CacheSystemIF cacheSystemIF(clk, rst);
    ControllerIF controllerIF(clk, rst);
    RecoveryManagerIF recoveryIF(clk, rst);
    DCache dCache(loadStoreUnitIF, cacheSystemIF, controllerIF, recoveryIF);

    int readCount = 0;
    int writeCount = 0;
    MSHR_IndexPath mshrID;

    task Store(input PhyAddrPath addr, input DCacheLinePath data,
               input DCacheByteEnablePath byteWE, input logic expectedHit,
               output MSHR_IndexPath id, input logic readEnable = FALSE,
               input PhyAddrPath readAddr = '0, input DCacheLinePath readData = '0);
        @(negedge clk);
        loadStoreUnitIF.dcReadReq[0] = readEnable;
        loadStoreUnitIF.dcReadAddr[0] = readAddr;
        loadStoreUnitIF.dcWriteReq = TRUE;
        loadStoreUnitIF.dcWriteAddr = addr;
        loadStoreUnitIF.dcWriteData = data;
        loadStoreUnitIF.dcWriteByteWE = byteWE;
        #HOLD;
        assert (loadStoreUnitIF.dcWriteReqAck === TRUE)
            else $fatal(1, "Store at %h was not accepted", addr);
        @(posedge clk);
        #HOLD;
        assert (loadStoreUnitIF.dcWriteHit === expectedHit && loadStoreUnitIF.dcWriteBusy === FALSE)
            else $fatal(1, "Store at %h: expected hit=%b, got hit=%b busy=%b",
                        addr, expectedHit, loadStoreUnitIF.dcWriteHit, loadStoreUnitIF.dcWriteBusy);
        assert (loadStoreUnitIF.storeHasAllocatedMSHR[0] === !expectedHit)
            else $fatal(1, "Unexpected store MSHR allocation at %h", addr);
        if (readEnable) begin
            assert (loadStoreUnitIF.dcReadHit[0] === TRUE && loadStoreUnitIF.dcReadBusy[0] === FALSE)
                else $fatal(1, "Concurrent load at %h did not hit", readAddr);
        end
        id = loadStoreUnitIF.storeMSHRID[0];
        @(negedge clk);
        loadStoreUnitIF.dcWriteReq = FALSE;
        loadStoreUnitIF.dcReadReq[0] = FALSE;
        // Keep the payload stable until miss handling merges it with the fetched line.
        @(posedge clk);
        #HOLD;
        if (readEnable) begin
            assert (loadStoreUnitIF.dcReadData[0] === readData)
                else $fatal(1, "Concurrent load at %h: expected %h, got %h", readAddr, readData, loadStoreUnitIF.dcReadData[0]);
        end
    endtask

    task LoadMiss(input PhyAddrPath addr, output MSHR_IndexPath id);
        @(negedge clk);
        loadStoreUnitIF.dcReadReq[0] = TRUE;
        loadStoreUnitIF.dcReadAddr[0] = addr;
        @(posedge clk);
        #HOLD;
        assert (loadStoreUnitIF.dcReadHit[0] === FALSE && loadStoreUnitIF.dcReadBusy[0] === FALSE &&
                loadStoreUnitIF.loadHasAllocatedMSHR[0] === TRUE)
            else $fatal(1, "Load miss at %h did not allocate an MSHR", addr);
        id = loadStoreUnitIF.loadMSHRID[0];
        @(negedge clk);
        loadStoreUnitIF.dcReadReq[0] = FALSE;
        @(posedge clk);
        #HOLD;
        assert (loadStoreUnitIF.mshrValid[id] === TRUE)
            else $fatal(1, "Allocated MSHR %0d is not valid", id);
    endtask

    task MemoryAccess(input logic write, input PhyAddrPath addr,
                      input DCacheLinePath data, input MSHR_IndexPath id);
        MemAccessSerial serial;
        MemWriteSerial wserial;
        serial = MemAccessSerial'(readCount + 1);
        wserial = MemWriteSerial'(writeCount + 1);
        while (cacheSystemIF.dcMemAccessReq.valid !== TRUE) begin
            @(posedge clk);
            #HOLD;
        end
        // A request must remain stable while memory delays its acknowledgement.
        repeat (3) begin
            assert (cacheSystemIF.dcMemAccessReq.valid === TRUE &&
                    cacheSystemIF.dcMemAccessReq.we === write && cacheSystemIF.dcMemAccessReq.addr === addr)
                else $fatal(1, "Expected memory write=%b addr=%h, got %p", write, addr, cacheSystemIF.dcMemAccessReq);
            if (write) begin
                assert (cacheSystemIF.dcMemAccessReq.data === data)
                    else $fatal(1, "Writeback at %h: expected %h, got %h", addr, data, cacheSystemIF.dcMemAccessReq.data);
            end
            @(posedge clk);
            #HOLD;
        end
        @(negedge clk);
        cacheSystemIF.dcMemAccessReqAck = '{TRUE, serial, wserial};
        @(posedge clk);
        @(negedge clk);
        cacheSystemIF.dcMemAccessReqAck = '0;

        // Neither an invalid response nor a response for another transaction may advance the MSHR.
        for (int i = 0; i < 2; i++) begin
            if (write)
                cacheSystemIF.dcMemAccessResponse = '{i == 1, MemWriteSerial'(wserial + i)};
            else
                cacheSystemIF.dcMemAccessResult = '{i == 1, MemAccessSerial'(serial + i), ~data};
            repeat (3) begin
                @(posedge clk);
                #HOLD;
                assert (loadStoreUnitIF.mshrPhase[id] ===
                        (write ? MSHR_PHASE_VICTIM_WRITE_COMPLETE : MSHR_PHASE_MISS_READ_MEM_RECEIVE) &&
                        cacheSystemIF.dcMemAccessReq.valid === FALSE)
                    else $fatal(1, "MSHR %0d advanced before the matching memory response", id);
            end
            @(negedge clk);
        end
        if (write) begin
            cacheSystemIF.dcMemAccessResponse = '{TRUE, wserial};
            writeCount++;
        end
        else begin
            cacheSystemIF.dcMemAccessResult = '{TRUE, serial, data};
            readCount++;
        end
        @(posedge clk);
        @(negedge clk);
        cacheSystemIF.dcMemAccessResponse = '0;
        cacheSystemIF.dcMemAccessResult = '0;
    endtask

    task WaitFree(input MSHR_IndexPath id);
        do begin
            @(posedge clk);
            #HOLD;
            assert (cacheSystemIF.dcMemAccessReq.valid === FALSE)
                else $fatal(1, "Unexpected memory request while waiting for MSHR %0d to retire", id);
        end while (loadStoreUnitIF.mshrValid[id] !== FALSE);
    endtask

    task CompleteLoad(input PhyAddrPath addr, input DCacheLinePath data, input MSHR_IndexPath id);
        while (loadStoreUnitIF.mshrPhase[id] !== MSHR_PHASE_MISS_HANDLING_COMPLETE) begin
            @(posedge clk);
            #HOLD;
        end
        // The allocating load receives the filled line through the MSHR bypass before releasing it.
        @(negedge clk);
        loadStoreUnitIF.dcReadReq[0] = TRUE;
        loadStoreUnitIF.dcReadAddr[0] = addr;
        @(posedge clk);
        #HOLD;
        assert (loadStoreUnitIF.dcReadHit[0] === FALSE && loadStoreUnitIF.dcReadBusy[0] === TRUE &&
                loadStoreUnitIF.mshrAddrHit[0] === TRUE && loadStoreUnitIF.mshrAddrHitMSHRID[0] === id &&
                loadStoreUnitIF.mshrReadHit[0] === TRUE && loadStoreUnitIF.mshrReadData[0] === data)
            else $fatal(1, "Load at %h did not receive %h from MSHR %0d", addr, data, id);
        @(negedge clk);
        loadStoreUnitIF.dcReadReq[0] = FALSE;
        @(posedge clk);
        @(negedge clk);
        loadStoreUnitIF.makeMSHRCanBeInvalidDirect[id] = TRUE;
        @(posedge clk);
        @(negedge clk);
        loadStoreUnitIF.makeMSHRCanBeInvalidDirect[id] = FALSE;
        WaitFree(id);
    endtask

    task ReadHit(input PhyAddrPath addr, input DCacheLinePath data);
        @(negedge clk);
        loadStoreUnitIF.dcReadReq[0] = TRUE;
        loadStoreUnitIF.dcReadAddr[0] = addr;
        @(posedge clk);
        #HOLD;
        assert (loadStoreUnitIF.dcReadHit[0] === TRUE && loadStoreUnitIF.dcReadBusy[0] === FALSE &&
                loadStoreUnitIF.loadHasAllocatedMSHR[0] === FALSE)
            else $fatal(1, "Load at %h did not hit", addr);
        @(negedge clk);
        loadStoreUnitIF.dcReadReq[0] = FALSE;
        @(posedge clk);
        #HOLD;
        assert (loadStoreUnitIF.dcReadData[0] === data)
            else $fatal(1, "Load at %h: expected %h, got %h", addr, data, loadStoreUnitIF.dcReadData[0]);
        assert (cacheSystemIF.dcMemAccessReq.valid === FALSE)
            else $fatal(1, "A cache hit issued an unexpected memory request");
    endtask

    initial begin
        #(STEP * 2 * (DCACHE_INDEX_NUM + 1000));
        $fatal(1, "DCache test timed out after %0d reads and %0d writebacks; MSHR phases=%p",
                    readCount, writeCount, loadStoreUnitIF.mshrPhase);
    end

    initial begin
        // The replacement sequence and byte masks below exercise the default configuration.
        assert (DCACHE_WAY_NUM == 2 && DCACHE_LINE_BIT_WIDTH == 64 && DCACHE_LSU_READ_PORT_NUM == 1)
            else $fatal(1, "This test requires two ways, 64-bit lines, and one load port");
        loadStoreUnitIF.dcReadReq = '{default: FALSE};
        loadStoreUnitIF.dcReadAddr = '{default: '0};
        loadStoreUnitIF.dcReadUncachable = '{default: FALSE};
        loadStoreUnitIF.dcReadActiveListPtr = '{default: '0};
        loadStoreUnitIF.dcWriteReq = FALSE;
        loadStoreUnitIF.dcWriteAddr = '0;
        loadStoreUnitIF.dcWriteData = '0;
        loadStoreUnitIF.dcWriteByteWE = '0;
        loadStoreUnitIF.dcWriteUncachable = FALSE;
        loadStoreUnitIF.makeMSHRCanBeInvalidDirect = '{default: FALSE};
        cacheSystemIF.dcMemAccessReqAck = '0;
        cacheSystemIF.dcMemAccessResult = '0;
        cacheSystemIF.dcMemAccessResponse = '0;
        cacheSystemIF.dcFlushReq = FALSE;
        cacheSystemIF.flushComplete = FALSE;
        controllerIF.backEnd = '0;
        recoveryIF.toRecoveryPhase = FALSE;
        recoveryIF.flushRangeHeadPtr = '0;
        recoveryIF.flushRangeTailPtr = '0;
        recoveryIF.flushAllInsns = FALSE;
        rstStart = TRUE;
        @(posedge clk);
        @(negedge clk);
        rstStart = FALSE;
        @(negedge rst);
        $display("========== Test Start ==========");

        // A store miss merges only enabled bytes; untouched bytes come from memory.
        Store(ADDR_A, 64'h00000000_11223344, 8'h0f, FALSE, mshrID);
        MemoryAccess(FALSE, ADDR_A, LINE_A, mshrID);
        WaitFree(mshrID);
        ReadHit(ADDR_A, 64'h01234567_11223344);
        ReadHit(PhyAddrPath'(ADDR_A + 4), 64'h01234567_11223344);
        Store(PhyAddrPath'(ADDR_A + 4), 64'hdeadbeef_00000000, 8'hf0, TRUE, mshrID);
        ReadHit(ADDR_A, 64'hdeadbeef_11223344);
        Store(PhyAddrPath'(ADDR_A + 2), 64'h00000000_00aa0000, 8'h04, TRUE, mshrID);
        ReadHit(ADDR_A, MODIFIED_A);
        Store(ADDR_A, '1, '0, TRUE, mshrID);
        ReadHit(ADDR_A, MODIFIED_A);

        // Fill the other way and the last set, then exercise both array ports with a load and a store.
        LoadMiss(PhyAddrPath'(ADDR_B + 4), mshrID);
        MemoryAccess(FALSE, ADDR_B, LINE_B, mshrID);
        CompleteLoad(ADDR_B, LINE_B, mshrID);
        ReadHit(ADDR_A, MODIFIED_A);
        ReadHit(ADDR_B, LINE_B);
        LoadMiss(ADDR_D, mshrID);
        MemoryAccess(FALSE, ADDR_D, LINE_D, mshrID);
        CompleteLoad(ADDR_D, LINE_D, mshrID);
        Store(ADDR_D, 64'hee, 8'h01, TRUE, mshrID, TRUE, ADDR_B, LINE_B);
        ReadHit(ADDR_A, MODIFIED_A);
        ReadHit(ADDR_D, MODIFIED_D);

        // Make A the least recently used line. Its dirty data must be written back before filling C.
        ReadHit(ADDR_B, LINE_B);
        LoadMiss(ADDR_C, mshrID);
        MemoryAccess(TRUE, ADDR_A, MODIFIED_A, mshrID);
        MemoryAccess(FALSE, ADDR_C, LINE_C, mshrID);
        CompleteLoad(ADDR_C, LINE_C, mshrID);
        ReadHit(ADDR_C, LINE_C);
        ReadHit(ADDR_B, LINE_B);

        // Reload the evicted data. Replacing a clean line must not cause another writeback.
        LoadMiss(ADDR_A, mshrID);
        MemoryAccess(FALSE, ADDR_A, MODIFIED_A, mshrID);
        CompleteLoad(ADDR_A, MODIFIED_A, mshrID);
        ReadHit(ADDR_A, MODIFIED_A);
        ReadHit(ADDR_D, MODIFIED_D);
        repeat (3) begin
            @(posedge clk);
            #HOLD;
            assert (cacheSystemIF.dcMemAccessReq.valid === FALSE &&
                    loadStoreUnitIF.dcReadHit[0] === FALSE &&
                    loadStoreUnitIF.dcWriteHit === FALSE)
                else $fatal(1, "An idle cache reported a hit or issued a memory request");
        end
        $display("========== Test Passed: %0d reads, %0d writebacks ==========", readCount, writeCount);
        $finish;
    end
endmodule
