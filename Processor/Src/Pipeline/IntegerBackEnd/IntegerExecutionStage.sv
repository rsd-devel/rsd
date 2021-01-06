// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Execution stage
//

import BasicTypes::*;
import MemoryMapTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import PipelineTypes::*;
import DebugTypes::*;
import FetchUnitTypes::*;
import RenameLogicTypes::*;


function automatic logic IsConditionEnabledInt( CondCode cond, DataPath opA, DataPath opB );
    logic ce;
    SignedDataPath signedOpA;
    SignedDataPath signedOpB;

    signedOpA = opA;
    signedOpB = opB;

    case( cond )
        COND_EQ:  ce = ( opA == opB );
        COND_NE:  ce = ( opA != opB );
        COND_LT:  ce = ( signedOpA < signedOpB );
        COND_LTU: ce = ( opA < opB );
        COND_GE:  ce = ( signedOpA >= signedOpB );
        COND_GEU: ce = ( opA >= opB );

        // AL 常時（無条件） -
        COND_AL: ce = 1;

        default:
            ce = 1;
    endcase

    return ce;

endfunction

//
// 実行ステージ
//

module IntegerExecutionStage(
    IntegerExecutionStageIF.ThisStage port,
    IntegerRegisterReadStageIF.NextStage prev,
    BypassNetworkIF.IntegerExecutionStage bypass,
    RecoveryManagerIF.IntegerExecutionStage recovery,
    ControllerIF.IntegerExecutionStage ctrl,
    DebugIF.IntegerExecutionStage debug
);

    IntegerExecutionStageRegPath pipeReg [INT_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif

    // --- Pipeline registers
    always_ff@(posedge port.clk)   // synchronous rst
    begin
        if (port.rst) begin
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                pipeReg[i].valid <= FALSE;
            end
        end
        else if(!ctrl.backEnd.stall) begin  // write data
            pipeReg <= prev.nextStage;
        end
    end

    // Pipeline control
    logic stall, clear;
    logic flush[ INT_ISSUE_WIDTH ];

    IntIssueQueueEntry iqData[INT_ISSUE_WIDTH];
    IntOpInfo  intOpInfo [ INT_ISSUE_WIDTH ];
    BranchPred bPred [ INT_ISSUE_WIDTH ];
    AddrPath pc [ INT_ISSUE_WIDTH ];

    PRegDataPath fuOpA [ INT_ISSUE_WIDTH ];
    PRegDataPath fuOpB [ INT_ISSUE_WIDTH ];
    PRegDataPath dataOut [ INT_ISSUE_WIDTH ];

    // Condition
    logic isCondEnabled [ INT_ISSUE_WIDTH ];

    // ALU
    DataPath aluDataOut [ INT_ISSUE_WIDTH ];
    IntALU_Code aluCode [ INT_ISSUE_WIDTH ];

    for ( genvar i = 0; i < INT_ISSUE_WIDTH; i++ ) begin : BlockALU
        IntALU intALU(
            .aluCode ( aluCode[i] ),
            .fuOpA_In ( fuOpA[i].data ),
            .fuOpB_In ( fuOpB[i].data ),
            .aluDataOut ( aluDataOut[i] )
        );
    end

    // Shifter
    ShiftOperandType shiftOperandType [ INT_ISSUE_WIDTH ];
    RISCV_IntOperandImmShift shiftImmIn [ INT_ISSUE_WIDTH ];
    DataPath shiftDataOut [ INT_ISSUE_WIDTH ];
    logic shiftCarryOut [ INT_ISSUE_WIDTH ];

    for ( genvar i = 0; i < INT_ISSUE_WIDTH; i++ ) begin : BlockShifter
        Shifter shifter(
            .shiftOperandType( shiftOperandType[i] ),
            .shiftType( shiftImmIn[i].shiftType ),
            .immShiftAmount( shiftImmIn[i].shift ),
            .regShiftAmount( fuOpB[i][SHIFT_AMOUNT_BIT_SIZE-1:0] ),
            .dataIn( fuOpA[i].data ),
            .carryIn( 1'b0 ),
            .dataOut( shiftDataOut[i] ),
            .carryOut( shiftCarryOut[i] )
        );
    end

    // Branch
    logic isBranch [ INT_ISSUE_WIDTH ];
    logic isJump [ INT_ISSUE_WIDTH ];
    logic brTaken  [ INT_ISSUE_WIDTH ];
    BranchResult brResult [ INT_ISSUE_WIDTH ];
    logic predMiss [ INT_ISSUE_WIDTH ];
    logic regValid [ INT_ISSUE_WIDTH ];

    IntOpSubInfo intSubInfo[ INT_ISSUE_WIDTH ];
    BrOpSubInfo  brSubInfo[ INT_ISSUE_WIDTH ];

    always_comb begin
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            iqData[i] = pipeReg[i].intQueueData;
            intOpInfo[i] = iqData[i].intOpInfo;
            intSubInfo[i] = intOpInfo[i].intSubInfo;
            brSubInfo[i] = intOpInfo[i].brSubInfo;
            pc[i] = ToAddrFromPC(iqData[i].pc);
            flush[i] = SelectiveFlushDetector(
                        recovery.toRecoveryPhase,
                        recovery.flushRangeHeadPtr,
                        recovery.flushRangeTailPtr,
                        iqData[i].activeListPtr
                        );

            // オペランド
            fuOpA[i] = ( pipeReg[i].bCtrl.rA.valid ? bypass.intSrcRegDataOutA[i] : pipeReg[i].operandA );
            fuOpB[i] = ( pipeReg[i].bCtrl.rB.valid ? bypass.intSrcRegDataOutB[i] : pipeReg[i].operandB );

            // Condition
            isCondEnabled[i] = IsConditionEnabledInt( iqData[i].cond, fuOpA[i].data, fuOpB[i].data );

            // Shifter
            shiftOperandType[i] = intSubInfo[i].shiftType;
            shiftImmIn[i] = intSubInfo[i].shiftIn;

            // ALU
            aluCode[i] = intSubInfo[i].aluCode;

            //
            // データアウト
            //
            unique case ( iqData[i].opType )
            INT_MOP_TYPE_ALU:       dataOut[i].data = aluDataOut[i];
            INT_MOP_TYPE_SHIFT:     dataOut[i].data = shiftDataOut[i];
            //INT_MOP_TYPE_BR, INT_MOP_TYPE_RIJ :        dataOut[i].data = ToPC_FromAddr(pc[i] + PC_OPERAND_OFFSET);
            INT_MOP_TYPE_BR, INT_MOP_TYPE_RIJ :        dataOut[i].data = pc[i] + PC_OPERAND_OFFSET;
            default: /* select */  dataOut[i].data = ( isCondEnabled[i] ? fuOpA[i].data : fuOpB[i].data );
            endcase

            // If invalid registers are read, regValid is negated and this op must be replayed.
            regValid[i] =
                (intSubInfo[i].operandTypeA != OOT_REG || fuOpA[i].valid ) &&
                (intSubInfo[i].operandTypeB != OOT_REG || fuOpB[i].valid );
            dataOut[i].valid = regValid[i];


            //
            // --- Bypass
            //
            bypass.intCtrlIn[i] = pipeReg[i].bCtrl;
            bypass.intDstRegDataOut[i] = dataOut[i];

            //
            // --- 分岐
            //
            bPred[i] = brSubInfo[i].bPred;
            isBranch[i] = ( iqData[i].opType inside { INT_MOP_TYPE_BR, INT_MOP_TYPE_RIJ } );
            isJump[i] = 
                (iqData[i].opType == INT_MOP_TYPE_BR && iqData[i].cond == COND_AL)
                    || iqData[i].opType == INT_MOP_TYPE_RIJ;

            // 分岐orレジスタ間接分岐で，条件が有効ならTaken
            brTaken[i] = pipeReg[i].valid && isBranch[i] && isCondEnabled[i];

            // Whether this branch is conditional one or not.
            brResult[i].isCondBr = !isJump[i];
            
            // The address of a branch.
            brResult[i].brAddr = ToPC_FromAddr(pc[i]);

            // ターゲットアドレスの計算
            if( brTaken[i] ) begin
                brResult[i].nextAddr =
                    ToPC_FromAddr(
                        (iqData[i].opType == INT_MOP_TYPE_BR) ?  
                            (pc[i] + ExtendBranchDisplacement(brSubInfo[i].brDisp) ) : // 方向分岐 
                            (AddJALR_TargetOffset(fuOpA[i].data, brSubInfo[i].brDisp) // レジスタ間接分岐 
                        ) 
                    );
            end
            else begin
                brResult[i].nextAddr = ToPC_FromAddr(pc[i] + INSN_BYTE_WIDTH);
            end
            brResult[i].execTaken = brTaken[i];
            brResult[i].predTaken = bPred[i].predTaken;
            brResult[i].valid = isBranch[i] && pipeReg[i].valid && regValid[i];
            brResult[i].globalHistory = bPred[i].globalHistory;
            brResult[i].phtPrevValue = bPred[i].phtPrevValue;
                    
            // 予測ミス判定
            predMiss[i] =
                brResult[i].valid &&
                (
                     (bPred[i].predTaken != brTaken[i]) ||
                     (brTaken[i] == TRUE &&
                      bPred[i].predAddr != brResult[i].nextAddr)
                );

            brResult[i].mispred = predMiss[i];
        end
    end

    //
    // --- Pipeline レジスタ書き込み
    //
    IntegerRegisterWriteStageRegPath nextStage [ INT_ISSUE_WIDTH ];

    always_comb begin
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            `ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].opId = pipeReg[i].opId;
            `endif

            nextStage[i].intQueueData = pipeReg[i].intQueueData;

            // リセットorフラッシュ時はNOP
            nextStage[i].valid =
                (stall || clear || port.rst || flush[i]) ? FALSE : pipeReg[i].valid;

            nextStage[i].dataOut = dataOut[i];

            nextStage[i].brResult    = brResult[i];
            nextStage[i].brMissPred  = predMiss[i];
        end

        // Output
        port.nextStage = nextStage;

        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            debug.intExReg[i].valid = pipeReg[i].valid;
            debug.intExReg[i].flush = flush[i];
            debug.intExReg[i].opId = pipeReg[i].opId;
`ifdef RSD_FUNCTIONAL_SIMULATION
            debug.intExReg[i].dataOut = dataOut[i];
            debug.intExReg[i].fuOpA   = fuOpA[i].data;
            debug.intExReg[i].fuOpB   = fuOpB[i].data;
            debug.intExReg[i].aluCode  = aluCode[i];
            debug.intExReg[i].opType  = iqData[i].opType;
            debug.intExReg[i].brPredMiss = predMiss[i];
`endif
        end
    `endif
end

endmodule : IntegerExecutionStage
