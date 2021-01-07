// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Store queue
//

`include "BasicMacros.sv"

import BasicTypes::*;
import CacheSystemTypes::*;
import OpFormatTypes::*;
import LoadStoreUnitTypes::*;
import MemoryMapTypes::*;
import DebugTypes::*;

module StoreCommitter(
    LoadStoreUnitIF.StoreCommitter port,
    RecoveryManagerIF.StoreCommitter recovery,
    IO_UnitIF.StoreCommitter ioUnit,
    DebugIF.StoreCommitter debug,
    PerformanceCounterIF.StoreCommitter perfCounter
);

    // State machine
    typedef enum logic
    {
        PHASE_COMMIT = 0,
        PHASE_RECOVER = 1
    } Phase;
    Phase phase;
    Phase nextPhase;

    StoreQueueCountPath unfinishedStoreNum;
    StoreQueueCountPath nextUnfinishedStoreNum;

    always_ff @( posedge port.clk ) begin
        if (port.rst) begin
            phase <= PHASE_COMMIT;
            unfinishedStoreNum <= '0;
        end
        else begin
            phase <= nextPhase;
            unfinishedStoreNum <= nextUnfinishedStoreNum;
        end
    end

    always_comb begin
        // Decide a next phase.
        if(port.rst) begin
            nextPhase = PHASE_COMMIT;
        end
        else if (recovery.toRecoveryPhase) begin
            nextPhase = PHASE_RECOVER;
        end
        else if (phase == PHASE_RECOVER ) begin
            // All entries are released.
            // Store Queue is recovered in one cycle.
            nextPhase = PHASE_COMMIT;
        end
        else begin
            nextPhase = phase;
        end
    end

    MSHR_Phase portMSHRPhase[MSHR_NUM];
    logic portStoreHasAllocatedMSHR;
    MSHR_IndexPath portStoreMSHRID;
    always_comb begin
        for (int i = 0; i < MSHR_NUM; i++) begin
            portMSHRPhase[i] = port.mshrPhase[i];
        end
        portStoreHasAllocatedMSHR = port.storeHasAllocatedMSHR[0];
        portStoreMSHRID = port.storeMSHRID[0];
    end


    // The pipeline register of store commit pipeline.
    logic stallStoreTagStage;
    typedef struct packed {
        logic valid;
        logic condEnabled;
        LSQ_BlockDataPath data;
        LSQ_BlockAddrPath blockAddr;
        LSQ_BlockWordEnablePath wordWE;
        LSQ_WordByteEnablePath byteWE;
        logic isIO;
        logic isUncachable;
    } StgReg;

    StgReg tagStagePipeReg;
    StgReg nextTagStagePipeReg;
    StgReg dataStagePipeReg;
    StgReg nextDataStagePipeReg;
    logic headStoreHasAllocatedMSHRPipeReg;
    MSHR_IndexPath storeMSHRID;

    always_ff @( posedge port.clk ) begin
        if (port.rst) begin
            tagStagePipeReg <= '0;
            dataStagePipeReg <= '0;
            headStoreHasAllocatedMSHRPipeReg <= FALSE;
            storeMSHRID <= '0;
        end
        else begin
            if (!stallStoreTagStage) begin
                tagStagePipeReg <= nextTagStagePipeReg;
            end
            dataStagePipeReg <= nextDataStagePipeReg;

            // Memorize whether a head store has allocated a MSHR entry or not.
            if (!stallStoreTagStage) begin
                headStoreHasAllocatedMSHRPipeReg <= FALSE;
            end
            else if (!headStoreHasAllocatedMSHRPipeReg) begin
                headStoreHasAllocatedMSHRPipeReg <= portStoreHasAllocatedMSHR;
            end

            // Memorize the allocated mshr id when the head store allocates a mshr entry.
            if (portStoreHasAllocatedMSHR) begin
                storeMSHRID <= portStoreMSHRID;
            end
        end
    end

    // Generate DCache write enable signals.
    function automatic DCacheByteEnablePath GenerateDCacheWriteEnable(
        LSQ_BlockWordEnablePath wordWE,
        LSQ_WordByteEnablePath byteWE, 
        LSQ_BlockAddrPath blockAddr
    );
        DCacheByteEnablePath ret;
        LSQ_WordByteEnablePath [LSQ_BLOCK_WORD_WIDTH-1:0] we;

        for (int i = 0; i < LSQ_BLOCK_WORD_WIDTH; i++) begin
            if (wordWE[i])
                we[i] = byteWE;
            else
                we[i] = '0;
        end

        // LSQ block to DCache
        ret = we;
        ret = ret << (
            LSQ_BLOCK_BYTE_WIDTH * 
            LSQ_SelectBits(blockAddr, 0, DCACHE_LINE_BYTE_NUM_BIT_WIDTH-LSQ_BLOCK_BYTE_WIDTH_BIT_SIZE)
        );
        return ret;
    endfunction

    function automatic DCacheLinePath GenerateDCacheLine(
        LSQ_BlockDataPath data
    );
        // WE で不要な部分は落とされるので，単純にデュプリケートする
        DCacheLinePath line;
        line = '0;
        for (int i = 0; i < DCACHE_LINE_BYTE_NUM/LSQ_BLOCK_BYTE_WIDTH; i++) begin
             line[i*LSQ_BLOCK_WIDTH +: LSQ_BLOCK_WIDTH] = data;
        end
        return line;
    endfunction


    // Pipeline stage structure:
    // | Commit | SQ | Tag | Data
    //
    // Commit: The processor commit stage.
    //
    // SQ:      Read a store queue entry.
    // Tag:     Access tag array & hit/miss detection.
    // Data:    Write data array.


    logic dcWriteReq;
    PhyAddrPath dcWriteAddr;
    DCacheLinePath dcWriteData;
    logic dcWriteUncachable;
    logic isIO;
    logic [DCACHE_LINE_BYTE_NUM-1:0] dcWriteByteWE;
    logic isUncachable;
    StoreQueueIndexPath retiredStoreQueuePtr;
    // --- SQ stage.
    always_comb begin
        retiredStoreQueuePtr =
            port.storeQueueHeadPtr +
            (tagStagePipeReg.valid ? 1 : 0) +
            (dataStagePipeReg.valid ? 1 : 0);
        if (retiredStoreQueuePtr >= STORE_QUEUE_ENTRY_NUM) begin
            // Compensate the index to point in the store queue
            retiredStoreQueuePtr -= STORE_QUEUE_ENTRY_NUM;
        end

        port.retiredStoreQueuePtr = retiredStoreQueuePtr;

        nextUnfinishedStoreNum = unfinishedStoreNum;
        if (port.commitStore) begin
            nextUnfinishedStoreNum += port.commitStoreNum;
        end

        isIO = 
            IsPhyAddrIO(
                LSQ_ToFullPhyAddrFromBlockAddrAndWordWE(
                    port.retiredStoreLSQ_BlockAddr, port.retiredStoreWordWE
                )
            );
        
        isUncachable =
            IsPhyAddrUncachable(
                LSQ_ToFullPhyAddrFromBlockAddrAndWordWE(
                    port.retiredStoreLSQ_BlockAddr, port.retiredStoreWordWE
                )
            );

        port.busyInRecovery = phase == PHASE_RECOVER;

        if (unfinishedStoreNum == 0) begin
            // There is no entry for pushing to the store commit pipeline.
            nextTagStagePipeReg = '0;
            nextTagStagePipeReg.valid = FALSE;
            dcWriteReq = FALSE;
        end
        else begin
            nextTagStagePipeReg.isIO = isIO;
            nextTagStagePipeReg.isUncachable = isUncachable;

            // Push an store access to the store commit pipeline.
            if (!port.retiredStoreCondEnabled || isIO) begin
                dcWriteReq = FALSE;
                nextTagStagePipeReg.valid = TRUE;   // Push for releasing an entry..
            end
            else begin
                dcWriteReq = !stallStoreTagStage;
                nextTagStagePipeReg.valid = port.dcWriteReqAck;
            end

            nextTagStagePipeReg.condEnabled = port.retiredStoreCondEnabled;
            nextTagStagePipeReg.blockAddr = port.retiredStoreLSQ_BlockAddr;
            nextTagStagePipeReg.data = port.retiredStoreData;
            nextTagStagePipeReg.wordWE = port.retiredStoreWordWE;
            nextTagStagePipeReg.byteWE = port.retiredStoreByteWE;

            if (!stallStoreTagStage && nextTagStagePipeReg.valid) begin
                nextUnfinishedStoreNum--;
            end

        end

        if (stallStoreTagStage) begin
            // When a head store has allocated a mshr entry, it skips writebacking its data.
            if (headStoreHasAllocatedMSHRPipeReg) begin
                dcWriteReq = FALSE;
            end
            else begin
                dcWriteReq = tagStagePipeReg.condEnabled;
            end

            dcWriteAddr =
                LSQ_ToFullAddrFromBlockAddr(tagStagePipeReg.blockAddr);
            dcWriteData =
                GenerateDCacheLine(tagStagePipeReg.data);
            dcWriteByteWE =
                GenerateDCacheWriteEnable(tagStagePipeReg.wordWE, tagStagePipeReg.byteWE, tagStagePipeReg.blockAddr);
            dcWriteUncachable = 
                tagStagePipeReg.isUncachable;
        end
        else begin
            dcWriteAddr =
                LSQ_ToFullAddrFromBlockAddr(port.retiredStoreLSQ_BlockAddr);
            dcWriteData = 
                GenerateDCacheLine(port.retiredStoreData);
            dcWriteByteWE =
                GenerateDCacheWriteEnable(port.retiredStoreWordWE, port.retiredStoreByteWE, port.retiredStoreLSQ_BlockAddr);
            dcWriteUncachable =
                isUncachable;
        end

        port.dcWriteReq = dcWriteReq;
        port.dcWriteData = dcWriteData;
        port.dcWriteByteWE = dcWriteByteWE;
        port.dcWriteAddr = dcWriteAddr;
        port.dcWriteUncachable = dcWriteUncachable;
    end

    // --- Tag stage
    logic finishWriteBack;
    always_comb begin
        finishWriteBack = FALSE;
        if (tagStagePipeReg.valid) begin
            if(!tagStagePipeReg.condEnabled || tagStagePipeReg.isIO) begin
                stallStoreTagStage = FALSE;
            end
            else if (headStoreHasAllocatedMSHRPipeReg) begin
                // When a head store has allocated a mshr entry, stall until its data is written to cache by MSHR.
                if (portMSHRPhase[storeMSHRID] > MSHR_PHASE_MISS_WRITE_CACHE_REQUEST) begin
                    stallStoreTagStage = FALSE;
                    finishWriteBack = TRUE;
                end
                else begin
                    stallStoreTagStage = TRUE;
                end
            end
            else begin
                stallStoreTagStage = !port.dcWriteHit;   // Stall if miss!
            end
        end
        else begin
            stallStoreTagStage = FALSE;
        end

        nextDataStagePipeReg = tagStagePipeReg;
        if (stallStoreTagStage) begin
            nextDataStagePipeReg.valid = FALSE;
        end

`ifndef RSD_DISABLE_PERFORMANCE_COUNTER
        for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
            perfCounter.storeMiss[i] = i == 0 ? finishWriteBack : FALSE;  // Only supports a single store port 
        end
