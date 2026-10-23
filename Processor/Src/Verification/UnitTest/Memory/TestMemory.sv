// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;
import MemoryMapTypes::*;
import CacheSystemTypes::*;
import MemoryTypes::*;

module TestMemory;
    localparam STEP = 20;
    localparam HOLD = 4;
    localparam PhyAddrPath ADDR_A = PhyAddrPath'('h1000);
    localparam PhyAddrPath ADDR_B = PhyAddrPath'('h1000 + MEMORY_ENTRY_BYTE_NUM);
    localparam MemoryEntryDataPath DATA_A = 64'h01234567_89abcdef;
    localparam MemoryEntryDataPath DATA_B = 64'hfedcba98_76543210;

    logic clk, rst;
    TestBenchClockGenerator #( .STEP(STEP) ) clkgen ( .rstOut(FALSE), .* );
    CacheSystemIF cacheSystemIF(clk, rst);

    PhyAddrPath memAccessAddr;
    MemoryEntryDataPath memAccessWriteData, memReadData;
    logic memAccessRE, memAccessWE, memAccessBusy, memReadDataReady;
    MemAccessSerial nextMemReadSerial, memReadSerial;
    MemWriteSerial nextMemWriteSerial;
    MemAccessResponse memAccessResponse;

    // Test the cache-side protocol and the memory model together, without a hex image.
    MemoryAccessController controller(
        .port(cacheSystemIF),
        .memAccessReadBusy(memAccessBusy), .memAccessWriteBusy(memAccessBusy), .*
    );
    Memory memory(.memAccessAddr(AddrPath'(memAccessAddr)), .*);

    MemAccessResult expectedReads[$];
    MemWriteSerial expectedWrites[$];
    int readCount = 0, writeCount = 0;
    int readResponses = 0, writeResponses = 0;

    // Responses have variable latency. Check every response, including duplicates.
    always @(posedge clk) begin
        #HOLD;
        if (!rst) begin
            assert (!$isunknown({cacheSystemIF.icMemAccessResult.valid,
                                 cacheSystemIF.dcMemAccessResult.valid,
                                 cacheSystemIF.dcMemAccessResponse.valid}))
                else $fatal(1, "Unknown response valid signal");
            if (cacheSystemIF.icMemAccessResult.valid || cacheSystemIF.dcMemAccessResult.valid) begin
                MemAccessResult expected;
                assert (expectedReads.size() != 0)
                    else $fatal(1, "Unexpected read response");
                expected = expectedReads.pop_front();
                // Both caches receive the same result and identify it by the assigned ID.
                assert (cacheSystemIF.icMemAccessResult === expected &&
                        cacheSystemIF.dcMemAccessResult === expected)
                    else $fatal(1, "Read response: expected ID %0d, data %h; I=%h, D=%h",
                                expected.serial, expected.data,
                                cacheSystemIF.icMemAccessResult, cacheSystemIF.dcMemAccessResult);
                readResponses++;
            end
            if (cacheSystemIF.dcMemAccessResponse.valid) begin
                MemWriteSerial expected;
                assert (expectedWrites.size() != 0)
                    else $fatal(1, "Unexpected write response");
                expected = expectedWrites.pop_front();
                assert (cacheSystemIF.dcMemAccessResponse.serial === expected)
                    else $fatal(1, "Write response: expected ID %0d, got %0d",
                                expected, cacheSystemIF.dcMemAccessResponse.serial);
                writeResponses++;
            end
        end
    end

    task Step(input MemReadAccessReq icReq, input MemAccessReq dcReq,
              input logic expectedIC_Ack, expectedDC_Ack,
              input MemoryEntryDataPath expectedReadData = '0);
        MemAccessSerial serial;
        @(negedge clk);
        cacheSystemIF.icMemAccessReq = icReq;
        cacheSystemIF.dcMemAccessReq = dcReq;
        #HOLD;
        assert (cacheSystemIF.icMemAccessReqAck.ack === expectedIC_Ack &&
                cacheSystemIF.dcMemAccessReqAck.ack === expectedDC_Ack)
            else $fatal(1, "Request ack: expected I=%b D=%b, got I=%b D=%b (busy=%b)",
                        expectedIC_Ack, expectedDC_Ack, cacheSystemIF.icMemAccessReqAck.ack,
                        cacheSystemIF.dcMemAccessReqAck.ack, memAccessBusy);
        if (expectedIC_Ack || (expectedDC_Ack && !dcReq.we)) begin
            serial = expectedIC_Ack ? cacheSystemIF.icMemAccessReqAck.serial :
                                      cacheSystemIF.dcMemAccessReqAck.serial;
            assert (serial === MemAccessSerial'(readCount))
                else $fatal(1, "Read request ID: expected %0d, got %0d", readCount, serial);
            expectedReads.push_back('{TRUE, MemAccessSerial'(readCount), expectedReadData});
            readCount++;
        end
        if (expectedDC_Ack && dcReq.we) begin
            assert (cacheSystemIF.dcMemAccessReqAck.wserial === MemWriteSerial'(writeCount))
                else $fatal(1, "Write request ID: expected %0d, got %0d",
                            writeCount, cacheSystemIF.dcMemAccessReqAck.wserial);
            expectedWrites.push_back(MemWriteSerial'(writeCount));
            writeCount++;
        end
        @(posedge clk);
        #HOLD;
    endtask

    task Drain;
        Step('0, '0, FALSE, FALSE);
        // Wait for all accepted requests, without assuming a fixed response latency.
        do begin
            @(negedge clk);
            #HOLD;
        end while (expectedReads.size() != 0 || expectedWrites.size() != 0 || memAccessBusy);
    endtask

    initial begin
        #(STEP * 2 * 500);
        $fatal(1, "Memory test timed out: reads %0d/%0d, writes %0d/%0d",
                    readResponses, readCount, writeResponses, writeCount);
    end

    initial begin
        cacheSystemIF.icMemAccessReq = '0;
        cacheSystemIF.dcMemAccessReq = '0;
        @(negedge rst);
        $display("========== Test Start ==========");

        // Write A, then hold both an I read and a D write while memory is busy.
        Step('0, '{TRUE, TRUE, ADDR_A, DATA_A}, FALSE, TRUE);
        repeat (MEMORY_WRITE_PROCESS_LATENCY)
            Step('{TRUE, ADDR_A}, '{TRUE, TRUE, ADDR_B, DATA_B}, FALSE, FALSE);
        // I wins arbitration; D must retry and receive its own write ID.
        Step('{TRUE, ADDR_A}, '{TRUE, TRUE, ADDR_B, DATA_B}, TRUE, FALSE, DATA_A);
        repeat (MEMORY_READ_PROCESS_LATENCY)
            Step('0, '{TRUE, TRUE, ADDR_B, DATA_B}, FALSE, FALSE);
        Step('0, '{TRUE, TRUE, ADDR_B, DATA_B}, FALSE, TRUE);
        Drain();

        // Read back a different address through the D-cache request port.
        Step('0, '{TRUE, FALSE, ADDR_B, '0}, FALSE, TRUE, DATA_B);
        Drain();

        // Two reads compete. Keep D pending until I has been accepted and busy clears.
        Step('{TRUE, ADDR_A}, '{TRUE, FALSE, ADDR_B, '0}, TRUE, FALSE, DATA_A);
        repeat (MEMORY_READ_PROCESS_LATENCY)
            Step('0, '{TRUE, FALSE, ADDR_B, '0}, FALSE, FALSE);
        Step('0, '{TRUE, FALSE, ADDR_B, '0}, FALSE, TRUE, DATA_B);
        Drain();

        // Invalid requests must not alter memory, even when their write flag is set.
        Step('{FALSE, ADDR_A}, '{FALSE, TRUE, ADDR_A, '1}, FALSE, FALSE);
        Step('0, '{TRUE, FALSE, ADDR_A, '0}, FALSE, TRUE, DATA_A);
        Drain();

        // Overwrite B with zero, then read it through I and verify A is unchanged.
        Step('0, '{TRUE, TRUE, ADDR_B, '0}, FALSE, TRUE);
        Drain();
        Step('{TRUE, ADDR_B}, '0, TRUE, FALSE, '0);
        Drain();
        Step('0, '{TRUE, FALSE, ADDR_A, '0}, FALSE, TRUE, DATA_A);
        Drain();

        // Leave enough idle cycles to catch a duplicate or a spurious response.
        repeat (MEM_LATENCY_SIM_LATENCY_FLUCTUATION_RANGE + MEMORY_READ_PIPELINE_DEPTH + 2)
            Step('0, '0, FALSE, FALSE);
        $display("========== Test Passed: %0d reads, %0d writes ==========",
                 readResponses, writeResponses);
        $finish;
    end
endmodule : TestMemory
