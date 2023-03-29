// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for register read.
//


import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import PipelineTypes::*;
import DebugTypes::*;

`ifdef RSD_MARCH_FP_PIPE

module FPRegisterReadStage(
    FPRegisterReadStageIF.ThisStage port,
    FPIssueStageIF.NextStage prev,
    RegisterFileIF.FPRegisterReadStage registerFile,
    BypassNetworkIF.FPRegisterReadStage bypass,
    RecoveryManagerIF.FPRegisterReadStage recovery,
    ControllerIF.FPRegisterReadStage ctrl,
    DebugIF.FPRegisterReadStage debug
);

    // --- Pipeline registers
    FPRegisterReadStageRegPath pipeReg[FP_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif

    always_ff@( posedge port.clk )   // synchronous rst
    begin
        if (port.rst) begin
            for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin
                pipeReg[i].valid <= '0;
            end
        end
        else if(!ctrl.backEnd.stall) begin              // write data
            pipeReg <= prev.nextStage;
        end
    end



    // Pipeline controll
    logic stall, clear;
    logic flush[ FP_ISSUE_WIDTH ];
    FPIssueQueueEntry iqData[FP_ISSUE_WIDTH];
    FPOpInfo          fpOpInfo [FP_ISSUE_WIDTH];
    
    PRegDataPath operandA [ FP_ISSUE_WIDTH ];
    PRegDataPath operandB [ FP_ISSUE_WIDTH ];
    PRegDataPath operandC [ FP_ISSUE_WIDTH ];
    OpSrc opSrc[FP_ISSUE_WIDTH];
    OpDst opDst[FP_ISSUE_WIDTH];
    FPExecutionStageRegPath nextStage[FP_ISSUE_WIDTH];

    always_comb begin
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            iqData[i] = pipeReg[i].fpQueueData;
            fpOpInfo[i]  = pipeReg[i].fpQueueData.fpOpInfo;
            opSrc[i] = iqData[i].opSrc;
            opDst[i] = iqData[i].opDst;

            //
            // To the register file.
            //

            registerFile.fpSrcRegNumA[i] = opSrc[i].phySrcRegNumA;
            registerFile.fpSrcRegNumB[i] = opSrc[i].phySrcRegNumB;
            registerFile.fpSrcRegNumC[i] = opSrc[i].phySrcRegNumC;

            //
            // To the bypass network.
            // ストールやフラッシュの制御は，Bypass モジュールの内部で
            // コントローラの信号を参照して行われている
            //
            bypass.fpPhySrcRegNumA[i] = opSrc[i].phySrcRegNumA;
            bypass.fpPhySrcRegNumB[i] = opSrc[i].phySrcRegNumB;
            bypass.fpPhySrcRegNumC[i] = opSrc[i].phySrcRegNumC;

            bypass.fpWriteReg[i]  = opDst[i].writeReg & pipeReg[i].valid;
            bypass.fpPhyDstRegNum[i] = opDst[i].phyDstRegNum;

            bypass.fpReadRegA[i] = fpOpInfo[i].operandTypeA == OOT_REG;
            bypass.fpReadRegB[i] = fpOpInfo[i].operandTypeB == OOT_REG;
            bypass.fpReadRegC[i] = fpOpInfo[i].operandTypeC == OOT_REG;

            operandA[i] = registerFile.fpSrcRegDataA[i];
            operandB[i] = registerFile.fpSrcRegDataB[i];
            operandC[i] = registerFile.fpSrcRegDataC[i];
            operandA[i].valid = (fpOpInfo[i].operandTypeA != OOT_REG || registerFile.fpSrcRegDataA[i].valid);
            operandB[i].valid = (fpOpInfo[i].operandTypeB != OOT_REG || registerFile.fpSrcRegDataB[i].valid);
            operandC[i].valid = (fpOpInfo[i].operandTypeC != OOT_REG || registerFile.fpSrcRegDataC[i].valid);

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
            if (iqData[i].fpOpInfo.opType inside {FP_MOP_TYPE_DIV, FP_MOP_TYPE_SQRT}) begin
                nextStage[i].isFlushed = pipeReg[i].valid && flush[i];
            end
            else begin
                nextStage[i].isFlushed = FALSE;
            end
            
            // レジスタ値&フラグ
            nextStage[i].operandA = operandA[i];
            nextStage[i].operandB = operandB[i];
            nextStage[i].operandC = operandC[i];
            
            // Issue queue data
            nextStage[i].fpQueueData = pipeReg[i].fpQueueData;

            // バイパス制御
            nextStage[i].bCtrl = bypass.fpCtrlOut[i];

        end
        port.nextStage = nextStage;

        // Debug Register
        `ifndef RSD_DISABLE_DEBUG_REGISTER
        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            debug.fpRrReg[i].valid = pipeReg[i].valid;
            debug.fpRrReg[i].flush = flush[i];
            debug.fpRrReg[i].opId = pipeReg[i].opId;
        end
        `endif
    end
endmodule : FPRegisterReadStage

`endif
