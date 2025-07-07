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

typedef enum logic [1:0] {
    PRIVILEGE_LEVEL_M = 2'b11,
    PRIVILEGE_LEVEL_S = 2'b01,
    PRIVILEGE_LEVEL_U = 2'b00
} PrivilegeLevelType;

// If you add additional status bits, check CSR_Unit.sv because 
// only valid fields are updated.
typedef struct packed {
    logic [8:0] padding_7;  // 31:23
    logic TSR;              // 22
    logic padding_6;        // 21
    logic TVM;              // 20
    logic MXR;              // 19
    logic SUM;              // 18
    logic [4:0] padding_5;  // 17:13
    PrivilegeLevelType MPP; // 12:11
    logic [1:0] padding_4;  // 10:9
    logic SPP;              // 8
    logic MPIE;             // 7
    logic padding_3;        // 6
    logic SPIE;             // 5
    logic padding_2;        // 4
    logic MIE;              // 3
    logic padding_1;        // 2
    logic SIE;              // 1
    logic padding_0;        // 0
} CSR_MSTATUS_Path;

// If you add additional sstatus fields,
// add fields that will be copied from/to mstatus in ToSstatusFromMstatus/ToMstatusFromSstatus
typedef struct packed {
    logic [11:0] padding_4; // 31:20
    logic MXR;              // 19
    logic SUM;              // 18
    logic [8:0] padding_3;  // 17:9
    logic SPP;              // 8
    logic [1:0] padding_2;  // 7:6
    logic SPIE;             // 5
    logic [2:0] padding_1;  // 4:2
    logic SIE;              // 1
    logic padding_0;        // 0
} CSR_SSTATUS_Path;

function automatic CSR_SSTATUS_Path ToSstatusFromMstatus(input CSR_MSTATUS_Path mstatus);
    CSR_SSTATUS_Path value;
    value      = '0;
    value.MXR  = mstatus.MXR ;
    value.SUM  = mstatus.SUM ;
    value.SPP  = mstatus.SPP ;
    value.SPIE = mstatus.SPIE;
    value.SIE  = mstatus.SIE ;
    return value;
endfunction

function automatic CSR_MSTATUS_Path ToMstatusFromSstatus(input CSR_SSTATUS_Path sstatus, input CSR_MSTATUS_Path currentMstatus);
    CSR_MSTATUS_Path value;
    value      = currentMstatus;
    value.MXR  = sstatus.MXR ;
    value.SUM  = sstatus.SUM ;
    value.SPP  = sstatus.SPP ;
    value.SPIE = sstatus.SPIE;
    value.SIE  = sstatus.SIE ;
    return value;
endfunction

function automatic PrivilegeLevelType ToPrivilegeLevelFromSPP(input logic SPP);
    return SPP ? PRIVILEGE_LEVEL_S : PRIVILEGE_LEVEL_U;
endfunction

function automatic logic ToSPP_FromPrivilegeLevel(input PrivilegeLevelType privilegeLevel);
    assert(privilegeLevel inside {PRIVILEGE_LEVEL_U, PRIVILEGE_LEVEL_S});
    return privilegeLevel == PRIVILEGE_LEVEL_S;
endfunction

// Machine ISA
typedef struct packed {
    logic Z;
    logic Y;
    logic X;
    logic W;
    logic V;
    logic U;
    logic T;
    logic S;
    logic R;
    logic Q;
    logic P;
    logic O;
    logic N;
    logic M;
    logic L;
    logic K;
    logic J;
    logic I;
    logic H;
    logic G;
    logic F;
    logic E;
    logic D;
    logic C;
    logic B;
    logic A;
} CSR_MISA_ExtensionsType;

typedef struct packed {
    logic [1:0] MXL; // 31:30
    logic [3:0] padding_0; // 29:26
    CSR_MISA_ExtensionsType EXTENSIONS; // 25:0
} CSR_MISA_Path;

// Interrupt pending?
typedef struct packed {
    logic [19:0] padding_6; // 31:12
    logic MEIP;             // 11:11    machine external interrupt
    logic padding_5;        // 10:10
    logic SEIP;             // 11:11    supervisor external interrupt
    logic padding_4;        // 8:8
    logic MTIP;             // 7:7      machine timer interrupt
    logic padding_3;        // 6:6
    logic STIP;             // 5:5      supervisor timer interrupt
    logic padding_2;        // 4:4
    logic MSIP;             // 3:3      machine software interrupt
    logic padding_1;        // 2:2
    logic SSIP;             // 1:1      supervisor software interrupt
    logic padding_0;        // 0:0
} CSR_MIP_Path;

