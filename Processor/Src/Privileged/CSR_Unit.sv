// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// CSR Unit
//

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import CSR_UnitTypes::*;
import OpFormatTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;

module CSR_Unit(
    CSR_UnitIF.CSR_Unit port,
    PerformanceCounterIF.CSR perfCounter
);

    CSR_BodyPath csrReg, csrNext;
    DataPath rv;
    CSR_ValuePath wv;
    DataPath mcycle;    // for debug
    AddrPath jumpTarget;
    CommitLaneCountPath regCommitNum;

    PrivilegeLevelType privilegeLevel, privilegeLevelNext;

    function automatic CSR_BodyPath GetCSRResetValue();
        CSR_BodyPath value;
        value = '0;
        value.misa.MXL = ENCODED_XLEN_32;
        value.misa.EXTENSIONS.I = 1;
        value.misa.EXTENSIONS.M = 1;
        value.misa.EXTENSIONS.F = 1;
        value.misa.EXTENSIONS.D = 1;
        value.misa.EXTENSIONS.U = 1;
        value.misa.EXTENSIONS.S = 1;
        return value;
    endfunction

    function logic IsSupportedPrivilegeLevel(
        input PrivilegeLevelType level,
        input CSR_MISA_Path misa,
    );
        return level == PRIVILEGE_LEVEL_M ||
               misa.EXTENSIONS.S && level == PRIVILEGE_LEVEL_S ||
               misa.EXTENSIONS.U && level == PRIVILEGE_LEVEL_U;
    endfunction

    always_ff@(posedge port.clk) begin
        if (port.rst) begin
            csrReg <= GetCSRResetValue();
            regCommitNum <= '0;
            privilegeLevel <= PRIVILEGE_LEVEL_M;
        end
        else begin
            csrReg <= csrNext;
            privilegeLevel <= privilegeLevelNext;
            regCommitNum <= port.commitNum;
            // if (privilegeLevel != privilegeLevelNext) begin
            //     $display("privilege level: %b -> %b", privilegeLevel, privilegeLevelNext);
            // end
        end
    end

    always_comb begin
        mcycle = csrReg.mcycle;

        privilegeLevelNext = privilegeLevel;

        // Read a CSR value
        unique case (port.csrNumber) 
            CSR_NUM_MSTATUS: begin
                CSR_MSTATUS_Path value;
                value = csrReg.mstatus;
                if (!csrReg.misa.EXTENSIONS.S) begin
                    value.TSR = '0;
                    value.TVM = '0;
                    value.MXR = '0;
                    value.SUM = '0;
                    value.SPP = '0;
                    value.SPIE= '0;
                    value.SIE = '0;
                end
                if (!csrReg.misa.EXTENSIONS.U) begin
                    value.MPRV = '0;
                    value.MPP = '0;
                end
                rv = value;
            end
            CSR_NUM_MIP:        rv = csrReg.mip;
            CSR_NUM_MIE:        rv = csrReg.mie;
            CSR_NUM_MCAUSE:     rv = csrReg.mcause;
            CSR_NUM_MTVEC:      rv = csrReg.mtvec;
            CSR_NUM_MTVAL:      rv = csrReg.mtval;
            CSR_NUM_MEPC:       rv = csrReg.mepc;
            CSR_NUM_MSCRATCH:   rv = csrReg.mscratch;

            CSR_NUM_MISA: rv = csrReg.misa;

            CSR_NUM_MCYCLE:   rv = csrReg.mcycle;
            CSR_NUM_MINSTRET: rv = csrReg.minstret;
