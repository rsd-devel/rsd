// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

import BasicTypes::*;
import PipelineTypes::*;
import FetchUnitTypes::*;
import MemoryMapTypes::*;

module FetchStage(
    FetchStageIF.ThisStage port,
    RecoveryManagerIF.FetchStage recovery,
    ControllerIF.FetchStage ctrl,
    DebugIF.FetchStage debug,
    PerformanceCounterIF.FetchStage perfCounter
);
    PC_Path pc, pcIn;
    PC_Path predictedPC, fetchRequestPC;
    FetchStageRegPath nextPipeReg[FETCH_WIDTH], pipeReg[FETCH_WIDTH];
    PreDecodeStageRegPath nextStage[FETCH_WIDTH];

    logic stall, clear;
    logic stallFromCtrl;
    logic regStall, regStallFromCtrl;
    logic beginStallFromCtrl;
    BranchPred brPred[FETCH_WIDTH], regBrPred[FETCH_WIDTH];
    logic isFlushed[FETCH_WIDTH];
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            regStall <= FALSE;
            regStallFromCtrl <= FALSE;
        end
        else begin
            regStall <= stall;
            regStallFromCtrl <= stallFromCtrl;
        end

        if (port.rst)
            pc <= PC_Path'(INSN_RESET_VECTOR);
        else
            pc <= pcIn;

        if (port.rst) begin
            for (int i = 0; i < FETCH_WIDTH; i++) begin
                pipeReg[i] <= '0;
                regBrPred[i] <= '0;
            end
        end
        else begin
            if (!stallFromCtrl)
                pipeReg <= nextPipeReg;
            else begin
                for (int i = 0; i < FETCH_WIDTH; i++) begin
                    if (isFlushed[i])
                        pipeReg[i].valid <= FALSE;
                end
            end
            // Save this group's prediction before the predictor advances during a stall.
            if (beginStallFromCtrl)
                regBrPred <= brPred;
        end

    end

    always_comb begin
        // The controller holds the current response with stallFromCtrl. During
        // interrupt drain, only new fetches need to stall.
        stallFromCtrl = ctrl.ifStage.stall;
        stall = stallFromCtrl || ctrl.drainFetchForInterrupt;
        // Clearing only the response on a redirect lets the target request through.
        clear = port.rst || (stallFromCtrl && ctrl.ifStage.clear) || ctrl.drainFetchForInterrupt;
        beginStallFromCtrl = stallFromCtrl && !regStallFromCtrl;
    end


    logic icMiss;
    BTB_OffsetPath fetchStartOffset;
    logic [FETCH_WIDTH-1:0] validByFetchLane, validByGroupOffset;
    logic empty;
    always_comb begin
        empty = TRUE;
        for (int fetchLane = 0; fetchLane < FETCH_WIDTH; fetchLane++) begin
            validByFetchLane[fetchLane] = pipeReg[fetchLane].valid;
            if (pipeReg[fetchLane].valid)
                empty = FALSE;
        end

        icMiss = pipeReg[0].valid && !port.icReadHit[0];
        ctrl.ifStageSendBubbleLower = icMiss;
        ctrl.ifStageEmpty = empty;

        // Lane 0 starts at the fetch PC. Earlier instructions in the group are skipped.
        fetchStartOffset = ToFetchGroupOffset(pipeReg[0].pc);
        validByGroupOffset = validByFetchLane << fetchStartOffset;
        for (int groupOffset = 0; groupOffset < FETCH_WIDTH; groupOffset++)
            port.updateBrHistory[groupOffset] = !regStallFromCtrl && validByGroupOffset[groupOffset];
    end

    // Use the first predicted-taken branch among the valid group offsets.
    always_comb begin
        predictedPC = ToFetchGroupBase(pc) + FETCH_GROUP_BYTE_NUM;
        for (int groupOffset = 0; groupOffset < FETCH_WIDTH; groupOffset++) begin
            if (validByGroupOffset[groupOffset] && port.btbHit[groupOffset] && port.brPredTaken[groupOffset]) begin
                predictedPC = port.btbOut[groupOffset];
                break;
            end
        end

        if (recovery.toRecoveryPhase)
            fetchRequestPC = recovery.recoveredPC_FromRwCommit;
        else if (recovery.recoverFromRename)
            fetchRequestPC = recovery.recoveredPC_FromRename;
        else if (regStall || !pipeReg[0].valid)
            fetchRequestPC = pc;
        else
            fetchRequestPC = predictedPC;
        port.fetchRequestPC = fetchRequestPC;

        if (port.interruptAddrWE)
            pcIn = port.interruptAddrIn;
        else
            pcIn = fetchRequestPC;
        // Interrupt entry samples the registered PC after the pipeline drains.
        port.pcOut = pc;
    end

