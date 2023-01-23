// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`include "BasicMacros.sv"
import BasicTypes::*;
import OpFormatTypes::*;

module FPDivSqrtUnit(FPDivSqrtUnitIF.FPDivSqrtUnit port);

    typedef enum logic[1:0]
    {
        DIVIDER_PHASE_FREE       = 0,  // Divider is free
        DIVIDER_PHASE_RESERVED   = 1,  // Divider is not processing but reserved
        DIVIDER_PHASE_PROCESSING = 2,  // In processing
        DIVIDER_PHASE_WAITING    = 3   // Wait for issuing div from replayqueue
    } DividerPhase;
    DividerPhase regPhase  [MULDIV_ISSUE_WIDTH];
    DividerPhase nextPhase [MULDIV_ISSUE_WIDTH];
    logic finished[MULDIV_ISSUE_WIDTH];

    for (genvar i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin : BlockDivUnit
        DividerUnit divUnit(
            .clk(port.clk),
            .rst(port.rst),
            .req(port.Req[i]),
            .fuOpA_In(port.dataInA[i]),
            .fuOpB_In(port.dataInB[i]),
            .divCode('0),
            .finished(finished[i]),
            .dataOut(port.DataOut[i])
        );
    end

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < FP_DIVSQRT_ISSUE_WIDTH; i++) begin
                regPhase[i] <= DIVIDER_PHASE_FREE;
            end
        end
        else begin
            regPhase <= nextPhase;
        end
    end

    always_comb begin
        nextPhase = regPhase;


        for (int i = 0; i < FP_DIVSQRT_ISSUE_WIDTH; i++) begin

            case (regPhase[i])
            default: begin
                nextPhase[i] = DIVIDER_PHASE_FREE;
            end

            DIVIDER_PHASE_FREE: begin
                // Reserve divider and do not issue divs after that.
                if (port.Acquire[i]) begin
                    nextPhase[i] = DIVIDER_PHASE_RESERVED;
                end
            end

            DIVIDER_PHASE_RESERVED: begin
                // Request to the divider
                // NOT make a request when below situation
                // 1) When any operands of inst. are invalid
                // 2) When the divider is waiting for the instruction
                //    to receive the result of the divider
                if (port.Req[i]) begin
                    // Receive the request of div, 
                    // so move to processing phase
                    nextPhase[i] = DIVIDER_PHASE_PROCESSING;
                end
            end

            DIVIDER_PHASE_PROCESSING: begin
                // Div operation has finished, so we can get result from divider
                if (finished[i]) begin
                    nextPhase[i] = DIVIDER_PHASE_WAITING;
                end
            end

            DIVIDER_PHASE_WAITING: begin
                if (port.Release[i]) begin 
                    // Divが除算器から結果を取得できたので，
                    // IQからのdivの発行を許可する 
                    nextPhase[i] = DIVIDER_PHASE_FREE;
                end
            end
            endcase // regPhase[i]


            // 除算器に要求をしたdivがフラッシュされたので，除算器を解放する
            if (port.Reset[i]) begin
                nextPhase[i] = DIVIDER_PHASE_FREE;
            end

            if (port.ResetFromFPIssue_Stage[i]) begin
                nextPhase[i] = DIVIDER_PHASE_FREE;
            end

            // 現状 acquire が issue ステージからくるので，次のサイクルの状態でフリーか
            // どうかを判定する必要がある
            port.Free[i]     = nextPhase[i] == DIVIDER_PHASE_FREE ? TRUE : FALSE;   
            port.Finished[i] = regPhase[i] == DIVIDER_PHASE_WAITING ? TRUE : FALSE;
            port.Busy[i]     = regPhase[i] == DIVIDER_PHASE_PROCESSING ? TRUE : FALSE;
            port.Reserved[i] = regPhase[i] == DIVIDER_PHASE_RESERVED ? TRUE : FALSE;

        end // for (int i = 0; i < FP_DIVSQRT_ISSUE_WIDTH; i++) begin

    end // always_comb begin


endmodule
