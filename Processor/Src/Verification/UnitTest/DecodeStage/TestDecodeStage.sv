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
`ifdef RSD_ENABLE_ZICFILP
    localparam bit CFI_ENABLED = 1;
`else
    localparam bit CFI_ENABLED = 0;
`endif
    localparam ELP_State_Type EXPECTED_ELP = CFI_ENABLED ? LP_EXPECTED : LP_NOT_EXPECTED;
    localparam IntMicroOpSubType LPAD_OP_TYPE = CFI_ENABLED ? INT_MOP_TYPE_LPL_CHECK : INT_MOP_TYPE_ALU;
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
    int fpEncodingCases = 0;
    int jalrEncodingCases = 0;
    int opEncodingCases = 0;

    DecodeStageIF port(.*);
    PreDecodeStageIF prev(.*);
    ControllerIF ctrl(.*);
    DebugIF debug(.*);
    PerformanceCounterIF perfCounter(.*);
    DecodeStage dut(.*);

    for (genvar i = 0; i < DECODE_WIDTH; i++) begin : DecodeInput
        Decoder decoder(
            .insn(insn[i]), .illegalPC(illegalPC[i]), .landingPadEnabled(TRUE),
            .fpStateEnabled(TRUE),
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
        Check(port.elpState === (CFI_ENABLED ? value : LP_NOT_EXPECTED),
              "recovery respects the configured extension");
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
              port.nextStage[0].elp == EXPECTED_ELP, description);
    endtask

    task CheckEncoding(input InsnPath encoding, input logic illegal,
                       input MicroOpType expectedType, input logic expectedWriteReg,
                       input FPU_Code expectedCode = FC_ADD);
        int validOps;
        string description;
        insn[0] = encoding;
        #1;
        description = $sformatf("encoding %08x (illegal=%0b)", encoding, illegal);
        validOps = 0;
        for (int i = 0; i < MICRO_OP_MAX_NUM; i++) begin
            if (!decodedOps[0][i].valid)
                continue;
            validOps++;
            if (illegal) begin
                Check(decodedOps[0][i].mopType == MOP_TYPE_MEM &&
                      decodedOps[0][i].mopSubType.memType == MEM_MOP_TYPE_ENV &&
                      decodedOps[0][i].operand.systemOp.envCode == ENV_INSN_ILLEGAL &&
                      decodedOps[0][i].serialized && !decodedOps[0][i].writeReg &&
                      decodedOps[0][i].nextELP == LP_NOT_EXPECTED,
                      description);
            end
            else begin
                Check(decodedOps[0][i].mopType == expectedType &&
                      !decodedOps[0][i].serialized &&
                      decodedOps[0][i].writeReg == expectedWriteReg,
                      description);
`ifdef RSD_MARCH_FP_PIPE
                if (expectedType == MOP_TYPE_FP)
                    Check(decodedOps[0][i].operand.fpOp.fpuCode == expectedCode, description);
`endif
            end
        end
        Check(validOps == 1 && decodedInfo[0].isSerialized == illegal, description);
        if (illegal)
            Check(!decodedInfo[0].writePC && !decodedInfo[0].isCall &&
                  !decodedInfo[0].isReturn && !decodedInfo[0].isRelBranch, description);
    endtask

    task CheckFPEncoding(input InsnPath encoding, input logic illegal,
                         input FPU_Code expectedCode);
`ifdef RSD_MARCH_FP_PIPE
        CheckEncoding(encoding, illegal, MOP_TYPE_FP, TRUE, expectedCode);
