// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// 2-read/write set-associative data cache
//

// --- Uncachable load/store
// Uncachable loads always receive data from a data bus. They never update cache.
// Uncachable stores always write data directly to memory. 
// They first receive data from the data bus in a cache line granularity, 
// update the cache line, and then send it back to the data bus. They never update cache.
//
// MSHRs play a key role as below:
// Every uncachable load/store misses in cache and allocates an MSHR.
// The MSHR issues a memory read request to the data bus in a cache line granularity.
// A load receives data from the MSHR and deallocates it.
// A store merges its data and the loaded cache line, and then the MSHR sends the merged data to the data bus.
//
// Uncachable stores must firstly load data from a data bus for simplicity of the current implementation, 
// in which the current implementation always send a write request to the AXI data bus in cache line granularity.

`include "BasicMacros.sv"

import BasicTypes::*;
import OpFormatTypes::*;
import CacheSystemTypes::*;
import OpFormatTypes::*;
import MemoryMapTypes::*;
import LoadStoreUnitTypes::*;

// Merge stored data and fetched line.
function automatic void MergeStoreDataToLine(
    output DCacheLinePath dstLine,
    input DCacheLinePath fetchedLine,
    input DCacheLinePath storedLine,
    input logic [DCACHE_LINE_BYTE_NUM-1:0] storedDirty
);
    for (int i = 0; i < DCACHE_LINE_BYTE_NUM; i++) begin
        for (int b = 0; b < 8; b++) begin
            dstLine[i*8 + b] = storedDirty[i] ? storedLine[i*8 + b] : fetchedLine[i*8 + b];
        end
    end
endfunction



// To a line address (index+tag) from a full address.
function automatic PhyAddrPath ToLineAddrFromFullAddr(input PhyAddrPath addr);
    return {
        addr[PHY_ADDR_WIDTH-1 : DCACHE_LINE_BYTE_NUM_BIT_WIDTH],
        { DCACHE_LINE_BYTE_NUM_BIT_WIDTH{1'b0} }
    };
endfunction

// To a line address (index+tag) part from a full address.
function automatic DCacheLineAddr ToLinePartFromFullAddr(input PhyAddrPath addr);
    return addr[PHY_ADDR_WIDTH-1 : DCACHE_LINE_BYTE_NUM_BIT_WIDTH];
endfunction

// To a line index from a full address.
function automatic DCacheIndexPath ToIndexPartFromFullAddr(input PhyAddrPath addr);
    return addr[PHY_ADDR_WIDTH-DCACHE_TAG_BIT_WIDTH-1 : DCACHE_LINE_BYTE_NUM_BIT_WIDTH];
endfunction

// To a line tag from a full address.
function automatic DCacheTagPath ToTagPartFromFullAddr(input PhyAddrPath addr);
    return addr[PHY_ADDR_WIDTH - 1 : PHY_ADDR_WIDTH - DCACHE_TAG_BIT_WIDTH];
endfunction

// Build a full address from index and tag parts.
function automatic PhyAddrPath BuildFullAddr(input DCacheIndexPath index, input DCacheTagPath tag);
    return {
        tag,
        index,
        { DCACHE_LINE_BYTE_NUM_BIT_WIDTH{1'b0} }
    };
endfunction

// To a part of a line index from a full address.
function automatic DCacheIndexSubsetPath ToIndexSubsetPartFromFullAddr(input PhyAddrPath addr);
    return addr[DCACHE_LINE_BYTE_NUM_BIT_WIDTH+DCACHE_INDEX_SUBSET_BIT_WIDTH-1 : DCACHE_LINE_BYTE_NUM_BIT_WIDTH];
endfunction

// 0-cleared MSHR entry.
function automatic MissStatusHandlingRegister ClearedMSHR();
    MissStatusHandlingRegister mshr;
    mshr = '0;
    return mshr;
endfunction

//
// Tree-LRU replacement
// https://en.wikipedia.org/wiki/Pseudo-LRU
//

// Calculate an evicted way based on the current state.
function automatic DCacheWayPath 
TreeLRU_CalcEvictedWay(DCacheTreeLRU_StatePath state);
    DCacheWayPath evicted = 0;  // An evicted way number
    int pos = 0;                // A head position of the current level
    for (int i = 0; i < DCACHE_WAY_BIT_NUM; i++) begin
        evicted = (evicted << 1) + (state[pos + evicted] ? 0 : 1);
        pos += (1 << i);    // Each level has (1<<i) bits
    end
    return evicted;
endfunction

// Calculate an updated bit vector that represents a binary tree of tree-LRU
function automatic DCacheTreeLRU_StatePath
TreeLRU_CalcUpdatedState(DCacheWayPath way);
    DCacheTreeLRU_StatePath next = 0;
    int pos = 0;    // A head position of the current level
    // A way number bits are scanned from the MSB
    for (int i = 0; i < DCACHE_WAY_BIT_NUM; i++) begin
        for (int j = 0; j < (1 << i); j++) begin
            next[pos + j] = way[DCACHE_WAY_BIT_NUM - 1 - i];    
        end
        pos += (1 << i);
    end
    return next;
endfunction

// Calculate a bit vector that represents write enable signals
function automatic DCacheTreeLRU_StatePath
TreeLRU_CalcWriteEnable(logic weIn, DCacheWayPath way);
    int pos = 0;
    int c = 0;  // The next updated pos
    DCacheTreeLRU_StatePath we = '0;
    // A way number bits are scanned from the MSB
    for (int i = 0; i < DCACHE_WAY_BIT_NUM; i++) begin
        we[pos + c] = weIn;
        c = (c << 1) + way[DCACHE_WAY_BIT_NUM - 1 - i];
        pos += (1 << i);
    end
    return we;
endfunction

//
// Controller to handle the state of DCache.
//
module DCacheController(DCacheIF.DCacheController port);

    // DCache state
    DCachePhase regPhase, nextPhase;

    // For flush
    logic dcFlushReqAck;
    logic dcFlushComplete;
    logic mshrBusy;
    logic loadStoreBusy;

    // DCache phase
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            regPhase <= DCACHE_PHASE_NORMAL;
        end
        else begin
            regPhase <= nextPhase;
        end
    end

    always_comb begin
        nextPhase = regPhase;
        dcFlushReqAck = FALSE;
        dcFlushComplete = FALSE;
        mshrBusy = FALSE;
        loadStoreBusy = FALSE;

        case (regPhase)
        default: begin
            nextPhase = DCACHE_PHASE_NORMAL;
        end
        DCACHE_PHASE_NORMAL: begin
            for (int i = 0; i < MSHR_NUM; i++) begin
                if (port.mshrPhase[i] != MSHR_PHASE_INVALID) begin
                    // MSHRs are not free
                    mshrBusy = TRUE;
                end
            end
            for (int i = 0; i < DCACHE_LSU_PORT_NUM; i++) begin
                if (port.lsuCacheGrtReg[i] || port.lsuCacheGrt[i]) begin
                    // Load or store inflight
                    loadStoreBusy = TRUE;
                end
            end

            // DCache can enter the flush phase when MSHRs are free.
            // MSHR can be busy when a preceding load of fence.i allocated the MSHR 
            // but was subsequently flushed.
            dcFlushReqAck = !mshrBusy;
            if (port.dcFlushReq && dcFlushReqAck) begin
                nextPhase = DCACHE_PHASE_FLUSH_PROCESSING;
            end
        end
        DCACHE_PHASE_FLUSH_PROCESSING: begin
            if (port.mshrFlushComplete) begin
                nextPhase = DCACHE_PHASE_FLUSH_COMPLETE;
            end
        end
        DCACHE_PHASE_FLUSH_COMPLETE: begin
            dcFlushComplete = TRUE;
            if (port.flushComplete) begin
                nextPhase = DCACHE_PHASE_NORMAL;
            end
        end
        endcase

        // DCache -> cacheFlushManagemer
        port.dcFlushReqAck = dcFlushReqAck;
        port.dcFlushComplete = dcFlushComplete;

        // DCache controller -> DCache submodules
        port.dcFlushing = (regPhase == DCACHE_PHASE_FLUSH_PROCESSING);
    end

    `RSD_ASSERT_CLK(
        port.clk,
        !(loadStoreBusy && port.dcFlushReq && dcFlushReqAck),
        "Inflight load or store is found on DC flush request acquirement."
    );

endmodule : DCacheController

//
// The arbiter of the ports of the main memory.
//
module DCacheMemoryReqPortArbiter(DCacheIF.DCacheMemoryReqPortArbiter port);

    logic req[MSHR_NUM];
    logic grant[MSHR_NUM];
    MSHR_IndexPath memInSel;
    logic memValid;

    always_comb begin
        // Clear
        for (int r = 0; r < MSHR_NUM; r++) begin
            grant[r] = FALSE;
            req[r] = port.mshrMemReq[r];
        end

        // Arbitrate
        memInSel = '0;
        memValid = FALSE;
        for (int r = 0; r < MSHR_NUM; r++) begin
            if (req[r]) begin
                grant[r] = TRUE;
                memInSel = r;
                memValid = TRUE;
                break;
            end
        end

        // Outputs
        port.memInSel = memInSel;
        port.memValid = memValid;
        for (int r = 0; r < MSHR_NUM; r++) begin
            port.mshrMemGrt[r] = grant[r];
        end
    end

endmodule : DCacheMemoryReqPortArbiter

//
// Multiplexer for a memory signals
//

module DCacheMemoryReqPortMultiplexer(DCacheIF.DCacheMemoryReqPortMultiplexer port);

    MSHR_IndexPath portIn;
    always_comb begin

        portIn = port.memInSel;

        port.memAddr = port.mshrMemMuxIn[portIn].addr;
        port.memData = port.mshrMemMuxIn[portIn].data;
        port.memWE = port.mshrMemMuxIn[portIn].we;

        for (int i = 0; i < MSHR_NUM; i++) begin
            port.mshrMemMuxOut[i].ack = port.memReqAck;
            port.mshrMemMuxOut[i].serial = port.memSerial;
            port.mshrMemMuxOut[i].wserial = port.memWSerial;
        end

    end

endmodule : DCacheMemoryReqPortMultiplexer


