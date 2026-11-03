// Copyright 2026- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;
import MemoryMapTypes::*;
import MicroOpTypes::*;
import OpFormatTypes::*;
import PipelineTypes::*;
import FetchUnitTypes::*;

module TestDecodeStage;
    localparam InsnPath NOP = 32'h00000013;
    localparam InsnPath LPAD = 32'h00000017;
    localparam InsnPath JALR = 32'h00050067; // jalr x0, x10, 0
    localparam InsnPath JAL = 32'h0100006f;  // jal x0, +16
    localparam PC_Path START_PC = PC_Path'(32'h80001000);

    logic clk = FALSE;
    logic rst = TRUE;
    logic externalStall = FALSE;
    logic clear = FALSE;
    logic inputValid[DECODE_WIDTH];
    logic illegalPC[DECODE_WIDTH];
    InsnPath insn[DECODE_WIDTH];
    PC_Path pc[DECODE_WIDTH];
    BranchPred prediction[DECODE_WIDTH];
    OpInfo [MICRO_OP_MAX_NUM-1:0] decodedOps[DECODE_WIDTH];
    InsnInfo decodedInfo[DECODE_WIDTH];
    int checks = 0;

    DecodeStageIF port(.*);
    PreDecodeStageIF prev(.*);
    ControllerIF ctrl(.*);
    DebugIF debug(.*);
    PerformanceCounterIF perfCounter(.*);
    DecodeStage dut(.*);

    for (genvar i = 0; i < DECODE_WIDTH; i++) begin : DecodeInput
        Decoder decoder(
            .insn(insn[i]), .illegalPC(illegalPC[i]), .landingPadEnabled(TRUE),
            .microOps(decodedOps[i]), .insnInfo(decodedInfo[i])
        );
    end

    always_comb begin
        // Model the controller's downstream stall and decode-owned stall separately.
        ctrl.idStage.stall = !clear && (externalStall || ctrl.idStageStallUpper);
        ctrl.idStage.clear = clear;
        ctrl.stallByDecodeStage = !clear && !externalStall && ctrl.idStageStallUpper;
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            prev.nextStage[i] = '0;
            prev.nextStage[i].valid = inputValid[i];
            prev.nextStage[i].insn = insn[i];
            prev.nextStage[i].pc = pc[i];
            prev.nextStage[i].brPred = prediction[i];
            prev.nextStage[i].microOps = decodedOps[i];
            prev.nextStage[i].insnInfo = decodedInfo[i];
        end
    end

    // Drive and sample away from the active edge; no DUT state is forced.
    task Tick;
        #4;
        clk = TRUE;
        #1;
        clk = FALSE;
        #1;
    endtask

    task Check(input logic condition, input string description);
        checks++;
        if (condition !== TRUE)
            $fatal(1, "DecodeStage: %s", description);
    endtask

    task ClearInput;
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            inputValid[i] = FALSE;
            illegalPC[i] = FALSE;
            insn[i] = NOP;
            pc[i] = START_PC + i * INSN_BYTE_WIDTH;
            prediction[i] = '0;
        end
    endtask

    task Reset;
        rst = TRUE;
        externalStall = FALSE;
        clear = FALSE;
        port.serializeNextInsn = FALSE;
        port.recoverELP = FALSE;
        port.recoveredELP = LP_NOT_EXPECTED;
        port.setELP_OnInterrupt = FALSE;
        ClearInput();
        Tick();
        rst = FALSE;
        #1;
        Check(port.elpState === LP_NOT_EXPECTED, "reset clears ELP");
    endtask

    task Recover(input ELP_State_Type value, input logic serialize);
        clear = TRUE;
        port.recoverELP = TRUE;
        port.recoveredELP = value;
        port.serializeNextInsn = serialize;
        Tick();
        clear = FALSE;
        port.recoverELP = FALSE;
        port.serializeNextInsn = FALSE;
        #1;
        Check(port.elpState === value, "recovery overrides frontend clear");
    endtask

    task LoadBundle(input InsnPath first, input InsnPath second, input logic secondValid);
        ClearInput();
        inputValid[0] = TRUE;
        inputValid[1] = secondValid;
        insn[0] = first;
        insn[1] = second;
        Tick();
        ClearInput();
        #1;
    endtask

    task CheckEnv(input ENV_Code expected, input string description);
        Check(port.nextStage[0].valid &&
              port.nextStage[0].opInfo.mopType == MOP_TYPE_MEM &&
              port.nextStage[0].opInfo.mopSubType.memType == MEM_MOP_TYPE_ENV &&
              port.nextStage[0].opInfo.operand.systemOp.envCode == expected &&
              port.nextStage[0].opInfo.serialized &&
              port.nextStage[0].elp == LP_EXPECTED, description);
    endtask

    initial begin
        #100000;
        $fatal(1, "DecodeStage test timed out");
    end

    initial begin
        if (DECODE_WIDTH != 2)
            $fatal(1, "DecodeStage test requires two decode lanes");

        Reset();
        LoadBundle(JALR, LPAD, TRUE);
        Check(port.nextStage[0].valid && port.nextStage[0].elp == LP_NOT_EXPECTED &&
              port.nextStage[0].nextELP == LP_EXPECTED, "JALR starts a landing pad expectation");
        Check(port.nextStage[1].valid && port.nextStage[1].elp == LP_EXPECTED &&
              port.nextStage[1].nextELP == LP_NOT_EXPECTED &&
              port.nextStage[1].opInfo.mopSubType.intType == INT_MOP_TYPE_LPL_CHECK,
              "the following LPAD receives and consumes ELP");
        // Every payload RAM receives each dispatched op, including unused union views.
        Check(!$isunknown(port.nextStage[1].opInfo), "LPAD initializes the entire payload");
        Tick();
        Check(port.elpState === LP_NOT_EXPECTED, "LPAD leaves no expectation");

        Reset();
        LoadBundle(JALR, NOP, FALSE);
        externalStall = TRUE;
        repeat (3) begin
            Tick();
            Check(port.elpState === LP_NOT_EXPECTED, "completed bundle cannot advance ELP while stalled");
            Check(port.nextStage[0].opInfo.mopSubType.intType == INT_MOP_TYPE_RIJ,
                  "held JALR is not rechecked with its own outgoing ELP");
        end
        externalStall = FALSE;
        Tick();
        Check(port.elpState === LP_EXPECTED, "accepting the JALR advances ELP");
        Tick();
        Check(port.elpState === LP_EXPECTED, "empty bundle retains ELP");

        // An earlier corrected direct branch discards the later JALR.
        Reset();
        LoadBundle(JAL, JALR, TRUE);
        Check(port.nextFlush && port.nextStage[0].valid && !port.nextStage[1].valid,
              "branch correction discards the suffix");
        Tick();
        Check(port.elpState === LP_NOT_EXPECTED, "discarded JALR must not change ELP");

        // If that prediction was correct, the second instruction is live.
        Reset();
        inputValid[0] = TRUE;
        inputValid[1] = TRUE;
        insn[0] = JAL;
        insn[1] = JALR;
        pc[1] = START_PC + 16;
        prediction[0].predTaken = TRUE;
        prediction[0].predAddr = START_PC + 16;
        Tick();
        ClearInput();
        #1;
        Check(!port.nextFlush && port.nextStage[1].valid, "correct prediction keeps the suffix");
        Tick();
        Check(port.elpState === LP_EXPECTED, "live suffix JALR advances ELP");

        Reset();
        Recover(LP_EXPECTED, FALSE);
        LoadBundle(LPAD, NOP, FALSE);
        clear = TRUE;
        #1;
        Check(!port.nextStage[0].valid, "frontend clear suppresses decoded output");
        Tick();
        Check(port.elpState === LP_EXPECTED, "cleared LPAD must not consume ELP");
        clear = FALSE;
        externalStall = TRUE;
        port.recoverELP = TRUE;
        port.recoveredELP = LP_NOT_EXPECTED;
        Tick();
        Check(port.elpState === LP_NOT_EXPECTED, "recovery overrides a downstream stall");
        externalStall = FALSE;
        port.recoverELP = FALSE;
        Recover(LP_EXPECTED, FALSE);
        port.setELP_OnInterrupt = TRUE;
        Tick();
        Check(port.elpState === LP_NOT_EXPECTED, "interrupt entry clears ELP");
        port.setELP_OnInterrupt = FALSE;

        Reset();
        Recover(LP_EXPECTED, FALSE);
        inputValid[0] = TRUE;
        illegalPC[0] = TRUE;
        Tick();
        ClearInput();
        #1;
        CheckEnv(ENV_INSN_VIOLATION, "instruction access fault outranks landing pad fault");

        Reset();
        Recover(LP_EXPECTED, FALSE);
        LoadBundle(32'hffffffff, NOP, FALSE);
        CheckEnv(ENV_LPAD_FAIL, "landing pad fault outranks illegal instruction");

        Reset();
        Recover(LP_EXPECTED, FALSE);
        LoadBundle(NOP, NOP, FALSE);
        CheckEnv(ENV_LPAD_FAIL, "missing LPAD becomes a serialized fault");

        // A serialized replay must retain both the request and its incoming ELP.
        Reset();
        Recover(LP_EXPECTED, TRUE);
        LoadBundle(LPAD, NOP, FALSE);
        Check(port.nextStage[0].valid && port.nextStage[0].opInfo.serialized &&
              port.nextStage[0].elp == LP_EXPECTED &&
              port.nextStage[0].opInfo.mopSubType.intType == INT_MOP_TYPE_LPL_CHECK,
              "serialized replay checks the original LPAD with restored ELP");
        Tick();
        Check(port.elpState === LP_NOT_EXPECTED, "serialized LPAD consumes ELP once");

        // Serialization splits a two-instruction bundle across two cycles.
        Reset();
        Recover(LP_NOT_EXPECTED, TRUE);
        LoadBundle(JALR, LPAD, TRUE);
        Check(ctrl.idStageStallUpper && port.nextStage[0].valid && !port.nextStage[1].valid,
              "serialized first op leaves the bundle incomplete");
        Tick();
        Check(port.elpState === LP_NOT_EXPECTED, "incomplete bundle retains its entry ELP");
        Check(!ctrl.idStageStallUpper && port.nextStage[0].valid &&
              port.nextStage[0].elp == LP_EXPECTED &&
              port.nextStage[0].opInfo.mopSubType.intType == INT_MOP_TYPE_LPL_CHECK,
              "remaining LPAD sees the JALR's ELP despite deferred bundle update");
        Tick();
        Check(port.elpState === LP_NOT_EXPECTED, "completed split bundle records its final ELP");

        Reset();
        LoadBundle(32'h0020a1af, NOP, FALSE); // amoadd.w x3, x2, (x1)
        Check(port.nextStage[0].valid && port.nextStage[0].nextELP === LP_NOT_EXPECTED,
              "A-extension emit helper initializes ELP");

        $display("DecodeStage: %0d checks passed", checks);
        $display("========== Test Passed ==========");
        $finish;
    end
endmodule
