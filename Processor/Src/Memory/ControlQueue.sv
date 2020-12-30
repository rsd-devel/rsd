// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// ControlQueue
//

`include "SysDeps/XilinxMacros.vh"

import BasicTypes::*;
import MemoryTypes::*;

module ControlQueue ( 
input 
    logic clk,
    logic rst,
    logic push,
    logic pop,
    logic [ `PS_PL_CTRL_QUEUE_DATA_BIT_SIZE-1:0 ] pushedData,
output
    logic full,
    logic empty,
    logic [ `PS_PL_CTRL_QUEUE_DATA_BIT_SIZE-1:0 ] headData
);

    typedef logic [`PS_PL_CTRL_QUEUE_ADDR_BIT_SIZE-1:0] IndexPath;

    IndexPath headPtr;
    IndexPath tailPtr;

    // size, initial head, initial tail, initial count
    QueuePointer #( `PS_PL_CTRL_QUEUE_SIZE, 0, 0, 0 )
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
        

    logic [ `PS_PL_CTRL_QUEUE_DATA_BIT_SIZE-1:0 ] controlQueue[ `PS_PL_CTRL_QUEUE_SIZE ]; // synthesis syn_ramstyle = "select_ram"

    always_ff @( posedge clk ) begin
        if( push ) begin
            controlQueue[ tailPtr ] <= pushedData;
        end
    end
    
    always_comb begin
        headData = controlQueue[ headPtr ];
    end

endmodule : ControlQueue

 