`ifndef RSD_DISABLE_PERFORMANCE_COUNTER
            CSR_NUM_MHPMCOUNTER3: rv = perfCounter.perfCounter.numLoadMiss;
            CSR_NUM_MHPMCOUNTER4: rv = perfCounter.perfCounter.numStoreMiss;
            CSR_NUM_MHPMCOUNTER5: rv = perfCounter.perfCounter.numIC_Miss;
            CSR_NUM_MHPMCOUNTER6: rv = perfCounter.perfCounter.numBranchPredMiss;
`endif
`ifdef RSD_MARCH_FP_PIPE
            CSR_NUM_FFLAGS: rv = csrReg.fcsr.fflags;
            CSR_NUM_FRM:    rv = csrReg.fcsr.frm;
            CSR_NUM_FCSR:   rv = csrReg.fcsr;
`endif
            default: begin
                if (csrReg.misa.EXTENSIONS.S) begin
                    unique case (port.csrNumber)
                        CSR_NUM_SSTATUS:    rv = ToSstatusFromMstatus(csrReg.mstatus);
                        CSR_NUM_SIP:        rv = csrReg.mip & csrReg.mideleg;
                        CSR_NUM_SIE:        rv = csrReg.sie & csrReg.mideleg;
                        CSR_NUM_STVEC:      rv = csrReg.stvec;
                        CSR_NUM_SSCRATCH:   rv = csrReg.sscratch;
                        CSR_NUM_SEPC:       rv = csrReg.sepc;
                        CSR_NUM_SCAUSE:     rv = csrReg.scause;
                        CSR_NUM_STVAL:      rv = csrReg.stval;

                        CSR_NUM_MEDELEG:    rv = csrReg.medeleg;
                        CSR_NUM_MEDELEGH:   rv = csrReg.medelegh;
                        CSR_NUM_MIDELEG:    rv = csrReg.mideleg;
                        default: rv = '0;
                    endcase
                end
                else begin
                    rv = '0;
                end
            end
        endcase 

        // check csr read/write permission
        port.csrUnitTriggerExcpt = port.csrWE && privilegeLevel < port.csrNumber[9:8];

        // Writeback 
        csrNext = csrReg;

        // Update Cycles
        csrNext.mcycle = csrNext.mcycle + 1;
        csrNext.minstret = csrNext.minstret + regCommitNum;

        wv = '0;

        if (port.triggerInterrupt) begin
            // Interrupt
            if (privilegeLevel == PRIVILEGE_LEVEL_M || !csrReg.misa.EXTENSIONS.S || !csrReg.mideleg[port.interruptCode]) begin
                privilegeLevelNext = PRIVILEGE_LEVEL_M;
            end
            else begin
                privilegeLevelNext = PRIVILEGE_LEVEL_S;
            end

            if (privilegeLevelNext == PRIVILEGE_LEVEL_M) begin
                csrNext.mstatus.MPIE = csrNext.mstatus.MIE; // MIE の古い値
                csrNext.mstatus.MIE = 0; // グローバル割り込み許可を落とす
                csrNext.mstatus.MPP = privilegeLevel; // トラップ前の特権レベル
                csrNext.mepc = ToAddrFromPC(port.interruptRetAddr); // 割り込み発生時の PC
                csrNext.mtval = 0;
                csrNext.mcause.isInterrupt = TRUE;
                csrNext.mcause.code.interruptCode = port.interruptCode;
            end
            else if (privilegeLevelNext == PRIVILEGE_LEVEL_S) begin
                csrNext.mstatus.SPIE = csrNext.mstatus.SIE; // SIE の古い値
                csrNext.mstatus.SIE = 0; // グローバル割り込み許可を落とす
                csrNext.mstatus.SPP = ToSPP_FromPrivilegeLevel(privilegeLevel); // トラップ前の特権レベル
                csrNext.sepc = ToAddrFromPC(port.interruptRetAddr); // 割り込み発生時の PC
                csrNext.stval = 0;
                csrNext.scause.isInterrupt = TRUE;
                csrNext.scause.code.interruptCode = port.interruptCode;
            end
            //$display("int: from %x", port.interruptRetAddr);
        end
        else if (port.triggerExcpt) begin
            if (port.excptCause == EXEC_STATE_TRAP_MRET) begin
                // MRET
                privilegeLevelNext = csrReg.misa.EXTENSIONS.U ? csrReg.mstatus.MPP : PRIVILEGE_LEVEL_M;
                csrNext.mstatus.MIE = csrNext.mstatus.MPIE; // MIE の古い値に戻す
                csrNext.mstatus.MPIE = 1; // MPIE = 1
                csrNext.mstatus.MPP = PRIVILEGE_LEVEL_U; // 最小の特権レベル
                // > If y≠M, xRET also sets MPRV=0.
                if (privilegeLevelNext != PRIVILEGE_LEVEL_M) begin
                    csrNext.mstatus.MPRV = 0;
                end
            end
            else if (port.excptCause == EXEC_STATE_TRAP_SRET) begin
                // SRET
                privilegeLevelNext = ToPrivilegeLevelFromSPP(csrReg.mstatus.SPP);
                csrNext.mstatus.SIE = csrNext.mstatus.SPIE; // SIE の古い値に戻す
                csrNext.mstatus.SPIE = 1; // SPIE = 1
                csrNext.mstatus.SPP = ToSPP_FromPrivilegeLevel(PRIVILEGE_LEVEL_U); // 最小の特権レベル
                // > If y≠M, xRET also sets MPRV=0.
                if (privilegeLevelNext != PRIVILEGE_LEVEL_M) begin
                    csrNext.mstatus.MPRV = 0;
                end
            end
            else begin
                // Exception
                if (privilegeLevel == PRIVILEGE_LEVEL_M || !csrReg.misa.EXTENSIONS.S || !csrReg.medeleg[ToTrapCodeFromExecState(port.excptCause, privilegeLevel)]) begin
                    privilegeLevelNext = PRIVILEGE_LEVEL_M;
                end
                else begin
                    privilegeLevelNext = PRIVILEGE_LEVEL_S;
                end

                if (privilegeLevelNext == PRIVILEGE_LEVEL_M) begin
                    csrNext.mstatus.MPIE = csrNext.mstatus.MIE; // MIE の古い値
                    csrNext.mstatus.MIE = 0;    // グローバル割り込み許可を落とす
                    csrNext.mstatus.MPP = privilegeLevel; // トラップ前の特権レベル
                    csrNext.mepc = ToAddrFromPC(port.excptCauseAddr); // 例外の発生元 PC を書き込む
                    csrNext.mtval = port.excptCauseDataAddr;// ECALL/EBREAK の場合は PC?
                    csrNext.mcause.isInterrupt = FALSE;
                    csrNext.mcause.code.trapCode = ToTrapCodeFromExecState(port.excptCause, privilegeLevel);
                end
                else if (privilegeLevelNext == PRIVILEGE_LEVEL_S) begin
                    csrNext.mstatus.SPIE = csrNext.mstatus.SIE; // MIE の古い値
                    csrNext.mstatus.SIE = 0;    // グローバル割り込み許可を落とす
                    csrNext.mstatus.SPP = ToSPP_FromPrivilegeLevel(privilegeLevel); // トラップ前の特権レベル
                    csrNext.sepc = ToAddrFromPC(port.excptCauseAddr); // 例外の発生元 PC を書き込む
                    csrNext.stval = port.excptCauseDataAddr;// ECALL/EBREAK の場合は PC?
                    csrNext.scause.isInterrupt = FALSE;
                    csrNext.scause.code.trapCode = ToTrapCodeFromExecState(port.excptCause, privilegeLevel);
                end
                //$display("trap: from %x", ToAddrFromPC(port.excptCauseAddr));
            end
        end
        else if (port.csrWE && !port.csrUnitTriggerExcpt) begin
            // Operation
            unique case (port.csrCode) 
                CSR_WRITE:  wv = port.csrWriteIn;
                CSR_SET:    wv = rv | port.csrWriteIn;
                CSR_CLEAR:  wv = rv & (~port.csrWriteIn);
                default:    wv = port.csrWriteIn;    // ???
            endcase

            unique case (port.csrNumber) 
                CSR_NUM_MISA: begin
                    if (wv.misa.EXTENSIONS.S && !wv.misa.EXTENSIONS.U) begin
                        wv.misa.EXTENSIONS.S = 0;
                    end
                    csrNext.misa.EXTENSIONS.S = wv.misa.EXTENSIONS.S;
                    csrNext.misa.EXTENSIONS.U = wv.misa.EXTENSIONS.U;
                end
                CSR_NUM_MSTATUS, CSR_NUM_SSTATUS: begin
                    if (port.csrNumber == CSR_NUM_MSTATUS) begin
                        if (csrReg.misa.EXTENSIONS.S) begin
                            csrNext.mstatus.TSR = wv.mstatus.TSR;
                            csrNext.mstatus.TVM = wv.mstatus.TVM;
                            csrNext.mstatus.MXR = wv.mstatus.MXR;
                            csrNext.mstatus.SUM = wv.mstatus.SUM;
                            csrNext.mstatus.SPP = wv.mstatus.SPP;
                            csrNext.mstatus.SPIE= wv.mstatus.SPIE;
                            csrNext.mstatus.SIE = wv.mstatus.SIE;
                        end
                        if (csrReg.misa.EXTENSIONS.U) begin
                            csrNext.mstatus.MPRV = wv.mstatus.MPRV;
                            csrNext.mstatus.MPP = wv.mstatus.MPP;
                        end
                        csrNext.mstatus.MPIE= wv.mstatus.MPIE;
                        csrNext.mstatus.MIE = wv.mstatus.MIE;
                    end
                    else if (csrReg.misa.EXTENSIONS.S) begin
                        csrNext.mstatus = ToMstatusFromSstatus(wv, csrReg.mstatus);
                    end
                    // check MPP is supported Level
                    if (!IsSupportedPrivilegeLevel(csrNext.mstatus.MPP, csrNext.misa)) begin
                        // fallback
                        csrNext.mstatus.MPP = csrReg.mstatus.MPP;
                    end
                    //$display("mstatus: %x", wv);
                end
                // MIP                
                // > Only the bits corresponding to lower-privilege 
                // > software interrupts (USIP, SSIP), timer interrupts (UTIP,
                // > STIP), and external interrupts (UEIP, SEIP) in mip are writable 
                // > through this CSR address; the remaining bits are read-only.
                CSR_NUM_MIP: begin
                    csrNext.mip.CUSTOM = wv.mip.CUSTOM;
                    if (csrReg.misa.EXTENSIONS.S) begin
                        csrNext.mip.SEIP = wv.mip.SEIP;
                        csrNext.mip.STIP = wv.mip.STIP;
                        csrNext.mip.SSIP = wv.mip.SSIP;
                    end
                end
                CSR_NUM_MIE:begin
                    csrNext.mie = wv;
                    //$display("mie: %x", wv);
                end
                CSR_NUM_MCAUSE:     csrNext.mcause = wv;
                CSR_NUM_MTVEC:      csrNext.mtvec = wv;
                CSR_NUM_MTVAL:      csrNext.mtval = wv;
                // The low bit of mepc is always zero,
                // as described in Chapter 3.1.19 of RISC-V Privileged Architectures.
                CSR_NUM_MEPC:       csrNext.mepc = {wv[31:1], 1'b0};
                CSR_NUM_MSCRATCH:   csrNext.mscratch = wv;

                CSR_NUM_MCYCLE:     csrNext.mcycle = wv;
                CSR_NUM_MINSTRET:   csrNext.minstret = wv;
`ifdef RSD_MARCH_FP_PIPE
                CSR_NUM_FFLAGS:     csrNext.fcsr.fflags = wv;
                CSR_NUM_FRM:        csrNext.fcsr.frm = Rounding_Mode'(wv);
                CSR_NUM_FCSR:       csrNext.fcsr = FFlags_Path'(wv);
`endif
                default: if (csrReg.misa.EXTENSIONS.S) begin
                    unique case (port.csrNumber)
                        CSR_NUM_SIE:        csrNext.sie = wv & csrNext.mideleg;
                        CSR_NUM_STVEC:      csrNext.stvec = wv;
                        CSR_NUM_SSCRATCH:   csrNext.sscratch = wv;
                        CSR_NUM_SEPC:       csrNext.sepc = wv;
                        CSR_NUM_SCAUSE:     csrNext.scause = wv;
                        CSR_NUM_STVAL:      csrNext.stval = wv;

                        CSR_NUM_MEDELEG: begin
                            csrNext.medeleg = wv;
                            csrNext.medeleg[16] = 0; // can't delegate double trap
                            csrNext.medeleg[11] = 0; // can't delegate ECALL from M-mode
                        end
                        CSR_NUM_MEDELEGH: csrNext.medelegh = wv;
                        CSR_NUM_MIDELEG: begin
                            csrNext.mideleg.CUSTOM = wv.mideleg.CUSTOM;
                            csrNext.mideleg.SEI    = wv.mideleg.SEI;
                            csrNext.mideleg.STI    = wv.mideleg.STI;
                            csrNext.mideleg.SSI    = wv.mideleg.SSI;
                        end
                        default: wv = '0;    // dummy
                    endcase
                end
            endcase 
        end

`ifdef RSD_MARCH_FP_PIPE
        // write to fflags from FP-CM and Mem-EX(CSR) shouldn't occur at the same time.
        else if(port.fflagsWE) begin
            csrNext.fcsr.fflags = port.fflagsData;
        end
        port.fflags = csrReg.fcsr.fflags;
        port.frm = csrReg.fcsr.frm;
`endif

        csrNext.mip.MTIP = port.reqTimerInterrupt;      // Timer interrupt request
        csrNext.mip.CUSTOM[port.customInterruptCode] = port.reqCustomInterrupt;   // Custom interrupt request

        port.csrReadOut = rv;
        if (port.excptCause == EXEC_STATE_TRAP_MRET) begin
            port.excptTargetAddr = csrReg.mepc;
            //$display("mret: to %x", csrNext.mepc);
        end
        else if (port.excptCause == EXEC_STATE_TRAP_SRET) begin
            port.excptTargetAddr = csrReg.sepc;
            //$display("sret: to %x", csrNext.sepc);
        end
        else begin
            case (privilegeLevelNext)
                PRIVILEGE_LEVEL_M: port.excptTargetAddr = {csrReg.mtvec.base, CSR_XTVEC_BASE_PADDING};
                PRIVILEGE_LEVEL_S: port.excptTargetAddr = {csrReg.stvec.base, CSR_XTVEC_BASE_PADDING};
                default: begin end
            endcase
        end

        port.csrWholeOut = csrReg;

        port.privilegeLevel = privilegeLevel;
    end

    `RSD_ASSERT_CLK(
        port.clk, 
        !(port.triggerExcpt && !(port.excptCause inside {
            EXEC_STATE_TRAP_ECALL, 
            EXEC_STATE_TRAP_EBREAK, 
            EXEC_STATE_TRAP_SRET,
            EXEC_STATE_TRAP_MRET,
            EXEC_STATE_FAULT_LOAD_MISALIGNED,
            EXEC_STATE_FAULT_LOAD_VIOLATION,
            EXEC_STATE_FAULT_STORE_MISALIGNED,
            EXEC_STATE_FAULT_STORE_VIOLATION,
            EXEC_STATE_FAULT_INSN_ILLEGAL,
            EXEC_STATE_FAULT_INSN_VIOLATION,
            EXEC_STATE_FAULT_INSN_MISALIGNED
        })),
        "Invalid exception cause is passed"
    );

    `RSD_ASSERT_CLK(
        port.clk, 
        !(
            (port.triggerExcpt && port.csrWE) || 
            (port.triggerInterrupt && port.csrWE) || 
            (port.triggerExcpt && port.triggerInterrupt)
        ),
        "CSR update, trap or interrupt are performed at the same cycle"
    );

    `RSD_ASSERT_CLK(
        port.clk, 
        !(
            (port.triggerInterrupt ||
                (port.triggerExcpt && port.excptCause != EXEC_STATE_TRAP_MRET && port.excptCause != EXEC_STATE_TRAP_SRET)
            ) && privilegeLevelNext >= privilegeLevel
        ),
        "Trap to lower privilege level"
    );

endmodule : CSR_Unit

