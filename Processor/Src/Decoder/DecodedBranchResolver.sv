// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Resolve branch misprediction on the decode stage.
// This unit includes a simple return address stack.
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
    logic clk, rst, stall, decodeComplete,
    logic insnValidIn[DECODE_WIDTH],
    RISCV_ISF_Common [DECODE_WIDTH-1 : 0] isf,      // Unpacked array of structure corrupts in Modelsim.
    BranchPred [DECODE_WIDTH-1 : 0] brPredIn,
    PC_Path pc[DECODE_WIDTH],
    InsnInfo [DECODE_WIDTH-1 : 0] insnInfo,
output 
    logic insnValidOut[DECODE_WIDTH],
    logic insnFlushed[DECODE_WIDTH],
    logic insnFlushTriggering[DECODE_WIDTH],
    logic flushTriggered,
    BranchPred brPredOut[DECODE_WIDTH],
    PC_Path recoveredPC
);
    // Return address stack.
    parameter RAS_ENTRY_NUM = 4;
    typedef logic [$clog2(RAS_ENTRY_NUM)-1 : 0] RAS_IndexPath;
    PC_Path ras[RAS_ENTRY_NUM];
    PC_Path nextRAS;
    logic pushRAS;
    logic popRAS;
    RAS_IndexPath rasPtr;
    RAS_IndexPath nextRAS_Ptr;

    always_ff@(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < RAS_ENTRY_NUM; i++) begin
                ras[i] <= '0;
            end
            rasPtr <= '0;
        end
        else if (!stall && decodeComplete) begin
            // 全 micro op のデコード完了時にだけ RAS を更新するようにしないと，
            // 次のステージに送り込んだ micro op のターゲットと，ここから
            // 出しているターゲットアドレスがずれて（ras の ptr が更新されるから）
            // 正しく動かなくなる
            if (pushRAS) begin
                ras[nextRAS_Ptr] <= nextRAS;
            end
            rasPtr <= nextRAS_Ptr;
        end
        // if (pushRAS) begin
        //     $display("Call(%d) flush @%x old:%p new:%p", nextRAS_Ptr, pc[addrCheckLane], brPredIn[addrCheckLane].predAddr, decodedPC[addrCheckLane]);
        // end 
        // else if (popRAS) begin
        //     $display("Ret(%d)  @%x old:%p new:%p", rasPtr, pc[addrCheckLane], brPredIn[addrCheckLane].predAddr, decodedPC[addrCheckLane]);
        // end
        // if (flushTriggered) begin
        //     $display("flushTriggered @%x old:%p new:%p", pc[addrCheckLane], brPredIn[addrCheckLane].predAddr, decodedPC[addrCheckLane]);
        // end
    end

    
    PC_Path decodedPC[DECODE_WIDTH];
    PC_Path nextPC[DECODE_WIDTH];
    RISCV_ISF_U isfU[DECODE_WIDTH];

    logic addrCheck;
    logic addrIncorrect;
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
    logic addrMismatch[DECODE_WIDTH];

    always_comb begin
        
        // Initialize
        flushTriggered = FALSE;
        recoveredPC = '0;

        pushRAS = FALSE;
        popRAS = FALSE;
        nextRAS = 0;
        nextRAS_Ptr = rasPtr;
        
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
                // Update the RAS.
                pushRAS = insnInfo[i].isCall;

                addrCheckLane = i;
                addrCheck = TRUE;
                break;
            end
            else if ( // JALR
                brTargetType[i] == BTT_INDIRECT_JUMP
            ) begin
                // Update theRAS.
                pushRAS = insnInfo[i].isCall;
                popRAS = insnInfo[i].isReturn;

                if (popRAS) begin
                    // Resolve branch pred using the PC read from RAS
                    addrCheckLane = i;
                    addrCheck = TRUE;
                    break;
                end
                else if (pushRAS) begin
                    // Push next PC to RAS．Do not resolve branch pred
                    addrCheckLane = i;
                    break;
                end
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
            nextPC[i] = pc[i] + INSN_BYTE_WIDTH;
            if (brTargetType[i] == BTT_PC_RELATIVE) begin
                // Calculate target PC from displacement
                if (isfU[i].opCode == RISCV_JAL) begin
                    decodedPC[i] = pc[i] + ExtendBranchDisplacement( GetJAL_Target(isfU[i]));
                end
                else begin
                    decodedPC[i] = pc[i] + ExtendBranchDisplacement( GetBranchDisplacement(isfU[i]));
                end
            end
            else if (brTargetType[i] == BTT_INDIRECT_JUMP) begin
                // Read branch target PC from RAS
                decodedPC[i] = ras[rasPtr];
            end
            else begin
                // non-branch instruction
                decodedPC[i] = nextPC[i];
            end
        end
        
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            addrMismatch[i] = brPredIn[i].predAddr != decodedPC[i];
        end
        
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            if (((addrMismatch[i] && addrCheck) || addrIncorrect) && addrCheckLane == i) begin
                flushTriggered = TRUE;
                brPredOut[i].predAddr = decodedPC[i];
                brPredOut[i].predTaken = TRUE;
                break;
            end
        end
        recoveredPC = decodedPC[addrCheckLane];

        // Update the RAS.
        nextRAS = nextPC[addrCheckLane];
        if (pushRAS) begin
            // $display("Call(%d) flush @%x old:%p new:%p", nextRAS_Ptr, pc[addrCheckLane], brPredIn[addrCheckLane].predAddr, decodedPC[addrCheckLane]);
            nextRAS_Ptr = rasPtr + 1;
        end 
        else if (popRAS) begin
            // $display("Ret(%d)  @%x old:%p new:%p", rasPtr, pc[addrCheckLane], brPredIn[addrCheckLane].predAddr, decodedPC[addrCheckLane]);
            nextRAS_Ptr = rasPtr - 1;
        end
        else begin
            nextRAS_Ptr = rasPtr;
        end

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

