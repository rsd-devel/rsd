// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Main module for ASIC synthesis
// Connect all modules and interfaces at the top level 
//

import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryTypes::*;
import MemoryMapTypes::*;
import IO_UnitTypes::*;
import DebugTypes::*;

module Main_ASIC (
input
    logic clk_p, clk_n,
    logic negResetIn, // 負論理
    logic rxd,
output
`ifndef RSD_DISABLE_DEBUG_REGISTER
    DebugRegister debugRegister,
`endif
    logic serialWE,
    SerialDataPath serialWriteData,
    logic posResetOut, // 正論理
    LED_Path ledOut, // LED Output
    logic txd
);

`ifdef RSD_DISABLE_DEBUG_REGISTER
    // Hide from in/out ports
    DebugRegister debugRegister;
`endif
    
    logic programLoaded; // Asserted after finished program loading

    assign clk = clk_p;
    //
    // --- Clock and Reset
    //
    logic locked; // You must disable the reset signal (rst) after the clock generator is locked.
    logic rst, rstStart, rstTrigger;

    assign locked = TRUE;
        
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

    MemAccessSerial nextMemReadSerial; // RSDの次の読み出し要求に割り当てられるシリアル(id)
    MemWriteSerial nextMemWriteSerial; // RSDの次の書き込み要求に割り当てられるシリアル(id)

    MemAccessSerial memReadSerial; // メモリの読み出しデータのシリアル
    MemAccessResponse memAccessResponse; // メモリ書き込み完了通知

    localparam ADDR_BIT_WIDTH = 15; // 32KB = 2 ^ 15
    localparam MEMORY_ENTRY_NUM = 
        1 << (ADDR_BIT_WIDTH - $clog2(MEMORY_ENTRY_BYTE_NUM));
    Memory #(
        .ENTRY_NUM (MEMORY_ENTRY_NUM)
    ) memory (
        .clk( clk ),
        .rst( rst ),
        .memAccessAddr( memAccessAddr ),
        .memAccessWriteData( memAccessWriteData ),
        .memAccessRE( memAccessRE ),
        .memAccessWE( memAccessWE ),
        .memAccessBusy( memAccessBusy ),
        .nextMemReadSerial( nextMemReadSerial ),
        .nextMemWriteSerial( nextMemWriteSerial ),
        .memReadDataReady( memReadDataReady ),
        .memReadData( memReadData ),
        .memReadSerial( memReadSerial ),
        .memAccessResponse( memAccessResponse )
    );

    assign memAccessReadBusy = memAccessBusy;
    assign memAccessWriteBusy = memAccessBusy;

    //
    // --- Memory connection
    //
    always_comb begin
        if ( !programLoaded ) begin
            // Load program
            memAccessAddr = memAccessAddrFromProgramLoader;
            memAccessWriteData = memAccessWriteDataFromProgramLoader;
            memAccessRE = FALSE;
            memAccessWE = memAccessWE_FromProgramLoader;
        end
        else begin
            // Connect to the core
            memAccessAddr = memAccessAddrFromCore;
            memAccessWriteData = memAccessWriteDataFromCore;
            memAccessRE = memAccessRE_FromCore;
            memAccessWE = memAccessWE_FromCore;
        end
    end
    
    //
    // --- Serial communication IO
    //
    logic txdBuffer, serialReady;
    
    always_ff @(posedge clk) begin
        txd <= txdBuffer;
    end

    //
    // --- LED IO
    //
    PC_Path lastCommittedPC;

    assign ledOut = lastCommittedPC[ LED_WIDTH-1:0 ];


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
        .nextMemReadSerial( nextMemReadSerial ),
        .nextMemWriteSerial( nextMemWriteSerial ),
        .memReadDataReady( memReadDataReady ),
        .memReadData( memReadData ),
        .memReadSerial( memReadSerial ),
        .memAccessResponse( memAccessResponse ),
        .rstStart( rstStart ),
        .serialWE( serialWE ),
        .serialWriteData( serialWriteData ),
        .lastCommittedPC( lastCommittedPC ),
        .debugRegister ( debugRegister )
    );

    initial begin
        // NOTE: Now it is assumed that program loading finishes instantaneous.
        programLoaded = TRUE;
    end
    
endmodule : Main_ASIC
