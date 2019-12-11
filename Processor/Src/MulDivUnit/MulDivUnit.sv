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

module MulDivUnit(MulDivUnitIF.MulDivUnit port);

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
        DIVIDER_PHASE_WAITING    = 3   // Wait for issuing div from replayqueue
    } DividerPhase;
    DividerPhase regPhase  [MULDIV_ISSUE_WIDTH];
    DividerPhase nextPhase [MULDIV_ISSUE_WIDTH];
    logic finished[MULDIV_ISSUE_WIDTH];

    for (genvar i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin : BlockDivUnit
        DividerUnit divUnit(
            .clk(port.clk),
            .rst(port.rst),
            .req(port.divReq[i]),
            .fuOpA_In(port.dataInA[i]),
            .fuOpB_In(port.dataInB[i]),
            .divCode(port.divCode[i]),
            .finished(finished[i]),
            .dataOut(port.divDataOut[i])
        );
    end

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin
                regPhase[i] <= DIVIDER_PHASE_FREE;
            end
        end
        else begin
            regPhase <= nextPhase;
        end
    end

    always_comb begin
        nextPhase = regPhase;


        for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin

            case (regPhase[i])
            default: begin
                nextPhase[i] = DIVIDER_PHASE_FREE;
            end

            DIVIDER_PHASE_FREE: begin
                // Reserve divider and do not issue divs after that.
                if (port.divAcquire[i]) begin
                    nextPhase[i] = DIVIDER_PHASE_RESERVED;
                end
            end

            DIVIDER_PHASE_RESERVED: begin
                // Request to the divider
                // NOT make a request when below situation
                // 1) When any operands of inst. are invalid
                // 2) When the divider is waiting for the instruction
                //    to receive the result of the divider
                if (port.divReq[i]) begin
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
                if (port.divRelease[i]) begin 
                    // Divが除算器から結果を取得できたので，
                    // IQからのdivの発行を許可する 
                    nextPhase[i] = DIVIDER_PHASE_FREE;
                end
            end
            endcase // regPhase[i]


            // 除算器に要求をしたdivがフラッシュされたので，除算器を解放する
            if (port.divReset[i]) begin
                nextPhase[i] = DIVIDER_PHASE_FREE;
            end

            `ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
                if (port.divResetFromMI_Stage[i] || 
                    port.divResetFromMR_Stage[i] || 
                    port.divResetFromMT_Stage[i]
                ) begin
                    nextPhase[i] = DIVIDER_PHASE_FREE;
                end
            `else
                if (port.divResetFromCI_Stage[i]) begin
                    nextPhase[i] = DIVIDER_PHASE_FREE;
                end
            `endif

            // 現状 acquire が issue ステージからくるので，次のサイクルの状態でフリーか
            // どうかを判定する必要がある
            port.divFree[i]     = nextPhase[i] == DIVIDER_PHASE_FREE ? TRUE : FALSE;   
            port.divFinished[i] = regPhase[i] == DIVIDER_PHASE_WAITING ? TRUE : FALSE;
            port.divBusy[i]     = regPhase[i] == DIVIDER_PHASE_PROCESSING ? TRUE : FALSE;
            port.divReserved[i] = regPhase[i] == DIVIDER_PHASE_RESERVED ? TRUE : FALSE;

        end // for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin

    end // always_comb begin


endmodule
