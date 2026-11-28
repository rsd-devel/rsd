// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Gshare Branch Predictor
//

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import FetchUnitTypes::*;

module Gshare(
    FetchStageIF.BranchPredictor port,
    ControllerIF.BranchPredictor ctrl
);

    `RSD_STATIC_ASSERT(PHT_ENTRY_NUM % FETCH_WIDTH == 0, "A PHT row must contain a whole fetch group.");
    `RSD_STATIC_ASSERT(PHT_ROW_NUM >= 2, "The PHT must contain at least two rows.");
    localparam BANK_NUM = 2;
    localparam BANK_ENTRY_NUM = PHT_ROW_NUM / BANK_NUM;
    typedef logic [$clog2(BANK_ENTRY_NUM > 1 ? BANK_ENTRY_NUM : 2)-1:0] BankIndexPath;

    typedef PHT_EntryPath [FETCH_WIDTH-1:0] RowPath;
    RowPath readRow, trainingRow, writeRow, heldTrainingRow;
    RowPath bankRow[BANK_NUM], regBankRow[BANK_NUM];
    PHT_RowIndexPath trainingRowIndex;
    BankIndexPath resetBankAddr;
    logic predictionBank, regPredictionBank, regRowBank, headBank;
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
        // Keep the raw counters before selecting the bank output.
        always_ff @(posedge port.clk) begin
            if (port.capturePredRows)
                regBankRow[b] <= bankRow[b];
        end
        always_comb begin
            // Initialize both banks in parallel so the full table fits in the reset sequence.
            bankWE = port.rst || (writeEnable && headBank == b);
            if (port.rst)
                bankAddr = resetBankAddr;
            else if (predictionBank == b)
                bankAddr = BankIndexPath'(port.phtReadRow / BANK_NUM);
            else
                bankAddr = BankIndexPath'(trainingRowIndex / BANK_NUM);
        end
    end

    always_comb begin
        predictionBank = port.phtReadRow[0];
        readRow = regBankRow[regRowBank];
    end

    always_ff @(posedge port.clk) begin
        regPredictionBank <= predictionBank;
        if (port.capturePredRows)
            regRowBank <= regPredictionBank;
        if (port.rstStart)
            resetBankAddr <= '0;
        else if (port.rst)
            resetBankAddr <= BankIndexPath'((resetBankAddr + 1) % BANK_ENTRY_NUM);
    end

    PHT_EntryPath counters[FETCH_WIDTH];
    logic brPredTaken[FETCH_WIDTH];
    always_comb begin
        // Each counter maps directly to its instruction offset in the fetch group.
        for (int groupOffset = 0; groupOffset < FETCH_WIDTH; groupOffset++) begin
            counters[groupOffset] = port.brLookupValid ? readRow[groupOffset] : '0;
            brPredTaken[groupOffset] = counters[groupOffset][PHT_ENTRY_WIDTH-1];
        end
        port.brPredTaken = brPredTaken;
        port.phtPrevValue = counters;
    end

    typedef struct packed {
        PHT_IndexPath index;
        logic taken;
    } UpdatePath;
    UpdatePath queueIn[INT_ISSUE_WIDTH], update;
    logic updateValid[INT_ISSUE_WIDTH], updatePending, rowReady;

    TrainingQueue #(
        .ENTRY_NUM(PHT_QUEUE_SIZE), .DATA_WIDTH($bits(UpdatePath)), .PUSH_WIDTH(INT_ISSUE_WIDTH)
    ) trainingQueue (
        .clk(port.clk), .rst(port.rst), .pushValid(updateValid), .pushData(queueIn),
        .pop(writeEnable), .headValid(updatePending), .headData(update)
    );

    always_comb begin
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            queueIn[i].index = ToPHT_TrainingIndex(port.brResult[i].brLookup.ctx, port.brResult[i].brAddr);
            queueIn[i].taken = port.brResult[i].execTaken;
            // Skip reinforcement of a counter already saturated at prediction time.
            updateValid[i] = port.brResult[i].valid && port.brResult[i].brLookup.valid &&
                             port.brResult[i].brType == BTB_COND &&
                             (port.brResult[i].btbHit || port.brResult[i].execTaken) &&
                             (port.brResult[i].execTaken ? port.brResult[i].phtPrevValue != PHT_ENTRY_MAX
                                                         : port.brResult[i].phtPrevValue != '0);
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
        trainingRowIndex = PHT_RowIndexPath'(update.index / FETCH_WIDTH);
        headBank = trainingRowIndex[0];
        readTraining = updatePending && headBank != predictionBank && !rowReady;
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

endmodule : Gshare
