// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


// 
// --- Types related to IO_Unit
//

package IO_UnitTypes;

import BasicTypes::*;

// Timer related definitions
localparam TIMER_REGISTER_WIDTH = 64;
typedef logic [TIMER_REGISTER_WIDTH-1:0] TimerRegisterRawPath;

typedef struct packed{    // struct TimerRegisterSplitPath
    DataPath hi;
    DataPath low;
} TimerRegisterSplitPath;

typedef union packed {
    TimerRegisterRawPath raw;
    TimerRegisterSplitPath split;
} TimerRegisterPath;

typedef struct packed {
    TimerRegisterPath mtime;
    TimerRegisterPath mtimecmp;
} TimerRegsters;

//
// --- PLIC related definitions
// Contextを追加するときは、メモリマップのPLICのサイズを広げること
// Source 1:
// Context 0+2k: hartid=k, M-mode
// Context 1+2k: hartid=k, S-mode
//
// ロードストアの取り扱い
// * IO_Unit -> PLIC_Unit -> IO_Unit -> CSR_Unit
// 割り込みの発生順序
// * Interrupt source -> PLIC_Unit -> CSR_Unit
localparam PLIC_NUM_SOURCES = 1;
localparam PLIC_NUM_CONTEXTS = 2;

localparam PLIC_NUM_SOURCES_BEGIN = 1;
localparam PLIC_NUM_SOURCES_END = PLIC_NUM_SOURCES + 1;

localparam PLIC_NUM_SOURCES_LOG = $clog2(PLIC_NUM_SOURCES+1);
localparam PLIC_NUM_ENABLE_REGS = (PLIC_NUM_SOURCES / 32) + 1;
localparam PLIC_NUM_PENDING_REGS = PLIC_NUM_ENABLE_REGS;

typedef struct packed { // struct PLIC_UnitRegisters
    logic [PLIC_NUM_SOURCES:0][31:0] sourcePriority;
    logic [PLIC_NUM_PENDING_REGS*32-1:0] pending;
    logic [PLIC_NUM_CONTEXTS-1:0][31:0] priorityThreshold;
    logic [PLIC_NUM_CONTEXTS-1:0][PLIC_NUM_SOURCES/32:0][31:0] enable;
} PLIC_UnitRegisters;

//
// --- LED IO
//
`ifndef RSD_SYNTHESIS
localparam LED_WIDTH = 16;
`elsif RSD_SYNTHESIS_ZEDBOARD
localparam LED_WIDTH = 8;
`else
localparam LED_WIDTH = 16;
`endif
typedef logic [ LED_WIDTH-1:0 ] LED_Path;

// Serial IO
`ifdef RSD_SYNTHESIS_FPGA
    localparam SERIAL_OUTPUT_WIDTH = 8;
`else
    localparam SERIAL_OUTPUT_WIDTH = 32;
`endif
typedef logic [ SERIAL_OUTPUT_WIDTH-1:0 ] SerialDataPath;



endpackage


