// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// MemoryWriteDataQueue
//

`include "SysDeps/XilinxMacros.vh"

import BasicTypes::*;
import MemoryTypes::*;

module MemoryWriteDataQueue ( 
input 
    logic clk,
    logic rst,
    logic push,
    logic pop,
    MemoryEntryDataPath pushedData,
output
    logic full,
    logic empty,
    MemoryEntryDataPath headData,
    logic [`MEMORY_AXI4_WRITE_ID_WIDTH-1: 0] headPtr,
    logic [`MEMORY_AXI4_WRITE_ID_WIDTH-1: 0] tailPtr
);

    // typedef logic [`MEMORY_AXI4_WRITE_ID_WIDTH-1: 0] IndexPath;

    // IndexPath headPtr;
    // IndexPath tailPtr;

    // size, initial head, initial tail, initial count
    QueuePointer #( `MEMORY_AXI4_WRITE_ID_NUM, 0, 0, 0 )
        pointer(
            .clk( clk ),
            .rst( rst ),
            .push( push ),
            .pop( pop ),
            .full( full ),
            .empty( empty ),
            .headPtr( headPtr ),
            .tailPtr( tailPtr )
        );
        

    logic [ MEMORY_ENTRY_BIT_NUM-1:0 ] memoryWriteDataQueue[ `MEMORY_AXI4_WRITE_ID_NUM ]; // synthesis syn_ramstyle = "select_ram"

    always_ff @( posedge clk ) begin
        if( push ) begin
            memoryWriteDataQueue[ tailPtr ] <= pushedData;
        end
    end
    
    always_comb begin
        headData = memoryWriteDataQueue[ headPtr ];
    end

endmodule : MemoryWriteDataQueue

 