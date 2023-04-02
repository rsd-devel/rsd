// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- DebugIF
//

import BasicTypes::*;
import MemoryMapTypes::*;
import DebugTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import LoadStoreUnitTypes::*;
import PipelineTypes::*;

interface DebugIF( input logic clk, rst );
    
`ifndef RSD_DISABLE_DEBUG_REGISTER
    // Mainモジュール外部へ出力する信号群
    DebugRegister debugRegister;
    
    // debugRegisterの入力となる信号群
    // 各ステージからデータを集める
    NextPCStageDebugRegister npReg [ FETCH_WIDTH ];
    FetchStageDebugRegister   ifReg [ FETCH_WIDTH ];
    PreDecodeStageDebugRegister pdReg [ DECODE_WIDTH ];
    DecodeStageDebugRegister    idReg [ DECODE_WIDTH ];
    RenameStageDebugRegister    rnReg [ RENAME_WIDTH ];
    DispatchStageDebugRegister  dsReg [ DISPATCH_WIDTH ];
    
    IntegerIssueStageDebugRegister         intIsReg [ INT_ISSUE_WIDTH ];
    IntegerRegisterReadStageDebugRegister  intRrReg [ INT_ISSUE_WIDTH ];
    IntegerExecutionStageDebugRegister     intExReg [ INT_ISSUE_WIDTH ];
    IntegerRegisterWriteStageDebugRegister intRwReg [ INT_ISSUE_WIDTH ];

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    ComplexIntegerIssueStageDebugRegister         complexIsReg [ COMPLEX_ISSUE_WIDTH ];
    ComplexIntegerRegisterReadStageDebugRegister  complexRrReg [ COMPLEX_ISSUE_WIDTH ];
    ComplexIntegerExecutionStageDebugRegister     complexExReg [ COMPLEX_ISSUE_WIDTH ];
    ComplexIntegerRegisterWriteStageDebugRegister complexRwReg [ COMPLEX_ISSUE_WIDTH ];
`endif

    MemoryIssueStageDebugRegister          memIsReg [ MEM_ISSUE_WIDTH ];
    MemoryRegisterReadStageDebugRegister   memRrReg [ MEM_ISSUE_WIDTH ];
    MemoryExecutionStageDebugRegister      memExReg [ MEM_ISSUE_WIDTH ];
    MemoryTagAccessStageDebugRegister      mtReg    [ MEM_ISSUE_WIDTH ];
    MemoryAccessStageDebugRegister         maReg    [ MEM_ISSUE_WIDTH ];
    MemoryRegisterWriteStageDebugRegister  memRwReg [ MEM_ISSUE_WIDTH ];

