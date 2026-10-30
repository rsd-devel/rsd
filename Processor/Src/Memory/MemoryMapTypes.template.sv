// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

{{ GENERATED_NOTICE }}


// 
// --- Types related to a memory map
//

package MemoryMapTypes;

import BasicTypes::*;


//
// Related to instructions 
//
localparam INSN_RESET_VECTOR = {{ INSN_RESET_VECTOR }};

// The processor stops when it reaches PC_GOAL
localparam PC_GOAL = {{ PC_GOAL }};

//
// PC
//

 // This option compresses PC for reducing resource consumption.
{{ RSD_NARROW_PC_DEFINE }}
// The PC compression is achieved by leveraging the memory map.
// The memory map in the logical address space is as follows.
{{ MEMORY_MAP_DOC }}
// In this map, instruction access is not performed in the IO area, so
// the range of valid instructions is only in the ROM and RAM areas.
// The narrow PC format keeps the most significant bit and lower address bits.
// Note that when handling exceptions, it is necessary to handle with a 32-bit address.

`ifdef RSD_NARROW_PC
localparam PC_WIDTH = {{ PC_WIDTH }};
`else
localparam PC_WIDTH = ADDR_WIDTH;
`endif

localparam PC_TAG = ADDR_WIDTH - PC_WIDTH;
typedef logic [PC_WIDTH-1:0] PC_Path;

// 圧縮されたPCを32ビットアドレスに変換する
function automatic AddrPath ToAddrFromPC ( PC_Path pc );
`ifdef RSD_NARROW_PC
    return { pc[PC_WIDTH-1], { PC_TAG{1'b0} }, pc[PC_WIDTH-2:0] };
`else
    return pc;
`endif
endfunction

// 32ビットアドレスを圧縮する
function automatic PC_Path ToPC_FromAddr ( AddrPath addr );
`ifdef RSD_NARROW_PC
    return { addr[ADDR_WIDTH-1], addr [PC_WIDTH-2:0] };
`else
    return addr;
`endif
endfunction


//
// Logical address memory type
//
typedef enum logic[1:0]  {
    MMT_MEMORY  = 2'b00,
    MMT_IO      = 2'b01,
    MMT_ILLEGAL = 2'b10
} MemoryMapType;

//
// Physical Address
// The most significant two bits of the physical memory address is used distinguish between 
// accesses to a normal memory region, memory-mapped IO region, and uncachable region.
localparam PHY_ADDR_WIDTH = {{ PHY_ADDR_WIDTH }};  // 1bit uncachable flag + 1bit IO flag + raw memory space
localparam PHY_ADDR_WIDTH_BIT_SIZE = $clog2(PHY_ADDR_WIDTH);
localparam PHY_ADDR_BYTE_WIDTH = PHY_ADDR_WIDTH / BYTE_WIDTH;

localparam PHY_RAW_ADDR_WIDTH = PHY_ADDR_WIDTH - 2;
localparam PHY_RAW_ADDR_WIDTH_BIT_SIZE = $clog2(PHY_RAW_ADDR_WIDTH);
localparam PHY_RAW_ADDR_BYTE_WIDTH = PHY_RAW_ADDR_WIDTH / BYTE_WIDTH;

typedef logic [PHY_RAW_ADDR_WIDTH-1:0] PhyRawAddrPath;
typedef struct packed {
    logic isUncachable; // True if address points to an uncachable address space.
    logic isIO; // True if address points to a memory-mapped IO.
    PhyRawAddrPath addr;
} PhyAddrPath;


//
// Memory map between logical and physical address spaces
// 

{{ MEMORY_MAP_CONSTANTS }}


// Get a memory type from a logical address
function automatic MemoryMapType GetMemoryMapType(AddrPath addr);
{{ GET_MEMORY_MAP_TYPE_BODY }}
    else begin
        return MMT_ILLEGAL;
    end
endfunction

// Convert a logical address to a physical address
function automatic PhyAddrPath ToPhyAddrFromLogical(AddrPath logAddr);
    PhyAddrPath phyAddr;

{{ TO_PHY_ADDR_FROM_LOGICAL_BODY }}
    else begin
        // Invalid
        phyAddr.isUncachable = FALSE;
        phyAddr.isIO = FALSE;
        phyAddr.addr = 32'hCCCC_CCCC;
    end

    return phyAddr;
endfunction

function automatic logic IsPhyAddrIO(PhyAddrPath phyAddr);
    return phyAddr.isIO;
endfunction

function automatic logic IsPhyAddrUncachable(PhyAddrPath phyAddr);
    return phyAddr.isUncachable;
endfunction

endpackage
