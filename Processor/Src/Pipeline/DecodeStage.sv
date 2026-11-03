// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// DecodeStage
//

import BasicTypes::*;
import MemoryMapTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import PipelineTypes::*;
import DebugTypes::*;
import FetchUnitTypes::*;

//
// Pick micro ops for feeding to a next stage from all decoded micro ops.
//
module MicroOpPicker(
input
    AllDecodedMicroOpPath req,
    AllDecodedMicroOpPath serialize,
output
    logic picked[DECODE_WIDTH],
    AllDecodedMicroOpIndex pickedIndex[DECODE_WIDTH],
    AllDecodedMicroOpPath next
);
    logic clear;
    logic sent;
    AllDecodedMicroOpPath cur;

    always_comb begin
        clear = FALSE;
        sent = FALSE;
        cur = req;

        for (int i = 0; i < DECODE_WIDTH; i++) begin
            picked[i] = FALSE;
            pickedIndex[i] = 0;
            for (int mn = 0; mn < ALL_DECODED_MICRO_OP_WIDTH; mn++) begin
                if (cur[mn] && !clear) begin
                    // シリアライズが有効な場合，1 mop のみ次のステージに送る
                    // If this op is serialized one, only a single op is picked.
                    if (serialize[mn]) begin
                        clear = TRUE;
                    end
                    // 既に通常命令を送っている場合，このシリアライズ命令はピックしない
                    if (clear && sent) begin
                        break;
                    end

                    sent = TRUE;
                    picked[i] = TRUE;
                    pickedIndex[i] = mn;
                    cur[mn] = FALSE;
                    break;
                end
            end
            
        end
        
        next = cur;
    end
endmodule



module DecodeStage(
    DecodeStageIF.ThisStage port, 
    PreDecodeStageIF.NextStage prev,
    ControllerIF.DecodeStage ctrl,
    DebugIF.DecodeStage debug,
    PerformanceCounterIF.DecodeStage perfCounter
);
    // --- Pipeline registers
    DecodeStageRegPath pipeReg[DECODE_WIDTH];
    