typedef struct packed {
    logic [21:0] padding_3; // 31:10
    logic SEIP;             // 9:9    supervisor external interrupt
    logic [2:0] padding_2;  // 8:6
    logic STIP;             // 5:5    supervisor timer interrupt
    logic [2:0] padding_1;  // 4:2
    logic SSIP;             // 1:1    supervisor software interrupt
    logic padding_0;        // 0:0
} CSR_SIP_Path;

// Interrupt enable?
typedef struct packed {
    logic [19:0] padding_6; // 31:12
    logic MEIE;             // 11:11    machine external interrupt
    logic padding_5;        // 10:10
    logic SEIE;             // 9:9      supervisor external interrupt
    logic padding_4;        // 8:8
    logic MTIE;             // 7:7      machine timer interrupt
    logic padding_3;        // 6:6
    logic STIE;             // 5:5      supervisor timer interrupt
    logic padding_2;        // 4:4
    logic MSIE;             // 3:3      machine software interrupt
    logic padding_1;        // 2:2
    logic SSIE;             // 1:1      supervisor software interrupt
    logic padding_0;        // 0:0
} CSR_MIE_Path;

typedef struct packed {
    logic [21:0] padding_3; // 31:10
    logic SEIE;             // 9:9    supervisor external interrupt
    logic [2:0] padding_2;  // 8:6
    logic STIE;             // 5:5    supervisor timer interrupt
    logic [2:0] padding_1;  // 4:2
    logic SSIE;             // 1:1    supervisor software interrupt
    logic padding_0;        // 0:0
} CSR_SIE_Path;

typedef struct packed {
    logic [21:0] padding_3; // 31:10
    logic SEI;              // 9:9    supervisor external interrupt
    logic [2:0] padding_2;  // 8:6
    logic STI;              // 5:5    supervisor timer interrupt
    logic [2:0] padding_1;  // 4:2
    logic SSI;              // 1:1    supervisor software interrupt
    logic padding_0;        // 0:0
} CSR_MIDELEG_Path;

typedef enum logic [4:0] {
    CSR_CAUSE_TRAP_CODE_INSN_MISALIGNED = 0,
    CSR_CAUSE_TRAP_CODE_INSN_VIOLATION = 1,
    CSR_CAUSE_TRAP_CODE_INSN_ILLEGAL = 2,
    CSR_CAUSE_TRAP_CODE_BREAK = 3,
    CSR_CAUSE_TRAP_CODE_LOAD_MISALIGNED = 4,
    CSR_CAUSE_TRAP_CODE_LOAD_VIOLATION = 5,
    CSR_CAUSE_TRAP_CODE_STORE_MISALIGNED = 6,
    CSR_CAUSE_TRAP_CODE_STORE_VIOLATION = 7,
    CSR_CAUSE_TRAP_CODE_UCALL = 8,
    CSR_CAUSE_TRAP_CODE_SCALL = 9,
    CSR_CAUSE_TRAP_CODE_MCALL = 11,

    CSR_CAUSE_TRAP_CODE_UNKNOWN = 14
} CSR_CAUSE_TrapCodePath;

function automatic CSR_CAUSE_TrapCodePath ToTrapCodeFromExecState(ExecutionState state, PrivilegeLevelType priv);
    case(state)
    EXEC_STATE_TRAP_ECALL: begin
        case (priv)
            PRIVILEGE_LEVEL_U: return CSR_CAUSE_TRAP_CODE_UCALL;
            PRIVILEGE_LEVEL_S: return CSR_CAUSE_TRAP_CODE_SCALL;
            PRIVILEGE_LEVEL_M: return CSR_CAUSE_TRAP_CODE_MCALL;
            default: return CSR_CAUSE_TRAP_CODE_UNKNOWN;
        endcase
    end
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

