// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Complex Integer Execution stage
//
// 乗算/SIMD 命令の演算を行う
// COMPLEX_EXEC_STAGE_DEPTH 段にパイプライン化されている
//

`include "BasicMacros.sv"
import BasicTypes::*;
import OpFormatTypes::*;
import ActiveListIndexTypes::*;

module MulDivUnit(
    MulDivUnitIF.MulDivUnit port,
    RecoveryManagerIF.MulDivUnit recovery
);

    for (genvar i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin : BlockMulUnit
        // MultiplierUnit
        PipelinedMultiplierUnit #(
            .BIT_WIDTH(DATA_WIDTH),
            .PIPELINE_DEPTH(MULDIV_STAGE_DEPTH)
        ) mulUnit (
            .clk(port.clk),
            .stall(port.stall),
            .fuOpA_In(port.dataInA[i]),
            .fuOpB_In(port.dataInB[i]),
            .getUpper(port.mulGetUpper[i]),
            .mulCode(port.mulCode[i]),
            .dataOut(port.mulDataOut[i])
        );
    end


    //
    // DividerUnit
    //

    typedef enum logic[1:0]
    {
        DIVIDER_PHASE_FREE       = 0,  // Divider is free
        DIVIDER_PHASE_RESERVED   = 1,  // Divider is not processing but reserved
        DIVIDER_PHASE_PROCESSING = 2,  // In processing
        DIVIDER_PHASE_WRITE      = 3   // Write the result without replaying DIV
    } DividerPhase;
    DividerPhase regPhase  [MULDIV_ISSUE_WIDTH];
    DividerPhase nextPhase [MULDIV_ISSUE_WIDTH];
    logic finished[MULDIV_ISSUE_WIDTH];
    DataPath divDataOut[MULDIV_ISSUE_WIDTH];
    logic divReq[MULDIV_ISSUE_WIDTH];

    logic flush[MULDIV_ISSUE_WIDTH];
    logic rst_divider[MULDIV_ISSUE_WIDTH];
    ActiveListIndexPath regActiveListPtr[MULDIV_ISSUE_WIDTH];
    ActiveListIndexPath nextActiveListPtr[MULDIV_ISSUE_WIDTH];
    OpDst regOpDst[MULDIV_ISSUE_WIDTH];
    OpDst nextOpDst[MULDIV_ISSUE_WIDTH];
    logic regPassedRW[MULDIV_ISSUE_WIDTH];
    logic nextPassedRW[MULDIV_ISSUE_WIDTH];

    for (genvar i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin : BlockDivUnit
        DividerUnit divUnit(
            .clk(port.clk),
            .rst(rst_divider[i]),
            .req(divReq[i]),
            .fuOpA_In(port.dataInA[i]),
            .fuOpB_In(port.dataInB[i]),
            .divCode(port.divCode[i]),
            .finished(finished[i]),
            .dataOut(divDataOut[i])
        );
    end

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin
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

        for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin

            // A free divider has no live operation. In particular, its old
            // ActiveList pointer must not cancel a new, already filtered issue.
            flush[i] = regPhase[i] != DIVIDER_PHASE_FREE && SelectiveFlushDetector(
                recovery.toRecoveryPhase,
                recovery.flushRangeHeadPtr,
                recovery.flushRangeTailPtr,
                recovery.flushAllInsns,
                regActiveListPtr[i]
            );
            divReq[i] = port.divReq[i] && regPhase[i] == DIVIDER_PHASE_RESERVED &&
                !port.rst && !port.stall && !flush[i];

            // The accepted DIV must pass normal RW first. Otherwise a short
            // division could complete before its delayed RF invalidation.
            if (port.divPassedRW[i]) begin
                nextPassedRW[i] = TRUE;
            end
            port.divWriteValid[i] = regPhase[i] == DIVIDER_PHASE_WRITE &&
                regPassedRW[i] && !port.rst && !port.stall && !flush[i];
            port.divWritePtr[i] = regActiveListPtr[i];
            port.divWriteData[i] = divDataOut[i];

            case (regPhase[i])
            default: begin
                nextPhase[i] = DIVIDER_PHASE_FREE;
            end

            DIVIDER_PHASE_FREE: begin
                // Reserve divider and do not issue any div after that.
                if (port.divAcquire[i] && !port.rst && !port.stall) begin
                    nextPhase[i] = DIVIDER_PHASE_RESERVED;
                    nextActiveListPtr[i] = port.acquireActiveListPtr[i];
                    nextOpDst[i] = port.acquireOpDst[i];
                    nextPassedRW[i] = FALSE;
                end
            end

            DIVIDER_PHASE_RESERVED: begin
                // Missing operands are replayed while this reservation is held.
                if (divReq[i]) begin
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
                // Hold the result until the ordinary RF/AL write ports are
                // free. rd=x0 still needs the ActiveList completion write.
                if (port.divWriteValid[i] && port.divWriteReady[i]) begin
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
            port.divFree[i]     = nextPhase[i] == DIVIDER_PHASE_FREE ? TRUE : FALSE;   
            // Consumers replay through IS/RR, so writing at this edge is early
            // enough. Wait while RW has not been passed or its ports are busy,
            // but never in RESERVED: that would block missing-operand replay.
            port.divBusy[i] = regPhase[i] == DIVIDER_PHASE_PROCESSING ||
                (regPhase[i] == DIVIDER_PHASE_WRITE &&
                 !(port.divWriteValid[i] && port.divWriteReady[i]));
            port.divReserved[i] = regPhase[i] == DIVIDER_PHASE_RESERVED ? TRUE : FALSE;
            port.divPendingDst[i] = regOpDst[i];

        end // for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin

    end // always_comb begin


endmodule
