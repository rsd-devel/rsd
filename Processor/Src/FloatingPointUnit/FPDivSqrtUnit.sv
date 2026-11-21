// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`include "BasicMacros.sv"
import BasicTypes::*;
import OpFormatTypes::*;
import ActiveListIndexTypes::*;

module FPDivSqrtUnit(FPDivSqrtUnitIF.FPDivSqrtUnit port, RecoveryManagerIF.FPDivSqrtUnit recovery);

    typedef enum logic[1:0]
    {
        DIVIDER_PHASE_FREE       = 0,  // Divider is free
        DIVIDER_PHASE_RESERVED   = 1,  // Divider is not processing but reserved
        DIVIDER_PHASE_PROCESSING = 2,  // In processing
        DIVIDER_PHASE_WRITE      = 3   // Wait for the ordinary FP RW port
    } DividerPhase;
    DividerPhase regPhase  [FP_DIVSQRT_ISSUE_WIDTH];
    DividerPhase nextPhase [FP_DIVSQRT_ISSUE_WIDTH];
    logic finished[FP_DIVSQRT_ISSUE_WIDTH];
    logic req[FP_DIVSQRT_ISSUE_WIDTH];

    logic flush[FP_DIVSQRT_ISSUE_WIDTH];
    logic rst_divider[FP_DIVSQRT_ISSUE_WIDTH];
    ActiveListIndexPath regActiveListPtr[FP_DIVSQRT_ISSUE_WIDTH];
    ActiveListIndexPath nextActiveListPtr[FP_DIVSQRT_ISSUE_WIDTH];
    OpDst regOpDst[FP_DIVSQRT_ISSUE_WIDTH];
    OpDst nextOpDst[FP_DIVSQRT_ISSUE_WIDTH];
    logic regPassedRW[FP_DIVSQRT_ISSUE_WIDTH];
    logic nextPassedRW[FP_DIVSQRT_ISSUE_WIDTH];

    for (genvar i = 0; i < FP_DIVSQRT_ISSUE_WIDTH; i++) begin : BlockDivUnit
        FP32DivSqrter fpDivSqrter(
            .clk(port.clk),
            .rst(rst_divider[i]),
            .lhs(port.dataInA[i]),
            .rhs(port.dataInB[i]),
            .rm(port.rm[i]),
            .is_divide(port.is_divide[i]),
            .req(req[i]),
            .finished(finished[i]),
            .result(port.DataOut[i]),
            .fflags(port.FFlagsOut[i])
        );
    end

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < FP_DIVSQRT_ISSUE_WIDTH; i++) begin
                regPhase[i] <= DIVIDER_PHASE_FREE;
                regActiveListPtr[i] <= 0;
                regOpDst[i] <= '0;
                regPassedRW[i] <= FALSE;
            end
        end
        else begin
            regPhase <= nextPhase;
            regActiveListPtr <= nextActiveListPtr;
            regOpDst <= nextOpDst;
            regPassedRW <= nextPassedRW;
        end
    end

    always_comb begin
        nextPhase = regPhase;
        nextActiveListPtr = regActiveListPtr;
        nextOpDst = regOpDst;
        nextPassedRW = regPassedRW;

        for (int i = 0; i < FP_DIVSQRT_ISSUE_WIDTH; i++) begin

            // Only a live operation can be cancelled by its retained AL tag.
            flush[i] = regPhase[i] != DIVIDER_PHASE_FREE && SelectiveFlushDetector(
                recovery.toRecoveryPhase,
                recovery.flushRangeHeadPtr,
                recovery.flushRangeTailPtr,
                recovery.flushAllInsns,
                regActiveListPtr[i]
            );
            req[i] = port.Req[i] && regPhase[i] == DIVIDER_PHASE_RESERVED &&
                !port.rst && !port.stall && !flush[i];

            // Completion must wait until the accepted attempt's normal RW
            // invalidation has been sampled, even if the result is ready first.
            if (port.passedRW[i]) begin
                nextPassedRW[i] = TRUE;
            end
            port.writeValid[i] = regPhase[i] == DIVIDER_PHASE_WRITE &&
                regPassedRW[i] && !port.rst && !port.stall && !flush[i];
            port.writePtr[i] = regActiveListPtr[i];

            case (regPhase[i])
            default: begin
                nextPhase[i] = DIVIDER_PHASE_FREE;
            end

            DIVIDER_PHASE_FREE: begin
                // Reserve divider and do not issue any div after that.
                if (port.Acquire[i] && !port.rst && !port.stall) begin
                    nextPhase[i] = DIVIDER_PHASE_RESERVED;
                    nextActiveListPtr[i] = port.acquireActiveListPtr[i];
                    nextOpDst[i] = port.acquireOpDst[i];
                    nextPassedRW[i] = FALSE;
                end
            end

            DIVIDER_PHASE_RESERVED: begin
                // Missing operands replay while this reservation is retained.
                if (req[i]) begin
                    // Receive the request of div, 
                    // so move to processing phase
                    nextPhase[i] = DIVIDER_PHASE_PROCESSING;
                end
            end

            DIVIDER_PHASE_PROCESSING: begin
                // Div operation has finished, so we can get result from divider
                if (finished[i]) begin
                    nextPhase[i] = DIVIDER_PHASE_WRITE;
                end
            end

            DIVIDER_PHASE_WRITE: begin
                // FP32DivSqrter retains both the result and fflags until reuse.
                if (port.writeValid[i] && port.writeReady[i]) begin
                    nextPhase[i] = DIVIDER_PHASE_FREE;
                end
            end
            endcase // regPhase[i]

            // 除算器に要求をしたdivがフラッシュされたので，除算器を解放する
            if (port.rst || flush[i]) begin
                nextPhase[i] = DIVIDER_PHASE_FREE;
                nextPassedRW[i] = FALSE;
            end
            rst_divider[i] = port.rst | flush[i];

            // 現状 acquire が issue ステージからくるので，次のサイクルの状態でフリーか
            // どうかを判定する必要がある
            port.Free[i]     = nextPhase[i] == DIVIDER_PHASE_FREE ? TRUE : FALSE;   
            // RESERVED must not block the replay that supplies missing operands.
            // Consumers released at the write edge still pass through IS/RR.
            port.Busy[i] = regPhase[i] == DIVIDER_PHASE_PROCESSING ||
                (regPhase[i] == DIVIDER_PHASE_WRITE &&
                 !(port.writeValid[i] && port.writeReady[i]));
            port.Reserved[i] = regPhase[i] == DIVIDER_PHASE_RESERVED ? TRUE : FALSE;
            port.pendingDst[i] = regOpDst[i];

        end // for (int i = 0; i < FP_DIVSQRT_ISSUE_WIDTH; i++) begin

    end // always_comb begin


endmodule