`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif

    always_ff@ (posedge port.clk)
    begin
        if (port.rst) begin
            for (int i = 0; i < DECODE_WIDTH; i++) begin
                pipeReg[i].valid <= FALSE;
            end
        end
        else if (!ctrl.idStage.stall) begin             // write data
            pipeReg <= prev.nextStage;
        end
    end

    // Control
    logic initiate;
    logic complete;

    // ELP
    ELP_State_Type lastELP, prevELP;

    always_ff@ (posedge port.clk)
    begin
        if (port.rst) begin
            prevELP <= LP_NOT_EXPECTED;
        end
        else begin
            if (port.setELP_OnInterrupt || port.recoverELP) begin
                prevELP <= port.setELP_OnInterrupt ? LP_NOT_EXPECTED : port.recoveredELP;
            end
            else begin
                // Keep the bundle's incoming ELP while its decoded ops are stalled.
                if (complete && !(ctrl.idStage.stall && !ctrl.stallByDecodeStage) &&
                    !ctrl.idStage.clear) begin
                    prevELP <= lastELP;
                end
            end
        end
    end

    always_comb begin
        port.elpState = prevELP;
    end

    // Pipeline control
    logic stall, clear;
    logic empty;
    RenameStageRegPath nextStage[DECODE_WIDTH];
    
    // Micro-op decoder
    OpInfo [ALL_DECODED_MICRO_OP_WIDTH-1:0] originalMicroOps;
    InsnInfo [DECODE_WIDTH-1:0] originalInsnInfo;
    OpInfo [ALL_DECODED_MICRO_OP_WIDTH-1:0] checkedMicroOps;
    InsnInfo [DECODE_WIDTH-1:0] checkedInsnInfo;
    OpInfo [ALL_DECODED_MICRO_OP_WIDTH-1:0] microOps;  // Decoded micro ops
    InsnInfo [DECODE_WIDTH-1:0] insnInfo;   // Whether a decoded instruction is branch or not.
    ELP_State_Type [ALL_DECODED_MICRO_OP_WIDTH-1:0] elps;

    always_comb begin
        empty = TRUE;
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            if (pipeReg[i].valid)
                empty = FALSE;
        end
        ctrl.idStageEmpty = empty;
    end

    
    // Early branch misprediction detection.
    RISCV_ISF_Common [DECODE_WIDTH-1:0] isfIn;
    logic stallBranchResolver;
    logic insnValidIn[DECODE_WIDTH];
    BranchPred [DECODE_WIDTH-1:0] brPredIn;
    PC_Path pcIn[DECODE_WIDTH];

    logic insnValidOut[DECODE_WIDTH];
    logic insnFlushed[DECODE_WIDTH];
    logic insnFlushTriggering[DECODE_WIDTH];
    logic flushTriggered;
    BranchPred brPredOut[DECODE_WIDTH];
    PC_Path recoveredPC;

    always_comb begin
        stallBranchResolver = ctrl.idStage.stall && !ctrl.stallByDecodeStage;
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            insnValidIn[i] = pipeReg[i].valid;
            isfIn[i] = pipeReg[i].insn;
            pcIn[i] = pipeReg[i].pc;
            brPredIn[i] = pipeReg[i].brPred;
        end
    end

    DecodedBranchResolver decodeStageBranchResolver(
        .clk(port.clk),
        .rst(port.rst),
        .stall(stallBranchResolver),
        .decodeComplete(complete),
        .insnValidIn(insnValidIn),
        .isf(isfIn),
        .brPredIn(brPredIn),
        .pc(pcIn),
        .insnInfo(insnInfo),
        .insnValidOut(insnValidOut),
        .insnFlushed(insnFlushed),
        .insnFlushTriggering(insnFlushTriggering),
        .flushTriggered(flushTriggered),
        .brPredOut(brPredOut),
        .recoveredPC(recoveredPC)
    );
    
    always_comb begin
        port.nextFlush = complete && flushTriggered && !clear;
        port.nextRecoveredPC = recoveredPC;
    end
    
    AllDecodedMicroOpPath remainingValidMOps;
    AllDecodedMicroOpPath nextValidMOps;

    AllDecodedMicroOpPath curValidMOps;
    AllDecodedMicroOpPath pickedValidMOps;
    AllDecodedMicroOpPath serializedMOps;
    
    AllDecodedMicroOpIndex mopPickedIndex[DECODE_WIDTH];
    logic mopPicked[DECODE_WIDTH];
    DecodeLaneIndexPath orgPickedInsnLane;


    always_ff@( posedge port.clk ) begin
        if (port.rst || ctrl.idStage.clear) begin
            remainingValidMOps <= 0;
            initiate <= TRUE;
        end
        else begin
            if (!(ctrl.idStage.stall && !ctrl.stallByDecodeStage)) begin
                initiate <= complete;
                remainingValidMOps <= nextValidMOps;
            end
        end
    end
    
    // From the index of decoded micro ops lanes to that of instructions.
    function automatic DecodeLaneIndexPath ToInsnLane(AllDecodedMicroOpIndex mopLane);
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            for (int j = 0; j < MICRO_OP_MAX_NUM; j++) begin
                if(mopLane == i*MICRO_OP_MAX_NUM + j)
                    return i;
            end
        end
        return 0;
    endfunction
    
    logic currentSerializeNextInsn, nextSerializeNextInsn;

    always_ff@ (posedge port.clk)
    begin
        if (port.rst) begin
            currentSerializeNextInsn <= FALSE;
        end
        else begin
            if (port.serializeNextInsn) begin
                currentSerializeNextInsn <= TRUE;
            end
            else if (complete && !stallBranchResolver) begin
                currentSerializeNextInsn <= nextSerializeNextInsn;
            end
        end
    end

    always_comb begin
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            for (int j = 0; j < MICRO_OP_MAX_NUM; j++) begin
                originalMicroOps[i*MICRO_OP_MAX_NUM + j] = pipeReg[i].microOps[j];
            end
            originalInsnInfo[i] = pipeReg[i].insnInfo;
        end
        
        //
        // Setup current valid bits(=un-decoded bits).
        //
        if (initiate) begin
            for (int i = 0; i < ALL_DECODED_MICRO_OP_WIDTH; i++) begin
                curValidMOps[i] = originalMicroOps[i].valid;
            end
        end
        else begin
            curValidMOps = remainingValidMOps;
        end

        CheckLandingPad(
            .insnValidIn(insnValidIn),
            .microOps(originalMicroOps),
            .insnInfo(originalInsnInfo),
            .prevELP(prevELP),
            .modifiedMicroOps(checkedMicroOps),
            .modifiedInsnInfo(checkedInsnInfo),
            .elps(elps)
        );

        ProcessSerializeNextInsn(
            .insnValidIn(insnValidIn),
            .microOps(checkedMicroOps),
            .insnInfo(checkedInsnInfo),
            .currentSerializeNextInsn(currentSerializeNextInsn),
            .modifiedMicroOps(microOps),
            .modifiedInsnInfo(insnInfo),
            .nextSerializeNextInsn(nextSerializeNextInsn)
        );

        // Set a "serialized" flag for each micro op.
        for (int i = 0; i < ALL_DECODED_MICRO_OP_WIDTH; i++) begin
            serializedMOps[i] = microOps[i].serialized;
        end
    end

    // serialize next microOp
    function automatic void ProcessSerializeNextInsn(
        input logic insnValidIn[DECODE_WIDTH],
        input OpInfo [ALL_DECODED_MICRO_OP_WIDTH-1:0] microOps,
        input InsnInfo [DECODE_WIDTH-1:0] insnInfo,
        input logic currentSerializeNextInsn,
        output OpInfo [ALL_DECODED_MICRO_OP_WIDTH-1:0] modifiedMicroOps,
        output InsnInfo [DECODE_WIDTH-1:0] modifiedInsnInfo,
        output logic nextSerializeNextInsn
    );
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            modifiedInsnInfo[i] = insnInfo[i];
        end
        for (int i = 0; i < ALL_DECODED_MICRO_OP_WIDTH; i++) begin
            modifiedMicroOps[i] = microOps[i];
        end

        nextSerializeNextInsn = currentSerializeNextInsn;
        for (int i = 0; i < ALL_DECODED_MICRO_OP_WIDTH; i++) begin
            if (insnValidIn[ToInsnLane(i)] && microOps[i].valid && nextSerializeNextInsn) begin
                modifiedInsnInfo[ToInsnLane(i)].isSerialized = TRUE;
                modifiedMicroOps[i].serialized = TRUE;
                nextSerializeNextInsn = FALSE;
            end
        end
    endfunction

    function automatic void CheckLandingPad(
        input logic insnValidIn[DECODE_WIDTH],
        input OpInfo [ALL_DECODED_MICRO_OP_WIDTH-1:0] microOps,
        input InsnInfo [DECODE_WIDTH-1:0] insnInfo,
        input ELP_State_Type prevELP,
        output OpInfo [ALL_DECODED_MICRO_OP_WIDTH-1:0] modifiedMicroOps,
        output InsnInfo [DECODE_WIDTH-1:0] modifiedInsnInfo,
        output ELP_State_Type [ALL_DECODED_MICRO_OP_WIDTH-1:0] elps
    );
        ELP_State_Type currentELP;

        modifiedInsnInfo = insnInfo;
        modifiedMicroOps = microOps;
        currentELP = prevELP;
        for (int i = 0; i < ALL_DECODED_MICRO_OP_WIDTH; i++) begin
            elps[i] = currentELP;
            if (insnValidIn[ToInsnLane(i)] && microOps[i].valid) begin
                if (currentELP == LP_EXPECTED &&
                    !(microOps[i].mopType == MOP_TYPE_INT && microOps[i].mopSubType.intType == INT_MOP_TYPE_LPL_CHECK) &&
                    !(microOps[i].mopType == MOP_TYPE_MEM && microOps[i].mopSubType.memType == MEM_MOP_TYPE_ENV &&
                      microOps[i].operand.systemOp.envCode == ENV_INSN_VIOLATION)
                ) begin
                    // Instruction access faults take priority over a landing pad fault.
                    modifiedInsnInfo[ToInsnLane(i)].writePC = FALSE;
                    modifiedInsnInfo[ToInsnLane(i)].isCall = FALSE;
                    modifiedInsnInfo[ToInsnLane(i)].isReturn = FALSE;
                    modifiedInsnInfo[ToInsnLane(i)].isRelBranch = FALSE;
                    modifiedInsnInfo[ToInsnLane(i)].isSerialized = TRUE;

                    modifiedMicroOps[i] = '0;
                    modifiedMicroOps[i].mopType = MOP_TYPE_MEM;
                    modifiedMicroOps[i].mopSubType.memType = MEM_MOP_TYPE_ENV;
                    modifiedMicroOps[i].operand.systemOp.isEnv = TRUE;
                    modifiedMicroOps[i].operand.systemOp.envCode = ENV_LPAD_FAIL;
                    modifiedMicroOps[i].opTypeA = OOT_IMM;
                    modifiedMicroOps[i].opTypeB = OOT_IMM;
`ifdef RSD_MARCH_FP_PIPE
                    modifiedMicroOps[i].opTypeC = OOT_IMM;
