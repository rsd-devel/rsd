// Copyright 2026 RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
`timescale 1ns/1ps

module MultiBankRAMTestCase #(
    parameter READ_NUM = 1, WRITE_NUM = 1, WIDTH = 4
)(output bit done);
    localparam BANK_NUM = 1 << $clog2(READ_NUM > WRITE_NUM ? READ_NUM : WRITE_NUM);
    // Cover the minimum two entries per bank and a non-power-of-two total depth.
    localparam ENTRIES = WIDTH < 8 ? 2 * BANK_NUM : 24;
    typedef logic [$clog2(ENTRIES)-1:0] Address;
    typedef logic [WIDTH-1:0] Value;
    logic clk = 0;
    always #5 clk = ~clk;
    logic we[WRITE_NUM];
    Address wa[WRITE_NUM], ra[READ_NUM];
    Value wv[WRITE_NUM], blockRV[READ_NUM], distributedRV[READ_NUM];
    Value expected[ENTRIES];

    BlockMultiBankRAM #(ENTRIES, WIDTH, READ_NUM, WRITE_NUM)
        blockRAM(clk, we, wa, wv, ra, blockRV);
    DistributedMultiBankRAM #(ENTRIES, WIDTH, READ_NUM, WRITE_NUM)
        distributedRAM(clk, we, wa, wv, ra, distributedRV);

    task automatic Cycle(input bit checkOutputs = 1);
        Value previous[READ_NUM], readBeforeWrite[READ_NUM];
        for (int i = 0; i < READ_NUM; i++) begin
            previous[i] = blockRV[i];
            readBeforeWrite[i] = expected[ra[i]];
        end
        #1;
        if (checkOutputs) begin
            for (int i = 0; i < READ_NUM; i++) begin
                assert (blockRV[i] === previous[i])
                    else $fatal(1, "%m: block output changed before clock, port=%0d", i);
                assert (distributedRV[i] === expected[ra[i]])
                    else $fatal(1, "%m: asynchronous read mismatch, port=%0d address=%0d", i, ra[i]);
            end
        end
        @(posedge clk);
        for (int i = 0; i < WRITE_NUM; i++) begin
            if (we[i])
                expected[wa[i]] = wv[i];
        end
        #1;
        if (checkOutputs) begin
            for (int i = 0; i < READ_NUM; i++) begin
                // Block RAM is READ_FIRST; distributed RAM sees the updated array.
                assert (blockRV[i] === readBeforeWrite[i])
                    else $fatal(1, "%m: synchronous read mismatch, port=%0d address=%0d expected=%h got=%h",
                                i, ra[i], readBeforeWrite[i], blockRV[i]);
                assert (distributedRV[i] === expected[ra[i]])
                    else $fatal(1, "%m: read after write mismatch, port=%0d address=%0d", i, ra[i]);
            end
        end
        @(negedge clk);
    endtask

    initial begin
        done = 0;
        for (int i = 0; i < WRITE_NUM; i++) begin
            we[i] = 0;
            wa[i] = 0;
            wv[i] = 0;
        end
        for (int i = 0; i < READ_NUM; i++)
            ra[i] = Address'(i);
        @(negedge clk);
        // Block RAM has no reset. Initialize all entries through a public write port.
        for (int a = 0; a < ENTRIES; a++) begin
            we[0] = 1;
            wa[0] = Address'(a);
            wv[0] = Value'(7 * a + 1);
            Cycle(0);
        end

        // Rotate banks independently of rows; active ports never conflict within a bank.
        // Even cycles include same-address read/write, and disabled ports still change data.
        for (int n = 0; n < 64; n++) begin
            for (int i = 0; i < READ_NUM; i++)
                ra[i] = Address'(((n / BANK_NUM + 3 * i) % (ENTRIES / BANK_NUM)) * BANK_NUM
                                 + (n + i) % BANK_NUM);
            for (int i = 0; i < WRITE_NUM; i++) begin
                we[i] = (n + i) % 4 != 0;
                wa[i] = Address'(((3 * n + i) % (ENTRIES / BANK_NUM)) * BANK_NUM
                                 + (n + i) % BANK_NUM);
                if (n % 2 == 0 && i < READ_NUM)
                    wa[i] = ra[i];
                wv[i] = Value'(13 * (n + 1) + 7 * i);
            end
            Cycle();
        end

        // Check every location, including both ends, with writes disabled.
        for (int i = 0; i < WRITE_NUM; i++)
            we[i] = 0;
        for (int a = 0; a < ENTRIES; a++) begin
            for (int i = 0; i < READ_NUM; i++)
                ra[i] = Address'((a + i) % ENTRIES);
            Cycle();
        end
        $display("PASS MultiBankRAM R=%0d W=%0d WIDTH=%0d ENTRIES=%0d", READ_NUM, WRITE_NUM, WIDTH, ENTRIES);
        done = 1;
    end
endmodule

module TestMultiBankRAM;
    wire [31:0] done;
    // Narrow distributed banks use registers; wider ones use LUT RAM.
    for (genvar w = 0; w < 2; w++) begin : widths
        for (genvar r = 1; r <= 4; r++) begin : reads
            for (genvar n = 1; n <= 4; n++) begin : writes
                MultiBankRAMTestCase #(.READ_NUM(r), .WRITE_NUM(n), .WIDTH(w == 0 ? 4 : 16))
                    testCase(done[16*w + 4*(r-1) + n-1]);
            end
        end
    end
    initial begin
        wait (&done);
        $display("========== Test Passed: MultiBankRAM 32 configurations ==========");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "MultiBankRAM test timed out");
    end
endmodule
