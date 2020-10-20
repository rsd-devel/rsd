// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for register read.
//

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import MicroOpTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import LoadStoreUnitTypes::*;
import DebugTypes::*;

// シリアライズ命令が送られて来た場合，パイプラインを適切にストールさせる
// シリアライズ命令の前の命令がコミットして ROB が空になるまで待って，
// さらにシリアライズ命令自身がコミットされるまで上流をストールさせ続ける
//
// DecodeStage がシリアライズ命令のみを必ず単独で送ってくるようにしているため，
// 先頭しかみていない
module RenameStageSerializer(
input 
    logic clk, rst, stall, clear, activeListEmpty, storeQueueEmpty,
    OpInfo [RENAME_WIDTH-1:0] opInfo, // Unpacked array of structure corrupts in Modelsim.
    logic [RENAME_WIDTH-1:0] valid,
output 
    logic serialize
);
    generate
        for (genvar i = 1; i < RENAME_WIDTH; i++) begin : assertionBlock
            `RSD_ASSERT_CLK_FMT(
                clk, 
                !(opInfo[i].serialized && valid[i]), 
                ("Multiple serialized ops were sent to RenameStage. (%x, %x)", opInfo[i].serialized, valid[i])
            ); 
        end
    endgenerate

    // Serialize phase
    typedef enum logic[1:0]
    {
        PHASE_NORMAL = 0,               // フェッチ継続
        PHASE_WAIT_OWN = 2              // 自分自身のコミット待ち
    } Phase;
    Phase regPhase, nextPhase;

    always_ff@(posedge clk)   // synchronous rst
    begin
        if (rst) begin
            regPhase <= PHASE_NORMAL;
        end
        else if(!stall) begin             // write data
            regPhase <= nextPhase;
        end
    end

    always_comb begin
        // multiple serialized ops must not be sent to this stage.
        serialize = FALSE;
        nextPhase = PHASE_NORMAL;
        if (clear) begin
            nextPhase = PHASE_NORMAL; // force reset 
        end
        if (regPhase == PHASE_NORMAL) begin
            if (opInfo[0].serialized && valid[0]) begin
                if (opInfo[0].operand.miscMemOp.fence) begin // Fence
                    if (!activeListEmpty || !storeQueueEmpty) begin
                        // Fence must wait for all previous ops to be committed
                        // AND all committed stores in SQ to be written back
                        serialize = TRUE;   
                        nextPhase = PHASE_NORMAL;
                    end
                    else begin
                        // deassert serialize" for dispatch    
                        nextPhase = PHASE_WAIT_OWN;
                    end
                end 
                else begin // Non-fence
                    if (!activeListEmpty) begin
                        // Wait for all previous ops to be committed
                        serialize = TRUE;   
                        nextPhase = PHASE_NORMAL;
                    end
                    else begin
                        // deassert serialize" for dispatch  
                        nextPhase = PHASE_WAIT_OWN;
                    end
                end
            end
        end
        else begin
            // Wait for a serialized op to be committed
            if (!activeListEmpty || !storeQueueEmpty) begin
                serialize = TRUE;
                nextPhase = PHASE_WAIT_OWN;
            end
            else begin
                nextPhase = PHASE_NORMAL;
            end
        end
    end

endmodule

module RenameStage(
    RenameStageIF.ThisStage port,
    DecodeStageIF.NextStage prev,
    RenameLogicIF.RenameStage renameLogic,
    ActiveListIF.RenameStage activeList,
    SchedulerIF.RenameStage scheduler,
    LoadStoreUnitIF.RenameStage loadStoreUnit,
    RecoveryManagerIF.RenameStage recovery,
    ControllerIF.RenameStage ctrl,
    DebugIF.RenameStage debug
);

    // --- Pipeline registers
    RenameStageRegPath pipeReg[RENAME_WIDTH];
    logic regFlush;
    PC_Path regRecoveredPC;


`ifndef RSD_SYNTHESIS
    `ifndef RSD_VIVADO_SIMULATION
        // Don't care these values, but avoiding undefined status in Questa.
        initial begin
            for (int i = 0; i < RENAME_WIDTH; i++) begin
                pipeReg[i] = '0;
            end
            regRecoveredPC = '0;
        end
    `endif
