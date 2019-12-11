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


