// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// FP Execution stage
//
// 浮動小数点演算の実行を行う
// FP_EXEC_STAGE_DEPTH 段にパイプライン化されている
//

`include "BasicMacros.sv"
import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import PipelineTypes::*;
import DebugTypes::*;

`ifdef RSD_MARCH_FP_PIPE

module FPExecutionStage(
    FPExecutionStageIF.ThisStage port,
    FPRegisterReadStageIF.NextStage prev,
    FPDivSqrtUnitIF.FPExecutionStage fpDivSqrtUnit,
    SchedulerIF.FPExecutionStage scheduler,
    BypassNetworkIF.FPExecutionStage bypass,
    RecoveryManagerIF.FPExecutionStage recovery,
    ControllerIF.FPExecutionStage ctrl,
    DebugIF.FPExecutionStage debug,
    CSR_UnitIF.FPExecutionStage csrUnit
);
    // Pipeline control
    logic stall, clear;
    logic flush[ FP_ISSUE_WIDTH ][ FP_EXEC_STAGE_DEPTH ];

    `RSD_STATIC_ASSERT(FP_ISSUE_WIDTH == FP_DIVSQRT_ISSUE_WIDTH, "These muse be same");

    //
    // --- Local Pipeline Register
    //

    // 複数サイクルにわたる FPExecutionStage 内で
    // 使用するパイプラインレジスタ
    typedef struct packed // LocalPipeReg
    {

`ifndef RSD_DISABLE_DEBUG_REGISTER
        OpId      opId;