localparam CSR_CAUSE_INTERRUPT_CODE_WIDTH = 5;
typedef enum logic [CSR_CAUSE_INTERRUPT_CODE_WIDTH-1:0] {
    CSR_CAUSE_INTERRUPT_CODE_TIMER = 7,
    CSR_CAUSE_INTERRUPT_CODE_MACHINE_EXTERNAL = 11
} CSR_CAUSE_InterruptCodePath;

typedef union packed    // IntOpInfo
{
    ExternalInterruptCodePath   exCode;
    CSR_CAUSE_InterruptCodePath csrCode;
} InterruptCodeConvPath;


typedef union packed    // CSR_CAUSE_CodePath
{
    CSR_CAUSE_TrapCodePath trapCode;
    CSR_CAUSE_InterruptCodePath  interruptCode;
} CSR_CAUSE_CodePath;

typedef struct packed {
    logic isInterrupt;          // 31
    logic [25:0] padding;       // 30:5
    CSR_CAUSE_CodePath code;    //  4:0
} CSR_CAUSE_Path;


typedef enum logic [1:0] {
    CSR_XTVEC_MODE_BASE = 0,
    CSR_XTVEC_MODE_VECTORED = 1
} CSR_XTVEC_ModePath;

typedef struct packed {
    logic [29:0]        base;    // 31:2
    CSR_XTVEC_ModePath  mode;    //  1:0
} CSR_XTVEC_Path;

typedef struct packed {
    logic [23:0] padding;
    Rounding_Mode frm;
    FFlags_Path fflags;
} CSR_FCSR_Path;

localparam logic [1:0] CSR_XTVEC_BASE_PADDING = 2'b0;

// All members have 32bit width
typedef union packed {
    CSR_SIP_Path    sip;
    CSR_SIE_Path    sie;
    CSR_XTVEC_Path  stvec;
    DataPath        sscratch;
    DataPath        sepc;
    CSR_CAUSE_Path  scause;
    DataPath        stval;

    CSR_MSTATUS_Path mstatus;
    CSR_MIP_Path mip;
    CSR_MIE_Path mie;
    CSR_CAUSE_Path mcause;
    CSR_XTVEC_Path mtvec;
    DataPath mtval;
    DataPath mepc;
    DataPath mscratch;
    DataPath medeleg;
    DataPath medelegh;
    CSR_MIDELEG_Path mideleg;

    CSR_MISA_Path misa;

    DataPath mcycle;
    DataPath minstret;
    CSR_FCSR_Path fcsr;
} CSR_ValuePath;

typedef struct packed {
    // Interrupt related registers
    CSR_SIE_Path    sie;
    CSR_XTVEC_Path  stvec;
    DataPath        sscratch;
    DataPath        sepc;
    CSR_CAUSE_Path  scause;
    DataPath        stval;

    CSR_MSTATUS_Path mstatus;
    CSR_MIP_Path mip;
    CSR_MIE_Path mie;
    CSR_CAUSE_Path mcause;
    CSR_XTVEC_Path mtvec;
    DataPath mtval;
    DataPath mepc;
    DataPath mscratch;
    DataPath medeleg;
    DataPath medelegh;
    CSR_MIDELEG_Path mideleg;

    CSR_MISA_Path misa;

    DataPath mcycle;
    DataPath minstret;
`ifdef RSD_MARCH_FP_PIPE
    CSR_FCSR_Path fcsr;
`endif
} CSR_BodyPath;

//
// Supervisor Trap Setup
//
localparam CSR_NUM_SSTATUS    = 12'h100; // Supervisor status register.
localparam CSR_NUM_SIE        = 12'h104; // Supervisor interrupt-enable register.
localparam CSR_NUM_STVEC      = 12'h105; // Supervisor trap handler base address.
localparam CSR_NUM_SCOUNTEREN = 12'h106; // Supervisor counter enable.

//
// Supervisor Configuration
//
localparam CSR_NUM_SENVCFG = 12'h10A; // Supervisor environment configuration register.

//
// Supervisor Counter Setup
//
localparam CSR_NUM_SCOUNTINHIBIT = 12'h120; // Supervisor counter-inhibit register.

//
// Supervisor Trap Handling
//
localparam CSR_NUM_SSCRATCH = 12'h140; // Supervisor scratch register.
localparam CSR_NUM_SEPC = 12'h141; // Supervisor exception program counter.
localparam CSR_NUM_SCAUSE = 12'h142; // Supervisor trap cause.
localparam CSR_NUM_STVAL = 12'h143; // Supervisor trap value.
localparam CSR_NUM_SIP = 12'h144; // Supervisor interrupt pending.
localparam CSR_NUM_SCOUNTOVF = 12'hDA0; // Supervisor count overflow.

