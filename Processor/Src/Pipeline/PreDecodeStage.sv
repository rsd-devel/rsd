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
    DebugIF.PreDecodeStage debug,
    CSR_UnitIF.PreDecodeStage csrUnit
);
    // --- Pipeline registers
    PreDecodeStageRegPath pipeReg;

    always_ff@ (posedge port.clk)
    begin
        if (port.rst) begin
`ifdef RSD_SYNTHESIS
            pipeReg.valid <= '0;
`else
            // Keep idle decoder inputs defined in four-state simulation.
            pipeReg <= '0;
`endif
        end
        else if (!ctrl.pdStage.stall) begin             // write data
            pipeReg <= prev.nextStage;
        end
    end

    localparam FETCH_GROUP_OFFSET_WIDTH = $clog2(FETCH_GROUP_BYTE_NUM);
    PC_Path pc[DECODE_WIDTH];
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpSerial sid[DECODE_WIDTH];
`endif
    logic illegalPC[DECODE_WIDTH];
    always_comb begin
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            // All valid lanes share the group's upper PC bits. An offset that wraps is invalid.
            pc[i] = pipeReg.pc;
            pc[i][FETCH_GROUP_OFFSET_WIDTH-1:0] = pipeReg.pc[FETCH_GROUP_OFFSET_WIDTH-1:0]
                + FETCH_GROUP_OFFSET_WIDTH'(i * INSN_BYTE_WIDTH);
            illegalPC[i] = GetMemoryMapType(ToAddrFromPC(pc[i])) == MMT_ILLEGAL;
`ifndef RSD_DISABLE_DEBUG_REGISTER
            sid[i] = pipeReg.sid + OpSerial'(i);
`endif
        end
    end

    // Micro op decoder
    OpInfo [DECODE_WIDTH-1:0][MICRO_OP_MAX_NUM-1:0] microOps;  // Decoded micro ops
    InsnInfo [DECODE_WIDTH-1:0] insnInfo;   // Whether a decoded instruction is branch or not.
    for (genvar i = 0; i < DECODE_WIDTH; i++) begin
        Decoder decoder(
            .insn(pipeReg.insn[i]),
            .insnInfo(insnInfo[i]),
            .microOps(microOps[i]),
            .illegalPC(illegalPC[i]),
            .landingPadEnabled(csrUnit.xLPE),
            .fpStateEnabled(csrUnit.fpStateEnabled)
        );
    end

    // Pipeline control
    logic stall, clear;
    DecodeStageRegPath nextStage[DECODE_WIDTH];
    
    
    always_comb begin
        stall = ctrl.pdStage.stall;
        clear = ctrl.pdStage.clear;

        for (int i = 0; i < DECODE_WIDTH; i++) begin
            nextStage[i].valid = 
                (stall || clear || port.rst) ? FALSE : pipeReg.valid[i];
            
            // Decoded micro-op and context.
            nextStage[i].insn = pipeReg.insn[i];
            nextStage[i].pc = pc[i];
            nextStage[i].brPred = pipeReg.brPred[i];

            nextStage[i].insnInfo = insnInfo[i];
            nextStage[i].microOps = microOps[i];

`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].sid = sid[i];
`endif
        end
        
        port.nextStage = nextStage;
        ctrl.pdStageEmpty = !(|pipeReg.valid);

        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            // 先頭が次に送られたら，デコード元は消える．
            debug.pdReg[i].valid = pipeReg.valid[i];
            debug.pdReg[i].sid = sid[i];
`ifdef RSD_FUNCTIONAL_SIMULATION
            debug.pdReg[i].aluCode = microOps[i][1].operand.intOp.aluCode;
            debug.pdReg[i].opType = microOps[i][1].mopSubType.intType;
`endif
        end
`endif

    end
endmodule : PreDecodeStage