`endif
                    modifiedMicroOps[i].cond = COND_AL;
                    modifiedMicroOps[i].valid = TRUE;
                    modifiedMicroOps[i].serialized = TRUE;
                    modifiedMicroOps[i].nextELP = LP_NOT_EXPECTED;
                    modifiedMicroOps[i].mid = microOps[i].mid;
                    modifiedMicroOps[i].split = microOps[i].split;
                    modifiedMicroOps[i].last = microOps[i].last;
                end
                currentELP = modifiedMicroOps[i].nextELP;
            end
        end
    endfunction

    always_comb begin
        // The resolver can discard a suffix after an earlier branch or serialized op.
        // Keep this separate from checking, whose InsnInfo feeds the resolver.
        lastELP = prevELP;
        for (int i = 0; i < ALL_DECODED_MICRO_OP_WIDTH; i++) begin
            if (insnValidOut[ToInsnLane(i)] && microOps[i].valid) begin
                lastELP = microOps[i].nextELP;
            end
        end
    end

    MicroOpPicker picker(curValidMOps, serializedMOps, mopPicked, mopPickedIndex, pickedValidMOps);

    always_comb begin
        // --- The picker picks micro ops

        // Set picked results.
        nextValidMOps = pickedValidMOps;
        
        complete = TRUE;
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            for (int j = 0; j < MICRO_OP_MAX_NUM; j++) begin
                if(nextValidMOps[i*MICRO_OP_MAX_NUM+j] && insnValidIn[i]) begin
                    complete = FALSE;
                end
            end
            // "complete" does not care "insnValidOut" because "insnValidOut" is in
            // a critical path.
            if(!insnValidOut[i]) begin
                for (int j = 0; j < MICRO_OP_MAX_NUM; j++) begin
                    nextValidMOps[i*MICRO_OP_MAX_NUM + j] = FALSE;
                end
            end
        end

        // Stall decision
        ctrl.idStageStallUpper = !complete;
        // After idStageStallUpper is received, the Controller returns stall/clear signals.
        stall = ctrl.idStage.stall;
        clear = ctrl.idStage.clear;
        
        
        // Pick decoded micro ops.
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            orgPickedInsnLane = ToInsnLane(mopPickedIndex[i]);
        
            nextStage[i].opInfo = microOps[ mopPickedIndex[i] ];

            nextStage[i].valid = insnValidOut[orgPickedInsnLane] && mopPicked[i] && !clear;
            nextStage[i].pc = pipeReg[orgPickedInsnLane].pc;
            nextStage[i].bPred = brPredOut[orgPickedInsnLane];  
            nextStage[i].elp = elps[ mopPickedIndex[i] ];
            nextStage[i].nextELP = microOps[ mopPickedIndex[i] ].nextELP;

`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].opId.sid = pipeReg[orgPickedInsnLane].sid;
            nextStage[i].opId.mid = nextStage[i].opInfo.mid;
