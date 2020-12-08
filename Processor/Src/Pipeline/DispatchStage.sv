// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for dispatch.
//

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import MicroOpTypes::*;
import PipelineTypes::*;
import SchedulerTypes::*;
import DebugTypes::*;

module DispatchStage(
    //DispatchStageIF.ThisStage port,
    RenameStageIF.NextStage prev,
    SchedulerIF.DispatchStage scheduler,
    ControllerIF.DispatchStage ctrl,
    DebugIF.DispatchStage debug
);

    // パディングは IntOpSubInfo のみ行う．対応できない場合は ASSERT に引っかかる
    `RSD_STATIC_ASSERT(
        INT_SUB_INFO_BIT_WIDTH <= BR_SUB_INFO_BIT_WIDTH, 
        "Invalid padding at IntOpSubInfo"
    );

    // --- Pipeline registers
    DispatchStageRegPath pipeReg [ DISPATCH_WIDTH ];
    always_ff @(posedge ctrl.clk) begin
        if (ctrl.rst) begin
            for (int i = 0; i < DISPATCH_WIDTH; i++) begin
                pipeReg[i] <= '0;
            end
        end
        else if (!ctrl.dsStage.stall) begin
            pipeReg <= prev.nextStage;
        end
        else begin
            pipeReg <= pipeReg;
        end
    end

    // Pipeline controll
    logic stall, clear;
    logic update  [ DISPATCH_WIDTH ];
    OpInfo opInfo [ DISPATCH_WIDTH ];
    IntIssueQueueEntry     intEntry     [ DISPATCH_WIDTH ];
    ComplexIssueQueueEntry complexEntry [ DISPATCH_WIDTH ];
    MemIssueQueueEntry     memEntry     [ DISPATCH_WIDTH ];
    SchedulerEntry schedulerEntry [ DISPATCH_WIDTH ];
    OpSrc opSrc[ DISPATCH_WIDTH ];
    OpDst opDst[ DISPATCH_WIDTH ];

    IntOpSubInfo intSubInfo[ DISPATCH_WIDTH ];
    BrOpSubInfo  brSubInfo [ DISPATCH_WIDTH ];
    MulOpSubInfo mulSubInfo[ DISPATCH_WIDTH ];
    DivOpSubInfo divSubInfo[ DISPATCH_WIDTH ];
    always_comb begin
        stall = ctrl.dsStage.stall;
        clear = ctrl.dsStage.clear;

        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
            update[i] = !stall && !clear && pipeReg[i].valid;
            opInfo[i] = pipeReg[i].opInfo;
        end

        //
        // Dispatch an op to the shceduler.
        //
        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
            //
            // Issue queue payload RAM entry.
            //
`ifndef RSD_DISABLE_DEBUG_REGISTER
            intEntry[i].opId     = pipeReg[i].opId;
            complexEntry[i].opId = pipeReg[i].opId;
            memEntry[i].opId     = pipeReg[i].opId;
