// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Scheduler
//
`include "BasicMacros.sv"

import BasicTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import MicroOpTypes::*;

//
// Track issues ops. Tracked information is used for waking up and releasing entries.
//
module WakeupPipelineRegister(
    WakeupSelectIF.WakeupPipelineRegister port,
    RecoveryManagerIF.WakeupPipelineRegister recovery
);
    `RSD_STATIC_ASSERT(
        ISSUE_QUEUE_INT_LATENCY == 1, 
        "Int latency must be 1."
    );
    // Normally, the latency of INT is 1, so when ISSUE_QUEUE_INT_LATENCY is other than 1, it is not supported.
    // To make ISSUE_QUEUE_INT_LATENCY larger than 1, the following part must be changed. (Refer to the implementation of COMPLEX or MEM)
    // - update of intPipeReg.
    // - port.wakeup, port.wakeupVector 
    // - port.releaseEntry

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

`ifdef RSD_MARCH_FP_PIPE
    WakeupPipeReg fpPipeReg[ FP_ISSUE_WIDTH ][ ISSUE_QUEUE_FP_LATENCY ];
    WakeupPipeReg nextFPPipeReg[ FP_ISSUE_WIDTH ];
    logic [$clog2(ISSUE_QUEUE_FP_LATENCY):0] canBeFlushedRegCountFP;    //FlushedOpが存在している可能性があるFPパイプラインレジスタの段数
    logic flushFP[ FP_ISSUE_WIDTH ];
    IssueQueueIndexPath fpSelectedPtr[ FP_ISSUE_WIDTH ];
`endif

    // Flushed Op detection
    logic [$clog2(ISSUE_QUEUE_INT_LATENCY):0] canBeFlushedRegCountInt;    //FlushedOpが存在している可能性があるIntパイプラインレジスタの段数
    logic [$clog2(ISSUE_QUEUE_MEM_LATENCY):0] canBeFlushedRegCountMem;    //FlushedOpが存在している可能性があるMemパイプラインレジスタの段数
    ActiveListIndexPath flushRangeHeadPtr;  //フラッシュされた命令の範囲のhead
    ActiveListIndexPath flushRangeTailPtr;  //フラッシュされた命令の範囲のtail
    logic flushAllInsns;
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

`ifdef RSD_MARCH_FP_PIPE
        for( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            for( int j = 0; j < ISSUE_QUEUE_FP_LATENCY; j++ ) begin
                fpPipeReg[i][j].ptr <= '1;
                fpPipeReg[i][j].depVector <= '1;
                fpPipeReg[i][j].activeListPtr <= '1;
            end
        end
`endif
    end
