// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for register read.
//


import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import PipelineTypes::*;
import DebugTypes::*;

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE

module ComplexIntegerRegisterReadStage(
    ComplexIntegerRegisterReadStageIF.ThisStage port,
    ComplexIntegerIssueStageIF.NextStage prev,
    RegisterFileIF.ComplexIntegerRegisterReadStage registerFile,
    BypassNetworkIF.ComplexIntegerRegisterReadStage bypass,
    RecoveryManagerIF.ComplexIntegerRegisterReadStage recovery,
    ControllerIF.ComplexIntegerRegisterReadStage ctrl,
    DebugIF.ComplexIntegerRegisterReadStage debug
);

    // --- Pipeline registers
    ComplexIntegerRegisterReadStageRegPath pipeReg[COMPLEX_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif

    always_ff@( posedge port.clk )   // synchronous rst
    begin
        if (port.rst) begin
            for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
                pipeReg[i].valid <= '0;
            end
        end
        else if(!ctrl.backEnd.stall) begin              // write data
            pipeReg <= prev.nextStage;
        end
    end



    // Pipeline controll
    logic stall, clear;
    logic flush[ COMPLEX_ISSUE_WIDTH ];
    ComplexIssueQueueEntry iqData[COMPLEX_ISSUE_WIDTH];
    MulOpSubInfo mulOpInfo[COMPLEX_ISSUE_WIDTH];
    OpSrc opSrc[COMPLEX_ISSUE_WIDTH];
    OpDst opDst[COMPLEX_ISSUE_WIDTH];
    ComplexIntegerExecutionStageRegPath nextStage[COMPLEX_ISSUE_WIDTH];

    always_comb begin
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            iqData[i] = pipeReg[i].complexQueueData;
            mulOpInfo[i] = iqData[i].complexOpInfo.mulSubInfo;
            opSrc[i] = iqData[i].opSrc;
            opDst[i] = iqData[i].opDst;

            //
            // To the register file.
            //

            registerFile.complexSrcRegNumA[i] = opSrc[i].phySrcRegNumA;
            registerFile.complexSrcRegNumB[i] = opSrc[i].phySrcRegNumB;

            //
            // To the bypass network.
            // ストールやフラッシュの制御は，Bypass モジュールの内部で
            // コントローラの信号を参照して行われている
            //
            bypass.complexPhySrcRegNumA[i] = opSrc[i].phySrcRegNumA;
            bypass.complexPhySrcRegNumB[i] = opSrc[i].phySrcRegNumB;

            bypass.complexWriteReg[i]  = opDst[i].writeReg & pipeReg[i].valid;
            bypass.complexPhyDstRegNum[i] = opDst[i].phyDstRegNum;

            // Complex Integer では、operandTypeはOOT_REGしか未サポート
            bypass.complexReadRegA[i] = TRUE;
            bypass.complexReadRegB[i] = TRUE;
            //bypass.complexReadRegA[i] = ( iqData[i].complexOpInfo.operandTypeA == OOT_REG );
            //bypass.complexReadRegB[i] = ( iqData[i].complexOpInfo.operandTypeB == OOT_REG );

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

            nextStage[i].replay = pipeReg[i].replay;

            // divがこのステージ内でフラッシュされた場合：
            // Dividerへの要求予約を取り消し，
            // IQからdivを発行できるようにする 
            if (iqData[i].opType == COMPLEX_MOP_TYPE_DIV) begin
                nextStage[i].isFlushed = pipeReg[i].valid && flush[i];
            end
            else begin
                nextStage[i].isFlushed = FALSE;
            end
            
            // レジスタ値&フラグ
            nextStage[i].operandA = registerFile.complexSrcRegDataA[i];
            nextStage[i].operandB = registerFile.complexSrcRegDataB[i];
`ifdef RSD_ENABLE_VECTOR_PATH
            nextStage[i].vecOperandA = registerFile.complexSrcVecDataA[i];
            nextStage[i].vecOperandB = registerFile.complexSrcVecDataB[i];
`endif
            // Issue queue data
            nextStage[i].complexQueueData = pipeReg[i].complexQueueData;

            // バイパス制御
            nextStage[i].bCtrl = bypass.complexCtrlOut[i];

        end
        port.nextStage = nextStage;

        // Debug Register
        `ifndef RSD_DISABLE_DEBUG_REGISTER
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            debug.complexRrReg[i].valid = pipeReg[i].valid;
            debug.complexRrReg[i].flush = flush[i];
            debug.complexRrReg[i].opId = pipeReg[i].opId;
        end
        `endif
    end
endmodule : ComplexIntegerRegisterReadStage

`endif
