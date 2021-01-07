// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- Core module
//
// プロセッサ・コアに含まれる全てのモジュールをインスタンシエートし、
// インターフェースで接続する

import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryTypes::*;
import MemoryMapTypes::*;
import IO_UnitTypes::*;
import DebugTypes::*;

module Core (
input
    logic clk,
    logic rst, rstStart,
    MemAccessSerial nextMemReadSerial, // RSDの次の読み出し要求に割り当てられるシリアル(id)
    MemWriteSerial nextMemWriteSerial, // RSDの次の書き込み要求に割り当てられるシリアル(id)
    MemoryEntryDataPath memReadData,
    logic memReadDataReady,
    MemAccessSerial memReadSerial, // メモリの読み出しデータのシリアル
    MemAccessResponse memAccessResponse, // メモリ書き込み完了通知
    logic memAccessReadBusy,
    logic memAccessWriteBusy,
    logic reqExternalInterrupt,
    ExternalInterruptCodePath externalInterruptCode,
output
    DebugRegister debugRegister,
    PC_Path lastCommittedPC,
    PhyAddrPath memAccessAddr,
    MemoryEntryDataPath memAccessWriteData,
    logic memAccessRE,
    logic memAccessWE,
    logic serialWE,
    SerialDataPath serialWriteData
);
    //
    // --- For Debug
    //
    DebugIF debugIF( clk, rst );
    PerformanceCounterIF perfCounterIF( clk, rst );

    assign debugRegister = debugIF.debugRegister;

`ifndef RSD_DISABLE_DEBUG_REGISTER
    Debug debug ( debugIF, lastCommittedPC );
`else
    always_ff @(posedge clk) begin
        lastCommittedPC <= debugIF.lastCommittedPC;
    end
`endif

`ifndef RSD_DISABLE_PERFORMANCE_COUNTER
    PerformanceCounter perfCounter(perfCounterIF, debugIF);
