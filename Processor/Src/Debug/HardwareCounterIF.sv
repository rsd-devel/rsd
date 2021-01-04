// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- HardwareCounterIF
//

import BasicTypes::*;
import DebugTypes::*;

interface HardwareCounterIF( input logic clk, rst );
    
`ifndef RSD_DISABLE_HARDWARE_COUNTER
    
    // Hardware counter exported to CSR
    PerfCounterPath perfCounter;
    
    // ロードがDキャッシュミスしたかどうか
    logic loadMiss[LOAD_ISSUE_WIDTH];
    
    // コミット関係
    logic refetchThisPC;
    logic refetchNextPC;
    logic refetchBrTarget;
    
    modport HardwareCounter (
    input
        clk,
        rst,
        loadMiss,
        refetchThisPC,
        refetchNextPC,
        refetchBrTarget,
    output
        perfCounter
    );

    modport MemoryTagAccessStage (
    output
        loadMiss
    );
    
    modport CommitStage (
    output
        refetchThisPC,
        refetchNextPC,
        refetchBrTarget
    );

    modport CSR (
    input
        perfCounter
    );
`else
    // Dummy to suppress warning.
    PerfCounterPath perfCounter;

    modport HardwareCounter (
    input
        clk,
    output
        perfCounter
    );
    
    modport LoadStoreUnit (
        input clk
    );
    
    modport MemoryTagAccessStage (
        input clk
    );

    modport CommitStage (
        input clk
    );

    modport CSR (
        input clk
    );
`endif


endinterface : HardwareCounterIF