//
// An arbiter of the ports of the tag/data array.
//
// 以下2カ所から来る合計 R 個のアクセス要求に対して，最大 DCache のポート分だけ grant を返す
//   load unit/store unit: port.lsuCacheReq 
//   mshr の全エントリ:     mshrCacheReq    
//
//   cacheArrayInGrant[p]=TRUE or FALSE 
//     割り当ての結果，キャッシュの p 番目のポートに要求が来たかどうか
//   cacheArrayInSel[P] = r: 
//     上記の R 個 リクエストのうち，r 番目 が
//     キャッシュの p 番目のポートに割り当てられた
//   cacheArrayOutSel[r] = p: 
//     上記の R 個 リクエストのうち，r 番目 が
//     キャッシュの p 番目のポートに割り当てられた
//
// 典型的には，
//   grant[0]: load, grant[1]: store, grant[2],grant[3]...: mshr
//
module DCacheArrayPortArbiter(DCacheIF.DCacheArrayPortArbiter port);

    logic req[DCACHE_MUX_PORT_NUM];
    logic grant[DCACHE_MUX_PORT_NUM];

    DCacheMuxPortIndexPath cacheArrayInSel[DCACHE_ARRAY_PORT_NUM];
    DCacheArrayPortIndex   cacheArrayOutSel[DCACHE_MUX_PORT_NUM];
    logic                  cacheArrayInGrant[DCACHE_ARRAY_PORT_NUM];

    always_comb begin
        // Clear
        for (int r = 0; r < DCACHE_MUX_PORT_NUM; r++) begin
            cacheArrayOutSel[r] = '0;
            grant[r] = FALSE;
        end

        // Merge inputs.
        for (int r = 0; r < DCACHE_LSU_PORT_NUM; r++) begin
            if (port.dcFlushing) begin
                // Only MSHRs can be processed during flush.
                req[r] = FALSE;
            end
            else begin
            req[r] = port.lsuCacheReq[r];
        end
        end
        for (int r = 0; r < MSHR_NUM; r++) begin
            req[r + DCACHE_LSU_PORT_NUM] = port.mshrCacheReq[r];
        end

        // Arbitrate
        for (int p = 0; p < DCACHE_ARRAY_PORT_NUM; p++ ) begin
            cacheArrayInGrant[p] = FALSE;
            cacheArrayInSel[p] = '0;
            for (int r = 0; r < DCACHE_MUX_PORT_NUM; r++) begin
                if (req[r]) begin
                    req[r] = FALSE;
                    grant[r] = TRUE;
                    cacheArrayInSel[p] = r;
                    cacheArrayOutSel[r] = p;
                    cacheArrayInGrant[p] = TRUE;
                    break;
                end
            end
        end

        // Outputs
        port.cacheArrayInSel = cacheArrayInSel;
        port.cacheArrayInGrant = cacheArrayInGrant;
        port.cacheArrayOutSel = cacheArrayOutSel;

        for (int r = 0; r < DCACHE_LSU_PORT_NUM; r++) begin
            port.lsuCacheGrt[r] = grant[r];
        end
        for (int r = 0; r < MSHR_NUM; r++) begin
            port.mshrCacheGrt[r] = grant[r + DCACHE_LSU_PORT_NUM];
        end
    end

endmodule : DCacheArrayPortArbiter



//
// Multiplexer for d-cache signals
//
// DCacheArrayPortArbiter でアービトレーションした結果に基づき，
// DCache の各ポートと load/store/mshr の各ユニットをスイッチする．
// DCache アクセスはパイプライン化されているため，スイッチもパイプラインの各ステージ
// にあわせて行われる．
//
module DCacheArrayPortMultiplexer(DCacheIF.DCacheArrayPortMultiplexer port);

    DCacheMuxPortIndexPath portIn;
    DCacheMuxPortIndexPath portInRegTagStg[DCACHE_ARRAY_PORT_NUM];
    logic                  portInRegGrantTagStg[DCACHE_ARRAY_PORT_NUM];

    DCacheArrayPortIndex portOutRegTagStg[DCACHE_MUX_PORT_NUM];
    DCacheArrayPortIndex portOutRegDataStg[DCACHE_MUX_PORT_NUM];

    // アドレスステージで LRU/MSHR から入力された要求をマージしたもの
    DCachePortMultiplexerIn muxIn[DCACHE_MUX_PORT_NUM];

    // ADDR<>TAG の間にあるレジスタ
    // マージした要求をアービトレーションして選んだ結果
    DCachePortMultiplexerIn muxInReg[DCACHE_ARRAY_PORT_NUM];    // DCACHE_ARRAY_PORT_NUM!

    DCachePortMultiplexerTagOut muxTagOut[DCACHE_MUX_PORT_NUM];
    DCachePortMultiplexerDataOut muxDataOut[DCACHE_MUX_PORT_NUM];

    logic tagHit[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];
    logic mshrConflict[DCACHE_ARRAY_PORT_NUM];

    logic mshrAddrHit[DCACHE_ARRAY_PORT_NUM];
    MSHR_IndexPath mshrAddrHitMSHRID[DCACHE_ARRAY_PORT_NUM];
    logic mshrReadHit[DCACHE_ARRAY_PORT_NUM];
    DCacheLinePath mshrReadData[DCACHE_ARRAY_PORT_NUM];
    DCacheLinePath portMSHRData[MSHR_NUM];
    logic portMSHRCanBeInvalid[MSHR_NUM];

    logic           repIsHit[DCACHE_ARRAY_PORT_NUM];
    DCacheWayPath   repHitWay[DCACHE_ARRAY_PORT_NUM];

    // *** Hack for Synplify...
    // Signals in an interface are set to temporally signals for avoiding
    // errors outputted by Synplify.
    DCacheTagPath   tagArrayDataOutTmp[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];
    logic           tagArrayValidOutTmp[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];
    logic           dataArrayDirtyOutTmp[DCACHE_ARRAY_PORT_NUM];
    DCacheLinePath  dataArrayDataOutTmp[DCACHE_ARRAY_PORT_NUM];
    DCacheWayPath   replArrayDataOutTmp[DCACHE_ARRAY_PORT_NUM];

    // 置き換え情報のインデクスが被ってるかどうか
    logic isReplSameIndex[DCACHE_ARRAY_PORT_NUM];

    always_ff @(posedge port.clk) begin


        for (int i = 0; i < DCACHE_ARRAY_PORT_NUM; i++) begin
            if (port.rst) begin
                portInRegTagStg[i] <= '0;
                muxInReg[i] <= '0;
                portInRegGrantTagStg[i] <= FALSE;
            end
            else begin
                portInRegTagStg[i] <= port.cacheArrayInSel[i];
                muxInReg[i] <= muxIn[ port.cacheArrayInSel[i] ];
                portInRegGrantTagStg[i] <= port.cacheArrayInGrant[i];
            end

        end

        for (int i = 0; i < DCACHE_MUX_PORT_NUM; i++) begin
            if (port.rst) begin
                portOutRegTagStg[i] <= '0;
                portOutRegDataStg[i] <= '0;
            end
            else begin
                portOutRegTagStg[i] <= port.cacheArrayOutSel[i];
                portOutRegDataStg[i] <= portOutRegTagStg[i];
            end
        end
    end


    always_comb begin

        // Merge inputs.
        for (int r = 0; r < DCACHE_LSU_PORT_NUM; r++) begin
            muxIn[r] = port.lsuMuxIn[r];
        end
        for (int r = 0; r < MSHR_NUM; r++) begin
            muxIn[r + DCACHE_LSU_PORT_NUM] = port.mshrCacheMuxIn[r];
        end

        for (int r = 0; r < MSHR_NUM; r++) begin
            portMSHRCanBeInvalid[r] = FALSE;
            portMSHRData[r] = port.mshrData[r];
        end


        //
        // stage:   | ADDR    | D$TAG    | D$DATA   |
        // process: | arbiter |          |          |
        //          | tag-in  | tag-out  |          |
        //          |         | hit/miss |          |
        //          |         | data-in  | data-out |
        //          |         | repl-in  | repl-out |
        //
        // Pipeline regs between ADDR<>D$TAG:   portInRegTagStg, portOutRegTagStg, muxInReg
        // Pipeline regs between D$TAG<>D$DATA: portOutRegDataStg
        //

        // --- Address calculation stage (ADDR, MemoryExecutionStage).
        // Tag array inputs
        for (int p = 0; p < DCACHE_ARRAY_PORT_NUM; p++) begin
            portIn = port.cacheArrayInSel[p];
            port.tagArrayWE[p]       = muxIn[ portIn ].tagWE;
            port.tagArrayWriteWay[p] = muxIn[ portIn ].evictWay;
            port.tagArrayIndexIn[p]  = muxIn[ portIn ].indexIn;
            port.tagArrayDataIn[p]   = muxIn[ portIn ].tagDataIn;
            port.tagArrayValidIn[p]  = muxIn[ portIn ].tagValidIn;
        end

        // --- Tag access stage (D$TAG, MemoryTagAccessStage).
        tagArrayDataOutTmp = port.tagArrayDataOut;
        tagArrayValidOutTmp = port.tagArrayValidOut;

        // Hit/miss detection
        for (int p = 0; p < DCACHE_ARRAY_PORT_NUM; p++) begin
            mshrConflict[p] = FALSE;
            mshrReadHit[p] = FALSE;
            mshrAddrHit[p] = FALSE;
            mshrAddrHitMSHRID[p] = '0;
            mshrReadData[p] = '0;
            for (int m = 0; m < MSHR_NUM; m++) begin
                if (port.mshrValid[m] &&
                    muxInReg[p].indexIn == ToIndexPartFromFullAddr(port.mshrAddr[m])
                ) begin
                    mshrConflict[p] = TRUE;

                    // When request addr hits mshr,
                    // 1. the mshr allocator load must bypass data from MSHR,
                    // 2. other loads can bypass data from MSHR if possible.
                    if (muxInReg[p].tagDataIn == ToTagPartFromFullAddr(port.mshrAddr[m])) begin
                        // To bypass data from MSHR.
                        if (port.mshrPhase[m] >= MSHR_PHASE_MISS_WRITE_CACHE_REQUEST) begin
                        //if (port.mshrPhase[m] >= MSHR_PHASE_MISS_WRITE_CACHE_REQUEST) begin
                            if (muxInReg[p].makeMSHRCanBeInvalid) begin
                                portMSHRCanBeInvalid[m] = TRUE;
                            end
                            mshrReadHit[p] = TRUE;
                        end
                        mshrAddrHit[p] = TRUE;
                        mshrAddrHitMSHRID[p] = m;
                        mshrReadData[p] = portMSHRData[m];
                    end
                end
            end

            repHitWay[p] = '0;
            repIsHit[p] = FALSE;
            for (int way = 0; way < DCACHE_WAY_NUM; way++) begin
                tagHit[way][p] =
                    (tagArrayDataOutTmp[way][p] == muxInReg[p].tagDataIn) &&
                    tagArrayValidOutTmp[way][p] &&
                    !mshrConflict[p];
                if (tagHit[way][p]) begin
                    repHitWay[p] = way;
                    repIsHit[p] = TRUE;
                end
            end
        end

        // Tag array outputs
        for (int r = 0; r < DCACHE_MUX_PORT_NUM; r++) begin
            for (int w = 0; w < DCACHE_WAY_NUM; w++) begin
                muxTagOut[r].tagDataOut[w] = tagArrayDataOutTmp[w][ portOutRegTagStg[r] ];
                muxTagOut[r].tagValidOut[w] = tagArrayValidOutTmp[w][ portOutRegTagStg[r] ];
            end
            muxTagOut[r].tagHit = repIsHit[portOutRegTagStg[r]];
            muxTagOut[r].mshrConflict = mshrConflict[ portOutRegTagStg[r] ];
            muxTagOut[r].mshrReadHit = mshrReadHit[ portOutRegTagStg[r] ];
            muxTagOut[r].mshrAddrHit = mshrAddrHit[ portOutRegTagStg[r] ];
            muxTagOut[r].mshrAddrHitMSHRID = mshrAddrHitMSHRID[ portOutRegTagStg[r] ];
            muxTagOut[r].mshrReadData = mshrReadData[ portOutRegTagStg[r] ];
        end


        for (int r = 0; r < MSHR_NUM; r++) begin
            port.mshrCanBeInvalid[r] = portMSHRCanBeInvalid[r];
        end

        // Data array inputs
        for (int p = 0; p < DCACHE_ARRAY_PORT_NUM; p++) begin
            port.dataArrayDataIn[p]    = muxInReg[p].dataDataIn;
            port.dataArrayDirtyIn[p]   = muxInReg[p].dataDirtyIn;
            port.dataArrayWriteWay[p]  = muxInReg[p].tagWE ? muxInReg[p].evictWay : repHitWay[p];

            // If dataArrayDoesReadEvictedWay is valid, instead of a way of dataArrayReadWay, 
            // a way specified by a replacement algorithm is read for eviction.
            port.dataArrayDoesReadEvictedWay[p] = muxInReg[p].isVictimEviction;
            port.dataArrayReadWay[p] = repHitWay[p];
            
            port.dataArrayByteWE_In[p] = muxInReg[p].dataByteWE;
            port.dataArrayWE[p] =
                muxInReg[p].dataWE || (muxInReg[p].dataWE_OnTagHit && repIsHit[p]);
            port.dataArrayIndexIn[p]   = muxInReg[p].indexIn;
        end

        // 置き換え情報の更新
        for (int p = 0; p < DCACHE_ARRAY_PORT_NUM; p++) begin
            isReplSameIndex[p] = FALSE;

            for (int i = 0; i < p; i++) begin
                if (muxInReg[i].indexIn == muxInReg[p].indexIn) begin
                    isReplSameIndex[p] = TRUE;
                end
            end

            port.replArrayIndexIn[p] = muxInReg[p].indexIn;
            port.replArrayDataIn[p] = 0;
            if (isReplSameIndex[p]) begin
                port.replArrayWE[p] = FALSE;
            end
            else begin
                if (muxInReg[p].tagWE) begin
                    // 書き込み時は追い出し対象のウェイを渡す
                    port.replArrayWE[p] = TRUE;
                    port.replArrayDataIn[p] = muxInReg[p].evictWay;
                end
                else if (muxInReg[p].isVictimEviction) begin
                    // MSHR からの victim 読み出し時は，置き換え情報の読み出し
                    port.replArrayWE[p] = FALSE;    
                end
                else begin
                    // ヒット時はヒットしたウェイを渡す
                    port.replArrayWE[p] = repIsHit[p];
                    port.replArrayDataIn[p] = repHitWay[p];
                end
            end
        end


        // ---Data array access stage (D$DATA, MemoryAccessStage).
        // Data array outputs
        dataArrayDataOutTmp = port.dataArrayDataOut;
        dataArrayDirtyOutTmp = port.dataArrayDirtyOut;
        replArrayDataOutTmp = port.replArrayDataOut;
        for (int r = 0; r < DCACHE_MUX_PORT_NUM; r++) begin
            muxDataOut[r].dataDataOut = dataArrayDataOutTmp[ portOutRegDataStg[r] ];
            muxDataOut[r].dataDirtyOut = dataArrayDirtyOutTmp[ portOutRegDataStg[r] ];
            muxDataOut[r].replDataOut = replArrayDataOutTmp[ portOutRegDataStg[r] ];
        end
    end

    // Output to each port.
    always_comb begin
        for (int r = 0; r < DCACHE_LSU_PORT_NUM; r++) begin
            port.lsuMuxTagOut[r] = muxTagOut[r];
            port.lsuMuxDataOut[r] = muxDataOut[r];
        end
        for (int r = 0; r < MSHR_NUM; r++) begin
            port.mshrCacheMuxTagOut[r] = muxTagOut[r + DCACHE_LSU_PORT_NUM];
            port.mshrCacheMuxDataOut[r] = muxDataOut[r + DCACHE_LSU_PORT_NUM];
        end
    end

