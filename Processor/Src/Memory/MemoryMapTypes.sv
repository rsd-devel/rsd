// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


// 
// --- Types related to a memory map
//

package MemoryMapTypes;

import BasicTypes::*;

//
// --- Memory map
//



//
// 命令アドレス
//
localparam INSN_RESET_VECTOR = 32'h00001000;

// すべてのベンチマークは、PC_GOALを最終PCとする
localparam PC_GOAL = 32'h80001004;

//
// PC
//

 // PCを圧縮して19ビットにする．面積削減用．
`define RSD_NARROW_PC
 //    PCの圧縮は，現在の論理アドレス空間のメモリ配置をうまく利用して実現している
 //    現在の論理アドレス空間のメモリ配置は以下の通り．
 //      0x0000_1000 - 0x0000_FFFF: Section 0 (ROM)
 //      0x8000_0000 - 0x8003_FFFF: Section 1 (RAM)
 //      0x4000_0000 - 0x4000_000F: Timer IO
 //      0x4000_2000: Serial IO 
 //    このうち，IO 領域には命令アクセスを行うことはないため，
 //    有効な命令の範囲は ROM および RAM 領域のみである．
 //    この範囲内では，論理アドレスは最上位1ビットと下位18ビットしか使われることがない:
 //        ROM 領域: 最上位ビットは 0, 下位16ビットを使用
 //        RAM 領域: 最上位ビットは 1, 下位18ビットを使用
 //    したがって，使わないビットを捨てて，間を詰めることでPCの圧縮が可能
 //      例1) ROM 領域: 0x0000_2000 -> 0x0_2000
 //      例2) RAM 領域: 0x8000_2000 -> 0x4_2000 (最上位 1 ビットと下位 18 ビットを抽出)
 //    ただし，例外を取り扱う際は，32ビットのアドレスで処理する必要があるので注意

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
// 論理と物理メモリ空間のマッピング
// 


//
// Section 0 (ROM?)
// 0x0000_1000 - 0x0000_ffff -> 0x0_1000 -> 0x0_ffff
//
localparam LOG_ADDR_SECTION_0_BEGIN = 32'h0000_1000;
localparam LOG_ADDR_SECTION_0_END   = 32'h0001_0000;
localparam LOG_ADDR_SECTION_0_ADDR_BIT_WIDTH = 16;

// 下位アドレスを切り出してそのまま加算できるように，0x1000 分は無視
localparam PHY_ADDR_SECTION_0_BASE = 20'h0_0000;


//
// Section 1 (RAM?)
// 0x8000_0000 - 0x8003_ffff -> 0x1_0000 -> 0x4_ffff
//
localparam LOG_ADDR_SECTION_1_BEGIN = 32'h8000_0000;
localparam LOG_ADDR_SECTION_1_END   = 32'h8004_0000;
localparam LOG_ADDR_SECTION_1_ADDR_BIT_WIDTH = 18;

localparam PHY_ADDR_SECTION_1_BASE = 20'h1_0000;

//
// Uncachable section (RAM?)
// 0x8004_0000 - 0x8004_ffff -> 0x5_0000 -> 0x5_ffff
//
localparam LOG_ADDR_UNCACHABLE_BEGIN = 32'h8004_0000;
localparam LOG_ADDR_UNCACHABLE_END   = 32'h8005_0000;
localparam LOG_ADDR_UNCACHABLE_ADDR_BIT_WIDTH = 19;

// 下位アドレスを切り出してそのまま加算できるように，0x1000 分は無視
localparam PHY_ADDR_UNCACHABLE_BASE = 20'h1_0000;

//
// --- Serial IO
//
localparam LOG_ADDR_SERIAL_OUTPUT = 32'h4000_2000;
localparam PHY_ADDR_SERIAL_OUTPUT = 20'h0_2000;


//
// --- Timer IO
//

// Timer IO の 論理アドレス
// 0x4000_0000 - 0x4000_000F
localparam LOG_ADDR_TIMER_BASE    = 32'h4000_0000;
localparam LOG_ADDR_TIMER_LOW     = LOG_ADDR_TIMER_BASE + 0;
localparam LOG_ADDR_TIMER_HI      = LOG_ADDR_TIMER_BASE + 4;
localparam LOG_ADDR_TIMER_CMP_LOW = LOG_ADDR_TIMER_BASE + 8;
localparam LOG_ADDR_TIMER_CMP_HI  = LOG_ADDR_TIMER_BASE + 12;

localparam LOG_ADDR_TIMER_BEGIN = LOG_ADDR_TIMER_BASE;
localparam LOG_ADDR_TIMER_END   = LOG_ADDR_TIMER_BASE + 16;

// タイマーの IO 物理アドレス
// 0x0_0000 - 0x0_000F
localparam PHY_ADDR_TIMER_BASE    = 20'h0_0000;
localparam PHY_ADDR_TIMER_LOW     = PHY_ADDR_TIMER_BASE + 0;
localparam PHY_ADDR_TIMER_HI      = PHY_ADDR_TIMER_BASE + 4;
localparam PHY_ADDR_TIMER_CMP_LOW = PHY_ADDR_TIMER_BASE + 8;
localparam PHY_ADDR_TIMER_CMP_HI  = PHY_ADDR_TIMER_BASE + 12;

localparam PHY_ADDR_TIMER_ZONE_BIT_WIDTH = 4;


// 論理アドレスからメモリタイプを得る
function automatic MemoryMapType GetMemoryMapType(AddrPath addr);
    // TODO: アドレス変換を真面目に実装する
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

// 論理アドレスから物理アドレスへの変換
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
