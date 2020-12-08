// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// The interface of a CSR unit.
//


import BasicTypes::*;
import MemoryMapTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import CSR_UnitTypes::*;

interface CSR_UnitIF(
    input logic clk, rst, rstStart, reqExternalInterrupt, 
    ExternalInterruptCodePath externalInterruptCode
);

    logic csrWE;  // CSR write enable
    CSR_NumberPath csrNumber;   // CSR number
    CSR_Code csrCode;           // CSR operation code (ex. set, clear...)
    DataPath csrReadOut;        // a register value read from CSR 
    DataPath csrWriteIn;        // a value to be written to CSR
    CSR_BodyPath csrWholeOut;   // whole values of CSR

    // Exception = trap or fault
    // Trap request
    logic   triggerExcpt;
    ExecutionState excptCause;
    PC_Path excptCauseAddr;     // EBREAK/ECALL 時の mepc
    AddrPath excptTargetAddr;   // Trap vector or MRET return target
    AddrPath excptCauseDataAddr;     // fault 発生時のデータアドレス

    // Interrupt
    logic triggerInterrupt;
    CSR_CAUSE_InterruptCodePath interruptCode;
    PC_Path interruptRetAddr;

    // Timer interrupt request
    logic reqTimerInterrupt;

    // Latched code, see the cooments in the CSR.
    ExternalInterruptCodePath externalInterruptCodeInCSR;

    // Used in updating minstret
    CommitLaneCountPath commitNum;

    modport MemoryExecutionStage(
    input
        clk, rst, rstStart,
        csrReadOut,
    output 
        csrWE,
        csrNumber,
        csrCode,
        csrWriteIn
    );

    // 割り込みは以下の流れで要求が流れる
    // IO_Unit -> reqTimerInterrupt ->
    // CSR_Unit -> csrReg.mie.MTIE ->
    // InterruptController -> triggerInterrupt -> 
    // FetchStage and CSR_Unit
    modport IO_Unit(
    output 
        reqTimerInterrupt
    );

    // For counter update
    modport CommitStage (
    output
        commitNum
    );


    modport RecoveryManager(
    input
        excptTargetAddr,
    output
        triggerExcpt,
        excptCauseAddr,
        excptCause,
        excptCauseDataAddr
    );

    modport CSR_Unit(
    input
        clk, rst, rstStart,
        csrWE,
        csrNumber,
        csrCode,
        csrWriteIn,
        triggerExcpt,
        excptCauseAddr,
        excptCause,
        excptCauseDataAddr,
        commitNum,
        reqTimerInterrupt,
        reqExternalInterrupt,
        externalInterruptCode,
        triggerInterrupt,
        interruptCode,
        interruptRetAddr,
    output 
        csrWholeOut,
        csrReadOut,
        excptTargetAddr,
        externalInterruptCodeInCSR
    );

    modport InterruptController(
    input
        clk, rst, rstStart,
        csrWholeOut,
        externalInterruptCodeInCSR,
    output
        triggerInterrupt,
        interruptRetAddr,
        interruptCode
    );

endinterface
