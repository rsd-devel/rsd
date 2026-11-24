// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for updating PC
//

import BasicTypes::*;
import PipelineTypes::*;
import MemoryMapTypes::*;
import FetchUnitTypes::*;

//`define RSD_STOP_FETCH_ON_PRED_MISS

module NextPCStage(
    NextPCStageIF.ThisStage port,
    FetchStageIF.NextPCStage next,
    RecoveryManagerIF.NextPCStage recovery,
    ControllerIF.NextPCStage ctrl,
    DebugIF.NextPCStage debug
);

`ifdef RSD_STOP_FETCH_ON_PRED_MISS
    typedef enum logic {
        PHASE_FETCH,
        PHASE_WAIT
    } Phase;

    parameter PHASE_DELAY = 2;
    Phase phase[PHASE_DELAY];
    Phase nextPhase;
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < PHASE_DELAY; i++) begin
                phase[i] <= PHASE_FETCH;
            end
        end
        else if (recovery.toRecoveryPhase || recovery.toCommitPhase) begin
            for (int i = 0; i < PHASE_DELAY; i++) begin
                phase[i] <= PHASE_FETCH;
            end
        end
        else begin
            for (int i = 0; i < PHASE_DELAY - 1; i++) begin
                phase[i+1] <= phase[i];
            end
            phase[0] <= nextPhase;
        end
    end

    always_comb begin
        if (recovery.toRecoveryPhase) begin
            nextPhase = PHASE_FETCH;
        end
        else begin

            nextPhase = phase[0];
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                if (port.brResult[i].valid && port.brResult[i].mispred) begin
                    nextPhase = PHASE_WAIT;
                end
            end
        end
    end
`endif

`ifndef RSD_DISABLE_DEBUG_REGISTER
    // Debug serial IDs start at one.
    OpSerial curSID, nextSID;
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            curSID <= 1;
        end
        else begin
            curSID <= nextSID;
        end
    end
`endif

    logic pcWE;
    PC_Path pc, pcIn, sequentialPC, predNextPC;
    FetchStageRegPath nextStage[ FETCH_WIDTH ];

    // Pipeline Control
    logic stall, clear;
    logic regStall, beginStall;
    logic writePC_FromOuter;
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            regStall <= FALSE;
        end
        else begin
            regStall <= stall;
        end
    end

    always_comb begin
        // Control
        stall = ctrl.npStage.stall;
        clear = ctrl.npStage.clear;
`ifdef RSD_STOP_FETCH_ON_PRED_MISS
        ctrl.npStageSendBubbleLower =
            (!recovery.toRecoveryPhase && phase[PHASE_DELAY - 1] == PHASE_WAIT);
`else
        ctrl.npStageSendBubbleLower = FALSE;
`endif

        beginStall = !regStall && stall;

        // Whether PC is written from outside
        if (recovery.toRecoveryPhase || recovery.recoverFromRename
                                     || port.interruptAddrWE) begin
            writePC_FromOuter = TRUE;
        end
        else begin
            writePC_FromOuter = FALSE;
        end
        
        // Update PC if not stalled.
        // NOTE: Update even during stall in the next cases:
        //   1) if PC is written from outside
        //   2) if it is beginning of stall
        //   (see the comment of regBrPred in FetchStage.sv)
        pcWE = writePC_FromOuter || !stall || beginStall;
    end


    //
    // Branch Prediction
    //
    always_comb begin
        // Form the fall-through from the registered request in parallel with prediction.
        sequentialPC = ToFetchGroupBase(pc) + FETCH_GROUP_BYTE_NUM;

        // Decide the address to input to the branch predictor
        if (recovery.toRecoveryPhase) begin
            // Branch misprediction or an exception etc. is detected
            // Refetch instruction specified by Rw, Cm stage
            predNextPC = recovery.recoveredPC_FromRwCommit;
        end
        else if (recovery.recoverFromRename) begin
            // Detect branch misprediction in decode stage
            predNextPC = recovery.recoveredPC_FromRename;
        end
        else begin
            // IF holds a valid group when icRE is set. After a stall, pc holds
            // the pending request; after reset or interrupt entry, IF is empty.
            predNextPC = (!regStall && next.icRE) ? sequentialPC : pc;

            for (int i = 0; i < FETCH_WIDTH; i++) begin
                // Process of branch prediction:
                // If BTB is hit, the instruction is predicted to be a branch. 
                // In addition, if the branch is predicted as Taken, 
                // the address read from BTB is used as next PC.
                if (!regStall && next.fetchSlotValid[i] &&
                        next.btbHit[i] && next.brPredTaken[i]) begin
                    // Use PC from BTB
                    predNextPC = next.btbOut[i];
                    break;
                end
            end
        end
        // To Branch predictor
        port.predNextPC = predNextPC;
    end


    //
    //  Updating PC
    //
    always_ff @(posedge port.clk) begin
        pc <= pcIn;
    end

    always_comb begin
        pcIn = pc;
        if (port.rst) begin
            pcIn = PC_Path'(INSN_RESET_VECTOR);
        end
        else if (pcWE) begin
            // Register the interrupt vector before it reaches the predictor.
            pcIn = port.interruptAddrWE ? port.interruptAddrIn : predNextPC;
        end
        // Interrupt entry samples the pending PC after the pipeline has drained.
        port.pcOut = pc;

        for (int i = 0; i < FETCH_WIDTH; i++) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
            // Generate serial id for dumping
            nextStage[i].sid = curSID + i;
`endif
            nextStage[i].pc = predNextPC + i * INSN_BYTE_WIDTH;
            if (port.interruptAddrWE || clear ||
                int'(ToFetchGroupOffset(predNextPC)) >= FETCH_WIDTH - i) begin
                nextStage[i].valid = FALSE;
            end
            else begin
                nextStage[i].valid = TRUE;
            end
        end

        port.nextStage = nextStage;
    end


    //
    // I-cache Access
    //
    PhyAddrPath predNextPhyAddr;
    always_comb begin
        // Translate both candidates before selection so the late stall signal
        // does not feed the address-range decoding.
        predNextPhyAddr = ToPhyAddrFromLogical(ToAddrFromPC(predNextPC));

        // Decide input address of I-cache
        if (next.icRE && stall) begin
            // Use the PC of the IF stage
            port.icNextReadAddrIn = next.icReadAddrIn;
        end
        else begin
            // Use the PC of this stage
            port.icNextReadAddrIn = predNextPhyAddr;
        end
    end


`ifndef RSD_DISABLE_DEBUG_REGISTER
    logic [FETCH_WIDTH : 0] numValidInsns;
    always_comb begin
        numValidInsns = 0; // Count valid instructions in this stage
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            if (!nextStage[i].valid) begin
                break;
            end
            else begin
                numValidInsns++;
            end
        end

        // Update serial ID.
        nextSID = ( stall || clear) ? 
            curSID : (curSID + numValidInsns);

        // --- Debug Register
        for ( int i = 0; i < FETCH_WIDTH; i++ ) begin
            debug.npReg[i].valid = stall ? FALSE : nextStage[i].valid;
            debug.npReg[i].sid = nextStage[i].sid;
        end
    end
`endif

endmodule : NextPCStage
