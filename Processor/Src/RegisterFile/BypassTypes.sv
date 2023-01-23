// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


// 
// --- Types related to bypass network.
//

package BypassTypes;

import BasicTypes::*;

typedef enum logic unsigned [1:0]   // enum BypassSelect
{
    BYPASS_STAGE_INT_EX = 0,
    BYPASS_STAGE_INT_WB = 1,
    BYPASS_STAGE_MEM_MA = 2,
    BYPASS_STAGE_MEM_WB = 3
} BypassSelectStage;


typedef struct packed {
    // TODO: unionで実装
    IntIssueLaneIndexPath intLane;
    ComplexIssueLaneIndexPath complexLane;
    MemIssueLaneIndexPath memLane;
`ifdef RSD_ENABLE_FP_PATH
    FPIssueLaneIndexPath fpLane;
`endif
} BypassLane;

typedef struct packed {
    logic valid; // バイパスするか否か
    BypassSelectStage stg;
    BypassLane lane;
} BypassSelect;

typedef struct packed {
    BypassSelect rA;
    BypassSelect rB;
`ifdef RSD_ENABLE_FP_PATH
    BypassSelect rC;
`endif
} BypassControll;

endpackage