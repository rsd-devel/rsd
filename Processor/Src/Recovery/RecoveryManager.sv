// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Recovery Manager
//   リカバリに遷移する信号を各モジュールにブロードキャストするモジュール
//   モジュールのリカバリ自体はそれぞれのモジュール中で記述される
//
// 例外が起きてリカバリが行われる様子は以下のようになっている
// 1. RwStageもしくはCmStageからexceptionDetected信号が, RecoveryManagerに発信される
// 2. exceptionDetected信号があさーとされた次のサイクルに, 各モジュールにtoRecoveryPhase信号が発信される(PHASE_RECOVER_0)
// 3. すべてのモジュールのリカバリが終わったことを確認したら, 各モジュールにtoCommitPhase信号を送り, リカバリ終了

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;

module RecoveryManager(
    RecoveryManagerIF.RecoveryManager port,
    ActiveListIF.RecoveryManager activeList,
    CSR_UnitIF.RecoveryManager csrUnit,
    ControllerIF.RecoveryManager ctrl,
    PerformanceCounterIF.RecoveryManager perfCounter
);
    typedef struct packed
    {
        // リカバリのフェーズ
        // 実行ステージからリカバリがかかる場合もあるので，
        // コミットステージのフェーズと同期しているわけではない
        PipelinePhase phase;

        // リカバリ要求
        // これらはステージの終わりのあたりで来ることが多いので，一旦レジスタに積んで
        // パイプライン化する
        logic exceptionDetectedInCommitStage;
        AddrPath recoveredPC_FromRwStage;
        AddrPath recoveredPC_FromCommitStage;

        // Related to CSR 
        // これらもパイプライン化のため
        ExecutionState excptCause;      // Trap vector or MRET return target
        AddrPath excptCauseDataAddr;    // fault 発生時のデータアドレス

        // ActiveList中のどのエントリがどのエントリまでをフラッシュするかを示すポインタ
        ActiveListIndexPath flushRangeHeadPtr;
        ActiveListIndexPath flushRangeTailPtr;
     
        logic recoveryFromRwStage;  // 例外がどこのステージで検出されたか
        RefetchType refetchType;    // リフェッチのタイプ

    } RecoveryManagerStatePath;
    RecoveryManagerStatePath regState;
    RecoveryManagerStatePath nextState;

    // 各モジュールに送られる信号
    // リカバリ時の動作自体は各モジュールで記述される
    logic toRecoveryPhase, toCommitPhase;

    // CSR からリフェッチするかどうか
    logic refetchFromCSR;

    //リカバリによって回復されるPC
    PC_Path recoveredPC;

    // 例外を起こした命令のActiveListのポインタ
    ActiveListIndexPath exceptionOpPtr;

    // 例外が検出された後リカバリ状態に移行する
    logic exceptionDetected;

    always_ff@(posedge port.clk) begin  // synchronous rst
        if (!port.rst) begin
            regState <= nextState;
        end
        else begin
            regState.phase <= PHASE_COMMIT;
            regState.flushRangeHeadPtr <= '0;
            regState.flushRangeTailPtr <= '0;
            regState.recoveryFromRwStage <= FALSE;
            regState.refetchType <= REFETCH_TYPE_THIS_PC;

            regState.exceptionDetectedInCommitStage <= '0;
            regState.recoveredPC_FromRwStage <= '0;
            regState.recoveredPC_FromCommitStage <= '0;

            regState.excptCause <= EXEC_STATE_NOT_FINISHED;
            regState.excptCauseDataAddr <= '0;
        end
    end


    always_comb begin
        // To Recovery 0
        toRecoveryPhase = 
            port.exceptionDetectedInCommitStage || 
            port.exceptionDetectedInRwStage;
        if (toRecoveryPhase) begin
            nextState.recoveryFromRwStage = port.exceptionDetectedInRwStage;
        end
        else begin
            nextState.recoveryFromRwStage = FALSE;
        end

        // Return to COMMIT_PHASE
        toCommitPhase =
            (regState.phase == PHASE_RECOVER_1) &&  // must be PHASE_RECOVER_1 because PHASE_RECOVER_0 procedures has been finished
            !(port.renameLogicRecoveryRMT || port.issueQueueReturnIndex); // LSQ は1サイクルでリカバリが行われるので待つべきは RMT と IQ
        nextState.refetchType = 
            port.exceptionDetectedInCommitStage ? 
                port.refetchTypeFromCommitStage : 
                port.refetchTypeFromRwStage;

        // Trap/fault origin
        // これらの要求は一旦レジスタに積む
        nextState.excptCause = port.recoveryCauseFromCommitStage;
        nextState.excptCauseDataAddr = port.faultingDataAddr;
        nextState.exceptionDetectedInCommitStage = port.exceptionDetectedInCommitStage;
        nextState.recoveredPC_FromRwStage = port.recoveredPC_FromRwStage;
        nextState.recoveredPC_FromCommitStage = port.recoveredPC_FromCommitStage;

        // CSR への要求はすべて PHASE_RECOVER_0 に行う
        refetchFromCSR = regState.refetchType inside {
            REFETCH_TYPE_NEXT_PC_TO_CSR_TARGET, REFETCH_TYPE_THIS_PC_TO_CSR_TARGET
        };
        csrUnit.triggerExcpt = (regState.phase == PHASE_RECOVER_0) && refetchFromCSR;
        csrUnit.excptCauseAddr = ToPC_FromAddr(regState.recoveredPC_FromCommitStage);
        csrUnit.excptCause = regState.excptCause;
        csrUnit.excptCauseDataAddr = regState.excptCauseDataAddr;

        // Recovered PC
        if(regState.phase == PHASE_RECOVER_0) begin
            if (refetchFromCSR) begin
                recoveredPC = ToPC_FromAddr(csrUnit.excptTargetAddr);
            end
            else begin
                if (regState.refetchType == REFETCH_TYPE_THIS_PC) begin
                    recoveredPC = regState.exceptionDetectedInCommitStage ?
                        ToPC_FromAddr(regState.recoveredPC_FromCommitStage) : 
                        ToPC_FromAddr(regState.recoveredPC_FromRwStage);
                end
                else if (regState.refetchType inside{REFETCH_TYPE_NEXT_PC, REFETCH_TYPE_STORE_NEXT_PC}) begin
                    recoveredPC = regState.exceptionDetectedInCommitStage ?
                        ToPC_FromAddr(regState.recoveredPC_FromCommitStage) + INSN_BYTE_WIDTH : 
                        ToPC_FromAddr(regState.recoveredPC_FromRwStage) + INSN_BYTE_WIDTH;
                end
                else begin // REFETCH_TYPE_BRANCH_TARGET
                    recoveredPC = regState.exceptionDetectedInCommitStage ?
                        ToPC_FromAddr(regState.recoveredPC_FromCommitStage) : 
                        ToPC_FromAddr(regState.recoveredPC_FromRwStage);
                end
            end
        end
        else begin
            recoveredPC = '0;
        end

        if(port.rst) begin
            nextState.phase = PHASE_COMMIT;
        end
        else if(regState.phase == PHASE_COMMIT) begin
            nextState.phase = toRecoveryPhase ? PHASE_RECOVER_0 : PHASE_COMMIT;
        end
        else if(regState.phase == PHASE_RECOVER_0) begin
            nextState.phase = PHASE_RECOVER_1;
        end
        else begin
            nextState.phase = toCommitPhase ? PHASE_COMMIT : regState.phase;
        end

        port.phase = regState.phase;

        // Update a PC in a fetcher if branch misprediction occurs.
        port.recoveredPC_FromRwCommit = recoveredPC;
        port.toCommitPhase = toCommitPhase;

        // To each logic to be recovered.
        port.toRecoveryPhase = regState.phase == PHASE_RECOVER_0;
        port.recoveryFromRwStage = regState.recoveryFromRwStage;

        // 選択的フラッシュにおいても，フロントエンドは全てフラッシュされる
        ctrl.cmStageFlushUpper = regState.phase == PHASE_RECOVER_0;

        // フラッシュする命令の範囲の管理
        exceptionDetected = port.exceptionDetectedInCommitStage || port.exceptionDetectedInRwStage;
        exceptionOpPtr = activeList.exceptionOpPtr;

        nextState.flushRangeHeadPtr = 
            (nextState.refetchType inside {REFETCH_TYPE_THIS_PC, REFETCH_TYPE_THIS_PC_TO_CSR_TARGET}) ?
                exceptionOpPtr : exceptionOpPtr + 1;
        nextState.flushRangeTailPtr = activeList.detectedFlushRangeTailPtr;
        port.loadQueueRecoveryTailPtr = activeList.loadQueueRecoveryTailPtr;
        port.storeQueueRecoveryTailPtr = 
            regState.refetchType == REFETCH_TYPE_STORE_NEXT_PC ? 
                (activeList.storeQueueRecoveryTailPtr + 1): activeList.storeQueueRecoveryTailPtr;

        port.flushRangeHeadPtr = regState.flushRangeHeadPtr;
        port.flushRangeTailPtr = regState.flushRangeTailPtr;

        // 
        port.unableToStartRecovery = 
            (regState.phase != PHASE_COMMIT) || 
            port.renameLogicRecoveryRMT || 
            port.issueQueueReturnIndex || 
            port.replayQueueFlushedOpExist || 
            port.wakeupPipelineRegFlushedOpExist;


        // Hardware Counter
