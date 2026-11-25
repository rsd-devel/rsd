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
        fetchStartOffset = ToFetchGroupOffset(pipeReg.pc);
        validByGroupOffset = {FETCH_WIDTH{pipeReg.valid}} << fetchStartOffset;
    end

    // Fetch speculates on BTB call/return types. Only an accepted group changes the stack.
    localparam RAS_ENTRY_NUM = 4;
    typedef logic [$clog2(RAS_ENTRY_NUM)-1:0] RAS_IndexPath;
    PC_Path ras[RAS_ENTRY_NUM];
    RAS_IndexPath rasPtr;
    logic [RAS_ENTRY_NUM-1:0] rasValid;
    logic pushRAS, popRAS;
    PC_Path returnPC;
    always_ff @(posedge port.clk) begin
        if (port.rst || recovery.fetchRedirect.valid || port.interruptAddrWE) begin
            // Ignore entries from the discarded path until the corresponding slots are written again.
            rasValid <= '0;
            rasPtr <= '0;
        end
        else if (pushRAS) begin
            ras[rasPtr + RAS_IndexPath'(1)] <= returnPC;
            rasPtr <= rasPtr + RAS_IndexPath'(1);
            rasValid[rasPtr + RAS_IndexPath'(1)] <= TRUE;
        end
        else if (popRAS) begin
            // Keep the entry on pop so deep returns can reuse targets on the next lap.
            rasPtr <= rasPtr - RAS_IndexPath'(1);
        end
    end

    PC_Path predictedTakenPC;
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
                    nextPredCtx.usedRAS = port.readBrType[groupOffset] == BTB_RETURN && rasValid[rasPtr];
                    predictedPC = nextPredCtx.usedRAS ? ras[rasPtr] : port.btbOut[groupOffset];
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
            nextPredCtx.btbBrType[groupOffset] = port.readBrType[groupOffset];
            nextPredCtx.btbHit[groupOffset] = port.btbHit[groupOffset];
            nextPredCtx.btbHitWay[groupOffset] = port.btbHitWay[groupOffset];
            nextPredCtx.phtPrevValue[groupOffset] = port.phtPrevValue[groupOffset];
        end


        fetchRequestHistory = regFetchRequestHistory;
        if (recovery.fetchRedirect.valid) begin
            fetchRequestPC = recovery.fetchRedirect.pc;
            if (recovery.fetchRedirect.restoreHistory)
                fetchRequestHistory = recovery.fetchRedirect.brHistory;
        end
        else begin
            fetchRequestPC = (regStall || !pipeReg.valid) ? regPC : predictedPC;
            // A held group contributes once, when its prediction is first saved.
            if ((|takenByGroupOffset) && !regStallFromCtrl && (stallFromCtrl || !ctrl.ifStage.clear))
                fetchRequestHistory = AdvanceTakenHistory(regFetchRequestHistory, predictedTakenPC);
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
            nextStage.brPred[fetchLane].usedRAS = responsePrediction.usedRAS && responsePrediction.takenByGroupOffset[groupOffset];
            nextStage.brPred[fetchLane].btbBrType = responsePrediction.btbBrType[groupOffset];
            nextStage.brPred[fetchLane].btbHit = responsePrediction.btbHit[groupOffset];
            nextStage.brPred[fetchLane].btbHitWay = responsePrediction.btbHitWay[groupOffset];
            nextStage.brPred[fetchLane].phtPrevValue = responsePrediction.phtPrevValue[groupOffset];
            nextStage.brPred[fetchLane].globalHistory = responsePrediction.globalHistory;
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
