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

    // Pipeline control
    logic stall, clear;
    logic empty;
    RenameStageRegPath nextStage[DECODE_WIDTH];
    
    // Micro-op decoder
    OpInfo [ALL_DECODED_MICRO_OP_WIDTH-1:0] microOps;  // Decoded micro ops
    InsnInfo [DECODE_WIDTH-1:0] insnInfo;   // Whether a decoded instruction is branch or not.
    
    always_comb begin
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            for (int j = 0; j < MICRO_OP_MAX_NUM; j++) begin
                microOps[i*MICRO_OP_MAX_NUM + j] = pipeReg[i].microOps[j];
            end
            insnInfo[i] = pipeReg[i].insnInfo;
        end

        empty = TRUE;
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            if (pipeReg[i].valid)
                empty = FALSE;
        end
        ctrl.idStageEmpty = empty;
    end
    
    
    // Control
    logic initiate;
    logic complete;
    
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
    BranchGlobalHistoryPath recoveredBrHistory;

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
        .recoveredPC(recoveredPC),
        .recoveredBrHistory(recoveredBrHistory)
    );
    
    always_comb begin
        port.nextFlush = complete && flushTriggered && !clear;
        port.nextRecoveredPC = recoveredPC;
        port.nextRecoveredBrHistory = recoveredBrHistory;
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
    

    always_comb begin
        
        //
        // Setup current valid bits(=un-decoded bits).
        //
        if (initiate) begin
            for (int i = 0; i < ALL_DECODED_MICRO_OP_WIDTH; i++) begin
                curValidMOps[i] = microOps[i].valid;
            end
        end
        else begin
            curValidMOps = remainingValidMOps;
        end

        // Set a "serialized" flag for each micro op.
        for (int i = 0; i < ALL_DECODED_MICRO_OP_WIDTH; i++) begin
            serializedMOps[i] = microOps[i].serialized;
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


