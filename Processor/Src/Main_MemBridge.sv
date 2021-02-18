// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.



//
// Main_RSD
//
// This is wrapper module for compiling at synplify2017


import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryTypes::*;
import DebugTypes::*;
import MemoryMapTypes::*;
import IO_UnitTypes::*;

// Wrapper module
module Main_MemBridge (
input
    logic clk_p,
    logic negResetIn, // 負論理

`ifndef RSD_DISABLE_DEBUG_REGISTER
output
    DebugRegister debugRegister,
`endif

output
    logic serialWE,
    SerialDataPath serialWriteData,
    logic posResetOut, // 正論理
    LED_Path ledOut, // LED Output
// Memory
output
    AddrPath memAccessAddr,
    MemoryEntryDataPath memAccessWriteData,
    logic memAccessRE,
    logic memAccessWE,
input
    logic memAccessBusy,    // メモリアクセス要求を受け付けられない
    MemAccessSerial nextMemReadSerial, // RSDの次の読み出し要求に割り当てられるシリアル(id)
    MemWriteSerial nextMemWriteSerial, // RSDの次の書き込み要求に割り当てられるシリアル(id)
    logic memReadDataReady, // TRUEなら、メモリの読出しデータあり
    MemoryEntryDataPath memReadData, // メモリの読出しデータ
    MemAccessSerial memReadSerial, // メモリの読み出しデータのシリアル
    MemAccessResponse memAccessResponse // メモリ書き込み完了通知
);

    Main_MemBridgeBody main (.*);

endmodule : Main_MemBridge



module Main_MemBridgeBody (
input
    logic clk_p,
    logic negResetIn, // 負論理

`ifndef RSD_DISABLE_DEBUG_REGISTER
output
    DebugRegister debugRegister,
`endif

output
    logic serialWE,
    SerialDataPath serialWriteData,
    logic posResetOut, // 正論理
    LED_Path ledOut, // LED Output

// Memory bus
output
    AddrPath memAccessAddr,
    MemoryEntryDataPath memAccessWriteData,
    logic memAccessRE,
    logic memAccessWE,
input
    logic memAccessBusy,    // メモリアクセス要求を受け付けられない
    MemAccessSerial nextMemReadSerial, // RSDの次の読み出し要求に割り当てられるシリアル(id)
    MemWriteSerial nextMemWriteSerial, // RSDの次の書き込み要求に割り当てられるシリアル(id)
    logic memReadDataReady, // TRUEなら、メモリの読出しデータあり
    MemoryEntryDataPath memReadData, // メモリの読出しデータ
    MemAccessSerial memReadSerial, // メモリの読み出しデータのシリアル
    MemAccessResponse memAccessResponse // メモリ書き込み完了通知
);

    // RSD_POST_SYNTHESIS
    // RSD_FUNCTIONAL_SIMULATION
    logic clk;
    logic programLoaded; // プログラムのロードが済んだらTRUE

`ifdef RSD_DISABLE_DEBUG_REGISTER
    DebugRegister debugRegister; // RSD_DISABLE_DEBUG_REGISTER時はどこにも繋がない
`endif
    

    //
    // --- Clock and Reset
    //
    logic memCLK;
    logic locked; // You must disable the reset signal (rst) after the clock generator is locked.
    logic rst, rstStart, rstTrigger;

    assign clk = clk_p;
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
    // --- Memory
    //
    MemoryEntryDataPath memAccessWriteDataFromCore;
    PhyAddrPath memAccessAddrFromCore;
    logic memAccessRE_FromCore;
    logic memAccessWE_FromCore;

    assign memAccessReadBusy = memAccessBusy;
    assign memAccessWriteBusy = memAccessBusy;

    always_comb begin
        programLoaded = TRUE;
        memAccessAddr = memAccessAddrFromCore;
        memAccessWriteData = memAccessWriteDataFromCore;
        memAccessRE = memAccessRE_FromCore;
        memAccessWE = memAccessWE_FromCore;
    end
    
    //
    // --- LED IO
    //
    PC_Path lastCommittedPC;

    assign ledOut = lastCommittedPC[ LED_WIDTH-1:0 ];

    // External interrupt
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
    
endmodule : Main_MemBridgeBody
