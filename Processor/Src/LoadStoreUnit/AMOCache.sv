
`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;

module AMOCache(
    AMOCacheIF.AMOCache port
);
    logic           cacheValid;
    PhyAddrPath     cachedAddr;
    PRegDataPath    cachedData;

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            cacheValid <= FALSE;
            cachedAddr <= '0;
            cachedData <= '0;
        end
        else if (port.writeEnable) begin
            cacheValid <= TRUE;
            cachedAddr <= port.writeAddr;
            cachedData <= port.writeData;
        end
        else if (port.invalidate) begin
            cacheValid <= FALSE;
        end
    end

    always_ff @(posedge port.clk) begin
        port.cached <= cacheValid;
        port.readAddr <= cachedAddr;
        port.readDataOut <= cachedData;
    end
endmodule
