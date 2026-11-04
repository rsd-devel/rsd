// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`timescale 1ns/1ps
import BasicTypes::*;
import MemoryMapTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import CSR_UnitTypes::*;

module TestInterruptController;
`ifdef RSD_ENABLE_ZICFILP
    localparam bit CFI_ENABLED = 1;
`else
    localparam bit CFI_ENABLED = 0;
`endif
    localparam ELP_State_Type EXPECTED_ELP = CFI_ENABLED ? LP_EXPECTED : LP_NOT_EXPECTED;
    localparam AddrPath VECTOR_BASE = 32'h80000100;
    localparam AddrPath SUPERVISOR_VECTOR_BASE = 32'h80000200;
    localparam AddrPath RETURN_PC = 32'h80001234;
    localparam DataPath MACHINE_INTERRUPTS = 32'h00000888;
    localparam DataPath SUPERVISOR_INTERRUPTS = 32'h00000222;
    localparam DataPath ALL_INTERRUPTS = MACHINE_INTERRUPTS | SUPERVISOR_INTERRUPTS | 32'hffff0000;
    logic clk = 0, rst = 1, rstStart = 1;
    logic reqCustomInterrupt = 0;
    CustomInterruptCodePath customInterruptCode = '0;

    CSR_UnitIF csr(.*);
    PLIC_UnitIF plic(.*);
    IO_UnitIF ioPort(.clk(clk), .rst(rst), .rstStart(rstStart),
                     .serialWE(), .serialWriteDataOut());
    PerformanceCounterIF perf(.*);
    ControllerIF ctrl(.*);
    NextPCStageIF fetchStage(.*);
    DecodeStageIF decodeStage(.*);
    RecoveryManagerIF recovery(.*);
    PLIC_Unit plicUnit(plic, csr, ioPort);
    CSR_Unit csrUnit(csr, plic, perf);
    InterruptController interruptCtrl(csr, ctrl, fetchStage, decodeStage, recovery);

    int cases = 0;
    int aliasCases = 0;
    int cfiCases = 0;
    string caseName;

    // Keep stimulus and checks away from the active edge in both simulators.
    task automatic Tick;
        #4; clk = 1;
        #1; clk = 0;
        #1;
    endtask

    task automatic CheckSIP;
        DataPath delegated, initialPending, operand, visible, expected;
        DataPath values[4] = '{32'h0, 32'hffffffff, 32'h2, 32'h4};
        for (int mask = 0; mask < 8; mask++)
            for (int origin = 0; origin < 2; origin++)
                for (int pending = 0; pending < 2; pending++)
                    for (int pattern = 0; pattern < 4; pattern++)
                        for (int op = 1; op <= 3; op++) begin
                            caseName = $sformatf("SIP mask=%0d S=%0d SSIP=%0d pattern=%0d op=%0d",
                                                mask, origin, pending, pattern, op);
                            Reset();
                            delegated = InterruptBits(3'(mask), 1) | 32'h80010000;
                            initialPending = 32'h80010220 | (DataPath'(pending) << 1);
                            operand = values[pattern];
                            visible = initialPending & delegated;
                            expected = op == 1 ? operand : op == 2 ? visible | operand : visible & ~operand;
                            expected = (initialPending & ~(delegated & 32'h2)) |
                                       (expected & delegated & 32'h2);
                            WriteCSR(CSR_NUM_MIDELEG, delegated);
                            WriteCSR(CSR_NUM_MIP, initialPending);
                            if (origin != 0) begin
                                WriteCSR(CSR_NUM_MSTATUS, 32'h800);
                                csr.triggerExcpt = 1;
                                Tick();
                                csr.triggerExcpt = 0;
                            end
                            ReadCSR(CSR_NUM_SIP, visible);
                            WriteCSR(CSR_NUM_SIP, operand, CSR_Code'(op));
                            assert (DataPath'(csr.csrWholeOut.mip) === expected)
                                else $fatal(1, "SIP changed the wrong pending bits (%s)", caseName);
                            ReadCSR(CSR_NUM_SIP, expected & delegated);
                            aliasCases++;
                        end

        // A following RMW must observe the immediately preceding software write.
        caseName = "consecutive SIP writes";
        Reset();
        WriteCSR(CSR_NUM_MIDELEG, 2);
        WriteCSR(CSR_NUM_SIP, 2);
        WriteCSR(CSR_NUM_SIP, 4, CSR_SET);
        ReadCSR(CSR_NUM_SIP, 2);
        WriteCSR(CSR_NUM_SIP, 4, CSR_CLEAR);
        ReadCSR(CSR_NUM_SIP, 2);
        WriteCSR(CSR_NUM_SIP, 2, CSR_CLEAR);
        ReadCSR(CSR_NUM_SIP, 0);

        // Hardware SEIP is readable, but MIP RMW must not latch it in software.
        caseName = "hardware SEIP and software RMW";
        Reset();
        WriteCSR(CSR_NUM_MIDELEG, SUPERVISOR_INTERRUPTS);
        WritePLIC(PHY_ADDR_PLIC_SOURCE_PRIORITY_BASE + 4, 1);
        WritePLIC(PHY_ADDR_PLIC_ENABLE_BASE + 'h80, 2);
        plic.interruptReqFromInterruptSource[1] = 1;
        repeat (3) Tick();
        ReadCSR(CSR_NUM_MIP, 32'h200);
        WriteCSR(CSR_NUM_MIP, 2, CSR_SET);
        ReadCSR(CSR_NUM_MIP, 32'h202);
        WriteCSR(CSR_NUM_MIP, 2, CSR_CLEAR);
        ReadCSR(CSR_NUM_MIP, 32'h200);
        WriteCSR(CSR_NUM_SIP, 0);
        ReadCSR(CSR_NUM_SIP, 32'h200);
        plic.interruptReqFromInterruptSource[1] = 0;
        WritePLIC(PHY_ADDR_PLIC_ENABLE_BASE + 'h80, 0);
        repeat (2) Tick();
        ReadCSR(CSR_NUM_MIP, 0);
        aliasCases += 2;
    endtask

    // The test mask is {external, software, timer}, in descending priority.
    function automatic DataPath InterruptBits(input logic [2:0] mask, input bit supervisor = 0);
        if (supervisor)
            return (DataPath'(mask[2]) << 9) |
                   (DataPath'(mask[1]) << 1) | (DataPath'(mask[0]) << 5);
        else
            return (DataPath'(mask[2]) << 11) |
                   (DataPath'(mask[1]) << 3) | (DataPath'(mask[0]) << 7);
    endfunction

    function automatic int PriorityCode(input DataPath pending);
        for (int code = 31; code >= 16; code--)
            if (pending[code]) return code;
        return pending[11] ? 11 : pending[3] ? 3 : pending[7] ? 7 :
               pending[9] ? 9 : pending[1] ? 1 : 5;
    endfunction

    // Counters may advance while waiting; only trap state must stay unchanged.
    task automatic CheckTrapState(input CSR_BodyPath previous);
        assert ({csr.csrWholeOut.mstatus, csr.csrWholeOut.mstatush, csr.csrWholeOut.mepc,
                 csr.csrWholeOut.mcause, csr.csrWholeOut.mtval,
                 csr.csrWholeOut.sepc, csr.csrWholeOut.scause, csr.csrWholeOut.stval} ===
                {previous.mstatus, previous.mstatush, previous.mepc, previous.mcause, previous.mtval,
                 previous.sepc, previous.scause, previous.stval})
            else $fatal(1, "Unexpected trap state change (%s)", caseName);
    endtask

    task automatic Reset;
        ctrl.wholePipelineEmpty = 0;
        recovery.unableToStartRecovery = 0;
        fetchStage.pcOut = ToPC_FromAddr(RETURN_PC);
        csr.csrRE = 0;
        csr.csrWE = 0;
        csr.csrNumber = CSR_NUM_MSCRATCH;
        csr.csrCode = CSR_WRITE;
        csr.csrWriteIn = '0;
        csr.triggerExcpt = 0;
        csr.excptCause = EXEC_STATE_TRAP_MRET;
        csr.excptCauseAddr = '0;
        csr.excptCauseDataAddr = '0;
        csr.excptELP = LP_NOT_EXPECTED;
        decodeStage.elpState = LP_NOT_EXPECTED;
        csr.retireNum = '0;
        csr.reqTimerInterrupt = 0;
        csr.msip = 0;
`ifdef RSD_MARCH_FP_PIPE
        csr.fflagsWE = 0;
        csr.fflagsData = '0;
