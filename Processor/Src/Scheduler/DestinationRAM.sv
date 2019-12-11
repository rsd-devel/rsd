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

    //
    // Destination register number
    //

    typedef struct packed // Entry
    {
        SchedulerRegTag  regTag;
    } Entry;

    logic write[DISPATCH_WIDTH];
    IssueQueueIndexPath writePtr[DISPATCH_WIDTH];
    Entry writeData[DISPATCH_WIDTH];
    IssueQueueIndexPath readPtr[WAKEUP_WIDTH];
    Entry readData[WAKEUP_WIDTH];

    DistributedMultiPortRAM #(
        .ENTRY_NUM( ISSUE_QUEUE_ENTRY_NUM ),
        .ENTRY_BIT_SIZE( $bits(Entry) ),
        .READ_NUM( WAKEUP_WIDTH ),
        .WRITE_NUM( DISPATCH_WIDTH )
    ) dstRAM (
        .clk( port.clk ),
        .we( write ),
        .wa( writePtr ),
        .wv( writeData ),
        .ra( readPtr ),
        .rv( readData )
    );

    IssueQueueIndexPath rstIndex;
    always_ff @ (posedge port.clk) begin
        if (port.rstStart || rstIndex >= ISSUE_QUEUE_ENTRY_NUM-1) begin
            rstIndex <= 0;
        end
        else begin
            rstIndex <= rstIndex + 1;
        end
    end

    always_comb begin
        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
            write[i] = port.write[i];
            writePtr[i] = port.writePtr[i];
            writeData[i].regTag = port.writeDstTag[i].regTag;
        end

        for (int i = 0; i < WAKEUP_WIDTH; i++) begin
            port.wakeupDstTag[i].regTag = readData[i].regTag;
        end

        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            readPtr[i] = port.wakeupPtr[i];
        end
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            readPtr[(i+INT_ISSUE_WIDTH)] = port.wakeupPtr[(i+INT_ISSUE_WIDTH)];
        end
        for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            readPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = port.wakeupPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)];
        end
        // Stores do not wake up consumers.


        // Reset sequence.
        if (port.rst) begin
            for (int i = 0; i < DISPATCH_WIDTH; i++) begin
                write[i] = FALSE;
            end
            write[0] = TRUE;
            writePtr[0] = rstIndex;
            writeData[0] = '0;
        end
    end

endmodule : DestinationRAM



