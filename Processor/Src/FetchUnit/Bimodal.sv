// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Branch predictor -- 2bc.
//

import BasicTypes::*;
import MemoryMapTypes::*;
import FetchUnitTypes::*;

function automatic PHT_IndexPath ToPHT_Index_Local(PC_Path addr);
    return
        addr[
            PHT_ENTRY_NUM_BIT_WIDTH + INSN_ADDR_BIT_WIDTH - 1: 
            INSN_ADDR_BIT_WIDTH
        ];
endfunction

module Bimodal(
    NextPCStageIF.BranchPredictor port,
    FetchStageIF.BranchPredictor next
);

    PC_Path pcIn;

    logic brPredTaken;

    // PHT control logic
    logic phtWE[INT_ISSUE_WIDTH];
    PHT_IndexPath phtWA[INT_ISSUE_WIDTH];
    PHT_EntryPath phtWV[INT_ISSUE_WIDTH];
    PHT_EntryPath phtPrevValue[INT_ISSUE_WIDTH];

    // Read port need for branch predict and update counter.
    PHT_IndexPath phtRA[FETCH_WIDTH];
    PHT_EntryPath phtRV[FETCH_WIDTH];

    // assert when misprediction occured.
    logic mispred;

    logic pushPhtQueue, popPhtQueue;
    logic full, empty;

    PhtQueueEntry phtQueue[PHT_QUEUE_SIZE];
    PhtQueuePointerPath headPtr, tailPtr;

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
        if(port.rstStart) begin
            resetIndex <= 0;
        end
        else begin
            resetIndex <= resetIndex + 1;
        end
    end

    always_ff @(posedge port.clk) begin
        // Push Pht Queue
        if (port.rst) begin
            phtQueue[resetIndex % PHT_QUEUE_SIZE].phtWA <= '0;
            phtQueue[resetIndex % PHT_QUEUE_SIZE].phtWV <= PHT_ENTRY_MAX / 2 + 1;
        end
        else if (pushPhtQueue) begin
            phtQueue[headPtr].phtWA <= phtWA[INT_ISSUE_WIDTH-1];
            phtQueue[headPtr].phtWV <= phtWV[INT_ISSUE_WIDTH-1];
        end
    end


    always_comb begin
    
        pcIn = port.predNextPC;

        for (int i = 0; i < FETCH_WIDTH; i++) begin
            next.phtPrevValue[i] = phtRV[i];

            // Predict directions (Check the MSB).
            brPredTaken =
                phtRV[i][PHT_ENTRY_WIDTH - 1] && next.btbHit[i];
            next.brPredTaken[i] = brPredTaken;

            if (brPredTaken) begin
                // If brPred is taken, next instruction don't be executed.
                break;
            end
        end

        // Negate first. (to discard the result of previous cycle)
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            phtWE[i] = FALSE;
            updatePht = FALSE;
            pushPhtQueue = FALSE;
        end

        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            // When branch instruction is executed, update PHT.
            if (updatePht) begin
                pushPhtQueue = port.brResult[i].valid;
            end
            else begin
                phtWE[i] = port.brResult[i].valid;
                updatePht |= phtWE[i];
            end

            phtWA[i] = ToPHT_Index_Local(port.brResult[i].brAddr);

            mispred = port.brResult[i].mispred && port.brResult[i].valid;
            
            // Counter's value.
            phtPrevValue[i] = port.brResult[i].phtPrevValue; 
            
            // Update PHT's counter (saturated up/down counter).
            if (port.brResult[i].execTaken) begin
                phtWV[i] = (phtPrevValue[i] == PHT_ENTRY_MAX) ? 
                    PHT_ENTRY_MAX : phtPrevValue[i] + 1;
            end
            else begin
                phtWV[i] = (phtPrevValue[i] == 0) ? 
                    0 : phtPrevValue[i] - 1;
            end

            // When miss prediction is occured, recovory history.
            if (mispred) begin
                break;
            end
        end

        for (int i = 0; i < FETCH_WIDTH; i++) begin
            // Read PHT entry for next cycle (use PC).
            phtRA[i] = ToPHT_Index_Local(pcIn + i*INSN_BYTE_WIDTH);
        end


        // Pop PHT Queue
        if (!empty && !updatePht) begin
            popPhtQueue = TRUE;
            phtWE[0] = TRUE;
            phtWA[0] = phtQueue[tailPtr].phtWA;
            phtWV[0] = phtQueue[tailPtr].phtWV;
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


endmodule : Bimodal


