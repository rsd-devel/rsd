// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import FetchUnitTypes::*;

module BTB(
    NextPCStageIF.BTB port,
    FetchStageIF.BTB next
);
    `RSD_STATIC_ASSERT(BTB_WAY_NUM == 2, "BTB replacement requires two ways.");

    // Pad each way to whole write-enable slices so updating one branch
    // preserves the other way without reading the set on the training port.
    localparam BYTE_NUM = ($bits(BTB_Entry) + 7) / 8;
    typedef logic [BYTE_NUM*8-1:0] WayPath;
    WayPath [BTB_WAY_NUM-1:0] readRow, writeRow;
    logic [BTB_WAY_NUM-1:0][BYTE_NUM-1:0] writeMask;
    BTB_SetIndexPath writeSet, resetIndex;
    PC_Path lookupPC;

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

    BlockDualPortMaskedRAM #(
        .ENTRY_NUM(BTB_SET_NUM > 1 ? BTB_SET_NUM : 2),
        .ENTRY_BIT_SIZE($bits(writeRow))
    ) btbEntryArray (
        .clk(port.clk), .we(writeMask), .wa(writeSet), .wv(writeRow),
        .ra(ToBTB_Set(port.fetchRequestPC)), .rv(readRow)
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
        lookupPC <= port.fetchRequestPC;
        if (port.rstStart)
            resetIndex <= '0;
        else if (port.rst)
            resetIndex <= BTB_SetIndexPath'((resetIndex + 1) % BTB_SET_NUM);
    end

    always_comb begin
        BTB_Tag lookupTag;
        BTB_Entry wayEntry[BTB_WAY_NUM];
        logic [BTB_WAY_NUM-1:0] blockHit;
        logic [FETCH_WIDTH-1:0] hitByOffset;
        lookupTag = ToBTB_Tag(lookupPC);
        hitByOffset = '0;
        for (int w = 0; w < BTB_WAY_NUM; w++) begin
            wayEntry[w] = BTB_Entry'(readRow[w]);
            blockHit[w] = wayEntry[w].tag.block == lookupTag.block;
            if (blockHit[w])
                hitByOffset[wayEntry[w].tag.offset] = TRUE;
        end

        // Each slot describes a fixed instruction position in the aligned group.
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            next.btbHit[i] = FALSE;
            next.btbHitWay[i] = '0;
            next.btbOut[i] = '0;
            next.readIsCondBr[i] = FALSE;
            if (hitByOffset[i]) begin
                next.btbHit[i] = TRUE;
                // A later way wins if two entries match both the block and the offset.
                for (int w = 0; w < BTB_WAY_NUM; w++) begin
                    if (blockHit[w] && wayEntry[w].tag.offset == BTB_OffsetPath'(i)) begin
                        next.btbHitWay[i] = BTB_WayIndexPath'(w);
                        next.btbOut[i] = ToRawAddrFromBTB_Addr(wayEntry[w].data, lookupPC);
                        next.readIsCondBr[i] = wayEntry[w].isCondBr;
                    end
                end
            end
        end
    end

    always_comb begin
        pushCount = '0;
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            queueIn[i].setIndex = ToBTB_Set(port.brResult[i].brAddr);
            queueIn[i].entry.tag = ToBTB_Tag(port.brResult[i].brAddr);
            queueIn[i].entry.data = ToBTB_Addr(port.brResult[i].nextAddr);
            queueIn[i].entry.isCondBr = port.brResult[i].isCondBr;
            queueIn[i].hit = port.brResult[i].btbHit;
            queueIn[i].hitWay = port.brResult[i].btbHitWay;
            queueWA[i] = tailPtr + BTBQueuePointerPath'(pushCount);
            // Drop training when full. Otherwise, draining one entry leaves room for up to two lanes.
            queueWE[i] = !port.rst && port.brResult[i].valid && port.brResult[i].execTaken &&
                         !port.brResult[i].btbTargetCorrect && count < BTB_QUEUE_SIZE;
            if (queueWE[i])
                pushCount++;
        end
    end

    always_comb begin
        Update update;
        update = queue[headPtr];
        writeEnable = !port.rst && count != 0;
        writeSet = port.rst ? resetIndex : update.setIndex;
        // A delayed hit may replace a newer occupant. Write its full tag and target together.
        writeWay = update.hit ? update.hitWay : victimWay;
        for (int w = 0; w < BTB_WAY_NUM; w++) begin
            writeMask[w] = {BYTE_NUM{port.rst || (writeEnable && writeWay == w)}};
            // A reset entry can match tag and offset zero, like any other partial-tag alias.
            writeRow[w] = port.rst ? '0 : WayPath'(update.entry);
        end
    end
endmodule : BTB
