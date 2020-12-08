

// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// The interface of a cache flush management unit.
//


import BasicTypes::*;
import MemoryMapTypes::*;
import CacheSystemTypes::*;
import OpFormatTypes::*;
import LoadStoreUnitTypes::*;
import MemoryMapTypes::*;

interface CacheFlushManagerIF( input logic clk, rst );

    // CacheFlushManagement
    logic cacheFlushReq;
    logic cacheFlushComplete;

    modport CacheFlushManager(
    input
        clk,
        rst,
        cacheFlushReq,
    output
        cacheFlushComplete
    );

    modport MemoryExecutionStage(
    input
        cacheFlushComplete,
    output
        cacheFlushReq
    );

    modport ReplayQueue(
    input
        cacheFlushComplete
    );

endinterface : CacheFlushManagerIF
