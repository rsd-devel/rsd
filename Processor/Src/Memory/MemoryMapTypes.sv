// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


// 
// --- Types related to a memory map
//

package MemoryMapTypes;

import BasicTypes::*;


//
// Related to instructions 
//
localparam INSN_RESET_VECTOR = 32'h00001000;

// The processor stops when it reaches PC_GOAL
localparam PC_GOAL = 32'h80001004;

//
// PC
//

 // This option compresses PC to 19 bits for reducing resource consumption.
`define RSD_NARROW_PC
// The PC compression is achieved by leveraging the memory map.
// The memory map in the logical address space is as follows.
//       0x0000_1000 --0x0000_FFFF: Section 0 (ROM)
//       0x8000_0000 --0x8003_FFFF: Section 1 (RAM)
//       0x8004_0000 --0x8004_FFFF: Section 2 (Uncachable RAM)
//       0x4000_0000 --0x4000_000F: Timer IO
//       0x4000_2000: Serial IO
// In this map, instruction access is not performed in the IO area, so
// the range of valid instructions is only in the ROM and RAM areas.
// Within this range, only the most significant 1 bit and the lowest 18 bits are used:
//       ROM area: Most significant bit is 0, lower 16 bits are used
//       RAM area: Most significant bit is 1, low 18 bits
// Therefore, it is possible to compress the PC by discarding unused bits and to close the gap.
//       Example 1) ROM area: 0x0000_2000-> 0x0_2000
//       Example 2) RAM area: 0x8000_2000-> 0x4_2000 (extract the most significant 1 bit and the lowest 18 bits)
// Note that when handling exceptions, it is necessary to handle with a 32-bit address.

`ifdef RSD_NARROW_PC
localparam PC_WIDTH = 19;
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
localparam PHY_ADDR_WIDTH = 22;  // 22 bits: 1bit uncachable flag + 1bit IO flag + 1MB memory space
localparam PHY_ADDR_WIDTH_BIT_SIZE = $clog2(PHY_ADDR_WIDTH);
localparam PHY_ADDR_BYTE_WIDTH = PHY_ADDR_WIDTH / BYTE_WIDTH;

localparam PHY_RAW_ADDR_WIDTH = PHY_ADDR_WIDTH - 2;  // 20 + isIO (1 bit) + isUncachable (1 bit)
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


//
// Section 0 (ROM?)
// logical [0x0000_1000 - 0x0000_ffff] -> physical [0x0_1000 - 0x0_ffff]
//
localparam LOG_ADDR_SECTION_0_BEGIN = ADDR_WIDTH'('h0000_1000);
localparam LOG_ADDR_SECTION_0_END   = ADDR_WIDTH'('h0001_0000);
localparam LOG_ADDR_SECTION_0_ADDR_BIT_WIDTH = 16;

// Ignore 0x1000 so that the lower address bits can be added as it is
localparam PHY_ADDR_SECTION_0_BASE = PHY_RAW_ADDR_WIDTH'('h0_0000);


//
// Section 1 (RAM?)
// logical [0x8000_0000 - 0x8003_ffff] -> physical [0x1_0000 - 0x4_ffff]
//
localparam LOG_ADDR_SECTION_1_BEGIN = ADDR_WIDTH'('h8000_0000);
localparam LOG_ADDR_SECTION_1_END   = ADDR_WIDTH'('h8004_0000);
localparam LOG_ADDR_SECTION_1_ADDR_BIT_WIDTH = 18;
localparam PHY_ADDR_SECTION_1_BASE = PHY_RAW_ADDR_WIDTH'('h1_0000);

//
// Uncachable section (RAM?)
// logical [0x8004_0000 - 0x8004_ffff] -> uncachable [0x5_0000 -> 0x5_ffff]
//
localparam LOG_ADDR_UNCACHABLE_BEGIN = ADDR_WIDTH'('h8004_0000);
localparam LOG_ADDR_UNCACHABLE_END   = ADDR_WIDTH'('h8005_0000);
localparam LOG_ADDR_UNCACHABLE_ADDR_BIT_WIDTH = 19;

// Ignore 0x1000 so that the lower address bits can be added as it is
localparam PHY_ADDR_UNCACHABLE_BASE = PHY_RAW_ADDR_WIDTH'('h1_0000);

//
// --- Serial IO
// logical [0x4000_2000] -> io [0x2000]
//
localparam LOG_ADDR_SERIAL_OUTPUT = ADDR_WIDTH'('h4000_2000);
localparam PHY_ADDR_SERIAL_OUTPUT = PHY_RAW_ADDR_WIDTH'('h0_2000);


//
// --- Timer IO
//