endmodule : DCacheArrayPortMultiplexer


//
// Tag/data/dirty bits array.
//
module DCacheArray(DCacheIF.DCacheArray port);
    // Data array signals
    logic dataArrayWE[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];
    logic dataArrayByteWE[DCACHE_LINE_BYTE_NUM][DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];
    DCacheIndexPath dataArrayIndex[DCACHE_ARRAY_PORT_NUM];
    BytePath        dataArrayIn[DCACHE_LINE_BYTE_NUM][DCACHE_ARRAY_PORT_NUM];
    BytePath        dataArrayOut[DCACHE_LINE_BYTE_NUM][DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];
    logic           dataArrayDirtyIn[DCACHE_ARRAY_PORT_NUM];
    logic           dataArrayDirtyOut[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];
    DCacheWayPath   dataArrayReadWayReg[DCACHE_ARRAY_PORT_NUM];
    DCacheWayPath   dataArrayReadWay[DCACHE_ARRAY_PORT_NUM];
    logic           dataArrayDoesReadEvictedWayReg[DCACHE_ARRAY_PORT_NUM];

    // *** Hack for Synplify...
    DCacheByteEnablePath dataArrayByteWE_Tmp[DCACHE_ARRAY_PORT_NUM];
    DCacheLinePath dataArrayInTmp[DCACHE_ARRAY_PORT_NUM];
    DCacheLinePath dataArrayOutTmp[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];

    // Tag array signals
    logic tagArrayWE[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];
    DCacheIndexPath tagArrayIndex[DCACHE_ARRAY_PORT_NUM];
    DCacheTagValidPath tagArrayIn[DCACHE_ARRAY_PORT_NUM];
    DCacheTagValidPath tagArrayOut[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];
    // Temporal signals for Vivado
    logic [$bits(DCacheTagValidPath)-1:0] tagArrayOutTmp[DCACHE_WAY_NUM][DCACHE_ARRAY_PORT_NUM];

    // Replacement array signals
    logic replArrayWE[DCACHE_TREE_LRU_STATE_BIT_NUM][DCACHE_ARRAY_PORT_NUM];
    DCacheTreeLRU_StatePath replArrayWE_Flat[DCACHE_ARRAY_PORT_NUM];
    DCacheIndexPath replArrayIndex[DCACHE_ARRAY_PORT_NUM];
    logic replArrayIn[DCACHE_TREE_LRU_STATE_BIT_NUM][DCACHE_ARRAY_PORT_NUM];
    DCacheTreeLRU_StatePath replArrayInFlat[DCACHE_ARRAY_PORT_NUM];
    logic replArrayOut[DCACHE_TREE_LRU_STATE_BIT_NUM][DCACHE_ARRAY_PORT_NUM];
    DCacheTreeLRU_StatePath replArrayOutFlat[DCACHE_ARRAY_PORT_NUM];
    DCacheWayPath replArrayResult[DCACHE_ARRAY_PORT_NUM];

    // Reset signals
    DCacheIndexPath rstIndex;

    always_ff @(posedge port.clk) begin
        if (port.rstStart)
            rstIndex <= '0;
        else
            rstIndex <= rstIndex + 1;

        // データアレイから読み出した後に選択する way は1サイクル前にくるので FF につんでおく
        for (int p = 0; p < DCACHE_ARRAY_PORT_NUM; p++) begin
            if (port.rst) begin
                dataArrayReadWayReg[p] <= '0;
                dataArrayDoesReadEvictedWayReg[p] <= '0;
            end
            else begin
                dataArrayReadWayReg[p] <= port.dataArrayReadWay[p];
                dataArrayDoesReadEvictedWayReg[p] <= port.dataArrayDoesReadEvictedWay[p];
            end
        end
    end


    generate
        for (genvar way = 0; way < DCACHE_WAY_NUM; way++) begin
            // Data array instance
            for (genvar i = 0; i < DCACHE_LINE_BYTE_NUM; i++) begin
                BlockTrueDualPortRAM #(
                    .ENTRY_NUM( DCACHE_INDEX_NUM ),
                    .ENTRY_BIT_SIZE( $bits(BytePath) )
                    //.PORT_NUM( DCACHE_ARRAY_PORT_NUM )
                ) dataArray (
                    .clk( port.clk ),
                    .we( dataArrayByteWE[i][way] ),
                    .rwa( dataArrayIndex ),
                    .wv( dataArrayIn[i] ),
                    .rv( dataArrayOut[i][way] )
                );
            end

            // Dirty array instance
            // The dirty array is synchronized with the data array.
            BlockTrueDualPortRAM #(
                .ENTRY_NUM( DCACHE_INDEX_NUM ),
                .ENTRY_BIT_SIZE( 1 )
                //.PORT_NUM( DCACHE_ARRAY_PORT_NUM )
            ) dirtyArray (
                .clk( port.clk ),
                .we( dataArrayWE[way] ),
                .rwa( dataArrayIndex ),
                .wv( dataArrayDirtyIn ),
                .rv( dataArrayDirtyOut[way] )
            );

            // Tag array instance
            BlockTrueDualPortRAM #(
                .ENTRY_NUM( DCACHE_INDEX_NUM ),
                .ENTRY_BIT_SIZE( $bits(DCacheTagValidPath) )
                //.PORT_NUM( DCACHE_ARRAY_PORT_NUM )
            ) tagArray (
                .clk( port.clk ),
                .we( tagArrayWE[way] ),
                .rwa( tagArrayIndex ),
                .wv( tagArrayIn ),
                .rv( tagArrayOutTmp[way] )
            );
        end

        // Replacement array instance
        // This array is not used when the number of ways is oen.
        for (genvar i = 0; i < DCACHE_TREE_LRU_STATE_BIT_NUM; i++) begin
            BlockTrueDualPortRAM #(
                .ENTRY_NUM( DCACHE_INDEX_NUM ),
                .ENTRY_BIT_SIZE(1)
                //.PORT_NUM( DCACHE_ARRAY_PORT_NUM )
            ) replArray (
                .clk( port.clk ),
                .we( replArrayWE[i] ),
                .rwa( replArrayIndex ),
                .wv( replArrayIn[i] ),
                .rv( replArrayOut[i] )
            );
        end
    endgenerate


    always_comb begin

        // Replacement signals
        //
        for (int p = 0; p < DCACHE_ARRAY_PORT_NUM; p++) begin
            replArrayIndex[p] = port.replArrayIndexIn[p];
            replArrayWE_Flat[p] = TreeLRU_CalcWriteEnable(port.replArrayWE[p], port.replArrayDataIn[p]);
            replArrayInFlat[p] = TreeLRU_CalcUpdatedState(port.replArrayDataIn[p]);
            // Since the replacement information is stored in a different array 
            // for each bit, the bit order is exchanged.
            for (int i = 0; i < DCACHE_TREE_LRU_STATE_BIT_NUM; i++) begin
                replArrayWE[i][p] = replArrayWE_Flat[p][i];
                replArrayIn[i][p] = replArrayInFlat[p][i];
                replArrayOutFlat[p][i] = replArrayOut[i][p];    
            end
            // Do not use the output of replArray
            replArrayResult[p] = (DCACHE_WAY_NUM == 1) ? 0 : TreeLRU_CalcEvictedWay(replArrayOutFlat[p]);
            port.replArrayDataOut[p] = replArrayResult[p];
        end

        // Data array signals
        for (int p = 0; p < DCACHE_ARRAY_PORT_NUM; p++) begin
            dataArrayIndex[p] = port.dataArrayIndexIn[p];
            dataArrayDirtyIn[p] = port.dataArrayDirtyIn[p];
            for (int way = 0; way < DCACHE_WAY_NUM; way++) begin
                dataArrayWE[way][p] = (port.dataArrayWriteWay[p] == way) ? port.dataArrayWE[p] : FALSE;
            end
        end

        // *** Hack for Synplify...
        // Signals in an interface must be connected to temporal signals for avoiding
        // errors outputted by Synplify.
        dataArrayByteWE_Tmp = port.dataArrayByteWE_In;
        dataArrayInTmp = port.dataArrayDataIn;


        // *** Hack for Vivado...
        // Assign temporal signal from tagArray
        tagArrayOut = tagArrayOutTmp;

        for (int p = 0; p < DCACHE_ARRAY_PORT_NUM; p++) begin
            for (int i = 0; i < DCACHE_LINE_BYTE_NUM; i++) begin
                for (int way = 0; way < DCACHE_WAY_NUM; way++) begin
                    dataArrayByteWE[i][way][p] = dataArrayWE[way][p] && dataArrayByteWE_Tmp[p][i];
                end
                for (int b = 0; b < 8; b++) begin
                    dataArrayIn[i][p][b] = dataArrayInTmp[p][i*8 + b];
                    for (int way = 0; way < DCACHE_WAY_NUM; way++) begin
                        dataArrayOutTmp[way][p][i*8 + b] = dataArrayOut[i][way][p][b];
                    end
                end
            end
        end

        // Way select
        for (int p = 0; p < DCACHE_ARRAY_PORT_NUM; p++) begin
            dataArrayReadWay[p] = 
                dataArrayDoesReadEvictedWayReg[p] ? replArrayResult[p] : dataArrayReadWayReg[p];
            port.dataArrayDataOut[p] = dataArrayOutTmp[dataArrayReadWay[p]][p];
            port.dataArrayDirtyOut[p] = dataArrayDirtyOut[dataArrayReadWay[p]][p];
        end


        // Tag signals
        for (int p = 0; p < DCACHE_ARRAY_PORT_NUM; p++) begin
            tagArrayIndex[p]    = port.tagArrayIndexIn[p];
            tagArrayIn[p].tag   = port.tagArrayDataIn[p];
            tagArrayIn[p].valid = port.tagArrayValidIn[p];

            for (int way = 0; way < DCACHE_WAY_NUM; way++) begin
                tagArrayWE[way][p] = 
                    port.tagArrayWE[p] && (way == port.tagArrayWriteWay[p]);

                port.tagArrayDataOut[way][p]  = tagArrayOut[way][p].tag;
                port.tagArrayValidOut[way][p] = tagArrayOut[way][p].valid;
            end
        end

        // Reset
        if (port.rst) begin
            for (int p = 0; p < DCACHE_ARRAY_PORT_NUM; p++) begin
                for (int way = 0; way < DCACHE_WAY_NUM; way++) begin
                    for (int i = 0; i < DCACHE_LINE_BYTE_NUM; i++) begin
                        dataArrayByteWE[i][way][p] = FALSE;
                    end
                    tagArrayWE[way][p] = FALSE;
                end
            end

            // Port 0 is used for reset.
            for (int i = 0; i < DCACHE_LINE_BYTE_NUM; i++) begin
                for (int way = 0; way < DCACHE_WAY_NUM; way++) begin
                    dataArrayByteWE[i][way][0] = TRUE;
                end
                dataArrayIn[i][0] = 8'hcd;
            end
            for (int way = 0; way < DCACHE_WAY_NUM; way++) begin
                dataArrayWE[way][0] = TRUE;
            end
            dataArrayIndex[0] = rstIndex;
            dataArrayDirtyIn[0] = FALSE;

            tagArrayIndex[0] = rstIndex;
            for (int way = 0; way < DCACHE_WAY_NUM; way++) begin
                tagArrayWE[way][0] = TRUE;
            end
            tagArrayIn[0].tag = 0;
            tagArrayIn[0].valid = FALSE;

            replArrayIndex[0] = rstIndex;
            for (int i = 0; i < DCACHE_TREE_LRU_STATE_BIT_NUM; i++) begin
                replArrayWE[i][0] = TRUE;
                replArrayInFlat[0] = 0;
                replArrayIn[i][0] = 0;
            end
        end
    end

