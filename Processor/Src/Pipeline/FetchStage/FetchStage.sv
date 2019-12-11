// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for fetching instructions.
//

import BasicTypes::*;
import PipelineTypes::*;
import FetchUnitTypes::*;
import MemoryMapTypes::*;

module FetchStage(
    FetchStageIF.ThisStage port,
    NextPCStageIF.NextStage prev,
    ControllerIF.FetchStage ctrl,
    DebugIF.FetchStage debug
);

    // Pipeline Controll
    logic stall, clear;
    logic empty;
    logic regStall, beginStall;
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            regStall <= FALSE;
        end
        else begin
            regStall <= stall;
        end
    end

    
    // --- Pipeline registers
    FetchStageRegPath pipeReg[FETCH_WIDTH];
    PreDecodeStageRegPath nextStage[ FETCH_WIDTH ];

    always_comb begin
        // Control
        stall = ctrl.ifStage.stall;
        clear = ctrl.ifStage.clear;

        // Stall upper stages if cannot fetch valid instruction 
        ctrl.ifStageSendBubbleLower = 
            pipeReg[0].valid && !port.icReadHit[0];

        // Check whether instructions exist in this stage
        empty = TRUE;
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            if (pipeReg[i].valid)
                empty = FALSE;
        end
        ctrl.ifStageEmpty = empty;

        // Detect beginning of stall
        beginStall = !regStall && stall;
    end

    // Whether instruction is invalidated by branch prediction
    logic isFlushed[FETCH_WIDTH];

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < FETCH_WIDTH; i++) begin
                pipeReg[i] <= '0;
            end
        end
        else if (!stall) begin
            pipeReg <= prev.nextStage;
        end
        else begin
            for (int i = 0; i < FETCH_WIDTH; i++) begin
                if (isFlushed[i]) begin                    
                    // When a branch is predicted as Taken during stall,
                    // clear the valid bits of the subsequent lanes
                    pipeReg[i].valid <= FALSE;
                end
            end
        end
    end


    BranchPred brPred[FETCH_WIDTH];

    // Record the result of branch prediction.
    //
    // When this stage is stalled, the next instruction's PC is input to 
    // the branch predictor and the output of the branch predictor will change 
    // in the next cycle.
    // Hence, when stalled, the process of branch prediction must be performed at the beginning cycle of stall.
    // And more, it is necessary to keep the branch prediction result of the stalled instruction.
    BranchPred regBrPred[FETCH_WIDTH];
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < FETCH_WIDTH; i++) begin
                regBrPred[i] <= '0;
            end
        end
        else if (beginStall) begin
            regBrPred <= brPred;
        end
    end


    //
    // Branch Prediction
    //
    always_comb begin

        // The result of branch prediction
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            brPred[i].predAddr = port.brPredTaken[i] ? 
                port.btbOut[i] : pipeReg[i].pc + INSN_BYTE_WIDTH;
            brPred[i].predTaken = port.brPredTaken[i];
            brPred[i].globalHistory = port.brGlobalHistory[i];
            brPred[i].phtPrevValue = port.phtPrevValue[i];
        end

        // Check whether instructions are flushed by branch prediction
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            isFlushed[i] = FALSE;
            if (!regStall && pipeReg[i].valid && brPred[i].predTaken) begin
                for (int j = i + 1; j < FETCH_WIDTH; j++) begin
                    isFlushed[j] = pipeReg[j].valid;
                end

                break;
            end
        end

        // Update the branch history
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            port.updateBrHistory[i] = !regStall && pipeReg[i].valid;
        end
    end


    //
    // I-cache Access
    //
    AddrPath fetchAddrOut;
    always_comb begin
        // --- I-cache read
        port.icRE = pipeReg[0].valid; // read enable: whether check hit/miss
        fetchAddrOut = ToAddrFromPC(pipeReg[0].pc);
        // Address for comparing tag
        port.icReadAddrIn = ToPhyAddrFromLogical(fetchAddrOut);


        // Send information about this stage to the previous stage for
        // deciding the next fetch address
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            port.fetchStageIsValid[i] = pipeReg[i].valid;
            port.fetchStagePC[i] = pipeReg[i].pc;
        end
    end


    //
    // --- Pipeline registers
    //
    always_comb begin
        for ( int i = 0; i < FETCH_WIDTH; i++ ) begin
            if (stall || clear || port.rst || isFlushed[i]) begin
                nextStage[i].valid = FALSE;
            end
            else begin
                nextStage[i].valid = pipeReg[i].valid;
            end

`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].sid = pipeReg[i].sid;
`endif
            nextStage[i].pc = pipeReg[i].pc;
            nextStage[i].brPred = regStall ? regBrPred[i] : brPred[i];
            nextStage[i].insn = pipeReg[i].valid ? 
                port.icReadDataOut[i] : '0;
        end

        port.nextStage = nextStage;

`ifndef RSD_DISABLE_DEBUG_REGISTER
        // --- Debug Register
        for ( int i = 0; i < FETCH_WIDTH; i++ ) begin
            debug.ifReg[i].valid = pipeReg[i].valid;
            debug.ifReg[i].sid = pipeReg[i].sid;
            debug.ifReg[i].flush = isFlushed[i];
        end
`endif
    end

endmodule : FetchStage
