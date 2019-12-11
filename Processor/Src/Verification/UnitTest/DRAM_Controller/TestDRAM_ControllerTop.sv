// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.



// Main モジュール
// 全てのモジュールとインターフェースの最上位での接続を行う
//

import BasicTypes::*;
import MemoryTypes::*;

module TestDRAM_ControllerTop (
input
    logic clk_p, clk_n,
    logic negResetIn, // 負論理
    logic rxd,
`ifdef RSD_SYNTHESIS_ATLYS
output
    wire DDR2CLK0, DDR2CLK1, DDR2CKE,
    wire DDR2RASN, DDR2CASN, DDR2WEN,
    wire DDR2RZQ, DDR2ZIO,
    wire DDR2LDM, DDR2UDM, DDR2ODT,
    wire [2:0]  DDR2BA,
    wire [12:0] DDR2A,
inout
    wire [15:0] DDR2DQ,
    wire DDR2UDQS, DDR2UDQSN, DDR2LDQS, DDR2LDQSN,
`endif
output
    logic posResetOut,
    logic txd,
    logic [7:0] ledOut // LED Output
);
`ifdef RSD_SYNTHESIS_ATLYS
    parameter MAX_COUNT_BIT = 26;
`else
    parameter MAX_COUNT_BIT = 6;
`endif
    parameter MAX_COUNT = 1 << MAX_COUNT_BIT; // ループの周期
    
    
    //
    // --- Clock and Reset
    //
    logic clk, memCLK;
    logic locked; // You must disable the reset signal (rst) after the clock generator is locked.
    logic rst, rstStart, rstTrigger;

`ifdef RSD_SYNTHESIS_ATLYS
    logic locked1, locked2;
    AtlysClockGenerator clockGen(
        .CLK_IN(clk_p),
        .CLK_OUT(clk),
        .LOCKED(locked1)
    );
    AtlysMemoryClockGenerator memClockGen(
        .CLK_IN(clk_p),
        .CLK_OUT(memCLK),
        .LOCKED(locked2)
    );
    assign locked = locked1 & locked2;
`else
    // For Simulation
    assign clk = clk_p;
    assign locked = TRUE;
`endif
        
    // Generate a global reset signal 'rst' from 'rstTrigger'.
    assign rstTrigger = ~negResetIn;
    assign posResetOut = rst;
    ResetController rstController(
        .clk( clk ),
        .rstTrigger( rstTrigger ),
        .locked( locked ),
        .rst( rst ),
        .rstStart( rstStart )
    );

    //
    // --- Memory
    //
    logic memCaribrationDone; // メモリのキャリブレーションが終わったらTRUE
    
    MemoryEntryDataPath memReadData;
    logic memReadDataReady;
    
    logic memBusy;
    MemoryEntryDataPath memWriteData;
    AddrPath memAddr;
    logic memRE;
    logic memWE;
    
    logic cmdFull, rdFull, wrFull;
    
