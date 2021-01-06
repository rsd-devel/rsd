// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for updating PC
//

import BasicTypes::*;
import PipelineTypes::*;
import MemoryMapTypes::*;
import CacheSystemTypes::*;
import FetchUnitTypes::*;

//`define RSD_STOP_FETCH_ON_PRED_MISS

// Detect the cache line boundary in sequential access
function automatic logic StepOverCacheLine (PC_Path pc1, PC_Path pc2);
    return pc1[ICACHE_LINE_BYTE_NUM_BIT_WIDTH] != pc2[ICACHE_LINE_BYTE_NUM_BIT_WIDTH];
endfunction

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

    // デバッグ用SID
    // 内部事情により，1 からはじめる
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpSerial curSID, nextSID;
    FlipFlop#( .FF_WIDTH(OP_SERIAL_WIDTH), .RESET_VALUE(1) )
        sidFF(
            .out( curSID ),
            .in ( nextSID ),
            .clk( port.clk ),
            .rst( port.rst )
        );
`endif

    PC_Path predNextPC;
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
        port.pcWE = 
            (writePC_FromOuter || !stall || beginStall) && !port.rst;
    end


    //
    // Branch Prediction
    //
    always_comb begin

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
            // Use current PC
            predNextPC = port.pcOut;

            for (int i = 0; i < FETCH_WIDTH; i++) begin
                // Process of branch prediction:
                // If BTB is hit, the instruction is predicted to be a branch. 
                // In addition, if the branch is predicted as Taken, 
                // the address read from BTB is used as next PC.
                if (!regStall && next.fetchStageIsValid[i] && 
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
    always_comb begin

        // --- PC
        if (port.interruptAddrWE) begin
            // When an interrupt occurs, use interrupt address.
            // NOTE: This input can be a critical path.
            // Hence, interrupt address is input to PC first rather than 
            // input to the branch predictor directly.
            port.pcIn = port.interruptAddrIn;
        end
        else if (beginStall) begin
            // Update PC based on the branch prediction result accessed
            // immediately before the stall if it is beginning of stall.
            // (see the comment of regBrPred in FetchStage.sv)
            port.pcIn = predNextPC;
        end
        else begin
            // Increment PC
            port.pcIn = predNextPC + FETCH_WIDTH*INSN_BYTE_WIDTH;
            for (int i = 1; i < FETCH_WIDTH; i++) begin
                if (StepOverCacheLine(predNextPC, 
                                     predNextPC+i*INSN_BYTE_WIDTH)) begin
                    // When PC stepped over the border of cache line, stop there
                    port.pcIn = predNextPC+i*INSN_BYTE_WIDTH;
                    break;
                end
            end
        end

        for (int i = 0; i < FETCH_WIDTH; i++) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
            // Generate serial id for dumping
            nextStage[i].sid = curSID + i;
`endif
            nextStage[i].pc = predNextPC + i * INSN_BYTE_WIDTH;
            if (port.interruptAddrWE || clear ||
                StepOverCacheLine(predNextPC, nextStage[i].pc)) begin
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
    AddrPath fetchAddr;
    always_comb begin
        // Decide input address of I-cache
        if (next.fetchStageIsValid[0] && stall) begin
            // Use the PC of the IF stage
            fetchAddr = ToAddrFromPC(next.fetchStagePC[0]);
        end
        else begin
            // Use the PC of this stage
            fetchAddr = ToAddrFromPC(predNextPC);
        end
        
        // To I-cache
        port.icNextReadAddrIn = ToPhyAddrFromLogical(fetchAddr);
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
