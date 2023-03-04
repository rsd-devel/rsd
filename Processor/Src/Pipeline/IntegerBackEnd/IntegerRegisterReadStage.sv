// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for register read.
//

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import PipelineTypes::*;
import DebugTypes::*;

//
// --- Immediate
//
function automatic DataPath RISCV_OpImm(
    RISCV_IntOperandImmShift intOperandImm
);

    // Todo: optimize
    DataPath result;
    case( intOperandImm.immType )
        //RISCV_IMM_I : begin
        default : begin
            result   = { {12{intOperandImm.imm[19]}}, intOperandImm.imm };
        end
        RISCV_IMM_U : begin
            result   = { intOperandImm.imm, 12'h0 };
        end
    endcase // immType
    return result;
endfunction : RISCV_OpImm


//
// --- オペランドの選択
//

function automatic DataPath SelectOperandIntReg(
input
    OpOperandType opType, DataPath regV, DataPath immV, DataPath pcV
);
    case( opType )
    default:    // OOT_REG
        return regV;
    OOT_IMM:
        return immV;
    OOT_PC:
        return pcV;
    endcase
endfunction

//
// --- Integer Register Read Stage
//
module IntegerRegisterReadStage(
    IntegerRegisterReadStageIF.ThisStage port,
    IntegerIssueStageIF.NextStage prev,
    RegisterFileIF.IntegerRegisterReadStage registerFile,
    BypassNetworkIF.IntegerRegisterReadStage bypass,
    RecoveryManagerIF.IntegerRegisterReadStage recovery,
    ControllerIF.IntegerRegisterReadStage ctrl,
    DebugIF.IntegerRegisterReadStage debug
);

    // --- Pipeline registers
    IntegerRegisterReadStageRegPath pipeReg [INT_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif

    always_ff@(posedge port.clk)   // synchronous rst
    begin
        if (port.rst) begin
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                pipeReg[i].valid <= FALSE;
            end
        end
        else if(!ctrl.backEnd.stall) begin              // write data
            pipeReg <= prev.nextStage;
        end
    end

    // Operand
    DataPath immOut [ INT_ISSUE_WIDTH ];
    AddrPath pc [ INT_ISSUE_WIDTH ];
    PRegDataPath operandA [ INT_ISSUE_WIDTH ];
    PRegDataPath operandB [ INT_ISSUE_WIDTH ];

    // Pipeline controll
    logic stall, clear;
    logic flush[ INT_ISSUE_WIDTH ];
    IntIssueQueueEntry iqData[INT_ISSUE_WIDTH];
    IntOpSubInfo intSubInfo[INT_ISSUE_WIDTH];
    BrOpSubInfo brSubInfo[INT_ISSUE_WIDTH];
    OpSrc opSrc[INT_ISSUE_WIDTH];
    OpDst opDst[INT_ISSUE_WIDTH];
    IntegerExecutionStageRegPath nextStage[INT_ISSUE_WIDTH];

    always_comb begin
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            iqData[i] = pipeReg[i].intQueueData;
            intSubInfo[i] = iqData[i].intOpInfo.intSubInfo;
            brSubInfo[i] = iqData[i].intOpInfo.brSubInfo;
            opSrc[i] = iqData[i].opSrc;
            opDst[i] = iqData[i].opDst;
            pc[i] = ToAddrFromPC(iqData[i].pc);

            //
            // To the register file.
            //
            registerFile.intSrcRegNumA[i] = opSrc[i].phySrcRegNumA;
            registerFile.intSrcRegNumB[i] = opSrc[i].phySrcRegNumB;

            //
            // To the bypass network.
            // ストールやフラッシュの制御は，Bypass モジュールの内部で
            // コントローラの信号を参照して行われている
            //
            bypass.intPhySrcRegNumA[i] = opSrc[i].phySrcRegNumA;
            bypass.intPhySrcRegNumB[i] = opSrc[i].phySrcRegNumB;

            bypass.intWriteReg[i]  = opDst[i].writeReg & pipeReg[i].valid;
            bypass.intPhyDstRegNum[i] = opDst[i].phyDstRegNum;
            bypass.intReadRegA[i] = ( intSubInfo[i].operandTypeA == OOT_REG ) || ( brSubInfo[i].operandTypeA == OOT_REG );
            bypass.intReadRegB[i] = ( intSubInfo[i].operandTypeB == OOT_REG ) || ( brSubInfo[i].operandTypeA == OOT_REG );

            //
            // --- オペランド選択
            //
            immOut[i] = RISCV_OpImm(
                .intOperandImm( intSubInfo[i].shiftIn )
            );
            operandA[i].data = SelectOperandIntReg(
                intSubInfo[i].operandTypeA,
                registerFile.intSrcRegDataA[i].data,
                immOut[i],
                pc[i]
            );
            operandB[i].data = SelectOperandIntReg(
                intSubInfo[i].operandTypeB,
                registerFile.intSrcRegDataB[i].data,
                immOut[i],
                pc[i]
            );
            operandA[i].valid = (intSubInfo[i].operandTypeA != OOT_REG || registerFile.intSrcRegDataA[i].valid);
            operandB[i].valid = (intSubInfo[i].operandTypeB != OOT_REG || registerFile.intSrcRegDataB[i].valid);

            //
            // --- Pipeline ラッチ書き込み
            //
            `ifndef RSD_DISABLE_DEBUG_REGISTER
                nextStage[i].opId = pipeReg[i].opId;
            `endif

            // リセットorフラッシュ時はNOP
            flush[i] = SelectiveFlushDetector(
                        recovery.toRecoveryPhase,
                        recovery.flushRangeHeadPtr,
                        recovery.flushRangeTailPtr,
                        recovery.flushAllInsns,
                        iqData[i].activeListPtr
                        );
            nextStage[i].valid =
                (stall || clear || port.rst || flush[i]) ? FALSE : pipeReg[i].valid;

            // レジスタ値&フラグ
            nextStage[i].operandA = operandA[i];
            nextStage[i].operandB = operandB[i];

            // Issue queue data
            nextStage[i].intQueueData = pipeReg[i].intQueueData;

            // バイパス制御
            nextStage[i].bCtrl = bypass.intCtrlOut[i];

        end
        port.nextStage = nextStage;

        // Debug Register
        `ifndef RSD_DISABLE_DEBUG_REGISTER
            for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
                debug.intRrReg[i].valid = pipeReg[i].valid;
                debug.intRrReg[i].flush = flush[i];
                debug.intRrReg[i].opId = pipeReg[i].opId;
            end
        `endif
    end
endmodule : IntegerRegisterReadStage