// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


package MemoryTypes;

import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryMapTypes::*;

//
// メインメモリのメモリサイズ
//
`ifdef RSD_SYNTHESIS
    `ifdef RSD_USE_EXTERNAL_MEMORY
        localparam MEMORY_ADDR_BIT_SIZE = 32;
    `else
        localparam MEMORY_ADDR_BIT_SIZE = 18; // 256KB
    `endif
`else
        localparam MEMORY_ADDR_BIT_SIZE = 25; // 512KB
`endif

localparam MEMORY_BYTE_SIZE = 1 << MEMORY_ADDR_BIT_SIZE;

// メモリはダミーデータで初期化するが
// そのダミーデータの行数（1行がメモリの1エントリに対応）を指定する。
// メモリの方が大きければ、ダミーデータを繰り返し読み込んで初期化する。
localparam DUMMY_HEX_ENTRY_NUM = 256;


// Size
localparam MEMORY_ENTRY_BIT_NUM /*verilator public*/ = 64; // メモリ1エントリのビット幅
localparam MEMORY_ENTRY_BYTE_NUM = MEMORY_ENTRY_BIT_NUM / BYTE_WIDTH;
localparam MEMORY_ADDR_MSB = MEMORY_ADDR_BIT_SIZE - 1;
localparam MEMORY_ADDR_LSB = $clog2( MEMORY_ENTRY_BYTE_NUM );
localparam MEMORY_INDEX_BIT_WIDTH = MEMORY_ADDR_MSB - MEMORY_ADDR_LSB + 1;
localparam MEMORY_ENTRY_NUM /*verilator public*/ = (1 << MEMORY_INDEX_BIT_WIDTH);
typedef logic [ MEMORY_ENTRY_BIT_NUM-1:0 ] MemoryEntryDataPath;

// Latency

// - メモリ読み出し時に通るパイプラインの長さ。
localparam MEMORY_READ_PIPELINE_DEPTH = 5;

// - メモリ書込アクセスの処理時間
localparam MEMORY_WRITE_PROCESS_LATENCY = 2;

// - メモリ読出アクセスの処理時間
// 読出アクセスを行ってから、次に読出/書込アクセスできるようになるまでの
// サイクル数を示す。データを取得するまでのサイクル数ではないので注意。
localparam MEMORY_READ_PROCESS_LATENCY = 2;

// - メモリ読出/書込アクセスの処理時間をカウント
typedef logic [1:0] MemoryProcessLatencyCount;


//
// RSDがAXI4を用いてメモリアクセスする場合のAXI4バスのパラメータ
//

// RSDのメモリ空間とPS(ARM)のメモリ空間のオフセット
// PS(ARM)のプロセスはここで指定したアドレス以降の空間をRSDとの明示的データ共有以外の目的で使用してはいけない．
localparam MEMORY_AXI4_BASE_ADDR = 32'h10000000; // 256MB

localparam MEMORY_AXI4_DATA_BIT_NUM = 64; // AXI4バスのデータ幅

// AXI4のバースト数
// RSDのメモリアクセス単位はキャッシュライン幅単位なので，それをAXI4バスのデータ幅で割った数
localparam MEMORY_AXI4_BURST_LEN = MEMORY_ENTRY_BIT_NUM/MEMORY_AXI4_DATA_BIT_NUM;
localparam MEMORY_AXI4_BURST_BIT_NUM = $clog2( MEMORY_AXI4_BURST_LEN );

// 同時にoutstanding可能なトランザクションの最大数を決める
// D-Cacheからの要求の最大数はMSHR_NUM，I-Cacheからの要求は1，最大要求数はMSHR_NUM+1となる
localparam MEMORY_AXI4_READ_ID_WIDTH = CacheSystemTypes::MEM_ACCESS_SERIAL_BIT_SIZE;
localparam MEMORY_AXI4_READ_ID_NUM = (1 << MEMORY_AXI4_READ_ID_WIDTH);