`ifdef RSD_USE_EXTERNAL_MEMORY
    AtlysDRAM_Controller dramController(
        .CLK( clk ),
        .DRAM_CLK( memCLK ),
        .RST_X( ~rst ),
        .calib_done( memCaribrationDone ), 
        .D_ADR( memAddr ),
        .D_DIN( memWriteData ),
        .D_WE( memWE ), 
        .D_RE( memRE ),
        .D_DOUT( memReadData ),
        .D_DOUT_RDY( memReadDataReady ),
        .D_BUSY( memBusy ),
        .cmd_full( cmdFull ),
        .rd_full( rdFull ),
        .wr_full( wrFull ),
        
        // DRAM interface
       .DDR2CLK0        (DDR2CLK0),
       .DDR2CLK1        (DDR2CLK1),
       .DDR2CKE         (DDR2CKE),
       .DDR2RASN        (DDR2RASN),
       .DDR2CASN        (DDR2CASN),
       .DDR2WEN         (DDR2WEN),
       .DDR2RZQ         (DDR2RZQ),
       .DDR2ZIO         (DDR2ZIO),
       .DDR2BA          (DDR2BA),
       .DDR2A           (DDR2A),
       .DDR2DQ          (DDR2DQ),
       .DDR2UDQS        (DDR2UDQS),
       .DDR2UDQSN       (DDR2UDQSN),
       .DDR2LDQS        (DDR2LDQS),
       .DDR2LDQSN       (DDR2LDQSN),
       .DDR2LDM         (DDR2LDM),
       .DDR2UDM         (DDR2UDM),
       .DDR2ODT         (DDR2ODT)
    );
`else // Use internal memory
    Memory memory (
        .clk( clk ),
        .rst( rst ),
        .memAccessAddr( memAddr ),
        .memReadData( memReadData ),
        .memAccessWriteData( memWriteData ),
        .memAccessRE( memRE ),
        .memAccessWE( memWE ),
        .memAccessBusy( memBusy ),
        .memReadDataReady( memReadDataReady )
    );
    assign memCaribrationDone = TRUE;
`endif
    
    
    //
    // DRAMにアクセスする際のアドレスとデータを設定
    // 全アドレスの書き→全アドレスの読み を繰り返す
    // 書くデータはアドレスと同じ
    // 読んだデータとアドレスを比較し、一致/不一致をmatchedに格納
    //
    AddrPath addr, nextAddr;
    AddrPath readAddr, nextReadAddr; // 読出データのアドレスを保持
    logic matched, nextMatched;
    logic error, nextError;
    logic rw, nextRW; // TRUEならWrite
    always_ff @( posedge clk ) begin
        if ( rst || ~memCaribrationDone ) begin
            addr <= '0;
            readAddr <= '0;
            matched <= FALSE;
            rw <= TRUE;
            error <= FALSE;
        end
        else begin
            addr <= nextAddr;
            readAddr <= nextReadAddr;
            matched <= nextMatched;
            rw <= nextRW;
            error <= nextError;
        end
    end

    always_comb begin
        nextAddr = addr;
        nextRW = rw;
        
        if ( !memBusy ) begin
            nextAddr = addr + MEMORY_ENTRY_BYTE_NUM;
            if ( nextAddr >= MAX_COUNT ) begin
                nextAddr = '0;
                nextRW = ~rw;
            end
        end
        
        memWE = rw && !memBusy;
        memRE = !rw && !memBusy;
        memAddr = addr;
        memWriteData = { ~addr, addr, ~addr, addr };
    end
    
    always_comb begin
        nextReadAddr = readAddr;
        nextMatched = matched;
        nextError = error;

        if ( memReadDataReady ) begin
            nextReadAddr = readAddr + MEMORY_ENTRY_BYTE_NUM;
            if ( nextReadAddr >= MAX_COUNT ) begin
                nextReadAddr = '0;
            end
            nextMatched = ( memReadData == { ~readAddr, readAddr, ~readAddr, readAddr } );
            if ( memReadData != { ~readAddr, readAddr, ~readAddr, readAddr } ) begin
                nextError = error || ( memReadData != { ~readAddr, readAddr, ~readAddr, readAddr } );
            end
        end
    end
    
    //
    // --- LED IO
    //
    logic [25:0] ledBlinkCounter; // just for LED

    always_ff @(posedge clk) begin
        if ( rst ) begin
            ledBlinkCounter <= '0;
            ledOut <= '0;
        end
        else begin
            ledBlinkCounter <= ledBlinkCounter + 1;
            
            ledOut[7] <= ledBlinkCounter[25];
            ledOut[6] <= matched;
            ledOut[5] <= memRE;
            ledOut[4] <= memWE;
            ledOut[3] <= memBusy;
            ledOut[2] <= memReadDataReady;
            ledOut[1] <= cmdFull;
            ledOut[0] <= error;
            //ledOut[0] <= ~memCaribrationDone;  // DRAM calibration done 
        end
    end

endmodule