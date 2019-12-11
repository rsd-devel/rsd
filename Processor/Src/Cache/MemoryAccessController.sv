// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Memory Access Controller
// キャッシュとメモリの間に存在し、
// メモリアクセス要求の形式を変換する。
// ICacheとDCacheからのアクセスの調停も行う。
//

`include "BasicMacros.sv"

import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryTypes::*;
import MemoryMapTypes::*;

module MemoryAccessController (
    CacheSystemIF.MemoryAccessController port,
input
    MemAccessSerial nextMemReadSerial, // RSDの次の読み出し要求に割り当てられるシリアル(id)
    MemWriteSerial nextMemWriteSerial, // RSDの次の書き込み要求に割り当てられるシリアル(id)
    MemoryEntryDataPath memReadData,
    logic memReadDataReady,
    MemAccessSerial memReadSerial, // メモリの読み出しデータのシリアル
    MemAccessResponse memAccessResponse, // メモリ書き込み完了通知
    logic memAccessReadBusy,
    logic memAccessWriteBusy,
output
    PhyAddrPath memAccessAddr,
    MemoryEntryDataPath memAccessWriteData,
    logic memAccessRE,
    logic memAccessWE
);
    // ICache/DCacheからの要求を受理するか否か
    logic icAck;
    logic dcAck;

    // メモリアクセスのシリアル番号を保持するカウンタ
    // 現在の実装では、読出し
    MemAccessSerial reqSerial, nextReqSerial;
    MemAccessSerial resultSerial, nextResultSerial;

    always_ff @( posedge port.clk ) begin
        if ( port.rst ) begin
            reqSerial <= '0;
            resultSerial <= '0;
        end
        else begin
            reqSerial <= nextReqSerial;
            resultSerial <= nextResultSerial;
        end
    end

    // メモリへのアクセス要求
    always_comb begin
        // ICache/DCacheの要求を受けるor何もしない を決定
        icAck = FALSE;
        dcAck = FALSE;
        if ( !memAccessReadBusy && port.icMemAccessReq.valid )
            icAck = TRUE;
        else if ( !memAccessReadBusy && port.dcMemAccessReq.valid && ( port.dcMemAccessReq.we == FALSE ) )
            dcAck = TRUE;
        else if ( !memAccessWriteBusy && port.dcMemAccessReq.valid  && ( port.dcMemAccessReq.we == TRUE ) )
            dcAck = TRUE;

        // ICache/DCacheの要求を受ける場合、
        // それに従ってメモリへリクエストを送る
        if ( icAck ) begin
            memAccessAddr = port.icMemAccessReq.addr;
            memAccessWriteData = '0;
            memAccessRE = TRUE;
            memAccessWE = FALSE;
        end
        else if ( dcAck ) begin
            memAccessAddr = port.dcMemAccessReq.addr;
            memAccessWriteData = port.dcMemAccessReq.data;
            memAccessRE = ( port.dcMemAccessReq.we ? FALSE : TRUE );
            memAccessWE = ( port.dcMemAccessReq.we ? TRUE : FALSE );
        end
        else begin
            memAccessAddr = '0;
            memAccessWriteData = '0;
            memAccessRE = FALSE;
            memAccessWE = FALSE;
        end

        // Ack for Request
        port.icMemAccessReqAck.ack = icAck;
        port.icMemAccessReqAck.serial = nextMemReadSerial; // I-Cacheは読み出し要求しかしない
        port.dcMemAccessReqAck.ack = dcAck;
        // D-Cacheの要求は書き込みと読み出しの2種類あり，シリアルは独立に管理されている
        port.dcMemAccessReqAck.serial = nextMemReadSerial;
        port.dcMemAccessReqAck.wserial = nextMemWriteSerial;
    end

    // メモリの読出し結果
    always_comb begin
        port.icMemAccessResult.valid = memReadDataReady;
        port.icMemAccessResult.serial = memReadSerial;
        port.icMemAccessResult.data = memReadData;
        port.dcMemAccessResult.valid = memReadDataReady;
        port.dcMemAccessResult.serial = memReadSerial;
        port.dcMemAccessResult.data = memReadData;
        port.dcMemAccessResponse = memAccessResponse;
    end

    // MemAccessSerial
    always_comb begin
        nextReqSerial = reqSerial;
        nextResultSerial = resultSerial;

        // 読出要求が来たら、reqSerialをインクリメント
        if ( icAck || ( dcAck && port.dcMemAccessReq.we == FALSE ) ) begin
            nextReqSerial = reqSerial + 1;
        end

        // 読出結果が来たら、resultSerialをインクリメント
        if ( memReadDataReady ) begin
            nextResultSerial = resultSerial + 1;
        end
    end

    // 現在の実装では、キャッシュラインのデータ幅とメモリの入出力データ幅は
    // 同じである必要がある。
    `RSD_STATIC_ASSERT(
        $bits(ICacheLinePath) == $bits(MemoryEntryDataPath), 
        ("The data width of a cache line(%x) and a memory entry(%x) are not matched.", $bits(ICacheLinePath), $bits(MemoryEntryDataPath))
    );
    `RSD_STATIC_ASSERT(
        $bits(DCacheLinePath) == $bits(MemoryEntryDataPath),
        ("The data width of a cache line(%x) and a memory entry(%x) are not matched.", $bits(DCacheLinePath), $bits(MemoryEntryDataPath))
    );
endmodule

