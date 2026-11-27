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
    BranchLookupPath regBrLookup, nextBrLookup;
    logic refillPredRows, regRefillPredRows, advancePredRows;
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
        BranchLookupPath brLookup;
        logic [FETCH_WIDTH-1:0] btbHit;
        BTB_BranchType [FETCH_WIDTH-1:0] btbBrType;
        logic usedRAS;
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
            regBrLookup <= '0;
            regRefillPredRows <= FALSE;
        end
        else begin
            regPC <= pcIn;
            regFetchRequestHistory <= fetchRequestHistory;
            regBrLookup <= nextBrLookup;
            regRefillPredRows <= refillPredRows;
        end

        if (port.rst) begin
            pipeReg <= '0;
            regPredCtx <= '0;
        end
        else begin
            if (!stallFromCtrl || refillPredRows)
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
        // A held response uses regPredCtx. Interrupt drain issues no new
        // fetches, even when waiting on a branch that still needs training.
        port.btbUpdateAllowed = !recovery.fetchRedirect.valid &&
            ((regStallFromCtrl && stallFromCtrl) || ctrl.drainFetchForInterrupt);
    end

    logic icMiss;
    BTB_OffsetPath fetchStartOffset;
    logic [FETCH_WIDTH-1:0] validByGroupOffset;
    always_comb begin
        icMiss = pipeReg.valid && !port.icReadHit;
        ctrl.ifStageSendBubbleLower = icMiss;
        ctrl.ifStageEmpty = !pipeReg.valid;

        // The predictor uses fixed group offsets at or after the fetch PC.
        port.brLookupValid = regBrLookup.valid;
        fetchStartOffset = ToFetchGroupOffset(pipeReg.pc);
        validByGroupOffset = {FETCH_WIDTH{pipeReg.valid}} << fetchStartOffset;
    end

    // Fetch speculates on BTB call/return types. Only an accepted group changes the stack.
    PC_Path ras[RAS_ENTRY_NUM];
    RAS_IndexPath rasPtr, nextRAS_Ptr;
    logic pushRAS, popRAS, rasWE;
    PC_Path returnPC;
    always_ff @(posedge port.clk) begin
        rasPtr <= nextRAS_Ptr;
        if (port.rst) begin
            for (int i = 0; i < RAS_ENTRY_NUM; i++)
                ras[i] <= '0;
        end
        else if (rasWE)
            ras[nextRAS_Ptr] <= returnPC;
    end

    always_comb begin
        nextRAS_Ptr = rasPtr;
        rasWE = FALSE;
        if (port.rst)
            nextRAS_Ptr = '0;
        else if (recovery.fetchRedirect.valid || port.interruptAddrWE) begin
            // Cold redirects have no checkpoint. Preserve the circular stack as a prediction hint.
            if (recovery.fetchRedirect.restorePredCtx && recovery.fetchRedirect.valid && !port.interruptAddrWE)
                nextRAS_Ptr = recovery.fetchRedirect.predCtx.rasPtr;
        end
        else if (pushRAS) begin
            nextRAS_Ptr = rasPtr + RAS_IndexPath'(1);
            rasWE = TRUE;
        end
        else if (popRAS)
            nextRAS_Ptr = rasPtr - RAS_IndexPath'(1);
    end

    PC_Path predictedTakenPC;
    logic advanceHistory;
    logic [FETCH_WIDTH-1:0] takenByGroupOffset;
    always_comb begin
        predictedPC = ToFetchGroupBase(regPC) + FETCH_GROUP_BYTE_NUM;
        takenByGroupOffset = '0;
        predictedTakenPC = '0;
        nextPredCtx.usedRAS = FALSE;
        for (int groupOffset = 0; groupOffset < FETCH_WIDTH; groupOffset++) begin
            if (validByGroupOffset[groupOffset] && port.btbHit[groupOffset]) begin
                // A jump is taken regardless of the counter. Later offsets are off the predicted path.
                if (port.readBrType[groupOffset] != BTB_COND || port.brPredTaken[groupOffset]) begin
                    // A return can select the current stack top in the same cycle as the BTB target.
                    nextPredCtx.usedRAS = port.readBrType[groupOffset] == BTB_RETURN;
                    predictedPC = nextPredCtx.usedRAS ? ras[rasPtr] : port.btbOut[groupOffset];
                    predictedTakenPC = ToFetchGroupBase(pipeReg.pc) | PC_Path'(groupOffset << INSN_ADDR_BIT_WIDTH);
                    takenByGroupOffset[groupOffset] = TRUE;
                    break;
                end
            end
        end

        // IC ミスによるストール時のために，予測結果コンテキストを残しておく
        // この保存は IC ミス判定とは無関係に行われるため，予測の遅延が短縮される
        nextPredCtx.brLookup = regBrLookup;
        // The first group after a cold redirect has history but no predecessor rows.
        if (!regBrLookup.valid)
            nextPredCtx.brLookup.ctx = MakeBranchHistoryContext('0, regFetchRequestHistory, FALSE);
        nextPredCtx.takenByGroupOffset = takenByGroupOffset;
        for (int groupOffset = 0; groupOffset < FETCH_WIDTH; groupOffset++) begin
            nextPredCtx.btbBrType[groupOffset] = port.readBrType[groupOffset];
            nextPredCtx.btbHit[groupOffset] = port.btbHit[groupOffset];
            nextPredCtx.btbHitWay[groupOffset] = port.btbHitWay[groupOffset];
            nextPredCtx.phtPrevValue[groupOffset] = port.phtPrevValue[groupOffset];
        end


        advanceHistory = (|takenByGroupOffset) && !regStallFromCtrl && (stallFromCtrl || !ctrl.ifStage.clear);
        fetchRequestHistory = regFetchRequestHistory;
        if (recovery.fetchRedirect.valid) begin
            fetchRequestPC = recovery.fetchRedirect.pc;
            if (recovery.fetchRedirect.restorePredCtx)
                fetchRequestHistory = BranchContextHistory(recovery.fetchRedirect.predCtx.ctx);
        end
        else begin
            fetchRequestPC = (regStall || !pipeReg.valid) ? regPC : predictedPC;
            // A held group contributes once, when its prediction is first saved.
            if (advanceHistory)
                fetchRequestHistory = AdvanceTakenHistory(regFetchRequestHistory, predictedTakenPC);
        end
        if (!USE_GSHARE)
            fetchRequestHistory = '0;

        if (port.interruptAddrWE)
            pcIn = port.interruptAddrIn;
        else
            pcIn = fetchRequestPC;
        // Interrupt entry samples the registered PC after the pipeline drains.
        port.pcOut = regPC;
    end

    // Read the BTB and PHT for A while the preceding rows and regPC select B.
    // Capture A's candidates with B at the edge and start both reads for B.
    always_comb begin
        refillPredRows = !port.interruptAddrWE && recovery.fetchRedirect.valid && recovery.fetchRedirect.restorePredCtx;
        port.btbReadSet = refillPredRows ? BranchContextBTB_Set(recovery.fetchRedirect.predCtx.ctx) : ToBTB_Set(pcIn);
        port.phtReadRow = refillPredRows ? BranchContextPHT_Row(recovery.fetchRedirect.predCtx.ctx) :
                                           ToPHT_Row(pcIn, fetchRequestHistory);
        advancePredRows = regRefillPredRows || (!regStall && pipeReg.valid);
        port.capturePredRows = advancePredRows && !recovery.fetchRedirect.valid && !port.interruptAddrWE;

        nextBrLookup = regBrLookup;
        if (refillPredRows) begin
            // The predecessor row is ready one edge after a warm redirect.
            nextBrLookup = '{valid: FALSE, ctx: recovery.fetchRedirect.predCtx.ctx};
        end
        else if (port.interruptAddrWE || recovery.fetchRedirect.valid)
            nextBrLookup = '0;
        else if (regRefillPredRows)
            nextBrLookup.valid = TRUE;
        else if (advancePredRows)
            nextBrLookup = '{
                valid: TRUE,
                ctx: MakeBranchHistoryContext(advanceHistory ? predictedTakenPC : regPC,
                                              regFetchRequestHistory, advanceHistory)
            };
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
        nextPipeReg.valid = !port.interruptAddrWE && !clear && !refillPredRows;

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
            nextStage.brPred[fetchLane].usedRAS = responsePrediction.usedRAS && responsePrediction.takenByGroupOffset[groupOffset];
            nextStage.brPred[fetchLane].btbBrType = responsePrediction.btbBrType[groupOffset];
            nextStage.brPred[fetchLane].brLookup = responsePrediction.brLookup;
            nextStage.brPred[fetchLane].btbHit = responsePrediction.btbHit[groupOffset];
            nextStage.brPred[fetchLane].btbHitWay = responsePrediction.btbHitWay[groupOffset];
            nextStage.brPred[fetchLane].phtPrevValue = responsePrediction.phtPrevValue[groupOffset];
            // The fetched group updates the stack only when it advances, even after a stall.
            nextStage.brPred[fetchLane].rasPtr = rasPtr;
            nextStage.insn[fetchLane] = validByFetchLane[fetchLane] ? port.icReadDataOut[fetchLane] : '0;
        end
        port.nextStage = nextStage;
    end

    always_comb begin
        pushRAS = FALSE;
        popRAS = FALSE;
        returnPC = '0;
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            // A held I-cache response carries its original prediction until it advances.
            if (nextStage.valid[i] && nextStage.brPred[i].predTaken) begin
                pushRAS = nextStage.brPred[i].btbBrType == BTB_CALL;
                popRAS = nextStage.brPred[i].btbBrType inside {BTB_RETURN, BTB_RETURN_OFFSET};
                returnPC = pipeReg.pc + PC_Path'((i + 1) * INSN_BYTE_WIDTH);
            end
        end
    end

`ifndef RSD_SYNTHESIS
    PC_Path expectedHeldTarget;
    always_ff @(posedge port.clk) begin
        // Check the compact checkpoint against the history actually used to fetch this group.
        if (!port.rst && USE_GSHARE && (|nextStage.valid) && !regStallFromCtrl)
            assert (BranchContextHistory(nextStage.brPred[0].brLookup.ctx) == regFetchRequestHistory)
                else $fatal(1, "Fetch checkpoint disagrees with the request history");
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