// Logical addresses for Timer IO 
// 0x4000_0000 - 0x4000_000F
localparam LOG_ADDR_TIMER_BASE    = ADDR_WIDTH'('h4000_0000);
localparam LOG_ADDR_TIMER_LOW     = LOG_ADDR_TIMER_BASE + 0;
localparam LOG_ADDR_TIMER_HI      = LOG_ADDR_TIMER_BASE + 4;
localparam LOG_ADDR_TIMER_CMP_LOW = LOG_ADDR_TIMER_BASE + 8;
localparam LOG_ADDR_TIMER_CMP_HI  = LOG_ADDR_TIMER_BASE + 12;

localparam LOG_ADDR_TIMER_BEGIN = LOG_ADDR_TIMER_BASE;
localparam LOG_ADDR_TIMER_END   = LOG_ADDR_TIMER_BASE + 16;

// Physical addresses for Timer IO 
// 0x0_0000 - 0x0_000F
localparam PHY_ADDR_TIMER_BASE    = PHY_RAW_ADDR_WIDTH'('h0_0000);
localparam PHY_ADDR_TIMER_LOW     = PHY_ADDR_TIMER_BASE + 0;
localparam PHY_ADDR_TIMER_HI      = PHY_ADDR_TIMER_BASE + 4;
localparam PHY_ADDR_TIMER_CMP_LOW = PHY_ADDR_TIMER_BASE + 8;
localparam PHY_ADDR_TIMER_CMP_HI  = PHY_ADDR_TIMER_BASE + 12;

localparam PHY_ADDR_TIMER_ZONE_BIT_WIDTH = 4;


// Get a memory type from a logical address
function automatic MemoryMapType GetMemoryMapType(AddrPath addr);
    if (addr == LOG_ADDR_SERIAL_OUTPUT) begin
        return MMT_IO;
    end
    else if (LOG_ADDR_TIMER_BEGIN <= addr && addr < LOG_ADDR_TIMER_END) begin
        return MMT_IO;
    end
    else if (LOG_ADDR_UNCACHABLE_BEGIN <= addr && addr < LOG_ADDR_UNCACHABLE_END) begin
        return MMT_MEMORY;
    end
    else if (LOG_ADDR_SECTION_0_BEGIN <= addr && addr < LOG_ADDR_SECTION_0_END) begin
        return MMT_MEMORY;
    end
    else if (LOG_ADDR_SECTION_1_BEGIN <= addr && addr < LOG_ADDR_SECTION_1_END) begin
        return MMT_MEMORY;
    end
    else begin
        return MMT_ILLEGAL;
    end
endfunction

// Convert a logical address to a physical address
function automatic PhyAddrPath ToPhyAddrFromLogical(AddrPath logAddr);
    PhyAddrPath phyAddr;

    if (logAddr == LOG_ADDR_SERIAL_OUTPUT) begin
        phyAddr.isUncachable = TRUE;
        phyAddr.isIO = TRUE;
        phyAddr.addr = PHY_ADDR_SERIAL_OUTPUT;
    end
    else if (LOG_ADDR_TIMER_BEGIN <= logAddr && logAddr < LOG_ADDR_TIMER_END) begin
        phyAddr.isUncachable = TRUE;
        phyAddr.isIO = TRUE;
        phyAddr.addr = PHY_ADDR_TIMER_BASE + 
            logAddr[PHY_ADDR_TIMER_ZONE_BIT_WIDTH-1:0];
    end
    else if (LOG_ADDR_UNCACHABLE_BEGIN <= logAddr && logAddr < LOG_ADDR_UNCACHABLE_END) begin
        // Uncachable region (RAM?)
        phyAddr.isUncachable = TRUE;
        phyAddr.isIO = FALSE;
        phyAddr.addr = PHY_ADDR_UNCACHABLE_BASE + 
            logAddr[LOG_ADDR_UNCACHABLE_ADDR_BIT_WIDTH-1:0];
    end
    
    else if (LOG_ADDR_SECTION_0_BEGIN <= logAddr && logAddr < LOG_ADDR_SECTION_0_END) begin
        // Section 0 (ROM?)
        phyAddr.isUncachable = FALSE;
        phyAddr.isIO = FALSE;
        phyAddr.addr = PHY_ADDR_SECTION_0_BASE + 
            logAddr[LOG_ADDR_SECTION_0_ADDR_BIT_WIDTH:0];
    end
    else if (LOG_ADDR_SECTION_1_BEGIN <= logAddr && logAddr < LOG_ADDR_SECTION_1_END) begin
        // Section 1 (RAM?)
        phyAddr.isUncachable = FALSE;
        phyAddr.isIO = FALSE;
        phyAddr.addr = PHY_ADDR_SECTION_1_BASE + 
            logAddr[LOG_ADDR_SECTION_1_ADDR_BIT_WIDTH-1:0];
    end
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