`endif
        end
        
        
        port.nextStage = nextStage;

`ifndef RSD_DISABLE_PERFORMANCE_COUNTER
        perfCounter.branchPredMissDetectedOnDecode = complete && flushTriggered && !clear;
`endif
        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            // 先頭が次に送られたら，デコード元は消える．
            debug.idReg[i].valid = pipeReg[i].valid;
            debug.idReg[i].flushed = insnFlushed[i];
            debug.idReg[i].flushTriggering = insnFlushTriggering[i];

            for (int j = 0; j < MICRO_OP_MAX_NUM; j++) begin
                if(microOps[i*MICRO_OP_MAX_NUM + j].valid && microOps[i*MICRO_OP_MAX_NUM + j].mid == 0) begin
                    if(!curValidMOps[i*MICRO_OP_MAX_NUM + j]) begin
                        debug.idReg[i].valid = FALSE;
                    end
                    break;
                end
            end
            
            
            debug.idReg[i].opId.sid = pipeReg[i].sid;
            debug.idReg[i].opId.mid = 0;
            debug.idReg[i].pc = ToAddrFromPC(pipeReg[i].pc);
            debug.idReg[i].insn = pipeReg[i].insn;
            
            debug.idReg[i].undefined = FALSE;
            debug.idReg[i].unsupported = FALSE;
            for (int j = 0; j < MICRO_OP_MAX_NUM; j++) begin
                debug.idReg[i].undefined = debug.idReg[i].undefined | microOps[i*MICRO_OP_MAX_NUM + j].undefined;
                debug.idReg[i].unsupported = debug.idReg[i].unsupported | microOps[i*MICRO_OP_MAX_NUM + j].unsupported;
            end
        end
`endif

    end
endmodule : DecodeStage


