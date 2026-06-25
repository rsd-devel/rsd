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
import MulDivUnitTypes::*;

module MulDivUnit(
    MulDivUnitIF.MulDivUnit port,
    RecoveryManagerIF.MulDivUnit recovery,
    RegisterFileIF.MulDivUnit registerFile,
    ActiveListIF.MulDivUnit activeList
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
        DIVIDER_PHASE_FREE           = 0,  // Divider is free
        DIVIDER_PHASE_RESERVED       = 1,  // Divider is not processing but reserved
        DIVIDER_PHASE_PROCESSING     = 2,  // In processing
        DIVIDER_PHASE_REGISTER_WRITE = 3   // Write result to RegisterFile and ActiveList
    } DividerPhase;
    DividerPhase regPhase  [MULDIV_ISSUE_WIDTH];
    DividerPhase nextPhase [MULDIV_ISSUE_WIDTH];
    logic finished[MULDIV_ISSUE_WIDTH];
    DataPath divDataOut  [MULDIV_ISSUE_WIDTH];

    logic flush[MULDIV_ISSUE_WIDTH];
    logic rst_divider[MULDIV_ISSUE_WIDTH];
    MulDivAcquireData regAcquireData[MULDIV_ISSUE_WIDTH];
    MulDivAcquireData nextAcquireData[MULDIV_ISSUE_WIDTH];
    
    for (genvar i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin : BlockDivUnit
        DividerUnit divUnit(
            .clk(port.clk),
            .rst(rst_divider[i]),
            .req(port.divReq[i]),
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
                regAcquireData[i] <= '0;
            end
        end
        else begin
            regPhase <= nextPhase;
            regAcquireData <= nextAcquireData;
        end
    end

    always_comb begin
        nextPhase = regPhase;
        nextAcquireData = regAcquireData;

        for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin
            // register
            registerFile.divDstRegWE[i] = FALSE;
            registerFile.divDstRegNum[i] = '0;
            registerFile.divDstRegData[i] = '0;
            // ActiveList
            activeList.divWrite[i] = FALSE;
            activeList.divWriteData[i] = '0;

            case (regPhase[i])
            default: begin
                nextPhase[i] = DIVIDER_PHASE_FREE;
            end

            DIVIDER_PHASE_FREE: begin
                // Reserve divider and do not issue any div after that.
                if (port.divAcquire[i]) begin
                    nextPhase[i] = DIVIDER_PHASE_RESERVED;
                    nextAcquireData[i] = port.acquireData[i];
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
                    nextPhase[i] = DIVIDER_PHASE_REGISTER_WRITE;
                end
            end

            DIVIDER_PHASE_REGISTER_WRITE: begin
                nextPhase[i] = DIVIDER_PHASE_FREE;

                // register
                registerFile.divDstRegWE[i] = regAcquireData[i].opDst.writeReg;
                registerFile.divDstRegNum[i] = regAcquireData[i].opDst.phyDstRegNum;
                registerFile.divDstRegData[i].valid = TRUE;
                registerFile.divDstRegData[i].data = divDataOut[i];

                // ActiveList
                activeList.divWrite[i] = TRUE;
                activeList.divWriteData[i].ptr = regAcquireData[i].activeListPtr;
                // activeList.divWriteData[i].loadQueuePtr = regAcquireData[i].loadQueueRecoveryPtr;
                // activeList.divWriteData[i].storeQueuePtr = regAcquireData[i].storeQueueRecoveryPtr;
                activeList.divWriteData[i].state = EXEC_STATE_SUCCESS;
                // activeList.divWriteData[i].pc = regAcquireData[i].pc;
                // activeList.divWriteData[i].dataAddr = '0;
                // activeList.divWriteData[i].isBranch = FALSE;
                // activeList.divWriteData[i].isStore = FALSE;
            end
            endcase // regPhase[i]


            // Cancel divider allocation on pipeline flush
            flush[i] = SelectiveFlushDetector(
                recovery.toRecoveryPhase,
                recovery.flushRangeHeadPtr,
                recovery.flushRangeTailPtr,
                recovery.flushAllInsns,
                regAcquireData[i].activeListPtr
            );

            // 除算器に要求したdivがフラッシュされたら、レジスタとActiveListへの書き込みもキャンセルする
            if (flush[i]) begin
                registerFile.divDstRegWE[i] = FALSE;
                activeList.divWrite[i] = FALSE;
            end

            // 除算器に要求をしたdivがフラッシュされたので，除算器を解放する
            if (flush[i]) begin
                nextPhase[i] = DIVIDER_PHASE_FREE;
            end
            rst_divider[i] = port.rst | flush[i];

            // 現状 acquire が issue ステージからくるので，次のサイクルの状態でフリーか
            // どうかを判定する必要がある
            port.divFree[i]     = nextPhase[i] == DIVIDER_PHASE_FREE ? TRUE : FALSE;
            // ReplayQueueでdivの完了待ちをしている命令のRRが
            // ちょうどレジスタの値を読み込めるようになるタイミングにするためにnextPhaseを使う
            port.divBusy[i]     = nextPhase[i] == DIVIDER_PHASE_PROCESSING ? TRUE : FALSE;
            port.divReserved[i] = regPhase[i] == DIVIDER_PHASE_RESERVED ? TRUE : FALSE;

        end // for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin

    end // always_comb begin


endmodule
