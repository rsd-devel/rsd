// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Complex Integer Execution stage
//
// 乗算/SIMD 命令の演算を行う
// COMPLEX_EXEC_STAGE_DEPTH 段にパイプライン化されている
//

`include "BasicMacros.sv"
import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import PipelineTypes::*;
import DebugTypes::*;

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE

module ComplexIntegerExecutionStage(
    ComplexIntegerExecutionStageIF.ThisStage port,
    ComplexIntegerRegisterReadStageIF.NextStage prev,
    MulDivUnitIF.ComplexIntegerExecutionStage mulDivUnit,
    SchedulerIF.ComplexIntegerExecutionStage scheduler,
    BypassNetworkIF.ComplexIntegerExecutionStage bypass,
    RecoveryManagerIF.ComplexIntegerExecutionStage recovery,
    ControllerIF.ComplexIntegerExecutionStage ctrl,
    DebugIF.ComplexIntegerExecutionStage debug
);
    // Pipeline controll
    logic stall, clear;
    logic flush[ COMPLEX_ISSUE_WIDTH ][ COMPLEX_EXEC_STAGE_DEPTH ];

    `RSD_STATIC_ASSERT(COMPLEX_ISSUE_WIDTH == MULDIV_ISSUE_WIDTH, "These muse be same");
    `RSD_STATIC_ASSERT(COMPLEX_EXEC_STAGE_DEPTH == MULDIV_STAGE_DEPTH, "These muse be same");

    //
    // --- Local Pipeline Register
    //

    // 複数サイクルにわたる ComplexIntegerExecutionStage 内で
    // 使用するパイプラインレジスタ
    typedef struct packed // LocalPipeReg
    {

`ifndef RSD_DISABLE_DEBUG_REGISTER
        OpId      opId;
