// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Gshare Branch Predictor
//

import BasicTypes::*;
import MemoryMapTypes::*;
import FetchUnitTypes::*;

function automatic PHT_IndexPath ToPHT_Index_Global(AddrPath addr, BranchGlobalHistoryPath gh);
    PHT_IndexPath phtIndex;
    phtIndex =
        addr[
            PHT_ENTRY_NUM_BIT_WIDTH + INSN_ADDR_BIT_WIDTH - 1: 
            INSN_ADDR_BIT_WIDTH
        ];
    phtIndex[PHT_ENTRY_NUM_BIT_WIDTH - 1 : PHT_ENTRY_NUM_BIT_WIDTH - BRANCH_GLOBAL_HISTORY_BIT_WIDTH] ^= gh;
    return phtIndex;
endfunction

module Gshare(
    NextPCStageIF.BranchPredictor port,
    FetchStageIF.BranchPredictor fetch,
    ControllerIF.BranchPredictor ctrl
);

    logic stall, clear;
    PC_Path pcIn;

    // Use combinational logic
    logic brPredTaken[FETCH_WIDTH];
    logic updateHistory[FETCH_WIDTH];

    // Logic for read/write PHT
    logic phtWE[INT_ISSUE_WIDTH];
    PHT_IndexPath phtWA[INT_ISSUE_WIDTH];
    PHT_EntryPath phtWV[INT_ISSUE_WIDTH];
    PHT_EntryPath phtPrevValue[INT_ISSUE_WIDTH];

    // Read port need for branch predict and update counter.
    PHT_IndexPath phtRA[FETCH_WIDTH];
    PHT_EntryPath phtRV[FETCH_WIDTH];

    // Branch history for using predict.
    BranchGlobalHistoryPath nextBrGlobalHistory, regBrGlobalHistory;
    BranchGlobalHistoryPath brGlobalHistory [ FETCH_WIDTH ];

    // assert when misprediction occured.
    logic hasMispred, regHasMispred;

    logic pushPhtQueue, popPhtQueue;
    logic full, empty;

    // Queue for multibank pht
    PhtQueueEntry phtQueue[PHT_QUEUE_SIZE];
    PhtQueuePointerPath headPtr, tailPtr;

    // Check for write number in 1cycle.
    logic updatePht;

    // the body of PHT.
    generate
        BlockMultiBankRAM #(
            .ENTRY_NUM( PHT_ENTRY_NUM ),
            .ENTRY_BIT_SIZE( $bits( PHT_EntryPath ) ),
            .READ_NUM( FETCH_WIDTH ),
            .WRITE_NUM( INT_ISSUE_WIDTH )
        )
        pht( 
            .clk(port.clk),
            .we(phtWE),
            .wa(phtWA),
            .wv(phtWV),
            .ra(phtRA),
            .rv(phtRV)
        );
        
        QueuePointer #(
            .SIZE( PHT_QUEUE_SIZE )
        )
        phtQueuePointer(
            .clk(port.clk),
            .rst(port.rst),
            .push(pushPhtQueue),
            .pop(popPhtQueue),
            .full(full),
            .empty(empty),
            .headPtr(headPtr),
            .tailPtr(tailPtr)    
        );
    endgenerate
    
    
    // Counter for reset sequence.
    PHT_IndexPath resetIndex;
    always_ff @(posedge port.clk) begin
        if (port.rstStart) begin
            resetIndex <= 0;
        end
        else begin
            resetIndex <= resetIndex + 1;
        end
    end

    always_ff @(posedge port.clk) begin
        // update Branch Global History.
        if (port.rst) begin
            regBrGlobalHistory <= '0;
            regHasMispred <= '0;
        end
        else begin
            regBrGlobalHistory <= nextBrGlobalHistory;
            regHasMispred <= hasMispred;
        end

        // Push Pht Queue
        if (pushPhtQueue) begin
            phtQueue[tailPtr].phtWA <= phtWA[INT_ISSUE_WIDTH-1];
            phtQueue[tailPtr].phtWV <= phtWV[INT_ISSUE_WIDTH-1];
        end
    end


    always_comb begin

        stall = ctrl.ifStage.stall;
        clear = ctrl.ifStage.clear;
    
        pcIn = port.predNextPC;

        nextBrGlobalHistory = regBrGlobalHistory;

        for (int i = 0; i < FETCH_WIDTH; i++) begin
            brPredTaken[i] = FALSE;
            // Output global history to pipeline for recovery.
            brGlobalHistory[i] = regBrGlobalHistory;
            updateHistory[i] = FALSE;
        end

        for (int i = 0; i < FETCH_WIDTH; i++) begin
            // Predict directions (Check the MSB).
            brPredTaken[i] = fetch.btbHit[i] && 
                (phtRV[i][PHT_ENTRY_WIDTH - 1] || !fetch.readIsCondBr[i]);

            // Assert BTB is hit, ICache line is valid, and conditional branch.
            updateHistory[i] = fetch.btbHit[i] && fetch.readIsCondBr[i] && 
                fetch.updateBrHistory[i] && !regHasMispred;

            // Generate next brGlobalHistory.
            if (updateHistory[i]) begin
                // Shift history 1 bit to the left and reflect prediction direction in LSB.
                nextBrGlobalHistory = 
                    (nextBrGlobalHistory << 1) | brPredTaken[i];
                
                if (brPredTaken[i]) begin
                    // If brPred is taken, next instruction don't be executed.
                    break;
                end
            end
            if (fetch.btbHit[i]) begin
                break;
            end
        end
        
        fetch.phtPrevValue = phtRV;
        fetch.brPredTaken = brPredTaken;
        fetch.brGlobalHistory = brGlobalHistory;

        // Discard the result of previous cycle
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            phtWE[i] = FALSE;
            phtWV[i] = '0;
            // Counter's value.
            phtPrevValue[i] = port.brResult[i].phtPrevValue; 
            phtWA[i] = ToPHT_Index_Global(
                port.brResult[i].brAddr,
                port.brResult[i].globalHistory
            );
        end

        if (port.recoverBrHistory) begin
            nextBrGlobalHistory = port.recoveredBrHistory;
        end


        updatePht = FALSE;
        pushPhtQueue = FALSE;
        hasMispred = FALSE;

        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            // When branch instruction is executed, update PHT.
            if (updatePht) begin
                pushPhtQueue = port.brResult[i].valid;
            end
            else begin
                phtWE[i] = port.brResult[i].valid;
                updatePht |= phtWE[i];
            end

            if (port.brResult[i].mispred && port.brResult[i].valid) begin
                hasMispred = TRUE;
            end

            // Update PHT's counter (saturated up/down counter).
            if (port.brResult[i].execTaken) begin
                phtWV[i] = (phtPrevValue[i] == PHT_ENTRY_MAX) ? 
                    PHT_ENTRY_MAX : phtPrevValue[i] + 1;
            end
            else begin
                phtWV[i] = (phtPrevValue[i] == 0) ? 
                    0 : phtPrevValue[i] - 1;
            end
        end

        for (int i = 0; i < FETCH_WIDTH; i++) begin
            // Read PHT entry for next cycle (use PC ^ brGlobalHistory).
            phtRA[i] = ToPHT_Index_Global(
                pcIn + i*INSN_BYTE_WIDTH,
                nextBrGlobalHistory
            );
        end

        // Pop PHT Queue
        if (!empty && !updatePht) begin
            popPhtQueue = TRUE;
            phtWE[0] = TRUE;
            phtWA[0] = phtQueue[headPtr].phtWA;
            phtWV[0] = phtQueue[headPtr].phtWV;
        end 
        else begin
            popPhtQueue = FALSE;
        end

        // In reset sequence, the write port 0 is used for initializing, and 
        // the other write ports are disabled.
        if (port.rst) begin
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                phtWE[i] = (i == 0) ? TRUE : FALSE;
                phtWA[i] = resetIndex;
                phtWV[i] = PHT_ENTRY_MAX / 2 + 1;
            end

            // To avoid writing to the same bank (avoid error message)
            for (int i = 0; i < FETCH_WIDTH; i++) begin
                phtRA[i] = i;
            end

            pushPhtQueue = FALSE;
            popPhtQueue = FALSE;
        end
    end

endmodule : Gshare
