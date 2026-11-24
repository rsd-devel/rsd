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
    FetchStageRegPath nextPipeReg, pipeReg;
    PreDecodeStageRegPath nextStage;

    logic stall, clear;
    logic stallFromCtrl;
    logic regStall, regStallFromCtrl;
    logic beginStallFromCtrl;
    // Both predictions are indexed by offset in the aligned fetch group.
    BranchPred liveBrPred[FETCH_WIDTH], regBrPred[FETCH_WIDTH];
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
            pipeReg <= '0;
            for (int i = 0; i < FETCH_WIDTH; i++)
                regBrPred[i] <= '0;
        end
        else begin
            if (!stallFromCtrl)
                pipeReg <= nextPipeReg;
            // Save this group's prediction before the predictor advances during a stall.
            if (beginStallFromCtrl)
                regBrPred <= liveBrPred;
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
    logic [FETCH_WIDTH-1:0] validByGroupOffset;
    always_comb begin
        icMiss = pipeReg.valid && !port.icReadHit;
        ctrl.ifStageSendBubbleLower = icMiss;
        ctrl.ifStageEmpty = !pipeReg.valid;

        // The predictor uses fixed group offsets at or after the fetch PC.
        fetchStartOffset = ToFetchGroupOffset(pipeReg.pc);
        validByGroupOffset = {FETCH_WIDTH{pipeReg.valid}} << fetchStartOffset;
        for (int groupOffset = 0; groupOffset < FETCH_WIDTH; groupOffset++)
            port.updateBrHistory[groupOffset] = !regStallFromCtrl && validByGroupOffset[groupOffset];
    end

    BranchPred brPred[FETCH_WIDTH];
    logic [FETCH_WIDTH-1:0] flushByGroupOffset;
    always_comb begin
        for (int groupOffset = 0; groupOffset < FETCH_WIDTH; groupOffset++) begin
            liveBrPred[groupOffset].takenAddr = port.btbOut[groupOffset];
            liveBrPred[groupOffset].btbHit = port.btbHit[groupOffset];
            liveBrPred[groupOffset].btbHitWay = port.btbHitWay[groupOffset];
            liveBrPred[groupOffset].takenAddrChangedAtDecode = FALSE;
            liveBrPred[groupOffset].predTaken = port.brPredTaken[groupOffset];
            liveBrPred[groupOffset].globalHistory = port.brGlobalHistory[groupOffset];
            liveBrPred[groupOffset].phtPrevValue = port.phtPrevValue[groupOffset];
            brPred[groupOffset] = regStallFromCtrl ? regBrPred[groupOffset] : liveBrPred[groupOffset];
        end

        predictedPC = ToFetchGroupBase(pc) + FETCH_GROUP_BYTE_NUM;
        flushByGroupOffset = '0;
        // The first predicted-taken branch supplies the target and discards all later offsets.
        for (int groupOffset = 0; groupOffset < FETCH_WIDTH; groupOffset++) begin
            if (validByGroupOffset[groupOffset] && brPred[groupOffset].predTaken) begin
                predictedPC = brPred[groupOffset].takenAddr;
                flushByGroupOffset = {FETCH_WIDTH{TRUE}} << (groupOffset + 1);
                break;
            end
        end

        if (recovery.toRecoveryPhase)
            fetchRequestPC = recovery.recoveredPC_FromRwCommit;
        else if (recovery.recoverFromRename)
            fetchRequestPC = recovery.recoveredPC_FromRename;
        else if (regStall || !pipeReg.valid)
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
        nextPipeReg.pc = fetchRequestPC;
`ifndef RSD_DISABLE_DEBUG_REGISTER
        nextPipeReg.sid = curSID;
`endif
        nextPipeReg.valid = !port.interruptAddrWE && !clear;

        // Repeat the current I-cache lookup while the request is stalled.
        if (pipeReg.valid && stall)
            icNextReadPC = pipeReg.pc;
        else
            icNextReadPC = fetchRequestPC;
        port.icRE = pipeReg.valid;
        port.icReadAddrIn = ToAddrFromPC(pipeReg.pc);
        port.icNextReadAddrIn = ToAddrFromPC(icNextReadPC);
    end

    logic [FETCH_WIDTH-1:0] validByFetchLane, validThroughBranch;
    always_comb begin
        validThroughBranch = (validByGroupOffset & ~flushByGroupOffset) >> fetchStartOffset;
        // A fresh response shows flushed lanes for one cycle. A held response has already discarded them.
        validByFetchLane = regStallFromCtrl ? validThroughBranch : (validByGroupOffset >> fetchStartOffset);

        nextStage.pc = pipeReg.pc;
`ifndef RSD_DISABLE_DEBUG_REGISTER
        nextStage.sid = pipeReg.sid;
`endif
        if (stallFromCtrl || ctrl.ifStage.clear || port.rst)
            nextStage.valid = '0;
        else
            nextStage.valid = validThroughBranch;
        for (int fetchLane = 0; fetchLane < FETCH_WIDTH; fetchLane++) begin
            BTB_OffsetPath groupOffset;
            groupOffset = BTB_OffsetPath'((fetchStartOffset + fetchLane) % FETCH_WIDTH);
            nextStage.brPred[fetchLane] = brPred[groupOffset];
            nextStage.insn[fetchLane] = validByFetchLane[fetchLane] ? port.icReadDataOut[fetchLane] : '0;
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
    always_comb begin
        nextSID = curSID;
        if (!stall && nextPipeReg.valid)
            nextSID = curSID + OpSerial'(FETCH_WIDTH - int'(ToFetchGroupOffset(fetchRequestPC)));

        for (int i = 0; i < FETCH_WIDTH; i++) begin
            debug.ifReg[i].valid = validByFetchLane[i];
            debug.ifReg[i].sid = pipeReg.sid + OpSerial'(i);
            debug.ifReg[i].flush = validByFetchLane[i] && !validThroughBranch[i];
            debug.ifReg[i].icMiss = (i == 0) && icMissOnCtrlStallEntry;
        end
    end
`endif
endmodule : FetchStage
