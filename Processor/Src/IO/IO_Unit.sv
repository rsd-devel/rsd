// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// UI Unit
//

`include "BasicMacros.sv"

import BasicTypes::*;
import LoadStoreUnitTypes::*;
import MemoryMapTypes::*;
import IO_UnitTypes::*;
import DebugTypes::*;

module IO_Unit(
    IO_UnitIF.IO_Unit port,
    CSR_UnitIF.IO_Unit csrUnit
);

    // Timer register
    TimerRegsters tmReg;
    TimerRegsters tmNext;
    always_ff@(posedge port.clk) begin
        if (port.rst) begin
            tmReg <= '0;
        end
        else begin
            tmReg <= tmNext;
        end
    end

    PhyRawAddrPath phyRawReadAddr, phyRawWriteAddr;

    always_comb begin
        phyRawReadAddr = port.ioReadAddrIn.addr;
        phyRawWriteAddr = port.ioWriteAddrIn.addr;

        // Update timer
        tmNext = tmReg;
        tmNext.mtime.raw = tmNext.mtime.raw + 1;

        // Generate a timer interrupt signal
        csrUnit.reqTimerInterrupt = 
            tmNext.mtime.raw >= tmNext.mtimecmp.raw ? TRUE : FALSE;
        //$display("time, cmp: %d, %d", tmNext.mtime.raw, tmNext.mtimecmp.raw);

        // Write a timer regsiter
        if (port.ioWE) begin
            //$display("IO write %0x: %0x", port.ioWriteAddrIn, port.ioWriteDataIn);
            if (phyRawWriteAddr == PHY_ADDR_TIMER_LOW) begin
                tmNext.mtime.split.low = port.ioWriteDataIn;
            end
            else if (phyRawWriteAddr == PHY_ADDR_TIMER_HI) begin
                tmNext.mtime.split.hi = port.ioWriteDataIn;
            end
            else if (phyRawWriteAddr == PHY_ADDR_TIMER_CMP_LOW) begin
                tmNext.mtimecmp.split.low = port.ioWriteDataIn;
            end
            else if (phyRawWriteAddr == PHY_ADDR_TIMER_CMP_HI) begin
                tmNext.mtimecmp.split.hi = port.ioWriteDataIn;
            end
            //$display(tmNext.mtime.raw);
            //$display(tmNext.mtimecmp.raw);
        end

        // Read a timer rigister
        if (phyRawReadAddr == PHY_ADDR_TIMER_LOW) begin
            port.ioReadDataOut = tmReg.mtime.split.low;
        end
        else if (phyRawReadAddr == PHY_ADDR_TIMER_HI) begin
            port.ioReadDataOut = tmReg.mtime.split.hi;
        end
        else if (phyRawReadAddr == PHY_ADDR_TIMER_CMP_LOW) begin
            port.ioReadDataOut = tmReg.mtimecmp.split.low;
        end
        else begin
            //if (port.ioReadAddrIn == PHY_ADDR_TIMER_CMP_HI) begin
            port.ioReadDataOut = tmReg.mtimecmp.split.hi;
        end
    end


    always_comb begin
        // Serial IO
        port.serialWE = FALSE;
        port.serialWriteDataOut = port.ioWriteDataIn[SERIAL_OUTPUT_WIDTH-1 : 0];
        if (port.ioWE && phyRawWriteAddr == PHY_ADDR_SERIAL_OUTPUT) begin
            port.serialWE = TRUE;
        end
    end
endmodule
