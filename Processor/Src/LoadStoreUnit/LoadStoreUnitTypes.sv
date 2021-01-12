// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


// 
// --- Types related to a load-store queue.
//

package LoadStoreUnitTypes;

import MicroArchConf::*;
import BasicTypes::*;
import MemoryMapTypes::*;
import CacheSystemTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import MemoryMapTypes::*;

// Load/store queues compare addresses as a word unit.

// LSQ 内部の処理は，現在は物理アドレス幅に揃える
localparam LSQ_ADDR_MSB = PHY_ADDR_WIDTH; 
localparam LSQ_ADDR_UPPER_PADDING_BIT_SIZE = PHY_ADDR_WIDTH - LSQ_ADDR_MSB;

// LSQ 内部のデータ幅
//localparam LSQ_BLOCK_WIDTH = DATA_WIDTH;  // ロードストアの最大データ幅に等しい
localparam LSQ_BLOCK_WIDTH = 32;  // ロードストアの最大データ幅に等しい
localparam LSQ_BLOCK_WORD_WIDTH = LSQ_BLOCK_WIDTH / DATA_WIDTH;
localparam LSQ_BLOCK_BYTE_WIDTH = LSQ_BLOCK_WIDTH / BYTE_WIDTH;
localparam LSQ_BLOCK_BYTE_WIDTH_BIT_SIZE = $clog2(LSQ_BLOCK_BYTE_WIDTH);
typedef logic [LSQ_BLOCK_WIDTH-1:0] LSQ_BlockDataPath;


// LSQ 内部データ幅単位のアドレス
typedef logic [LSQ_ADDR_MSB-1-LSQ_BLOCK_BYTE_WIDTH_BIT_SIZE:0] LSQ_BlockAddrPath;

function automatic LSQ_BlockAddrPath LSQ_ToBlockAddr(PhyAddrPath addr);
    return addr[LSQ_ADDR_MSB-1 : LSQ_BLOCK_BYTE_WIDTH_BIT_SIZE];
endfunction

function automatic PhyAddrPath LSQ_ToFullAddrFromBlockAddr(LSQ_BlockAddrPath blockAddr);
    return { { LSQ_ADDR_UPPER_PADDING_BIT_SIZE{1'b0} }, blockAddr, {LSQ_BLOCK_BYTE_WIDTH_BIT_SIZE{1'b0}} };
endfunction

// Load queue
localparam LOAD_QUEUE_ENTRY_NUM = CONF_LOAD_QUEUE_ENTRY_NUM;
localparam LOAD_QUEUE_ENTRY_NUM_BIT_WIDTH = $clog2(LOAD_QUEUE_ENTRY_NUM);

typedef logic [ LOAD_QUEUE_ENTRY_NUM_BIT_WIDTH-1:0 ] LoadQueueIndexPath;
typedef logic [ LOAD_QUEUE_ENTRY_NUM_BIT_WIDTH:0 ] LoadQueueCountPath;
typedef logic [ (1<<LOAD_QUEUE_ENTRY_NUM_BIT_WIDTH)-1:0 ] LoadQueueOneHotPath;

// Store queue
localparam STORE_QUEUE_ENTRY_NUM = CONF_STORE_QUEUE_ENTRY_NUM;
localparam STORE_QUEUE_ENTRY_NUM_BIT_WIDTH = $clog2(STORE_QUEUE_ENTRY_NUM);

typedef logic [ STORE_QUEUE_ENTRY_NUM_BIT_WIDTH-1:0 ] StoreQueueIndexPath;
typedef logic [ STORE_QUEUE_ENTRY_NUM_BIT_WIDTH:0 ] StoreQueueCountPath;
typedef logic [ (1<<STORE_QUEUE_ENTRY_NUM_BIT_WIDTH)-1:0 ] StoreQueueOneHotPath;

// Read enable signals per word.
typedef logic [ LSQ_BLOCK_WORD_WIDTH-1:0 ] LSQ_BlockWordEnablePath;
typedef logic [ LSQ_BLOCK_BYTE_WIDTH-1:0 ] LSQ_BlockByteEnablePath;
typedef logic [ DATA_BYTE_WIDTH-1:0 ] LSQ_WordByteEnablePath;

