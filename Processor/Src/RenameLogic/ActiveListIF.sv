// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// ActiveListIF
//

import BasicTypes::*;
import MicroOpTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import PipelineTypes::*;
import LoadStoreUnitTypes::*;
import OpFormatTypes::*;

interface ActiveListIF( input logic clk, rst );

    // Push 'pushedValue' on dispatch if this is true.
    logic pushTail [RENAME_WIDTH];

    // This value is pushed to an active list on dispatch.
    ActiveListEntry pushedTailData [RENAME_WIDTH];

    // This pointer is send to an issue queue on dispatch.
    // Execution state is written to an entry corresponding to an pointer.
    ActiveListIndexPath pushedTailPtr [RENAME_WIDTH];

    // Pop the head entry in an active list on commitment.
    CommitLaneCountPath popHeadNum;

    // Pop the Tail entry in an active list on retire.
    CommitLaneCountPath popTailNum;

    // In RRMT recovery mode, readData become the front entries data in an active list.
    // Otherwise, readData become the tail entries data in an active list.
    ActiveListEntry readData[COMMIT_WIDTH];

    // The front entries data in an active list.
    // This is used for commitment desicion.
    ExecutionState headExecState[COMMIT_WIDTH];
    ActiveListCountPath validEntryNum;

    // The count of entries from exception op to tail
    ActiveListCountPath recoveryEntryNum;

    // 'execState' is updated on execution.
    logic               intWrite[INT_ISSUE_WIDTH];
    ActiveListWriteData intWriteData[INT_ISSUE_WIDTH];

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    logic               complexWrite[COMPLEX_ISSUE_WIDTH];
    ActiveListWriteData complexWriteData[COMPLEX_ISSUE_WIDTH];
`endif

    logic               memWrite[MEM_ISSUE_WIDTH];
    ActiveListWriteData memWriteData[MEM_ISSUE_WIDTH];

`ifdef RSD_MARCH_FP_PIPE
    logic               fpWrite[FP_ISSUE_WIDTH];
    ActiveListWriteData fpWriteData[FP_ISSUE_WIDTH];
    FFlags_Path     fpFFlagsData[FP_ISSUE_WIDTH];
    FFlags_Path     fflagsData[COMMIT_WIDTH];
`endif
    // Status of an active list.
    logic allocatable;


    // ActiveList/LSQ TailPtr for recovery
    LoadQueueIndexPath loadQueueRecoveryTailPtr;
    StoreQueueIndexPath storeQueueRecoveryTailPtr;

    // Flush range at exception-detected cycle
    ActiveListIndexPath detectedFlushRangeTailPtr;
    ActiveListIndexPath exceptionOpPtr; // Exception op's ActiveListPtr


    // To active list
    modport ActiveList(
    input
        clk,
        rst,
        pushTail,
        pushedTailData,
        popHeadNum,
        popTailNum,
        intWrite,
        intWriteData,
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        complexWrite,
        complexWriteData,
`endif
        memWrite,
        memWriteData,
`ifdef RSD_MARCH_FP_PIPE
        fpWrite,
        fpWriteData,
        fpFFlagsData,
`endif
    output
`ifdef RSD_MARCH_FP_PIPE
        fflagsData,
`endif
        pushedTailPtr,
        readData,
        headExecState,
        loadQueueRecoveryTailPtr,
        storeQueueRecoveryTailPtr,
        detectedFlushRangeTailPtr,
        exceptionOpPtr,
        allocatable,
        validEntryNum,
        recoveryEntryNum
    );

    // 'pushedTailPtr' is set to an entry in issue queue.
    // 'pushTail' is push request to an active list.
    // 'pushedTailData' is pushed data.
    modport RenameStage(
    input
        allocatable,
        pushedTailPtr,
        validEntryNum,
    output
        pushTail,
        pushedTailData
    );

    modport IntegerRegisterWriteStage(
    output
        intWrite,
        intWriteData
    );

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    modport ComplexIntegerRegisterWriteStage(
    output
        complexWrite,
        complexWriteData
    );
`endif

    modport MemoryRegisterWriteStage(
    output
        memWrite,
        memWriteData
    );

`ifdef RSD_MARCH_FP_PIPE
    modport FPRegisterWriteStage(
    output
        fpWrite,
        fpWriteData,
        fpFFlagsData
    );
`endif

    modport CommitStage(
    input
`ifdef RSD_MARCH_FP_PIPE
        fflagsData,
`endif
        readData,
        headExecState,
        validEntryNum
    );

    modport RenameLogic(
    input
        readData,
        popTailNum
    );

    modport RenameLogicCommitter(
    input
        readData,
        recoveryEntryNum,
    output
        popHeadNum,
        popTailNum
    );

    modport RecoveryManager(
    input
        loadQueueRecoveryTailPtr,
        storeQueueRecoveryTailPtr,
        detectedFlushRangeTailPtr,
        exceptionOpPtr
    );

endinterface : ActiveListIF
