// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


// 
// --- Types related to CSR
//

package CSR_UnitTypes;

import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;

// If you add additonal status bits, check CSR_Unit.sv because 
// only valid fileds are updated.
typedef struct packed {
    logic [23:0] padding_2;  // 31:8
    logic MPIE;               // 7
    logic [2:0] padding_1;   // 6:4
    logic MIE;              // 3
    logic [2:0] padding_0;   // 2:0
} CSR_MSTATUS_Path;

// Interrupt pending?
typedef struct packed {
    logic [19:0] padding_3; // 31:12
    logic MEIP;             // 11:11    external interrupt
    logic [2:0] padding_2;  // 10:8
    logic MTIP;             // 7:7      timer interrupt
    logic [2:0] padding_1;  // 6:4
    logic MSIP;             // 3:3      software interrupt
    logic [2:0] padding_0;  // 2:0
} CSR_MIP_Path;

// Interrupt enable?
typedef struct packed {
    logic [19:0] padding_3; // 31:12
    logic MEIE;             // 11:11    external interrupt
    logic [2:0] padding_2;  // 10:8
    logic MTIE;             // 7:7      timer interrupt
    logic [2:0] padding_1;  // 6:4
    logic MSIE;             // 3:3      software interrupt
    logic [2:0] padding_0;  // 2:0
} CSR_MIE_Path;

typedef enum logic [3:0] {
    CSR_CAUSE_TRAP_CODE_INSN_MISALIGNED = 0,
    CSR_CAUSE_TRAP_CODE_INSN_VIOLATION = 1,
    CSR_CAUSE_TRAP_CODE_INSN_ILLEGAL = 2,
    CSR_CAUSE_TRAP_CODE_BREAK = 3,
    CSR_CAUSE_TRAP_CODE_LOAD_MISALIGNED = 4,
    CSR_CAUSE_TRAP_CODE_LOAD_VIOLATION = 5,
    CSR_CAUSE_TRAP_CODE_STORE_MISALIGNED = 6,
    CSR_CAUSE_TRAP_CODE_STORE_VIOLATION = 7,
    CSR_CAUSE_TRAP_CODE_MCALL = 11,

    CSR_CAUSE_TRAP_CODE_UNKNOWN = 14
} CSR_CAUSE_TrapCodePath;

function automatic CSR_CAUSE_TrapCodePath ToTrapCodeFromExecState(ExecutionState state);
    case(state)
    EXEC_STATE_TRAP_ECALL:  return CSR_CAUSE_TRAP_CODE_MCALL;
    EXEC_STATE_TRAP_EBREAK: return CSR_CAUSE_TRAP_CODE_BREAK;

    EXEC_STATE_FAULT_LOAD_MISALIGNED:  return CSR_CAUSE_TRAP_CODE_LOAD_MISALIGNED;
    EXEC_STATE_FAULT_LOAD_VIOLATION:   return CSR_CAUSE_TRAP_CODE_LOAD_VIOLATION;
    EXEC_STATE_FAULT_STORE_MISALIGNED: return CSR_CAUSE_TRAP_CODE_STORE_MISALIGNED;
    EXEC_STATE_FAULT_STORE_VIOLATION:  return CSR_CAUSE_TRAP_CODE_STORE_VIOLATION;
    
    EXEC_STATE_FAULT_INSN_ILLEGAL:     return CSR_CAUSE_TRAP_CODE_INSN_ILLEGAL;
    EXEC_STATE_FAULT_INSN_VIOLATION:   return CSR_CAUSE_TRAP_CODE_INSN_VIOLATION;
    EXEC_STATE_FAULT_INSN_MISALIGNED:  return CSR_CAUSE_TRAP_CODE_INSN_MISALIGNED;

    default: return CSR_CAUSE_TRAP_CODE_UNKNOWN;
    endcase
endfunction


typedef enum logic [3:0] {
    CSR_CAUSE_INTERRUPT_CODE_TIMER = 7
} CSR_CAUSE_InterruptCodePath;

typedef union packed    // IntOpInfo
{
    CSR_CAUSE_TrapCodePath trapCode;
    CSR_CAUSE_InterruptCodePath  interruptCode;
} CSR_CAUSE_CodePath;

typedef struct packed {
    logic isInterrupt;          // 31
    logic [26:0] padding;       // 30:4
    CSR_CAUSE_CodePath code;    //  3:0
} CSR_CAUSE_Path;


typedef enum logic [1:0] {
    CSR_MTVEC_MODE_BASE = 0,
    CSR_MTVEC_MODE_VECTORED = 1
} CSR_MTVEC_ModePath;

typedef struct packed {
    logic [29:0]        base;    // 31:2
    CSR_MTVEC_ModePath  mode;    //  1:0
} CSR_MTVEC_Path;

localparam logic [1:0] CSR_MTVEC_BASE_PADDING = 2'b0;

// All members have 32bit width
typedef union packed {
    CSR_MSTATUS_Path mstatus;
    CSR_MIP_Path mip;
    CSR_MIE_Path mie;
    CSR_CAUSE_Path mcause;
    CSR_MTVEC_Path mtvec;
    DataPath mtval;
    DataPath mepc;
    DataPath mscratch;

    DataPath mcycle;
    DataPath minstret;
} CSR_ValuePath;

typedef struct packed {
    // Inturrupt related registers
    CSR_MSTATUS_Path mstatus;
    CSR_MIP_Path mip;
    CSR_MIE_Path mie;
    CSR_CAUSE_Path mcause;
    CSR_MTVEC_Path mtvec;
    DataPath mtval;
    DataPath mepc;
    DataPath mscratch;

    DataPath mcycle;
    DataPath minstret;
} CSR_BodyPath;

