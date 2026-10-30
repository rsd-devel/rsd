// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

import BasicTypes::*;
import LoadStoreUnitTypes::*;
import IO_UnitTypes::*;
import MemoryMapTypes::*;

interface PLIC_UnitIF(
    input 
        logic clk, rst, rstStart
);

    logic ioWE;
    DataPath ioWriteDataIn;
    PhyAddrPath phyRawWriteAddrIn;
    logic ioRE;
    PhyAddrPath phyRawReadAddrIn;
    DataPath ioReadDataOut;

    // Interrupt Source -> PLIC_Unit
    logic interruptReqFromInterruptSource [PLIC_NUM_SOURCES:0]; // source 0 is unused

    // PLIC_Unit -> InterruptController
    logic [PLIC_NUM_CONTEXTS-1:0] reqExternalInterrupt;

    modport IO_Unit (
    input
        ioReadDataOut,
    output
        ioWE,
        ioWriteDataIn,
        phyRawWriteAddrIn,
        ioRE,
        phyRawReadAddrIn
    );

    modport CSR_Unit (
    input
        reqExternalInterrupt
    );

    modport PLIC_Unit (
    input
        clk, rst, rstStart,
        ioWE,
        ioWriteDataIn,
        phyRawWriteAddrIn,
        ioRE,
        phyRawReadAddrIn,
        interruptReqFromInterruptSource,
    output
        ioReadDataOut,
        reqExternalInterrupt
    );

endinterface : PLIC_UnitIF