`endif
            // OpSrc
            opSrc[i].phySrcRegNumA = pipeReg[i].phySrcRegNumA;
            opSrc[i].phySrcRegNumB = pipeReg[i].phySrcRegNumB;

            // OpDst
            opDst[i].writeReg = pipeReg[i].opInfo.writeReg;
            opDst[i].phyDstRegNum = pipeReg[i].phyDstRegNum;

            //
            // --- To an integer queue.
            //
            intEntry[i].opType = opInfo[i].mopSubType.intType;
            intEntry[i].cond = opInfo[i].cond;

            // OpSrc/OpDst
            intEntry[i].opSrc = opSrc[i];
            intEntry[i].opDst = opDst[i];

            // ActiveListIndexPath
            intEntry[i].activeListPtr = pipeReg[i].activeListPtr;

            //LSQ Tail Pointer for one cycle recovery
            intEntry[i].loadQueueRecoveryPtr = pipeReg[i].loadQueueRecoveryPtr;
            intEntry[i].storeQueueRecoveryPtr = pipeReg[i].storeQueueRecoveryPtr;

            // PC
            intEntry[i].pc = pipeReg[i].pc;

            intSubInfo[i].operandTypeA  = opInfo[i].opTypeA;
            intSubInfo[i].operandTypeB  = opInfo[i].opTypeB;
            intSubInfo[i].shiftIn       = opInfo[i].operand.intOp.shiftIn;
            intSubInfo[i].shiftType     = opInfo[i].operand.intOp.shiftType;
            intSubInfo[i].aluCode       = opInfo[i].operand.intOp.aluCode;
            intSubInfo[i].padding = '0;

            brSubInfo[i].brDisp = opInfo[i].operand.brOp.brDisp;
            brSubInfo[i].bPred = pipeReg[i].brPred;
            brSubInfo[i].operandTypeA = opInfo[i].opTypeA;
            brSubInfo[i].operandTypeB = opInfo[i].opTypeB;

            if ((intEntry[i].opType == INT_MOP_TYPE_BR) || (intEntry[i].opType == INT_MOP_TYPE_RIJ) ) begin
                intEntry[i].intOpInfo.brSubInfo = brSubInfo[i];
            end
            else begin
                intEntry[i].intOpInfo.intSubInfo = intSubInfo[i];
            end

            //
            // --- To a complex integer queue.
            //
            complexEntry[i].opType = opInfo[i].mopSubType.complexType;

            // OpSrc/OpDst
            complexEntry[i].opSrc = opSrc[i];
            complexEntry[i].opDst = opDst[i];

            // ActiveListIndexPath
            complexEntry[i].activeListPtr = pipeReg[i].activeListPtr;

            // PC
            complexEntry[i].pc = pipeReg[i].pc;

            complexEntry[i].loadQueueRecoveryPtr = pipeReg[i].loadQueueRecoveryPtr;
            complexEntry[i].storeQueueRecoveryPtr = pipeReg[i].storeQueueRecoveryPtr;

            mulSubInfo[i].mulGetUpper = opInfo[i].operand.complexOp.mulGetUpper;
            mulSubInfo[i].mulCode = opInfo[i].operand.complexOp.mulCode;

            divSubInfo[i].padding = '0;
            divSubInfo[i].divCode = opInfo[i].operand.complexOp.divCode;
            
            if (complexEntry[i].opType == COMPLEX_MOP_TYPE_MUL) begin
                complexEntry[i].complexOpInfo.mulSubInfo = mulSubInfo[i];
            end
            else begin // 将来ComplexパイプラインにMulとDiv以外の演算器を追加する場合はここをelse if (complexEntry[i].opType == COMPLEX_MOP_TYPE_DIV)に
                complexEntry[i].complexOpInfo.divSubInfo = divSubInfo[i];
            end
            
            //
            // --- To a memory queue.
            //

            // MemOpInfo
            memEntry[i].memOpInfo.opType = opInfo[i].mopSubType.memType;

            memEntry[i].memOpInfo.cond          = opInfo[i].cond;
            memEntry[i].memOpInfo.operandTypeA  = opInfo[i].opTypeA;
            memEntry[i].memOpInfo.operandTypeB  = opInfo[i].opTypeB;
            memEntry[i].memOpInfo.addrIn        = opInfo[i].operand.memOp.addrIn;
            memEntry[i].memOpInfo.isAddAddr     = opInfo[i].operand.memOp.isAddAddr;
            memEntry[i].memOpInfo.isRegAddr     = opInfo[i].operand.memOp.isRegAddr;
            memEntry[i].memOpInfo.memAccessMode = opInfo[i].operand.memOp.memAccessMode;

            memEntry[i].memOpInfo.csrCtrl     = opInfo[i].operand.memOp.csrCtrl;
            memEntry[i].memOpInfo.envCode     = opInfo[i].operand.systemOp.envCode;

            memEntry[i].memOpInfo.isFenceI    = opInfo[i].operand.miscMemOp.fenceI;

`ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            // これらは complex のフォーマットから取得する
            memEntry[i].memOpInfo.mulSubInfo = mulSubInfo[i];
            memEntry[i].memOpInfo.divSubInfo = divSubInfo[i];
