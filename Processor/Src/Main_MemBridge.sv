// Copyright 2021- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryTypes::*;
import DebugTypes::*;
import MemoryMapTypes::*;
import IO_UnitTypes::*;


module MemoryBridge(
input
    logic pinClk,   // チップ外クロック（低速）
    logic coreClk,  // チップ内コア用クロック（高速）

    // チップ外
output
    AddrPath pinMemAccessAddr,                  // core -> 外部へのメモリのアドレス
    MemoryEntryDataPath pinMemAccessWriteData,  // core -> 外部への書き込み時のデータ
    logic pinMemAccessRE,                       // core -> 外部への読み出し要求
    logic pinMemAccessWE,                       // core -> 外部への書き込み要求
input
    logic pinMemAccessBusy,                 // メモリアクセス要求を受け付けられない
    MemAccessSerial pinNextMemReadSerial,   // RSDの次の読み出し要求に割り当てられるシリアル(id)
    MemWriteSerial pinNextMemWriteSerial,   // RSDの次の書き込み要求に割り当てられるシリアル(id)
    logic pinMemReadDataReady,              // TRUEなら、メモリの読出しデータあり
    MemoryEntryDataPath pinMemReadData,     // メモリの読出しデータ
    MemAccessSerial pinMemReadSerial,       // メモリの読み出しデータのシリアル
    MemAccessResponse pinMemAccessResponse, // メモリ書き込み完了通知

    // コア側
input
    AddrPath coreMemAccessAddr,
    MemoryEntryDataPath coreMemAccessWriteData,
    logic coreMemAccessRE,
    logic coreMemAccessWE,
output
    logic coreMAccessBusy,                  // メモリアクセス要求を受け付けられない
    MemAccessSerial coreNextMemReadSerial,  // RSDの次の読み出し要求に割り当てられるシリアル(id)
    MemWriteSerial coreNextMemWriteSerial,  // RSDの次の書き込み要求に割り当てられるシリアル(id)
    logic coreMemReadDataReady,             // TRUEなら、メモリの読出しデータあり
    MemoryEntryDataPath coreMemReadData,    // メモリの読出しデータ
    MemAccessSerial coreMemReadSerial,      // メモリの読み出しデータのシリアル
    MemAccessResponse coreMemAccessResponse // メモリ書き込み完了通知
);
    always_comb begin
        // pin~ はチップの外のピンに接続されている信号線
        // core~ はcore に接続されている信号線

        // 現在はテスト用に直結しています
        pinMemAccessAddr = coreMemAccessAddr;
        pinMemAccessWriteData = coreMemAccessWriteData;
        pinMemAccessRE = coreMemAccessRE;
        pinMemAccessWE = coreMemAccessWE;

        coreMAccessBusy = pinMemAccessBusy;
        coreNextMemReadSerial = pinNextMemReadSerial;
        coreNextMemWriteSerial = pinNextMemWriteSerial;
        coreMemReadDataReady = pinMemReadDataReady;
        coreMemReadData = pinMemReadData;
        coreMemReadSerial = pinMemReadSerial;
        coreMemAccessResponse = pinMemAccessResponse;
    end
endmodule



// Wrapper module
module Main_MemBridge (
input
    logic coreClk,
    logic pinClk,
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

    // External interrupt
input
    logic reqExternalInterrupt,
    ExternalInterruptCodePath externalInterruptCode,

    // Memory
output
    AddrPath pinMemAccessAddr,
    MemoryEntryDataPath pinMemAccessWriteData,
    logic pinMemAccessRE,
    logic pinMemAccessWE,
input
    logic pinMemAccessBusy,                  // メモリアクセス要求を受け付けられない
    MemAccessSerial pinNextMemReadSerial,  // RSDの次の読み出し要求に割り当てられるシリアル(id)
    MemWriteSerial pinNextMemWriteSerial,  // RSDの次の書き込み要求に割り当てられるシリアル(id)
    logic pinMemReadDataReady,             // TRUEなら、メモリの読出しデータあり
    MemoryEntryDataPath pinMemReadData,    // メモリの読出しデータ
    MemAccessSerial pinMemReadSerial,      // メモリの読み出しデータのシリアル
    MemAccessResponse pinMemAccessResponse // メモリ書き込み完了通知
);
    // コア側
    AddrPath coreMemAccessAddr;
    MemoryEntryDataPath coreMemAccessWriteData;
    logic coreMemAccessRE;
    logic coreMemAccessWE;
    logic coreMAccessBusy;                // メモリアクセス要求を受け付けられない
    MemAccessSerial coreNextMemReadSerial;  // RSDの次の読み出し要求に割り当てられるシリアル(id)
    MemWriteSerial coreNextMemWriteSerial;  // RSDの次の書き込み要求に割り当てられるシリアル(id)
    logic coreMemReadDataReady;             // TRUEなら、メモリの読出しデータあり
    MemoryEntryDataPath coreMemReadData;    // メモリの読出しデータ
    MemAccessSerial coreMemReadSerial;      // メモリの読み出しデータのシリアル
    MemAccessResponse coreMemAccessResponse; // メモリ書き込み完了通知

    MemoryBridge bridge(
        .coreClk(coreClk),
        .pinClk(pinClk),
        .*
    );

    Main_MemBridgeBody main (
        .memAccessAddr(coreMemAccessAddr),
        .memAccessWriteData(coreMemAccessWriteData),
        .memAccessRE(coreMemAccessRE),
        .memAccessWE(coreMemAccessWE),
        .memAccessBusy(coreMAccessBusy),
        .nextMemReadSerial(coreNextMemReadSerial),
        .nextMemWriteSerial(coreNextMemWriteSerial),
        .memReadDataReady(coreMemReadDataReady),
        .memReadData(coreMemReadData),
        .memReadSerial(coreMemReadSerial),
        .memAccessResponse(coreMemAccessResponse),
        .clk(coreClk),
        .*
    );

endmodule : Main_MemBridge



module Main_MemBridgeBody (
input
    logic clk,
    logic negResetIn, // 負論理

`ifndef RSD_DISABLE_DEBUG_REGISTER
output
    DebugRegister debugRegister,
`endif

output
    logic serialWE,
    SerialDataPath serialWriteData,
    LED_Path ledOut, // LED Output
    logic posResetOut, // 正論理
    
    // External interrupt
input
    logic reqExternalInterrupt,
    ExternalInterruptCodePath externalInterruptCode,

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
    logic memAccessReadBusy, memAccessWriteBusy;
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
