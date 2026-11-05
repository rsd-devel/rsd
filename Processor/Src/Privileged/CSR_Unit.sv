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
import MicroOpTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;

module CSR_Unit(
    CSR_UnitIF.CSR_Unit port,
    PLIC_UnitIF.CSR_Unit plicUnit,
    PerformanceCounterIF.CSR perfCounter
);

    CSR_BodyPath csrReg, csrNext;
    DataPath rv;
    logic csrImplemented;
    CSR_ValuePath wv;
    DataPath mcycle;    // for debug
    AddrPath jumpTarget;
    AddrPath mepc;
    AddrPath sepc;
    AddrPath trapValue;
    CommitLaneCountPath regRetireNum;
    CommitLaneCountPath minstretIncrement;
    logic minstretWritePending, minstretWritePendingNext;

    CSR_MIP_Path mipReg, mipRegNext, mipWired;

    PrivilegeLevelType privilegeLevel, privilegeLevelNext;
    PrivilegeLevelType excptPrivilegeLevel;
    PrivilegeLevelType returnPrivilegeLevel;

    function automatic CSR_BodyPath GetCSRResetValue();
        CSR_BodyPath value;
        value = '0;
        value.misa.MXL = ENCODED_XLEN_32;
        value.misa.EXTENSIONS.I = 1;
        value.misa.EXTENSIONS.M = 1;
        value.misa.EXTENSIONS.A = 1;