`endif

        logic valid;  // Valid flag. If this is 0, its op is treated as NOP.
        logic regValid; // Valid flag of a destination register.
        FPIssueQueueEntry fpQueueData;
    } LocalPipeReg;

    LocalPipeReg localPipeReg [ FP_ISSUE_WIDTH ][ FP_EXEC_STAGE_DEPTH-1 ];
    LocalPipeReg nextLocalPipeReg [ FP_ISSUE_WIDTH ][ FP_EXEC_STAGE_DEPTH-1 ];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin
            for (int j = 0; j < FP_EXEC_STAGE_DEPTH-1; j++) begin
                localPipeReg[i][j] <= '0;
            end
        end
    end
`endif

    always_ff@( posedge port.clk ) begin
        if (port.rst || clear) begin
            for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin
                for ( int j = 0; j < FP_EXEC_STAGE_DEPTH-1; j++ ) begin
                    localPipeReg[i][j].valid <= '0;
                    localPipeReg[i][j].regValid <= '0;
                end
            end
        end
        else if(!ctrl.backEnd.stall) begin   // write data
            localPipeReg <= nextLocalPipeReg;
        end
    end


    //
    // --- Pipeline Register
    //

    // FPRegisterReadStage との境界にあるパイプラインレジスタ
    FPExecutionStageRegPath pipeReg[FP_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif
    always_ff@(posedge port.clk)   // synchronous rst
    begin
        if (port.rst) begin
            for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin
                pipeReg[i].valid <= '0;
            end
        end
        else if(!ctrl.backEnd.stall) begin   // write data
            pipeReg <= prev.nextStage;
        end
    end

    //
    // Signals
    //
    FPIssueQueueEntry iqData        [ FP_ISSUE_WIDTH ] [FP_EXEC_STAGE_DEPTH];
    FPOpInfo          fpOpInfo [ FP_ISSUE_WIDTH ];
    FPMicroOpSubType opType [FP_ISSUE_WIDTH];
    FPU_Code fpuCode [FP_ISSUE_WIDTH];
    Rounding_Mode rm [FP_ISSUE_WIDTH];
    Rounding_Mode stRM [FP_ISSUE_WIDTH];
    Rounding_Mode dynRM [FP_ISSUE_WIDTH];

    PRegDataPath  fuOpA    [ FP_ISSUE_WIDTH ];
    PRegDataPath  fuOpB    [ FP_ISSUE_WIDTH ];
    PRegDataPath  fuOpC    [ FP_ISSUE_WIDTH ];
    logic         regValid [ FP_ISSUE_WIDTH ];
    PRegDataPath  dataOut  [ FP_ISSUE_WIDTH ];
    FFlags_Path   fflagsOut[ FP_ISSUE_WIDTH ];

    DataPath  addDataOut     [ FP_ISSUE_WIDTH ];
    DataPath  mulDataOut     [ FP_ISSUE_WIDTH ];
    DataPath  fmaDataOut     [ FP_ISSUE_WIDTH ];
    DataPath  otherDataOut   [ FP_ISSUE_WIDTH ];

    FFlags_Path   addFFlagsOut [ FP_ISSUE_WIDTH ];
    FFlags_Path   mulFFlagsOut [ FP_ISSUE_WIDTH ];
    FFlags_Path   fmaFFlagsOut [ FP_ISSUE_WIDTH ];
    FFlags_Path   otherFFlagsOut [ FP_ISSUE_WIDTH ];



    //
    // Divider/Sqrt Unit
    //
    logic isDivSqrt         [ FP_ISSUE_WIDTH ]; 

    for ( genvar i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
        FP32PipelinedAdder #(
            .PIPELINE_DEPTH(FP_EXEC_STAGE_DEPTH)
        ) fpAdder (
            .clk (port.clk),
            .lhs ( fuOpA[i].data ),
            .rhs ( fpuCode[i] == FC_SUB ? {~fuOpB[i].data[31], fuOpB[i].data[30:0]} : fuOpB[i].data ),
            //.rm (rm[i]),
            .result ( addDataOut[i] )
            //.fflags ( addFFlagsOut[i])
        );
        
        FP32PipelinedMultiplier #(
            .PIPELINE_DEPTH(FP_EXEC_STAGE_DEPTH)
        ) fpMultiplier (
            .clk (port.clk),
            .lhs ( fuOpA[i].data ),
            .rhs ( fuOpB[i].data ),
            //.rm (rm[i]),
            .result ( mulDataOut[i] )
            //.fflags ( mulFFlagsOut[i])
        );

        FP32PipelinedFMA fpFMA (
            .clk (port.clk),
            .mullhs ( fpuCode[i] inside {FC_FNMSUB, FC_FNMADD} ? {~fuOpA[i].data[31], fuOpA[i].data[30:0]} : fuOpA[i].data),
            .mulrhs ( fuOpB[i].data ),
            .addend ( fpuCode[i] inside {FC_FMSUB, FC_FNMADD} ? {~fuOpC[i].data[31], fuOpC[i].data[30:0]} : fuOpC[i].data ),
            //.rm (rm[i]),
            .result ( fmaDataOut[i] )
            //.fflags ( fmaFFlagsOut[i])
        );
        
        FP32PipelinedOther #(
            .PIPELINE_DEPTH(FP_EXEC_STAGE_DEPTH)
        ) fpOther (
            .clk (port.clk),
            .lhs ( fuOpA[i].data ),
            .rhs ( fuOpB[i].data ),
            .fpuCode (fpuCode[i]),
            .rm (rm[i]),
            .result ( otherDataOut[i] ),
            .fflags ( otherFFlagsOut[i])
        );
    end

    always_comb begin
        // FP Div/Sqrt Unit
        for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin

            fpDivSqrtUnit.dataInA[i] = fuOpA[i].data;
            fpDivSqrtUnit.dataInB[i] = fuOpB[i].data;

            // DIV or SQRT
            fpDivSqrtUnit.is_divide[i] = fpOpInfo[i].fpuCode == FC_DIV;
            fpDivSqrtUnit.rm[i] = rm[i];

            isDivSqrt[i] =  
                pipeReg[i].fpQueueData.fpOpInfo.opType inside {FP_MOP_TYPE_DIV, FP_MOP_TYPE_SQRT};

            // Request to the divider/sqrter
            // NOT make a request when below situation
            // 1) When any operands of inst. are invalid
            // 2) When the divider/sqrter is waiting for the instruction
            //    to receive the result of the divider/sqrter
            fpDivSqrtUnit.Req[i] = 
                fpDivSqrtUnit.Reserved[i] && 
                pipeReg[i].valid && isDivSqrt[i] && 
                fuOpA[i].valid && fuOpB[i].valid;

            if (fpDivSqrtUnit.Finished[i] &&
                localPipeReg[i][FP_EXEC_STAGE_DEPTH-2].valid &&
                (localPipeReg[i][FP_EXEC_STAGE_DEPTH-2].fpQueueData.fpOpInfo.opType inside {FP_MOP_TYPE_DIV, FP_MOP_TYPE_SQRT})&& 
                localPipeReg[i][FP_EXEC_STAGE_DEPTH-2].regValid
            ) begin 
                // Div/Sqrt Unitから結果を取得できたので，
                // IQからの発行を許可する 
                fpDivSqrtUnit.Release[i] = TRUE;
            end
            else begin
                fpDivSqrtUnit.Release[i] = FALSE;
            end
        end
    end

    always_comb begin
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            iqData[i][0] = pipeReg[i].fpQueueData;
            fpOpInfo[i]  = pipeReg[i].fpQueueData.fpOpInfo;
            opType[i]    = fpOpInfo[i].opType;
            fpuCode[i]   = fpOpInfo[i].fpuCode;
            stRM[i]      = fpOpInfo[i].rm;
            dynRM[i]     = csrUnit.frm;
            if (stRM[i] == RM_DYN) begin
                rm[i] = dynRM[i];
            end
            else begin
                rm[i] = stRM[i];
            end
            

            flush[i][0] = SelectiveFlushDetector(
                recovery.toRecoveryPhase,
                recovery.flushRangeHeadPtr,
                recovery.flushRangeTailPtr,
                recovery.flushAllInsns, 
                pipeReg[i].fpQueueData.activeListPtr
            );

            // From local pipeline 
            for (int j = 1; j < FP_EXEC_STAGE_DEPTH; j++) begin 
                iqData[i][j] = localPipeReg[i][j-1].fpQueueData; 
                flush[i][j] = SelectiveFlushDetector( 
                    recovery.toRecoveryPhase, 
                    recovery.flushRangeHeadPtr, 
                    recovery.flushRangeTailPtr, 
                    recovery.flushAllInsns, 
                    localPipeReg[i][j-1].fpQueueData.activeListPtr 
                );
            end

            // オペランド
            fuOpA[i] = ( pipeReg[i].bCtrl.rA.valid ? bypass.fpSrcRegDataOutA[i] : pipeReg[i].operandA );
            fuOpB[i] = ( pipeReg[i].bCtrl.rB.valid ? bypass.fpSrcRegDataOutB[i] : pipeReg[i].operandB );
            fuOpC[i] = ( pipeReg[i].bCtrl.rC.valid ? bypass.fpSrcRegDataOutC[i] : pipeReg[i].operandC );
           

            
            //
            // --- regValid
            //

            // If invalid registers are read, regValid is negated and this op must be replayed.
            regValid[i] =
                (fpOpInfo[i].operandTypeA != OOT_REG || fuOpA[i].valid ) &&
                (fpOpInfo[i].operandTypeB != OOT_REG || fuOpB[i].valid ) &&
                (fpOpInfo[i].operandTypeC != OOT_REG || fuOpC[i].valid );
            

            //
            // --- データアウト(実行ステージの最終段の処理)
            //
            dataOut[i].valid
                = localPipeReg[i][FP_EXEC_STAGE_DEPTH-2].regValid;
            // TODO fflagsをちゃんと実装
            unique case ( localPipeReg[i][FP_EXEC_STAGE_DEPTH-2].fpQueueData.fpOpInfo.opType )
                FP_MOP_TYPE_ADD: begin
                    dataOut[i].data = addDataOut[i];
                    //fflagsData[i] = addFFlagsOut[i];
                    fflagsOut[i] = '0;
                end
                FP_MOP_TYPE_MUL: begin
                    dataOut[i].data = mulDataOut[i];
                    //fflagsData[i] = mulFFlagsOut[i];
                    fflagsOut[i] = '0;
                end
                FP_MOP_TYPE_DIV, FP_MOP_TYPE_SQRT: begin
                    dataOut[i].data = fpDivSqrtUnit.DataOut[i];
                    //fflagsData[i] = fpDivSqrtUnit.FFlagsOut[i];
                    fflagsOut[i] = '0;
                end 
                FP_MOP_TYPE_FMA: begin
                    dataOut[i].data = fmaDataOut[i];
                    //fflagsData[i] = fmaFFlagsOut[i];
                    fflagsOut[i] = '0;
                end
                default: begin /* FP_MOP_TYPE_OTHER */
                    dataOut[i].data = otherDataOut[i];
                    fflagsOut[i] = otherFFlagsOut[i];
                end
            endcase

            //
            // --- Bypass
            //

            // 最初のステージで出力
            bypass.fpCtrlIn[i] = pipeReg[i].bCtrl;

            // 最後のステージで出力
            bypass.fpDstRegDataOut[i] = dataOut[i];

            //
            // --- Replay
            //

            // ISから3ステージ後=EX1ステージでReplayを出力
            // このとき、localPipeReg[lane][0]のデータを使う
            scheduler.fpRecordEntry[i] =
                !stall &&
                !clear &&
                !flush[i][1] &&
                localPipeReg[i][0].valid &&
                !localPipeReg[i][0].regValid;
            scheduler.fpRecordData[i] =
                localPipeReg[i][0].fpQueueData;
        end
    end

    //
    // --- Pipeline レジスタ書き込み
    //
    FPRegisterWriteStageRegPath nextStage [ FP_ISSUE_WIDTH ];

    always_comb begin
        // Local Pipeline Register
        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextLocalPipeReg[i][0].opId = pipeReg[i].opId;
