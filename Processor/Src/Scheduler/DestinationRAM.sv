// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Scheduler::DestinationRAM
// DestinationRAM is a table that has destination register numbers.
// It is looked up with the id of a woke up op in the IQ.
//

import BasicTypes::*;
import SchedulerTypes::*;

module DestinationRAM (WakeupSelectIF.DestinationRAM port);

    ResettableDistributedMultiPortRAM #(
        .ENTRY_NUM( ISSUE_QUEUE_ENTRY_NUM ),
        .ENTRY_BIT_SIZE( $bits(SchedulerDstTag) ),
        .READ_NUM( WAKEUP_WIDTH ),
        .WRITE_NUM( DISPATCH_WIDTH ),
        .RESET_VALUE( '0 )
    ) dstRAM (
        .clk( port.clk ),
        .rst( port.rst ),
        .rstStart( port.rstStart ),
        .we( port.write ),
        .wa( port.writePtr ),
        .wv( port.writeDstTag ),
        .ra( port.wakeupPtr ),
        .rv( port.wakeupDstTag )
    );

endmodule : DestinationRAM



