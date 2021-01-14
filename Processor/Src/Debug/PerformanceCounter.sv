// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`ifndef RSD_DISABLE_PERFORMANCE_COUNTER

import BasicTypes::*;
import DebugTypes::*;

module PerformanceCounter (
    PerformanceCounterIF.PerformanceCounter port,
    DebugIF.PerformanceCounter debug
);
    PerfCounterPath cur, next;
    always_ff @(posedge port.clk) begin
        cur <= port.rst ? '0 : next;
    end
    
    always_comb begin
        next = cur;
        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            if (port.loadMiss[i]) begin
                next.numLoadMiss++;
            end
        end
        for ( int i = 0; i < STORE_ISSUE_WIDTH; i++ ) begin
            if (port.storeMiss[i]) begin
                next.numStoreMiss++;
            end
        end
        next.numIC_Miss += port.icMiss ? 1 : 0;
        next.numStoreLoadForwardingFail += port.storeLoadForwardingFail ? 1 : 0;
        next.numMemDepPredMiss += port.memDepPredMiss ? 1 : 0;
        next.numBranchPredMiss += port.branchPredMiss ? 1 : 0;
        next.numBranchPredMissDetectedOnDecode += port.branchPredMissDetectedOnDecode ? 1 : 0;

        port.perfCounter = cur;  // Export current values
`ifndef RSD_DISABLE_DEBUG_REGISTER
        debug.perfCounter = next;    // Export next values for updating registers in debug
`endif
    end
    

endmodule : PerformanceCounter

`else

module PerformanceCounter (
    PerformanceCounterIF.PerformanceCounter port
);
    always_comb begin
        port.perfCounter = '0; // Suppressing warning.
    end
endmodule : PerformanceCounter

`endif
