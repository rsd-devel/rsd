// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Resolve branch misprediction on the decode stage.
//

import BasicTypes::*;
import MemoryMapTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import PipelineTypes::*;
import DebugTypes::*;
import FetchUnitTypes::*;

module DecodedBranchResolver(
input
    logic insnValidIn[DECODE_WIDTH],
    RISCV_ISF_Common [DECODE_WIDTH-1 : 0] isf,      // Unpacked array of structure corrupts in Modelsim.
    BranchPred [DECODE_WIDTH-1 : 0] brPredIn,
    PC_Path pc[DECODE_WIDTH],
    InsnInfo [DECODE_WIDTH-1 : 0] insnInfo,
    BTB_BranchType [DECODE_WIDTH-1 : 0] brType,
output 
    logic insnValidOut[DECODE_WIDTH],
    logic insnFlushed[DECODE_WIDTH],
    logic insnFlushTriggering[DECODE_WIDTH],
    logic flushTriggered,
    BranchPred brPredOut[DECODE_WIDTH],
    PC_Path recoveredPC, rasReturnPC,
    logic rasPush,
    BranchRecoveryPath recoveredPredCtx
);
    PC_Path decodedPC[DECODE_WIDTH];
    RISCV_ISF_U isfU[DECODE_WIDTH];

    logic addrCheck;
    logic addrIncorrect;
    logic predPush, rasMiss;
    DecodeLaneIndexPath addrCheckLane;
    typedef enum logic [1:0] 
    {
        BTT_NEXT = 0,       // nextPC 
        BTT_PC_RELATIVE = 1,         // BRANCH, JAL
        BTT_INDIRECT_JUMP  = 2,       // JALR

        // This insn is serialized, so the succeeding insns are flushed
        BTT_SERIALIZED  = 3 
    } BranchTargetType;
    BranchTargetType brTargetType[DECODE_WIDTH];

    always_comb begin
        
        // Initialize
        flushTriggered = FALSE;
        recoveredPC = '0;

        for (int i = 0; i < DECODE_WIDTH; i++) begin
            insnValidOut[i] = insnValidIn[i];
            insnFlushed[i] = FALSE;
            insnFlushTriggering[i] = FALSE;
            brPredOut[i] = brPredIn[i];
            isfU[i] = isf[i];
        end

        addrCheck = FALSE;
        addrIncorrect = FALSE;
        addrCheckLane = '0;
        
        // Determine the type of branch
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            
            if (insnInfo[i].isRelBranch) begin
                // Normal branch.
                brTargetType[i] = BTT_PC_RELATIVE;
            end
            else if (insnInfo[i].writePC) begin
                // Indirect branch
                brTargetType[i] = BTT_INDIRECT_JUMP;
            end
            else if (insnInfo[i].isSerialized) begin
                brTargetType[i] = BTT_SERIALIZED;
            end
            else begin
                brTargetType[i] = BTT_NEXT;
            end
        end

        // Detects possible  patterns where flash occurs
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            if (!insnValidIn[i]) begin
                break;
            end
            
            if (!insnInfo[i].writePC && brPredIn[i].predTaken) begin
                // Recovery if not branch instructions are predicted as branches.
                addrCheckLane = i;
                addrCheck = TRUE;
                addrIncorrect = TRUE;   // ミスが確定
                break;
            end
            else if ( //JAL || ( Branch && predTaken )
                brTargetType[i] == BTT_PC_RELATIVE && 
                (isfU[i].opCode == RISCV_JAL || brPredIn[i].predTaken)   
            ) begin
                addrCheckLane = i;
                addrCheck = TRUE;
                break;
            end
            else if ( // JALR
                brTargetType[i] == BTT_INDIRECT_JUMP
            ) begin
                // Decode can repair the RAS here. Execute resolves the indirect target.
                addrCheckLane = i;
                addrCheck = TRUE;
                break;
            end
            else if (brTargetType[i] == BTT_SERIALIZED) begin
                // The succeeding instructions are flushed.
                addrCheckLane = i;
                addrCheck = TRUE;
                addrIncorrect = TRUE;   // ミスが確定
                break;
            end
        end
        
        // Calculate target PC
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            if (brTargetType[i] == BTT_PC_RELATIVE) begin
                // Calculate target PC from displacement
                if (isfU[i].opCode == RISCV_JAL) begin
                    decodedPC[i] = pc[i] + ExtendBranchDisplacement( GetJAL_Target(isfU[i]));
                end
                else begin
                    decodedPC[i] = pc[i] + ExtendBranchDisplacement( GetBranchDisplacement(isfU[i]));
                end
            end
            else if (brTargetType[i] == BTT_INDIRECT_JUMP && brPredIn[i].predTaken) begin
                decodedPC[i] = brPredIn[i].takenAddr;
            end
            else begin
                decodedPC[i] = pc[i] + INSN_BYTE_WIDTH;
            end
        end
        
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            // A direction miss redirects even when the target equals the fall-through PC.
            if (addrCheckLane == i &&
                (addrIncorrect || (addrCheck && brTargetType[i] == BTT_PC_RELATIVE &&
                                   (!brPredIn[i].predTaken || brPredIn[i].takenAddr != decodedPC[i])))) begin
                flushTriggered = TRUE;
                brPredOut[i].predTaken = insnInfo[i].writePC;
                if (insnInfo[i].writePC) begin
                    // Decode supplies the target on a redirect. Keep the Fetch hit way for training.
                    brPredOut[i].takenAddrChangedAtDecode = TRUE;
                    brPredOut[i].takenAddr = decodedPC[i];
                end
                break;
            end
        end
        recoveredPC = decodedPC[addrCheckLane];
        // Repair the selected instruction's stack operation even when its target was correct.
        predPush = brPredIn[addrCheckLane].predTaken && brPredIn[addrCheckLane].btbBrType == BTB_CALL;
        rasPush = addrCheck && brType[addrCheckLane] == BTB_CALL && !predPush;
        rasReturnPC = pc[addrCheckLane] + INSN_BYTE_WIDTH;
        rasMiss = addrCheck && (predPush != (brType[addrCheckLane] == BTB_CALL) ||
            (brPredIn[addrCheckLane].predTaken &&
             (brPredIn[addrCheckLane].btbBrType inside {BTB_RETURN, BTB_RETURN_OFFSET}) !=
             (brType[addrCheckLane] inside {BTB_RETURN, BTB_RETURN_OFFSET})));
        flushTriggered = flushTriggered || rasMiss;

        recoveredPredCtx.ctx = RecoverBranchHistory(
            pc[addrCheckLane], brPredIn[addrCheckLane].brLookup, brPredOut[addrCheckLane].predTaken
        );
        // An unresolved indirect call pushes its link while following Fetch's prediction.
        recoveredPredCtx.rasPtr = RecoverRAS_Ptr(
            brPredIn[addrCheckLane].rasPtr, brType[addrCheckLane], brPredOut[addrCheckLane].predTaken || rasPush
        );

        if (flushTriggered) begin
            for (int i = 0; i < DECODE_WIDTH; i++) begin
                if (i > addrCheckLane) begin
                    insnValidOut[i] = FALSE;
                    insnFlushed[i] = TRUE;
                end
            end
            insnFlushTriggering[addrCheckLane] = TRUE;
        end
    end // always_comb

endmodule

