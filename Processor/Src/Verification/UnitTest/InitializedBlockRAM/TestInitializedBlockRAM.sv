// Copyright 2026 RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
`timescale 1ns/1ps

module InitializedBlockRAMTestCase #(parameter WIDTH = 64)(output bit done);
    localparam BYTES = WIDTH / 8;
    localparam ENTRIES = 256 / BYTES;
    typedef logic [WIDTH-1:0] Value;
    logic clk = 0;
    always #5 clk = ~clk;
    logic we = 0;
    logic [$clog2(ENTRIES)-1:0] wa = 0, ra = 0;
    Value wv = '0, rv;
    Value expected[ENTRIES];
    // Use the same 128-bit sparse image at every port width to check address/lane mapping.
    InitializedBlockRAM #(.ENTRY_NUM(ENTRIES), .ENTRY_BIT_SIZE(WIDTH),
                          .INIT_HEX_FILE("Image.mem")) ram(.*);

    // The fixture contains byte addresses 0..15 and 64..127; all other bytes are absent.
    function automatic Value ImageWord(input int address);
        Value value;
        for (int b = 0; b < BYTES; b++) begin
            int offset;
            offset = address * BYTES + b;
            value[8*b+:8] = (offset < 16 || (offset >= 64 && offset < 128)) ?
                            8'(offset) : 8'hcd;
        end
        return value;
    endfunction

    task automatic Access(input bit writeEnable, input int writeAddress,
                          input Value writeValue, input int readAddress);
        Value previous;
        @(negedge clk);
        previous = rv;
        we = writeEnable;
        wa = writeAddress;
        wv = writeValue;
        ra = readAddress;
        #1;
        assert (rv === previous)
            else $fatal(1, "WIDTH=%0d: output changed before clock", WIDTH);
        @(posedge clk);
        if (writeEnable)
            expected[writeAddress] = writeValue;
        #1;
        assert (rv === expected[readAddress])
            else $fatal(1, "WIDTH=%0d address=%0d: expected %h, got %h",
                        WIDTH, readAddress, expected[readAddress], rv);
    endtask

    initial begin
        done = 0;
        for (int a = 0; a < ENTRIES; a++)
            expected[a] = ImageWord(a);
        // Only fully initialized words are checked before the dummy fill.
        for (int a = 64 / BYTES; a < 128 / BYTES; a++)
            Access(0, 0, '0, a);

        ram.FillDummyData();
        ram.InitializeMemory("Image.mem");
        for (int a = 0; a < ENTRIES; a++)
            Access(0, 0, '0, a);

        // A runtime reload must preserve an existing write outside the sparse image.
        Access(1, ENTRIES-1, '1, ENTRIES-1);
        // Stop writes before reloading the image between clock edges.
        @(negedge clk);
        we = 0;
        ram.InitializeMemory("Image.mem");
        Access(0, 0, '0, ENTRIES-1);

        // Exercise collisions, adjacent words and changing addresses with writes disabled.
        for (int i = 0; i < 128; i++) begin
            Value data;
            int address;
            address = (17*i + 3) % ENTRIES;
            for (int b = 0; b < BYTES; b++)
                data[8*b+:8] = 8'(i*7 + b);
            Access(i % 4 != 0, address, data, i % 2 == 0 ? address : address ^ 1);
        end
        for (int a = 0; a < ENTRIES; a++)
            Access(0, 0, '0, a);
        $display("PASS InitializedBlockRAM WIDTH=%0d", WIDTH);
        done = 1;
    end
endmodule

module TestInitializedBlockRAM;
    wire [6:0] done;
    // Wide cases check RTL behavior; they do not establish FPGA BRAM inference support.
    for (genvar i = 0; i < 7; i++) begin : widths
        InitializedBlockRAMTestCase #(.WIDTH(8 << i)) testCase(done[i]);
    end
    initial begin
        wait (&done);
        $display("========== Test Passed: InitializedBlockRAM 8..512 bits ==========");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "InitializedBlockRAM test timed out");
    end
endmodule
