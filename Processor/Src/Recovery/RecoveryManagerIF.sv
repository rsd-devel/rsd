// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- RecoveryManagerIF
//

import BasicTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import LoadStoreUnitTypes::*;

interface RecoveryManagerIF( input logic clk, rst );

    // Phase of a pipeline
    PipelinePhase phase;

    // A type of exception from CommitStage
    RefetchType refetchTypeFromCommitStage;

    // A type of exception from CommitStage
    RefetchType refetchTypeFromRwStage;

    // Index of detected exception op in CommitStage
    CommitLaneIndexPath recoveryOpIndex;

    // Exception detected in CommitStage
    logic exceptionDetectedInCommitStage;

    // Exception detected in RwStage
    logic exceptionDetectedInRwStage;

    // PC control
    logic    toCommitPhase;
    AddrPath recoveredPC_FromCommitStage;
    AddrPath recoveredPC_FromRwStage;
    AddrPath recoveredPC_FromRwCommit;      // Correct PC

    // For fault handling
    AddrPath faultingDataAddr;

    //　Miss prediction detected in RenameStage
    logic    recoverFromRename;
    AddrPath recoveredPC_FromRename;

    // Trigger recovery of each module
    logic toRecoveryPhase;

    // Flush range to broadcast
    ActiveListIndexPath flushRangeHeadPtr;
    ActiveListIndexPath flushRangeTailPtr;

    // ActiveList/LSQ TailPtr for recovery
    LoadQueueIndexPath loadQueueRecoveryTailPtr;
    LoadQueueIndexPath loadQueueHeadPtr;
    StoreQueueIndexPath storeQueueRecoveryTailPtr;
    StoreQueueIndexPath storeQueueHeadPtr;

    // IssueQueueEntryPtr to be flushed at recovery
    IssueQueueOneHotPath flushIQ_Entry;

    // In IQ returning index to freelist
    logic issueQueueReturnIndex;

    // In AL recovery
    logic inRecoveryAL;

    // In RMT recovery
    logic renameLogicRecoveryRMT;

    // In ReplayQueue flushing
    logic replayQueueFlushedOpExist;

    // In wakeupPipelineReg flushing
    logic wakeupPipelineRegFlushedOpExist;

    // Unable to detect exception and start recovery
    logic unableToStartRecovery;

    // IssueQueueのflushが必要なエントリかどうかの判定に使う
    IssueQueueOneHotPath notIssued;

    // wakeupPipelineRegister内の命令のフラッシュに使う
    logic selected [ ISSUE_WIDTH ];
    IssueQueueIndexPath selectedPtr [ ISSUE_WIDTH ];
    ActiveListIndexPath selectedActiveListPtr [ ISSUE_WIDTH ];

    // RwStageからのリカバリかどうか
    //toRecoveryPhaseと同時に立ちTrueでないときCommitStageからのリカバリ
    logic recoveryFromRwStage;

    // Why recovery is caused
    ExecutionState recoveryCauseFromCommitStage;

    modport RecoveryManager(
    input
        clk,
        rst,
        exceptionDetectedInCommitStage,
        refetchTypeFromCommitStage,
        exceptionDetectedInRwStage,
        refetchTypeFromRwStage,
        renameLogicRecoveryRMT,
        issueQueueReturnIndex,
        replayQueueFlushedOpExist,
        wakeupPipelineRegFlushedOpExist,
        recoveredPC_FromCommitStage,
        recoveredPC_FromRwStage,
        faultingDataAddr,
        notIssued,
        flushIQ_Entry,
        recoveryCauseFromCommitStage,
    output
        phase,
        toRecoveryPhase,
        recoveredPC_FromRwCommit,
        toCommitPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        unableToStartRecovery,
        recoveryFromRwStage,
        loadQueueRecoveryTailPtr,
        storeQueueRecoveryTailPtr
    );

    modport RenameStage(
    output
        recoverFromRename,
        recoveredPC_FromRename
    );

    modport CommitStage(
    input
        phase,
        unableToStartRecovery,
        renameLogicRecoveryRMT,
    output
        exceptionDetectedInCommitStage,
        recoveryOpIndex,
        refetchTypeFromCommitStage,
        recoveryCauseFromCommitStage
    );

    modport NextPCStage(
    input
        toCommitPhase,
        toRecoveryPhase,
        recoveredPC_FromRwCommit,
        recoverFromRename,
        recoveredPC_FromRename
    );

    modport RenameLogic(
    input
        toRecoveryPhase,
        inRecoveryAL,
    output
        renameLogicRecoveryRMT
    );

    modport RenameLogicCommitter(
    input
        toRecoveryPhase,
        toCommitPhase,
    output
        inRecoveryAL
    );

    modport IssueQueue(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        notIssued,
        selected,
        selectedPtr,
        recoveryFromRwStage,
    output
        flushIQ_Entry,
        issueQueueReturnIndex,
        selectedActiveListPtr
    );

    modport Scheduler(
    input
        toRecoveryPhase,
        flushIQ_Entry,
    output
        notIssued
    );

    modport ScheduleStage(
    input
        toRecoveryPhase,
        flushIQ_Entry
    );

    modport SelectLogic(
    output
        selected,
        selectedPtr
    );

    modport ReplayQueue(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        recoveryFromRwStage,
    output
        replayQueueFlushedOpExist
    );

    modport WakeupPipelineRegister(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        selectedActiveListPtr,
        flushIQ_Entry,
        recoveryFromRwStage,
    output
        wakeupPipelineRegFlushedOpExist
    );

    modport LoadQueue(
    input
        toRecoveryPhase,
        loadQueueRecoveryTailPtr,
    output
        loadQueueHeadPtr
    );

    modport StoreQueue(
    input
        toRecoveryPhase,
        storeQueueRecoveryTailPtr,
    output
        storeQueueHeadPtr
    );

    modport StoreCommitter(
    input
        toRecoveryPhase
    );


    modport IntegerIssueStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr
    );

    modport IntegerRegisterReadStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr
    );

    modport IntegerExecutionStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr
    );

    modport IntegerRegisterWriteStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr
    );

    modport ComplexIntegerIssueStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr
    );

    modport ComplexIntegerRegisterReadStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr
    );

    modport ComplexIntegerExecutionStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr
    );

    modport ComplexIntegerRegisterWriteStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr
    );

    modport MemoryIssueStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr
    );

    modport MemoryRegisterReadStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr
    );

    modport MemoryExecutionStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr
    );

    modport MemoryTagAccessStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr
    );

    modport MemoryAccessStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr
    );

    modport MemoryRegisterWriteStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr
    );

    modport ActiveList(
    input
        toRecoveryPhase,
        toCommitPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        unableToStartRecovery,
    output
        exceptionDetectedInRwStage,
        refetchTypeFromRwStage,
        recoveredPC_FromCommitStage,
        recoveredPC_FromRwStage,
        faultingDataAddr
    );

    modport InterruptController(
    input
        unableToStartRecovery
    );

endinterface : RecoveryManagerIF

