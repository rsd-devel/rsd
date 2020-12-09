// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// The interface of a load/store unit.
//


import BasicTypes::*;
import MemoryMapTypes::*;
import CacheSystemTypes::*;
import OpFormatTypes::*;
import LoadStoreUnitTypes::*;
import MemoryMapTypes::*;

interface LoadStoreUnitIF( input logic clk, rst, rstStart );

    // Allocation
    logic allocatable;
    logic loadQueueAllocatable;
    logic storeQueueAllocatable;
    logic allocateLoadQueue [ RENAME_WIDTH ];
    logic allocateStoreQueue [ RENAME_WIDTH ];
    LoadQueueIndexPath allocatedLoadQueuePtr [ RENAME_WIDTH ];
    StoreQueueIndexPath allocatedStoreQueuePtr [ RENAME_WIDTH ];

    // Execution
    logic executeLoad [ LOAD_ISSUE_WIDTH ];
    logic executedLoadRegValid [LOAD_ISSUE_WIDTH];
    PhyAddrPath executedLoadAddr [ LOAD_ISSUE_WIDTH ];
    DataPath executedLoadData [ LOAD_ISSUE_WIDTH ];
    PC_Path executedLoadPC  [LOAD_ISSUE_WIDTH ];
    VectorPath executedLoadVectorData [ LOAD_ISSUE_WIDTH ];
    MemAccessMode executedLoadMemAccessMode [ LOAD_ISSUE_WIDTH ];
    StoreQueueIndexPath executedStoreQueuePtrByLoad [ LOAD_ISSUE_WIDTH ];
    LoadQueueIndexPath executedLoadQueuePtrByLoad[ LOAD_ISSUE_WIDTH ];

    logic executeStore [ STORE_ISSUE_WIDTH ];
    logic executedStoreCondEnabled [ STORE_ISSUE_WIDTH ];
    logic executedStoreRegValid [ STORE_ISSUE_WIDTH ];
    PhyAddrPath executedStoreAddr [ STORE_ISSUE_WIDTH ];
    DataPath executedStoreData [ STORE_ISSUE_WIDTH ];
    VectorPath executedStoreVectorData [ STORE_ISSUE_WIDTH ];
    MemAccessMode executedStoreMemAccessMode [ STORE_ISSUE_WIDTH ];
    LoadQueueIndexPath executedLoadQueuePtrByStore [ STORE_ISSUE_WIDTH ];
    StoreQueueIndexPath executedStoreQueuePtrByStore [ STORE_ISSUE_WIDTH ];

    // Commit
    logic commitStore;
    CommitLaneCountPath commitStoreNum;

    // Retire
    logic releaseLoadQueue;
    CommitLaneCountPath releaseLoadQueueEntryNum;


    // Whether to release the head entry(s) of the SQ.
    logic releaseStoreQueueHead;    // For commit

    // The number of released entries.
    CommitLaneCountPath releaseStoreQueueHeadEntryNum;  // For commit


    // ストア結果をキャッシュに書き込む際に SQ から読み出すデータ
    StoreQueueIndexPath retiredStoreQueuePtr;
    LSQ_BlockDataPath retiredStoreData;
    logic retiredStoreCondEnabled;
    LSQ_BlockWordEnablePath retiredStoreWordWE;
    LSQ_WordByteEnablePath retiredStoreByteWE;
    LSQ_BlockAddrPath retiredStoreLSQ_BlockAddr;

    // SQ status.
    logic storeQueueEmpty;
    StoreQueueIndexPath storeQueueHeadPtr;
    StoreQueueCountPath storeQueueCount;

    // Recover
    logic busyInRecovery;


    // Store-Load Forwarding
    logic storeLoadForwarded [ LOAD_ISSUE_WIDTH ];
    LSQ_BlockDataPath forwardedLoadData [ LOAD_ISSUE_WIDTH ];
    logic forwardMiss[ LOAD_ISSUE_WIDTH ];
    
    // DCache
    logic dcReadReq[LOAD_ISSUE_WIDTH];    // Read request from the LSU.
    logic dcReadBusy[LOAD_ISSUE_WIDTH];   // Read ports are busy and cannot accept requests.
    logic dcReadHit[LOAD_ISSUE_WIDTH];

    PhyAddrPath dcReadAddr[LOAD_ISSUE_WIDTH];
    DCacheLinePath dcReadData[LOAD_ISSUE_WIDTH];
    logic dcReadUncachable[LOAD_ISSUE_WIDTH];

    // Forward されたのでメインメモリアクセスや MSHR 確保をキャンセルする 
    // MSHR を確保してしまうと，フォワードしたロードの方はヒット扱いでリタイアするので
    // 永久に MSHR のエントリが解放されない
    logic dcReadCancelFromMT_Stage[LOAD_ISSUE_WIDTH];    

    // MSHRをAllocateした命令かどうか
    logic loadHasAllocatedMSHR[DCACHE_LSU_READ_PORT_NUM];
    MSHR_IndexPath loadMSHRID[DCACHE_LSU_READ_PORT_NUM];
    logic storeHasAllocatedMSHR[DCACHE_LSU_WRITE_PORT_NUM];
    MSHR_IndexPath storeMSHRID[DCACHE_LSU_WRITE_PORT_NUM];

    logic dcWriteReq;     // Same as the read signals.
    logic dcWriteReqAck;
    logic dcWriteBusy;
    logic dcWriteHit;
    PhyAddrPath dcWriteAddr;
    DCacheLinePath dcWriteData;
    DCacheByteEnablePath dcWriteByteWE;
    logic dcWriteUncachable;

    // MSHRからのLoad
    logic mshrAddrHit[LOAD_ISSUE_WIDTH];
    MSHR_IndexPath mshrAddrHitMSHRID[LOAD_ISSUE_WIDTH];
    logic mshrReadHit[LOAD_ISSUE_WIDTH];
    DCacheLinePath mshrReadData[LOAD_ISSUE_WIDTH];

    // MSHRをAllocateした命令からのメモリリクエストかどうか
    // MSHRをAllocateしたLoad命令がMemoryRegisterReadStageでflushされた場合，AllocateされたMSHRは解放可能になる
    logic makeMSHRCanBeInvalidByMemoryRegisterReadStage[MSHR_NUM];

    // そのリクエストがアクセスに成功した場合，AllocateされたMSHRは解放可能になる
    logic makeMSHRCanBeInvalid[LOAD_ISSUE_WIDTH];

    // MSHRをAllocateしたLoad命令がStoreForwardingによって完了した場合，AllocateされたMSHRは解放可能になる
    logic makeMSHRCanBeInvalidByMemoryTagAccessStage[MSHR_NUM];

    // MSHRをAllocateしたLoad命令がReplayQueueの先頭でflushされた場合，AllocateされたMSHRは解放可能になる
    logic makeMSHRCanBeInvalidByReplayQueue[MSHR_NUM];

    // MSHR
    logic mshrValid[MSHR_NUM];
    MSHR_Phase mshrPhase[MSHR_NUM]; // MSHR phase.
    DCacheIndexSubsetPath mshrAddrSubset[MSHR_NUM];

    // Memory dependent prediction
    logic conflict [ STORE_ISSUE_WIDTH ];
    logic memAccessOrderViolation [ STORE_ISSUE_WIDTH ];
    PC_Path conflictLoadPC [ STORE_ISSUE_WIDTH ];
    
    modport DCache(
    input
        clk,
        rst,
        rstStart,
        dcReadReq,
        dcWriteReq,
        dcWriteData,
        dcWriteAddr,
        dcWriteByteWE,
        dcWriteUncachable,
        dcReadAddr,
        dcReadUncachable,
        dcReadCancelFromMT_Stage,
        makeMSHRCanBeInvalidByMemoryRegisterReadStage,
        makeMSHRCanBeInvalid,
        makeMSHRCanBeInvalidByMemoryTagAccessStage,
        makeMSHRCanBeInvalidByReplayQueue,
    output
        dcReadHit,
        dcReadBusy,
        dcReadData,
        dcWriteHit,
        dcWriteBusy,
        dcWriteReqAck,
        mshrAddrHit,
        mshrAddrHitMSHRID,
        mshrAddrSubset,
        mshrReadHit,
        mshrReadData,
        mshrValid,
        mshrPhase,
        loadHasAllocatedMSHR,
        loadMSHRID,
        storeHasAllocatedMSHR,
        storeMSHRID
    );



    modport LoadQueue(
    input
        clk,
        rst,
        allocateLoadQueue,
        executeLoad,
        executedLoadQueuePtrByLoad,
        executedLoadQueuePtrByStore,
        executedLoadAddr,
        executedLoadPC,
        executedLoadRegValid,
        executedStoreAddr,
        executeStore,
        executedLoadMemAccessMode,
        releaseLoadQueue,
        releaseLoadQueueEntryNum,
        executedStoreMemAccessMode,
    output
        allocatedLoadQueuePtr,
        loadQueueAllocatable,
        conflict,
        conflictLoadPC
    );

    modport StoreQueue(
    input
        clk,
        rst,
        allocateStoreQueue,
        executeLoad,
        executedLoadAddr,
        executeStore,
        executedStoreQueuePtrByLoad,
        executedStoreQueuePtrByStore,
        executedStoreAddr,
        executedStoreData,
        executedStoreVectorData,
        executedStoreCondEnabled,
        executedStoreRegValid,
        executedStoreMemAccessMode,
        releaseStoreQueueHead,
        releaseStoreQueueHeadEntryNum,
        retiredStoreQueuePtr,
        executedLoadMemAccessMode,
    output
        allocatedStoreQueuePtr,
        storeQueueAllocatable,
        storeLoadForwarded,
        forwardedLoadData,
        forwardMiss,
        retiredStoreData,
        retiredStoreCondEnabled,
        retiredStoreWordWE,
        retiredStoreByteWE,
        retiredStoreLSQ_BlockAddr,
        storeQueueEmpty,
        storeQueueCount,
        storeQueueHeadPtr
    );

    modport StoreCommitter(
    input
        clk,
        rst,
        commitStore,
        commitStoreNum,
        retiredStoreCondEnabled,
        dcWriteBusy,
        dcWriteHit,
        dcWriteReqAck,
        retiredStoreLSQ_BlockAddr,
        retiredStoreData,
        retiredStoreWordWE,
        retiredStoreByteWE,
        storeQueueEmpty,
        storeQueueCount,
        storeQueueHeadPtr,
        allocatable,
        storeHasAllocatedMSHR,
        storeMSHRID,
        mshrPhase,
    output
        dcWriteReq,
        dcWriteData,
        dcWriteAddr,
        dcWriteByteWE,
        dcWriteUncachable,
        retiredStoreQueuePtr,
        releaseStoreQueueHead,
        busyInRecovery,
        releaseStoreQueueHeadEntryNum
    );

    modport LoadStoreUnit(
    input
        clk,
        rst,
        loadQueueAllocatable,
        storeQueueAllocatable,
        executeLoad,
        executedLoadAddr,
        executedLoadMemAccessMode,
        storeLoadForwarded,
        forwardedLoadData,
        dcReadData,
        busyInRecovery,
        mshrReadHit,
        mshrReadData,
    output
        executedLoadData,
        executedLoadVectorData,
        allocatable
    );

    modport RenameStage(
    input
        allocatable,
        allocatedLoadQueuePtr,
        allocatedStoreQueuePtr,
        storeQueueEmpty,
    output
        allocateLoadQueue,
        allocateStoreQueue
    );

    modport MemoryRegisterReadStage(
    output
        makeMSHRCanBeInvalidByMemoryRegisterReadStage
    );

    modport MemoryExecutionStage(
    input
        clk,
    output
        dcReadReq,
        dcReadAddr,
        dcReadUncachable,
        makeMSHRCanBeInvalid
    );

    modport MemoryTagAccessStage(
    input
        forwardMiss,
        storeLoadForwarded,
        conflict,
        dcReadHit,
        mshrAddrHit,
        mshrAddrHitMSHRID,
        mshrReadHit,
        loadHasAllocatedMSHR,
        loadMSHRID,
    output
        dcReadCancelFromMT_Stage,
        executeLoad,
        executedLoadQueuePtrByLoad,
        executedLoadQueuePtrByStore,
        executedLoadAddr,
        executedLoadPC,
        executedLoadRegValid,
        executeStore,
        executedStoreQueuePtrByLoad,
        executedStoreQueuePtrByStore,
        executedStoreData,
        executedStoreVectorData,
        executedStoreAddr,
        executedStoreCondEnabled,
        executedStoreRegValid,
        executedLoadMemAccessMode,
        executedStoreMemAccessMode,
        makeMSHRCanBeInvalidByMemoryTagAccessStage,
        memAccessOrderViolation
    );

    modport MemoryAccessStage(
    input
        executedLoadData,
        executedLoadVectorData
    );

    modport ReplayQueue(
    input
        mshrValid,
        mshrPhase,
        mshrAddrSubset,
    output
        makeMSHRCanBeInvalidByReplayQueue
    );

    modport CommitStage(
    input
        busyInRecovery,
    output
        releaseLoadQueue,
        releaseLoadQueueEntryNum,
        commitStore,
        commitStoreNum
    );

    modport MemoryDependencyPredictor(
    input
        memAccessOrderViolation,
        conflictLoadPC
    );

endinterface : LoadStoreUnitIF


