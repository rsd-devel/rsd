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
    logic reqCustomInterrupt,
    CustomInterruptCodePath customInterruptCode,
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
    DebugIF debugIF();
    PerformanceCounterIF perfCounterIF();

    assign debugIF.clk = clk;
    assign debugIF.rst = rst;
    assign perfCounterIF.clk = clk;
    assign perfCounterIF.rst = rst;

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
    ControllerIF ctrlIF();

    // Pipeline stages
    NextPCStageIF npStageIF();
    FetchStageIF ifStageIF();
    PreDecodeStageIF pdStageIF();
    DecodeStageIF idStageIF();
    RenameStageIF rnStageIF();
    //DispatchStageIF dsStageIF( clk, rst );
    ScheduleStageIF scStageIF();

    IntegerIssueStageIF intIsStageIF();
    IntegerRegisterReadStageIF intRrStageIF();
    IntegerExecutionStageIF intExStageIF();
    //IntegerRegisterWriteStageIF intRwStageIF( clk, rst );

    ComplexIntegerIssueStageIF complexIsStageIF();
    ComplexIntegerRegisterReadStageIF complexRrStageIF();
    ComplexIntegerExecutionStageIF complexExStageIF();

    MemoryIssueStageIF memIsStageIF();
    MemoryRegisterReadStageIF memRrStageIF();
    MemoryExecutionStageIF memExStageIF();
    MemoryTagAccessStageIF mtStageIF();
    MemoryAccessStageIF maStageIF();
    //MemoryRegisterWriteStageIF memRwStageIF( clk, rst );
    
    FPIssueStageIF fpIsStageIF();
    FPRegisterReadStageIF fpRrStageIF();
    FPExecutionStageIF fpExStageIF();
    FPDivSqrtUnitIF fpDivSqrtUnitIF();

    CommitStageIF cmStageIF();

    // Other interfaces.
    CacheSystemIF cacheSystemIF();
    RenameLogicIF renameLogicIF();
    ActiveListIF activeListIF();
    SchedulerIF schedulerIF();
    WakeupSelectIF wakeupSelectIF();
    RegisterFileIF registerFileIF();
    BypassNetworkIF bypassNetworkIF();
    LoadStoreUnitIF loadStoreUnitIF();
    RecoveryManagerIF recoveryManagerIF();
    CSR_UnitIF csrUnitIF();
    IO_UnitIF ioUnitIF();
    MulDivUnitIF mulDivUnitIF();
    CacheFlushManagerIF cacheFlushManagerIF();
    AMOCacheIF amoCacheIF();

    assign ctrlIF.clk = clk;
    assign ctrlIF.rst = rst;

    assign npStageIF.clk = clk;
    assign npStageIF.rst = rst;
    assign npStageIF.rstStart = rstStart;
    assign ifStageIF.clk = clk;
    assign ifStageIF.rst = rst;
    assign pdStageIF.clk = clk;
    assign pdStageIF.rst = rst;
    assign idStageIF.clk = clk;
    assign idStageIF.rst = rst;
    assign rnStageIF.clk = clk;
    assign rnStageIF.rst = rst;
    assign rnStageIF.rstStart = rstStart;
    assign scStageIF.clk = clk;
    assign scStageIF.rst = rst;

    assign intIsStageIF.clk = clk;
    assign intIsStageIF.rst = rst;
    assign intRrStageIF.clk = clk;
    assign intRrStageIF.rst = rst;
    assign intExStageIF.clk = clk;
    assign intExStageIF.rst = rst;

    assign complexIsStageIF.clk = clk;
    assign complexIsStageIF.rst = rst;
    assign complexRrStageIF.clk = clk;
    assign complexRrStageIF.rst = rst;
    assign complexExStageIF.clk = clk;
    assign complexExStageIF.rst = rst;

    assign memIsStageIF.clk = clk;
    assign memIsStageIF.rst = rst;
    assign memRrStageIF.clk = clk;
    assign memRrStageIF.rst = rst;
    assign memExStageIF.clk = clk;
    assign memExStageIF.rst = rst;
    assign mtStageIF.clk = clk;
    assign mtStageIF.rst = rst;
    assign maStageIF.clk = clk;
    assign maStageIF.rst = rst;

    assign fpIsStageIF.clk = clk;
    assign fpIsStageIF.rst = rst;
    assign fpRrStageIF.clk = clk;
    assign fpRrStageIF.rst = rst;
    assign fpExStageIF.clk = clk;
    assign fpExStageIF.rst = rst;
    assign fpDivSqrtUnitIF.clk = clk;
    assign fpDivSqrtUnitIF.rst = rst;
    assign cmStageIF.clk = clk;
    assign cmStageIF.rst = rst;

    assign cacheSystemIF.clk = clk;
    assign cacheSystemIF.rst = rst;
    assign renameLogicIF.clk = clk;
    assign renameLogicIF.rst = rst;
    assign renameLogicIF.rstStart = rstStart;
    assign activeListIF.clk = clk;
    assign activeListIF.rst = rst;
    assign schedulerIF.clk = clk;
    assign schedulerIF.rst = rst;
    assign schedulerIF.rstStart = rstStart;
    assign wakeupSelectIF.clk = clk;
    assign wakeupSelectIF.rst = rst;
    assign wakeupSelectIF.rstStart = rstStart;
    assign registerFileIF.clk = clk;
    assign registerFileIF.rst = rst;
    assign registerFileIF.rstStart = rstStart;
    assign bypassNetworkIF.clk = clk;
    assign bypassNetworkIF.rst = rst;
    assign bypassNetworkIF.rstStart = rstStart;
    assign loadStoreUnitIF.clk = clk;
    assign loadStoreUnitIF.rst = rst;
    assign loadStoreUnitIF.rstStart = rstStart;
    assign recoveryManagerIF.clk = clk;
    assign recoveryManagerIF.rst = rst;
    assign csrUnitIF.clk = clk;
    assign csrUnitIF.rst = rst;
    assign csrUnitIF.rstStart = rstStart;
    assign csrUnitIF.reqCustomInterrupt = reqCustomInterrupt;
    assign csrUnitIF.customInterruptCode = customInterruptCode;
    assign ioUnitIF.clk = clk;
    assign ioUnitIF.rst = rst;
    assign ioUnitIF.rstStart = rstStart;
    assign serialWE = ioUnitIF.serialWE;
    assign serialWriteData = ioUnitIF.serialWriteDataOut;
    assign mulDivUnitIF.clk = clk;
    assign mulDivUnitIF.rst = rst;
    assign cacheFlushManagerIF.clk = clk;
    assign cacheFlushManagerIF.rst = rst;
    assign amoCacheIF.clk = clk;
    assign amoCacheIF.rst = rst;

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
        ReplayQueue replayQueue( schedulerIF, loadStoreUnitIF, mulDivUnitIF, fpDivSqrtUnitIF, cacheFlushManagerIF, recoveryManagerIF, ctrlIF );
        Scheduler scheduler( schedulerIF, wakeupSelectIF, recoveryManagerIF, mulDivUnitIF, fpDivSqrtUnitIF, debugIF );
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
        MulDivUnit mulDivUnit(mulDivUnitIF, recoveryManagerIF, registerFileIF, activeListIF);

    MemoryIssueStage memIsStage( memIsStageIF, scStageIF, schedulerIF, recoveryManagerIF, mulDivUnitIF, ctrlIF, debugIF );
    MemoryRegisterReadStage memRrStage( memRrStageIF, memIsStageIF, registerFileIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, debugIF );
    MemoryExecutionStage memExStage( memExStageIF, memRrStageIF, loadStoreUnitIF, cacheFlushManagerIF, mulDivUnitIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, csrUnitIF, amoCacheIF, debugIF );
    MemoryTagAccessStage mtStage( mtStageIF, memExStageIF, schedulerIF, loadStoreUnitIF, recoveryManagerIF, ctrlIF, amoCacheIF, debugIF, perfCounterIF );
    MemoryAccessStage maStage( maStageIF, mtStageIF, loadStoreUnitIF, mulDivUnitIF, bypassNetworkIF, ioUnitIF, recoveryManagerIF, ctrlIF, amoCacheIF, debugIF );
        LoadStoreUnit loadStoreUnit( loadStoreUnitIF, ctrlIF );
        LoadQueue loadQueue( loadStoreUnitIF, recoveryManagerIF );
        StoreQueue storeQueue( loadStoreUnitIF, recoveryManagerIF );
        StoreCommitter storeCommitter(loadStoreUnitIF, recoveryManagerIF, ioUnitIF, debugIF, perfCounterIF);
        DCache dCache( loadStoreUnitIF, cacheSystemIF, ctrlIF, recoveryManagerIF);
        AMOCache amocache(amoCacheIF);
    MemoryRegisterWriteStage memRwStage( /*memRwStageIF,*/ maStageIF, loadStoreUnitIF, registerFileIF, activeListIF, recoveryManagerIF, ctrlIF, debugIF );