`endif

    //
    // --- Interfaces
    //

    // Pipeline control logic
    ControllerIF ctrlIF( clk, rst );

    // Pipeline stages
    NextPCStageIF npStageIF( clk, rst, rstStart );
    FetchStageIF ifStageIF( clk, rst, rstStart );
    PreDecodeStageIF pdStageIF( clk, rst );
    DecodeStageIF idStageIF( clk, rst );
    RenameStageIF rnStageIF( clk, rst, rstStart );
    //DispatchStageIF dsStageIF( clk, rst );
    ScheduleStageIF scStageIF( clk, rst );

    IntegerIssueStageIF intIsStageIF( clk, rst );
    IntegerRegisterReadStageIF intRrStageIF( clk, rst );
    IntegerExecutionStageIF intExStageIF( clk, rst );
    //IntegerRegisterWriteStageIF intRwStageIF( clk, rst );

    ComplexIntegerIssueStageIF complexIsStageIF( clk, rst );
    ComplexIntegerRegisterReadStageIF complexRrStageIF( clk, rst );
    ComplexIntegerExecutionStageIF complexExStageIF( clk, rst );

    MemoryIssueStageIF memIsStageIF( clk, rst );
    MemoryRegisterReadStageIF memRrStageIF( clk, rst );
    MemoryExecutionStageIF memExStageIF( clk, rst );
    MemoryTagAccessStageIF mtStageIF( clk, rst );
    MemoryAccessStageIF maStageIF( clk, rst );
    //MemoryRegisterWriteStageIF memRwStageIF( clk, rst );

    CommitStageIF cmStageIF( clk, rst );

    // Other interfaces.
    CacheSystemIF cacheSystemIF( clk, rst );
    RenameLogicIF renameLogicIF( clk, rst, rstStart );
    ActiveListIF activeListIF( clk, rst );
    SchedulerIF schedulerIF( clk, rst, rstStart );
    WakeupSelectIF wakeupSelectIF( clk, rst, rstStart );
    RegisterFileIF registerFileIF( clk, rst, rstStart );
    BypassNetworkIF bypassNetworkIF( clk, rst, rstStart );
    LoadStoreUnitIF loadStoreUnitIF( clk, rst, rstStart );
    RecoveryManagerIF recoveryManagerIF( clk, rst );
    CSR_UnitIF csrUnitIF(clk, rst, rstStart, reqExternalInterrupt, externalInterruptCode);
    IO_UnitIF ioUnitIF(clk, rst, rstStart, serialWE, serialWriteData);
    MulDivUnitIF mulDivUnitIF(clk, rst);
    CacheFlushManagerIF cacheFlushManagerIF(clk, rst);

    //
    // --- Modules
    //
    Controller controller( ctrlIF, debugIF );
    MemoryAccessController memoryAccessController(
        .port( cacheSystemIF.MemoryAccessController ),
        .memAccessAddr( memAccessAddr ),
        .memAccessWriteData( memAccessWriteData ),
        .memAccessRE( memAccessRE ),
        .memAccessWE( memAccessWE ),
        .memAccessReadBusy( memAccessReadBusy ),
        .memAccessWriteBusy( memAccessWriteBusy ),
        .nextMemReadSerial( nextMemReadSerial ),
        .nextMemWriteSerial( nextMemWriteSerial ),
        .memReadDataReady( memReadDataReady ),
        .memReadData( memReadData ),
        .memReadSerial( memReadSerial ),
        .memAccessResponse( memAccessResponse )
    );


    NextPCStage npStage( npStageIF, ifStageIF, recoveryManagerIF, ctrlIF, debugIF );
        PC pc( npStageIF );
        BTB btb( npStageIF, ifStageIF );
        BranchPredictor brPred( npStageIF, ifStageIF, ctrlIF );
    FetchStage ifStage( ifStageIF, npStageIF, ctrlIF, debugIF, perfCounterIF );
        ICache iCache( npStageIF, ifStageIF, cacheSystemIF );
    
    PreDecodeStage pdStage( pdStageIF, ifStageIF, ctrlIF, debugIF );
    DecodeStage idStage( idStageIF, pdStageIF, ctrlIF, debugIF, perfCounterIF );

    RenameStage rnStage( rnStageIF, idStageIF, renameLogicIF, activeListIF, schedulerIF, loadStoreUnitIF, recoveryManagerIF, ctrlIF, debugIF );
        RenameLogic renameLogic( renameLogicIF, activeListIF, recoveryManagerIF );
        RenameLogicCommitter renameLogicCommitter( renameLogicIF, activeListIF, recoveryManagerIF );
        ActiveList activeList( activeListIF, recoveryManagerIF, ctrlIF, debugIF );
        RMT rmt_wat( renameLogicIF );
        RetirementRMT retirementRMT( renameLogicIF );
        MemoryDependencyPredictor memoryDependencyPredictor( rnStageIF, loadStoreUnitIF );
    
    DispatchStage dsStage( /*dsStageIF,*/ rnStageIF, schedulerIF, ctrlIF, debugIF );

    ScheduleStage scStage( scStageIF, schedulerIF, recoveryManagerIF, ctrlIF );
        IssueQueue issueQueue( schedulerIF, wakeupSelectIF, recoveryManagerIF, debugIF );
        ReplayQueue replayQueue( schedulerIF, loadStoreUnitIF, mulDivUnitIF, cacheFlushManagerIF, recoveryManagerIF, ctrlIF );
        Scheduler scheduler( schedulerIF, wakeupSelectIF, recoveryManagerIF, mulDivUnitIF, debugIF );
        WakeupPipelineRegister wakeupPipelineRegister( wakeupSelectIF, recoveryManagerIF );
        DestinationRAM destinationRAM( wakeupSelectIF );
        WakeupLogic wakeupLogic( wakeupSelectIF );
        SelectLogic selectLogic( wakeupSelectIF, recoveryManagerIF );

    IntegerIssueStage intIsStage( intIsStageIF, scStageIF, schedulerIF, recoveryManagerIF, ctrlIF, debugIF );
    IntegerRegisterReadStage intRrStage( intRrStageIF, intIsStageIF, registerFileIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, debugIF );
    IntegerExecutionStage intExStage( intExStageIF, intRrStageIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, debugIF );
    IntegerRegisterWriteStage intRwStage( /*intRwStageIF,*/ intExStageIF, schedulerIF, npStageIF, registerFileIF, activeListIF, recoveryManagerIF, ctrlIF, debugIF );

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    ComplexIntegerIssueStage complexIsStage( complexIsStageIF, scStageIF, schedulerIF, recoveryManagerIF, mulDivUnitIF, ctrlIF, debugIF );
    ComplexIntegerRegisterReadStage complexRrStage( complexRrStageIF, complexIsStageIF, registerFileIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, debugIF );
    ComplexIntegerExecutionStage complexExStage( complexExStageIF, complexRrStageIF, mulDivUnitIF, schedulerIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, debugIF );
    ComplexIntegerRegisterWriteStage complexRwStage( complexExStageIF, registerFileIF, activeListIF, recoveryManagerIF, ctrlIF, debugIF );
`endif
        MulDivUnit mulDivUnit(mulDivUnitIF);

    MemoryIssueStage memIsStage( memIsStageIF, scStageIF, schedulerIF, recoveryManagerIF, mulDivUnitIF, ctrlIF, debugIF );
    MemoryRegisterReadStage memRrStage( memRrStageIF, memIsStageIF,loadStoreUnitIF, mulDivUnitIF, registerFileIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, debugIF );
    MemoryExecutionStage memExStage( memExStageIF, memRrStageIF, loadStoreUnitIF, cacheFlushManagerIF, mulDivUnitIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, csrUnitIF, debugIF );
    MemoryTagAccessStage mtStage( mtStageIF, memExStageIF, schedulerIF, loadStoreUnitIF, mulDivUnitIF, recoveryManagerIF, ctrlIF, debugIF, perfCounterIF );
    MemoryAccessStage maStage( maStageIF, mtStageIF, loadStoreUnitIF, mulDivUnitIF, bypassNetworkIF, ioUnitIF, recoveryManagerIF, ctrlIF, debugIF );
        LoadStoreUnit loadStoreUnit( loadStoreUnitIF, ctrlIF );
        LoadQueue loadQueue( loadStoreUnitIF, recoveryManagerIF );
        StoreQueue storeQueue( loadStoreUnitIF, recoveryManagerIF );
        StoreCommitter storeCommitter(loadStoreUnitIF, recoveryManagerIF, ioUnitIF, debugIF, perfCounterIF);
        DCache dCache( loadStoreUnitIF, cacheSystemIF, ctrlIF );
    MemoryRegisterWriteStage memRwStage( /*memRwStageIF,*/ maStageIF, registerFileIF, activeListIF, recoveryManagerIF, ctrlIF, debugIF );

    RegisterFile registerFile( registerFileIF );
        BypassController bypassController( bypassNetworkIF, ctrlIF );
        BypassNetwork  bypassNetwork( bypassNetworkIF, ctrlIF );
`ifdef RSD_ENABLE_VECTOR_PATH
        VectorBypassNetwork  vectorBypassNetwork( bypassNetworkIF, ctrlIF );
`endif
    // A commitment stage generates a flush signal and this is send to scheduler.
    CommitStage cmStage( cmStageIF, renameLogicIF, activeListIF, loadStoreUnitIF, recoveryManagerIF, csrUnitIF, debugIF );
        RecoveryManager recoveryManager( recoveryManagerIF, activeListIF, csrUnitIF, ctrlIF, perfCounterIF );

    CSR_Unit csrUnit(csrUnitIF, perfCounterIF);
    CacheFlushManager cacheFlushManager( cacheFlushManagerIF, cacheSystemIF );
    InterruptController interruptCtrl(csrUnitIF, ctrlIF, npStageIF, recoveryManagerIF);
    IO_Unit ioUnit(ioUnitIF, csrUnitIF);

endmodule : Core