`endif

            memEntry[i].memOpInfo.loadQueuePtr  = pipeReg[i].loadQueuePtr;
            memEntry[i].memOpInfo.storeQueuePtr = pipeReg[i].storeQueuePtr;

            memEntry[i].memOpInfo.hasAllocatedMSHR = 0;
            memEntry[i].memOpInfo.mshrID = '0;

            // OpSrc
            memEntry[i].opSrc = opSrc[i];
            memEntry[i].opDst = opDst[i];

            // ActiveListIndexPath
            memEntry[i].activeListPtr = pipeReg[i].activeListPtr;

            //LSQ Tail Pointer for one cycle recovery
            memEntry[i].loadQueueRecoveryPtr = pipeReg[i].loadQueueRecoveryPtr;
            memEntry[i].storeQueueRecoveryPtr = pipeReg[i].storeQueueRecoveryPtr;

            // PC
            memEntry[i].pc = pipeReg[i].pc;

            //
            // Scheduler Entry
            //
            schedulerEntry[i].opType = opInfo[i].mopType;
            schedulerEntry[i].opSubType = opInfo[i].mopSubType;

            schedulerEntry[i].srcRegValidA = ( opInfo[i].opTypeA == OOT_REG );
            schedulerEntry[i].srcRegValidB = ( opInfo[i].opTypeB == OOT_REG );
            schedulerEntry[i].opSrc = opSrc[i];
            schedulerEntry[i].opDst = opDst[i];

            schedulerEntry[i].srcPtrRegA = pipeReg[i].srcIssueQueuePtrRegA;
            schedulerEntry[i].srcPtrRegB = pipeReg[i].srcIssueQueuePtrRegB;

            //
            // Output to scheduler
            //
            scheduler.write[i] = update[i];
            scheduler.writePtr[i] = pipeReg[i].issueQueuePtr;
            scheduler.writeAL_Ptr[i] = pipeReg[i].activeListPtr;
            scheduler.intWriteData[i] = intEntry[i];
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            scheduler.complexWriteData[i] = complexEntry[i];
`endif
            scheduler.memWriteData[i] = memEntry[i];
            scheduler.writeSchedulerData[i] = schedulerEntry[i];
            scheduler.allocated[i] = pipeReg[i].valid;
            scheduler.memDependencyPred[i] = prev.memDependencyPred[i];
        end

`ifndef RSD_DISABLE_DEBUG_REGISTER
        // Debug Register
        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
            debug.dsReg[i].valid = pipeReg[i].valid;
            debug.dsReg[i].opId = pipeReg[i].opId;

`ifdef RSD_FUNCTIONAL_SIMULATION
            debug.dsReg[i].readRegA = opInfo[i].opTypeA == OOT_REG;
            debug.dsReg[i].logSrcRegA = opInfo[i].operand.intOp.srcRegNumA;
            debug.dsReg[i].phySrcRegA = pipeReg[i].phySrcRegNumA;

            debug.dsReg[i].readRegB = opInfo[i].opTypeB == OOT_REG;
            debug.dsReg[i].logSrcRegB = opInfo[i].operand.intOp.srcRegNumB;
            debug.dsReg[i].phySrcRegB = pipeReg[i].phySrcRegNumB;

            debug.dsReg[i].writeReg = opInfo[i].writeReg;
            debug.dsReg[i].logDstReg = opInfo[i].operand.intOp.dstRegNum;
            debug.dsReg[i].phyDstReg = pipeReg[i].phyDstRegNum;
            debug.dsReg[i].phyPrevDstReg = pipeReg[i].phyPrevDstRegNum;

            debug.dsReg[i].issueQueuePtr = pipeReg[i].issueQueuePtr;
`endif
        end
`endif
    end

endmodule : DispatchStage