//
// Supervisor Protection and Translation
//
localparam CSR_NUM_SATP = 12'h180; // Supervisor address translation and protection.
//
// Debug/Trace Registers
//
localparam CSR_NUM_SCONTEXT = 12'h5A8; // Supervisor-mode context register.

//
// Supervisor State Enable Registers
//
localparam CSR_NUM_SSTATEEN0 = 12'h10C; // Supervisor State Enable 0 Register.
localparam CSR_NUM_SSTATEEN1 = 12'h10D;
localparam CSR_NUM_SSTATEEN2 = 12'h10E;
localparam CSR_NUM_SSTATEEN3 = 12'h10F;

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
localparam CSR_NUM_MSTATUSH  = 12'h310; // Additional machine status register, RV32 only.
localparam CSR_NUM_MEDELEGH  = 12'h312; // Upper 32 bits of medeleg, RV32 only.

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
                                            // hB01 is absence
localparam CSR_NUM_MINSTRET      = 12'hB02; // Machine instructions-retired counter.

// Machine performance-monitoring counter.
localparam CSR_NUM_MHPMCOUNTER3   = 12'hB03; 
localparam CSR_NUM_MHPMCOUNTER4   = 12'hB04;
localparam CSR_NUM_MHPMCOUNTER5   = 12'hB05;
localparam CSR_NUM_MHPMCOUNTER6   = 12'hB06;
localparam CSR_NUM_MHPMCOUNTER7   = 12'hB07;
localparam CSR_NUM_MHPMCOUNTER8   = 12'hB08;
localparam CSR_NUM_MHPMCOUNTER9   = 12'hB09;
localparam CSR_NUM_MHPMCOUNTER10  = 12'hB0A;
localparam CSR_NUM_MHPMCOUNTER11  = 12'hB0B;
localparam CSR_NUM_MHPMCOUNTER12  = 12'hB0C;
localparam CSR_NUM_MHPMCOUNTER13  = 12'hB0D;
localparam CSR_NUM_MHPMCOUNTER14  = 12'hB0E;
localparam CSR_NUM_MHPMCOUNTER15  = 12'hB0F;
// ... TODO: Define these counters
localparam CSR_NUM_MHPMCOUNTER31 = 12'hB1F;

localparam CSR_NUM_MCYCLEH       = 12'hB80; // Upper 32 bits of mcycle, RV32I only.
                                            // hB81 is absence
localparam CSR_NUM_MINSTRETH     = 12'hB82; // Upper 32 bits of minstret, RV32I only.

// Upper 32 bits of mhpmcounterX, RV32I only.
localparam CSR_NUM_MHPMCOUNTER3H  = 12'hB83;
localparam CSR_NUM_MHPMCOUNTER4H  = 12'hB84;
localparam CSR_NUM_MHPMCOUNTER5H  = 12'hB85;
localparam CSR_NUM_MHPMCOUNTER6H  = 12'hB86;
localparam CSR_NUM_MHPMCOUNTER7H  = 12'hB87;
localparam CSR_NUM_MHPMCOUNTER8H  = 12'hB88;
localparam CSR_NUM_MHPMCOUNTER9H  = 12'hB89;
localparam CSR_NUM_MHPMCOUNTER10H = 12'hB8A;
localparam CSR_NUM_MHPMCOUNTER11H = 12'hB8B;
localparam CSR_NUM_MHPMCOUNTER12H = 12'hB8C;
localparam CSR_NUM_MHPMCOUNTER13H = 12'hB8D;
localparam CSR_NUM_MHPMCOUNTER14H = 12'hB8E;
localparam CSR_NUM_MHPMCOUNTER15H = 12'hB8F;
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

// Floating-Point CSRs
localparam CSR_NUM_FFLAGS    = 12'h001; // FP accrued exceptions.
localparam CSR_NUM_FRM       = 12'h002; // FP dynamic rounding mode.
localparam CSR_NUM_FCSR      = 12'h003; // FP CSR (frm + fflags)

endpackage