`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpSerial curSID, nextSID;
`endif
    PC_Path icNextReadPC;
    always_comb begin
        for (int i = 0; i < FETCH_WIDTH; i++) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextPipeReg[i].sid = curSID + i;
`endif
            nextPipeReg[i].pc = fetchRequestPC + i * INSN_BYTE_WIDTH;
            if (port.interruptAddrWE || clear ||
                int'(ToFetchGroupOffset(fetchRequestPC)) >= FETCH_WIDTH - i)
                nextPipeReg[i].valid = FALSE;
            else
                nextPipeReg[i].valid = TRUE;
        end

        // Repeat the current I-cache lookup while the request is stalled.
        if (pipeReg[0].valid && stall)
            icNextReadPC = pipeReg[0].pc;
        else
            icNextReadPC = fetchRequestPC;
        port.icRE = pipeReg[0].valid;
        port.icReadAddrIn = ToAddrFromPC(pipeReg[0].pc);
        port.icNextReadAddrIn = ToAddrFromPC(icNextReadPC);
    end

    always_comb begin
        // Match each I-cache lane to its predictor entry. Lanes that wrap are already invalid.
        for (int fetchLane = 0; fetchLane < FETCH_WIDTH; fetchLane++) begin
            BTB_OffsetPath groupOffset;
            groupOffset = BTB_OffsetPath'((fetchStartOffset + fetchLane) % FETCH_WIDTH);
            brPred[fetchLane].takenAddr = port.btbOut[groupOffset];
            brPred[fetchLane].btbHit = port.btbHit[groupOffset];
            brPred[fetchLane].btbHitWay = port.btbHitWay[groupOffset];
            brPred[fetchLane].takenAddrChangedAtDecode = FALSE;
            brPred[fetchLane].predTaken = port.brPredTaken[groupOffset];
            brPred[fetchLane].globalHistory = port.brGlobalHistory[groupOffset];
            brPred[fetchLane].phtPrevValue = port.phtPrevValue[groupOffset];
            isFlushed[fetchLane] = FALSE;
        end
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            if (!regStallFromCtrl && pipeReg[i].valid && brPred[i].predTaken) begin
                for (int j = i + 1; j < FETCH_WIDTH; j++)
                    isFlushed[j] = pipeReg[j].valid;
                break;
            end
        end

        for (int i = 0; i < FETCH_WIDTH; i++) begin
            if (stallFromCtrl || ctrl.ifStage.clear || port.rst || isFlushed[i])
                nextStage[i].valid = FALSE;
            else
                nextStage[i].valid = pipeReg[i].valid;
`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].sid = pipeReg[i].sid;
`endif
            nextStage[i].pc = pipeReg[i].pc;
            nextStage[i].brPred = regStallFromCtrl ? regBrPred[i] : brPred[i];
            nextStage[i].insn = pipeReg[i].valid ? port.icReadDataOut[i] : '0;
        end
        port.nextStage = nextStage;
    end


    // Performance counter
    logic icMissOnCtrlStallEntry;
    always_comb begin
        icMissOnCtrlStallEntry = icMiss && beginStallFromCtrl;
`ifndef RSD_DISABLE_PERFORMANCE_COUNTER
        perfCounter.icMiss = icMissOnCtrlStallEntry;
`endif
    end

`ifndef RSD_DISABLE_DEBUG_REGISTER
    always_ff @(posedge port.clk) begin
        if (port.rst)
            curSID <= 1;
        else
            curSID <= nextSID;
    end
    logic [FETCH_WIDTH:0] numValidInsns;
    always_comb begin
        numValidInsns = 0;
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            if (!nextPipeReg[i].valid)
                break;
            numValidInsns++;
        end
        nextSID = (stall || clear) ? curSID : curSID + numValidInsns;

        for (int i = 0; i < FETCH_WIDTH; i++) begin
            debug.ifReg[i].valid = pipeReg[i].valid;
            debug.ifReg[i].sid = pipeReg[i].sid;
            debug.ifReg[i].flush = isFlushed[i];
            debug.ifReg[i].icMiss = (i == 0) && icMissOnCtrlStallEntry;
        end
    end
`endif
endmodule : FetchStage