`endif

    always_ff@( posedge port.clk )   // synchronous rst
    begin
        if (port.rst) begin
            for (int i = 0; i < RENAME_WIDTH; i++) begin
                pipeReg[i].valid <= FALSE;
            end
            regFlush <= '0;
            regRecoveredPC <= '0;
        end
        else if(!ctrl.rnStage.stall) begin             // write data
            pipeReg <= prev.nextStage;
            regFlush <= prev.nextFlush;
            regRecoveredPC <= prev.nextRecoveredPC;
        end
    end

    always_comb begin
        recovery.recoverFromRename = regFlush;
        recovery.recoveredPC_FromRename = regRecoveredPC;
        ctrl.rnStageFlushUpper = regFlush;
    end


    // Pipeline controll
    logic stall, clear;
    logic empty;
    logic serialize;

    logic [ RENAME_WIDTH-1:0 ] valid;
    logic update [ RENAME_WIDTH ];
    OpInfo [RENAME_WIDTH-1:0] opInfo;
    ActiveListEntry alEntry [ RENAME_WIDTH ];
    DispatchStageRegPath nextStage [ RENAME_WIDTH ];

    logic isLoad[RENAME_WIDTH];
    logic isStore[RENAME_WIDTH];
    logic isBranch[RENAME_WIDTH];

    logic activeListEmpty;
    logic storeQueueEmpty;

    always_comb begin
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            valid[i] = pipeReg[i].valid;
            opInfo[i] = pipeReg[i].opInfo;
        end

        // The rename stage stalls when resources cannot be allocated.
        // Inputs of stall/flush requests to the controller must not dependend
        // on stall/clear signals for avoiding a race condition.
        ctrl.rnStageSendBubbleLower =
            (
                ( |valid ) &&
                (
                    !renameLogic.allocatable ||
                    !scheduler.allocatable ||
                    !activeList.allocatable ||
                    !loadStoreUnit.allocatable
                )
            ) || serialize;

        stall = ctrl.rnStage.stall;
        clear = ctrl.rnStage.clear;
        activeListEmpty = activeList.validEntryNum == 0;
        storeQueueEmpty = loadStoreUnit.storeQueueEmpty;
    end

    RenameStageSerializer serializer(
        port.clk, port.rst, stall, clear, activeListEmpty, storeQueueEmpty,
        opInfo, 
        valid,
        serialize
    );

    logic isEnv[RENAME_WIDTH];
    always_comb begin
        //
        // --- Data to Rename logic
        //
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            // The rename stage stalls when resources cannot be allocated.
            update[i] =
                valid[i] && !stall && !clear;
        end

        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            isLoad[i] = 
                (opInfo[i].mopType == MOP_TYPE_MEM) && 
                (opInfo[i].mopSubType.memType == MEM_MOP_TYPE_LOAD);
            isStore[i] = 
                (opInfo[i].mopType == MOP_TYPE_MEM) && 
                (opInfo[i].mopSubType.memType == MEM_MOP_TYPE_STORE);
            isEnv[i] = 
                (opInfo[i].mopType == MOP_TYPE_MEM) && 
                (opInfo[i].mopSubType.memType == MEM_MOP_TYPE_ENV);
            isBranch[i] =
                (opInfo[i].mopType == MOP_TYPE_INT) &&
                (opInfo[i].mopSubType.intType inside {INT_MOP_TYPE_BR, INT_MOP_TYPE_RIJ});
        end

        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            renameLogic.updateRMT[i] = update[i];

            // Logical register numbers
            renameLogic.logSrcRegA[i] = isBranch[i] ? opInfo[i].operand.brOp.srcRegNumA : opInfo[i].operand.intOp.srcRegNumA;
            renameLogic.logSrcRegB[i] = isBranch[i] ? opInfo[i].operand.brOp.srcRegNumB : opInfo[i].operand.intOp.srcRegNumB;
            renameLogic.logDstReg[i] = isBranch[i] ? opInfo[i].operand.brOp.dstRegNum : opInfo[i].operand.intOp.dstRegNum;

            // Read/Write control
            renameLogic.readRegA[i] = opInfo[i].opTypeA == OOT_REG;
            renameLogic.readRegB[i] = opInfo[i].opTypeB == OOT_REG;

            renameLogic.writeReg[i] = opInfo[i].writeReg;

            // to WAT
            renameLogic.watWriteRegFromPipeReg[i] = opInfo[i].writeReg && update[i];
            renameLogic.watWriteIssueQueuePtrFromPipeReg[i] = scheduler.allocatedPtr[i];
        end


        //
        // --- Renamed operands
        //
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            // Renamed physical register numbers.
            nextStage[i].phySrcRegNumA = renameLogic.phySrcRegA[i];
            nextStage[i].phySrcRegNumB = renameLogic.phySrcRegB[i];
            nextStage[i].phyDstRegNum = renameLogic.phyDstReg[i];
            nextStage[i].phyPrevDstRegNum = renameLogic.phyPrevDstReg[i];

        end

        // Source pointer for a matrix scheduler.
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            // Renamed physical register numbers.
            nextStage[i].srcIssueQueuePtrRegA = renameLogic.srcIssueQueuePtrRegA[i];
            nextStage[i].srcIssueQueuePtrRegB = renameLogic.srcIssueQueuePtrRegB[i];
        end


        //
        // Active list allocation
        //
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            activeList.pushTail[i] = update[i];

            `ifndef RSD_DISABLE_DEBUG_REGISTER
                alEntry[i].opId = pipeReg[i].opId;
            `endif

            alEntry[i].pc = pipeReg[i].pc;

            alEntry[i].phyPrevDstRegNum = nextStage[i].phyPrevDstRegNum;
            alEntry[i].phyDstRegNum = nextStage[i].phyDstRegNum;
            alEntry[i].logDstRegNum = opInfo[i].operand.intOp.dstRegNum;
            alEntry[i].writeReg = opInfo[i].writeReg;
            alEntry[i].isLoad = isLoad[i];
            alEntry[i].isStore = isStore[i];
            alEntry[i].isBranch = isBranch[i];
            alEntry[i].isEnv = opInfo[i].operand.systemOp.isEnv;
            alEntry[i].undefined = opInfo[i].undefined || opInfo[i].unsupported;
            alEntry[i].last = opInfo[i].last;
            alEntry[i].prevDependIssueQueuePtr = renameLogic.prevDependIssueQueuePtr[i];

            nextStage[i].activeListPtr = activeList.pushedTailPtr[i];
        end
        activeList.pushedTailData = alEntry;

        //
        // Issue queue allocation
        //
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            scheduler.allocate[i] = update[i];
            nextStage[i].issueQueuePtr = scheduler.allocatedPtr[i];
        end


        //
        // Load/store unit allocation
        //
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            loadStoreUnit.allocateLoadQueue[i] = update[i] && isLoad[i];
            loadStoreUnit.allocateStoreQueue[i] = update[i] && isStore[i];

            nextStage[i].loadQueuePtr = loadStoreUnit.allocatedLoadQueuePtr[i];
            nextStage[i].storeQueuePtr = loadStoreUnit.allocatedStoreQueuePtr[i];
        end

        // Make read request to Memory Dependent Prediction
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            port.pc[i] = pipeReg[i].pc;
        end
        
        //
        // --- Pipeline control
        //

        // 'valid' is invalidate, if 'stall' or 'clear' or 'rst' is enabled.
        // That is, a op is treated as a NOP.
        // Otherwise 'valid' is set to a previous stage's 'valid.'
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].opId = pipeReg[i].opId;
`endif

            nextStage[i].valid =
                ( stall || clear || port.rst ) ? FALSE : valid[i];

            // Decoded micr-op and context.
            nextStage[i].pc = pipeReg[i].pc;
            nextStage[i].brPred = pipeReg[i].bPred;
            nextStage[i].opInfo = opInfo[i];

            // 以下のLSQのポインタはLSQのリカバリに用いる
            nextStage[i].loadQueueRecoveryPtr = loadStoreUnit.allocatedLoadQueuePtr[i];
            nextStage[i].storeQueueRecoveryPtr = loadStoreUnit.allocatedStoreQueuePtr[i];

        end
        port.nextStage = nextStage;

        empty = TRUE;
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            if (pipeReg[i].valid)
                empty = FALSE;
        end
        ctrl.rnStageEmpty = empty;

        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            debug.rnReg[i].valid = valid[i];
            debug.rnReg[i].opId = pipeReg[i].opId;
        end
`endif
    end



endmodule : RenameStage