`endif
    end

    // Whether to release the head entry(s) of the SQ.
    logic releaseStoreQueueHead;
    // The number of released entries.
    CommitLaneCountPath releaseStoreQueueHeadEntryNum;
    // --- Data stage
    always_comb begin
        ioUnit.ioWE = FALSE;
        ioUnit.ioWriteDataIn = 
            LSQ_ToScalarWordDataFromBlockData(dataStagePipeReg.data, dataStagePipeReg.wordWE);
        ioUnit.ioWriteAddrIn = 
            LSQ_ToFullPhyAddrFromBlockAddrAndWordWE(dataStagePipeReg.blockAddr, dataStagePipeReg.wordWE);
        if (dataStagePipeReg.valid) begin
            releaseStoreQueueHeadEntryNum = 1;
            releaseStoreQueueHead = TRUE;  // Ops whose conditions are not invalid must be released.
            if (dataStagePipeReg.condEnabled && dataStagePipeReg.isIO) begin
                ioUnit.ioWE = TRUE;
            end
        end
        else begin
            releaseStoreQueueHeadEntryNum = 0;
            releaseStoreQueueHead = FALSE;
        end

        port.releaseStoreQueueHeadEntryNum = releaseStoreQueueHeadEntryNum;
        port.releaseStoreQueueHead = releaseStoreQueueHead;
    end

`ifndef RSD_DISABLE_DEBUG_REGISTER
    always_comb begin
        debug.loadStoreUnitAllocatable = port.allocatable;
        debug.storeCommitterPhase = phase;
        debug.storeQueueCount = port.storeQueueCount;
        debug.busyInRecovery = port.busyInRecovery;
        debug.storeQueueEmpty = port.storeQueueEmpty;
    end
`endif

    `RSD_ASSERT_CLK(
        port.clk,
        port.rst || (unfinishedStoreNum <= STORE_QUEUE_ENTRY_NUM),
        "Committed store num is larger than store queue entry num." 
    );


    `RSD_ASSERT_CLK(
        port.clk,
        port.rst || !(phase == PHASE_RECOVER && port.commitStore && port.commitStoreNum > 0),
        "Stores are committed in recovery phase." 
    );

endmodule : StoreCommitter

