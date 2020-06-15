// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// 2-read/write set-associative data cache
//

import BasicTypes::*;
import OpFormatTypes::*;
import CacheSystemTypes::*;
import OpFormatTypes::*;
import MemoryMapTypes::*;

interface DCacheIF(
input
    logic clk,
    logic rst,
    logic rstStart
);
    // Tag array
    logic           tagArrayWE[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];
    DCacheIndexPath tagArrayIndexIn[DCACHE_ARRAY_PORT_NUM];
    DCacheTagPath   tagArrayDataIn [DCACHE_ARRAY_PORT_NUM];
    logic           tagArrayValidIn[DCACHE_ARRAY_PORT_NUM];
    DCacheTagPath   tagArrayDataOut[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];
    logic           tagArrayValidOut[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];

    // Data array
    logic           dataArrayWE[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];
    DCacheIndexPath dataArrayIndexIn[DCACHE_ARRAY_PORT_NUM];
    DCacheLinePath  dataArrayDataIn[DCACHE_ARRAY_PORT_NUM];
    DCacheLinePath  dataArrayDataOut[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];
    DCacheByteEnablePath dataArrayByteWE_In[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];
    logic  dataArrayDirtyIn[DCACHE_ARRAY_PORT_NUM];
    logic  dataArrayDirtyOut[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];


    // Port arbiter input/output
    logic           lsuCacheReq[DCACHE_LSU_PORT_NUM];
    logic           lsuCacheGrt[DCACHE_LSU_PORT_NUM];
    DCachePortMultiplexerIn lsuMuxIn[DCACHE_LSU_PORT_NUM];
    DCachePortMultiplexerTagOut lsuMuxTagOut[DCACHE_LSU_PORT_NUM];
    DCachePortMultiplexerDataOut lsuMuxDataOut[DCACHE_LSU_PORT_NUM];    // Data array outputs are pipelined.

    // MSHR<>Array
    logic           mshrCacheReq[MSHR_NUM];
    logic           mshrCacheGrt[MSHR_NUM];
    DCachePortMultiplexerIn mshrCacheMuxIn[MSHR_NUM];
    DCachePortMultiplexerTagOut mshrCacheMuxTagOut[MSHR_NUM];
    DCachePortMultiplexerDataOut mshrCacheMuxDataOut[MSHR_NUM];    // Data array outputs are pipelined.

    // Multiplexer
    DCacheMuxPortIndexPath  cacheArrayInSel[DCACHE_ARRAY_PORT_NUM];
    DCacheArrayPortIndex    cacheArrayOutSel[DCACHE_MUX_PORT_NUM];

    // MSHR<>Memory
    logic mshrMemReq[MSHR_NUM];
    logic mshrMemGrt[MSHR_NUM];
    MemoryPortMultiplexerIn mshrMemMuxIn[MSHR_NUM];
    MemoryPortMultiplexerOut mshrMemMuxOut[MSHR_NUM];
    MSHR_IndexPath memInSel;

    // Memory
    PhyAddrPath memAddr;
    DCacheLinePath memData;
    logic memValid;
    logic memWE;
    logic memReqAck;           // Request is accpeted or not.
    MemAccessSerial memSerial; // Read request serial
    MemAccessResult memAccessResult;
    MemWriteSerial memWSerial; // Write request serial
    MemAccessResponse memAccessResponse;

    // Miss handler
    logic initMSHR[MSHR_NUM];
    PhyAddrPath initMSHR_Addr[MSHR_NUM];

    logic mshrValid[MSHR_NUM];
    PhyAddrPath mshrAddr[MSHR_NUM];

    MSHR_Phase mshrPhase[MSHR_NUM]; // MSHR phase.
    DCacheLinePath mshrData[MSHR_NUM]; // Data in MSHR.
    DCacheIndexSubsetPath mshrAddrSubset[MSHR_NUM];

    logic mshrCanBeInvalid[MSHR_NUM];
    logic isAllocatedByStore[MSHR_NUM];

    logic isUncachable[MSHR_NUM];

    // MSHRをAllocateしたLoad命令がMemoryRegisterReadStageでflushされた場合，AllocateされたMSHRは解放可能になる
    logic makeMSHRCanBeInvalidByMemoryRegisterReadStage[MSHR_NUM];

    // MSHRをAllocateしたLoad命令がStoreForwardingによって完了した場合，AllocateされたMSHRは解放可能になる
    logic makeMSHRCanBeInvalidByMemoryTagAccessStage[MSHR_NUM];

    // MSHRをAllocateしたLoad命令がReplayQueueの先頭でflushされた場合，AllocateされたMSHRは解放可能になる
    logic makeMSHRCanBeInvalidByReplayQueue[MSHR_NUM];

    VectorPath storedLineData;
    logic [DCACHE_LINE_BYTE_NUM-1:0] storedLineByteWE;

    modport DCacheArrayPortArbiter(
    input
        lsuCacheReq,
        mshrCacheReq,
    output
        lsuCacheGrt,
        mshrCacheGrt,
        cacheArrayInSel,
        cacheArrayOutSel
    );

    modport DCacheArrayPortMultiplexer(
    input
        clk,
        rst,
        rstStart,
        mshrCacheMuxIn,
        lsuMuxIn,
        tagArrayDataOut,
        tagArrayValidOut,
        dataArrayDataOut,
        cacheArrayInSel,
        cacheArrayOutSel,
        dataArrayDirtyOut,
        mshrAddr,
        mshrValid,
        mshrPhase,
        mshrData,
    output
        mshrCacheMuxTagOut,
        mshrCacheMuxDataOut,
        lsuMuxTagOut,
        lsuMuxDataOut,
        tagArrayWE,
        tagArrayIndexIn,
        tagArrayDataIn,
        tagArrayValidIn,
        dataArrayWE,
        dataArrayIndexIn,
        dataArrayDataIn,
        dataArrayDirtyIn,
        dataArrayByteWE_In,
        mshrCanBeInvalid
    );


    modport DCacheMemoryReqPortArbiter(
    input
        mshrMemReq,
    output
        mshrMemGrt,
        memInSel,
        memValid
    );

    modport DCacheMemoryReqPortMultiplexer(
    input
        memReqAck,
        memSerial,
        memWSerial,
        mshrMemMuxIn,
        memInSel,
    output
        memAddr,
        memData,
        memWE,
        mshrMemMuxOut
    );

    modport DCacheMissHandler(
    input
        clk,
        rst,
        initMSHR,
        initMSHR_Addr,
        mshrCacheGrt,
        mshrCacheMuxTagOut,
        mshrCacheMuxDataOut,
        mshrMemGrt,
        mshrMemMuxOut,
        memAccessResult,
        memAccessResponse,
        mshrCanBeInvalid,
        isAllocatedByStore,
        isUncachable,
        makeMSHRCanBeInvalidByMemoryRegisterReadStage,
        makeMSHRCanBeInvalidByMemoryTagAccessStage,
        makeMSHRCanBeInvalidByReplayQueue,
        storedLineData,
        storedLineByteWE,
    output
        mshrCacheReq,
        mshrCacheMuxIn,
        mshrMemReq,
        mshrMemMuxIn,
        mshrValid,
        mshrAddr,
        mshrPhase,
        mshrData,
        mshrAddrSubset
    );

    modport DCacheArray(
    input
        clk,
        rst,
        rstStart,
        tagArrayWE,
        tagArrayIndexIn,
        tagArrayDataIn,
        tagArrayValidIn,
        dataArrayDataIn,
        dataArrayIndexIn,
        dataArrayDirtyIn,
        dataArrayByteWE_In,
        dataArrayWE,
    output
        tagArrayDataOut,
        tagArrayValidOut,
        dataArrayDataOut,
        dataArrayDirtyOut
    );



    modport DCache(
    input
        clk,
        rst,
        lsuCacheGrt,
        lsuMuxTagOut,
        lsuMuxDataOut,
        memAddr,
        memData,
        memWE,
        memValid,
        mshrValid,
        mshrAddr,
        mshrPhase,
        mshrAddrSubset,
    output
        lsuCacheReq,
        lsuMuxIn,
        memReqAck,
        memSerial,
        memWSerial,
        memAccessResponse,
        initMSHR,
        initMSHR_Addr,
        isAllocatedByStore,
        isUncachable,
        makeMSHRCanBeInvalidByMemoryRegisterReadStage,
        makeMSHRCanBeInvalidByMemoryTagAccessStage,
        makeMSHRCanBeInvalidByReplayQueue,
        storedLineData,
        storedLineByteWE
    );

endinterface
