// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.



// Main モジュール
// 全てのモジュールとインターフェースの最上位での接続を行う
//

`ifdef RSD_SYNTHESIS_ATLYS

import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryTypes::*;
import DebugTypes::*;
import IO_UnitTypes::*;

module Main #(
    parameter MEM_INIT_HEX_FILE = ""
)(
input
    logic clk_p, clk_n,
    logic negResetIn, // 負論理
    logic rxd,
    
`ifndef RSD_DISABLE_DEBUG_REGISTER
output
    DebugRegister debugRegister,
`endif

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
    logic serialWE,
    SerialDataPath serialWriteData,
    logic posResetOut, // 正論理
    LED_Path ledOut, // LED Output
    logic txd
);
    
`ifdef RSD_DISABLE_DEBUG_REGISTER
    DebugRegister debugRegister; // RSD_DISABLE_DEBUG_REGISTER時はどこにも繋がない
`endif
    
    logic programLoaded; // プログラムのロードが済んだらTRUE

    //
    // --- Clock and Reset
    //
    logic clk, memCLK;
    logic locked; // You must disable the reset signal (rst) after the clock generator is locked.
    logic rst, rstStart, rstTrigger;

`ifdef RSD_SYNTHESIS_TED
    TED_ClockGenerator clockgen(
        .clk_p(clk_p),
        .clk_n(clk_n),
        .clk(clk)
    );
    assign locked = TRUE;
`elsif RSD_SYNTHESIS_ATLYS
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
    // --- Memory and Program Loader
    //
    logic memCaribrationDone; // メモリのキャリブレーションが終わったらTRUE
    
    MemoryEntryDataPath memReadData;
    logic memReadDataReady;
    logic memAccessReadBusy;
    logic memAccessWriteBusy;
    logic memAccessBusy;
    
    MemoryEntryDataPath memAccessWriteData;
    MemoryEntryDataPath memAccessWriteDataFromCore;
    MemoryEntryDataPath memAccessWriteDataFromProgramLoader;

    AddrPath memAccessAddr, memAccessAddrFromProgramLoader;
    PhyAddrPath memAccessAddrFromCore;

    logic memAccessRE, memAccessRE_FromCore;
    logic memAccessWE, memAccessWE_FromCore, memAccessWE_FromProgramLoader;
    
`ifdef RSD_USE_EXTERNAL_MEMORY
    logic cmd_full, rd_full, wr_full;
    
    AtlysDRAM_Controller dramController(
        .CLK( clk ),
        .DRAM_CLK( memCLK ),
        .RST_X( ~rst ),
        .calib_done( memCaribrationDone ), 
        .D_ADR( memAccessAddr ),
        .D_DIN( memAccessWriteData ),
        .D_WE( memAccessWE ), 
        .D_RE( memAccessRE ),
        .D_BUSY( memAccessBusy ),
        .D_DOUT( memReadData ),
        .D_DOUT_RDY( memReadDataReady ),
        .cmd_full( cmd_full ),
        .rd_full( rd_full ),
        .wr_full( wr_full ),
        
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
    Memory #(
        .INIT_HEX_FILE( MEM_INIT_HEX_FILE )
    ) memory (
        .clk( clk ),
        .rst( rst ),
        .memAccessAddr( memAccessAddr ),
        .memAccessWriteData( memAccessWriteData ),
        .memAccessRE( memAccessRE ),
        .memAccessWE( memAccessWE ),
        .memAccessBusy( memAccessBusy ),
        .memReadData( memReadData ),
        .memReadDataReady( memReadDataReady )
    );
`endif

    assign memAccessReadBusy = memAccessBusy;
    assign memAccessWriteBusy = memAccessBusy;

`ifdef RSD_USE_PROGRAM_LOADER
    // Atlysボードを使う場合は、
    AtlysProgramLoader programLoader(
        .CLK( clk ),
        .RST_X( ~rst ), // RST_X is negative logic
        .RXD( rxd ),
        .ADDR( memAccessAddrFromProgramLoader ),
        .DATA( memAccessWriteDataFromProgramLoader ),
        .WE( memAccessWE_FromProgramLoader ),
        .DONE( programLoaded )
    );

    always_comb begin
        if ( !programLoaded ) begin
            memAccessAddr = memAccessAddrFromProgramLoader;
            memAccessWriteData = memAccessWriteDataFromProgramLoader;
            memAccessRE = FALSE;
            memAccessWE = memAccessWE_FromProgramLoader;
        end
        else begin
            memAccessAddr = memAccessAddrFromCore;
            memAccessWriteData = memAccessWriteDataFromCore;
            memAccessRE = memAccessRE_FromCore;
            memAccessWE = memAccessWE_FromCore;
        end
    end
`else
    always_comb begin
        programLoaded = TRUE;
        memAccessAddr = memAccessAddrFromCore;
        memAccessWriteData = memAccessWriteDataFromCore;
        memAccessRE = memAccessRE_FromCore;
        memAccessWE = memAccessWE_FromCore;
    end
`endif
    
    //
    // --- Serial communication IO
    //
    logic txdBuffer, serialReady;
    
    always @(posedge clk) begin
        txd <= txdBuffer;
    end

    AtlysUartTx serialIO(
        .CLK(clk),
        .RST_X(~rst), // RST_X is negative logic
        .DATA(serialWriteData),
        .WE(serialWE),
        .TXD(txdBuffer),
        .READY(serialReady)
    );

    //
    // --- LED IO
    //
    PC_Path lastCommittedPC;

`ifdef RSD_SYNTHESIS_ATLYS
    logic [25:0] ledBlinkCounter; // just for LED

    always @(posedge clk) begin
        ledBlinkCounter <= ledBlinkCounter + 1;
        
        ledOut[7] <= ledBlinkCounter[25];
        ledOut[6] <= FALSE; // TODO:パイプラインが動いているかを表示したい
        ledOut[5] <= ( lastCommittedPC == PC_GOAL ? TRUE : FALSE ); 
        ledOut[4] <= memAccessBusy;   // DRAM is working
        ledOut[3] <= ~txd;      // Uart TXD
        ledOut[2] <= ~rxd;      // Uart RXD
        ledOut[1] <= ~memCaribrationDone;  // DRAM calibration done 
        ledOut[0] <= ~programLoaded; // MEMORY IMAGE transfer is done
    end
`else
    assign ledOut = lastCommittedPC[ LED_WIDTH-1:0 ];
`endif

    logic reqExternalInterrupt;
    ExternalInterruptCodePath externalInterruptCode; 
    always_comb begin
        reqExternalInterrupt = FALSE;
        externalInterruptCode = 0;
    end

    //
    // --- Processor core
    //
    Core core (
        .clk( clk ),
        .rst( rst || !programLoaded ),
        .memAccessAddr( memAccessAddrFromCore ),
        .memAccessWriteData( memAccessWriteDataFromCore ),
        .memAccessRE( memAccessRE_FromCore ),
        .memAccessWE( memAccessWE_FromCore ),
        .memAccessReadBusy( memAccessReadBusy ),
        .memAccessWriteBusy( memAccessWriteBusy ),
        .reqExternalInterrupt( reqExternalInterrupt ),
        .externalInterruptCode( externalInterruptCode ),
        .memReadData( memReadData ),
        .memReadDataReady( memReadDataReady ),
        .rstStart( rstStart ),
        .serialWE( serialWE ),
        .serialWriteData( serialWriteData ),
        .lastCommittedPC( lastCommittedPC ),
        .debugRegister ( debugRegister )
    );
    
endmodule : Main

`endif