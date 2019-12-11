// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Scheduler
//

import BasicTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import MicroOpTypes::*;

//
// Track issues ops. Tracked information is used for waking up and releasing entries.
//
module WakeupPipelineRegister(
    WakeupSelectIF.WakeupPipelineRegister port,
    RecoveryManagerIF.WakeupPipelineRegister recovery
);

    // Pipeline registers
    typedef struct packed
    {
        logic valid;              // Valid flag.
        IssueQueueIndexPath ptr;  // A pointer to a selected entry.
        IssueQueueOneHotPath depVector;    // A producer vector for a producer matrix.
        ActiveListIndexPath activeListPtr;     // A pointer of active list for flush
    } WakeupPipeReg;

    WakeupPipeReg intPipeReg[ INT_ISSUE_WIDTH ][ ISSUE_QUEUE_INT_LATENCY ];
    WakeupPipeReg memPipeReg[ MEM_ISSUE_WIDTH ][ ISSUE_QUEUE_MEM_LATENCY ];
    WakeupPipeReg nextIntPipeReg[ INT_ISSUE_WIDTH ];
    WakeupPipeReg nextMemPipeReg[ MEM_ISSUE_WIDTH ];

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    WakeupPipeReg complexPipeReg[ COMPLEX_ISSUE_WIDTH ][ ISSUE_QUEUE_COMPLEX_LATENCY ];
    WakeupPipeReg nextComplexPipeReg[ COMPLEX_ISSUE_WIDTH ];
    logic [$clog2(ISSUE_QUEUE_COMPLEX_LATENCY):0] canBeFlushedRegCountComplex;    //FlushedOpが存在している可能性があるComplexパイプラインレジスタの段数
    logic flushComplex[ COMPLEX_ISSUE_WIDTH ];
    IssueQueueIndexPath complexSelectedPtr[ COMPLEX_ISSUE_WIDTH ];
