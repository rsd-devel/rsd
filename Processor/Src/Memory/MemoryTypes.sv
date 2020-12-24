// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

`include "SysDeps/XilinxMacros.vh"

package MemoryTypes;

import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryMapTypes::*;

//
// Size of Main Memory
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

// Specify the number of rows of the dummy data (one row corresponds to one entry in the memory) 
// for initializing the memory. 
// If the memory entry is larger than this value, the dummy data is repeatedly read and initialized.
localparam DUMMY_HEX_ENTRY_NUM = 256;


// Memory Entry Size
localparam MEMORY_ENTRY_BIT_NUM /*verilator public*/ = 64; // Bit width of each memory entry
localparam MEMORY_ENTRY_BYTE_NUM = MEMORY_ENTRY_BIT_NUM / BYTE_WIDTH;
localparam MEMORY_ADDR_MSB = MEMORY_ADDR_BIT_SIZE - 1;
localparam MEMORY_ADDR_LSB = $clog2( MEMORY_ENTRY_BYTE_NUM );
localparam MEMORY_INDEX_BIT_WIDTH = MEMORY_ADDR_MSB - MEMORY_ADDR_LSB + 1;
localparam MEMORY_ENTRY_NUM /*verilator public*/ = (1 << MEMORY_INDEX_BIT_WIDTH);
typedef logic [ MEMORY_ENTRY_BIT_NUM-1:0 ] MemoryEntryDataPath;

// Latency

// The pipeline length of memory read processing
localparam MEMORY_READ_PIPELINE_DEPTH = 5;

// The latency of memory write process
localparam MEMORY_WRITE_PROCESS_LATENCY = 2;

// The latency of memory read process.
// This value indicates # of cycles from the read access 
// to the next read/write access.
// Note that this value is not # of cycles to read data. 
localparam MEMORY_READ_PROCESS_LATENCY = 2;

// For counting the latency of memory read/write accrss
typedef logic [1:0] MemoryProcessLatencyCount;

typedef struct packed {
    logic [`MEMORY_AXI4_READ_ID_WIDTH-1: 0] id; // Request id for AXI4
    logic [`MEMORY_AXI4_ADDR_BIT_SIZE-1: 0] addr;
} MemoryReadReq;

// To simulate variable latency memory access
localparam MEM_LATENCY_SIM_QUEUE_SIZE = 128;
localparam MEM_LATENCY_SIM_LATENCY_FLUCTUATION_RANGE = 10;
localparam MEM_LATENCY_SIM_RAND_BIT_WIDTH = 32;
localparam MEM_LATENCY_SIM_RAND_SEED = 1987534242;
typedef logic [$clog2(MEM_LATENCY_SIM_LATENCY_FLUCTUATION_RANGE):0] LatencyCountPath;
typedef logic [MEM_LATENCY_SIM_RAND_BIT_WIDTH-1:0] MemoryRandPath;
typedef struct packed {
    logic isRead;
    logic isWrite;
    AddrPath memAccessAddr;
    MemoryEntryDataPath memAccessWriteData;
    MemAccessSerial nextMemReadSerial; // Serial ID assigned to the next read request
    MemWriteSerial nextMemWriteSerial; // Serial ID assigned to the next write request
    logic wr;
} MemoryLatencySimRequestPath;

endpackage
