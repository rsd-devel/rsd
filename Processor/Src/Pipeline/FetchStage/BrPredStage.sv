// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for updating PC
//

import BasicTypes::*;
import PipelineTypes::*;
import MemoryMapTypes::*;
import FetchUnitTypes::*;

module BrPredStage(
    BrPredStageIF.ThisStage port,
    FetchStageIF.BrPredStage next,
    RecoveryManagerIF.BrPredStage recovery,
    ControllerIF.BrPredStage ctrl,
    DebugIF.BrPredStage debug
);

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
    PC_Path pc, pcIn;
    PC_Path fallThroughPC, predictedPC, fetchRequestPC;
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
        stall = ctrl.bpStage.stall;
        clear = ctrl.bpStage.clear;

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
        // If no valid slot is predicted taken, advance to the next fetch group.
        fallThroughPC = ToFetchGroupBase(pc) + FETCH_GROUP_BYTE_NUM;
        predictedPC = fallThroughPC;
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            if (next.fetchSlotValid[i] && next.btbHit[i] && next.brPredTaken[i]) begin
                predictedPC = next.btbOut[i];
                break;
            end
        end
    end

    always_comb begin
        if (recovery.toRecoveryPhase) begin
            fetchRequestPC = recovery.recoveredPC_FromRwCommit;
        end
        else if (recovery.recoverFromRename) begin
            fetchRequestPC = recovery.recoveredPC_FromRename;
        end
        else if (regStall || !next.icRE) begin
            // Stall entry saved the pending request. An empty IF also starts at pc.
            fetchRequestPC = pc;
        end
        else begin
            fetchRequestPC = predictedPC;
        end
        port.fetchRequestPC = fetchRequestPC;
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
            pcIn = port.interruptAddrWE ? port.interruptAddrIn : fetchRequestPC;
        end
        // Interrupt entry samples the pending PC after the pipeline has drained.
        port.pcOut = pc;

        for (int i = 0; i < FETCH_WIDTH; i++) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
            // Generate serial id for dumping
            nextStage[i].sid = curSID + i;
`endif
            nextStage[i].pc = fetchRequestPC + i * INSN_BYTE_WIDTH;
            if (port.interruptAddrWE || clear ||
                int'(ToFetchGroupOffset(fetchRequestPC)) >= FETCH_WIDTH - i) begin
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
    always_comb begin
        // A stalled IF keeps reading the same cache set.
        if (next.icRE && stall) begin
            port.icNextReadAddrIn = next.icReadAddrIn;
        end
        else begin
            port.icNextReadAddrIn = ToAddrFromPC(fetchRequestPC);
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
            debug.bpReg[i].valid = stall ? FALSE : nextStage[i].valid;
            debug.bpReg[i].sid = nextStage[i].sid;
        end
    end
`endif

endmodule : BrPredStage