`ifdef RSD_MARCH_FP_PIPE
    FPIssueStageDebugRegister         fpIsReg [ FP_ISSUE_WIDTH ];
    FPRegisterReadStageDebugRegister  fpRrReg [ FP_ISSUE_WIDTH ];
    FPExecutionStageDebugRegister     fpExReg [ FP_ISSUE_WIDTH ];
    FPRegisterWriteStageDebugRegister fpRwReg [ FP_ISSUE_WIDTH ];
`endif

    CommitStageDebugRegister cmReg [ COMMIT_WIDTH ];

    SchedulerDebugRegister  scheduler [ ISSUE_QUEUE_ENTRY_NUM ];
    IssueQueueDebugRegister issueQueue [ ISSUE_QUEUE_ENTRY_NUM ];

    PC_Path lastCommittedPC;
    logic recover, toRecoveryPhase;
    ActiveListIndexPath activeListHeadPtr;
    ActiveListCountPath activeListCount;
    
    // debugRegisterの入力となる信号群
    // パイプラインコントローラからデータを集める
    PipelineControll npStagePipeCtrl;
    PipelineControll ifStagePipeCtrl;
    PipelineControll pdStagePipeCtrl;
    PipelineControll idStagePipeCtrl;
    PipelineControll rnStagePipeCtrl;
    PipelineControll dsStagePipeCtrl;
    PipelineControll backEndPipeCtrl;
    PipelineControll cmStagePipeCtrl;
    logic stallByDecodeStage;

    logic loadStoreUnitAllocatable;
    logic storeCommitterPhase;
    StoreQueueCountPath storeQueueCount;
    logic busyInRecovery;
    logic storeQueueEmpty;

    PerfCounterPath perfCounter;

    modport Debug (
    input 
        clk,
        rst,
        npReg,
        ifReg,
        pdReg,
        idReg,
        rnReg,
        dsReg,
        intIsReg,
        intRrReg,
        intExReg,
        intRwReg,
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        complexIsReg,
        complexRrReg,
        complexExReg,
        complexRwReg,
`endif
        memIsReg,
        memRrReg,
        memExReg,
        maReg,
        mtReg,
        memRwReg,
`ifdef RSD_MARCH_FP_PIPE
        fpIsReg,
        fpRrReg,
        fpExReg,
        fpRwReg,
`endif
        cmReg,
        scheduler,
        issueQueue,
        recover,
        toRecoveryPhase,
        activeListHeadPtr,
        activeListCount,
        lastCommittedPC,
        npStagePipeCtrl,
        ifStagePipeCtrl,
        pdStagePipeCtrl,
        idStagePipeCtrl,
        rnStagePipeCtrl,
        dsStagePipeCtrl,
        backEndPipeCtrl,
        cmStagePipeCtrl,
        stallByDecodeStage,
        loadStoreUnitAllocatable,
        storeCommitterPhase,
        storeQueueCount,
        busyInRecovery,
        storeQueueEmpty,
        perfCounter,
    output
        debugRegister
    );
    
    modport StoreCommitter (
    output
        loadStoreUnitAllocatable,
        storeCommitterPhase,
        storeQueueCount,
        busyInRecovery,
        storeQueueEmpty
    );
    
    modport Controller (
    output
        npStagePipeCtrl,
        ifStagePipeCtrl,
        pdStagePipeCtrl,
        idStagePipeCtrl,
        rnStagePipeCtrl,
        dsStagePipeCtrl,
        backEndPipeCtrl,
        cmStagePipeCtrl,
        stallByDecodeStage
    );
    
    modport ActiveList (
    output
        activeListHeadPtr,
        activeListCount
    );
    
    modport Scheduler (
    output
        scheduler
    );
    
    modport IssueQueue (
    output
        issueQueue
    );

    modport NextPCStage (
    output
        npReg
    );

    modport FetchStage (
    output
        ifReg
    );

    modport PreDecodeStage (
    output
        pdReg
    );

    modport DecodeStage (
    output
        idReg
    );
    
    modport RenameStage (
    output
        rnReg
    );

    modport DispatchStage (
    output
        dsReg
    );
    
    modport IntegerIssueStage (
    output
        intIsReg
    );
    
    modport IntegerRegisterReadStage (
    output
        intRrReg
    );
    
    modport IntegerExecutionStage (
    output
        intExReg
    );
    
    modport IntegerRegisterWriteStage (
    output
        intRwReg
    );
    
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    modport ComplexIntegerIssueStage (
    output
        complexIsReg
    );
    
    modport ComplexIntegerRegisterReadStage (
    output
        complexRrReg
    );
    
    modport ComplexIntegerExecutionStage (
    output
        complexExReg
    );
    
    modport ComplexIntegerRegisterWriteStage (
    output
        complexRwReg
    );
`endif
    
    modport MemoryIssueStage (
    output
        memIsReg
    );
    
    modport MemoryRegisterReadStage (
    output
        memRrReg
    );
    
    modport MemoryExecutionStage (
    output
        memExReg
    );
    
    modport MemoryTagAccessStage (
    output
        mtReg
    );

    modport MemoryAccessStage (
    output
        maReg
    );
    
    modport MemoryRegisterWriteStage (
    output
        memRwReg
    );

`ifdef RSD_MARCH_FP_PIPE
    modport FPIssueStage (
    output
        fpIsReg
    );
    
    modport FPRegisterReadStage (
    output
        fpRrReg
    );
    
    modport FPExecutionStage (
    output
        fpExReg
    );
    
    modport FPRegisterWriteStage (
    output
        fpRwReg
    );
`endif

    modport CommitStage (
    output
        lastCommittedPC,
        recover,
        toRecoveryPhase,
        cmReg
    );

    modport PerformanceCounter (
    output 
        perfCounter
    );
    
`else

    // When debug signals are disabled.
    PC_Path lastCommittedPC;
    DebugRegister debugRegister;
    
    modport Debug (
        input clk, lastCommittedPC,
        output debugRegister
        
    );
    
    modport StoreCommitter (
        input clk
    );
    
    modport Controller (
        input clk
    );
    
    modport ActiveList (
        input clk
    );
    
    modport Scheduler (
        input clk
    );
    
    modport IssueQueue (
        input clk
    );
    
    modport FetchStage (
        input clk
    );

    modport NextPCStage (
        input clk
    );

    modport PreDecodeStage (
        input clk
    );

    modport DecodeStage (
        input clk
    );
    
    modport RenameStage (
        input clk
    );

    modport DispatchStage (
        input clk
    );
    
    modport IntegerIssueStage (
        input clk
    );
    
    modport IntegerRegisterReadStage (
        input clk
    );
    
    modport IntegerExecutionStage (
        input clk
    );
    
    modport IntegerRegisterWriteStage (
        input clk
    );
    
    modport ComplexIntegerIssueStage (
        input clk
    );
    
    modport ComplexIntegerRegisterReadStage (
        input clk
    );
    
    modport ComplexIntegerExecutionStage (
        input clk
    );
    
    modport ComplexIntegerRegisterWriteStage (
        input clk
    );

`ifdef RSD_MARCH_FP_PIPE
    modport FPIssueStage (
        input clk
    );
    
    modport FPRegisterReadStage (
        input clk
    );
    
    modport FPExecutionStage (
        input clk
    );
    
    modport FPRegisterWriteStage (
        input clk
    );
`endif
    
    modport MemoryIssueStage (
        input clk
    );
    
    modport MemoryRegisterReadStage (
        input clk
    );
    
    modport MemoryExecutionStage (
        input clk
    );
    
    modport MemoryTagAccessStage (
        input clk
    );
    modport MemoryAccessStage (
        input clk
    );
    
    modport MemoryRegisterWriteStage (
        input clk
    );

    modport CommitStage (
        input clk,
        output lastCommittedPC
    );

    modport PerformanceCounter (
        input clk
    );
`endif


endinterface : DebugIF
