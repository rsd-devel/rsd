// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Schedule
//

import BasicTypes::*;
import SchedulerTypes::*;
import MicroOpTypes::*;

module Scheduler(
    SchedulerIF.Scheduler port,
    WakeupSelectIF.Scheduler wakeupSelect,
    RecoveryManagerIF.Scheduler recovery,
    MulDivUnitIF.Scheduler mulDivUnit,
    FPDivSqrtUnitIF.Scheduler fpDivSqrtUnit,
    DebugIF.Scheduler debug
);

    // A flag that indicates a not-issued state.
    // This flag contains the validness of each entry.
    logic [ISSUE_QUEUE_ENTRY_NUM-1:0] notIssued;

    // The type of an op in each entry.
    logic [ISSUE_QUEUE_ENTRY_NUM-1:0] isInt;
    logic [ISSUE_QUEUE_ENTRY_NUM-1:0] isComplex;
    logic [ISSUE_QUEUE_ENTRY_NUM-1:0] isDiv;
    logic [ISSUE_QUEUE_ENTRY_NUM-1:0] isLoad;
    logic [ISSUE_QUEUE_ENTRY_NUM-1:0] isStore;
`ifdef RSD_MARCH_FP_PIPE
    logic [ISSUE_QUEUE_ENTRY_NUM-1:0] isFP;
    logic [ISSUE_QUEUE_ENTRY_NUM-1:0] isFPDivSqrt;
`endif

    IssueQueueOneHotPath flushIQ_Entry;

    IssueQueueOneHotPath selectedVector;

    logic dispatchStore[DISPATCH_WIDTH];
    logic dispatchLoad[DISPATCH_WIDTH];
    logic canIssueDiv;
`ifdef RSD_MARCH_FP_PIPE
    logic canIssueFPDivSqrt;
`endif

`ifndef RSD_SYNTHESIS
    `ifndef RSD_VIVADO_SIMULATION
        // Don't care these values, but avoiding undefined status in Questa.
        initial begin
            isInt = '0;
            isComplex = '0;
            isDiv = '0;
            isLoad = '0;
            isStore = '0;
`ifdef RSD_MARCH_FP_PIPE
            isFP = '0;
            isFPDivSqrt = '0;
`endif
        end
    `endif
`endif

    always_ff @(posedge port.clk) begin
        if(port.rst) begin
            // Reset or recovery is necessary only for notIssued flags.
            for(int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++) begin
                notIssued[i] <= FALSE;
            end
        end
        else begin

            // Dispatch
            for (int i = 0; i < DISPATCH_WIDTH; i++) begin
                if( port.write[i] ) begin
                    notIssued[ port.writePtr[i] ] <= TRUE;

                    if (port.writeSchedulerData[i].opType == MOP_TYPE_MEM) begin
                        if (port.writeSchedulerData[i].opSubType.memType == MEM_MOP_TYPE_STORE) begin
                            // This port cannot access the data cache.
                            isLoad[ port.writePtr[i] ] <= FALSE;
                            isStore[ port.writePtr[i] ] <= TRUE;
                            isComplex[ port.writePtr[i] ] <= FALSE;
                            isInt[ port.writePtr[i] ] <= FALSE;
                            isDiv[ port.writePtr[i] ] <= FALSE;
`ifdef RSD_MARCH_FP_PIPE
                            isFP[ port.writePtr[i] ] <= FALSE;
                            isFPDivSqrt[ port.writePtr[i] ] <= FALSE;
`endif
                        end
                        else begin
                            `ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
                                isComplex[ port.writePtr[i] ] <= 
                                    port.writeSchedulerData[i].opSubType.memType inside {
                                        MEM_MOP_TYPE_MUL, MEM_MOP_TYPE_DIV
                                    };
                                isDiv[ port.writePtr[i] ] <= 
                                    port.writeSchedulerData[i].opSubType.memType inside {
                                        MEM_MOP_TYPE_DIV
                                    };
                                isLoad[ port.writePtr[i] ] <= 
                                    !(port.writeSchedulerData[i].opSubType.memType inside {
                                        MEM_MOP_TYPE_MUL, MEM_MOP_TYPE_DIV
                                    });
                            `else
                                isDiv[ port.writePtr[i] ] <= FALSE;
                                isComplex[ port.writePtr[i] ] <= FALSE;
                                isLoad[ port.writePtr[i] ] <= TRUE;
                            `endif
                            isStore[ port.writePtr[i] ] <= FALSE;
                            isInt[ port.writePtr[i] ] <= FALSE;
`ifdef RSD_MARCH_FP_PIPE
                            isFP[ port.writePtr[i] ] <= FALSE;
                            isFPDivSqrt[ port.writePtr[i] ] <= FALSE;
