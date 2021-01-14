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

    // An external interrupt request is latched in the CSR, and an actual 
    // interrupt is triggered at the next cycle. So external interrupt code must be latched.
    ExternalInterruptCodePath externalInterruptCodeReg;

    always_ff@(posedge port.clk) begin
        if (port.rst) begin
            csrReg <= '0;
            regCommitNum <= '0;
            externalInterruptCodeReg <= '0;
        end
        else begin
            csrReg <= csrNext;
            regCommitNum <= port.commitNum;
            externalInterruptCodeReg <= port.externalInterruptCode;
        end
    end

    always_comb begin
        mcycle = csrReg.mcycle;
        
        // Read a CSR value
        unique case (port.csrNumber) 
            CSR_NUM_MSTATUS:    rv = csrReg.mstatus;
            CSR_NUM_MIP:        rv = csrReg.mip;
            CSR_NUM_MIE:        rv = csrReg.mie;
            CSR_NUM_MCAUSE:     rv = csrReg.mcause;
            CSR_NUM_MTVEC:      rv = csrReg.mtvec;
            CSR_NUM_MTVAL:      rv = csrReg.mtval;
            CSR_NUM_MEPC:       rv = csrReg.mepc;
            CSR_NUM_MSCRATCH:   rv = csrReg.mscratch;

            CSR_NUM_MCYCLE:   rv = csrReg.mcycle;
            CSR_NUM_MINSTRET: rv = csrReg.minstret;
`ifndef RSD_DISABLE_PERFORMANCE_COUNTER
            CSR_NUM_MHPMCOUNTER3: rv = perfCounter.perfCounter.numLoadMiss;
            CSR_NUM_MHPMCOUNTER4: rv = perfCounter.perfCounter.numStoreMiss;
            CSR_NUM_MHPMCOUNTER5: rv = perfCounter.perfCounter.numIC_Miss;
            CSR_NUM_MHPMCOUNTER6: rv = perfCounter.perfCounter.numBranchPredMiss;
`endif
            default:          rv = '0;
        endcase 


        // Writeback 
        csrNext = csrReg;

        // Update Cycles
        csrNext.mcycle = csrNext.mcycle + 1;
        csrNext.minstret = csrNext.minstret + regCommitNum;

        wv = '0;

        if (port.triggerInterrupt) begin
            // Interrupt
            csrNext.mstatus.MPIE = csrNext.mstatus.MIE; // MIE の古い値
            csrNext.mstatus.MIE = 0;    // グローバル割り込み許可を落とす
            csrNext.mepc = ToAddrFromPC(port.interruptRetAddr); // 割り込み発生時の PC
            csrNext.mtval = ToAddrFromPC(port.interruptRetAddr);// PC?
            
            csrNext.mcause.isInterrupt = TRUE;
            csrNext.mcause.code.interruptCode = port.interruptCode;
            //$display("int: from %x", port.interruptRetAddr);
        end
        else if (port.triggerExcpt) begin
            if (port.excptCause == EXEC_STATE_TRAP_MRET) begin
                // MRET
                csrNext.mstatus.MIE = csrNext.mstatus.MPIE; // MIE の古い値に戻す
                //$display("mret: to %x", csrNext.mepc);
            end
            else begin
                // Trap
                csrNext.mstatus.MPIE = csrNext.mstatus.MIE; // MIE の古い値
                csrNext.mstatus.MIE = 0;    // グローバル割り込み許可を落とす
                csrNext.mepc = ToAddrFromPC(port.excptCauseAddr); // 例外の発生元 PC を書き込む
                csrNext.mtval = port.excptCauseDataAddr;// ECALL/EBREAK の場合は PC?
                
                csrNext.mcause.isInterrupt = FALSE;
                csrNext.mcause.code.trapCode = ToTrapCodeFromExecState(port.excptCause);
                //$display("trap: from %x", csrNext.mepc);

            end
        end
        else if (port.csrWE) begin
            // Operation
            unique case (port.csrCode) 
                CSR_WRITE:  wv = port.csrWriteIn;
                CSR_SET:    wv = rv | port.csrWriteIn;
                CSR_CLEAR:  wv = rv & (~port.csrWriteIn);
                default:    wv = port.csrWriteIn;    // ???
            endcase

            unique case (port.csrNumber) 
                CSR_NUM_MSTATUS: begin
                    //csrNext.mstatus.MIE = wv.mstatus.MIE;
                    //csrNext.mstatus.MPIE = wv.mstatus.MPIE;
                    csrNext.mstatus = wv;
                   //$display("mstatus: %x", wv);
                end

                // MIP                
                // > Only the bits corresponding to lower-privilege 
                // > software interrupts (USIP, SSIP), timer interrupts (UTIP,
                // > STIP), and external interrupts (UEIP, SEIP) in mip are writable 
                // > through this CSR address; the remaining bits are read-only.
                // Currently, only MTIP is supported and thus this is write only.
                //CSR_NUM_MIP:        csrNext.mip = wv;

                CSR_NUM_MIE:begin
                    csrNext.mie = wv;
                    //$display("mie: %x", wv);
                end
                CSR_NUM_MCAUSE:     csrNext.mcause = wv;
                CSR_NUM_MTVEC:      csrNext.mtvec = wv;
                CSR_NUM_MTVAL:      csrNext.mtval = wv;
                CSR_NUM_MEPC:       csrNext.mepc = wv;
                CSR_NUM_MSCRATCH:   csrNext.mscratch = wv;

                CSR_NUM_MCYCLE:     csrNext.mcycle = wv;
                CSR_NUM_MINSTRET:   csrNext.minstret = wv;
                default:            wv = '0;    // dummy
            endcase 
        end

        csrNext.mip.MTIP = port.reqTimerInterrupt;      // Timer interrupt request
        csrNext.mip.MEIP = port.reqExternalInterrupt;   // External interrupt request
        port.externalInterruptCodeInCSR = externalInterruptCodeReg;

        port.csrReadOut = rv;
        if (port.excptCause == EXEC_STATE_TRAP_MRET) begin
            port.excptTargetAddr = csrReg.mepc;
        end
        else begin
            port.excptTargetAddr = {csrReg.mtvec.base, CSR_MTVEC_BASE_PADDING};
        end

        port.csrWholeOut = csrReg;
    end

    `RSD_ASSERT_CLK(
        port.clk, 
        !(port.triggerExcpt && !(port.excptCause inside {
            EXEC_STATE_TRAP_ECALL, 
            EXEC_STATE_TRAP_EBREAK, 
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

endmodule : CSR_Unit