`endif
`ifndef RSD_DISABLE_PERFORMANCE_COUNTER
        perf.perfCounter = '0;
`endif
        plic.ioWE = 0;
        plic.ioRE = 0;
        plic.ioWriteDataIn = '0;
        plic.phyRawWriteAddrIn = '0;
        plic.phyRawReadAddrIn = '0;
        foreach (plic.interruptReqFromInterruptSource[i])
            plic.interruptReqFromInterruptSource[i] = 0;
        rst = 1;
        rstStart = 1;
        Tick();
        rst = 0;
        rstStart = 0;
        #1;
    endtask

    task automatic WriteCSR(input CSR_NumberPath number, input DataPath value,
                            input CSR_Code operation = CSR_WRITE);
        csr.csrNumber = number;
        csr.csrWriteIn = value;
        csr.csrCode = operation;
        csr.csrWE = 1;
        #1;
        assert (csr.csrUnitTriggerExcpt === 1'b0)
            else $fatal(1, "Unexpected CSR exception: %03x (%s)", number, caseName);
        Tick();
        csr.csrWE = 0;
        #1;
    endtask

    task automatic ReadCSR(input CSR_NumberPath number, input DataPath expected);
        csr.csrNumber = number;
        csr.csrRE = 1;
        #1;
        assert (csr.csrUnitTriggerExcpt === 1'b0 && csr.csrReadOut === expected)
            else $fatal(1, "CSR %03x: expected %08x, got %08x (%s)",
                        number, expected, csr.csrReadOut, caseName);
        csr.csrRE = 0;
        #1;
    endtask

    task automatic CheckSIE;
        DataPath delegated, initialEnable, operand, visible, expected;
        DataPath values[4] = '{32'h0, 32'hffffffff, 32'h80000282, 32'h00010028};
        for (int mask = 0; mask < 8; mask++)
            for (int custom = 0; custom < 2; custom++)
                for (int origin = 0; origin < 2; origin++)
                    for (int pattern = 0; pattern < 4; pattern++)
                        for (int op = 1; op <= 3; op++) begin
                            caseName = $sformatf("SIE mask=%0d custom=%0d S=%0d pattern=%0d op=%0d",
                                                mask, custom, origin, pattern, op);
                            Reset();
                            delegated = InterruptBits(3'(mask), 1) | (custom != 0 ? 32'h80010000 : 0);
                            initialEnable = values[pattern] & 32'hffff0aaa;
                            operand = values[(pattern + 1) % 4];
                            visible = initialEnable & delegated;
                            expected = op == 1 ? operand : op == 2 ? visible | operand : visible & ~operand;
                            expected = (initialEnable & ~delegated) | (expected & delegated);
                            WriteCSR(CSR_NUM_MIDELEG, delegated);
                            WriteCSR(CSR_NUM_MIE, initialEnable);
                            if (origin != 0) begin
                                WriteCSR(CSR_NUM_MSTATUS, 32'h800); // MPP=S
                                csr.triggerExcpt = 1;
                                Tick();
                                csr.triggerExcpt = 0;
                            end
                            ReadCSR(CSR_NUM_SIE, visible);
                            WriteCSR(CSR_NUM_SIE, operand, CSR_Code'(op));
                            assert (DataPath'(csr.csrWholeOut.mie) === expected)
                                else $fatal(1, "SIE changed the wrong MIE bits (%s)", caseName);
                            ReadCSR(CSR_NUM_SIE, expected & delegated);
                            if (origin == 0) begin
                                ReadCSR(CSR_NUM_MIE, expected);
                                WriteCSR(CSR_NUM_MIDELEG, ~delegated);
                                assert (DataPath'(csr.csrWholeOut.mie) === expected)
                                    else $fatal(1, "Changing delegation cleared MIE (%s)", caseName);
                                ReadCSR(CSR_NUM_SIE, expected & ~delegated & 32'hffff0222);
                            end
                            aliasCases++;
                        end
    endtask

    task automatic WritePLIC(input PhyRawAddrPath address, input DataPath value);
        plic.phyRawWriteAddrIn = PhyAddrPath'(address);
        plic.ioWriteDataIn = value;
        plic.ioWE = 1;
        Tick();
        plic.ioWE = 0;
        #1;
    endtask

    // Regressions for CSR-alias failures; do not force state.
    task automatic CheckSupervisorAlias(input int kind);
        caseName = kind == 0 ? "SIE reads MIE" : kind == 1 ? "SIE updates MIE" : "SIP clears SSIP";
        Reset();
        WriteCSR(CSR_NUM_MIDELEG, 2);
        WriteCSR(CSR_NUM_MIE, kind == 1 ? 0 : 2);
        WriteCSR(CSR_NUM_MIP, kind == 2 ? 2 : 0);
        WriteCSR(CSR_NUM_MSTATUS, 32'h882); // MPP=S, MPIE=1, SIE=1
        csr.triggerExcpt = 1;
        Tick();
        csr.triggerExcpt = 0;
        #1;
        assert (csr.privilegeLevel === PRIVILEGE_LEVEL_S)
            else $fatal(1, "Failed to enter S mode (%s)", caseName);
        if (kind == 1) begin
            WriteCSR(CSR_NUM_SIE, 2);
            assert (DataPath'(csr.csrWholeOut.mie) === 32'h2)
                else $fatal(1, "SIE write did not enable SSI in MIE");
        end
        else begin
            if (kind == 2) begin
                assert (csr.csrWholeOut.mip.SSIP === 1'b1)
                    else $fatal(1, "SSIP was not pending before the clear");
                WriteCSR(CSR_NUM_SIP, 0);
                assert (ctrl.npStageSendBubbleLowerForInterrupt === 1'b0)
                    else $fatal(1, "Clearing SSIP left the interrupt request active");
            end
            csr.csrNumber = kind == 0 ? CSR_NUM_SIE : CSR_NUM_SIP;
            csr.csrRE = 1;
            #1;
            assert (csr.csrUnitTriggerExcpt === 1'b0 &&
                    csr.csrReadOut === (kind == 0 ? 32'h2 : 32'h0))
                else $fatal(1, "Wrong CSR alias value %08x (%s)", csr.csrReadOut, caseName);
            csr.csrRE = 0;
        end
    endtask

    function automatic bit ExpectedLPE(input PrivilegeLevelType mode, input logic [2:0] enables);
        return CFI_ENABLED && (mode == PRIVILEGE_LEVEL_M ? enables[2] :
                               mode == PRIVILEGE_LEVEL_S ? enables[1] : enables[0]);
    endfunction

    task automatic ConfigureLPE(input logic [2:0] enables);
        WriteCSR(CSR_NUM_MSECCFG, DataPath'(enables[2]) << 10);
        WriteCSR(CSR_NUM_MENVCFG, DataPath'(enables[1]) << 2);
        WriteCSR(CSR_NUM_SENVCFG, DataPath'(enables[0]) << 2);
    endtask

    task automatic CheckCFICSR;
        CSR_NumberPath numbers[4] = '{CSR_NUM_MSECCFG, CSR_NUM_MENVCFG,
                                      CSR_NUM_SENVCFG, CSR_NUM_MSTATUSH};
        DataPath masks[4] = '{32'h400, 32'h4, 32'h4, 32'h200};
        CSR_MSTATUS_Path statusValue;
        caseName = "CFI CSR masks and aliases";
        Reset();
        foreach (numbers[i]) begin
            WriteCSR(numbers[i], '1);
            ReadCSR(numbers[i], CFI_ENABLED ? masks[i] : 0);
            WriteCSR(numbers[i], '1, CSR_CLEAR);
            ReadCSR(numbers[i], 0);
            WriteCSR(numbers[i], '1, CSR_SET);
            ReadCSR(numbers[i], CFI_ENABLED ? masks[i] : 0);
            cfiCases++;
        end
        WriteCSR(CSR_NUM_MSECCFGH, '1);
        ReadCSR(CSR_NUM_MSECCFGH, 0);
        WriteCSR(CSR_NUM_MENVCFGH, '1);
        ReadCSR(CSR_NUM_MENVCFGH, 0);
        WriteCSR(CSR_NUM_MSTATUS, 8);
        WriteCSR(CSR_NUM_SSTATUS, 32'h800000, CSR_SET);
        ReadCSR(CSR_NUM_MSTATUS, CFI_ENABLED ? 32'h800008 : 8);
        ReadCSR(CSR_NUM_SSTATUS, CFI_ENABLED ? 32'h800000 : 0);
        WriteCSR(CSR_NUM_MSTATUS, 32'h800000, CSR_CLEAR);
        ReadCSR(CSR_NUM_SSTATUS, 0);
        WriteCSR(CSR_NUM_MSTATUS, 32'h800008);
        WriteCSR(CSR_NUM_SSTATUS, 32'h800000, CSR_CLEAR);
        ReadCSR(CSR_NUM_MSTATUS, 8);

        // With S disabled, MENVCFG.LPE controls U directly.
        for (int enabled = 0; enabled < 2; enabled++) begin
            caseName = $sformatf("CFI U without S, LPE=%0d", enabled);
            Reset();
            ConfigureLPE(enabled ? 3'b110 : 3'b101);
            WriteCSR(CSR_NUM_MISA, 32'h40000, CSR_CLEAR);
            statusValue = '0;
            statusValue.MPP = PRIVILEGE_LEVEL_U;
            WriteCSR(CSR_NUM_MSTATUS, statusValue);
            WriteCSR(CSR_NUM_MSTATUSH, 32'h200);
            csr.excptCause = EXEC_STATE_TRAP_MRET;
            #1;
            assert (csr.recoverELP_FromCSR === ELP_State_Type'(CFI_ENABLED && enabled))
                else $fatal(1, "MRET used the wrong U-mode LPE (%s)", caseName);
            csr.triggerExcpt = 1;
            Tick();
            csr.triggerExcpt = 0;
            assert (csr.xLPE === (CFI_ENABLED && 1'(enabled)))
                else $fatal(1, "Wrong U-mode LPE without S (%s)", caseName);
            cfiCases++;
        end
    endtask

    task automatic CheckCFIPermissions;
        CSR_NumberPath numbers[6] = '{CSR_NUM_MSTATUSH, CSR_NUM_MSECCFG, CSR_NUM_MSECCFGH,
                                      CSR_NUM_MENVCFG, CSR_NUM_MENVCFGH, CSR_NUM_SENVCFG};
        CSR_BodyPath beforeAccess;
        for (int supervisor = 0; supervisor < 2; supervisor++) begin
            caseName = $sformatf("CFI CSR access from S=%0d", supervisor);
            Reset();
            ConfigureLPE(3'b111);
            WriteCSR(CSR_NUM_MSTATUS, supervisor ? 32'h800 : 0);
            csr.triggerExcpt = 1;
            Tick();
            csr.triggerExcpt = 0;
            beforeAccess = csr.csrWholeOut;
            foreach (numbers[i]) begin
                if (supervisor != 0 && numbers[i] == CSR_NUM_SENVCFG) begin
                    WriteCSR(CSR_NUM_SENVCFG, 0);
                    ReadCSR(CSR_NUM_SENVCFG, 0);
                    WriteCSR(CSR_NUM_SENVCFG, '1);
                    ReadCSR(CSR_NUM_SENVCFG, CFI_ENABLED ? 4 : 0);
                end
                else begin
                    csr.csrNumber = numbers[i];
                    csr.csrCode = CSR_CLEAR;
                    csr.csrWriteIn = '1;
                    csr.csrRE = 1;
                    csr.csrWE = 1;
                    #1;
                    assert (csr.csrUnitTriggerExcpt === 1'b1)
                        else $fatal(1, "Forbidden CFI CSR %03x did not trap (%s)", numbers[i], caseName);
                    Tick();
                    csr.csrRE = 0;
                    csr.csrWE = 0;
                    assert ({csr.csrWholeOut.mseccfg, csr.csrWholeOut.menvcfg,
                             csr.csrWholeOut.senvcfg, csr.csrWholeOut.mstatush} ===
                            {beforeAccess.mseccfg, beforeAccess.menvcfg,
                             beforeAccess.senvcfg, beforeAccess.mstatush})
                        else $fatal(1, "Forbidden access changed CFI state (%s)", caseName);
                end
                cfiCases++;
            end
        end
    endtask

    task automatic CheckCFINestedInterrupts;
        caseName = "CFI U to S to M nested interrupts";
        Reset();
        ConfigureLPE(3'b001); // Only the interrupted U program enables LPADs.
        WriteCSR(CSR_NUM_MIDELEG, 2);
        WriteCSR(CSR_NUM_MIE, 32'ha);
        WriteCSR(CSR_NUM_MIP, 2);
        WriteCSR(CSR_NUM_MSTATUS, 32'h82); // MRET to U; MIE/SIE enabled.
        csr.triggerExcpt = 1;
        Tick();
        csr.triggerExcpt = 0;
        decodeStage.elpState = LP_EXPECTED;
        ctrl.wholePipelineEmpty = 1;
        Tick();
        ctrl.wholePipelineEmpty = 0;
        decodeStage.elpState = LP_NOT_EXPECTED;
        assert (csr.privilegeLevel === PRIVILEGE_LEVEL_S &&
                csr.csrWholeOut.mstatus.SPELP === EXPECTED_ELP && csr.xLPE === 1'b0)
            else $fatal(1, "First nested trap lost U ELP");

        csr.msip = 1;
        Tick();
        ctrl.wholePipelineEmpty = 1;
        Tick();
        ctrl.wholePipelineEmpty = 0;
        assert (csr.privilegeLevel === PRIVILEGE_LEVEL_M &&
                csr.csrWholeOut.mstatush.MPELP === LP_NOT_EXPECTED &&
                csr.csrWholeOut.mstatus.SPELP === EXPECTED_ELP)
            else $fatal(1, "Nested M trap changed S saved ELP");
        csr.msip = 0;
        Tick();
        csr.excptCause = EXEC_STATE_TRAP_MRET;
        #1;
        assert (csr.recoverELP_FromCSR === LP_NOT_EXPECTED)
            else $fatal(1, "MRET restored the wrong nested ELP");
        csr.triggerExcpt = 1;
        Tick();
        csr.triggerExcpt = 0;
        assert (csr.privilegeLevel === PRIVILEGE_LEVEL_S &&
                csr.csrWholeOut.mstatus.SPELP === EXPECTED_ELP)
            else $fatal(1, "MRET corrupted the S return bank");
        csr.excptCause = EXEC_STATE_TRAP_SRET;
        #1;
        assert (csr.recoverELP_FromCSR === EXPECTED_ELP)
            else $fatal(1, "SRET did not restore the interrupted U ELP");
        csr.triggerExcpt = 1;
        Tick();
        csr.triggerExcpt = 0;
        assert (csr.privilegeLevel === PRIVILEGE_LEVEL_U && csr.xLPE === CFI_ENABLED &&
                csr.csrWholeOut.mstatus.SPELP === LP_NOT_EXPECTED)
            else $fatal(1, "Nested return did not clear SPELP");
        cfiCases++;
    endtask

    task automatic CheckCFIReturn(input bit supervisorReturn, fromSupervisor,
                                  input PrivilegeLevelType destination,
                                  input logic [2:0] enables, input bit savedELP);
        CSR_MSTATUS_Path statusValue;
        CSR_BodyPath beforeReturn;
        ELP_State_Type expectedELP;
        caseName = $sformatf("CFI return SRET=%0b fromS=%0b dest=%0d enables=%03b saved=%0b",
                            supervisorReturn, fromSupervisor, destination, enables, savedELP);
        Reset();
        ConfigureLPE(enables);
        WriteCSR(CSR_NUM_MEPC, RETURN_PC);
        WriteCSR(CSR_NUM_SEPC, RETURN_PC);
        statusValue = '0;
        statusValue.MPP = fromSupervisor ? PRIVILEGE_LEVEL_S : destination;
        statusValue.SPP = destination == PRIVILEGE_LEVEL_S;
        statusValue.SPELP = supervisorReturn ? ELP_State_Type'(savedELP) : LP_EXPECTED;
        WriteCSR(CSR_NUM_MSTATUS, statusValue);
        WriteCSR(CSR_NUM_MSTATUSH, supervisorReturn ? 32'h200 : DataPath'(savedELP) << 9);
        if (fromSupervisor) begin
            csr.triggerExcpt = 1; // MRET enters S, preserving the S return bank.
            Tick();
            csr.triggerExcpt = 0;
        end
        beforeReturn = csr.csrWholeOut;
        csr.excptCause = supervisorReturn ? EXEC_STATE_TRAP_SRET : EXEC_STATE_TRAP_MRET;
        expectedELP = ELP_State_Type'(savedELP && ExpectedLPE(destination, enables));
        #1;
        // Recovery must see the return value before triggerExcpt is asserted.
        assert (csr.recoverELP_FromCSR === expectedELP && csr.excptTargetAddr === RETURN_PC)
            else $fatal(1, "Wrong combinational CFI return state (%s)", caseName);
        csr.triggerExcpt = 1;
        Tick();
        csr.triggerExcpt = 0;
        assert (csr.privilegeLevel === destination &&
                csr.xLPE === ExpectedLPE(destination, enables))
            else $fatal(1, "Wrong return privilege/LPE (%s)", caseName);
        if (supervisorReturn)
            assert (csr.csrWholeOut.mstatus.SPELP === LP_NOT_EXPECTED &&
                    csr.csrWholeOut.mstatush.MPELP === beforeReturn.mstatush.MPELP)
                else $fatal(1, "SRET changed the wrong saved ELP bank (%s)", caseName);
        else
            assert (csr.csrWholeOut.mstatush.MPELP === LP_NOT_EXPECTED &&
                    csr.csrWholeOut.mstatus.SPELP === beforeReturn.mstatus.SPELP)
                else $fatal(1, "MRET changed the wrong saved ELP bank (%s)", caseName);
        cfiCases++;
    endtask

    task automatic CheckCFITrap(input PrivilegeLevelType origin, input bit toSupervisor,
                                input int eventKind, input logic [2:0] enables,
                                input ELP_State_Type elp);
        CSR_MSTATUS_Path statusValue;
        CSR_BodyPath beforeTrap;
        PrivilegeLevelType destination;
        DataPath expectedValue, expectedCause;
        destination = toSupervisor ? PRIVILEGE_LEVEL_S : PRIVILEGE_LEVEL_M;
        caseName = $sformatf("CFI trap origin=%0d dest=%0d event=%0d enables=%03b ELP=%0b",
                            origin, destination, eventKind, enables, elp);
        Reset();
        ConfigureLPE(enables);
        WriteCSR(CSR_NUM_MIDELEG, toSupervisor ? 2 : 0);
        WriteCSR(CSR_NUM_MEDELEG, toSupervisor ? 32'h40002 : 0);
        WriteCSR(CSR_NUM_MIE, 2);
        WriteCSR(CSR_NUM_MIP, eventKind == 0 ? 2 : 0);
        statusValue = '0;
        statusValue.MPP = origin;
        statusValue.MIE = 1;
        statusValue.MPIE = 1;
        statusValue.SIE = 1;
        statusValue.SPELP = LP_EXPECTED;
        WriteCSR(CSR_NUM_MSTATUS, statusValue);
        WriteCSR(CSR_NUM_MSTATUSH, 32'h200);
        if (origin != PRIVILEGE_LEVEL_M) begin
            csr.triggerExcpt = 1;
            Tick();
            csr.triggerExcpt = 0;
        end
        assert (csr.xLPE === ExpectedLPE(origin, enables))
            else $fatal(1, "Wrong source privilege LPE (%s)", caseName);
        beforeTrap = csr.csrWholeOut;
        csr.excptCause = eventKind == 2 ? EXEC_STATE_FAULT_LPAD : EXEC_STATE_FAULT_INSN_VIOLATION;
        csr.excptCauseAddr = ToPC_FromAddr(RETURN_PC);
        csr.excptCauseDataAddr = 32'hbad0;
        csr.excptELP = elp;
        decodeStage.elpState = elp;
        #1;
        assert (csr.recoverELP_FromCSR === LP_NOT_EXPECTED)
            else $fatal(1, "Trap handler inherited ELP (%s)", caseName);
        if (eventKind == 0) begin
            ctrl.wholePipelineEmpty = 1;
            #1;
            assert (csr.triggerInterrupt === 1'b1 && decodeStage.setELP_OnInterrupt === 1'b1 &&
                    csr.interruptELP === elp)
                else $fatal(1, "Interrupt lost the precise ELP (%s)", caseName);
        end
        else
            csr.triggerExcpt = 1;
        Tick();
        ctrl.wholePipelineEmpty = 0;
        csr.triggerExcpt = 0;
        decodeStage.elpState = LP_NOT_EXPECTED;
        expectedCause = eventKind == 0 ? 32'h80000001 : eventKind == 2 ? 18 : 1;
        expectedValue = eventKind == 0 ? 0 : eventKind == 2 ? 2 : 32'hbad0;
        assert (csr.privilegeLevel === destination && csr.xLPE === ExpectedLPE(destination, enables))
            else $fatal(1, "Wrong CFI handler privilege/LPE (%s)", caseName);
        if (toSupervisor)
            assert (csr.csrWholeOut.mstatus.SPELP === (CFI_ENABLED ? elp : LP_NOT_EXPECTED) &&
                    csr.csrWholeOut.mstatush.MPELP === beforeTrap.mstatush.MPELP &&
                    DataPath'(csr.csrWholeOut.scause) === expectedCause &&
                    csr.csrWholeOut.stval === expectedValue && csr.csrWholeOut.sepc === RETURN_PC)
                else $fatal(1, "Wrong supervisor CFI trap state (%s)", caseName);
        else
            assert (csr.csrWholeOut.mstatush.MPELP === (CFI_ENABLED ? elp : LP_NOT_EXPECTED) &&
                    csr.csrWholeOut.mstatus.SPELP === beforeTrap.mstatus.SPELP &&
                    DataPath'(csr.csrWholeOut.mcause) === expectedCause &&
                    csr.csrWholeOut.mtval === expectedValue && csr.csrWholeOut.mepc === RETURN_PC)
                else $fatal(1, "Wrong machine CFI trap state (%s)", caseName);
        cfiCases++;
    endtask

    task automatic CheckCase(input DataPath pending, enabled, delegated,
                             input bit vectorMode, machineEnable, supervisorEnable,
                             input PrivilegeLevelType origin);
        DataPath eligibleM, eligibleS;
        bit expectedRequest, toSupervisor;
        int expectedCode;
        AddrPath expectedTarget;
        CSR_BodyPath beforeTrap;
        CSR_MSTATUS_Path statusValue;
        caseName = $sformatf("pending=%03x enabled=%03x delegated=%03x vector=%0b MIE=%0b SIE=%0b mode=%0d",
                            pending, enabled, delegated, vectorMode, machineEnable, supervisorEnable, origin);
        Reset();
        WriteCSR(CSR_NUM_MTVEC, VECTOR_BASE | DataPath'(vectorMode));
        WriteCSR(CSR_NUM_STVEC, SUPERVISOR_VECTOR_BASE | DataPath'(vectorMode));
        WriteCSR(CSR_NUM_MIE, enabled);
        WriteCSR(CSR_NUM_MIDELEG, delegated);
        WriteCSR(CSR_NUM_MTVAL, 32'hdeadbeef);
        WriteCSR(CSR_NUM_STVAL, 32'hcafef00d);
        // Distinct nonzero values detect clearing the untouched trap bank.
        WriteCSR(CSR_NUM_MEPC, 32'h80005430);
        WriteCSR(CSR_NUM_SEPC, 32'h80004320);
        WriteCSR(CSR_NUM_MCAUSE, 1);
        WriteCSR(CSR_NUM_SCAUSE, 5);
        // Software supplies custom/STIP/SSIP; external requests use the PLIC.
        WriteCSR(CSR_NUM_MIP, pending & 32'hffff0022);
        statusValue = '0;
        statusValue.MPP = origin;
        statusValue.MIE = machineEnable;
        statusValue.MPIE = machineEnable;
        statusValue.SIE = supervisorEnable;
        WriteCSR(CSR_NUM_MSTATUS, statusValue);
        if (origin != PRIVILEGE_LEVEL_M) begin
            csr.triggerExcpt = 1;
            Tick();
            csr.triggerExcpt = 0;
        end
        assert (csr.privilegeLevel === origin)
            else $fatal(1, "Wrong initial privilege (%s)", caseName);

        // Each PLIC context feeds its own external-interrupt pending bit.
        WritePLIC(PHY_ADDR_PLIC_SOURCE_PRIORITY_BASE + 4, 1);
        WritePLIC(PHY_ADDR_PLIC_ENABLE_BASE, pending[11] ? 2 : 0);
        WritePLIC(PHY_ADDR_PLIC_ENABLE_BASE + 'h80, pending[9] ? 2 : 0);
        WritePLIC(PHY_ADDR_PLIC_PRIORITY_THRESHOLD_BASE, 0);
        WritePLIC(PHY_ADDR_PLIC_PRIORITY_THRESHOLD_BASE + 'h1000, 0);
        plic.interruptReqFromInterruptSource[1] = pending[11] || pending[9];
        csr.msip = pending[3];
        csr.reqTimerInterrupt = pending[7];
        repeat (3) Tick();
        assert ((csr.csrWholeOut.mip & ALL_INTERRUPTS) === pending)
            else $fatal(1, "Pending input did not reach mip (%s)", caseName);

        // Choose the destination privilege first, then the source priority.
        eligibleM = (origin != PRIVILEGE_LEVEL_M || machineEnable) ?
            pending & enabled & ~delegated : '0;
        eligibleS = (origin == PRIVILEGE_LEVEL_U ||
                     (origin == PRIVILEGE_LEVEL_S && supervisorEnable)) ?
            pending & enabled & delegated : '0;
        expectedRequest = (eligibleM | eligibleS) != 0;
        toSupervisor = eligibleM == 0 && eligibleS != 0;
        expectedCode = PriorityCode(toSupervisor ? eligibleS : eligibleM);
        expectedTarget = (toSupervisor ? SUPERVISOR_VECTOR_BASE : VECTOR_BASE) +
                         (vectorMode ? 4 * expectedCode : 0);
        beforeTrap = csr.csrWholeOut;
        assert (ctrl.npStageSendBubbleLowerForInterrupt === expectedRequest)
            else $fatal(1, "Wrong fetch stop request (%s)", caseName);

        // Neither a nonempty pipeline nor a concurrent recovery may take a trap.
        for (int blocked = 0; blocked < 2; blocked++) begin
            ctrl.wholePipelineEmpty = (blocked == 1);
            recovery.unableToStartRecovery = (blocked == 1);
            #1;
            assert (csr.triggerInterrupt === 1'b0 && fetchStage.interruptAddrWE === 1'b0)
                else $fatal(1, "Interrupt entered before recovery was safe (%s)", caseName);
            Tick();
            CheckTrapState(beforeTrap);
            assert (csr.privilegeLevel === origin)
                else $fatal(1, "Blocked interrupt changed privilege (%s)", caseName);
        end

        recovery.unableToStartRecovery = 0;
        #1;
        assert (csr.triggerInterrupt === expectedRequest &&
                fetchStage.interruptAddrWE === expectedRequest)
            else $fatal(1, "Wrong interrupt trigger (%s)", caseName);
        if (expectedRequest) begin
            assert (csr.interruptCode === CSR_CAUSE_InterruptCodePath'(expectedCode) &&
                    ToAddrFromPC(fetchStage.interruptAddrIn) === expectedTarget)
                else $fatal(1, "Expected interrupt %0d at %08x, got %0d at %08x (%s)",
                            expectedCode, expectedTarget, csr.interruptCode,
                            ToAddrFromPC(fetchStage.interruptAddrIn), caseName);
        end
        Tick();
        if (expectedRequest) begin
            if (toSupervisor) begin
                assert (csr.csrWholeOut.scause.isInterrupt === 1'b1 &&
                        csr.csrWholeOut.scause.code.interruptCode === CSR_CAUSE_InterruptCodePath'(expectedCode) &&
                        csr.csrWholeOut.sepc === RETURN_PC && csr.csrWholeOut.stval === DataPath'(0) &&
                        csr.privilegeLevel === PRIVILEGE_LEVEL_S &&
                        csr.csrWholeOut.mstatus.SPP === (origin == PRIVILEGE_LEVEL_S) &&
                        csr.csrWholeOut.mstatus.SPIE === supervisorEnable && csr.csrWholeOut.mstatus.SIE === 1'b0 &&
                        csr.csrWholeOut.mstatus.MIE === beforeTrap.mstatus.MIE &&
                        csr.csrWholeOut.mstatus.MPIE === beforeTrap.mstatus.MPIE &&
                        csr.csrWholeOut.mstatus.MPP === beforeTrap.mstatus.MPP)
                    else $fatal(1, "Wrong supervisor entry state (%s)", caseName);
            end
            else begin
                assert (csr.csrWholeOut.mcause.isInterrupt === 1'b1 &&
                        csr.csrWholeOut.mcause.code.interruptCode === CSR_CAUSE_InterruptCodePath'(expectedCode) &&
                        csr.csrWholeOut.mepc === RETURN_PC && csr.csrWholeOut.mtval === DataPath'(0) &&
                        csr.privilegeLevel === PRIVILEGE_LEVEL_M &&
                        csr.csrWholeOut.mstatus.MPP === origin &&
                        csr.csrWholeOut.mstatus.MPIE === machineEnable && csr.csrWholeOut.mstatus.MIE === 1'b0 &&
                        csr.csrWholeOut.mstatus.SIE === beforeTrap.mstatus.SIE &&
                        csr.csrWholeOut.mstatus.SPIE === beforeTrap.mstatus.SPIE &&
                        csr.csrWholeOut.mstatus.SPP === beforeTrap.mstatus.SPP)
                    else $fatal(1, "Wrong machine entry state (%s)", caseName);
            end
            assert (csr.triggerInterrupt === 1'b0)
                else $fatal(1, "Interrupt repeated while global enable was clear (%s)", caseName);
        end
        else begin
            CheckTrapState(beforeTrap);
            assert (csr.privilegeLevel === origin)
                else $fatal(1, "Masked interrupt changed privilege (%s)", caseName);
        end
        if (!expectedRequest || toSupervisor)
            assert ({csr.csrWholeOut.mepc, csr.csrWholeOut.mcause, csr.csrWholeOut.mtval} ===
                    {beforeTrap.mepc, beforeTrap.mcause, beforeTrap.mtval})
                else $fatal(1, "Unexpected machine trap bank update (%s)", caseName);
        if (!expectedRequest || !toSupervisor)
            assert ({csr.csrWholeOut.sepc, csr.csrWholeOut.scause, csr.csrWholeOut.stval} ===
                    {beforeTrap.sepc, beforeTrap.scause, beforeTrap.stval})
                else $fatal(1, "Unexpected supervisor trap bank update (%s)", caseName);
        // Taking one interrupt must not discard another pending source.
        assert ((csr.csrWholeOut.mip & ALL_INTERRUPTS) === pending)
            else $fatal(1, "Interrupt entry lost pending sources (%s)", caseName);
        if (expectedRequest) begin
            ctrl.wholePipelineEmpty = 0;
            csr.excptCause = toSupervisor ? EXEC_STATE_TRAP_SRET : EXEC_STATE_TRAP_MRET;
            csr.triggerExcpt = 1;
            #1;
            assert (csr.excptTargetAddr === RETURN_PC)
                else $fatal(1, "Wrong xRET target (%s)", caseName);
            Tick();
            csr.triggerExcpt = 0;
            #1;
            assert (csr.privilegeLevel === origin &&
                    csr.csrWholeOut.mstatus.MIE === machineEnable &&
                    csr.csrWholeOut.mstatus.SIE === supervisorEnable &&
                    ctrl.npStageSendBubbleLowerForInterrupt === 1'b1 &&
                    (csr.csrWholeOut.mip & ALL_INTERRUPTS) === pending &&
                    csr.interruptCode === CSR_CAUSE_InterruptCodePath'(expectedCode) &&
                    ToAddrFromPC(fetchStage.interruptAddrIn) === expectedTarget)
                else $fatal(1, "xRET did not restore privilege/enables/pending request (%s)", caseName);
            if (toSupervisor)
                assert (csr.csrWholeOut.mstatus.SPIE === 1'b1 && csr.csrWholeOut.mstatus.SPP === 1'b0)
                    else $fatal(1, "Wrong SRET status stack (%s)", caseName);
            else
                assert (csr.csrWholeOut.mstatus.MPIE === 1'b1 && csr.csrWholeOut.mstatus.MPP === PRIVILEGE_LEVEL_U)
                    else $fatal(1, "Wrong MRET status stack (%s)", caseName);
        end
        cases++;
    endtask

    initial begin
        static DataPath customPending[6] = '{32'h00010080, 32'h80000800,
                                     32'h80010000, 32'h80010000, 32'h80010000, 32'h80010000};
        static DataPath customDelegated[6] = '{32'h00010000, 32'h80000000,
                                       32'h80000000, 32'h00010000, 32'h80010000, 32'h0};
        CheckSupervisorAlias(0);
        CheckSupervisorAlias(1);
        CheckSIE();
        CheckSupervisorAlias(2);
        CheckSIP();
        CheckCFICSR();
        CheckCFIPermissions();
        CheckCFINestedInterrupts();
        for (int mode = 0; mode < 3; mode++)
            for (int enables = 0; enables < 8; enables++)
                for (int elp = 0; elp < 2; elp++) begin
                    CheckCFIReturn(0, 0, mode == 2 ? PRIVILEGE_LEVEL_M : PrivilegeLevelType'(mode),
                                   3'(enables), 1'(elp));
                    if (mode != 2) begin
                        CheckCFIReturn(1, 0, PrivilegeLevelType'(mode), 3'(enables), 1'(elp));
                        CheckCFIReturn(1, 1, PrivilegeLevelType'(mode), 3'(enables), 1'(elp));
                    end
                    if (!CFI_ENABLED || elp == 0 || ExpectedLPE(mode == 2 ? PRIVILEGE_LEVEL_M : PrivilegeLevelType'(mode), 3'(enables)))
                        for (int destination = 0; destination < (mode == 2 ? 1 : 2); destination++)
                            for (int eventKind = 0; eventKind < (CFI_ENABLED ? 3 : 2); eventKind++)
                                CheckCFITrap(mode == 2 ? PRIVILEGE_LEVEL_M : PrivilegeLevelType'(mode),
                                             1'(destination), eventKind, 3'(enables), ELP_State_Type'(elp));
                end
        for (int mode = 0; mode < 3; mode++)
            for (int vectorMode = 0; vectorMode < 2; vectorMode++)
                for (int mie = 0; mie < 2; mie++)
                    for (int sie = 0; sie < 2; sie++) begin
                        for (int pending = 0; pending < 8; pending++)
                            for (int enabled = 0; enabled < 8; enabled++) begin
                                CheckCase(InterruptBits(3'(pending)), InterruptBits(3'(enabled)), 0,
                                          1'(vectorMode), 1'(mie), 1'(sie),
                                          mode == 2 ? PRIVILEGE_LEVEL_M : PrivilegeLevelType'(mode));
                                for (int delegated = 0; delegated < 8; delegated++)
                                    CheckCase(InterruptBits(3'(pending), 1), InterruptBits(3'(enabled), 1),
                                              InterruptBits(3'(delegated), 1),
                                              1'(vectorMode), 1'(mie), 1'(sie),
                                              mode == 2 ? PRIVILEGE_LEVEL_M : PrivilegeLevelType'(mode));
                            end
                        // Both destination levels can be eligible simultaneously.
                        for (int m = 0; m < 3; m++)
                            for (int s = 0; s < 3; s++)
                                for (int enabled = 0; enabled < 4; enabled++)
                                    CheckCase(InterruptBits(3'b1 << m) | InterruptBits(3'b1 << s, 1),
                                              (enabled[0] ? InterruptBits(3'b1 << m) : 0) |
                                              (enabled[1] ? InterruptBits(3'b1 << s, 1) : 0),
                                              SUPERVISOR_INTERRUPTS, 1'(vectorMode), 1'(mie), 1'(sie),
                                              mode == 2 ? PRIVILEGE_LEVEL_M : PrivilegeLevelType'(mode));
                        // A delegated custom source must not override an M target.
                        // Same-level custom sources still prefer the highest code.
                        foreach (customPending[i])
                            CheckCase(customPending[i], customPending[i], customDelegated[i],
                                      1'(vectorMode), 1'(mie), 1'(sie),
                                      mode == 2 ? PRIVILEGE_LEVEL_M : PrivilegeLevelType'(mode));
                    end
        $display("Interrupt priority/mask/entry: %0d cases passed", cases);
        $display("CSR alias: %0d cases passed", aliasCases);
        $display("CFI CSR/trap/return: %0d cases passed (Zicfilp=%0b)", cfiCases, CFI_ENABLED);
        $display("========== Test Passed ==========");
        $finish;
    end

    initial begin
        #10000000;
        $fatal(1, "Interrupt controller test timed out (%s)", caseName);
    end
endmodule
