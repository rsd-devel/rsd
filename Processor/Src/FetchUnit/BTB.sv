// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import FetchUnitTypes::*;

module BTB(
    FetchStageIF.BTB port
);
    `RSD_STATIC_ASSERT(BTB_WAY_NUM == 2, "BTB replacement requires two ways.");

    // The entry table uses one synchronous 1RW RAM with byte write enables.
    // A lookup reads both ways. Byte-aligned ways let training update one
    // way in a single write while preserving the other.
    localparam BYTE_NUM = ($bits(BTB_Entry) + 7) / 8;
    typedef logic [BYTE_NUM*8-1:0] WayPath;
    WayPath [BTB_WAY_NUM-1:0] readRow, writeRow;
    logic [BTB_WAY_NUM-1:0][BYTE_NUM-1:0] writeMask;
    BTB_SetIndexPath arraySet, writeSet, resetIndex;

    typedef struct packed {
        BTB_SetIndexPath setIndex;
        BTB_Entry entry;
        logic hit;
        BTB_WayIndexPath hitWay;
    } Update;
    Update queueIn[INT_ISSUE_WIDTH], queue[BTB_QUEUE_SIZE];
    BTBQueuePointerPath queueWA[INT_ISSUE_WIDTH], headPtr, tailPtr;
    logic queueWE[INT_ISSUE_WIDTH];
    logic [$clog2(INT_ISSUE_WIDTH):0] pushCount;
    logic [BTB_QUEUE_SIZE_BIT_WIDTH:0] count;
    logic writeEnable;

    // A fetch miss allocates the way opposite the last write to this set.
    BTB_WayIndexPath victimWay, writeWay;

    DistributedDualPortRAM #(
        .ENTRY_NUM(BTB_SET_NUM > 1 ? BTB_SET_NUM : 2),
        .ENTRY_BIT_SIZE($bits(BTB_WayIndexPath))
    ) replacementWay (
        .clk(port.clk), .we(port.rst || writeEnable),
        .wa(writeSet), .wv(port.rst ? '0 : ~writeWay),
        .ra(writeSet), .rv(victimWay)
    );

    BlockSinglePortRAM #(
        .ENTRY_NUM(BTB_SET_NUM > 1 ? BTB_SET_NUM : 2),
        .ENTRY_BIT_SIZE($bits(writeRow)), .WRITE_SLICE_BIT_SIZE(8)
    ) btbEntryArray (
        .clk(port.clk), .we(writeMask), .rwa(arraySet), .wv(writeRow), .rv(readRow)
    );

    MultiWidthQueuePointer #(.SIZE(BTB_QUEUE_SIZE), .PUSH_WIDTH(INT_ISSUE_WIDTH)) btbQueuePointer (
        .clk(port.clk), .rst(port.rst), .push(pushCount != 0), .pushCount(pushCount),
        .pop(writeEnable), .popCount(1'b1), .headPtr(headPtr), .tailPtr(tailPtr), .count(count)
    );

    always_ff @(posedge port.clk) begin
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            if (queueWE[i])
                queue[queueWA[i]] <= queueIn[i];
        end
    end

    always_ff @(posedge port.clk) begin
        if (port.rstStart)
            resetIndex <= '0;
        else if (port.rst)
            resetIndex <= BTB_SetIndexPath'((resetIndex + 1) % BTB_SET_NUM);
    end

    BTB_Tag lookupTag;
    BTB_Entry wayEntry[BTB_WAY_NUM];
    logic [BTB_WAY_NUM-1:0] blockHit;
    logic [FETCH_WIDTH-1:0] hitByOffset;
    BTB_WayIndexPath hitWay[FETCH_WIDTH];
    PC_Path target[FETCH_WIDTH];
    BTB_BranchType brType[FETCH_WIDTH];
    always_comb begin
        lookupTag = ToBTB_Tag(port.pcOut);
        hitByOffset = '0;
        for (int w = 0; w < BTB_WAY_NUM; w++) begin
            wayEntry[w] = BTB_Entry'(readRow[w]);
            blockHit[w] = port.btbLookupValid && wayEntry[w].tag.block == lookupTag.block;
            if (blockHit[w])
                hitByOffset[wayEntry[w].tag.offset] = TRUE;
        end

        for (int groupOffset = 0; groupOffset < FETCH_WIDTH; groupOffset++) begin
            hitWay[groupOffset] = '0;
            target[groupOffset] = '0;
            brType[groupOffset] = BTB_JUMP;
            if (hitByOffset[groupOffset]) begin
                // A later way wins if two entries match both the block and the offset.
                for (int w = 0; w < BTB_WAY_NUM; w++) begin
                    if (blockHit[w] && wayEntry[w].tag.offset == BTB_OffsetPath'(groupOffset)) begin
                        hitWay[groupOffset] = BTB_WayIndexPath'(w);
                        target[groupOffset] = ToRawAddrFromBTB_Addr(wayEntry[w].data, port.pcOut);
                        brType[groupOffset] = wayEntry[w].brType;
                    end
                end
            end
            port.btbHit[groupOffset] = hitByOffset[groupOffset];
            port.btbHitWay[groupOffset] = hitWay[groupOffset];
            port.btbOut[groupOffset] = target[groupOffset];
            port.readBrType[groupOffset] = brType[groupOffset];
        end
    end

    always_comb begin
        pushCount = '0;
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            queueIn[i].setIndex = port.brResult[i].btbLookup.setIndex;
            queueIn[i].entry.tag = ToBTB_Tag(port.brResult[i].brAddr);
            queueIn[i].entry.data = ToBTB_Addr(port.brResult[i].nextAddr);
            queueIn[i].entry.brType = port.brResult[i].brType;
            queueIn[i].hit = port.brResult[i].btbHit;
            queueIn[i].hitWay = port.brResult[i].btbHitWay;
            queueWA[i] = tailPtr + BTBQueuePointerPath'(pushCount);
            // Earlier lanes take the available slots, including a slot freed by this write.
            queueWE[i] = !port.rst && port.brResult[i].valid && port.brResult[i].execTaken && port.brResult[i].btbLookup.valid &&
                         !port.brResult[i].btbEntryCorrect &&
                         count + pushCount < BTB_QUEUE_SIZE + int'(writeEnable);
            if (queueWE[i])
                pushCount++;
        end
    end

    Update update;
    always_comb begin
        update = queue[headPtr];
        writeEnable = !port.rst && port.btbUpdateAllowed && count != 0;
        writeSet = port.rst ? resetIndex : update.setIndex;
        arraySet = (port.rst || writeEnable) ? writeSet : port.btbReadSet;
        // A delayed hit may replace a newer occupant. Write its full tag and target together.
        writeWay = update.hit ? update.hitWay : victimWay;
        for (int w = 0; w < BTB_WAY_NUM; w++) begin
            writeMask[w] = {BYTE_NUM{port.rst || (writeEnable && writeWay == w)}};
            // A reset entry can match tag and offset zero, like any other partial-tag alias.
            writeRow[w] = port.rst ? '0 : WayPath'(update.entry);
        end
    end
endmodule : BTB