`ifdef RSD_MARCH_FP_PIPE
    FPIssueStage fpIsStage( fpIsStageIF, scStageIF, schedulerIF, recoveryManagerIF, fpDivSqrtUnitIF, ctrlIF, debugIF );
    FPRegisterReadStage fpRrStage( fpRrStageIF, fpIsStageIF, registerFileIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, debugIF );
    FPExecutionStage fpExStage( fpExStageIF, fpRrStageIF, fpDivSqrtUnitIF, schedulerIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, debugIF, csrUnitIF);
    FPRegisterWriteStage fpRwStage( fpExStageIF, registerFileIF, activeListIF, recoveryManagerIF, ctrlIF, debugIF );
    FPDivSqrtUnit fpDivSqrtUnit(fpDivSqrtUnitIF, recoveryManagerIF);
`endif

    RegisterFile registerFile( registerFileIF );
        BypassController bypassController( bypassNetworkIF, ctrlIF );
        BypassNetwork  bypassNetwork( bypassNetworkIF, ctrlIF );
    
    // A commitment stage generates a flush signal and this is send to scheduler.
    CommitStage cmStage( cmStageIF, renameLogicIF, activeListIF, loadStoreUnitIF, recoveryManagerIF, csrUnitIF, debugIF );
        RecoveryManager recoveryManager( recoveryManagerIF, activeListIF, csrUnitIF, ctrlIF, perfCounterIF );

    CSR_Unit csrUnit(csrUnitIF, perfCounterIF);
    CacheFlushManager cacheFlushManager( cacheFlushManagerIF, cacheSystemIF );
    InterruptController interruptCtrl(csrUnitIF, ctrlIF, npStageIF, recoveryManagerIF);
    IO_Unit ioUnit(ioUnitIF, csrUnitIF);

endmodule : Core
