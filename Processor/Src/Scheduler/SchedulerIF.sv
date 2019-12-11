// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// SchedulerIF
//

import BasicTypes::*;
import CacheSystemTypes::*;
import MicroOpTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import PipelineTypes::*;

interface SchedulerIF( input logic clk, rst, rstStart );

    // Allocation
    logic               allocate [ RENAME_WIDTH ];
    IssueQueueIndexPath allocatedPtr [ RENAME_WIDTH ];
    logic               allocatable;

    // Dispatch
    logic               write [ DISPATCH_WIDTH ];
    IssueQueueIndexPath writePtr [ DISPATCH_WIDTH ];
    ActiveListIndexPath writeAL_Ptr [ DISPATCH_WIDTH ];
    IntIssueQueueEntry  intWriteData [ DISPATCH_WIDTH ];
    MemIssueQueueEntry  memWriteData [ DISPATCH_WIDTH ];
    SchedulerEntry      writeSchedulerData [ DISPATCH_WIDTH ];

    // Schedule
    logic               selected [ ISSUE_WIDTH ];
    IssueQueueIndexPath selectedPtr [ ISSUE_WIDTH ];

    // Issue
    logic               intIssue [ INT_ISSUE_WIDTH ];
    IssueQueueIndexPath intIssuePtr [ INT_ISSUE_WIDTH ];
    IntIssueQueueEntry  intIssuedData [ INT_ISSUE_WIDTH ];

    logic               memIssue [ MEM_ISSUE_WIDTH ];
    IssueQueueIndexPath memIssuePtr [ MEM_ISSUE_WIDTH ];
    MemIssueQueueEntry  memIssuedData [ MEM_ISSUE_WIDTH ];

    // Release
    // Issued entries are flushed.
    logic               intRecordEntry[INT_ISSUE_WIDTH];
    logic               intReplayEntry[INT_ISSUE_WIDTH];
    IntIssueQueueEntry  intRecordData[INT_ISSUE_WIDTH];
    IntIssueQueueEntry  intReplayData[INT_ISSUE_WIDTH];

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    ComplexIssueQueueEntry  complexWriteData [ DISPATCH_WIDTH ];

    logic               complexIssue [ COMPLEX_ISSUE_WIDTH ];
    IssueQueueIndexPath complexIssuePtr [ COMPLEX_ISSUE_WIDTH ];
    ComplexIssueQueueEntry  complexIssuedData [ COMPLEX_ISSUE_WIDTH ];

    logic               complexRecordEntry[COMPLEX_ISSUE_WIDTH];
    logic               complexReplayEntry[COMPLEX_ISSUE_WIDTH];
    ComplexIssueQueueEntry  complexRecordData[COMPLEX_ISSUE_WIDTH];
    ComplexIssueQueueEntry  complexReplayData[COMPLEX_ISSUE_WIDTH];

    // Reserve to use divider
    logic divIsIssued [ COMPLEX_ISSUE_WIDTH ];
`endif

    logic               memReleaseEntry[MEM_ISSUE_WIDTH];
    logic               memRecordEntry[MEM_ISSUE_WIDTH];
    logic               memReplayEntry[MEM_ISSUE_WIDTH];
    MemIssueQueueEntry  memRecordData[MEM_ISSUE_WIDTH];
    MemIssueQueueEntry  memReplayData[MEM_ISSUE_WIDTH];
    logic               memRecordAddrHit[MEM_ISSUE_WIDTH];
    DCacheIndexSubsetPath   memRecordAddrSubset[MEM_ISSUE_WIDTH];
    logic replay;

    // Stall scheduling
    logic stall;

    // For issue queue flush of dispatch stage ops ( already allocate issue queue entry )
    logic allocated[DISPATCH_WIDTH];

    // Memory dependency prediction
    logic memDependencyPred [ DISPATCH_WIDTH ];

    // To an issue queue payload RAM
    modport IssueQueue(
    input
        clk,
        rst,
        rstStart,
        allocate,
        write,
        writePtr,
        writeAL_Ptr,
        intWriteData,
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        complexWriteData,
        complexIssue,
        complexIssuePtr,
`endif
        memWriteData,
        intIssue,
        intIssuePtr,
        memIssue,
        memIssuePtr,
        allocated,
    output
        allocatable,
        allocatedPtr,
        intIssuedData,
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        complexIssuedData,
`endif  
        memIssuedData
    );

    // To a scheduler (wakeup/select logic)
    modport Scheduler(
    input
        clk,
        rst,
        stall,
        write,
        writePtr,
        writeSchedulerData,
        memDependencyPred,
    output
        selected,
        selectedPtr
    );

    modport ReplayQueue(
    input
        clk,
        rst,
        rstStart,
        stall,
        intRecordEntry,
        intRecordData,
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        complexRecordEntry,
        complexRecordData,
`endif
        memRecordAddrHit,
        memRecordAddrSubset,
        memRecordEntry,
        memRecordData,
    output
        intReplayEntry,
        intReplayData,
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        complexReplayEntry,
        complexReplayData,
`endif
        memReplayEntry,
        memReplayData,
        replay
    );



    modport RenameStage(
    input
        allocatedPtr,
        allocatable,
    output
        allocate
    );

    modport DispatchStage(
    output
        write,
        writePtr,
        writeAL_Ptr,
        intWriteData,
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        complexWriteData,
`endif
        memWriteData,
        writeSchedulerData,
        allocated,
        memDependencyPred
    );

    modport ScheduleStage(
    input
        selected,
        selectedPtr,
    output
        stall
    );

    modport IntegerIssueStage(
    input
        intIssuedData,
        intReplayEntry,
        intReplayData,
        replay,
    output
        intIssuePtr,
        intIssue
    );

    modport IntegerRegisterWriteStage(
    output
        intRecordEntry,
        intRecordData
    );

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    modport ComplexIntegerIssueStage(
    input
        complexIssuedData,
        complexReplayEntry,
        complexReplayData,
        replay,
    output
        complexIssuePtr,
        complexIssue,
        divIsIssued
    );

    modport ComplexIntegerExecutionStage(
    input
        divIsIssued,
    output
        complexRecordEntry,
        complexRecordData
    );
`endif
    modport MemoryIssueStage(
    input
        memIssuedData,
        memReplayEntry,
        memReplayData,
        replay,
    output
        memIssuePtr,
        memIssue
    );

    modport MemoryTagAccessStage(
    output
        memRecordAddrHit,
        memRecordAddrSubset,
        memRecordEntry,
        memRecordData
    );
    
endinterface : SchedulerIF

