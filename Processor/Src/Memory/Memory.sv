// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Main Memory
//

`include "BasicMacros.sv"

import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryTypes::*;


/* メインメモリモジュール
Spartan-6のDRAMコントローラを模している。
読み出しはパイプライン化されていて、DRAMアクセスの遅延をシミュレートできる。

memAccess**には読出/書込の要求を書き込む。
要求が受け付けられない場合、出力memAccessBusyがTRUEになる。

memRead**には、読出結果が数サイクル遅れて出てくる。

読出レイテンシは、以下の式で表される。
BlockRAMのレイテンシ + パイプラインの深さ
*/
module Memory #(
    parameter INIT_HEX_FILE = ""    // Memory initialization file path
)(
input
    logic clk,
    logic rst,
    AddrPath memAccessAddr,
    MemoryEntryDataPath memAccessWriteData,
    logic memAccessRE,
    logic memAccessWE,
output
    logic memAccessBusy,    // メモリアクセス要求を受け付けられない
    MemAccessSerial nextMemReadSerial, // RSDの次の読み出し要求に割り当てられるシリアル(id)
    MemWriteSerial nextMemWriteSerial, // RSDの次の書き込み要求に割り当てられるシリアル(id)
    logic memReadDataReady, // TRUEなら、メモリの読出しデータあり
    MemoryEntryDataPath memReadData, // メモリの読出しデータ
    MemAccessSerial memReadSerial, // メモリの読み出しデータのシリアル
    MemAccessResponse memAccessResponse // メモリ書き込み完了通知
);

    // メモリ読出
    typedef struct packed { // MemoryPipeReg
        logic valid;
        MemoryEntryDataPath data;
        MemAccessSerial serial;
        MemWriteSerial wserial;
        logic wr;
    } MemoryPipeReg;
    
    MemoryPipeReg memPipeReg[ MEMORY_READ_PIPELINE_DEPTH ];
    MemoryPipeReg nextMemPipeReg; // 次サイクルでパイプラインに投入するデータ

    MemAccessSerial nextNextMemReadSerial; // RSDの次の読み出し要求に割り当てられるシリアル(id)
    MemWriteSerial nextNextMemWriteSerial; // RSDの次の書き込み要求に割り当てられるシリアル(id)
    
    logic memReadAccessAck, prevMemReadAccessAck; // 読出要求を受け付けたかどうか
    logic memWriteAccessAck, prevMemWriteAccessAck; // 読出要求を受け付けたかどうか
    
    // AccessBusyである残りサイクル数をカウント
    MemoryProcessLatencyCount processLatencyCount, nextProcessLatencyCount;
    
    MemoryEntryDataPath ramReadData;
    
    logic memoryWE;
    AddrPath memoryWA;
    MemoryEntryDataPath memoryWV;
    AddrPath memoryRA;

    // Body
    InitializedBlockRAM #( 
        .ENTRY_NUM( MEMORY_ENTRY_NUM ),
        .INIT_HEX_FILE( INIT_HEX_FILE ),
        .ENTRY_BIT_SIZE( MEMORY_ENTRY_BIT_NUM )
    ) body ( 
        .clk( clk ),
        .we( memoryWE ),
        .wa( memoryWA[ MEMORY_ADDR_MSB : MEMORY_ADDR_LSB ] ),
        .wv( memoryWV ),
        .ra( memoryRA[ MEMORY_ADDR_MSB : MEMORY_ADDR_LSB ] ),
        .rv( ramReadData )
    );

    // Push memory request temporarily to queue
    logic pushRequestQueue;
    MemoryLatencySimRequestPath pushedData;

    logic hasRequest, hasRequestReg;
    MemoryLatencySimRequestPath requestData, requestDataReg;

    MemoryLatencySimulator memReqQueue(
        .clk (clk),
        .rst (rst),
        .push (pushRequestQueue),
        .pushedData (pushedData),
        .hasRequest (hasRequest),
        .requestData (requestData)
    );
    
    // ARCコンテストのDDR2コントローラに合わせ、
    // クロックの立ち下がりで動かす
    always_ff @( posedge clk ) begin
        if ( rst ) begin
            processLatencyCount <= FALSE;
            prevMemReadAccessAck <= FALSE;
            prevMemWriteAccessAck <= FALSE;
            nextMemReadSerial <= '0;
            nextMemWriteSerial <= '0;
            requestDataReg <= '0;
            hasRequestReg <= FALSE;
            
            for ( int i = 0; i < MEMORY_READ_PIPELINE_DEPTH; i++ ) begin
                memPipeReg[i] <= '0;
            end
        end
        else begin
            processLatencyCount <= nextProcessLatencyCount;
            prevMemReadAccessAck <= memReadAccessAck;
            prevMemWriteAccessAck <= memWriteAccessAck;
            nextMemReadSerial <= nextNextMemReadSerial;
            nextMemWriteSerial <= nextNextMemWriteSerial;
            requestDataReg <= requestData;
            hasRequestReg <= hasRequest;
            
            memPipeReg[0] <= nextMemPipeReg;
            for ( int i = 0; i < MEMORY_READ_PIPELINE_DEPTH-1; i++ ) begin
                memPipeReg[i+1] <= memPipeReg[i];
            end
        end
    end
    
    always_comb begin
        // AccessBusyである残り時間をカウント
        if ( memAccessBusy ) begin
            nextProcessLatencyCount = processLatencyCount - 1;
        end
        else begin
            // RE/WEが立ったら、数サイクルAccessBusyになる
            if ( memAccessRE ) begin
                nextProcessLatencyCount = MEMORY_READ_PROCESS_LATENCY;
            end
            else if ( memAccessWE ) begin
                nextProcessLatencyCount = MEMORY_WRITE_PROCESS_LATENCY;
            end
            else begin
                nextProcessLatencyCount = 0;
            end
        end

        if (prevMemReadAccessAck) begin
            nextNextMemReadSerial = nextMemReadSerial + 1;
        end
        else begin
            nextNextMemReadSerial = nextMemReadSerial;
        end

        if (prevMemWriteAccessAck) begin
            nextNextMemWriteSerial = nextMemWriteSerial + 1;
        end
        else begin
            nextNextMemWriteSerial = nextMemWriteSerial;
        end
        
        // 読出要求が来て、Busyじゃなければ受け付ける
        memReadAccessAck = ( memAccessRE && !memAccessBusy ) ? TRUE : FALSE;

        // 書込要求が来て、Busyじゃなければ受け付ける
        memWriteAccessAck = ( memAccessWE && !memAccessBusy ) ? TRUE : FALSE;
        
        // 前のサイクルで読出要求を受け付けたら、読出結果をパイプラインに入力
        
        /* 修正前
        nextMemPipeReg.valid = prevMemReadAccessAck;
        nextMemPipeReg.data = ramReadData;
        nextMemPipeReg.serial = nextMemReadSerial;
        nextMemPipeReg.wserial = nextMemWriteSerial;
        nextMemPipeReg.wr = prevMemWriteAccessAck;
        */
        nextMemPipeReg.valid = hasRequestReg ? requestDataReg.isRead : FALSE;
        nextMemPipeReg.data = ramReadData;
        nextMemPipeReg.serial = requestDataReg.nextMemReadSerial;
        nextMemPipeReg.wserial = requestDataReg.nextMemWriteSerial;
        nextMemPipeReg.wr = requestDataReg.wr;

        pushRequestQueue = memReadAccessAck || memWriteAccessAck;
        pushedData.isRead = memAccessRE;
        pushedData.isWrite = memAccessWE;
        pushedData.memAccessAddr = memAccessAddr;
        pushedData.memAccessWriteData = memAccessWriteData;
        pushedData.nextMemReadSerial = nextNextMemReadSerial;
        pushedData.nextMemWriteSerial = nextNextMemWriteSerial;
        pushedData.wr = memWriteAccessAck;

        memoryWE = hasRequest ? requestData.isWrite : FALSE;
        memoryWA = requestData.memAccessAddr;
        memoryWV = requestData.memAccessWriteData;
        memoryRA = requestData.memAccessAddr;

    end

    // 出力ポート
    always_comb begin
        memReadDataReady = memPipeReg[ MEMORY_READ_PIPELINE_DEPTH-1 ].valid;
        memReadData = memPipeReg[ MEMORY_READ_PIPELINE_DEPTH-1 ].data;
        memAccessBusy = ( processLatencyCount != 0 ? TRUE : FALSE );
        memReadSerial = memPipeReg[ MEMORY_READ_PIPELINE_DEPTH-1 ].serial;
        memAccessResponse.valid = memPipeReg[ MEMORY_WRITE_PROCESS_LATENCY-1 ].wr;
        memAccessResponse.serial = memPipeReg[ MEMORY_WRITE_PROCESS_LATENCY-1 ].wserial;
    end

    `RSD_ASSERT_CLK(
        clk,
        !(memAccessRE && memAccessWE),
        "Cannot read and write the memory in the same cycle!"
    );
 endmodule
