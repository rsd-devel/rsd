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
    localparam BANK_NUM = 2;
    localparam BANK_ENTRY_NUM = ROW_NUM / BANK_NUM;
    typedef logic [$clog2(BANK_ENTRY_NUM > 1 ? BANK_ENTRY_NUM : 2)-1:0] BankIndexPath;
    typedef logic [$clog2(ROW_NUM)-1:0] RowIndexPath;

    typedef PHT_EntryPath [FETCH_WIDTH-1:0] RowPath;
    RowPath readRow, trainingRow, writeRow, heldTrainingRow;
    RowPath bankRow[BANK_NUM];
    RowIndexPath readRowIndex, trainingRowIndex;
    BankIndexPath resetBankAddr;
    logic predictionBank, regPredictionBank, headBank;
    logic readTraining, writeEnable, regReadTraining;

    // Adjacent PHT rows occupy opposite banks. Fetch owns its bank every cycle.
    for (genvar b = 0; b < BANK_NUM; b++) begin : bank
        logic bankWE;
        BankIndexPath bankAddr;
        BlockSinglePortRAM #(
            .ENTRY_NUM(BANK_ENTRY_NUM), .ENTRY_BIT_SIZE($bits(RowPath))
        ) counterArray (
            .clk(port.clk), .we(bankWE), .rwa(bankAddr), .wv(writeRow), .rv(bankRow[b])
        );
        always_comb begin
            // Initialize both banks in parallel so the full table fits in the reset sequence.
            bankWE = port.rst || (writeEnable && headBank == b);
            if (port.rst)
                bankAddr = resetBankAddr;
            else if (predictionBank == b)
                bankAddr = BankIndexPath'(readRowIndex / BANK_NUM);
            else
                bankAddr = BankIndexPath'(trainingRowIndex / BANK_NUM);
        end
    end

    always_comb begin
        predictionBank = readRowIndex[0];
        readRow = bankRow[regPredictionBank];
    end

    always_ff @(posedge port.clk) begin
        regPredictionBank <= predictionBank;
        if (port.rstStart)
            resetBankAddr <= '0;
        else if (port.rst)
            resetBankAddr <= BankIndexPath'((resetBankAddr + 1) % BANK_ENTRY_NUM);
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
        logic taken;
    } UpdatePath;
    typedef logic [$clog2(PHT_QUEUE_SIZE)-1:0] QueuePointerPath;
    UpdatePath queueIn[INT_ISSUE_WIDTH], queue[PHT_QUEUE_SIZE], update;
    QueuePointerPath queueWA[INT_ISSUE_WIDTH], headPtr, tailPtr;
    logic queueWE[INT_ISSUE_WIDTH], rowReady;
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
            queueIn[i].taken = port.brResult[i].execTaken;

            // Drop arrivals when already full. On a read cycle a nearly full
            // FIFO may have room for only the first eligible issue lane.
            queueWA[i] = tailPtr + QueuePointerPath'(pushCount);
            queueWE[i] = !port.rst && count < PHT_QUEUE_SIZE &&
                         count + pushCount < PHT_QUEUE_SIZE + int'(writeEnable) &&
                         port.brResult[i].valid && port.brResult[i].isCondBr &&
                         // Skip reinforcement of a counter already saturated at prediction time.
                         (port.brResult[i].execTaken ? port.brResult[i].phtPrevValue != PHT_ENTRY_MAX
                                                     : port.brResult[i].phtPrevValue != '0);
            if (queueWE[i])
                pushCount++;
        end
    end

    // Keep the head until its bank has been free for both the read and the write.
    // Save the read result if a fetch takes the bank before the write can proceed.
    always_ff @(posedge port.clk) begin
        regReadTraining <= readTraining;
        if (regReadTraining)
            heldTrainingRow <= bankRow[headBank];
        if (port.rst || writeEnable)
            rowReady <= FALSE;
        else if (readTraining)
            rowReady <= TRUE;
    end

    always_comb begin
        update = queue[headPtr];
        trainingRowIndex = RowIndexPath'(update.index / FETCH_WIDTH);
        headBank = trainingRowIndex[0];
        readTraining = !port.rst && count != 0 && headBank != predictionBank && !rowReady;
        writeEnable = !port.rst && headBank != predictionBank && rowReady;
        trainingRow = regReadTraining ? bankRow[headBank] : heldTrainingRow;
        writeRow = trainingRow;
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            if (port.rst)
                writeRow[i] = PHT_EntryPath'(PHT_ENTRY_MAX / 2 + 1);
            else if (update.index % FETCH_WIDTH == i) begin
                if (update.taken && trainingRow[i] != PHT_ENTRY_MAX)
                    writeRow[i] = trainingRow[i] + 1'b1;
                else if (!update.taken && trainingRow[i] != 0)
                    writeRow[i] = trainingRow[i] - 1'b1;
            end
        end
    end

endmodule : Bimodal
