// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Branch predictor -- 2bc.
//

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import FetchUnitTypes::*;

module Bimodal(
    FetchStageIF.BranchPredictor port
);

    localparam ROW_NUM = PHT_ENTRY_NUM / FETCH_WIDTH;
    `RSD_STATIC_ASSERT(PHT_ENTRY_NUM % FETCH_WIDTH == 0, "A PHT row must contain a whole fetch group.");
    `RSD_STATIC_ASSERT(ROW_NUM >= 2, "The PHT must contain at least two rows.");
    typedef logic [$clog2(ROW_NUM)-1:0] RowIndexPath;

    // One byte per counter gives each position its own block RAM write enable.
    BytePath [FETCH_WIDTH-1:0] readRow, writeRow;
    logic [FETCH_WIDTH-1:0] writeMask;
    RowIndexPath readRowIndex, writeRowIndex, resetRow;
    BlockDualPortMaskedRAM #(
        .ENTRY_NUM(ROW_NUM), .ENTRY_BIT_SIZE($bits(readRow))
    ) counterArray (
        .clk(port.clk), .we(writeMask), .wa(writeRowIndex), .wv(writeRow),
        .ra(readRowIndex), .rv(readRow)
    );

    always_ff @(posedge port.clk) begin
        if (port.rstStart)
            resetRow <= '0;
        else if (port.rst)
            resetRow <= RowIndexPath'((resetRow + 1) % ROW_NUM);
    end


    function automatic PHT_IndexPath ToPHT_Index(PC_Path pc);
        return PHT_IndexPath'(pc >> INSN_ADDR_BIT_WIDTH);
    endfunction
    PHT_EntryPath counters[FETCH_WIDTH];
    always_comb begin
        readRowIndex = RowIndexPath'(ToPHT_Index(port.fetchRequestPC) / FETCH_WIDTH);

        for (int groupOffset = 0; groupOffset < FETCH_WIDTH; groupOffset++) begin
            counters[groupOffset] = PHT_EntryPath'(readRow[groupOffset]);
            port.brPredTaken[groupOffset] = counters[groupOffset][PHT_ENTRY_WIDTH-1];
        end
        port.phtPrevValue = counters;
        port.brGlobalHistory = '0;
    end

    typedef struct packed {
        PHT_IndexPath index;
        PHT_EntryPath value;
    } UpdatePath;
    typedef logic [$clog2(PHT_QUEUE_SIZE)-1:0] QueuePointerPath;
    UpdatePath queueIn[INT_ISSUE_WIDTH], queue[PHT_QUEUE_SIZE], update;
    QueuePointerPath queueWA[INT_ISSUE_WIDTH], headPtr, tailPtr;
    logic queueWE[INT_ISSUE_WIDTH], writeEnable;
    logic [$clog2(INT_ISSUE_WIDTH):0] pushCount;
    logic [$clog2(PHT_QUEUE_SIZE):0] count;

    MultiWidthQueuePointer #(.SIZE(PHT_QUEUE_SIZE), .PUSH_WIDTH(INT_ISSUE_WIDTH)) queuePointer (
        .clk(port.clk), .rst(port.rst), .push(pushCount != 0), .pushCount(pushCount),
        .pop(writeEnable), .popCount(1'b1), .headPtr(headPtr), .tailPtr(tailPtr), .count(count)
    );

    always_ff @(posedge port.clk) begin
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            if (queueWE[i])
                queue[queueWA[i]] <= queueIn[i];
        end
    end

    always_comb begin
        pushCount = '0;
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            queueIn[i].index = ToPHT_Index(port.brResult[i].brAddr);
            queueIn[i].value = port.brResult[i].phtPrevValue;
            if (port.brResult[i].execTaken && port.brResult[i].phtPrevValue != PHT_ENTRY_MAX)
                queueIn[i].value = port.brResult[i].phtPrevValue + 1'b1;
            else if (!port.brResult[i].execTaken && port.brResult[i].phtPrevValue != 0)
                queueIn[i].value = port.brResult[i].phtPrevValue - 1'b1;

            // As in the BTB, a full queue drops new training. Otherwise its
            // simultaneous drain leaves space for both integer issue lanes.
            queueWA[i] = tailPtr + QueuePointerPath'(pushCount);
            queueWE[i] = !port.rst && count < PHT_QUEUE_SIZE &&
                         port.brResult[i].valid && port.brResult[i].isCondBr;
            if (queueWE[i])
                pushCount++;
        end
    end

    always_comb begin
        update = queue[headPtr];
        writeEnable = !port.rst && count != 0;
        writeRowIndex = port.rst ? resetRow : RowIndexPath'(update.index / FETCH_WIDTH);
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            writeMask[i] = port.rst || (writeEnable && update.index % FETCH_WIDTH == i);
            writeRow[i] = port.rst ? BytePath'(PHT_ENTRY_MAX / 2 + 1) : BytePath'(update.value);
        end
    end

endmodule : Bimodal