`endif

    // Flushed Op detection
    logic [$clog2(ISSUE_QUEUE_INT_LATENCY):0] canBeFlushedRegCountInt;    //FlushedOpが存在している可能性があるIntパイプラインレジスタの段数
    logic [$clog2(ISSUE_QUEUE_MEM_LATENCY):0] canBeFlushedRegCountMem;    //FlushedOpが存在している可能性があるMemパイプラインレジスタの段数
    ActiveListIndexPath flushRangeHeadPtr;  //フラッシュされた命令の範囲のhead
    ActiveListIndexPath flushRangeTailPtr;  //フラッシュされた命令の範囲のtail
    logic flushInt[ INT_ISSUE_WIDTH ];
    logic flushMem[ LOAD_ISSUE_WIDTH ];
    IssueQueueIndexPath intSelectedPtr[ INT_ISSUE_WIDTH ];
    IssueQueueIndexPath memSelectedPtr[ MEM_ISSUE_WIDTH ];
    IssueQueueOneHotPath flushIQ_Entry;

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            for( int j = 0; j < ISSUE_QUEUE_INT_LATENCY; j++ ) begin
                intPipeReg[i][j].ptr <= '1;
                intPipeReg[i][j].depVector <= '1;
                intPipeReg[i][j].activeListPtr <= '1;
            end
        end

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            for( int j = 0; j < ISSUE_QUEUE_COMPLEX_LATENCY; j++ ) begin
                complexPipeReg[i][j].ptr <= '1;
                complexPipeReg[i][j].depVector <= '1;
                complexPipeReg[i][j].activeListPtr <= '1;
            end
        end
`endif

        for( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            for( int j = 0; j < ISSUE_QUEUE_MEM_LATENCY; j++ ) begin
                memPipeReg[i][j].ptr <= '1;
                memPipeReg[i][j].depVector <= '1;
                memPipeReg[i][j].activeListPtr <= '1;
            end
        end
    end
`endif

    always_ff @( posedge port.clk ) begin
        if( port.rst ||(recovery.toRecoveryPhase && !recovery.recoveryFromRwStage) ) begin
            // パイプラインレジスタの初期化
            // Don't care except valid bits.
            for( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
                for( int j = 0; j < ISSUE_QUEUE_INT_LATENCY; j++ ) begin
                    intPipeReg[i][j].valid <= FALSE;
                end
            end

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
                for( int j = 0; j < ISSUE_QUEUE_COMPLEX_LATENCY; j++ ) begin
                    complexPipeReg[i][j].valid <= FALSE;
                end
            end
`endif

            for( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
                for( int j = 0; j < ISSUE_QUEUE_MEM_LATENCY; j++ ) begin
                    memPipeReg[i][j].valid <= FALSE;
                end
            end
        end
        else if ( !port.stall ) begin
            // 通常動作
            for( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
                for( int j = 1; j < ISSUE_QUEUE_INT_LATENCY; j++ ) begin
                    intPipeReg[i][j-1] <= intPipeReg[i][j];
                end
                intPipeReg[i][ ISSUE_QUEUE_INT_LATENCY-1 ] <= nextIntPipeReg[i];
            end

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
                for( int j = 1; j < ISSUE_QUEUE_COMPLEX_LATENCY; j++ ) begin
                    complexPipeReg[i][j-1] <= complexPipeReg[i][j];
                end
                complexPipeReg[i][ ISSUE_QUEUE_COMPLEX_LATENCY-1 ] <= nextComplexPipeReg[i];
            end
`endif

            for( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
                for( int j = 1; j < ISSUE_QUEUE_MEM_LATENCY; j++ ) begin
                    memPipeReg[i][j-1] <= memPipeReg[i][j];
                end
                memPipeReg[i][ ISSUE_QUEUE_MEM_LATENCY-1 ] <= nextMemPipeReg[i];
            end
        end
    end



    always_comb begin
        flushIQ_Entry = recovery.flushIQ_Entry;
        //
        // Register selected ops.
        //
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            // Input of PipeReg (Selected Data)
            intSelectedPtr[i] = port.selectedPtr[i];
            nextIntPipeReg[i].valid = port.selected[i] && !flushIQ_Entry[intSelectedPtr[i]];
            nextIntPipeReg[i].ptr = port.selectedPtr[i];
            nextIntPipeReg[i].depVector = port.selectedVector[i];
            nextIntPipeReg[i].activeListPtr = recovery.selectedActiveListPtr[i];
        end

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            complexSelectedPtr[i] = port.selectedPtr[(i+INT_ISSUE_WIDTH)];
            nextComplexPipeReg[i].valid = port.selected[(i+INT_ISSUE_WIDTH)] && !flushIQ_Entry[complexSelectedPtr[i]];
            nextComplexPipeReg[i].ptr = port.selectedPtr[(i+INT_ISSUE_WIDTH)];
            nextComplexPipeReg[i].depVector = port.selectedVector[(i+INT_ISSUE_WIDTH)];
            nextComplexPipeReg[i].activeListPtr = recovery.selectedActiveListPtr[(i+INT_ISSUE_WIDTH)];
        end
`endif

        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            memSelectedPtr[i] = port.selectedPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)];
            nextMemPipeReg[i].valid = port.selected[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] && !flushIQ_Entry[memSelectedPtr[i]];
            nextMemPipeReg[i].ptr = port.selectedPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)];
            nextMemPipeReg[i].depVector = port.selectedVector[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)];
            nextMemPipeReg[i].activeListPtr = recovery.selectedActiveListPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)];
        end

        //
        // Exit from the pipeline registers and now wakeup consumers.
        //
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            // Output of PipeReg (Wakeup Data)
            // Now, WAKEUP_WIDTH == ISSUE_WIDTH
            flushInt[i] = SelectiveFlushDetector(
                            canBeFlushedRegCountInt != 0,
                            flushRangeHeadPtr,
                            flushRangeTailPtr,
                            intPipeReg[i][0].activeListPtr
                            );
            port.wakeup[i] = intPipeReg[i][0].valid && !flushInt[i];
            port.wakeupPtr[i] = intPipeReg[i][0].ptr;
            port.wakeupVector[i] = intPipeReg[i][0].depVector;
        end

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            flushComplex[i] = SelectiveFlushDetector(
                            canBeFlushedRegCountComplex != 0,
                            flushRangeHeadPtr,
                            flushRangeTailPtr,
                            complexPipeReg[i][0].activeListPtr
                            );
            port.wakeup[(i+INT_ISSUE_WIDTH)] = complexPipeReg[i][0].valid && !flushComplex[i];
            port.wakeupPtr[(i+INT_ISSUE_WIDTH)] = complexPipeReg[i][0].ptr;
            port.wakeupVector[(i+INT_ISSUE_WIDTH)] = complexPipeReg[i][0].depVector;
        end
