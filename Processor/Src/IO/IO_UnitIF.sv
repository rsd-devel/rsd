// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// The interface of a load/store unit.
//


import BasicTypes::*;
import LoadStoreUnitTypes::*;
import IO_UnitTypes::*;
import MemoryMapTypes::*;

interface IO_UnitIF(
    input 
        logic clk, rst, rstStart,
    output
        logic serialWE,
        SerialDataPath serialWriteDataOut
);
    // Write request from a store qeueue 
    logic ioWE;
    DataPath ioWriteDataIn;
    PhyAddrPath ioWriteAddrIn;

    // Read request from a load pipeline
    DataPath ioReadDataOut;
    PhyAddrPath ioReadAddrIn;

    modport IO_Unit(
    input 
        clk, rst, rstStart,
        ioWE,
        ioWriteDataIn,
        ioWriteAddrIn,
        ioReadAddrIn,
    output
        ioReadDataOut,
        serialWE,
        serialWriteDataOut
    );

    modport MemoryAccessStage(
    input 
        ioReadDataOut,
    output
        ioReadAddrIn
    );

    modport StoreCommitter(
    output
        ioWE,
        ioWriteDataIn,
        ioWriteAddrIn
    );


endinterface : IO_UnitIF


