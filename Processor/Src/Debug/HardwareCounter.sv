// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`ifndef RSD_DISABLE_HARDWARE_COUNTER

import BasicTypes::*;
import DebugTypes::*;

module HardwareCounter (
    HardwareCounterIF.HardwareCounter port,
    DebugIF.HardwareCounter debug
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
        next.numRefetchThisPC += port.refetchThisPC ? 1 : 0;
        next.numRefetchNextPC += port.refetchNextPC ? 1 : 0;
        next.numRefetchBrTarget += port.refetchBrTarget ? 1 : 0;

        port.perfCounter = cur;  // Export current values
        debug.perfCounter = next;    // Export next values for updating registers in debug
    end
    

endmodule : HardwareCounter

`else

module HardwareCounter (
    HardwareCounterIF.HardwareCounter port
);
    always_comb begin
        port.perfCounter = '0; // Suppressing warning.
    end
endmodule : HardwareCounter

`endif