`endif

`ifdef RSD_MARCH_UNIFIED_LDST_MEM_PIPE
        // Store ports do not wake up consumers, thus LOAD_ISSUE_WIDTH is used.
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            flushMem[i] = SelectiveFlushDetector(
                            canBeFlushedRegCountMem != 0,
                            flushRangeHeadPtr,
                            flushRangeTailPtr,
                            memPipeReg[i][0].activeListPtr
                          );
            port.wakeup[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].valid && !flushMem[i];
            port.wakeupPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].ptr;
            port.wakeupVector[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].depVector;
        end

        // Wake up an instruction that depends on the store
        for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
            // Not need to assert flushMem because store dependent is not related on register
            port.wakeupPtr[i+WAKEUP_WIDTH] = memPipeReg[i][0].ptr;
            port.wakeupVector[i+WAKEUP_WIDTH] = memPipeReg[i][0].depVector;
        end
`else
        // Store ports do not wake up consumers, thus LOAD_ISSUE_WIDTH is used.
        for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            flushMem[i] = SelectiveFlushDetector(
                            canBeFlushedRegCountMem != 0,
                            flushRangeHeadPtr,
                            flushRangeTailPtr,
                            memPipeReg[i][0].activeListPtr
                            );
            port.wakeup[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].valid && !flushMem[i];
            port.wakeupPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].ptr;
            port.wakeupVector[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].depVector;
        end
        // Wake up an instruction that depends on the store
        for (int i = 0; i < MEM_ISSUE_WIDTH - LOAD_ISSUE_WIDTH; i++) begin
            // Not need to assert flushMem because store dependent is not related on register
            port.wakeupPtr[i+WAKEUP_WIDTH] = memPipeReg[i+LOAD_ISSUE_WIDTH][0].ptr;
            port.wakeupVector[i+WAKEUP_WIDTH] = memPipeReg[i+LOAD_ISSUE_WIDTH][0].depVector;
        end
`endif
    end

    // To an issue queue.
    // Flushed op is detected here.
    always_comb begin
        //
        // Release issue queue entries.
        // Entries can be released after they wake up consumers.
        //
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            port.releaseEntry[i] = intPipeReg[i][0].valid && !port.stall;
            port.releasePtr[i] = intPipeReg[i][0].ptr;
        end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            port.releaseEntry[(i+INT_ISSUE_WIDTH)] = complexPipeReg[i][0].valid && !port.stall;
            port.releasePtr[(i+INT_ISSUE_WIDTH)] = complexPipeReg[i][0].ptr;
        end
`endif
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            port.releaseEntry[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].valid && !port.stall;
            port.releasePtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].ptr;
        end
    end

    always_ff @( posedge port.clk ) begin
        if(port.rst) begin
            canBeFlushedRegCountInt <= 0;
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            canBeFlushedRegCountComplex <= 0;
`endif
            canBeFlushedRegCountMem <= 0;
            flushRangeHeadPtr <= 0;
            flushRangeTailPtr <= 0;
        end
        else if(recovery.toRecoveryPhase && recovery.recoveryFromRwStage) begin
            canBeFlushedRegCountInt <= ISSUE_QUEUE_INT_LATENCY;
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            canBeFlushedRegCountComplex <= ISSUE_QUEUE_COMPLEX_LATENCY;
`endif
            canBeFlushedRegCountMem <= ISSUE_QUEUE_MEM_LATENCY;
            flushRangeHeadPtr <= recovery.flushRangeHeadPtr;
            flushRangeTailPtr <= recovery.flushRangeTailPtr;
        end
        else begin
            if(canBeFlushedRegCountInt>0 && !port.stall) begin
                canBeFlushedRegCountInt <= canBeFlushedRegCountInt-1;
            end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            if(canBeFlushedRegCountComplex>0 && !port.stall) begin
                canBeFlushedRegCountComplex <= canBeFlushedRegCountComplex-1;
            end
`endif
            if(canBeFlushedRegCountMem>0 && !port.stall) begin
                canBeFlushedRegCountMem <= canBeFlushedRegCountMem-1;
            end
        end
    end

    always_comb begin
        recovery.wakeupPipelineRegFlushedOpExist = 
            (canBeFlushedRegCountInt != 0) || 
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            (canBeFlushedRegCountComplex != 0) || 
`endif
            (canBeFlushedRegCountMem != 0);
    end

endmodule : WakeupPipelineRegister