endmodule : DCacheArray

//
// Data cache main module.
//
module DCache(
    LoadStoreUnitIF.DCache lsu,
    CacheSystemIF.DCache cacheSystem,
    ControllerIF.DCache ctrl
);

    logic hit[DCACHE_LSU_PORT_NUM];
    logic missReq[DCACHE_LSU_PORT_NUM];
    PhyAddrPath missAddr[DCACHE_LSU_PORT_NUM];
    logic missIsUncachable[DCACHE_LSU_PORT_NUM];


    // Tag array
    DCacheIF port(lsu.clk, lsu.rst, lsu.rstStart);

    DCacheController controller(port);

    DCacheArray array(port);
    DCacheArrayPortArbiter arrayArbiter(port);
    DCacheArrayPortMultiplexer arrayMux(port);

    DCacheMemoryReqPortArbiter memArbiter(port);
    DCacheMemoryReqPortMultiplexer memMux(port);

    DCacheMissHandler missHandler(port);


    // Stored data
    DCacheLinePath storedLineData;
    logic [DCACHE_LINE_BYTE_NUM-1:0] storedLineByteWE;

    // Pipeline registers
    //
    // ----------------------------->
    // ADDR  | D$TAG | D$DATA  | WB
    //       |       | D$REP-U |
    //       |  LSQ  |         |
    // Addresses are input to the tag array in the ADDR stage (MemoryExecutionStage).
    // D$REP-W is replacement information update
    //
    PhyAddrPath dcReadAddrRegTagStg[DCACHE_LSU_READ_PORT_NUM];
    PhyAddrPath dcReadAddrRegDataStg[DCACHE_LSU_READ_PORT_NUM];
    logic dcReadReqReg[DCACHE_LSU_READ_PORT_NUM];
    logic lsuCacheGrtReg[DCACHE_LSU_PORT_NUM];
    logic dcReadUncachableReg[DCACHE_LSU_READ_PORT_NUM];

    logic dcWriteReqReg;
    PhyAddrPath dcWriteAddrReg;
    logic dcWriteUncachableReg;


    logic lsuLoadHasAllocatedMSHR[DCACHE_LSU_READ_PORT_NUM];
    MSHR_IndexPath lsuLoadMSHRID[DCACHE_LSU_READ_PORT_NUM];
    logic lsuStoreHasAllocatedMSHR[DCACHE_LSU_WRITE_PORT_NUM];
    MSHR_IndexPath lsuStoreMSHRID[DCACHE_LSU_WRITE_PORT_NUM];

    // MSHRからのLoad
    logic lsuMSHRAddrHit[DCACHE_LSU_READ_PORT_NUM];
    MSHR_IndexPath lsuMSHRAddrHitMSHRID[DCACHE_LSU_READ_PORT_NUM];
    logic lsuMSHRReadHit[DCACHE_LSU_READ_PORT_NUM];
    DCacheLinePath lsuMSHRReadData[DCACHE_LSU_READ_PORT_NUM];

    // MSHRをAllocateした命令からのメモリリクエストかどうか
    // MSHRをAllocateしたLoad命令がMemoryRegisterReadStageでflushされた場合，AllocateされたMSHRは解放可能になる
    logic lsuMakeMSHRCanBeInvalidByMemoryRegisterReadStage[MSHR_NUM];

    // そのリクエストがアクセスに成功した場合，AllocateされたMSHRは解放可能になる
    logic lsuMakeMSHRCanBeInvalid[DCACHE_LSU_READ_PORT_NUM];

    // MSHRをAllocateしたLoad命令がStoreForwardingによって完了した場合，AllocateされたMSHRは解放可能になる
    logic lsuMakeMSHRCanBeInvalidByMemoryTagAccessStage[MSHR_NUM];

    // MSHRをAllocateしたLoad命令がReplayQueueの先頭でflushされた場合，AllocateされたMSHRは解放可能になる
    logic lsuMakeMSHRCanBeInvalidByReplayQueue[MSHR_NUM];

