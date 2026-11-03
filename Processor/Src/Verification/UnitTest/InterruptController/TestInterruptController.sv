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
    localparam AddrPath VECTOR_BASE = 32'h80000100;
    localparam AddrPath RETURN_PC = 32'h80001234;
    localparam DataPath MACHINE_INTERRUPTS = 32'h00000888;
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
    RecoveryManagerIF recovery(.*);
    PLIC_Unit plicUnit(plic, csr, ioPort);
    CSR_Unit csrUnit(csr, plic, perf);
    InterruptController interruptCtrl(csr, ctrl, fetchStage, recovery);

    int cases = 0;
    string caseName;

    // Keep stimulus and checks away from the active edge in both simulators.
    task automatic Tick;
        #4; clk = 1;
        #1; clk = 0;
        #1;
    endtask

    // The test mask is {external, software, timer}, in descending priority.
    function automatic DataPath InterruptBits(input logic [2:0] mask);
        return (DataPath'(mask[2]) << 11) |
               (DataPath'(mask[1]) << 3) | (DataPath'(mask[0]) << 7);
    endfunction

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

    task automatic WriteCSR(input CSR_NumberPath number, input DataPath value);
        csr.csrNumber = number;
        csr.csrWriteIn = value;
        csr.csrWE = 1;
        #1;
        assert (csr.csrUnitTriggerExcpt === 1'b0)
            else $fatal(1, "Unexpected CSR exception: %03x (%s)", number, caseName);
        Tick();
        csr.csrWE = 0;
        #1;
    endtask

    task automatic WritePLIC(input PhyRawAddrPath address, input DataPath value);
        plic.phyRawWriteAddrIn = PhyAddrPath'(address);
        plic.ioWriteDataIn = value;
        plic.ioWE = 1;
        Tick();
        plic.ioWE = 0;
        #1;
    endtask

    task automatic CheckCase(input logic [2:0] pending, enabled,
                             input bit vectorMode, globalEnable, fromUser);
        logic [2:0] eligible;
        bit expectedRequest;
        int expectedCode;
        AddrPath expectedTarget;
        CSR_BodyPath beforeTrap;
        caseName = $sformatf("pending=%03b enabled=%03b vector=%0b MIE=%0b U=%0b",
                            pending, enabled, vectorMode, globalEnable, fromUser);
        Reset();
        WriteCSR(CSR_NUM_MTVEC, VECTOR_BASE | DataPath'(vectorMode));
        WriteCSR(CSR_NUM_MIE, InterruptBits(enabled));
        WriteCSR(CSR_NUM_MTVAL, 32'hdeadbeef);
        // MRET enters U mode with the requested MIE value restored from MPIE.
        WriteCSR(CSR_NUM_MSTATUS, DataPath'(globalEnable) << (fromUser ? 7 : 3));
        if (fromUser) begin
            csr.triggerExcpt = 1;
            Tick();
            csr.triggerExcpt = 0;
        end
        assert (csr.privilegeLevel === (fromUser ? PRIVILEGE_LEVEL_U : PRIVILEGE_LEVEL_M))
            else $fatal(1, "Wrong initial privilege (%s)", caseName);

        // Exercise the real PLIC source/pending/enable path, not a forced mip.
        WritePLIC(PHY_ADDR_PLIC_SOURCE_PRIORITY_BASE + 4, 1);
        WritePLIC(PHY_ADDR_PLIC_ENABLE_BASE, 2);
        WritePLIC(PHY_ADDR_PLIC_PRIORITY_THRESHOLD_BASE, 0);
        plic.interruptReqFromInterruptSource[1] = pending[2];
        csr.msip = pending[1];
        csr.reqTimerInterrupt = pending[0];
        repeat (3) Tick();
        assert ((csr.csrWholeOut.mip & MACHINE_INTERRUPTS) === InterruptBits(pending))
            else $fatal(1, "Pending input did not reach mip (%s)", caseName);

        eligible = pending & enabled;
        expectedRequest = (eligible != 0) && (fromUser || globalEnable);
        expectedCode = eligible[2] ? 11 : eligible[1] ? 3 : 7;
        expectedTarget = VECTOR_BASE + (vectorMode ? 4 * expectedCode : 0);
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
            assert (csr.csrWholeOut.mcause === beforeTrap.mcause &&
                    csr.csrWholeOut.mepc === beforeTrap.mepc &&
                    csr.csrWholeOut.mtval === beforeTrap.mtval &&
                    csr.csrWholeOut.mstatus === beforeTrap.mstatus)
                else $fatal(1, "Blocked interrupt changed trap state (%s)", caseName);
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
            assert (csr.csrWholeOut.mcause.isInterrupt === 1'b1 &&
                    csr.csrWholeOut.mcause.code.interruptCode === CSR_CAUSE_InterruptCodePath'(expectedCode) &&
                    csr.csrWholeOut.mepc === RETURN_PC && csr.csrWholeOut.mtval === DataPath'(0) &&
                    csr.privilegeLevel === PRIVILEGE_LEVEL_M &&
                    csr.csrWholeOut.mstatus.MPP === (fromUser ? PRIVILEGE_LEVEL_U : PRIVILEGE_LEVEL_M) &&
                    csr.csrWholeOut.mstatus.MPIE === globalEnable && csr.csrWholeOut.mstatus.MIE === 1'b0)
                else $fatal(1, "Wrong interrupt entry state (%s)", caseName);
            assert (csr.triggerInterrupt === 1'b0)
                else $fatal(1, "Interrupt repeated while MIE was clear (%s)", caseName);
        end
        else begin
            assert (csr.csrWholeOut.mcause === beforeTrap.mcause &&
                    csr.csrWholeOut.mepc === beforeTrap.mepc &&
                    csr.csrWholeOut.mtval === beforeTrap.mtval &&
                    csr.csrWholeOut.mstatus === beforeTrap.mstatus)
                else $fatal(1, "Masked interrupt changed trap state (%s)", caseName);
        end
        // Taking one interrupt must not discard another pending source.
        assert ((csr.csrWholeOut.mip & MACHINE_INTERRUPTS) === InterruptBits(pending))
            else $fatal(1, "Interrupt entry lost pending sources (%s)", caseName);
        cases++;
    endtask

    initial begin
        for (int mode = 0; mode < 2; mode++)
            for (int vectorMode = 0; vectorMode < 2; vectorMode++)
                for (int mie = 0; mie < 2; mie++)
                    for (int pending = 0; pending < 8; pending++)
                        for (int enabled = 0; enabled < 8; enabled++)
                            CheckCase(3'(pending), 3'(enabled), 1'(vectorMode), 1'(mie), 1'(mode));
        $display("Interrupt priority/mask/entry: %0d cases passed", cases);
        $display("========== Test Passed ==========");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Interrupt controller test timed out (%s)", caseName);
    end
endmodule