`ifndef RSD_DISABLE_PERFORMANCE_COUNTER
        perfCounter.storeLoadForwardingFail =
            regState.phase == PHASE_RECOVER_0 && (regState.refetchType == REFETCH_TYPE_THIS_PC);
        perfCounter.memDepPredMiss =
            regState.phase == PHASE_RECOVER_0 && (regState.refetchType inside {REFETCH_TYPE_NEXT_PC, REFETCH_TYPE_STORE_NEXT_PC});
        perfCounter.branchPredMiss =
            regState.phase == PHASE_RECOVER_0 && (regState.refetchType == REFETCH_TYPE_BRANCH_TARGET);
`endif
    end

    
    // Commit/Recovery state manage
    `RSD_ASSERT_CLK(
        port.clk,
        !(toCommitPhase && toRecoveryPhase),
        "Tried to start the commit phase and the recovery phase at the same time"
    );

    `RSD_ASSERT_CLK(
        port.clk,
        !(port.exceptionDetectedInRwStage && nextState.refetchType inside {REFETCH_TYPE_NEXT_PC_TO_CSR_TARGET, REFETCH_TYPE_THIS_PC_TO_CSR_TARGET} ),
        "RW stage recovery is not allowed in REFETCH_TYPE_CSR_UNIT_TARGET"
    );

endmodule : RecoveryManager