`ifndef RSD_SYNTHESIS
    `ifndef RSD_VIVADO_SIMULATION
        // Don't care these values, but avoiding undefined status in Questa.
        initial begin
            for (int i = 0; i < DCACHE_LSU_READ_PORT_NUM; i++) begin
                dcReadAddrRegTagStg[i] = '0;
                dcReadAddrRegDataStg[i] = '0;
                dcReadUncachableReg[i] = '0;
            end
            dcWriteAddrReg = '0;
            dcWriteUncachableReg = '0;
        end
    `endif
`endif

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < DCACHE_LSU_READ_PORT_NUM; i++) begin
                dcReadReqReg[i] <= FALSE;
            end
            for (int i = 0; i < DCACHE_LSU_PORT_NUM; i++) begin
                lsuCacheGrtReg[i] <= FALSE;
            end
            dcWriteReqReg <= '0;
        end
        else begin
            lsuCacheGrtReg <= port.lsuCacheGrt;

            for (int i = 0; i < DCACHE_LSU_READ_PORT_NUM; i++) begin
                dcReadReqReg[i] <= lsu.dcReadReq[i];
                dcReadAddrRegTagStg[i] <= lsu.dcReadAddr[i];
                dcReadUncachableReg[i] <= lsu.dcReadUncachable[i];
            end

            dcReadAddrRegDataStg <= dcReadAddrRegTagStg;

            dcWriteReqReg <= lsu.dcWriteReq;
            dcWriteAddrReg <= lsu.dcWriteAddr;
            dcWriteUncachableReg <= lsu.dcWriteUncachable;
        end
    end

`ifdef RSD_ENABLE_VECTOR_PATH
    `RSD_STATIC_ASSERT(
        $bits(VectorPath) == $bits(DCacheLinePath), 
        "The width of a DCache line must be same as the width of a vector register."
    );
`endif

    `RSD_STATIC_ASSERT(
        $bits(LSQ_BlockDataPath) <= $bits(DCacheLinePath), 
        "The width of a DCache line must be same or greater than that of an LSQ block."
    );

    always_comb begin

        for (int i = 0; i < DCACHE_LSU_READ_PORT_NUM; i++) begin
            lsuMakeMSHRCanBeInvalid[i] = lsu.makeMSHRCanBeInvalid[i];
        end

        // --- In the address execution stage (MemoryExecutionStage)
        // Load request
        for (int i = 0; i < DCACHE_LSU_READ_PORT_NUM; i++) begin

            port.lsuCacheReq[(i+DCACHE_LSU_READ_PORT_BEGIN)] = lsu.dcReadReq[i];
            port.lsuMuxIn[(i+DCACHE_LSU_READ_PORT_BEGIN)].tagWE = FALSE;
            port.lsuMuxIn[(i+DCACHE_LSU_READ_PORT_BEGIN)].indexIn = ToIndexPartFromFullAddr(lsu.dcReadAddr[i]);
            port.lsuMuxIn[(i+DCACHE_LSU_READ_PORT_BEGIN)].tagDataIn = ToTagPartFromFullAddr(lsu.dcReadAddr[i]);
            port.lsuMuxIn[(i+DCACHE_LSU_READ_PORT_BEGIN)].tagValidIn = TRUE;
            port.lsuMuxIn[(i+DCACHE_LSU_READ_PORT_BEGIN)].dataDataIn = '0;
            port.lsuMuxIn[(i+DCACHE_LSU_READ_PORT_BEGIN)].dataByteWE = '0;
            port.lsuMuxIn[(i+DCACHE_LSU_READ_PORT_BEGIN)].dataWE = FALSE;
            port.lsuMuxIn[(i+DCACHE_LSU_READ_PORT_BEGIN)].dataWE_OnTagHit = FALSE;
            port.lsuMuxIn[(i+DCACHE_LSU_READ_PORT_BEGIN)].dataDirtyIn = FALSE;
            port.lsuMuxIn[(i+DCACHE_LSU_READ_PORT_BEGIN)].makeMSHRCanBeInvalid = lsuMakeMSHRCanBeInvalid[i];
            port.lsuMuxIn[(i+DCACHE_LSU_READ_PORT_BEGIN)].evictWay = '0;
            port.lsuMuxIn[(i+DCACHE_LSU_READ_PORT_BEGIN)].isVictimEviction = FALSE;
            port.lsuMuxIn[(i+DCACHE_LSU_READ_PORT_BEGIN)].isFlushReq = FALSE;
        end

        // --- In the tag access stage (MemoryTagAccessStage)
        // Hit/miss detection
        for (int i = 0; i < DCACHE_LSU_READ_PORT_NUM; i++) begin
            hit[i] = FALSE;
            if (port.lsuMuxTagOut[(i+DCACHE_LSU_READ_PORT_BEGIN)].tagHit && lsuCacheGrtReg[(i+DCACHE_LSU_READ_PORT_BEGIN)]) begin
                hit[i] = TRUE;
            end
        end

        //
        // --- In the data array access stage.
        // Load data from a cache line.
        //
        for (int i = 0; i < DCACHE_LSU_READ_PORT_NUM; i++) begin
            // Read data address is aligned to word boundary in ReadDataFromLine.
            lsu.dcReadData[i] = port.lsuMuxDataOut[i].dataDataOut;
            lsu.dcReadHit[i] = hit[i];
        end