`endif

        logic valid;  // Valid flag. If this is 0, its op is treated as NOP.
        logic regValid; // Valid flag of a destination register.
        ComplexIssueQueueEntry complexQueueData;
    } LocalPipeReg;

    LocalPipeReg localPipeReg [ COMPLEX_ISSUE_WIDTH ][ COMPLEX_EXEC_STAGE_DEPTH-1 ];
    LocalPipeReg nextLocalPipeReg [ COMPLEX_ISSUE_WIDTH ][ COMPLEX_EXEC_STAGE_DEPTH-1 ];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            for (int j = 0; j < COMPLEX_EXEC_STAGE_DEPTH-1; j++) begin
                localPipeReg[i][j] <= '0;
            end
        end
    end
`endif

    always_ff@( posedge port.clk ) begin
        if (port.rst || clear) begin
            for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
                for ( int j = 0; j < COMPLEX_EXEC_STAGE_DEPTH-1; j++ ) begin
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

    // ComplexIntegerRegisterReadStage との境界にあるパイプラインレジスタ
    ComplexIntegerExecutionStageRegPath pipeReg[COMPLEX_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif
    always_ff@(posedge port.clk)   // synchronous rst
    begin
        if (port.rst) begin
            for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
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
    ComplexIssueQueueEntry iqData        [ COMPLEX_ISSUE_WIDTH ] [COMPLEX_EXEC_STAGE_DEPTH];
    ComplexOpInfo          complexOpInfo [ COMPLEX_ISSUE_WIDTH ];
    MulOpSubInfo           mulSubInfo    [ COMPLEX_ISSUE_WIDTH ];
    DivOpSubInfo           divSubInfo    [ COMPLEX_ISSUE_WIDTH ];

    PRegDataPath  fuOpA    [ COMPLEX_ISSUE_WIDTH ];
    PRegDataPath  fuOpB    [ COMPLEX_ISSUE_WIDTH ];
    logic         regValid [ COMPLEX_ISSUE_WIDTH ];
    PRegDataPath  dataOut  [ COMPLEX_ISSUE_WIDTH ];



    //
    // DividerUnit
    //
    logic isDiv         [ COMPLEX_ISSUE_WIDTH ]; 
    logic finished      [ COMPLEX_ISSUE_WIDTH ];

    // For selective flush
    ActiveListIndexPath regActiveListIndex  [ COMPLEX_ISSUE_WIDTH ];
    ActiveListIndexPath nextActiveListIndex [ COMPLEX_ISSUE_WIDTH ];
    logic divReset[ COMPLEX_ISSUE_WIDTH ];

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
                regActiveListIndex[i] <= '0;
            end
        end
        else begin
            regActiveListIndex <= nextActiveListIndex;
        end
    end

    for ( genvar i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
        //`RSD_ASSERT_CLK(port.clk, !(!mulDivUnit.divFree[i] && scheduler.divIsIssued[i]), "");
    end

    always_comb begin

        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            mulDivUnit.dataInA[i] = fuOpA[i].data;
            mulDivUnit.dataInB[i] = fuOpB[i].data;

            // DIV
            mulDivUnit.divCode[i] = divSubInfo[i].divCode;

            isDiv[i] =  
                pipeReg[i].complexQueueData.opType == COMPLEX_MOP_TYPE_DIV;

            // MUL
            mulDivUnit.mulGetUpper[i] = mulSubInfo[i].mulGetUpper;
            mulDivUnit.mulCode[i] = mulSubInfo[i].mulCode;

            // DIV
            mulDivUnit.divCode[i] = divSubInfo[i].divCode;

            mulDivUnit.dataInA[i] = fuOpA[i].data;
            mulDivUnit.dataInB[i] = fuOpB[i].data;

            // Reset 条件
            divReset[i] = FALSE;
            // Dividerで処理中のdivがフラッシュされたら，Dividerの状態をFREEに変更して
            // IQからdivを発行できるようにする
            if (recovery.toRecoveryPhase) begin
                divReset[i] = SelectiveFlushDetector( 
                    recovery.toRecoveryPhase, 
                    recovery.flushRangeHeadPtr, 
                    recovery.flushRangeTailPtr, 
                    recovery.flushAllInsns,
                    regActiveListIndex[i]
                );
            end
            if (clear) begin
                divReset[i] = TRUE;
            end
            if (isDiv[i] && (pipeReg[i].isFlushed || (pipeReg[i].valid && flush[i][0]))) begin
                // Div is flushed at register read stage, so release the divider
                divReset[i] = TRUE;
            end
            mulDivUnit.divReset[i] = divReset[i];

            // Request to the divider
            // NOT make a request when below situation
            // 1) When any operands of inst. are invalid
            // 2) When the divider is waiting for the instruction
            //    to receive the result of the divider
            mulDivUnit.divReq[i] = 
                mulDivUnit.divReserved[i] && 
                pipeReg[i].valid && isDiv[i] && 
                fuOpA[i].valid && fuOpB[i].valid;

            if (mulDivUnit.divFinished[i] &&
                localPipeReg[i][COMPLEX_EXEC_STAGE_DEPTH-2].valid &&
                localPipeReg[i][COMPLEX_EXEC_STAGE_DEPTH-2].complexQueueData.opType == COMPLEX_MOP_TYPE_DIV && 
                localPipeReg[i][COMPLEX_EXEC_STAGE_DEPTH-2].regValid
            ) begin 
                // Divが除算器から結果を取得できたので，
                // IQからのdivの発行を許可する 
                mulDivUnit.divRelease[i] = TRUE;
            end
            else begin
                mulDivUnit.divRelease[i] = FALSE;
            end
`endif

            if (pipeReg[i].valid && isDiv[i] && mulDivUnit.divReserved[i]) begin
                nextActiveListIndex[i] = 
                    pipeReg[i].complexQueueData.activeListPtr;
            end
            else begin
                nextActiveListIndex[i] = regActiveListIndex[i];
            end
        end
    end

    always_comb begin
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            iqData[i][0] = pipeReg[i].complexQueueData;
            complexOpInfo[i]  = pipeReg[i].complexQueueData.complexOpInfo;
            mulSubInfo[i]  = complexOpInfo[i].mulSubInfo;
            divSubInfo[i]  = complexOpInfo[i].divSubInfo;
            

            flush[i][0] = SelectiveFlushDetector(
                recovery.toRecoveryPhase,
                recovery.flushRangeHeadPtr,
                recovery.flushRangeTailPtr,
                recovery.flushAllInsns,
                pipeReg[i].complexQueueData.activeListPtr
            );

            // From local pipeline 
            for (int j = 1; j < COMPLEX_EXEC_STAGE_DEPTH; j++) begin 
                iqData[i][j] = localPipeReg[i][j-1].complexQueueData; 
                flush[i][j] = SelectiveFlushDetector( 
                    recovery.toRecoveryPhase, 
                    recovery.flushRangeHeadPtr, 
                    recovery.flushRangeTailPtr, 
                    recovery.flushAllInsns,
                    localPipeReg[i][j-1].complexQueueData.activeListPtr 
                );
            end

            // オペランド
            fuOpA[i] = ( pipeReg[i].bCtrl.rA.valid ? bypass.complexSrcRegDataOutA[i] : pipeReg[i].operandA );
            fuOpB[i] = ( pipeReg[i].bCtrl.rB.valid ? bypass.complexSrcRegDataOutB[i] : pipeReg[i].operandB );
           

            
            //
            // --- regValid
            //

            // If invalid regisers are read, regValid is negated and this op must be replayed.
            // ベクタ以外の演算
            regValid[i] =
                fuOpA[i].valid &&
                fuOpB[i].valid;

            //
            // --- データアウト(実行ステージの最終段の処理)
            //
            dataOut[i].valid
                = localPipeReg[i][COMPLEX_EXEC_STAGE_DEPTH-2].regValid;

            unique case ( localPipeReg[i][COMPLEX_EXEC_STAGE_DEPTH-2].complexQueueData.opType )
            COMPLEX_MOP_TYPE_DIV: dataOut[i].data = mulDivUnit.divDataOut[i];
            default: /* mul */    dataOut[i].data = mulDivUnit.mulDataOut[i];
            endcase

            //
            // --- Bypass
            //

            // 最初のステージで出力
            bypass.complexCtrlIn[i] = pipeReg[i].bCtrl;

            // 最後のステージで出力
            bypass.complexDstRegDataOut[i] = dataOut[i];

            //
            // --- Replay
            //

            // ISから3ステージ後=EX1ステージでReplayを出力
            // このとき、localPipeReg[lane][0]のデータを使う
            scheduler.complexRecordEntry[i] =
                !stall &&
                !clear &&
                !flush[i][1] &&
                localPipeReg[i][0].valid &&
                !localPipeReg[i][0].regValid;
            scheduler.complexRecordData[i] =
                localPipeReg[i][0].complexQueueData;
        end
    end


`ifdef RSD_ENABLE_VECTOR_PATH
    PVecDataPath  fuVecOpA    [ COMPLEX_ISSUE_WIDTH ];
    PVecDataPath  fuVecOpB    [ COMPLEX_ISSUE_WIDTH ];
    PVecDataPath  vecDataOut  [ COMPLEX_ISSUE_WIDTH ];

    //
    // VectorAdder
    //
    VectorPath vecAddDataOut [ COMPLEX_ISSUE_WIDTH ];
    for ( genvar i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin : BlockVecAdd
        PipelinedVectorAdder #(
            .PIPELINE_DEPTH( COMPLEX_EXEC_STAGE_DEPTH )
        ) vecAdder (
            .clk( port.clk ),
            .stall( stall ),
            .fuOpA_In( fuVecOpA[i].data ),
            .fuOpB_In( fuVecOpB[i].data ),
            .dataOut( vecAddDataOut[i] )
        );
    end

    //
    // VectorMultiplier
    //
    VectorPath vecMulDataOut [ COMPLEX_ISSUE_WIDTH ];
    for ( genvar i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin : BlockVecMul
        PipelinedVectorMultiplier #(
            .PIPELINE_DEPTH( COMPLEX_EXEC_STAGE_DEPTH )
        ) vecMul (
            .clk( port.clk ),
            .stall( stall ),
            .getUpper( FALSE ),
            .mulCode( AC_MUL ),
            .fuOpA_In( fuVecOpA[i].data ),
            .fuOpB_In( fuVecOpB[i].data ),
            .dataOut( vecMulDataOut[i] )
        );
    end

    always_comb begin
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            fuVecOpA[i] = ( pipeReg[i].bCtrl.rA.valid ? bypass.complexSrcVecDataOutA[i] : pipeReg[i].vecOperandA );
            fuVecOpB[i] = ( pipeReg[i].bCtrl.rB.valid ? bypass.complexSrcVecDataOutB[i] : pipeReg[i].vecOperandB );

            if ( iqData[i][0].opDst.phyDstRegNum.isVector ) begin
                // ベクタ演算
                regValid[i] =
                    fuVecOpA[i].valid &&
                    fuVecOpB[i].valid;
            end
            else begin
                // ベクタ以外の演算
                regValid[i] =
                    fuOpA[i].valid &&
                    fuOpB[i].valid;
            end
            vecDataOut[i].valid
                = localPipeReg[i][COMPLEX_EXEC_STAGE_DEPTH-2].regValid;

            unique case ( localPipeReg[i][COMPLEX_EXEC_STAGE_DEPTH-2].complexQueueData.opType )
            COMPLEX_MOP_TYPE_VEC_ADD: vecDataOut[i].data = vecAddDataOut[i];
            default: /* vec mul */    vecDataOut[i].data = vecMulDataOut[i];
            endcase
            bypass.complexDstVecDataOut[i] = vecDataOut[i];
        end
    end
`endif


    //
    // --- Pipeline レジスタ書き込み
    //
    ComplexIntegerRegisterWriteStageRegPath nextStage [ COMPLEX_ISSUE_WIDTH ];

    always_comb begin
        // Local Pipeline Register
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextLocalPipeReg[i][0].opId = pipeReg[i].opId;
`endif

            nextLocalPipeReg[i][0].valid = flush[i][0] ? FALSE : pipeReg[i].valid;
            nextLocalPipeReg[i][0].complexQueueData = pipeReg[i].complexQueueData;

            // Regvalid of local pipeline 
            if (isDiv[i]) begin
                nextLocalPipeReg[i][0].regValid = 
                    pipeReg[i].replay && (mulDivUnit.divFinished[i]);
            end
            else begin
                nextLocalPipeReg[i][0].regValid = regValid[i];
            end
            

            for (int j = 1; j < COMPLEX_EXEC_STAGE_DEPTH-1; j++) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
                nextLocalPipeReg[i][j].opId = localPipeReg[i][j-1].opId;
`endif 
                nextLocalPipeReg[i][j].valid = flush[i][j] ? FALSE : localPipeReg[i][j-1].valid;
                nextLocalPipeReg[i][j].regValid = localPipeReg[i][j-1].regValid; 
                nextLocalPipeReg[i][j].complexQueueData = localPipeReg[i][j-1].complexQueueData;
            end 
        end

        // To ComplexIntegerRegisterWriteStage
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].opId
                = localPipeReg[i][COMPLEX_EXEC_STAGE_DEPTH-2].opId;
`endif

            nextStage[i].complexQueueData
                = localPipeReg[i][COMPLEX_EXEC_STAGE_DEPTH-2].complexQueueData;

            // リセットorフラッシュ時はNOP
            nextStage[i].valid =
                (stall || clear || port.rst || flush[i][COMPLEX_EXEC_STAGE_DEPTH-1]) ? FALSE : localPipeReg[i][COMPLEX_EXEC_STAGE_DEPTH-2].valid;

            nextStage[i].dataOut = dataOut[i];
`ifdef RSD_ENABLE_VECTOR_PATH
            nextStage[i].vecDataOut = vecDataOut[i];
`endif
        end

        port.nextStage = nextStage;

        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            debug.complexExReg[i].valid[0] = pipeReg[i].valid;
            debug.complexExReg[i].flush[0] = flush[i][0];
            debug.complexExReg[i].opId[0] = pipeReg[i].opId;
            for ( int j = 1; j < COMPLEX_EXEC_STAGE_DEPTH; j++ ) begin
                debug.complexExReg[i].valid[j] = localPipeReg[i][j-1].valid;
                debug.complexExReg[i].opId[j] = localPipeReg[i][j-1].opId;
                debug.complexExReg[i].flush[j] = flush[i][j];
            end
`ifdef RSD_FUNCTIONAL_SIMULATION
            debug.complexExReg[i].dataOut = dataOut[i];
            debug.complexExReg[i].fuOpA   = fuOpA[i];
            debug.complexExReg[i].fuOpB   = fuOpB[i];

`ifdef RSD_ENABLE_VECTOR_PATH
            debug.complexExReg[i].vecDataOut = vecDataOut[i];
            debug.complexExReg[i].fuVecOpA = fuVecOpA[i];
            debug.complexExReg[i].fuVecOpB = fuVecOpB[i];
`endif

`endif  // `ifdef RSD_FUNCTIONAL_SIMULATION
        end //for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
`endif
end

endmodule : ComplexIntegerExecutionStage

`endif
