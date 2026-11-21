// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`include "SysDeps/XilinxMacros.vh"

module TestSerialOutput;
    import MemoryMapTypes::*;
    import IO_UnitTypes::*;

    localparam DEPTH = `PS_PL_CTRL_QUEUE_SIZE;
    localparam BYTES = 3 * DEPTH + 256;
    bit clk, rst;
    logic full, serialWE;
    SerialDataPath data;
    always #5 clk = !clk;

    Axi4LiteControlRegisterIF bus();
    assign bus.S_AXI_ACLK = clk;
    assign bus.S_AXI_ARESETN = !rst;
    IO_UnitIF ioPort(clk, rst, rst, full, serialWE, data);
    PLIC_UnitIF plicPort(clk, rst, rst, '0);
    CSR_UnitIF csrPort(clk, rst, rst);
    IO_Unit ioUnit(ioPort, plicPort, csrPort);
    Axi4LitePlToPsControlRegister fifo(bus, serialWE, data, '0, full);

    task automatic readPS(input int address, output int value);
        bus.S_AXI_ARADDR = address;
        bus.S_AXI_ARVALID = 1;
        do @(posedge clk); while (!bus.S_AXI_ARREADY);
        @(negedge clk);
        bus.S_AXI_ARVALID = 0;
        do @(posedge clk); while (!bus.S_AXI_RVALID);
        value = bus.S_AXI_RDATA;
        @(negedge clk);
    endtask

    task automatic expectStatus(input bit expectedFull);
        if (ioPort.ioReadDataOut !== 32'(expectedFull))
            $fatal(1, "Expected TX_FULL %0d, got %h", expectedFull, ioPort.ioReadDataOut);
    endtask

    task automatic sendByte(input int index);
        expectStatus(0);
        ioPort.ioWriteDataIn = index & 'hff;
        ioPort.ioWE = 1;
        @(negedge clk);
        ioPort.ioWE = 0;
    endtask

    task automatic expectByte(input int index);
        int value;
        readPS(4, value);
        if (value !== (index & 'hff))
            $fatal(1, "Byte %0d: expected %02h, got %h", index, index[7:0], value);
    endtask

    int value;
    initial begin
        rst = 1;
        bus.S_AXI_RREADY = 1;
        bus.S_AXI_ARVALID = 0;
        ioPort.ioRE = 1;
        ioPort.ioReadAddrIn = ToPhyAddrFromLogical(LOG_ADDR_SERIAL_STATUS);
        ioPort.ioWriteAddrIn = ToPhyAddrFromLogical(LOG_ADDR_SERIAL_STATUS);
        ioPort.ioWE = 0;
        repeat (3) @(negedge clk);
        rst = 0;
        // Writing the read-only status register must leave the FIFO empty.
        ioPort.ioWE = 1;
        ioPort.ioWriteDataIn = '1;
        @(negedge clk);
        ioPort.ioWE = 0;
        readPS(0, value);
        if (value !== 1) $fatal(1, "STATUS write enqueued a byte");
        ioPort.ioWriteAddrIn = ToPhyAddrFromLogical(LOG_ADDR_SERIAL_OUTPUT);

        for (int i = 0; i < DEPTH; i++) sendByte(i);
        // Keep reading STATUS with the ARM reader stopped.
        repeat (2 * DEPTH) begin
            expectStatus(1);
            @(negedge clk);
        end
        for (int i = DEPTH; i < BYTES; i++) begin
            expectStatus(1);
            expectByte(i - DEPTH);
            sendByte(i);
        end
        expectStatus(1);
        for (int i = BYTES - DEPTH; i < BYTES; i++) expectByte(i);
        expectStatus(0);
        readPS(0, value);
        if (value !== 1) $fatal(1, "FIFO should be empty after %0d bytes", BYTES);
        $display("SerialOutput passed (%0d bytes)", BYTES);
        $finish;
    end

    initial begin
        repeat (20 * BYTES) @(posedge clk);
        $fatal(1, "SerialOutput timed out");
    end
endmodule