`endif
                        end
                    end
                    else if (port.writeSchedulerData[i].opType == MOP_TYPE_COMPLEX) begin
                        if (port.writeSchedulerData[i].opSubType.complexType ==
                            COMPLEX_MOP_TYPE_DIV) begin
                            isLoad[ port.writePtr[i] ] <= FALSE;
                            isStore[ port.writePtr[i] ] <= FALSE;
                            isComplex[ port.writePtr[i] ] <= TRUE;
                            isInt[ port.writePtr[i] ] <= FALSE;
                            isDiv[ port.writePtr[i] ] <= TRUE;
`ifdef RSD_MARCH_FP_PIPE
                            isFP[ port.writePtr[i] ] <= FALSE;
                            isFPDivSqrt[ port.writePtr[i] ] <= FALSE;
`endif
                        end
                        else begin
                            isLoad[ port.writePtr[i] ] <= FALSE;
                            isStore[ port.writePtr[i] ] <= FALSE;
                            isComplex[ port.writePtr[i] ] <= TRUE;
                            isInt[ port.writePtr[i] ] <= FALSE;
                            isDiv[ port.writePtr[i] ] <= FALSE;
`ifdef RSD_MARCH_FP_PIPE
                            isFP[ port.writePtr[i] ] <= FALSE;
                            isFPDivSqrt[ port.writePtr[i] ] <= FALSE;
`endif
                        end
                    end
`ifdef RSD_MARCH_FP_PIPE
                    else if (port.writeSchedulerData[i].opType == MOP_TYPE_FP) begin
                        if (port.writeSchedulerData[i].opSubType.complexType inside {FP_MOP_TYPE_DIV, FP_MOP_TYPE_SQRT}) begin
                            isLoad[ port.writePtr[i] ] <= FALSE;
                            isStore[ port.writePtr[i] ] <= FALSE;
                            isComplex[ port.writePtr[i] ] <= FALSE;
                            isInt[ port.writePtr[i] ] <= FALSE;
                            isDiv[ port.writePtr[i] ] <= FALSE;
                            isFP[ port.writePtr[i] ] <= TRUE;
                            isFPDivSqrt[ port.writePtr[i] ] <= TRUE;
                        end
                        else begin
                            isLoad[ port.writePtr[i] ] <= FALSE;
                            isStore[ port.writePtr[i] ] <= FALSE;
                            isComplex[ port.writePtr[i] ] <= FALSE;
                            isInt[ port.writePtr[i] ] <= FALSE;
                            isDiv[ port.writePtr[i] ] <= FALSE;
                            isFP[ port.writePtr[i] ] <= TRUE;
                            isFPDivSqrt[ port.writePtr[i] ] <= FALSE;
                        end
                    end
`endif
                    else begin
                        isLoad[ port.writePtr[i] ] <= FALSE;
                        isStore[ port.writePtr[i] ] <= FALSE;
                        isComplex[ port.writePtr[i] ] <= FALSE;
                        isInt[ port.writePtr[i] ] <= TRUE;
                        isDiv[ port.writePtr[i] ] <= FALSE;
`ifdef RSD_MARCH_FP_PIPE
                        isFP[ port.writePtr[i] ] <= FALSE;
                        isFPDivSqrt[ port.writePtr[i] ] <= FALSE;
`endif
                    end
                end
            end

            // Select & issue & flush at recovery
            for (int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++) begin
                if (selectedVector[i] || flushIQ_Entry[i]) begin
                    notIssued[i] <= FALSE;
                end
            end
        end
    end
    


    always_comb begin

        // Generate ld/st inst dispatch information for making store bit vector at producer.
        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
            if ( port.write[i] ) begin
                if (port.writeSchedulerData[i].opType == MOP_TYPE_MEM) begin
                    if (port.writeSchedulerData[i].opSubType.memType == MEM_MOP_TYPE_STORE) begin
                        // Dispatch store
                        dispatchStore[i] = TRUE;
                        dispatchLoad[i] = FALSE;
                    end
                    else begin
                        // Dispatch load
                        dispatchStore[i] = FALSE;
                        dispatchLoad[i] = TRUE;
                    end
                end
                else begin
                    // Not dispatch ld/st inst.
                    dispatchStore[i] = FALSE;
                    dispatchLoad[i] = FALSE;
                end
            end
            else begin
                // Not dispatch inst.
                dispatchStore[i] = FALSE;
                dispatchLoad[i] = FALSE;
            end
        end

        // Connect dispatch/IQ info to IF
        wakeupSelect.dispatchStore = dispatchStore;
        wakeupSelect.dispatchLoad = dispatchLoad;
        wakeupSelect.notIssued = notIssued;

        // Controll logic
        wakeupSelect.stall = port.stall;

        // Dispatch
        wakeupSelect.write = port.write;
        wakeupSelect.writePtr = port.writePtr;

        wakeupSelect.memDependencyPred = port.memDependencyPred;

        flushIQ_Entry = recovery.flushIQ_Entry;
        recovery.notIssued = notIssued;

        for ( int i = 0; i < DISPATCH_WIDTH; i++ ) begin
            // wakeupSelect.writeSrcTag
            wakeupSelect.writeSrcTag[i].regTag[0].valid = port.writeSchedulerData[i].srcRegValidA;
            wakeupSelect.writeSrcTag[i].regTag[1].valid = port.writeSchedulerData[i].srcRegValidB;
`ifdef RSD_MARCH_FP_PIPE
            wakeupSelect.writeSrcTag[i].regTag[2].valid = port.writeSchedulerData[i].srcRegValidC;