`endif

            nextLocalPipeReg[i][0].valid = flush[i][0] ? FALSE : pipeReg[i].valid;
            nextLocalPipeReg[i][0].fpQueueData = pipeReg[i].fpQueueData;

            // Reg valid of local pipeline 
            if (isDivSqrt[i]) begin
                nextLocalPipeReg[i][0].regValid = 
                    pipeReg[i].replay && (fpDivSqrtUnit.Finished[i]);
            end
            else begin
                nextLocalPipeReg[i][0].regValid = regValid[i];
            end
            

            for (int j = 1; j < FP_EXEC_STAGE_DEPTH-1; j++) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
                nextLocalPipeReg[i][j].opId = localPipeReg[i][j-1].opId;
`endif 
                nextLocalPipeReg[i][j].valid = flush[i][j] ? FALSE : localPipeReg[i][j-1].valid;
                nextLocalPipeReg[i][j].regValid = localPipeReg[i][j-1].regValid; 
                nextLocalPipeReg[i][j].fpQueueData = localPipeReg[i][j-1].fpQueueData;
            end 
        end

        // To FPRegisterWriteStage
        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].opId
                = localPipeReg[i][FP_EXEC_STAGE_DEPTH-2].opId;
`endif

            nextStage[i].fpQueueData
                = localPipeReg[i][FP_EXEC_STAGE_DEPTH-2].fpQueueData;
            // TODO implment fflags
            nextStage[i].fflagsOut = fflagsOut[i];

            // リセットorフラッシュ時はNOP
            nextStage[i].valid =
                (stall || clear || port.rst || flush[i][FP_EXEC_STAGE_DEPTH-1]) ? FALSE : localPipeReg[i][FP_EXEC_STAGE_DEPTH-2].valid;

            nextStage[i].dataOut = dataOut[i];
        end

        port.nextStage = nextStage;

`ifndef RSD_DISABLE_DEBUG_REGISTER
        // Debug Register
        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            debug.fpExReg[i].valid[0] = pipeReg[i].valid;
            debug.fpExReg[i].flush[0] = flush[i][0];
            debug.fpExReg[i].opId[0] = pipeReg[i].opId;
            for ( int j = 1; j < FP_EXEC_STAGE_DEPTH; j++ ) begin
                debug.fpExReg[i].valid[j] = localPipeReg[i][j-1].valid;
                debug.fpExReg[i].opId[j] = localPipeReg[i][j-1].opId;
                debug.fpExReg[i].flush[j] = flush[i][j];
            end
`ifdef RSD_FUNCTIONAL_SIMULATION
            debug.fpExReg[i].dataOut = dataOut[i];
            debug.fpExReg[i].fuOpA   = fuOpA[i];
            debug.fpExReg[i].fuOpB   = fuOpB[i];
            debug.fpExReg[i].fuOpC   = fuOpC[i];
`endif
        end
`endif
    end

endmodule : FPExecutionStage

`endif