`else
        CheckEncoding(encoding, TRUE, MOP_TYPE_INT, FALSE);
`endif
        fpEncodingCases++;
    endtask

    initial begin
        #100000;
        $fatal(1, "DecodeStage test timed out");
    end

    initial begin
        if (DECODE_WIDTH != 2)
            $fatal(1, "DecodeStage test requires two decode lanes");

        Reset();
        // Sweep fixed fields as well as reserved values; valid encodings must survive.
        for (int rs2 = 0; rs2 < 32; rs2++) begin
            for (int funct3 = 0; funct3 < 8; funct3++) begin
                CheckFPEncoding({7'h70, 5'(rs2), 5'd1, 3'(funct3), 5'd31, 7'h53},
                                rs2 != 0 || funct3 > 1,
                                funct3 == 1 ? FC_FCLASS : FC_FMV_XW);
                CheckFPEncoding({7'h78, 5'(rs2), 5'd1, 3'(funct3), 5'd31, 7'h53},
                                rs2 != 0 || funct3 != 0, FC_FMV_WX);
            end
        end
        for (int op = 0; op < 4; op++) begin
            for (int fmt = 0; fmt < 4; fmt++) begin
                for (int rm = 0; rm < 8; rm++) begin
                    // RSD rejects reserved static modes 5/6; mode 7 remains dynamic.
                    CheckFPEncoding({5'd3, 2'(fmt), 5'd2, 5'd1, 3'(rm), 5'd31, 7'('h43 + 4*op)},
                                    fmt != 0 || rm == 5 || rm == 6,
                                    op == 0 ? FC_FMADD : op == 1 ? FC_FMSUB :
                                    op == 2 ? FC_FNMSUB : FC_FNMADD);
                end
            end
        end
        $display("FP decoder: %0d encodings checked", fpEncodingCases);

        // Neither the register fields nor the immediate can make a reserved JALR valid.
        for (int rd = 0; rd < 32; rd++) begin
            for (int rs1 = 0; rs1 < 32; rs1++) begin
                for (int funct3 = 0; funct3 < 8; funct3++) begin
                    for (int imm = 0; imm < 2; imm++) begin
                        CheckEncoding({12'(imm == 0 ? 0 : 'hfff), 5'(rs1), 3'(funct3), 5'(rd), 7'h67},
                                      funct3 != 0, MOP_TYPE_INT, rd != 0);
                        Check(decodedInfo[0].writePC == (funct3 == 0), "only valid JALR writes PC");
                        jalrEncodingCases++;
                    end
                end
            end
        end
        $display("Integer decoder: %0d JALR encodings checked", jalrEncodingCases);

        // Exhaust the OP function fields, including enabled and disabled extensions.
        for (int funct7 = 0; funct7 < 128; funct7++) begin
            for (int funct3 = 0; funct3 < 8; funct3++) begin
                for (int rd = 0; rd <= 31; rd += 31) begin
                    logic legal;
                    MicroOpType expectedType;
                    legal = funct7 == 0 || funct7 == 1 ||
                            (funct7 == 'h20 && (funct3 == 0 || funct3 == 5));
`ifdef RSD_ENABLE_ZBA
                    legal |= funct7 == 'h10 && (funct3 == 2 || funct3 == 4 || funct3 == 6);
`endif
`ifdef RSD_ENABLE_ZICOND
                    legal |= funct7 == 'h07 && (funct3 == 5 || funct3 == 7);
`endif
`ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
                    expectedType = funct7 == 1 ? MOP_TYPE_MEM : MOP_TYPE_INT;
`else
                    expectedType = funct7 == 1 ? MOP_TYPE_COMPLEX : MOP_TYPE_INT;
`endif
                    CheckEncoding({7'(funct7), 5'd15, 5'd15, 3'(funct3), 5'(rd), 7'h33},
                                  !legal, expectedType, rd != 0);
                    Check(!decodedInfo[0].writePC, "OP does not write PC");
                    opEncodingCases++;
                end
            end
        end
        $display("Integer decoder: %0d OP encodings checked", opEncodingCases);

        Reset();
        LoadBundle(JALR, LPAD, TRUE);
        Check(port.nextStage[0].valid && port.nextStage[0].elp == LP_NOT_EXPECTED &&
              port.nextStage[0].nextELP == EXPECTED_ELP, "JALR expectation matches the configured extension");
        Check(port.nextStage[1].valid && port.nextStage[1].elp == EXPECTED_ELP &&
              port.nextStage[1].nextELP == LP_NOT_EXPECTED &&
              port.nextStage[1].opInfo.mopSubType.intType == LPAD_OP_TYPE,
              "LPAD checking or AUIPC hint matches the configured extension");
        if (!CFI_ENABLED)
            Check(!port.nextStage[1].opInfo.writeReg &&
                  port.nextStage[1].opInfo.opTypeA == OOT_PC,
                  "disabled LPAD retains AUIPC-to-x0 hint semantics");
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
        Check(port.elpState === EXPECTED_ELP, "accepting the JALR advances ELP");
        Tick();
        Check(port.elpState === EXPECTED_ELP, "empty bundle retains ELP");

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
        Check(port.elpState === EXPECTED_ELP, "live suffix JALR advances ELP");

        Reset();
        Recover(LP_EXPECTED, FALSE);
        LoadBundle(LPAD, NOP, FALSE);
        clear = TRUE;
        #1;
        Check(!port.nextStage[0].valid, "frontend clear suppresses decoded output");
        Tick();
        Check(port.elpState === EXPECTED_ELP, "cleared LPAD must not consume ELP");
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
        CheckEnv(CFI_ENABLED ? ENV_LPAD_FAIL : ENV_INSN_ILLEGAL,
                 "landing pad checking preserves the configured exception priority");

        Reset();
        Recover(LP_EXPECTED, FALSE);
        LoadBundle(NOP, NOP, FALSE);
        if (CFI_ENABLED)
            CheckEnv(ENV_LPAD_FAIL, "missing LPAD becomes a serialized fault");
        else
            Check(port.nextStage[0].valid && !port.nextStage[0].opInfo.serialized &&
                  port.nextStage[0].opInfo.mopType == MOP_TYPE_INT &&
                  port.nextStage[0].opInfo.mopSubType.intType == INT_MOP_TYPE_ALU &&
                  port.nextStage[0].elp == LP_NOT_EXPECTED,
                  "disabled CFI does not fault on a missing landing pad");

        // A serialized replay must retain both the request and its incoming ELP.
        Reset();
        Recover(LP_EXPECTED, TRUE);
        LoadBundle(LPAD, NOP, FALSE);
        Check(port.nextStage[0].valid && port.nextStage[0].opInfo.serialized &&
              port.nextStage[0].elp == EXPECTED_ELP &&
              port.nextStage[0].opInfo.mopSubType.intType == LPAD_OP_TYPE,
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
              port.nextStage[0].elp == EXPECTED_ELP &&
              port.nextStage[0].opInfo.mopSubType.intType == LPAD_OP_TYPE,
              "remaining LPAD sees the JALR's ELP despite deferred bundle update");
        Tick();
        Check(port.elpState === LP_NOT_EXPECTED, "completed split bundle records its final ELP");

        Reset();
        LoadBundle(32'h0020a1af, NOP, FALSE); // amoadd.w x3, x2, (x1)
        Check(port.nextStage[0].valid && port.nextStage[0].nextELP === LP_NOT_EXPECTED,
              "A-extension emit helper initializes ELP");

        $display("DecodeStage: %0d checks passed (Zicfilp=%0b)", checks, CFI_ENABLED);
        $display("========== Test Passed ==========");
        $finish;
    end
endmodule