`endif
            wakeupSelect.writeSrcTag[i].regTag[0].num = port.writeSchedulerData[i].opSrc.phySrcRegNumA;
            wakeupSelect.writeSrcTag[i].regTag[1].num = port.writeSchedulerData[i].opSrc.phySrcRegNumB;
`ifdef RSD_MARCH_FP_PIPE
            wakeupSelect.writeSrcTag[i].regTag[2].num = port.writeSchedulerData[i].opSrc.phySrcRegNumC;
`endif

            // wakeupSelect.writeSrcTag
            wakeupSelect.writeDstTag[i].regTag.valid = port.writeSchedulerData[i].opDst.writeReg;
            wakeupSelect.writeDstTag[i].regTag.num = port.writeSchedulerData[i].opDst.phyDstRegNum;

            // Source pointers to a matrix.
            wakeupSelect.writeSrcTag[i].regPtr[0].valid = port.writeSchedulerData[i].srcRegValidA;
            wakeupSelect.writeSrcTag[i].regPtr[1].valid = port.writeSchedulerData[i].srcRegValidB;
`ifdef RSD_MARCH_FP_PIPE
            wakeupSelect.writeSrcTag[i].regPtr[2].valid = port.writeSchedulerData[i].srcRegValidC;
`endif

            wakeupSelect.writeSrcTag[i].regPtr[0].ptr = port.writeSchedulerData[i].srcPtrRegA;
            wakeupSelect.writeSrcTag[i].regPtr[1].ptr = port.writeSchedulerData[i].srcPtrRegB;
`ifdef RSD_MARCH_FP_PIPE
            wakeupSelect.writeSrcTag[i].regPtr[2].ptr = port.writeSchedulerData[i].srcPtrRegC;
`endif

        end

        // Check whether div can be issued
        // For stop issuing div according to the status of the divider
        canIssueDiv = TRUE;
        for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin
            if (!mulDivUnit.divFree[i]) begin
                canIssueDiv = FALSE;    // Currently, only a single div can be issued 
            end
        end
`ifdef RSD_MARCH_FP_PIPE
        canIssueFPDivSqrt = TRUE;
        for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin
            if (!fpDivSqrtUnit.Free[i]) begin
                canIssueFPDivSqrt = FALSE;    // Currently, only a single div/sqrt can be issued 
            end
        end
`endif

        // Select
        for(int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++) begin
            wakeupSelect.intIssueReq[i] = notIssued[i] && isInt[i];
`ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            wakeupSelect.loadIssueReq[i] = // mul/div is integrated into a load pipeline
                notIssued[i] && (
                    isLoad[i] || 
                    (isComplex[i] && (!isDiv[i] || (isDiv[i] && canIssueDiv)))
                );
`else
            wakeupSelect.loadIssueReq[i] = notIssued[i] && isLoad[i];
            wakeupSelect.complexIssueReq[i] = 
                notIssued[i] && isComplex[i] && (!isDiv[i] || (isDiv[i] && canIssueDiv));
`endif
            wakeupSelect.storeIssueReq[i] = notIssued[i] && isStore[i];
`ifdef RSD_MARCH_FP_PIPE
            wakeupSelect.fpIssueReq[i] = 
                notIssued[i] && isFP[i] && (!isFPDivSqrt[i] || (isFPDivSqrt[i] && canIssueFPDivSqrt));
`endif
        end

        for ( int i = 0; i < ISSUE_WIDTH; i++ ) begin
            port.selected[i] = wakeupSelect.selected[i] && !port.stall;
            port.selectedPtr[i] = wakeupSelect.selectedPtr[i];
        end

        selectedVector = '0;
        if (!port.stall) begin
            for (int i = 0; i < ISSUE_WIDTH; i++) begin
                selectedVector |= wakeupSelect.selectedVector[i];
            end
        end


        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for ( int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++ ) begin
`ifndef RSD_MARCH_FP_PIPE
            debug.scheduler[i].valid = notIssued[i] && (isInt[i] || isComplex[i] || isLoad[i] || isStore[i]);
`else
            debug.scheduler[i].valid = notIssued[i] && (isInt[i] || isComplex[i] || isLoad[i] || isStore[i] || isFP[i]);
`endif
        end
`endif
    end

endmodule : Scheduler