// 書き込みの総数は2のべき乗
// 現状，書き込み完了応答があるまで次の書き込みはできないため，InOに1つずつしか書き込みできない
// しかし，RSDからの書き込み要求を受け取ってバッファすることでアドレス要求(aw handshake)を先行して行えるので，
// MSHRと同数にするのが好ましい
localparam MEMORY_AXI4_WRITE_ID_WIDTH = CacheSystemTypes::MEM_WRITE_SERIAL_BIT_SIZE;
localparam MEMORY_AXI4_WRITE_ID_NUM = (1 << MEMORY_AXI4_WRITE_ID_WIDTH);

localparam MEMORY_AXI4_ADDR_BIT_SIZE = MEMORY_ADDR_BIT_SIZE; // AXI4のアドレス幅

// *USERはすべて未使用のため，専用線は削除
localparam MEMORY_AXI4_AWUSER_WIDTH = 0;
localparam MEMORY_AXI4_ARUSER_WIDTH = 0;
localparam MEMORY_AXI4_WUSER_WIDTH = 0;
localparam MEMORY_AXI4_RUSER_WIDTH = 0;
localparam MEMORY_AXI4_BUSER_WIDTH = 0;

typedef struct packed {
    logic [MEMORY_AXI4_READ_ID_WIDTH-1: 0] id; // AXI4用のリクエストID
    logic [MEMORY_AXI4_ADDR_BIT_SIZE-1: 0] addr;
} MemoryReadReq;

// To add variable latency memory access
localparam MEM_REQ_QUEUE_SIZE = 128;
localparam VARIAVBLE_WIDTH = 10;
localparam RANDOM_LATENCY_SEED = 10;
typedef logic [$clog2(VARIAVBLE_WIDTH):0] LatencyCountPath;
typedef struct packed {
    logic isRead;
    logic isWrite;
    AddrPath memAccessAddr;
    MemoryEntryDataPath memAccessWriteData;
    MemAccessSerial nextMemReadSerial; // RSDの次の読み出し要求に割り当てられるシリアル(id)
    MemWriteSerial nextMemWriteSerial; // RSDの次の書き込み要求に割り当てられるシリアル(id)
    logic wr;
} MemoryRequestData;


// PS-PL Memoryサイズ
localparam PS_PL_MEMORY_DATA_BIT_SIZE = 32;
localparam PS_PL_MEMORY_ADDR_BIT_SIZE = 11;
localparam PS_PL_MEMORY_ADDR_LSB = (PS_PL_MEMORY_DATA_BIT_SIZE/32) + 1; // 32-bit: 2, 64-bit: 3
localparam PS_PL_MEMORY_SIZE = 1 << (PS_PL_MEMORY_ADDR_BIT_SIZE-PS_PL_MEMORY_ADDR_LSB); // 512

// PS-PL ControlRegister
localparam PS_PL_CTRL_REG_DATA_BIT_SIZE = 32;
localparam PS_PL_CTRL_REG_ADDR_BIT_SIZE = 7;
localparam PS_PL_CTRL_REG_ADDR_LSB = (PS_PL_CTRL_REG_DATA_BIT_SIZE/32) + 1; // 32-bit: 2, 64-bit: 3
localparam PS_PL_CTRL_REG_SIZE = 1 << (PS_PL_CTRL_REG_ADDR_BIT_SIZE-PS_PL_CTRL_REG_ADDR_LSB); // 32

// PS-PL ControlQueue
localparam PS_PL_CTRL_QUEUE_DATA_BIT_SIZE = PS_PL_CTRL_REG_DATA_BIT_SIZE;
localparam PS_PL_CTRL_QUEUE_ADDR_BIT_SIZE = 6;
localparam PS_PL_CTRL_QUEUE_SIZE = 1 << PS_PL_CTRL_QUEUE_ADDR_BIT_SIZE; // 64


endpackage
