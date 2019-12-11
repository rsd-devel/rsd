// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;

parameter STEP = 10;
parameter HOLD = 2.5;
parameter SETUP = 0.5;
parameter WAIT = STEP*2-HOLD-SETUP;

module TestRegisterFile;
    
    //
    // Clock and Reset
    //
    logic clk, rst;
    TestBenchClockGenerator #( .STEP(STEP) ) clkgen ( .rstOut(FALSE), .* );
    
    //
    // Modules for test
    //
    /* Integer Register Read */
    PRegNumPath  [ INT_ISSUE_WIDTH-1:0 ] intSrcRegNumA ;
    PRegNumPath  [ INT_ISSUE_WIDTH-1:0 ] intSrcRegNumB;
    PFlagNumPath [ INT_ISSUE_WIDTH-1:0 ] intSrcFlagNum;
    
    DataPath [ INT_ISSUE_WIDTH-1:0 ] intSrcRegDataA;
    DataPath [ INT_ISSUE_WIDTH-1:0 ] intSrcRegDataB;
    FlagPath [ INT_ISSUE_WIDTH-1:0 ] intSrcFlagData;
    
    /* Integer Register Write */
    logic [ INT_ISSUE_WIDTH-1:0 ] intDstRegWE;
    logic [ INT_ISSUE_WIDTH-1:0 ] intDstFlagWE;

    PRegNumPath  [ INT_ISSUE_WIDTH-1:0 ] intDstRegNum ;
    PFlagNumPath [ INT_ISSUE_WIDTH-1:0 ] intDstFlagNum;
    
    DataPath [ INT_ISSUE_WIDTH-1:0 ] intDstRegData;
    FlagPath [ INT_ISSUE_WIDTH-1:0 ] intDstFlagData;
    
    /* Memory Register Read */
    PRegNumPath  [ MEM_ISSUE_WIDTH-1:0 ] memSrcRegNumA;
    PRegNumPath  [ MEM_ISSUE_WIDTH-1:0 ] memSrcRegNumB;
    PFlagNumPath [ MEM_ISSUE_WIDTH-1:0 ] memSrcFlagNum;
    
    DataPath [ MEM_ISSUE_WIDTH-1:0 ] memSrcRegDataA;
    DataPath [ MEM_ISSUE_WIDTH-1:0 ] memSrcRegDataB;
    FlagPath [ MEM_ISSUE_WIDTH-1:0 ] memSrcFlagData;
    
    /* Memory Register Write */
    logic [ MEM_ISSUE_WIDTH-1:0 ] memDstRegWE ;
    logic [ MEM_ISSUE_WIDTH-1:0 ] memDstFlagWE;

    PRegNumPath  [ MEM_ISSUE_WIDTH-1:0 ] memDstRegNum ;
    PFlagNumPath [ MEM_ISSUE_WIDTH-1:0 ] memDstFlagNum;
    
    DataPath [ MEM_ISSUE_WIDTH-1:0 ] memDstRegData ;
    FlagPath [ MEM_ISSUE_WIDTH-1:0 ] memDstFlagData;
    
    /* Module */
    TestRegisterFileTop top (
        .clk_p( clk ),
        .clk_n( ~clk ),
        .*
    );
    
    //
    // Test data
    //
    initial begin
        assert( INT_ISSUE_WIDTH >= 1 );
        assert( MEM_ISSUE_WIDTH >= 2 );
        assert( PREG_NUM >= 16 );
        
        // Initialize logic
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            intSrcRegNumA[i] = 0;
            intSrcRegNumB[i] = 0;
            intSrcFlagNum[i] = 0;
            intDstRegWE[i] = FALSE;
            intDstFlagWE[i] = FALSE;
            intDstRegNum[i] = 0;
            intDstRegData[i] = 0;
            intDstFlagNum[i] = 0;
            intDstFlagData[i] = 0;
        end
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            memSrcRegNumA[i] = 0;
            memSrcRegNumB[i] = 0;
            memSrcFlagNum[i] = 0;
            memDstRegWE[i] = FALSE;
            memDstFlagWE[i] = FALSE;
            memDstRegNum[i] = 0;
            memDstRegData[i] = 0;
            memDstFlagNum[i] = 0;
            memDstFlagData[i] = 0;
        end
        
        // Wait during reset sequence
        #WAIT;
        while(rst) @(posedge clk);
        
        // cycle 1
        #HOLD;
        
        intDstRegWE[0] = TRUE;
        intDstRegNum[0] = 1;
        intDstRegData[0] = 11;

        memDstRegWE[0] = TRUE;
        memDstRegNum[0] = 2;
        memDstRegData[0] = 22;
        
        memDstRegWE[1] = TRUE;
        memDstRegNum[1] = 3;
        memDstRegData[1] = 33;

        intDstFlagWE[0] = TRUE;
        intDstFlagNum[0] = 2;
        intDstFlagData[0] = 4'b0010;

        memDstFlagWE[0] = FALSE;
        memDstFlagNum[0] = 1;
        memDstFlagData[0] = 4'b1111;
        
        memDstFlagWE[1] = TRUE;
        memDstFlagNum[1] = 3;
        memDstFlagData[1] = 4'b1000;

        @(posedge clk);
        
        // cycle 2
        #HOLD;
        
        intDstRegWE[0] = TRUE;
        intDstRegNum[0] = 4;
        intDstRegData[0] = 44;

        memDstRegWE[0] = TRUE;
        memDstRegNum[0] = 5;
        memDstRegData[0] = 55;
        
        memDstRegWE[1] = TRUE;
        memDstRegNum[1] = 6;
        memDstRegData[1] = 66;

        intDstFlagWE[0] = TRUE;
        intDstFlagNum[0] = 1;
        intDstFlagData[0] = 4'b0001;
        
        memDstFlagWE[0] = TRUE;
        memDstFlagNum[0] = 3;
        memDstFlagData[0] = 4'b0100;

        memDstFlagWE[1] = FALSE;
        memDstFlagNum[1] = 2;
        memDstFlagData[1] = 4'b1111;

        // cycle 3 で読み出される
        intSrcFlagNum[0] = 3;
        memSrcFlagNum[0] = 3;
        memSrcFlagNum[1] = 3;
        
        @(posedge clk);

        // cycle 3
        #HOLD;

        memSrcRegNumA[0] = 1;
        memSrcRegNumB[0] = 2;
        memSrcRegNumA[1] = 3;
        memSrcRegNumB[1] = 4;
        intSrcRegNumA[0] = 5;
        intSrcRegNumB[0] = 6;
        
        // cycle 4 で読み出される
        memSrcFlagNum[0] = 1;
        memSrcFlagNum[1] = 2;
        intSrcFlagNum[0] = 3;

        #WAIT;
        assert( intSrcFlagData[0] == 4'b1000 );
        assert( memSrcFlagData[0] == 4'b1000 );
        assert( memSrcFlagData[1] == 4'b1000 );

        // cycle 4
        @(posedge clk);
        #HOLD;
        #WAIT;
        assert( memSrcRegDataA[0] == 11 );
        assert( memSrcRegDataB[0] == 22 );
        assert( memSrcRegDataA[1] == 33 );
        assert( memSrcRegDataB[1] == 44 );
        assert( intSrcRegDataA[0] == 55 );
        assert( intSrcRegDataB[0] == 66 );
        
        assert( memSrcFlagData[0] == 4'b0001 );
        assert( memSrcFlagData[1] == 4'b0010 );
        assert( intSrcFlagData[0] == 4'b0100 );
        
        @(posedge clk);
        $finish;
    end

endmodule
