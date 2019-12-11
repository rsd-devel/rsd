// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;

parameter STEP = 10;
parameter HOLD = 3;
parameter SETUP = 2;
parameter WAIT = STEP*2-HOLD-SETUP;

module TestDivider;
    
    //
    // Clock and Reset
    //
    logic clk, rst;
    TestBenchClockGenerator#(.STEP(STEP)) 
        clkGen(.rstOut(FALSE), .clk(clk), .rst(rst));
    
    //
    // Top Module
    //
    logic req;                  // request a new operation
    DataPath dividend;
    DataPath divisor;
    logic isSigned;             // operation is performed in a singed mode

    logic finished;      // Asserted when a result is obtained.
    DataPath quotient;
    DataPath remainder;

    logic refFinished;      
    DataPath refQuotient;
    DataPath refRemainder;

    int i, j, k;
    int pass = TRUE;

    TestRefDividerTop top(
        .clk_p(clk),
        .clk_n(~clk),
        .finished(finished),
        .quotient(quotient),
        .remainder(remainder),
        .refFinished(refFinished),
        .refQuotient(refQuotient),
        .refRemainder(refRemainder),
        .*
    );


    //
    // Test Data
    //
    initial begin
        
        // Initialize
        req = FALSE;
        dividend = '0;
        divisor = '0;
        isSigned = FALSE;

        // This wait is needed so that while(rst) functions.
        #HOLD
        #WAIT
                
        // Wait during reset sequence
        while (rst) @(posedge clk);

        // Test -8:7 and 0:15
        for (k = 0; k < 2; k++) begin   // 0:signed / 1:unsigned
            for (i = -8; i < 8; i++) begin
                for (j = -8; j < 8; j++) begin
                    dividend = i;
                    divisor = j;

                    // Setup a request
                    clkGen.WaitCycle(1);
                    #HOLD
                    req = TRUE;
                    isSigned = k == 0 ? TRUE : FALSE; // signed -> unsigned
                    #WAIT

                    // Calculation
                    clkGen.WaitCycle(1);
                    #HOLD
                    req = FALSE;
                    #WAIT
                    while (!refFinished || !finished) @(posedge clk);

                    $display(
                        "%s %x / %x = %x,%x(ref), %x,%x(test)", 
                        isSigned ? "signed" : "unsigned", 
                        dividend, divisor, 
                        refQuotient, refRemainder, 
                        quotient, remainder
                    );

                    if (!(refQuotient == quotient && refRemainder == remainder)) begin
                        $display("NG.");
                        $finish;
                    end;
                end
            end
        end

        // Test random
        for (i = 0; i < 1; i++) begin
            if (i == 0) begin  // Overflow test
                dividend = 32'h8000_0000;
                divisor = 32'hffff_ffff;
            end 
            else begin
                dividend = $random;
                divisor = $random;
            end
            for (k = 0; k < 2; k++) begin   // 0:signed / 1:unsigned
                // Setup a request
                clkGen.WaitCycle(1);
                #HOLD
                req = TRUE;
                isSigned = k == 0 ? TRUE : FALSE; // signed -> unsigned
                #WAIT

                // Calculation
                clkGen.WaitCycle(1);
                #HOLD
                req = FALSE;
                #WAIT
                while(!refFinished || !finished) @(posedge clk);

                $display(
                    "%s %x / %x = %x,%x(ref), %x,%x(test)", 
                    isSigned ? "signed" : "unsigned", 
                    dividend, divisor, 
                    refQuotient, refRemainder, 
                    quotient, remainder
                );
                if (!(refQuotient == quotient && refRemainder == remainder)) begin
                    $display("NG.");
                    $finish;
                end;
            end
        end

        // while(!rst) @(posedge clk);
        $display("OK!");
        $finish;
    end

endmodule