`ifdef RSD_MARCH_FP_PIPE
        value.misa.EXTENSIONS.F = 1;
`endif
        value.misa.EXTENSIONS.D = 0;
        value.misa.EXTENSIONS.U = 1;
        value.misa.EXTENSIONS.S = 1;
        return value;
    endfunction

    function logic IsSupportedPrivilegeLevel(
        input PrivilegeLevelType level,
        input CSR_MISA_Path misa
    );
        return level == PRIVILEGE_LEVEL_M ||
               misa.EXTENSIONS.S && level == PRIVILEGE_LEVEL_S ||
               misa.EXTENSIONS.U && level == PRIVILEGE_LEVEL_U;
    endfunction

    always_ff@(posedge port.clk) begin
        if (port.rst) begin
            csrReg <= GetCSRResetValue();
            mipReg <= '0;
            regRetireNum <= '0;
            minstretWritePending <= FALSE;
            privilegeLevel <= PRIVILEGE_LEVEL_M;
        end
        else begin
            csrReg <= csrNext;
            mipReg <= mipRegNext;
            privilegeLevel <= privilegeLevelNext;
            regRetireNum <= port.retireNum;
            minstretWritePending <= minstretWritePendingNext;
            // if (privilegeLevel != privilegeLevelNext) begin
            //     $display("privilege level: %b -> %b", privilegeLevel, privilegeLevelNext);
            // end
        end
    end

    always_comb begin
        mipWired = '0;
        mipWired.CUSTOM[port.customInterruptCode] = port.reqCustomInterrupt;   // Custom interrupt request
        mipWired.MEIP = plicUnit.reqExternalInterrupt[0]; // external interrupt for hart 0
        mipWired.MTIP = port.reqTimerInterrupt;      // Timer interrupt request
        mipWired.MSIP = port.msip; // Machine Software Interrupt request
        mipWired.SEIP = plicUnit.reqExternalInterrupt[1]; // external interrupt for hart 0
    end

    always_comb begin
        mcycle = csrReg.mcycle[31:0];

        // RSD uses IALIGN=32. Mask CSR reads and the implicit reads by xRET.
        // Revisit this mask if compressed instructions are supported.
        mepc = {csrReg.mepc[ADDR_WIDTH-1:2], 2'b0};
        sepc = {csrReg.sepc[ADDR_WIDTH-1:2], 2'b0};

        // Instruction encodings are optional trap values. Report zero for illegal
        // instructions so the pipeline does not need to retain their bits.
        trapValue = port.excptCause == EXEC_STATE_FAULT_LPAD ?
            CSR_TRAPVALUE_LANDING_PAD_FAIL :
            port.excptCause == EXEC_STATE_FAULT_INSN_ILLEGAL ? '0 : port.excptCauseDataAddr;

        privilegeLevelNext = privilegeLevel;
        returnPrivilegeLevel = port.excptCause == EXEC_STATE_TRAP_MRET ?
            (csrReg.misa.EXTENSIONS.U ? csrReg.mstatus.MPP : PRIVILEGE_LEVEL_M) :
            ToPrivilegeLevelFromSPP(csrReg.mstatus.SPP);

        port.xLPE = IsLandingPadEnabled(csrReg, privilegeLevel);
        // Recovery consumes this alongside the CSR target, before trap state is
        // clocked. The return destination controls LPE, independently of IRQs.
        port.recoverELP_FromCSR = LP_NOT_EXPECTED;
        if (IsLandingPadEnabled(csrReg, returnPrivilegeLevel)) begin
            if (port.excptCause == EXEC_STATE_TRAP_MRET)
                port.recoverELP_FromCSR = csrReg.mstatush.MPELP;
            else if (port.excptCause == EXEC_STATE_TRAP_SRET)
                port.recoverELP_FromCSR = csrReg.mstatus.SPELP;
        end

        // Select the exception destination independently of interrupt triggering.
        // Sharing privilegeLevelNext would put the interrupt path on the recovery PC.
        if (privilegeLevel == PRIVILEGE_LEVEL_M || !csrReg.misa.EXTENSIONS.S ||
            !csrReg.medeleg[ToTrapCodeFromExecState(port.excptCause, privilegeLevel)]) begin
            excptPrivilegeLevel = PRIVILEGE_LEVEL_M;
        end
        else begin
            excptPrivilegeLevel = PRIVILEGE_LEVEL_S;
        end

        // Read a CSR value
        csrImplemented = TRUE;
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
                    value.SPELP = LP_NOT_EXPECTED;
                end
                if (!csrReg.misa.EXTENSIONS.U) begin
                    value.MPRV = '0;
                    value.MPP = PRIVILEGE_LEVEL_U;
                end
                rv = value;
            end
            CSR_NUM_MIP:        rv = mipReg;
            CSR_NUM_MSTATUSH:   rv = csrReg.mstatush;
            CSR_NUM_MSECCFG:    rv = csrReg.mseccfg;
            CSR_NUM_MSECCFGH:   rv = '0;
            CSR_NUM_MENVCFG, CSR_NUM_MENVCFGH: begin
                rv = port.csrNumber == CSR_NUM_MENVCFG ? DataPath'(csrReg.menvcfg) : '0;
                csrImplemented = csrReg.misa.EXTENSIONS.U;
            end
            CSR_NUM_MIE:        rv = csrReg.mie;
            CSR_NUM_MCAUSE:     rv = csrReg.mcause;
            CSR_NUM_MTVEC:      rv = csrReg.mtvec;
            CSR_NUM_MTVAL:      rv = csrReg.mtval;
            CSR_NUM_MEPC:       rv = mepc;
            CSR_NUM_MSCRATCH:   rv = csrReg.mscratch;

            CSR_NUM_MISA: rv = csrReg.misa;

            // Implemented fixed-zero CSRs must not be treated as missing.
            CSR_NUM_MVENDORID, CSR_NUM_MARCHID, CSR_NUM_MIMPID, CSR_NUM_MHARTID,
            CSR_NUM_MCOUNTEREN: rv = '0;

            CSR_NUM_MCYCLE:    rv = csrReg.mcycle[31:0];
            CSR_NUM_MCYCLEH:   rv = csrReg.mcycle[63:32];
            CSR_NUM_MINSTRET:  rv = csrReg.minstret[31:0];
            CSR_NUM_MINSTRETH: rv = csrReg.minstret[63:32];
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
                        CSR_NUM_SENVCFG:    rv = csrReg.senvcfg;
                        CSR_NUM_SIP:        rv = csrReg.mip & csrReg.mideleg;
                        CSR_NUM_SIE:        rv = csrReg.mie & csrReg.mideleg;
                        CSR_NUM_STVEC:      rv = csrReg.stvec;
                        CSR_NUM_SSCRATCH:   rv = csrReg.sscratch;
                        CSR_NUM_SEPC:       rv = sepc;
                        CSR_NUM_SCAUSE:     rv = csrReg.scause;
                        CSR_NUM_STVAL:      rv = csrReg.stval;
                        // satp is fixed to Bare (zero); writes are ignored because no
                        // page-table translation is implemented. Revisit its state and
                        // supported MODE/ASID/PPN values when adding paging support.
                        CSR_NUM_SCOUNTEREN, CSR_NUM_SATP: rv = '0;

                        CSR_NUM_MEDELEG:    rv = csrReg.medeleg;
                        CSR_NUM_MEDELEGH:   rv = csrReg.medelegh;
                        CSR_NUM_MIDELEG:    rv = csrReg.mideleg;
                        default: begin
                            rv = '0;
                            csrImplemented = FALSE;
                        end
                    endcase
                end
                else begin
                    rv = '0;
                    csrImplemented = FALSE;
                end
            end
        endcase 

        // Check CSR existence, privilege and writes to read-only CSRs.
        // TVM lets M-mode software intercept S-mode virtual-memory management.
        // TVM is writable here, so S-mode satp reads/writes must trap when it
        // is set, even with Bare-only support. Keep this check if paging is added.
        port.csrUnitTriggerExcpt = (port.csrRE || port.csrWE) &&
            (!csrImplemented || privilegeLevel < port.csrNumber[9:8] ||
             (port.csrWE && port.csrNumber[11:10] == 2'b11) ||
             (privilegeLevel == PRIVILEGE_LEVEL_S && csrReg.mstatus.TVM &&
              port.csrNumber == CSR_NUM_SATP));

        // Writeback 
        csrNext = csrReg;
        mipRegNext = mipReg;
        minstretWritePendingNext = minstretWritePending;

        // CSR writes execute before retirement. Serialization makes the next
        // retired instruction the writer itself; its implicit update is replaced.
        minstretIncrement = regRetireNum;
        if (minstretWritePending && regRetireNum != 0) begin
            minstretIncrement = regRetireNum - 1'b1;
            minstretWritePendingNext = FALSE;
        end

        // Explicit writes below take precedence over the counter increments.
        csrNext.mcycle = csrNext.mcycle + 64'd1;
        csrNext.minstret = csrNext.minstret + minstretIncrement;

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
                csrNext.mstatush.MPELP = port.interruptELP;
            end
            else if (privilegeLevelNext == PRIVILEGE_LEVEL_S) begin
                csrNext.mstatus.SPIE = csrNext.mstatus.SIE; // SIE の古い値
                csrNext.mstatus.SIE = 0; // グローバル割り込み許可を落とす
                csrNext.mstatus.SPP = ToSPP_FromPrivilegeLevel(privilegeLevel); // トラップ前の特権レベル
                csrNext.sepc = ToAddrFromPC(port.interruptRetAddr); // 割り込み発生時の PC
                csrNext.stval = 0;
                csrNext.scause.isInterrupt = TRUE;
                csrNext.scause.code.interruptCode = port.interruptCode;
                csrNext.mstatus.SPELP = port.interruptELP;
            end
            //$display("int: from %x", port.interruptRetAddr);
        end
        else if (port.triggerExcpt) begin
            if (port.excptCause == EXEC_STATE_TRAP_MRET) begin
                // MRET
                privilegeLevelNext = csrReg.misa.EXTENSIONS.U ? csrReg.mstatus.MPP : PRIVILEGE_LEVEL_M;
                csrNext.mstatush.MPELP = LP_NOT_EXPECTED;
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
                csrNext.mstatus.SPELP = LP_NOT_EXPECTED;
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
                privilegeLevelNext = excptPrivilegeLevel;

                if (privilegeLevelNext == PRIVILEGE_LEVEL_M) begin
                    csrNext.mstatus.MPIE = csrNext.mstatus.MIE; // MIE の古い値
                    csrNext.mstatus.MIE = 0;    // グローバル割り込み許可を落とす
                    csrNext.mstatus.MPP = privilegeLevel; // トラップ前の特権レベル
                    csrNext.mepc = ToAddrFromPC(port.excptCauseAddr); // 例外の発生元 PC を書き込む
                    csrNext.mtval = trapValue;
                    csrNext.mcause.isInterrupt = FALSE;
                    csrNext.mcause.code.trapCode = ToTrapCodeFromExecState(port.excptCause, privilegeLevel);
                    csrNext.mstatush.MPELP = port.excptELP;
                end
                else if (privilegeLevelNext == PRIVILEGE_LEVEL_S) begin
                    csrNext.mstatus.SPIE = csrNext.mstatus.SIE; // MIE の古い値
                    csrNext.mstatus.SIE = 0;    // グローバル割り込み許可を落とす
                    csrNext.mstatus.SPP = ToSPP_FromPrivilegeLevel(privilegeLevel); // トラップ前の特権レベル
                    csrNext.sepc = ToAddrFromPC(port.excptCauseAddr); // 例外の発生元 PC を書き込む
                    csrNext.stval = trapValue;
                    csrNext.scause.isInterrupt = FALSE;
                    csrNext.scause.code.trapCode = ToTrapCodeFromExecState(port.excptCause, privilegeLevel);
                    csrNext.mstatus.SPELP = port.excptELP;
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
                            csrNext.mstatus.SPELP = wv.mstatus.SPELP;
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
                CSR_NUM_MSTATUSH: csrNext.mstatush.MPELP = wv.mstatush.MPELP;
                CSR_NUM_MSECCFG:  csrNext.mseccfg.MLPE = wv.mseccfg.MLPE;
                CSR_NUM_MENVCFG:  csrNext.menvcfg.LPE = wv.menvcfg.LPE;
                // MIP
                CSR_NUM_MIP: begin
                    mipRegNext.CUSTOM = wv.mip.CUSTOM;
                    if (csrReg.misa.EXTENSIONS.S) begin
                        mipRegNext.SEIP = wv.mip.SEIP;
                        mipRegNext.STIP = wv.mip.STIP;
                        mipRegNext.SSIP = wv.mip.SSIP;
                    end
                end
                CSR_NUM_MIE: begin
                    // Update implemented fields only; padding remains zero.
                    csrNext.mie.CUSTOM = wv.mie.CUSTOM;
                    csrNext.mie.MEIE = wv.mie.MEIE;
                    csrNext.mie.SEIE = wv.mie.SEIE;
                    csrNext.mie.MTIE = wv.mie.MTIE;
                    csrNext.mie.STIE = wv.mie.STIE;
                    csrNext.mie.MSIE = wv.mie.MSIE;
                    csrNext.mie.SSIE = wv.mie.SSIE;
                end
                CSR_NUM_MCAUSE:     csrNext.mcause = wv;
                CSR_NUM_MTVEC: begin
                    csrNext.mtvec.base = wv.mtvec.base;
                    // Reserved MODE values select Direct without changing BASE.
                    csrNext.mtvec.mode = wv.mtvec.mode == CSR_XTVEC_MODE_VECTORED ?
                        CSR_XTVEC_MODE_VECTORED : CSR_XTVEC_MODE_BASE;
                end
                CSR_NUM_MTVAL:      csrNext.mtval = wv;
                // The low bit of mepc is always zero,
                // as described in Chapter 3.1.19 of RISC-V Privileged Architectures.
                CSR_NUM_MEPC:       csrNext.mepc = {wv[31:1], 1'b0};
                CSR_NUM_MSCRATCH:   csrNext.mscratch = wv;

                // A write to either half suppresses the entire 64-bit increment.
                CSR_NUM_MCYCLE:     csrNext.mcycle = {csrReg.mcycle[63:32], wv};
                CSR_NUM_MCYCLEH:    csrNext.mcycle = {wv, csrReg.mcycle[31:0]};
                CSR_NUM_MINSTRET: begin
                    csrNext.minstret = {csrReg.minstret[63:32], wv};
                    minstretWritePendingNext = TRUE;
                end
                CSR_NUM_MINSTRETH: begin
                    csrNext.minstret = {wv, csrReg.minstret[31:0]};
                    minstretWritePendingNext = TRUE;
                end
`ifdef RSD_MARCH_FP_PIPE
                CSR_NUM_FFLAGS:     csrNext.fcsr.fflags = wv;
                CSR_NUM_FRM:        csrNext.fcsr.frm = Rounding_Mode'(wv);
                CSR_NUM_FCSR: begin
                    csrNext.fcsr.frm = wv.fcsr.frm;
                    csrNext.fcsr.fflags = wv.fcsr.fflags;
                end
`endif
                default: if (csrReg.misa.EXTENSIONS.S) begin
                    unique case (port.csrNumber)
                        CSR_NUM_SENVCFG: csrNext.senvcfg.LPE = wv.senvcfg.LPE;
                        CSR_NUM_SIP: begin
                            // Only delegated SSIP is writable through SIP;
                            // external/timer pending bits remain read-only here.
                            if (csrReg.mideleg.SSI)
                                mipRegNext.SSIP = wv.sip.SSIP;
                        end
                        CSR_NUM_SIE: begin
                            // SIE is the delegated view of MIE, not separate state.
                            // Preserve interrupt enables hidden from S-mode.
                            csrNext.mie = (csrReg.mie & ~csrReg.mideleg) |
                                          (wv & csrReg.mideleg);
                        end
                        CSR_NUM_STVEC: begin
                            csrNext.stvec.base = wv.stvec.base;
                            csrNext.stvec.mode = wv.stvec.mode == CSR_XTVEC_MODE_VECTORED ?
                                CSR_XTVEC_MODE_VECTORED : CSR_XTVEC_MODE_BASE;
                        end
                        CSR_NUM_SSCRATCH:   csrNext.sscratch = wv;
                        // Like MEPC, SEPC bit 0 is never writable.
                        CSR_NUM_SEPC:       csrNext.sepc = {wv[31:1], 1'b0};
                        CSR_NUM_SCAUSE:     csrNext.scause = wv;
                        CSR_NUM_STVAL:      csrNext.stval = wv;

                        CSR_NUM_MEDELEG: begin
                            csrNext.medeleg = wv;
                            csrNext.medeleg[CSR_CAUSE_TRAP_CODE_DOUBLE_TRAP] = 0; // can't delegate double trap
                            csrNext.medeleg[CSR_CAUSE_TRAP_CODE_MCALL]       = 0; // can't delegate ECALL from M-mode
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

`ifndef RSD_ENABLE_ZICFILP
        // Apply after every write/trap path so synthesis removes CFI-only state.
        // The CSR addresses and their privilege checks remain available as WARL zero.
        csrNext.mstatus.SPELP = LP_NOT_EXPECTED;
        csrNext.mstatush.MPELP = LP_NOT_EXPECTED;
        csrNext.mseccfg.MLPE = FALSE;
        csrNext.menvcfg.LPE = FALSE;
        csrNext.senvcfg.LPE = FALSE;
`endif

        if (port.csrNumber == CSR_NUM_MIP) begin
            rv = csrReg.mip;
        end
        port.csrReadOut = rv;

        // Publish software-pending writes on the same edge as their storage.
        // A following SIP read/modify/write must not use the old pending value.
        csrNext.mip = mipWired | mipRegNext;

        port.excptTargetAddr = '0;
        if (port.excptCause == EXEC_STATE_TRAP_MRET) begin
            port.excptTargetAddr = mepc;
            //$display("mret: to %x", csrNext.mepc);
        end
        else if (port.excptCause == EXEC_STATE_TRAP_SRET) begin
            port.excptTargetAddr = sepc;
            //$display("sret: to %x", csrNext.sepc);
        end
        else begin
            // RecoveryManager consumes this target only when triggerExcpt is set;
            // interrupt targets are selected separately by InterruptController.
            case (excptPrivilegeLevel)
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
            EXEC_STATE_FAULT_INSN_MISALIGNED,
            EXEC_STATE_FAULT_LPAD
        })),
        "Invalid exception cause is passed"
    );

    `RSD_ASSERT_CLK(
        port.clk, 
        !(
            (port.triggerExcpt && (port.csrRE || port.csrWE)) ||
            (port.triggerInterrupt && (port.csrRE || port.csrWE)) ||
            (port.triggerExcpt && port.triggerInterrupt)
        ),
        "CSR update, trap or interrupt are performed at the same cycle"
    );

    `RSD_ASSERT_CLK(
        port.clk, 
        !(
            (port.triggerInterrupt ||
                (port.triggerExcpt && port.excptCause != EXEC_STATE_TRAP_MRET && port.excptCause != EXEC_STATE_TRAP_SRET)
            ) && privilegeLevelNext < privilegeLevel
        ),
        "Trap to lower privilege level"
    );

endmodule : CSR_Unit

