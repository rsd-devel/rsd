// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// DecodeStage
//

import BasicTypes::*;
import MemoryMapTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import PipelineTypes::*;
import DebugTypes::*;
import FetchUnitTypes::*;
import MemoryMapTypes::*;


module PreDecodeStage(
    PreDecodeStageIF.ThisStage port, 
    FetchStageIF.NextStage prev,
    ControllerIF.PreDecodeStage ctrl,
    DebugIF.PreDecodeStage debug
);
    // --- Pipeline registers
    PreDecodeStageRegPath pipeReg[DECODE_WIDTH];
    
`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif

    always_ff@ (posedge port.clk)
    begin
        if (port.rst) begin
            for (int i = 0; i < DECODE_WIDTH; i++) begin
                pipeReg[i].valid <= FALSE;
            end
        end
        else if (!ctrl.pdStage.stall) begin             // write data
            pipeReg <= prev.nextStage;
        end
    end

    AddrPath pc[DECODE_WIDTH];
    logic illegalPC[DECODE_WIDTH];
    always_comb begin
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            pc[i] = ToAddrFromPC(pipeReg[i].pc);
            illegalPC[i] =
                GetMemoryMapType(pc[i]) == MMT_ILLEGAL ? TRUE : FALSE;
        end
    end

    // Micro op decoder
    OpInfo [DECODE_WIDTH-1:0][MICRO_OP_MAX_NUM-1:0] microOps;  // Decoded micro ops
    InsnInfo [DECODE_WIDTH-1:0] insnInfo;   // Whether a decoded instruction is branch or not.
    for (genvar i = 0; i < DECODE_WIDTH; i++) begin
        Decoder decoder(
            .insn(pipeReg[i].insn),
            .insnInfo(insnInfo[i]),
            .microOps(microOps[i]),
            .illegalPC(illegalPC[i])
        );
    end

    // Pipeline control
    logic stall, clear;
    logic empty;
    DecodeStageRegPath nextStage[DECODE_WIDTH];
    
    
    always_comb begin
        stall = ctrl.pdStage.stall;
        clear = ctrl.pdStage.clear;

        empty = TRUE;
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            nextStage[i].valid = 
                (stall || clear || port.rst) ? FALSE : pipeReg[i].valid;
            
            // Decoded micro-op and context.
            nextStage[i].insn = pipeReg[i].insn;
            nextStage[i].pc = pipeReg[i].pc;
            nextStage[i].brPred = pipeReg[i].brPred;

            nextStage[i].insnInfo = insnInfo[i];
            nextStage[i].microOps = microOps[i];

            if (pipeReg[i].valid)
                empty = FALSE;

`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].sid = pipeReg[i].sid;
`endif
        end
        
        port.nextStage = nextStage;
        ctrl.pdStageEmpty = empty;

        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            // 先頭が次に送られたら，デコード元は消える．
            debug.pdReg[i].valid = pipeReg[i].valid;
            debug.pdReg[i].sid = pipeReg[i].sid;
`ifdef RSD_FUNCTIONAL_SIMULATION
            debug.pdReg[i].aluCode = microOps[i][1].operand.intOp.aluCode;
            debug.pdReg[i].opType = microOps[i][1].mopSubType.intType;
`endif
        end
`endif

    end
endmodule : PreDecodeStage