// width が 0 の場合は 0 を返す
function automatic int LSQ_SelectBits(int data, int offset, int width);
    int ret;
    ret = 0;
    for (int i = 0; i < width; i++) begin
        ret[i] = data[i + offset];
    end
    return ret;
endfunction

// Generate read / write enable signals for each word
// from a memory address and an access size.
function automatic LSQ_BlockWordEnablePath LSQ_ToBlockWordEnable(
    PhyAddrPath addr,
    MemAccessMode mode
);
    LSQ_BlockWordEnablePath wordEnable;
    case(mode.size)
        MEM_ACCESS_SIZE_VEC: begin
            wordEnable = '1;    // All 1
        end
        default: begin
            wordEnable = 1;     // Lowest word
        end
    endcase

    return
        wordEnable << 
        LSQ_SelectBits(
            addr, DATA_BYTE_WIDTH_BIT_SIZE, LSQ_BLOCK_BYTE_WIDTH_BIT_SIZE - DATA_BYTE_WIDTH_BIT_SIZE
        );
    //return wordEnable << addr[ LSQ_BLOCK_BYTE_WIDTH_BIT_SIZE-1:DATA_BYTE_WIDTH_BIT_SIZE ];
endfunction

// Generate read / write enable signals for each byte
// from a memory address and an access size.
function automatic LSQ_WordByteEnablePath LSQ_ToWordByteEnable(
    PhyAddrPath addr,
    MemAccessMode mode
);
    LSQ_WordByteEnablePath byteEnable;
    
    case(mode.size)
        MEM_ACCESS_SIZE_BYTE: begin
            byteEnable = 'b0001;
        end
        MEM_ACCESS_SIZE_HALF_WORD: begin
            byteEnable = 'b0011;
        end
        default: begin
            byteEnable = '1;
        end
    endcase
    
    return byteEnable << addr[ DATA_BYTE_WIDTH_BIT_SIZE-1:0 ];
endfunction


function automatic PhyAddrPath LSQ_ToFullPhyAddrFromBlockAddrAndWordWE(
    LSQ_BlockAddrPath blockAddr, LSQ_BlockWordEnablePath wordWE
);
    PhyAddrPath ret;
    ret = {blockAddr, {LSQ_BLOCK_BYTE_WIDTH_BIT_SIZE{1'b0}}};
    for (int i = 0; i < LSQ_BLOCK_WORD_WIDTH; i++) begin
        if (wordWE[i]) begin
            return ret + i*DATA_BYTE_WIDTH;
        end
    end
    return ret;
endfunction

function automatic DataPath LSQ_ToScalarWordDataFromBlockData(
    LSQ_BlockDataPath data, LSQ_BlockWordEnablePath wordWE
);
    DataPath ret;
    ret = data[DATA_WIDTH-1:0];
    for (int i = 0; i < LSQ_BLOCK_WORD_WIDTH; i++) begin
        if (wordWE[i]) begin
            return (data >> (i*DATA_WIDTH));
        end
    end
    return ret;
endfunction

//
// Entries of LSQ
//

typedef struct packed // LoadQueueEntry
{
    // Whether the load was executed using the correct source operand
    logic regValid;
    // This flag indicate whether a load is finished or not.
    logic finished;
    
    // The address of a load.
    LSQ_BlockAddrPath address;
    
    // Read enable signals.
    LSQ_BlockWordEnablePath wordRE;

    // Addr for memory dependent predictor.
    PC_Path pc;
} LoadQueueEntry;

typedef struct packed // StoreQueueAddrEntry
{
    // Whether the store was executed using the correct source operand
    logic regValid;
    // This flag indicate whether a load is finished or not.
    logic finished;
    
    // The address of a store.
    LSQ_BlockAddrPath address;
    
    // Write enable signals.
    LSQ_BlockWordEnablePath wordWE;
    LSQ_WordByteEnablePath byteWE;
} StoreQueueAddrEntry;

typedef struct packed // StoreQueueDataEntry
{
    logic condEnabled;
    LSQ_BlockDataPath data;

    // Write enable signals.
    LSQ_BlockWordEnablePath wordWE;
    LSQ_WordByteEnablePath byteWE;
} StoreQueueDataEntry;


endpackage