`endif

    always_ff @( posedge port.clk ) begin
        if( port.rst ||(recovery.toRecoveryPhase && !recovery.recoveryFromRwStage) ) begin
            // Upon reset or recovery from the commit stage, initialize the wakeup pipeline register.
            // Set the valid flag to FALSE and the depVector to '0 to prevent incorrect wakeups of unrelated registers/instructions.
            for( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
                for( int j = 0; j < ISSUE_QUEUE_INT_LATENCY; j++ ) begin
                    intPipeReg[i][j].valid <= FALSE;
                    intPipeReg[i][j].depVector <= '0;
                end
            end

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
                for( int j = 0; j < ISSUE_QUEUE_COMPLEX_LATENCY; j++ ) begin
                    complexPipeReg[i][j].valid <= FALSE;
                    complexPipeReg[i][j].depVector <= '0;
                end
            end
`endif

            for( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
                for( int j = 0; j < ISSUE_QUEUE_MEM_LATENCY; j++ ) begin
                    memPipeReg[i][j].valid <= FALSE;
                    memPipeReg[i][j].depVector <= '0;
                end
            end

`ifdef RSD_MARCH_FP_PIPE
            for( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
                for( int j = 0; j < ISSUE_QUEUE_FP_LATENCY; j++ ) begin
                    fpPipeReg[i][j].valid <= FALSE;
                    fpPipeReg[i][j].depVector <= '0;
                end
            end
`endif
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

`ifdef RSD_MARCH_FP_PIPE
            for( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
                for( int j = 1; j < ISSUE_QUEUE_FP_LATENCY; j++ ) begin
                    fpPipeReg[i][j-1] <= fpPipeReg[i][j];
                end
                fpPipeReg[i][ ISSUE_QUEUE_FP_LATENCY-1 ] <= nextFPPipeReg[i];
            end
`endif
        end
        else begin
            // When the scheduler is stalled, only the 1st stage ([LATENCY-1]) of PipeReg needs to
            // be stalled so that the select result of that cycle is not reflected.
            // The 2nd and subsequent stages continue to flow regardless of stall.
            // Therefore the 2nd stage ([LATENCY-2]) must be filled with bubbles when the 1st stage is stalled.
            // IntPipe has only one stage by default, so such bubbles are unnecessary for IntPipe.
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
                for( int j = 1; j < ISSUE_QUEUE_COMPLEX_LATENCY-1; j++ ) begin
                    complexPipeReg[i][j-1] <= complexPipeReg[i][j];
                end
                complexPipeReg[i][ ISSUE_QUEUE_COMPLEX_LATENCY-2 ].valid <= FALSE;
                complexPipeReg[i][ ISSUE_QUEUE_COMPLEX_LATENCY-2 ].depVector <= '0;
            end
`endif
            for( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
                for( int j = 1; j < ISSUE_QUEUE_MEM_LATENCY-1; j++ ) begin
                    memPipeReg[i][j-1] <= memPipeReg[i][j];
                end
                memPipeReg[i][ ISSUE_QUEUE_MEM_LATENCY-2 ].valid <= FALSE;
                memPipeReg[i][ ISSUE_QUEUE_MEM_LATENCY-2 ].depVector <= '0;
            end
`ifdef RSD_MARCH_FP_PIPE
            for( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
                for( int j = 1; j < ISSUE_QUEUE_FP_LATENCY-1; j++ ) begin
                    fpPipeReg[i][j-1] <= fpPipeReg[i][j];
                end
                fpPipeReg[i][ ISSUE_QUEUE_FP_LATENCY-2 ].valid <= FALSE;
                fpPipeReg[i][ ISSUE_QUEUE_FP_LATENCY-2 ].depVector <= '0;
            end
`endif
        end
    end



    always_comb begin
        // A bit vector indicating whether each IQ entry is flushed.
        // This is used to deassert the wakeup signal of instructions that are selected but flushed at the same time.
        flushIQ_Entry = recovery.flushIQ_Entry;
        //
        // Register selected ops.
        //
        for (int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            // Input of PipeReg (Selected Data)
            intSelectedPtr[i] = port.selectedPtr[i];
            nextIntPipeReg[i].valid = port.selected[i] && !flushIQ_Entry[intSelectedPtr[i]];
            nextIntPipeReg[i].ptr = port.selectedPtr[i];
            nextIntPipeReg[i].depVector = port.selectedVector[i] & ~flushIQ_Entry;
            nextIntPipeReg[i].activeListPtr = recovery.selectedActiveListPtr[i];
        end

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            complexSelectedPtr[i] = port.selectedPtr[(i+INT_ISSUE_WIDTH)];
            nextComplexPipeReg[i].valid = port.selected[(i+INT_ISSUE_WIDTH)] && !flushIQ_Entry[complexSelectedPtr[i]];
            nextComplexPipeReg[i].ptr = port.selectedPtr[(i+INT_ISSUE_WIDTH)];
            nextComplexPipeReg[i].depVector = port.selectedVector[(i+INT_ISSUE_WIDTH)] & ~flushIQ_Entry;
            nextComplexPipeReg[i].activeListPtr = recovery.selectedActiveListPtr[(i+INT_ISSUE_WIDTH)];
        end
`endif

        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            memSelectedPtr[i] = port.selectedPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)];
            nextMemPipeReg[i].valid = port.selected[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] && !flushIQ_Entry[memSelectedPtr[i]];
            nextMemPipeReg[i].ptr = port.selectedPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)];
            nextMemPipeReg[i].depVector = port.selectedVector[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] & ~flushIQ_Entry;
            nextMemPipeReg[i].activeListPtr = recovery.selectedActiveListPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)];
        end