/*
        for (int i = DCACHE_LSU_READ_PORT_NUM; i < MEM_ISSUE_WIDTH; i++) begin
            lsu.dcReadData[i] = '0;
            lsu.dcReadHit[i] = FALSE;
            
        end
*/


        // --- In the first stage of the commit stages.
        // Write request


        for (int i = 0; i < DCACHE_LSU_WRITE_PORT_NUM; i++) begin
            assert(DCACHE_LSU_WRITE_PORT_NUM == 1);

            // Write data is not aligned?
            storedLineData = lsu.dcWriteData;
            storedLineByteWE = lsu.dcWriteByteWE;

            port.lsuCacheReq[(i+DCACHE_LSU_WRITE_PORT_BEGIN)] = lsu.dcWriteReq;
            port.lsuMuxIn[(i+DCACHE_LSU_WRITE_PORT_BEGIN)].tagWE = FALSE;    // First, stores read tag.
            port.lsuMuxIn[(i+DCACHE_LSU_WRITE_PORT_BEGIN)].indexIn = ToIndexPartFromFullAddr(lsu.dcWriteAddr);
            port.lsuMuxIn[(i+DCACHE_LSU_WRITE_PORT_BEGIN)].tagDataIn = ToTagPartFromFullAddr(lsu.dcWriteAddr);
            port.lsuMuxIn[(i+DCACHE_LSU_WRITE_PORT_BEGIN)].tagValidIn = TRUE;
            port.lsuMuxIn[(i+DCACHE_LSU_WRITE_PORT_BEGIN)].dataDataIn = storedLineData;
            port.lsuMuxIn[(i+DCACHE_LSU_WRITE_PORT_BEGIN)].dataByteWE = storedLineByteWE;
            port.lsuMuxIn[(i+DCACHE_LSU_WRITE_PORT_BEGIN)].dataWE = FALSE;
            port.lsuMuxIn[(i+DCACHE_LSU_WRITE_PORT_BEGIN)].dataWE_OnTagHit = TRUE;
            port.lsuMuxIn[(i+DCACHE_LSU_WRITE_PORT_BEGIN)].dataDirtyIn = TRUE;
            // ストアはコミット時に初めて MSHR にアクセスするので，キャンセルはしないはず？
            port.lsuMuxIn[(i+DCACHE_LSU_WRITE_PORT_BEGIN)].makeMSHRCanBeInvalid = FALSE;//lsuMakeMSHRCanBeInvalid[(i+DCACHE_LSU_WRITE_PORT_BEGIN)];
            port.lsuMuxIn[(i+DCACHE_LSU_WRITE_PORT_BEGIN)].evictWay = '0;
            port.lsuMuxIn[(i+DCACHE_LSU_WRITE_PORT_BEGIN)].isVictimEviction = FALSE;
            port.lsuMuxIn[(i+DCACHE_LSU_WRITE_PORT_BEGIN)].isFlushReq = FALSE;

            lsu.dcWriteReqAck = port.lsuCacheGrt[(i+DCACHE_LSU_WRITE_PORT_BEGIN)];
        end


        // --- In the first stage of the commit stages.
        // Hit/miss detection

        for (int i = 0; i < DCACHE_LSU_WRITE_PORT_NUM; i++) begin
            assert(DCACHE_LSU_WRITE_PORT_NUM == 1);

            // Store data to the array after miss handling finishes.
            hit[(i+DCACHE_LSU_WRITE_PORT_BEGIN)] = FALSE;
            if (port.lsuMuxTagOut[(i+DCACHE_LSU_WRITE_PORT_BEGIN)].tagHit && lsuCacheGrtReg[(i+DCACHE_LSU_WRITE_PORT_BEGIN)]) begin
                hit[(i+DCACHE_LSU_WRITE_PORT_BEGIN)] = TRUE;
            end

            lsu.dcWriteHit = hit[(i+DCACHE_LSU_WRITE_PORT_BEGIN)];
        end

    end

    always_comb begin
        port.storedLineData = storedLineData;
        port.storedLineByteWE = storedLineByteWE;
    end

    //
    // --- Miss requests.
    // In the tag access stage/second commit stage.
    //
    always_comb begin

        // Read requests from a memory execution stage.
        for (int i = 0; i < DCACHE_LSU_READ_PORT_NUM; i++) begin
            missReq[i] = 
                !hit[i] && 
                !port.lsuMuxTagOut[i].mshrConflict && 
                dcReadReqReg[i] && 
                lsuCacheGrtReg[i] && 
                !lsu.dcReadCancelFromMT_Stage[i];
            missAddr[i] = dcReadAddrRegTagStg[i];
            missIsUncachable[i] = dcReadUncachableReg[i];
        end

        // Write requests from a store queue committer.
        for (int i = DCACHE_LSU_WRITE_PORT_BEGIN; i < DCACHE_LSU_WRITE_PORT_NUM + DCACHE_LSU_READ_PORT_NUM; i++) begin
            assert(DCACHE_LSU_WRITE_PORT_NUM == 1);
            missReq[i] = !hit[i] && !port.lsuMuxTagOut[i].mshrConflict && dcWriteReqReg && lsuCacheGrtReg[i];
            missAddr[i] = dcWriteAddrReg;
            missIsUncachable[i] = dcWriteUncachableReg;
        end

    end


    // 1. MSHR 登録
    //   * 確保できない場合，待たせる
    //   * 以降は MSHR 登録アドレスへの操作は全部ブロック
    logic mshrConflict[DCACHE_LSU_PORT_NUM];

        // Miss handler
    logic portInitMSHR[MSHR_NUM];
    PhyAddrPath portInitMSHR_Addr[MSHR_NUM];
    logic portIsAllocatedByStore[MSHR_NUM];
    logic portIsUncachable[MSHR_NUM];

    always_comb begin

        // MSHR allocation signals for ReplayQueue
        for (int i = 0; i < DCACHE_LSU_READ_PORT_NUM; i++) begin
            lsuLoadHasAllocatedMSHR[i] = FALSE;
            lsuLoadMSHRID[i] = '0;
        end

        // MSHR allocation signals for storeCommitter
        for (int i = 0; i < DCACHE_LSU_WRITE_PORT_NUM; i++) begin
            lsuStoreHasAllocatedMSHR[i] = FALSE;
            lsuStoreMSHRID[i] = '0;
        end

        // MSHR addr/data hit and data signals for MemoryAccessBackend
        for (int i = 0; i < DCACHE_LSU_READ_PORT_NUM; i++) begin
            lsuMSHRAddrHit[i] = port.lsuMuxTagOut[i].mshrAddrHit;
            lsuMSHRAddrHitMSHRID[i] = port.lsuMuxTagOut[i].mshrAddrHitMSHRID;
            lsuMSHRReadHit[i] = port.lsuMuxTagOut[i].mshrReadHit;
            lsuMSHRReadData[i] = port.lsuMuxTagOut[i].mshrReadData;
        end

        for (int i = 0; i < DCACHE_LSU_PORT_NUM; i++) begin
            mshrConflict[i] = port.lsuMuxTagOut[i].mshrConflict;
        end

        // Check address conflict in missed access in this cycle.
        for (int i = 0; i < DCACHE_LSU_PORT_NUM; i++) begin
            for (int m = 0; m < i; m++) begin
                if (missReq[m] &&
                    ToIndexPartFromFullAddr(missAddr[i]) == ToIndexPartFromFullAddr(missAddr[m])
                ) begin
                    // An access with the same index cannot enter to the MSHR.
                    mshrConflict[i] = TRUE;
                end
            end
        end

        for (int i = 0; i < MSHR_NUM; i++) begin
            portInitMSHR[i] = FALSE;
            portInitMSHR_Addr[i] = '0;
            portIsAllocatedByStore[i] = FALSE;
            portIsUncachable[i] = FALSE;
        end

        for (int i = 0; i < DCACHE_LSU_PORT_NUM; i++) begin
            if (!missReq[i] || mshrConflict[i]) begin
                // This access hits the cache or is invalid.
                // An access with the same index cannot enter to the MSHR.
                continue;
            end

            // Search free MSHR entry and allocate.
            for (int m = 0; m < MSHR_NUM; m++) begin
                if (!port.mshrValid[m] && !portInitMSHR[m]) begin
                    portInitMSHR[m] = TRUE;
                    portInitMSHR_Addr[m] = missAddr[i];
                    portIsUncachable[m] = missIsUncachable[i];
                    if (i < DCACHE_LSU_READ_PORT_NUM) begin
                        lsuLoadHasAllocatedMSHR[i] = TRUE;
                        lsuLoadMSHRID[i] = m;
                    end
                    else begin
                        lsuStoreHasAllocatedMSHR[i-DCACHE_LSU_READ_PORT_NUM] = TRUE;
                        lsuStoreMSHRID[i-DCACHE_LSU_READ_PORT_NUM] = m;
                        portIsAllocatedByStore[m] = TRUE;
                    end
                    break;
                end
            end
        end

        for (int i = 0; i < MSHR_NUM; i++) begin
            port.initMSHR[i] = portInitMSHR[i];
            port.initMSHR_Addr[i] = portInitMSHR_Addr[i];
            port.isAllocatedByStore[i] = portIsAllocatedByStore[i];
            port.isUncachable[i] = portIsUncachable[i];
        end

        // DCache top -> DCache controller
        port.lsuCacheGrtReg = lsuCacheGrtReg;

        // Output control signals
        for (int i = 0; i < DCACHE_LSU_READ_PORT_NUM; i++) begin
            lsu.dcReadBusy[i] = mshrConflict[i];
        end
        lsu.dcWriteBusy = mshrConflict[DCACHE_LSU_WRITE_PORT_BEGIN];

        // MSHR addr/data hit and data signals for MemoryAccessBackend
        for (int i = 0; i < DCACHE_LSU_READ_PORT_NUM; i++) begin
            lsu.mshrAddrHit[i] = lsuMSHRAddrHit[i];
            lsu.mshrAddrHitMSHRID[i] = lsuMSHRAddrHitMSHRID[i];
            lsu.mshrReadHit[i] = lsuMSHRReadHit[i];
            lsu.mshrReadData[i] = lsuMSHRReadData[i];
        end

        // MSHR allocation signals for ReplayQueue
        for (int i = 0; i < DCACHE_LSU_READ_PORT_NUM; i++) begin
            lsu.loadHasAllocatedMSHR[i] = lsuLoadHasAllocatedMSHR[i];
            lsu.loadMSHRID[i] = lsuLoadMSHRID[i];
        end

        // MSHR allocation signals for storeCommitter
        for (int i = 0; i < DCACHE_LSU_WRITE_PORT_NUM; i++) begin
            lsu.storeHasAllocatedMSHR[i] = lsuStoreHasAllocatedMSHR[i];
            lsu.storeMSHRID[i] = lsuStoreMSHRID[i];
        end

    end

    always_comb begin
        for (int i = 0; i < MSHR_NUM; i++) begin
            lsuMakeMSHRCanBeInvalidByMemoryRegisterReadStage[i] = lsu.makeMSHRCanBeInvalidByMemoryRegisterReadStage[i];
            lsuMakeMSHRCanBeInvalidByMemoryTagAccessStage[i] = lsu.makeMSHRCanBeInvalidByMemoryTagAccessStage[i];
            lsuMakeMSHRCanBeInvalidByReplayQueue[i] = lsu.makeMSHRCanBeInvalidByReplayQueue[i];
        end
    end

    always_comb begin
        for (int i = 0; i < MSHR_NUM; i++) begin
            port.makeMSHRCanBeInvalidByMemoryRegisterReadStage[i] = lsuMakeMSHRCanBeInvalidByMemoryRegisterReadStage[i];
            port.makeMSHRCanBeInvalidByMemoryTagAccessStage[i] = lsuMakeMSHRCanBeInvalidByMemoryTagAccessStage[i];
            port.makeMSHRCanBeInvalidByReplayQueue[i] = lsuMakeMSHRCanBeInvalidByReplayQueue[i];
        end
    end


    //
    // Main memory
    //
    always_comb begin
        cacheSystem.dcMemAccessReq.valid = port.memValid;
        cacheSystem.dcMemAccessReq.we = port.memWE;
        cacheSystem.dcMemAccessReq.addr = port.memAddr;
        cacheSystem.dcMemAccessReq.data = port.memData;
        // To notice mshr phases and addr subset to ReplayQueue.
        for (int i = 0; i < MSHR_NUM; i++) begin
            lsu.mshrPhase[i] = port.mshrPhase[i];
            lsu.mshrAddrSubset[i] = port.mshrAddrSubset[i];
            lsu.mshrValid[i] = port.mshrValid[i];
        end
        port.memReqAck = cacheSystem.dcMemAccessReqAck.ack;
        port.memSerial = cacheSystem.dcMemAccessReqAck.serial;
        port.memAccessResult = cacheSystem.dcMemAccessResult;
        port.memWSerial = cacheSystem.dcMemAccessReqAck.wserial;
        port.memAccessResponse = cacheSystem.dcMemAccessResponse;
    end

    //
    // CacheFlushManager
    //
    always_comb begin
        // DCache -> cacheFlushManagemer
        cacheSystem.dcFlushReqAck = port.dcFlushReqAck;
        cacheSystem.dcFlushComplete = port.dcFlushComplete;

        // cacheFlushManagemer -> DCache
        port.dcFlushReq = cacheSystem.dcFlushReq;
        port.flushComplete = cacheSystem.flushComplete;
    end

endmodule : DCache


module DCacheMissHandler(
    DCacheIF.DCacheMissHandler port
);

    MissStatusHandlingRegister nextMSHR[MSHR_NUM];
    MissStatusHandlingRegister mshr[MSHR_NUM];

    logic portIsAllocatedByStore[MSHR_NUM];
    DCacheLinePath mergedLine[MSHR_NUM];

    logic mshrFlushComplete[MSHR_NUM];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < MSHR_NUM; i++) begin
            mshr[i] = '0;
        end
    end
