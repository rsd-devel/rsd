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
    PC_Path regPC, pcIn;
    PC_Path predictedPC, fetchRequestPC;
    BranchGlobalHistoryPath regFetchRequestHistory, fetchRequestHistory;
    FetchStageRegPath nextPipeReg, pipeReg;
    PreDecodeStageRegPath nextStage;

    logic stall, clear;
    logic stallFromCtrl;
    logic regStall, regStallFromCtrl;
    logic beginStallFromCtrl;
    // Keep the selected branch and its group's training context while Fetch is held.
    // The selected target itself is already in regPC when the held group advances.
    typedef struct packed {
        logic [FETCH_WIDTH-1:0] takenByGroupOffset;
        BranchGlobalHistoryPath globalHistory;
        logic [FETCH_WIDTH-1:0] btbHit;
        BTB_WayIndexPath [FETCH_WIDTH-1:0] btbHitWay;
        PHT_EntryPath [FETCH_WIDTH-1:0] phtPrevValue;
    } FetchPrediction;
    FetchPrediction nextPredCtx, regPredCtx;
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            regStall <= FALSE;
            regStallFromCtrl <= FALSE;
        end
        else begin
            regStall <= stall;
            regStallFromCtrl <= stallFromCtrl;
        end

        if (port.rst) begin
            regPC <= PC_Path'(INSN_RESET_VECTOR);
            regFetchRequestHistory <= '0;
        end
        else begin
            regPC <= pcIn;
            regFetchRequestHistory <= fetchRequestHistory;
        end

        if (port.rst) begin
            pipeReg <= '0;
            regPredCtx <= '0;
        end
        else begin
            if (!stallFromCtrl)
                pipeReg <= nextPipeReg;
            // Save this group's prediction before the predictor advances during a stall.
            if (beginStallFromCtrl)
                regPredCtx <= nextPredCtx;
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
    end

    PC_Path predictedTakenPC;
    logic [FETCH_WIDTH-1:0] takenByGroupOffset;
    always_comb begin
        predictedPC = ToFetchGroupBase(regPC) + FETCH_GROUP_BYTE_NUM;
        takenByGroupOffset = '0;
        predictedTakenPC = '0;
        for (int groupOffset = 0; groupOffset < FETCH_WIDTH; groupOffset++) begin
            if (validByGroupOffset[groupOffset] && port.btbHit[groupOffset]) begin
                // A jump is taken regardless of the counter. Later offsets are off the predicted path.
                if (!port.readIsCondBr[groupOffset] || port.brPredTaken[groupOffset]) begin
                    predictedPC = port.btbOut[groupOffset];
                    predictedTakenPC = ToFetchGroupBase(pipeReg.pc) | PC_Path'(groupOffset << INSN_ADDR_BIT_WIDTH);
                    takenByGroupOffset[groupOffset] = TRUE;
                    break;
                end
            end
        end

        // IC ミスによるストール時のために，予測結果コンテキストを残しておく
        // この保存は IC ミス判定とは無関係に行われるため，予測の遅延が短縮される
        nextPredCtx.globalHistory = regFetchRequestHistory;
        nextPredCtx.takenByGroupOffset = takenByGroupOffset;
        for (int groupOffset = 0; groupOffset < FETCH_WIDTH; groupOffset++) begin
            nextPredCtx.btbHit[groupOffset] = port.btbHit[groupOffset];
            nextPredCtx.btbHitWay[groupOffset] = port.btbHitWay[groupOffset];
            nextPredCtx.phtPrevValue[groupOffset] = port.phtPrevValue[groupOffset];
        end


        if (recovery.toRecoveryPhase)
            fetchRequestPC = recovery.recoveredPC_FromRwCommit;
        else if (recovery.recoverFromRename)
            fetchRequestPC = recovery.recoveredPC_FromRename;
        else if (regStall || !pipeReg.valid)
            fetchRequestPC = regPC;
        else
            fetchRequestPC = predictedPC;

        // On stall entry the predictor advances once. regPredCtx keeps the
        // original group's history while the I-cache retries its lookup.
        fetchRequestHistory = regFetchRequestHistory;
        if ((|takenByGroupOffset) && !regStallFromCtrl && (stallFromCtrl || !ctrl.ifStage.clear))
            fetchRequestHistory = AdvanceTakenHistory(regFetchRequestHistory, predictedTakenPC);

        // Keep the existing RW recovery priority over the speculative update.
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            if (port.brResult[i].valid && port.brResult[i].mispred) begin
                fetchRequestHistory = port.brResult[i].globalHistory;
                if (port.brResult[i].execTaken)
                    fetchRequestHistory = AdvanceTakenHistory(port.brResult[i].globalHistory, port.brResult[i].brAddr);
            end
        end
        if (!USE_GSHARE)
            fetchRequestHistory = '0;

        port.fetchRequestPC = fetchRequestPC;
        port.fetchRequestHistory = fetchRequestHistory;

        if (port.interruptAddrWE)
            pcIn = port.interruptAddrIn;
        else
            pcIn = fetchRequestPC;
        // Interrupt entry samples the registered PC after the pipeline drains.
        port.pcOut = regPC;
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

    FetchPrediction responsePrediction;
    PC_Path responseTakenAddr;
    logic [FETCH_WIDTH-1:0] flushByGroupOffset, validByFetchLane, validThroughBranch;
    always_comb begin
        responsePrediction = regStallFromCtrl ? regPredCtx : nextPredCtx;
        responseTakenAddr = regStallFromCtrl ? regPC : predictedPC;
        flushByGroupOffset = '0;
        for (int i = 1; i < FETCH_WIDTH; i++)
            flushByGroupOffset[i] = flushByGroupOffset[i-1] || responsePrediction.takenByGroupOffset[i-1];
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
            nextStage.brPred[fetchLane].predTaken = responsePrediction.takenByGroupOffset[groupOffset];
            nextStage.brPred[fetchLane].takenAddr = responsePrediction.takenByGroupOffset[groupOffset] ? responseTakenAddr : '0;
            nextStage.brPred[fetchLane].takenAddrChangedAtDecode = FALSE;
            nextStage.brPred[fetchLane].btbHit = responsePrediction.btbHit[groupOffset];
            nextStage.brPred[fetchLane].btbHitWay = responsePrediction.btbHitWay[groupOffset];
            nextStage.brPred[fetchLane].phtPrevValue = responsePrediction.phtPrevValue[groupOffset];
            nextStage.brPred[fetchLane].globalHistory = responsePrediction.globalHistory;
            nextStage.insn[fetchLane] = validByFetchLane[fetchLane] ? port.icReadDataOut[fetchLane] : '0;
        end
        port.nextStage = nextStage;
    end

`ifndef RSD_SYNTHESIS
    PC_Path expectedHeldTarget;
    always_ff @(posedge port.clk) begin
        if (beginStallFromCtrl)
            expectedHeldTarget <= predictedPC;
        // A redirect can overwrite regPC while the held group is being discarded.
        if (regStallFromCtrl && (|nextStage.valid) && (|regPredCtx.takenByGroupOffset))
            assert (regPC == expectedHeldTarget)
                else $fatal(1, "Fetch advanced a held taken branch with a different target");
    end
`endif

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