`ifdef RSD_MARCH_FP_PIPE
        for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin
            fpSelectedPtr[i] = port.selectedPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)];
            nextFPPipeReg[i].valid = port.selected[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)] && !flushIQ_Entry[fpSelectedPtr[i]];
            nextFPPipeReg[i].ptr = port.selectedPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)];
            nextFPPipeReg[i].depVector = port.selectedVector[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)] & ~flushIQ_Entry;
            nextFPPipeReg[i].activeListPtr = recovery.selectedActiveListPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)];
        end
`endif

        //
        // Exit from the pipeline registers and now wakeup consumers.
        //
        for (int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            // Output of PipeReg (Wakeup Data)
            // Now, WAKEUP_WIDTH == ISSUE_WIDTH
            flushInt[i] = SelectiveFlushDetector(
                            canBeFlushedRegCountInt != 0,
                            flushRangeHeadPtr,
                            flushRangeTailPtr,
                            flushAllInsns,
                            intPipeReg[i][0].activeListPtr
                            );
            port.wakeup[i] = intPipeReg[i][0].valid && !flushInt[i] && !port.stall;
            port.wakeupPtr[i] = intPipeReg[i][0].ptr;
            port.wakeupVector[i] = !port.stall ? intPipeReg[i][0].depVector : '0;
        end

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            flushComplex[i] = SelectiveFlushDetector(
                            canBeFlushedRegCountComplex != 0,
                            flushRangeHeadPtr,
                            flushRangeTailPtr,
                            flushAllInsns,
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
                            flushAllInsns,
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
                            flushAllInsns,
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

`ifdef RSD_MARCH_FP_PIPE
        for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin
            flushFP[i] = SelectiveFlushDetector(
                            canBeFlushedRegCountFP != 0,
                            flushRangeHeadPtr,
                            flushRangeTailPtr,
                            flushAllInsns,
                            fpPipeReg[i][0].activeListPtr
                            );
            port.wakeup[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+LOAD_ISSUE_WIDTH)] = fpPipeReg[i][0].valid && !flushFP[i];
            port.wakeupPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+LOAD_ISSUE_WIDTH)] = fpPipeReg[i][0].ptr;
            port.wakeupVector[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+LOAD_ISSUE_WIDTH)] = fpPipeReg[i][0].depVector;
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
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            port.releaseEntry[(i+INT_ISSUE_WIDTH)] = complexPipeReg[i][0].valid;
            port.releasePtr[(i+INT_ISSUE_WIDTH)] = complexPipeReg[i][0].ptr;
        end
`endif
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            port.releaseEntry[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].valid;
            port.releasePtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].ptr;
        end
`ifdef RSD_MARCH_FP_PIPE
        for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin
            port.releaseEntry[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)] = fpPipeReg[i][0].valid;
            port.releasePtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)] = fpPipeReg[i][0].ptr;
        end
`endif
    end

    always_ff @( posedge port.clk ) begin
        if(port.rst) begin
            canBeFlushedRegCountInt <= 0;
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            canBeFlushedRegCountComplex <= 0;
`endif
            canBeFlushedRegCountMem <= 0;
`ifdef RSD_MARCH_FP_PIPE
            canBeFlushedRegCountFP <= 0;
`endif
            flushRangeHeadPtr <= 0;
            flushRangeTailPtr <= 0;
            flushAllInsns <= FALSE;
        end
        else if(recovery.toRecoveryPhase && recovery.recoveryFromRwStage) begin
            canBeFlushedRegCountInt <= ISSUE_QUEUE_INT_LATENCY;
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            canBeFlushedRegCountComplex <= ISSUE_QUEUE_COMPLEX_LATENCY;
`endif
            canBeFlushedRegCountMem <= ISSUE_QUEUE_MEM_LATENCY;
`ifdef RSD_MARCH_FP_PIPE
            canBeFlushedRegCountFP <= ISSUE_QUEUE_FP_LATENCY;
`endif
            flushRangeHeadPtr <= recovery.flushRangeHeadPtr;
            flushRangeTailPtr <= recovery.flushRangeTailPtr;
            flushAllInsns <= recovery.flushAllInsns;
        end
        else begin
            if(canBeFlushedRegCountInt == ISSUE_QUEUE_INT_LATENCY) begin
                if(!port.stall) begin
                    canBeFlushedRegCountInt <= canBeFlushedRegCountInt-1;
                end
            end
            else if (canBeFlushedRegCountInt > 0) begin
                canBeFlushedRegCountInt <= canBeFlushedRegCountInt-1;
            end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            if(canBeFlushedRegCountComplex == ISSUE_QUEUE_COMPLEX_LATENCY) begin
                if(!port.stall) begin
                    canBeFlushedRegCountComplex <= canBeFlushedRegCountComplex-1;
                end
            end
            else if (canBeFlushedRegCountComplex > 0) begin
                canBeFlushedRegCountComplex <= canBeFlushedRegCountComplex-1;
            end
`endif
            if(canBeFlushedRegCountMem == ISSUE_QUEUE_MEM_LATENCY) begin
                if(!port.stall) begin
                    canBeFlushedRegCountMem <= canBeFlushedRegCountMem-1;
                end
            end
            else if (canBeFlushedRegCountMem > 0) begin
                canBeFlushedRegCountMem <= canBeFlushedRegCountMem-1;
            end
`ifdef RSD_MARCH_FP_PIPE
            if(canBeFlushedRegCountFP == ISSUE_QUEUE_FP_LATENCY) begin
                if(!port.stall) begin
                    canBeFlushedRegCountFP <= canBeFlushedRegCountFP-1;
                end
            end
            else if (canBeFlushedRegCountFP > 0) begin
                canBeFlushedRegCountFP <= canBeFlushedRegCountFP-1;
            end
`endif
        end
    end

    always_comb begin
        recovery.wakeupPipelineRegFlushedOpExist = 
            (canBeFlushedRegCountInt != 0) || 
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            (canBeFlushedRegCountComplex != 0) || 
`endif
`ifdef RSD_MARCH_FP_PIPE
            (canBeFlushedRegCountFP != 0) || 
`endif
            (canBeFlushedRegCountMem != 0);
    end

endmodule : WakeupPipelineRegister