`endif

    // MSHR
    always_ff@(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < MSHR_NUM; i++) begin
                mshr[i].valid <= FALSE;
                mshr[i].phase <= MSHR_PHASE_INVALID;
                mshr[i].canBeInvalid <= FALSE;
                mshr[i].isAllocatedByStore <= FALSE;
            end
        end
        else begin
            mshr <= nextMSHR;
        end
    end

    always_comb begin
        for (int i = 0; i < MSHR_NUM; i++) begin
            // To notice mshr phases to ReplayQueue.
            port.mshrPhase[i] = mshr[i].phase;

            // To notice mshr newAddr subset to ReplayQueue.
            port.mshrAddrSubset[i] = ToIndexSubsetPartFromFullAddr(mshr[i].newAddr);

            // To bypass mshr data to load instructions.
            port.mshrData[i] = mshr[i].line;

            port.mshrValid[i] = mshr[i].valid;
            port.mshrAddr[i] = mshr[i].newAddr;
        end

        // Flush operation uses MSHR[0];
        // therefore the complete signal comes from MSHR[0]. 
        port.mshrFlushComplete = mshrFlushComplete[0];
    end

    DCacheLinePath portStoredLineData;
    logic [DCACHE_LINE_BYTE_NUM-1:0] portStoredLineByteWE;
    always_comb begin
        portStoredLineData = port.storedLineData;
        portStoredLineByteWE = port.storedLineByteWE;
    end


    always_comb begin

        for (int i = 0; i < MSHR_NUM; i++) begin
            portIsAllocatedByStore[i] = port.isAllocatedByStore[i];
        end

        for (int i = 0; i < MSHR_NUM; i++) begin
            nextMSHR[i] = mshr[i];

            // Both MSHR_PHASE_VICTIM_READ_FROM_CACHE & MSHR_PHASE_MISS_WRITE_CACHE_REQUEST phases
            // use newAddr for a cache index.
            // The other phases do not use an index.
            port.mshrCacheMuxIn[i].indexIn = ToIndexPartFromFullAddr(mshr[i].newAddr);

            // Only MSHR_PHASE_MISS_WRITE_CACHE_REQUEST uses tagDataIn, dataByteWE and dataDataIn.
            port.mshrCacheMuxIn[i].tagDataIn = ToTagPartFromFullAddr(mshr[i].newAddr);
            port.mshrCacheMuxIn[i].dataDataIn = mshr[i].line;
            port.mshrCacheMuxIn[i].dataByteWE = {DCACHE_LINE_BYTE_NUM{1'b1}};
            port.mshrCacheMuxIn[i].tagValidIn = TRUE;        // Don't care for the other phases.

            // Other cache request signals.
            port.mshrCacheReq[i] = FALSE;
            port.mshrCacheMuxIn[i].tagWE = FALSE;
            port.mshrCacheMuxIn[i].dataWE = FALSE;
            port.mshrCacheMuxIn[i].dataWE_OnTagHit = FALSE;
            port.mshrCacheMuxIn[i].dataDirtyIn = FALSE;
            port.mshrCacheMuxIn[i].makeMSHRCanBeInvalid = FALSE;
            port.mshrCacheMuxIn[i].evictWay = mshr[i].evictWay;
            port.mshrCacheMuxIn[i].isVictimEviction = FALSE;
            port.mshrCacheMuxIn[i].isFlushReq = FALSE;

            // Memory request signals
            port.mshrMemReq[i] = FALSE;
            port.mshrMemMuxIn[i].data = mshr[i].line;

            // Don't care
            port.mshrMemMuxIn[i].we = FALSE;
            port.mshrMemMuxIn[i].addr = mshr[i].victimAddr;


            // For flush
            mshrFlushComplete[i] = FALSE;

            case(mshr[i].phase)
                default: begin

                    // Initialize or read a  MSHR.
                    if (port.initMSHR[i]) begin
                        // 1. MSHR 登録
                        // Initial phase

                        nextMSHR[i].valid = TRUE;
                        nextMSHR[i].newAddr = port.initMSHR_Addr[i];
                        nextMSHR[i].newValid = FALSE;
                        nextMSHR[i].victimValid = FALSE;

                        nextMSHR[i].victimDirty = FALSE;
                        nextMSHR[i].victimReceived = FALSE;
                        nextMSHR[i].memSerial = '0;
                        nextMSHR[i].memWSerial = '0;

                        nextMSHR[i].canBeInvalid = FALSE;
                        nextMSHR[i].isAllocatedByStore = portIsAllocatedByStore[i];
                        nextMSHR[i].isUncachable = port.isUncachable[i];

                        nextMSHR[i].evictWay = '0;

                        // Don't care
                        nextMSHR[i].flushIndex = '0;

                        // Dont'care
                        //nextMSHR[i].line = '0;

                        if (port.isUncachable[i]) begin
                            // Uncachable access does not update cache;
                            // therefore phases for evicting a victim are skipped.
                            nextMSHR[i].phase = MSHR_PHASE_MISS_READ_MEM_REQUEST;
                        end
                        else begin
                            nextMSHR[i].phase = MSHR_PHASE_VICTIM_REQUEST;
                        end
                    end
                    else if (port.dcFlushing && (i == 0)) begin
                        // MSHR[0] is used to flush DCache.
                        nextMSHR[i].valid = TRUE;
                        nextMSHR[i].newAddr = '0;
                        nextMSHR[i].newValid = FALSE;
                        nextMSHR[i].victimValid = FALSE;

                        nextMSHR[i].victimDirty = FALSE;
                        nextMSHR[i].victimReceived = FALSE;
                        nextMSHR[i].memSerial = '0;
                        nextMSHR[i].memWSerial = '0;

                        nextMSHR[i].canBeInvalid = FALSE;
                        nextMSHR[i].isAllocatedByStore = FALSE;
                        nextMSHR[i].isUncachable = FALSE;

                        nextMSHR[i].flushIndex = '0;

                        nextMSHR[i].line = '0;

                        nextMSHR[i].phase = MSHR_PHASE_FLUSH_VICTIM_REQEUST;
                end
                end
            
            //
            // --- States for DCache flush
            //

                // FLUSH 1.
                // Send a request to DCache to (1) get a victime line corresponding to flushIndex,
                // and (2) subsequently reset the corresponding tag and data entry.
                MSHR_PHASE_FLUSH_VICTIM_REQEUST: begin
                    // Access the cache array.
                    port.mshrCacheReq[i] = TRUE;
                    port.mshrCacheMuxIn[i].indexIn = mshr[i].flushIndex;
                    port.mshrCacheMuxIn[i].tagValidIn = FALSE;
                    port.mshrCacheMuxIn[i].tagWE = TRUE;
                    port.mshrCacheMuxIn[i].dataWE = TRUE;
                    port.mshrCacheMuxIn[i].dataWE_OnTagHit = FALSE;
                    port.mshrCacheMuxIn[i].dataDirtyIn = FALSE;
                    port.mshrCacheMuxIn[i].isFlushReq = TRUE;

                    nextMSHR[i].phase =
                        port.mshrCacheGrt[i] ?
                        MSHR_PHASE_FLUSH_VICTIM_RECEIVE_TAG : MSHR_PHASE_FLUSH_VICTIM_REQEUST;
                end

                // FLUSH 2.
                // Receive a tag of the victime line.
                MSHR_PHASE_FLUSH_VICTIM_RECEIVE_TAG: begin
                    // Read a victim line.
                    if (port.mshrCacheMuxTagOut[i].tagValidOut) begin
                        nextMSHR[i].victimAddr =
                            BuildFullAddr(
                                mshr[i].flushIndex,
                                port.mshrCacheMuxTagOut[i].tagDataOut
                            );
                        nextMSHR[i].victimValid = TRUE;
                        nextMSHR[i].phase = MSHR_PHASE_FLUSH_VICTIM_RECEIVE_DATA;
                    end
                    else begin
                        nextMSHR[i].victimValid = FALSE;
                        // Skip receiving data and writing back.
                        nextMSHR[i].phase = MSHR_PHASE_FLUSH_CHECK;
                    end
                end

                // FLUSH 3.
                // Receive data and a dirty bit of the victime line.
                MSHR_PHASE_FLUSH_VICTIM_RECEIVE_DATA: begin
                    // Receive cache data.
                    nextMSHR[i].victimReceived = TRUE;
                    nextMSHR[i].line = port.mshrCacheMuxDataOut[i].dataDataOut;
                    nextMSHR[i].victimDirty = port.mshrCacheMuxDataOut[i].dataDirtyOut;

                    if (nextMSHR[i].victimDirty) begin
                        // Write back dirty data
                        nextMSHR[i].phase = MSHR_PHASE_FLUSH_VICTIM_WRITE_TO_MEM;
                    end
                    else begin
                        nextMSHR[i].phase = MSHR_PHASE_FLUSH_CHECK;
                    end
                end

                // FLUSH 4.
                // Send a write back request of the dirty victime line to the data bus.
                MSHR_PHASE_FLUSH_VICTIM_WRITE_TO_MEM: begin
                    port.mshrMemReq[i] = TRUE;
                    port.mshrMemMuxIn[i].we = TRUE;
                    port.mshrMemMuxIn[i].addr = mshr[i].victimAddr;

                    if (port.mshrMemGrt[i] && port.mshrMemMuxOut[i].ack) begin
                        nextMSHR[i].memWSerial = port.mshrMemMuxOut[i].wserial;
                        nextMSHR[i].phase = MSHR_PHASE_FLUSH_VICTIM_WRITE_COMPLETE;
                    end
                    else begin
                        // Waiting until the request is accepted.
                        nextMSHR[i].phase = MSHR_PHASE_FLUSH_VICTIM_WRITE_TO_MEM;
                    end
                end

                // FLUSH 5.
                // Wait until the data is written back.
                MSHR_PHASE_FLUSH_VICTIM_WRITE_COMPLETE: begin
                    port.mshrMemReq[i] = FALSE;
                    if (mshr[i].victimValid &&
                        mshr[i].victimDirty &&
                        !(port.memAccessResponse.valid &&
                        mshr[i].memWSerial == port.memAccessResponse.serial)
                    ) begin
                        // Wait MSHR_PHASE_FLUSH_VICTIM_WRITE_COMPLETE.
                        nextMSHR[i].phase = MSHR_PHASE_FLUSH_VICTIM_WRITE_COMPLETE;
                    end
                    else begin
                        nextMSHR[i].phase = MSHR_PHASE_FLUSH_CHECK;
                    end
                end

                // FLUSH 6.
                // Ckeck if all cache lines have been written back.
                MSHR_PHASE_FLUSH_CHECK: begin
                    if (&(mshr[i].flushIndex)) begin
                        nextMSHR[i].flushIndex = '0;
                        mshrFlushComplete[i] = TRUE;
                    end
                    else begin
                        nextMSHR[i].flushIndex = mshr[i].flushIndex + 1;
                    end

                    nextMSHR[i].victimValid = FALSE;
                    nextMSHR[i].victimDirty = FALSE;
                    nextMSHR[i].victimReceived = FALSE;
                    nextMSHR[i].memSerial = '0;
                    nextMSHR[i].memWSerial = '0;
                    nextMSHR[i].line = '0;

                    if (mshrFlushComplete[i]) begin
                        nextMSHR[i].phase = MSHR_PHASE_INVALID;
                        nextMSHR[i].valid = FALSE;
                    end
                    else begin
                        nextMSHR[i].phase = MSHR_PHASE_FLUSH_VICTIM_REQEUST;
                    end
                end

            //
            // --- States for DCache flush (end)
            //

            //
            // --- States for DCache miss handling
            //

                // 2. リプレース対象の読み出し
                MSHR_PHASE_VICTIM_REQUEST: begin
                    // Access the cache array.
                    port.mshrCacheReq[i] = TRUE;
                    port.mshrCacheMuxIn[i].tagWE = FALSE;
                    port.mshrCacheMuxIn[i].dataWE = FALSE;
                    port.mshrCacheMuxIn[i].dataWE_OnTagHit = FALSE;
                    port.mshrCacheMuxIn[i].dataDirtyIn = FALSE;
                    port.mshrCacheMuxIn[i].isVictimEviction = TRUE;

                    nextMSHR[i].phase =
                        port.mshrCacheGrt[i] ?
                        MSHR_PHASE_VICTIM_RECEIVE_TAG : MSHR_PHASE_VICTIM_REQUEST;
                end

                MSHR_PHASE_VICTIM_RECEIVE_TAG: begin
                    // Read a victim line and receive tag data.
                    nextMSHR[i].tagDataOut = port.mshrCacheMuxTagOut[i].tagDataOut;
                    nextMSHR[i].tagValidOut = port.mshrCacheMuxTagOut[i].tagValidOut;
                    nextMSHR[i].phase = MSHR_PHASE_VICTIM_RECEIVE_DATA;
                end


                MSHR_PHASE_VICTIM_RECEIVE_DATA: begin
                    
                    // 置き換え情報
                    nextMSHR[i].evictWay = port.mshrCacheMuxDataOut[i].replDataOut;
                    if (mshr[i].tagValidOut[nextMSHR[i].evictWay]) begin
                        // 追い出し対象の読み出し済みタグと新しいアドレスの
                        // インデックスからフルアドレスを作る
                        nextMSHR[i].victimAddr =
                            BuildFullAddr(
                                ToIndexPartFromFullAddr(mshr[i].newAddr),
                                mshr[i].tagDataOut[
                                    nextMSHR[i].evictWay
                                ]
                            );
                        nextMSHR[i].victimValid = TRUE;
                    end
                    else begin
                        nextMSHR[i].victimValid = FALSE;
                    end


                    // Receive cache data.
                    // The data array outputs an evicted way determined in the array.
                    nextMSHR[i].victimReceived = TRUE;
                    nextMSHR[i].line = port.mshrCacheMuxDataOut[i].dataDataOut;
                    nextMSHR[i].victimDirty = port.mshrCacheMuxDataOut[i].dataDirtyOut;

                    if (nextMSHR[i].victimValid && nextMSHR[i].victimDirty) begin
                        nextMSHR[i].phase = MSHR_PHASE_VICTIM_WRITE_TO_MEM;
                    end
                    else begin
                        nextMSHR[i].phase = MSHR_PHASE_MISS_READ_MEM_REQUEST;
                    end
                end

                // 3. リプレース対象の書き出し
                MSHR_PHASE_VICTIM_WRITE_TO_MEM: begin
                    port.mshrMemReq[i] = TRUE;
                    port.mshrMemMuxIn[i].we = TRUE;
                    port.mshrMemMuxIn[i].addr = mshr[i].victimAddr;

                    if (port.mshrMemGrt[i] && port.mshrMemMuxOut[i].ack) begin
                        nextMSHR[i].memWSerial = port.mshrMemMuxOut[i].wserial;
                        nextMSHR[i].phase = MSHR_PHASE_VICTIM_WRITE_COMPLETE;
                    end
                    else begin
                        // Waiting until the request is accepted.
                        nextMSHR[i].phase = MSHR_PHASE_VICTIM_WRITE_TO_MEM;
                    end

                end

                // 4. リプレース対象の書き込み完了まで待機
                MSHR_PHASE_VICTIM_WRITE_COMPLETE: begin
                    port.mshrMemReq[i] = FALSE;
                    if (mshr[i].victimValid &&
                        mshr[i].victimDirty &&
                        !(port.memAccessResponse.valid &&
                        mshr[i].memWSerial == port.memAccessResponse.serial)
                    ) begin
                        // Wait MSHR_PHASE_VICTIM_WRITE_TO_MEM.
                        nextMSHR[i].phase = MSHR_PHASE_VICTIM_WRITE_COMPLETE;
                    end
                    else begin
                        nextMSHR[i].phase = MSHR_PHASE_MISS_READ_MEM_REQUEST;
                    end
                end

                // 5. ミスデータのメモリからの読みだし
                MSHR_PHASE_MISS_READ_MEM_REQUEST: begin
                    /* メモリ書込はResultを待たないように仕様変更
                    if (mshr[i].victimValid &&
                        mshr[i].victimDirty &&
                        !(port.memAccessResult.valid &&
                        mshr[i].memSerial == port.memAccessResult.serial)
                    ) begin
                        // Wait MSHR_PHASE_VICTIM_WRITE_TO_MEM.
                        port.mshrMemReq[i] = FALSE;
                    end
                    */
                    //else begin
                    if (TRUE) begin
                        // A victim line has been written to the memory and
                        // data on an MSHR entry is not valid.
                        nextMSHR[i].victimValid = FALSE;

                        // Fetch a missed line.
                        port.mshrMemReq[i] = TRUE;
                        port.mshrMemMuxIn[i].we = FALSE;
                        port.mshrMemMuxIn[i].addr = ToLineAddrFromFullAddr(mshr[i].newAddr);

                        if (port.mshrMemGrt[i] && port.mshrMemMuxOut[i].ack) begin
                            nextMSHR[i].memSerial = port.mshrMemMuxOut[i].serial;
                            nextMSHR[i].phase = MSHR_PHASE_MISS_READ_MEM_RECEIVE;
                        end
                        else begin
                            // Waiting until the request is accepted.
                            nextMSHR[i].phase = MSHR_PHASE_MISS_READ_MEM_REQUEST;
                        end
                    end
                end

                // Receive memory data.
                MSHR_PHASE_MISS_READ_MEM_RECEIVE: begin
                    if (!(port.memAccessResult.valid &&
                        mshr[i].memSerial == port.memAccessResult.serial)
                    ) begin
                        // Waiting until data is received.
                        nextMSHR[i].phase = MSHR_PHASE_MISS_READ_MEM_RECEIVE;
                    end
                    else begin
                        // Set a fetched line to a MSHR entry and go to the next phase.
                        nextMSHR[i].line = port.memAccessResult.data;
                        nextMSHR[i].newValid = TRUE;
                        if (mshr[i].isAllocatedByStore) begin
                            nextMSHR[i].phase = MSHR_PHASE_MISS_MERGE_STORE_DATA;
                        end
                        else if (mshr[i].isUncachable) begin
                            // An uncachable load does not update cache and 
                            // receives data via this MSHR entry directly.
                            nextMSHR[i].phase = MSHR_PHASE_MISS_HANDLING_COMPLETE;
                        end
                        else begin
                            // A cachable load updates cache using the fetched cache line.
                            nextMSHR[i].phase = MSHR_PHASE_MISS_WRITE_CACHE_REQUEST;
                        end
                    end
                end

                // 5.5. MSHRエントリの割り当て者がStore命令の場合，ミスデータとストア命令のデータを結合する
                MSHR_PHASE_MISS_MERGE_STORE_DATA: begin
                    // Merge the allocator store data and the fetched line.
                    MergeStoreDataToLine(mergedLine[i], mshr[i].line,
                        portStoredLineData, portStoredLineByteWE);
                    nextMSHR[i].line = mergedLine[i];

                    if (mshr[i].isUncachable) begin
                        // An uncachable store does not update cache and 
                        // writes the updated cache line back to memory.
                        nextMSHR[i].phase = MSHR_PHASE_UNCACHABLE_WRITE_TO_MEM;
                    end
                    else begin
                        // A cachable store updates cache using the updated cache line.
                        nextMSHR[i].phase = MSHR_PHASE_MISS_WRITE_CACHE_REQUEST;
                    end
                end

                // 6. (Uncachable store) Issue a write request to write the updated cache line.
                MSHR_PHASE_UNCACHABLE_WRITE_TO_MEM: begin
                    port.mshrMemReq[i] = TRUE;
                    port.mshrMemMuxIn[i].we = TRUE;
                    port.mshrMemMuxIn[i].addr = ToLineAddrFromFullAddr(mshr[i].newAddr);

                    if (port.mshrMemGrt[i] && port.mshrMemMuxOut[i].ack) begin
                        nextMSHR[i].memWSerial = port.mshrMemMuxOut[i].wserial;
                        nextMSHR[i].phase = MSHR_PHASE_UNCACHABLE_WRITE_COMPLETE;
                    end
                    else begin
                        // Waiting until the request is accepted.
                        nextMSHR[i].phase = MSHR_PHASE_UNCACHABLE_WRITE_TO_MEM;
                    end

                end

                // 6.5. (Uncachable store) Wait until the updated cache line is written to memory.
                MSHR_PHASE_UNCACHABLE_WRITE_COMPLETE: begin
                    port.mshrMemReq[i] = FALSE;
                    if (mshr[i].newValid &&
                        !(port.memAccessResponse.valid &&
                        mshr[i].memWSerial == port.memAccessResponse.serial)
                    ) begin
                        // Wait MSHR_PHASE_UNCACHABLE_WRITE_COMPLETE.
                        nextMSHR[i].phase = MSHR_PHASE_UNCACHABLE_WRITE_COMPLETE;
                    end
                    else begin
                        nextMSHR[i].phase = MSHR_PHASE_MISS_HANDLING_COMPLETE;
                    end
                end

                // 6. (Cachable load/store) ミスデータのキャッシュへの書き込み
                MSHR_PHASE_MISS_WRITE_CACHE_REQUEST: begin
                    // Fill the cache array.
                    port.mshrCacheReq[i] = TRUE;
                    port.mshrCacheMuxIn[i].tagWE = TRUE;
                    port.mshrCacheMuxIn[i].dataWE = TRUE;
                    port.mshrCacheMuxIn[i].dataWE_OnTagHit = FALSE;
                    port.mshrCacheMuxIn[i].dataDirtyIn = mshr[i].isAllocatedByStore;
                    // Use the saved evict way.
                    port.mshrCacheMuxIn[i].evictWay = mshr[i].evictWay;

                    if (port.mshrCacheGrt[i]) begin
                        // If my request is granted, miss handling finishes.
                        nextMSHR[i].phase = MSHR_PHASE_MISS_HANDLING_COMPLETE;
                    end
                    else begin
                        nextMSHR[i].phase = MSHR_PHASE_MISS_WRITE_CACHE_REQUEST;
                    end
                end

                // 7.
                // * (Cachable) データアレイへの書き込みと解放可能条件を待って MSHR 解放
                // 現在の開放可能条件は
                // ・割り当て者がLoadでそのLoadへのデータの受け渡しが完了した場合
                // ・割り当て者がStoreの場合 (該当Storeのデータはこの時点でキャッシュ or Memoryに書き込まれている)
                MSHR_PHASE_MISS_HANDLING_COMPLETE: begin
                    if (mshr[i].canBeInvalid || mshr[i].isAllocatedByStore) begin
                        nextMSHR[i].phase = MSHR_PHASE_INVALID;
                        nextMSHR[i].valid = FALSE;
                    end
                end
            endcase // case(mshr[i].phase)

            if (port.makeMSHRCanBeInvalidByMemoryRegisterReadStage[i]) begin
                // MSHR can be invalid when
                // its allocator load has been flushed at MemoryRegisterReadStage.
                nextMSHR[i].canBeInvalid = TRUE;
            end
            else if (port.makeMSHRCanBeInvalidByMemoryTagAccessStage[i]) begin
                // MSHR can be invalid when
                // its allocator load has completed correctly because of StoreForwarding.
                nextMSHR[i].canBeInvalid = TRUE;
            end
            else if (port.makeMSHRCanBeInvalidByReplayQueue[i]) begin
                // MSHR can be invalid when
                // its allocator load has been flushed at the top of ReplayQueue.
                nextMSHR[i].canBeInvalid = TRUE;
            end
            else if (port.mshrCanBeInvalid[i] && (mshr[i].phase >= MSHR_PHASE_MISS_WRITE_CACHE_REQUEST)) begin
                nextMSHR[i].canBeInvalid = TRUE;
            end
        end // for (int i = 0; i < MSHR_NUM; i++) begin
    end



endmodule : DCacheMissHandler

