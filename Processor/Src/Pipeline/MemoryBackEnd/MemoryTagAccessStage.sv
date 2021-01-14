// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Tag access stage
//

`include "BasicMacros.sv"

import BasicTypes::*;
import OpFormatTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import PipelineTypes::*;
import DebugTypes::*;
import MicroOpTypes::*;
import CacheSystemTypes::*;
import MemoryMapTypes::*;

// When this switch is enabled, instructions are re-issued from the issue queue.
// Otherwise, instructions are refetched.
`define RSD_ENABLE_REISSUE_ON_CACHE_MISS

// To a part of a line index from a full address.
function automatic DCacheIndexSubsetPath ToIndexSubsetPartFromFullAddrInMTStage(input AddrPath addr);
    return addr[DCACHE_LINE_BYTE_NUM_BIT_WIDTH+DCACHE_INDEX_SUBSET_BIT_WIDTH-1 : DCACHE_LINE_BYTE_NUM_BIT_WIDTH];
endfunction

module MemoryTagAccessStage(
    MemoryTagAccessStageIF.ThisStage port,
    MemoryExecutionStageIF.NextStage prev,
    SchedulerIF.MemoryTagAccessStage scheduler,
    LoadStoreUnitIF.MemoryTagAccessStage loadStoreUnit,
    MulDivUnitIF.MemoryTagAccessStage mulDivUnit,    
    RecoveryManagerIF.MemoryTagAccessStage recovery,
    ControllerIF.MemoryTagAccessStage ctrl,
    DebugIF.MemoryTagAccessStage debug,
    PerformanceCounterIF.MemoryTagAccessStage perfCounter
);

    MemoryTagAccessStageRegPath pipeReg[MEM_ISSUE_WIDTH];
    MemoryTagAccessStageRegPath ldPipeReg[LOAD_ISSUE_WIDTH];
    MemoryTagAccessStageRegPath stPipeReg[STORE_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif

    // --- Pipeline registers
    always_ff@( posedge port.clk )   // synchronous rst
    begin
        if (port.rst) begin
            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                pipeReg[i].valid <= '0;
            end
        end
        else if(!ctrl.backEnd.stall) begin              // write data
            pipeReg <= prev.nextStage;
        end
    end

    // Pipeline control
    logic stall, clear;

    logic lsuMakeMSHRCanBeInvalidByMemoryTagAccessStage[MSHR_NUM];
    MSHR_IndexPath mshrID;

    MemIssueQueueEntry ldIqData[LOAD_ISSUE_WIDTH];
    MemIssueQueueEntry stIqData[STORE_ISSUE_WIDTH];

    always_comb begin
        // Pipeline control
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;


        for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            ldPipeReg[i] = pipeReg[i];
            ldIqData[i] = pipeReg[i].memQueueData;
        end
        for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
            stPipeReg[i] = pipeReg[i + STORE_ISSUE_LANE_BEGIN];
            stIqData[i] = pipeReg[i + STORE_ISSUE_LANE_BEGIN].memQueueData;
        end

    end

    // Load pipe
    logic isLoad    [LOAD_ISSUE_WIDTH];
    logic isCSR     [LOAD_ISSUE_WIDTH];
    logic isENV     [LOAD_ISSUE_WIDTH];
    logic ldUpdate  [LOAD_ISSUE_WIDTH];
    logic ldRegValid[LOAD_ISSUE_WIDTH];
    logic ldFlush   [LOAD_ISSUE_WIDTH];
    logic isDiv     [LOAD_ISSUE_WIDTH];
    logic isMul     [LOAD_ISSUE_WIDTH];
    logic isFenceI  [LOAD_ISSUE_WIDTH];
    MemoryAccessStageRegPath ldNextStage[LOAD_ISSUE_WIDTH];
    MemIssueQueueEntry ldRecordData[LOAD_ISSUE_WIDTH];  // for ReplayQueue

    logic ldMSHR_Allocated[LOAD_ISSUE_WIDTH];
    logic ldMSHR_Hit[LOAD_ISSUE_WIDTH];
    DataPath ldMSHR_EntryID[LOAD_ISSUE_WIDTH];

    always_comb begin
        for ( int i = 0; i < MSHR_NUM; i++ ) begin
            lsuMakeMSHRCanBeInvalidByMemoryTagAccessStage[i] = FALSE;
        end

        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin

            ldFlush[i] = SelectiveFlushDetector(
                            recovery.toRecoveryPhase,
                            recovery.flushRangeHeadPtr,
                            recovery.flushRangeTailPtr,
                            ldIqData[i].activeListPtr
                        );
            ldUpdate[i]  = ldPipeReg[i].valid && !stall && !clear && !ldFlush[i];
            isLoad[i] = ( ldIqData[i].memOpInfo.opType == MEM_MOP_TYPE_LOAD );
            isCSR[i] = ( ldIqData[i].memOpInfo.opType == MEM_MOP_TYPE_CSR );
            isENV[i] = ( ldIqData[i].memOpInfo.opType == MEM_MOP_TYPE_ENV );
            isDiv[i] = ( ldIqData[i].memOpInfo.opType == MEM_MOP_TYPE_DIV );
            isMul[i] = ( ldIqData[i].memOpInfo.opType == MEM_MOP_TYPE_MUL );
            isFenceI[i] = ( ldIqData[i].memOpInfo.opType == MEM_MOP_TYPE_FENCE ) && ldIqData[i].memOpInfo.isFenceI;

            // Load store unit
            loadStoreUnit.executeLoad[i] = ldUpdate[i] && isLoad[i];
            loadStoreUnit.executedLoadAddr[i] = ldPipeReg[i].phyAddrOut;
            loadStoreUnit.executedLoadPC[i] = ldIqData[i].pc;
            loadStoreUnit.executedLoadMemAccessMode[i] = ldIqData[i].memOpInfo.memAccessMode;
            loadStoreUnit.executedStoreQueuePtrByLoad[i] = ldIqData[i].memOpInfo.storeQueuePtr;
            loadStoreUnit.executedLoadQueuePtrByLoad[i] = ldIqData[i].memOpInfo.loadQueuePtr;

            // Set hasAllocatedMSHR and mshrID info to notice ReplayQueue
            // whether missed loads have allocated MSHRs or not.
`ifndef RSD_DISABLE_DEBUG_REGISTER // Debug info
            ldRecordData[i].opId = ldPipeReg[i].memQueueData.opId;
`endif
            ldRecordData[i].activeListPtr = ldPipeReg[i].memQueueData.activeListPtr;
            ldRecordData[i].opSrc         = ldPipeReg[i].memQueueData.opSrc;
            ldRecordData[i].opDst         = ldPipeReg[i].memQueueData.opDst;
            ldRecordData[i].pc            = ldPipeReg[i].memQueueData.pc;
            ldRecordData[i].memOpInfo     = ldPipeReg[i].memQueueData.memOpInfo;
            ldRecordData[i].storeQueueRecoveryPtr = ldIqData[i].storeQueueRecoveryPtr;
            ldRecordData[i].loadQueueRecoveryPtr  = ldIqData[i].loadQueueRecoveryPtr;

            // For performance counters
            ldMSHR_Allocated[i] = FALSE;
            ldMSHR_Hit[i] = FALSE;
            ldMSHR_EntryID[i] = 0;

            // Set MSHR id if the load instruction allocated a MSHR entry.
            if (ldPipeReg[i].memQueueData.memOpInfo.hasAllocatedMSHR) begin
                ldRecordData[i].memOpInfo.hasAllocatedMSHR = ldPipeReg[i].memQueueData.memOpInfo.hasAllocatedMSHR;
                ldRecordData[i].memOpInfo.mshrID = ldPipeReg[i].memQueueData.memOpInfo.mshrID;
                // TODO: バグで Ex ステージで hasAllocatedMSHR が落とされているので，
                // ここに来ることは絶対無い
            end
            else begin
                if (i < LOAD_ISSUE_WIDTH) begin
                    ldRecordData[i].memOpInfo.hasAllocatedMSHR = loadStoreUnit.loadHasAllocatedMSHR[i];

                    // There are two sources of MSHR ID to memorize,
                    // 1. when a load hits a MSHR entry, the hit MSHR ID,
                    // 2. when a load allocates a MSHR entry, the allocated MSHR ID.
                    // 3. when otherwise (no hit and no allocate), don't ldUpdate.
                    if (loadStoreUnit.loadHasAllocatedMSHR[i]) begin
                        ldRecordData[i].memOpInfo.mshrID = loadStoreUnit.loadMSHRID[i];
                        // MSHR allocation is performed 
                        ldMSHR_Allocated[i] = TRUE;
                        ldMSHR_EntryID[i] = loadStoreUnit.loadMSHRID[i];
                    end
                    else if (loadStoreUnit.mshrAddrHit[i]) begin
                        // TODO: バグで Ex ステージで hasAllocatedMSHR が落とされているので，
                        // MSHR 確保後はここのパスを通ってしまう．意図してはいないがたまたま動いている．
                        ldRecordData[i].memOpInfo.mshrID = loadStoreUnit.mshrAddrHitMSHRID[i];
                        // MSHR Hit?
                        ldMSHR_Hit[i] = loadStoreUnit.mshrReadHit[i];
                        ldMSHR_EntryID[i] = loadStoreUnit.mshrAddrHitMSHRID[i];
                    end
                    else begin
                        ldRecordData[i].memOpInfo.mshrID = ldPipeReg[i].memQueueData.memOpInfo.mshrID;
                    end
                end
                else begin
                    ldRecordData[i].memOpInfo.hasAllocatedMSHR = FALSE;
                    ldRecordData[i].memOpInfo.mshrID = '0;
                end
            end

            loadStoreUnit.dcReadCancelFromMT_Stage[i] = FALSE;
            

`ifdef RSD_ENABLE_REISSUE_ON_CACHE_MISS
            if (isLoad[i]) begin
                if (loadStoreUnit.storeLoadForwarded[i]) begin
                    loadStoreUnit.dcReadCancelFromMT_Stage[i] = TRUE;   // キャンセルしてMSHR の確保を行わせない
                    ldRegValid[i] = loadStoreUnit.forwardMiss[i] ? FALSE : ldPipeReg[i].regValid;
                end
                else if (ldRecordData[i].memOpInfo.hasAllocatedMSHR) begin
                    // When the load has allocated an MSHR entry,
                    // The data will come from MSHR.
                    ldRegValid[i] = loadStoreUnit.mshrReadHit[i] ? ldPipeReg[i].regValid : FALSE;
                end
                else if (loadStoreUnit.mshrReadHit[i]) begin
                    ldRegValid[i] = ldPipeReg[i].regValid;
                end
                else begin
                    // The consumers of a missed load is invalidate.
                    ldRegValid[i] = loadStoreUnit.dcReadHit[i] ? ldPipeReg[i].regValid : FALSE;
                end
            end
            else if (ldRecordData[i].memOpInfo.hasAllocatedMSHR) begin
                // When the prefetch load has allocated an MSHR entry,
                // The data will come from MSHR.
                ldRegValid[i] = loadStoreUnit.mshrReadHit[i] ? ldPipeReg[i].regValid : FALSE;
            end
            else begin
                ldRegValid[i] = ldPipeReg[i].regValid;
            end
`else
            ldRegValid[i] = TRUE;
`endif

            // Sends to the load queue whether the load executed in this cycle is valid.
            loadStoreUnit.executedLoadRegValid[i] = ldRegValid[i];
            
            `ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
                if (isDiv[i] && ldRegValid[i]) begin
                    /*ldPipeReg[i].replay && */
                    ldRegValid[i] = mulDivUnit.divFinished[i];
                end
                mulDivUnit.divResetFromMT_Stage[i] = 
                    ldRegValid[i] && (ldFlush[i] || clear) && isDiv[i];
            `endif

            // Pipeline レジスタ書き込み
            ldNextStage[i].regValid = ldRegValid[i];
            ldNextStage[i].addrOut = ldPipeReg[i].addrOut;
            ldNextStage[i].memMapType = ldPipeReg[i].memMapType;
            ldNextStage[i].phyAddrOut = ldPipeReg[i].phyAddrOut;
            ldNextStage[i].csrDataOut = ldPipeReg[i].dataIn;

            ldNextStage[i].isLoad  = isLoad[i];
            ldNextStage[i].isStore = FALSE;
            ldNextStage[i].isCSR   = isCSR[i];
            ldNextStage[i].isDiv   = isDiv[i];
            ldNextStage[i].isMul   = isMul[i];

            ldNextStage[i].opDst = ldIqData[i].opDst;
            ldNextStage[i].activeListPtr = ldIqData[i].activeListPtr;
            ldNextStage[i].loadQueueRecoveryPtr  = ldIqData[i].loadQueueRecoveryPtr;
            ldNextStage[i].storeQueueRecoveryPtr = ldIqData[i].storeQueueRecoveryPtr;
            ldNextStage[i].pc = ldIqData[i].pc;


            // ExecState
            // 命令の実行結果によって、再フェッチが必要かどうかなどを判定する
            if (!ldUpdate[i] || (ldUpdate[i] && !ldRegValid[i])) begin
                ldNextStage[i].execState = EXEC_STATE_NOT_FINISHED;
            end
            else if ( isLoad[i] ) begin
                // ロードの実行に失敗した場合は、
                // 正しい実行結果が得られていないので、
                // そのロード命令からやり直す
                if ( loadStoreUnit.storeLoadForwarded[i] ) begin
                    // フォワードされた場合
                    ldNextStage[i].execState =
                        loadStoreUnit.forwardMiss[i] ? EXEC_STATE_REFETCH_THIS : EXEC_STATE_SUCCESS;
                    if (ldRecordData[i].memOpInfo.hasAllocatedMSHR) begin
                        lsuMakeMSHRCanBeInvalidByMemoryTagAccessStage[ldRecordData[i].memOpInfo.mshrID] = TRUE;
                    end
                end
                else if (ldRecordData[i].memOpInfo.hasAllocatedMSHR) begin
                    ldNextStage[i].execState =
                            loadStoreUnit.mshrReadHit[i] ? EXEC_STATE_SUCCESS : EXEC_STATE_REFETCH_THIS;
                end
                else if (loadStoreUnit.mshrReadHit[i]) begin
                    ldNextStage[i].execState = EXEC_STATE_SUCCESS;
                end
                else begin
                    // DCache
                    ldNextStage[i].execState =
                        loadStoreUnit.dcReadHit[i] ? EXEC_STATE_SUCCESS : EXEC_STATE_REFETCH_THIS;
                end
            end
            else if (ldRecordData[i].memOpInfo.hasAllocatedMSHR) begin
                ldNextStage[i].execState =
                        loadStoreUnit.mshrReadHit[i] ? EXEC_STATE_SUCCESS : EXEC_STATE_REFETCH_THIS;
            end
            else if (isENV[i]) begin
                // EBREAK/ECALL/MRET はトラップ扱い
                unique case (ldIqData[i].memOpInfo.envCode)
                ENV_BREAK:          ldNextStage[i].execState = EXEC_STATE_TRAP_EBREAK;
                ENV_CALL:           ldNextStage[i].execState = EXEC_STATE_TRAP_ECALL;
                ENV_MRET:           ldNextStage[i].execState = EXEC_STATE_TRAP_MRET;
                ENV_INSN_ILLEGAL:   ldNextStage[i].execState = EXEC_STATE_FAULT_INSN_ILLEGAL;
                ENV_INSN_VIOLATION: ldNextStage[i].execState = EXEC_STATE_FAULT_INSN_VIOLATION;
                default:
                    ldNextStage[i].execState = EXEC_STATE_TRAP_EBREAK;
                endcase
            end
            else if (isFenceI[i]) begin
                // FENCE.I flush all following ops when it is committed
                // not to use the expired data from ICache.
                ldNextStage[i].execState = EXEC_STATE_REFETCH_NEXT;
            end
`ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            else if (isDiv[i]) begin
                ldNextStage[i].execState = mulDivUnit.divFinished[i] ? EXEC_STATE_SUCCESS : EXEC_STATE_NOT_FINISHED;
            end
`endif 
            else begin
                ldNextStage[i].execState = EXEC_STATE_SUCCESS;
            end

            // 実行が正しく終了してる場合，フォールト判定を行う
            // ストアの依存予測ではこちらの方が優先される
            if (ldNextStage[i].execState inside {EXEC_STATE_SUCCESS, EXEC_STATE_REFETCH_NEXT}) begin
                if (isLoad[i]) begin
                    if (ldPipeReg[i].memMapType == MMT_ILLEGAL)
                        ldNextStage[i].execState = EXEC_STATE_FAULT_LOAD_VIOLATION;
                    else if (IsMisalignedAddress(ldPipeReg[i].addrOut, ldIqData[i].memOpInfo.memAccessMode.size))
                        ldNextStage[i].execState = EXEC_STATE_FAULT_LOAD_MISALIGNED;
                end
            end


            // リセットorフラッシュ時はNOP
            ldNextStage[i].valid =
                (stall || clear || port.rst || ldFlush[i]) ? FALSE : ldPipeReg[i].valid;

`ifndef RSD_DISABLE_DEBUG_REGISTER
            ldNextStage[i].opId = ldPipeReg[i].opId;
`endif
        end // for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin

        //フラッシュによってMSHRをアロケートしたロード命令がフラッシュされる場合のMSHRの解放処理
        for ( int i = 0; i < MSHR_NUM; i++ ) begin
            loadStoreUnit.makeMSHRCanBeInvalidByMemoryTagAccessStage[i] = FALSE;
        end
        for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            if (ldPipeReg[i].valid && isLoad[i]) begin
                if (ldFlush[i]) begin
                    lsuMakeMSHRCanBeInvalidByMemoryTagAccessStage[i] = ldRecordData[i].memOpInfo.hasAllocatedMSHR;
                end
            end
            else begin
                lsuMakeMSHRCanBeInvalidByMemoryTagAccessStage[i] = FALSE;
            end

            mshrID = ldRecordData[i].memOpInfo.mshrID;
            if (lsuMakeMSHRCanBeInvalidByMemoryTagAccessStage[i] && isLoad[i]) begin
                loadStoreUnit.makeMSHRCanBeInvalidByMemoryTagAccessStage[mshrID] = TRUE;
            end
        end

    end // always_comb


    logic isStore   [STORE_ISSUE_WIDTH];
    logic stUpdate  [STORE_ISSUE_WIDTH];
    logic stRegValid[STORE_ISSUE_WIDTH];
    logic stFlush   [STORE_ISSUE_WIDTH];
    MemoryAccessStageRegPath stNextStage[STORE_ISSUE_WIDTH];
    MemIssueQueueEntry stRecordData[STORE_ISSUE_WIDTH];  // for ReplayQueue

    // For memory dependency prediction (only for STORE)
    logic memAccessOrderViolation[STORE_ISSUE_WIDTH];

    always_comb begin

        for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
            memAccessOrderViolation[i] = FALSE;
            stFlush[i] = SelectiveFlushDetector(
                            recovery.toRecoveryPhase,
                            recovery.flushRangeHeadPtr,
                            recovery.flushRangeTailPtr,
                            stIqData[i].activeListPtr
                        );
            stUpdate[i]  = stPipeReg[i].valid && !stall && !clear && !stFlush[i];
            isStore[i] = (stIqData[i].memOpInfo.opType == MEM_MOP_TYPE_STORE);

            // Load store unit
            loadStoreUnit.executeStore[i] = stUpdate[i] && isStore[i];
            loadStoreUnit.executedStoreData[i] = stPipeReg[i].dataIn;
`ifdef RSD_ENABLE_VECTOR_PATH
            loadStoreUnit.executedStoreVectorData[i] = stPipeReg[i].vecDataIn;
`else
            loadStoreUnit.executedStoreVectorData[i] = '0;
`endif
            loadStoreUnit.executedStoreAddr[i] = stPipeReg[i].phyAddrOut;
            loadStoreUnit.executedStoreCondEnabled[i]   = stPipeReg[i].condEnabled;
            loadStoreUnit.executedStoreRegValid[i] = stPipeReg[i].regValid;
            loadStoreUnit.executedStoreMemAccessMode[i] = stIqData[i].memOpInfo.memAccessMode;
            loadStoreUnit.executedLoadQueuePtrByStore[i] = stIqData[i].memOpInfo.loadQueuePtr;
            loadStoreUnit.executedStoreQueuePtrByStore[i] = stIqData[i].memOpInfo.storeQueuePtr;

            // Set hasAllocatedMSHR and mshrID info to notice ReplayQueue
            // whether missed loads have allocated MSHRs or not.
`ifndef RSD_DISABLE_DEBUG_REGISTER // Debug info
            stRecordData[i].opId = stPipeReg[i].memQueueData.opId;
`endif
            stRecordData[i].activeListPtr = stPipeReg[i].memQueueData.activeListPtr;
            stRecordData[i].opSrc         = stPipeReg[i].memQueueData.opSrc;
            stRecordData[i].opDst         = stPipeReg[i].memQueueData.opDst;
            stRecordData[i].pc = stPipeReg[i].memQueueData.pc;
            stRecordData[i].storeQueueRecoveryPtr = stIqData[i].storeQueueRecoveryPtr;
            stRecordData[i].loadQueueRecoveryPtr  = stIqData[i].loadQueueRecoveryPtr;
            stRecordData[i].memOpInfo = stPipeReg[i].memQueueData.memOpInfo;
            stRecordData[i].memOpInfo.hasAllocatedMSHR = FALSE;
            stRecordData[i].memOpInfo.mshrID = '0;

`ifdef RSD_ENABLE_REISSUE_ON_CACHE_MISS
            stRegValid[i] = stPipeReg[i].regValid;
`else
            stRegValid[i] = TRUE;
`endif


            // Pipeline レジスタ書き込み
            stNextStage[i].regValid   = stRegValid[i];
            stNextStage[i].addrOut    = stPipeReg[i].addrOut;
            stNextStage[i].memMapType = stPipeReg[i].memMapType;
            stNextStage[i].phyAddrOut = stPipeReg[i].phyAddrOut;
            stNextStage[i].csrDataOut = stPipeReg[i].dataIn;

            stNextStage[i].isLoad = FALSE;
            stNextStage[i].isStore = isStore[i];
            stNextStage[i].isCSR = FALSE;
            stNextStage[i].isDiv = FALSE;
            stNextStage[i].isMul = FALSE;

            stNextStage[i].opDst = stIqData[i].opDst;
            stNextStage[i].activeListPtr  = stIqData[i].activeListPtr;
            stNextStage[i].loadQueueRecoveryPtr = stIqData[i].loadQueueRecoveryPtr;
            stNextStage[i].storeQueueRecoveryPtr = stIqData[i].storeQueueRecoveryPtr;
            stNextStage[i].pc  = stIqData[i].pc;

            // ExecState
            // 命令の実行結果によって、再フェッチが必要かどうかなどを判定する
            if (!stUpdate[i] || (stUpdate[i] && !stRegValid[i])) begin
                stNextStage[i].execState = EXEC_STATE_NOT_FINISHED;
            end
            else if ( isStore[i] && loadStoreUnit.conflict[i] ) begin
                // memAccessOrderViolation
                // ストア命令自身は正しく実行できているため、
                // 次の命令からやり直す
                stNextStage[i].execState = EXEC_STATE_REFETCH_NEXT;
                // Make request for studying violation instruction to Memory dependent predictor.
                memAccessOrderViolation[i] = TRUE;
            end
            else begin
                stNextStage[i].execState = EXEC_STATE_SUCCESS;
            end

            // 実行が正しく終了してる場合，フォールト判定を行う
            // ストアの依存予測ではこちらの方が優先される
            if (stNextStage[i].execState inside {EXEC_STATE_SUCCESS, EXEC_STATE_REFETCH_NEXT}) begin
                if (isStore[i]) begin
                    if (stPipeReg[i].memMapType == MMT_ILLEGAL)
                        stNextStage[i].execState = EXEC_STATE_FAULT_STORE_VIOLATION;
                    else if (IsMisalignedAddress(stPipeReg[i].addrOut, stIqData[i].memOpInfo.memAccessMode.size))
                        stNextStage[i].execState = EXEC_STATE_FAULT_STORE_MISALIGNED;
                end
            end


            // リセットorフラッシュ時はNOP
            stNextStage[i].valid =
                (stall || clear || port.rst || stFlush[i]) ? FALSE : stPipeReg[i].valid;

`ifndef RSD_DISABLE_DEBUG_REGISTER
            stNextStage[i].opId = stPipeReg[i].opId;
`endif
        end // for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
    end // always_comb begin


    logic flush   [ MEM_ISSUE_WIDTH ];
    MemoryAccessStageRegPath nextStage[MEM_ISSUE_WIDTH];

    always_comb begin
        loadStoreUnit.memAccessOrderViolation = memAccessOrderViolation;

        `ifdef RSD_MARCH_UNIFIED_LDST_MEM_PIPE
            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                // Record instructions to the replay queue.
                if (isStore[i]) begin
                    scheduler.memRecordEntry[i] = stUpdate[i] && !stRegValid[i];
                    scheduler.memRecordData[i] = stRecordData[i];
                    scheduler.memRecordAddrHit[i] = FALSE;
                    scheduler.memRecordAddrSubset[i] = ToIndexSubsetPartFromFullAddrInMTStage(stPipeReg[i].addrOut);
                    nextStage[i] = stNextStage[i];
                    flush[i] = stFlush[i];
                end
                else begin
                    scheduler.memRecordEntry[i] = ldUpdate[i] && !ldRegValid[i];
                    scheduler.memRecordData[i] = ldRecordData[i];
                    scheduler.memRecordAddrHit[i] = loadStoreUnit.mshrAddrHit[i];
                    scheduler.memRecordAddrSubset[i] = ToIndexSubsetPartFromFullAddrInMTStage(ldPipeReg[i].addrOut);
                    nextStage[i] = ldNextStage[i];
                    flush[i] = ldFlush[i];
                end
            end
        `else
            for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
                // Record instructions to the replay queue.
                scheduler.memRecordEntry[i] = ldUpdate[i] && !ldRegValid[i];
                scheduler.memRecordData[i] = ldRecordData[i];
                scheduler.memRecordAddrHit[i] = loadStoreUnit.mshrAddrHit[i];
                scheduler.memRecordAddrSubset[i] = ToIndexSubsetPartFromFullAddrInMTStage(ldPipeReg[i].addrOut);
                nextStage[i] = ldNextStage[i];
                flush[i] = ldFlush[i];
            end
            for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
                // Record instructions to the replay queue.
                scheduler.memRecordEntry[i+STORE_ISSUE_LANE_BEGIN] = stUpdate[i] && !stRegValid[i];
                scheduler.memRecordData[i+STORE_ISSUE_LANE_BEGIN] = stRecordData[i];
                scheduler.memRecordAddrHit[i+STORE_ISSUE_LANE_BEGIN] = FALSE;
                scheduler.memRecordAddrSubset[i+STORE_ISSUE_LANE_BEGIN] = ToIndexSubsetPartFromFullAddrInMTStage(stPipeReg[i].addrOut);
                nextStage[i+STORE_ISSUE_LANE_BEGIN] = stNextStage[i];
                flush[i+STORE_ISSUE_LANE_BEGIN] = stFlush[i];
            end
        `endif

        port.nextStage = nextStage;

    end

    always_comb begin

        // Debug Register
`ifndef RSD_DISABLE_PERFORMANCE_COUNTER
        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            // Record misses only when a MSHR entry is allocated.
            perfCounter.loadMiss[i] =
                ldUpdate[i] && isLoad[i] && ldMSHR_Allocated[i];
        end
`endif

        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            debug.mtReg[i].valid = pipeReg[i].valid;
            debug.mtReg[i].flush = flush[i];
            debug.mtReg[i].opId = pipeReg[i].opId;
        end
`ifdef RSD_FUNCTIONAL_SIMULATION

        `ifdef RSD_MARCH_UNIFIED_LDST_MEM_PIPE
            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                debug.mtReg[i].executeLoad = isLoad[i] ? loadStoreUnit.executeLoad[i] : FALSE;
                debug.mtReg[i].executedLoadAddr  = loadStoreUnit.executedLoadAddr[i];
                debug.mtReg[i].mshrAllocated = ldMSHR_Allocated[i] && ldUpdate[i] && isLoad[i];
                debug.mtReg[i].mshrHit = ldMSHR_Hit[i] && ldUpdate[i] && isLoad[i];
                debug.mtReg[i].mshrEntryID = (ldMSHR_Allocated[i] || ldMSHR_Hit[i]) ? ldMSHR_EntryID[i] : 0;

                debug.mtReg[i].executeStore      = isStore[i] ? loadStoreUnit.executeStore[i] : FALSE;
                debug.mtReg[i].executedStoreAddr = loadStoreUnit.executedStoreAddr[i];
                debug.mtReg[i].executedStoreData = loadStoreUnit.executedStoreData[i];
                debug.mtReg[i].executedStoreVectorData = loadStoreUnit.executedStoreVectorData[i];
            end

        `else
            for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
                debug.mtReg[i].executeLoad       = loadStoreUnit.executeLoad[i];
                debug.mtReg[i].executedLoadAddr  = loadStoreUnit.executedLoadAddr[i];
                debug.mtReg[i].mshrAllocated = ldMSHR_Allocated[i] && ldUpdate[i] && isLoad[i];
                debug.mtReg[i].mshrHit = ldMSHR_Hit[i] && ldUpdate[i] && isLoad[i];
                debug.mtReg[i].mshrEntryID = (ldMSHR_Allocated[i] || ldMSHR_Hit[i]) ? ldMSHR_EntryID[i] : 0;
            end
            for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
                debug.mtReg[i+STORE_ISSUE_LANE_BEGIN].executeStore      = loadStoreUnit.executeStore[i];
                debug.mtReg[i+STORE_ISSUE_LANE_BEGIN].executedStoreAddr = loadStoreUnit.executedStoreAddr[i];
                debug.mtReg[i+STORE_ISSUE_LANE_BEGIN].executedStoreData = loadStoreUnit.executedStoreData[i];
                debug.mtReg[i+STORE_ISSUE_LANE_BEGIN].executedStoreVectorData = loadStoreUnit.executedStoreVectorData[i];
            end
        `endif // `ifdef RSD_FUNCTIONAL_SIMULATION
`endif // `ifdef RSD_FUNCTIONAL_SIMULATION

`endif  // `ifndef RSD_DISABLE_DEBUG_REGISTER
    end


endmodule : MemoryTagAccessStage
