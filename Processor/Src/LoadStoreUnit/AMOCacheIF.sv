import BasicTypes::*;
import MemoryMapTypes::*;

interface AMOCacheIF( input logic clk, rst );
    logic           cached;
    PhyAddrPath     readAddr;
    PRegDataPath    readDataOut;

    logic           writeEnable;
    PhyAddrPath     writeAddr;
    PRegDataPath    writeData;

    logic           invalidate;

    modport AMOCache (
    input
        clk,
        rst,
        writeEnable,
        writeAddr,
        writeData,
        invalidate,
    output
        cached,
        readAddr,
        readDataOut
    );

    modport MemoryExecutionStage (
    input
        readDataOut
    );

    modport MemoryTagAccessStage (
    input
        cached,
        readAddr
    );

    modport MemoryAccessStage (
    output
        writeEnable,
        writeAddr,
        writeData,
        invalidate
    );
endinterface