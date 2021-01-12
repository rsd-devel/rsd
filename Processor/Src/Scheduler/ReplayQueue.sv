// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Replay queue
//

import BasicTypes::*;
import PipelineTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import CacheSystemTypes::*;
import RenameLogicTypes::*;

module ReplayQueue(
    SchedulerIF.ReplayQueue port,
    LoadStoreUnitIF.ReplayQueue mshr,
    MulDivUnitIF.ReplayQueue mulDivUnit,
    CacheFlushManagerIF.ReplayQueue cacheFlush,
    RecoveryManagerIF.ReplayQueue recovery,
    ControllerIF.ReplayQueue ctrl
);

    // A maximum replay interval between two entries in ReplayQueue is
    // equal to a maximum latency of all instruction.
    // TODO: modify this when adding an instruction whose latency is larger than
    //       memory access instructions.
    parameter REPLAY_QUEUE_MAX_INTERVAL = ISSUE_QUEUE_COMPLEX_LATENCY;
//    parameter REPLAY_QUEUE_MAX_INTERVAL = ISSUE_QUEUE_MEM_LATENCY;
    parameter REPLAY_QUEUE_MAX_INTERVAL_BIT_WIDTH = $clog2(REPLAY_QUEUE_MAX_INTERVAL);
    typedef logic [REPLAY_QUEUE_MAX_INTERVAL_BIT_WIDTH-1 : 0] ReplayQueueIntervalPath;


    // Body of replay queue
    typedef struct packed {
        // Int op data
        logic [INT_ISSUE_WIDTH-1 : 0] intValid;
        IntIssueQueueEntry [INT_ISSUE_WIDTH-1 : 0] intData;
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        // Complex op data
        logic [COMPLEX_ISSUE_WIDTH-1 : 0] complexValid;
        ComplexIssueQueueEntry [COMPLEX_ISSUE_WIDTH-1 : 0] complexData;
`endif
        // Mem op data
        logic [MEM_ISSUE_WIDTH-1 : 0] memValid;
        MemIssueQueueEntry [MEM_ISSUE_WIDTH-1 : 0] memData;
        logic [MEM_ISSUE_WIDTH-1 : 0] memAddrHit;
        DCacheIndexSubsetPath [MEM_ISSUE_WIDTH-1 : 0] memAddrSubset;
        // How many cycles to replay after waiting
        ReplayQueueIntervalPath replayInterval;
    } ReplayQueueEntry;

    ReplayQueueEntry recordData;
    ReplayQueueEntry replayEntryOut;

    ReplayQueueIndexPath headPtr;
    ReplayQueueIndexPath tailPtr;
    logic full;
    logic empty;

    // Input instructions are pushed when
    // some of these are valid.
    logic pushEntry;

    // Head instructions of ReplayQueue are poped unless
    // some loads of these are valid,
    // have allocated MSHR entries and
    // these MSHR entries have not receive data yet.
    logic popEntry;

    // To accept all instructions which must be pushed to ReplayQueue,
    // schedule and issue stage must stall when ReplayQueue is "almost" full.
    // The threshold is REPLAY_QUEUE_ENTRY_NUM - ISSUE_QUEUE_MEM_LATENCY
    // because ISSUE_QUEUE_MEM_LATENCY entries will pushed to ReplayQueue at most
    // after schedule and issue stage stall.
    logic almostFull;
    ReplayQueueCountPath count;

    // size, initial head, initial tail, initial count
    QueuePointerWithEntryCount #( REPLAY_QUEUE_ENTRY_NUM, 0, 0, 0 )
        pointer(
            .clk( port.clk ),
            .rst( port.rst ),
            .push( pushEntry ),
            .pop( popEntry ),
            .full( full ),
            .empty( empty ),
            .headPtr( headPtr ),
            .tailPtr( tailPtr ),
            .count ( count )
    );

    DistributedDualPortRAM #(
        .ENTRY_NUM( 1 << REPLAY_QUEUE_ENTRY_NUM_BIT_WIDTH ),
        .ENTRY_BIT_SIZE( $bits(ReplayQueueEntry) )
    ) replayQueue (
        .clk(port.clk),
        .we(pushEntry),
        .wa(tailPtr),
        .wv(recordData),
        .ra(headPtr),
        .rv(replayEntryOut)
    );

    // Recovery format
    logic recoveryFromCmStage;
    logic recoveryFromRwStage;

    // Valid information in replay queue
    logic replayEntryValidIn;
    logic replayEntryValidOut;

    logic noValidInst;
    ReplayQueueCountPath validInstCount;
    ReplayQueueCountPath validInstCountNext;

    ReplayQueueIntervalPath intervalIn;
    ReplayQueueIntervalPath nextIntervalIn;
    ReplayQueueIntervalPath intervalCount;
    ReplayQueueIntervalPath nextIntervalCount;

    // Flushed Op detection
    ReplayQueueCountPath canBeFlushedEntryCount;    //FlushedOpが存在している可能性があるエントリの個数
    ActiveListIndexPath flushRangeHeadPtr;  //フラッシュされた命令の範囲のhead
    ActiveListIndexPath flushRangeTailPtr;  //フラッシュされた命令の範囲のtail
    logic flushInt[ INT_ISSUE_WIDTH ];
    logic flushMem[ MEM_ISSUE_WIDTH ];
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    logic flushComplex[ COMPLEX_ISSUE_WIDTH ];
`endif

    // Outputs are pipelined for timing optimization.
    // "replay" signal is in a critical path.
    ReplayQueueEntry replayEntryReg;   // Don't care except valid bits.
    ReplayQueueEntry nextReplayEntry;
    logic replayReg;
    logic nextReplay;

    // State of MSHR
    logic [MEM_ISSUE_WIDTH-1 : 0] mshrNotReady;
    logic [MEM_ISSUE_WIDTH-1 : 0] mshrAddrSubsetMatch;
    logic [MEM_ISSUE_WIDTH-1 : 0] targetMSHRValid;
    MSHR_IndexPath mshrID[MEM_ISSUE_WIDTH];

    logic mshrValid[MSHR_NUM];
    MSHR_Phase mshrPhase[MSHR_NUM]; // MSHR phase.
    DCacheIndexSubsetPath mshrAddrSubset[MSHR_NUM];
    logic mshrMakeMSHRCanBeInvalidByReplayQueue[MSHR_NUM];

`ifndef RSD_SYNTHESIS
    `ifndef RSD_VIVADO_SIMULATION
        // Don't care these values, but avoiding undefined status in Questa.
        initial begin
            replayEntryReg = '0;
        end
    `endif
`endif

    always_comb begin
        recoveryFromRwStage = recovery.toRecoveryPhase && recovery.recoveryFromRwStage;
        recoveryFromCmStage = recovery.toRecoveryPhase && !recovery.recoveryFromRwStage;
    end

    always_ff @ (posedge port.clk) begin
        if (port.rst) begin
            replayEntryReg.intValid <= '0;
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            replayEntryReg.complexValid <= '0;
`endif
            replayEntryReg.memValid <= '0;
            replayReg <= '0;
            intervalIn <= '0;
            intervalCount <= '0;
        end
        else begin
            replayEntryReg <= nextReplayEntry;
            replayReg <= nextReplay;
            intervalIn <= nextIntervalIn;
            intervalCount <= nextIntervalCount;
        end
    end

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            validInstCount <= 0;
        end
        else begin
            validInstCount <= validInstCountNext;
        end
    end

    always_comb begin
        // Count how many valid instruction in replay queue
        noValidInst = (validInstCount == 0) ? TRUE : FALSE;

        validInstCountNext = validInstCount;
        if (pushEntry && replayEntryValidIn) begin
            validInstCountNext++;
        end

        if (popEntry && replayEntryValidOut) begin
            validInstCountNext--;
        end
    end

    always_comb begin
        // Set MSHR state
        for (int i = 0; i < MSHR_NUM; i++) begin
            mshrValid[i] = mshr.mshrValid[i];
            mshrPhase[i] = mshr.mshrPhase[i];
            mshrAddrSubset[i] = mshr.mshrAddrSubset[i];
        end

        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            mshrID[i] = replayEntryOut.memData[i].memOpInfo.mshrID;
        end
    end

    always_comb begin
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            if (port.rst) begin
                mshrNotReady[i] = FALSE;
            end
            else begin
                mshrNotReady[i] = 
                    (mshrPhase[mshrID[i]] < MSHR_PHASE_MISS_WRITE_CACHE_REQUEST) ? TRUE : FALSE;
            end
        end
    end

    always_comb begin
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            if (port.rst) begin
                targetMSHRValid[i] = FALSE;
            end
            else begin
                targetMSHRValid[i] = (mshrValid[mshrID[i]]) ? TRUE : FALSE;
            end
        end
    end

    always_comb begin
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            if (port.rst) begin
                mshrAddrSubsetMatch[i] = FALSE;
            end
            else begin
                mshrAddrSubsetMatch[i] = 
                    (mshrAddrSubset[mshrID[i]] == replayEntryOut.memAddrSubset[i]) ? TRUE : FALSE;
            end
        end
    end

    always_comb begin
        nextIntervalIn = intervalIn;
        if (pushEntry) begin
            nextIntervalIn = '0;
        end
        else if (intervalIn < REPLAY_QUEUE_MAX_INTERVAL) begin
            nextIntervalIn++;
        end
    end

    always_comb begin
        nextIntervalCount = intervalCount;
        if (popEntry) begin
            nextIntervalCount = '0;
        end
        else if (intervalCount < REPLAY_QUEUE_MAX_INTERVAL) begin
            nextIntervalCount++;
        end
    end

    always_comb begin

        // To a write port.
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            recordData.intValid[i] = port.intRecordEntry[i];
            recordData.intData[i] = port.intRecordData[i];
        end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            recordData.complexValid[i] = port.complexRecordEntry[i];
            recordData.complexData[i] = port.complexRecordData[i];
        end
`endif
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            recordData.memValid[i] = port.memRecordEntry[i];
            recordData.memData[i] = port.memRecordData[i];
            recordData.memAddrHit[i] = port.memRecordAddrHit[i];
            recordData.memAddrSubset[i] = port.memRecordAddrSubset[i];
        end
        recordData.replayInterval = intervalIn;


        if (port.rst) begin
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                recordData.intValid[i] = FALSE;
            end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
                recordData.complexValid[i] = FALSE;
            end
`endif
            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                recordData.memValid[i] = FALSE;
            end
            recordData.replayInterval = '0;
        end


        if (port.rst) begin
            replayEntryValidIn = FALSE;
        end
        else begin
            replayEntryValidIn = FALSE;
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                if (recordData.intValid[i]) begin
                    replayEntryValidIn = TRUE;
                end
            end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
                if (recordData.complexValid[i]) begin
                    replayEntryValidIn = TRUE;
                end
            end
`endif
            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                if (recordData.memValid[i]) begin
                    replayEntryValidIn = TRUE;
                end
            end
        end

        if (port.rst) begin
            replayEntryValidOut = FALSE;
        end
        else begin
            replayEntryValidOut = FALSE;
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                if (replayEntryOut.intValid[i]) begin
                    replayEntryValidOut = TRUE;
                end
            end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
                if (replayEntryOut.complexValid[i]) begin
                    replayEntryValidOut = TRUE;
                end
            end
`endif
            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                if (replayEntryOut.memValid[i]) begin
                    replayEntryValidOut = TRUE;
                end
            end
        end


        // To an input of ReplayQueue.
        if (port.rst) begin
            pushEntry = FALSE;
        end
        else if (full) begin
            pushEntry = FALSE;
        end
        else if (~replayEntryValidIn && noValidInst) begin
            // RQに有効な命令が無く，入力も有効ではないときは何もpushしない
            pushEntry = FALSE;
        end
        else begin
            pushEntry = FALSE;

            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                if (recordData.intValid[i]) begin
                    pushEntry = TRUE;
                end
            end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
                if (recordData.complexValid[i]) begin
                    pushEntry = TRUE;
                end
            end
`endif
            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                if (recordData.memValid[i]) begin
                    pushEntry = TRUE;
                end
            end
        end

        // To an output of ReplayQueue
        if (port.rst) begin
            popEntry = FALSE;
        end
        else if (empty) begin
            popEntry = FALSE;
        end
        else if (intervalCount < replayEntryOut.replayInterval) begin
            popEntry = FALSE;
        end
        else if (~replayEntryValidOut) begin
            // RQの先頭命令が無効なら必ずpopする　
            popEntry = TRUE;
        end
        else begin
            popEntry = TRUE;
            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                if (replayEntryOut.memValid[i] &&
                    (replayEntryOut.memData[i].memOpInfo.opType
                        inside { MEM_MOP_TYPE_LOAD }) && // the load is valid,
                    replayEntryOut.memData[i].memOpInfo.hasAllocatedMSHR && // has allocated MSHR entries,
                    mshrNotReady[i] // the corresponding MSHR entry has not receive data yet.
                ) begin
                    popEntry = FALSE;
                end
            end

            // FENCE.I
            if (replayEntryOut.memValid[0] && 
                (replayEntryOut.memData[0].memOpInfo.opType
                        inside { MEM_MOP_TYPE_FENCE }) && 
                replayEntryOut.memData[0].memOpInfo.isFenceI && // the FENCE.I is valid,
                !cacheFlush.cacheFlushComplete // cache flush is not completed yet.
            ) begin
                popEntry = FALSE;
            end

            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                if (replayEntryOut.memValid[i] &&
                    (replayEntryOut.memData[i].memOpInfo.opType
                        inside { MEM_MOP_TYPE_LOAD }) && // the load is valid,
                    replayEntryOut.memAddrHit[i] && // has hit a MSHR entry,
                    targetMSHRValid[i] && // the MSHR entry is valid
                    mshrAddrSubsetMatch[i] && // the MSHR entry still has corresponding request,
                    mshrNotReady[i] // the corresponding MSHR entry has not receive data yet.
                ) begin
                    popEntry = FALSE;
                end
`ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
                else if (
                    replayEntryOut.memValid[i] &&
                    replayEntryOut.memData[i].memOpInfo.opType == MEM_MOP_TYPE_DIV &&
                    mulDivUnit.divBusy[i]
                ) begin
                    popEntry = FALSE;
                end
`endif
            end
            
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin 
                if (replayEntryOut.complexValid[i] && 
                    replayEntryOut.complexData[i].opType == COMPLEX_MOP_TYPE_DIV && 
                    mulDivUnit.divBusy[i]   // Div unit is busy and wait it
                ) begin 
                    // Div interlock (stop issuing div while there is 
                    // any divs in the complex pipeline including replay queue)
                    popEntry = FALSE; 
                end 
            end 
`endif
        end

        // To stall upper stages.
        if (count >= (REPLAY_QUEUE_ENTRY_NUM - ISSUE_QUEUE_MEM_LATENCY)) begin
            almostFull = TRUE;
        end
        else begin
            almostFull = FALSE;
        end


        // To an output register.
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            nextReplayEntry.intValid[i] = popEntry && replayEntryOut.intValid[i];
            nextReplayEntry.intData[i] = replayEntryOut.intData[i];
        end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            nextReplayEntry.complexValid[i] = popEntry && replayEntryOut.complexValid[i];
            nextReplayEntry.complexData[i] = replayEntryOut.complexData[i];
        end
`endif
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            nextReplayEntry.memValid[i] = popEntry && replayEntryOut.memValid[i];
            nextReplayEntry.memData[i] = replayEntryOut.memData[i];
            nextReplayEntry.memAddrHit[i] = replayEntryOut.memAddrHit[i];
            nextReplayEntry.memAddrSubset[i] = replayEntryOut.memAddrSubset[i];
        end

        nextReplayEntry.replayInterval = replayEntryOut.replayInterval;
        nextReplay = (popEntry && replayEntryValidOut) ? TRUE : FALSE;

        // To an issue queue.
        // Flushed op is detected here.
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            flushInt[i] = SelectiveFlushDetector(
                            canBeFlushedEntryCount != 0,
                            flushRangeHeadPtr,
                            flushRangeTailPtr,
                            replayEntryReg.intData[i].activeListPtr
                            );
            port.intReplayEntry[i] = replayEntryReg.intValid[i] && !flushInt[i];
            port.intReplayData[i] = replayEntryReg.intData[i];
        end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            flushComplex[i] = SelectiveFlushDetector(
                                canBeFlushedEntryCount != 0,
                                flushRangeHeadPtr,
                                flushRangeTailPtr,
                                replayEntryReg.complexData[i].activeListPtr
                                );
            port.complexReplayEntry[i] = replayEntryReg.complexValid[i] && !flushComplex[i];
            port.complexReplayData[i] = replayEntryReg.complexData[i];
        end
`endif
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            flushMem[i] = SelectiveFlushDetector(
                            canBeFlushedEntryCount != 0,
                            flushRangeHeadPtr,
                            flushRangeTailPtr,
                            replayEntryReg.memData[i].activeListPtr
                            );
            port.memReplayEntry[i] = replayEntryReg.memValid[i] && !flushMem[i];
            port.memReplayData[i] = replayEntryReg.memData[i];
        end

        // MSHR can be invalid when its allocator load is flushed at ReplayQueue.
        for (int i = 0; i < MSHR_NUM; i++) begin
            mshrMakeMSHRCanBeInvalidByReplayQueue[i] = FALSE;
        end

        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            if (replayEntryReg.memValid[i] && replayEntryReg.memData[i].memOpInfo.hasAllocatedMSHR && flushMem[i]) begin
                mshrMakeMSHRCanBeInvalidByReplayQueue[replayEntryReg.memData[i].memOpInfo.mshrID] = TRUE;
            end
        end

        for (int i = 0; i < MSHR_NUM; i++) begin
            mshr.makeMSHRCanBeInvalidByReplayQueue[i] = mshrMakeMSHRCanBeInvalidByReplayQueue[i];
        end


        // Stall issue and schedule stages
        // when ReplayQueue issues or
        // its #entries exceeds the threshold.
        ctrl.isStageStallUpper = replayReg | almostFull;
        port.replay = replayReg;

    end

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            canBeFlushedEntryCount <= 0;
        end
        else if (recoveryFromRwStage || recoveryFromCmStage) begin
            canBeFlushedEntryCount <= count;
            flushRangeHeadPtr <= recovery.flushRangeHeadPtr;
            flushRangeTailPtr <= recovery.flushRangeTailPtr;
        end
        else if (canBeFlushedEntryCount > 0 && port.replay) begin
            canBeFlushedEntryCount <= canBeFlushedEntryCount - 1;
        end
    end

    always_comb begin
        recovery.replayQueueFlushedOpExist = (canBeFlushedEntryCount != 0);
    end

endmodule : ReplayQueue
