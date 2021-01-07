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
    
    // Dキャッシュミスしたかどうか
    logic loadMiss[LOAD_ISSUE_WIDTH];
    logic storeMiss[STORE_ISSUE_WIDTH];
    
    // コミット関係
    logic storeLoadForwardingFail;
    logic memDepPredMiss;
    logic branchPredMiss;
    
    modport HardwareCounter (
    input
        clk,
        rst,
        loadMiss,
        storeMiss,
        storeLoadForwardingFail,
        memDepPredMiss,
        branchPredMiss,
    output
        perfCounter
    );

    modport MemoryTagAccessStage (
    output
        loadMiss
    );
    
    modport RecoveryManager (
    output
        storeLoadForwardingFail,
        memDepPredMiss,
        branchPredMiss
    );

    modport StoreCommitter (
    output
        storeMiss
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
    
    modport LoadStoreUnit(input clk);
    modport MemoryTagAccessStage(input clk);
    modport RecoveryManager(input clk);
    modport CSR(input clk);
    modport StoreCommitter(input clk);
`endif


endinterface : HardwareCounterIF
