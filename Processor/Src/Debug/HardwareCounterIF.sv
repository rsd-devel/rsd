// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- HardwareCounterIF
//

import BasicTypes::*;
import DebugTypes::*;

interface HardwareCounterIF( input logic clk, rst );
    
`ifndef RSD_DISABLE_HARDWARE_COUNTER
    // LoadStoreUnitでハードウェアカウンタを読み出す際の信号線
    HardwareCounterType hardwareCounterType[ LOAD_ISSUE_WIDTH ];
    DataPath hardwareCounterData[ LOAD_ISSUE_WIDTH ];
    
    // ロードがDキャッシュミスしたかどうか
    logic loadMiss[ MEM_ISSUE_WIDTH ];
    
    // コミット関係
    CommitLaneCountPath commitNum;
    logic refetchThisPC;
    logic refetchNextPC;
    logic refetchBrTarget;
    
    modport HardwareCounter (
    input
        clk,
        rst,
        loadMiss,
        commitNum,
        refetchThisPC,
        refetchNextPC,
        refetchBrTarget,
        hardwareCounterType,
    output
        hardwareCounterData
    );
    
    modport LoadStoreUnit (
    input
        hardwareCounterData,
    output
        hardwareCounterType
    );
    
    modport MemoryTagAccessStage (
    output
        loadMiss
    );
    
    modport CommitStage (
    output
        commitNum,
        refetchThisPC,
        refetchNextPC,
        refetchBrTarget
    );
`else
    // Dummy to surpress warning.
    DataPath hardwareCounterData[ LOAD_ISSUE_WIDTH ];

    modport HardwareCounter (
    input
        clk,
    output
        hardwareCounterData
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
`endif


endinterface : HardwareCounterIF