//
// Machine Information Registers
//
localparam CSR_NUM_MVENDORID = 12'hF11; // Vendor ID.
localparam CSR_NUM_MARCHID   = 12'hF12; // Architecture ID.
localparam CSR_NUM_MIMPID    = 12'hF13; // Implementation ID.
localparam CSR_NUM_MHARTID   = 12'hF14; // Hardware thread ID.

//
// Machine Trap Setup
//
localparam CSR_NUM_MSTATUS   = 12'h300; // Machine status register.
localparam CSR_NUM_MISA      = 12'h301; // ISA and extensions
localparam CSR_NUM_MEDELEG   = 12'h302; // Machine exception delegation register.
localparam CSR_NUM_MIDELEG   = 12'h303; // Machine interrupt delegation register.
localparam CSR_NUM_MIE       = 12'h304; // Machine interrupt-enable register.
localparam CSR_NUM_MTVEC     = 12'h305; // Machine trap-handler base address.
localparam CSR_NUM_MCOUNTEREN = 12'h306; // Machine counter enable.

//
// Machine Trap Handling
//
localparam CSR_NUM_MSCRATCH  = 12'h340; // Scratch register for machine trap handlers.
localparam CSR_NUM_MEPC      = 12'h341; // Machine exception program counter.
localparam CSR_NUM_MCAUSE    = 12'h342; // Machine trap cause.
localparam CSR_NUM_MTVAL     = 12'h343; // Machine bad address or instruction.
localparam CSR_NUM_MIP       = 12'h344; // Machine interrupt pending.

//
// Machine Protection and Translation
//
localparam CSR_NUM_PMPCFG0   = 12'h3A0; // Physical memory protection configuration.
localparam CSR_NUM_PMPCFG1   = 12'h3A1; // Physical memory protection configuration, RV32 only.
localparam CSR_NUM_PMPCFG2   = 12'h3A2; // Physical memory protection configuration.
localparam CSR_NUM_PMPCFG3   = 12'h3A3; // Physical memory protection configuration, RV32 only.

localparam CSR_NUM_PMPADDR0  = 12'h3B0; // Physical memory protection address register.
localparam CSR_NUM_PMPADDR1  = 12'h3B1; 
localparam CSR_NUM_PMPADDR2  = 12'h3B2;
localparam CSR_NUM_PMPADDR3  = 12'h3B3;
localparam CSR_NUM_PMPADDR4  = 12'h3B4;
localparam CSR_NUM_PMPADDR5  = 12'h3B5;
localparam CSR_NUM_PMPADDR6  = 12'h3B6;
localparam CSR_NUM_PMPADDR7  = 12'h3B7;
localparam CSR_NUM_PMPADDR8  = 12'h3B8;
localparam CSR_NUM_PMPADDR9  = 12'h3B9;
localparam CSR_NUM_PMPADDR10 = 12'h3BA;
localparam CSR_NUM_PMPADDR11 = 12'h3BB;
localparam CSR_NUM_PMPADDR12 = 12'h3BC;
localparam CSR_NUM_PMPADDR13 = 12'h3BD;
localparam CSR_NUM_PMPADDR14 = 12'h3BE;
localparam CSR_NUM_PMPADDR15 = 12'h3BF;

localparam CSR_NUM_MCYCLE        = 12'hB00; // Machine cycle counter.
localparam CSR_NUM_MINSTRET      = 12'hB02; // Machine instructions-retired counter.

localparam CSR_NUM_MHPMCOUNTER3  = 12'hB03; // Machine performance-monitoring counter.
localparam CSR_NUM_MHPMCOUNTER4  = 12'hB04; // Machine performance-monitoring counter.
// ... TODO: Define these counters
localparam CSR_NUM_MHPMCOUNTER31 = 12'hB1F; // Machine performance-monitoring counter.

localparam CSR_NUM_MCYCLEH       = 12'hB80; // Upper 32 bits of mcycle, RV32I only.
localparam CSR_NUM_MINSTRETH     = 12'hB82; // Upper 32 bits of minstret, RV32I only.
localparam CSR_NUM_MHPMCOUNTER3H = 12'hB83; // Upper 32 bits of mhpmcounter3, RV32I only.
localparam CSR_NUM_MHPMCOUNTER4H = 12'hB84; // Upper 32 bits of mhpmcounter4, RV32I only.
// ... TODO: Define these counters
localparam CSR_NUM_MHPMCOUNTER31H = 12'hB9F; // Upper 32 bits of mhpmcounter31, RV32I only.

//
// Machine Counter Setup
//
localparam CSR_NUM_MHPMEVENT3    = 12'h323; // Machine performance-monitoring event selector.
localparam CSR_NUM_MHPMEVENT4    = 12'h324; // Machine performance-monitoring event selector.
// ... TODO: Define these counters
localparam CSR_NUM_MHPMEVENT31   = 12'h33F; // Machine performance-monitoring event selector.

//
// Debug/Trace Registers (shared with Debug Mode)
//
localparam CSR_NUM_TSELECT   = 12'h7A0; // Debug/Trace trigger register select.
localparam CSR_NUM_TDATA1    = 12'h7A1; // First Debug/Trace trigger data register.
localparam CSR_NUM_TDATA2    = 12'h7A2; // Second Debug/Trace trigger data register.
localparam CSR_NUM_TDATA3    = 12'h7A3; // Third Debug/Trace trigger data register.


// Debug Mode Registers
localparam CSR_NUM_DCSR      = 12'h7B0; // Debug control and status register.
localparam CSR_NUM_DPC       = 12'h7B1; // Debug PC.
localparam CSR_NUM_DSCRATCH  = 12'h7B2; // Debug scratch register.


endpackage


