// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


/*
 このファイルはSynplifyを用いた合成時のみ読み込まれます。
 QuestaSimによるシミュレーション時は読み込まれません。
*/

/*************************************/
/* These macros must not be changed. */
/*************************************/
`define RSD_SYNTHESIS // 合成時であることを示す

// 特定の信号(2次元以上のunpack配列？)は、
// Synplifyの合成時はinput／QuestaSimのシミュレーション時はref
// としないと動かないので、そのためのdefine
`define REF input 

`define RSD_SYNTHESIS_ZEDBOARD
`define RSD_SYNTHESIS_VIVADO

/********************************************************************/
/* These macros are for user configuration, so you can change them. */
/********************************************************************/

// ハードウェアカウンタ(実行サイクル数などをカウント)を合成しない場合、
// `RSD_DISABLE_HARDWARE_COUNTERを定義する
//`RSD_DISABLE_HARDWARE_COUNTER

/*
  Define one of these macros.
    - RSD_SYNTHESIS_TED : For Tokyo Electron Device Virtex-6 board (TB-6V-760LX)
        Defined compiler directives :
            `RSD_SMALL_MEMORY
    - RSD_SYNTHESIS_ATLYS : For Atlys Spartan-6 board
        Defined compiler directives :
            `RSD_DISABLE_DEBUG_REGISTER
            `RSD_USE_PROGRAM_LOADER
            `RSD_USE_EXTERNAL_MEMORY
    - RSD_SYNTHESIS_ZEDBOARD : For ZedBoard Zynq-7000 board
*/

/*
  Define one of these macros.
    - RSD_SYNTHESIS_SYNPLIFY : For Synopsys Synplify
    - RSD_SYNTHESIS_VIVADO   : For Xilinx Vivado
*/

`ifdef RSD_SYNTHESIS_ATLYS
    // If a RSD_DISABLE_DEBUG_REGISTER macro is not declared,
    // registers which are needed to debug is synthesized.
    // When you define a RSD_DISABLE_DEBUG_REGISTER macro,
    // you cannot utilize post-synthesis simulation,
    // but the area and speed of the processor are expected to improve.
    
    // AtlysボードはIOポートが少ないので、
    // 大量のIOポートを必要とするデバッグレジスタは今のところ実装できない
    `define RSD_DISABLE_DEBUG_REGISTER

    // プログラムローダをインスタンシエートする。
    // プログラムローダはリセット後にプログラムデータをシリアル通信で受けとり、
    // それをメモリに書き込む。この動作が終わるまでコアはメモリにアクセスできない。
    // 現在、プログラムローダはAtlysボードのみ対応しており、
    // 受け取るデータのサイズは SysDeps/Atlys/AtlysTypes.sv で設定する。
    `define RSD_USE_PROGRAM_LOADER

    // FPGA外部のメモリを使用する。
    // 現在は、AtlysボードのDDR2メモリにのみ対応。
    `define RSD_USE_EXTERNAL_MEMORY

    // 非ZYNQのFPGAがターゲット．
    // UART出力先がボードのI/Oポートで，ビット幅が8-bitとなる
    `define RSD_SYNTHESIS_FPGA

`elsif RSD_SYNTHESIS_TED
    `define RSD_SYNTHESIS_FPGA
`elsif RSD_SYNTHESIS_ZEDBOARD
    
    `define RSD_DISABLE_DEBUG_REGISTER

    // ZYNQがターゲット．
    // UART出力先がPSのUARTポートで，ビット幅が32-bitとなる
    `define RSD_SYNTHESIS_ZYNQ
    
`else
    // RSD_SYNTHESIS_TED / RSD_SYNTHESIS_ATLYS のいずれも定義されていない場合は
    // コンパイルエラーとする
    "Error!"
`endif

//
// シミュレーション時のみ定義されるはずのコンパイラディレクティブが
// 定義されていたらエラーとする。
//
`ifdef RSD_FUNCTIONAL_SIMULATION
    "Error!"
`endif

`ifdef RSD_POST_SYNTHESIS_SIMULATION
    "Error!"
`endif

// Synplify2017で論理合成する際は，
// トップ・レベル・モジュールの入出力ポートにインターフェースを使うと，
// Vivadoで合成できなくなる．
// そのため，インターフェース使わずに入出力ポートを記述する必要があるが，
// 非常に煩雑になるため，この部分をマクロに落とし込んで使用する．
`define EXPAND_AXI4MEMORY_PORT \
input \
    logic  axi4MemoryIF_M_AXI_ACLK, \
    logic  axi4MemoryIF_M_AXI_ARESETN, \
output \
    logic [MEMORY_AXI4_WRITE_ID_WIDTH-1 : 0] axi4MemoryIF_M_AXI_AWID, \
    logic [MEMORY_AXI4_ADDR_BIT_SIZE-1 : 0] axi4MemoryIF_M_AXI_AWADDR, \
    logic [7 : 0] axi4MemoryIF_M_AXI_AWLEN, \
    logic [2 : 0] axi4MemoryIF_M_AXI_AWSIZE, \
    logic [1 : 0] axi4MemoryIF_M_AXI_AWBURST, \
    logic  axi4MemoryIF_M_AXI_AWLOCK, \
    logic [3 : 0] axi4MemoryIF_M_AXI_AWCACHE, \
    logic [2 : 0] axi4MemoryIF_M_AXI_AWPROT, \
    logic [3 : 0] axi4MemoryIF_M_AXI_AWQOS, \
    logic [MEMORY_AXI4_AWUSER_WIDTH-1 : 0] axi4MemoryIF_M_AXI_AWUSER, \
    logic  axi4MemoryIF_M_AXI_AWVALID, \
input \
    logic  axi4MemoryIF_M_AXI_AWREADY, \
output \
    logic [MEMORY_AXI4_DATA_BIT_NUM-1 : 0] axi4MemoryIF_M_AXI_WDATA, \
    logic [MEMORY_AXI4_DATA_BIT_NUM/8-1 : 0] axi4MemoryIF_M_AXI_WSTRB, \
    logic  axi4MemoryIF_M_AXI_WLAST, \
    logic [MEMORY_AXI4_WUSER_WIDTH-1 : 0] axi4MemoryIF_M_AXI_WUSER, \
    logic  axi4MemoryIF_M_AXI_WVALID, \
input \
    logic  axi4MemoryIF_M_AXI_WREADY, \
    logic [MEMORY_AXI4_WRITE_ID_WIDTH-1 : 0] axi4MemoryIF_M_AXI_BID, \
    logic [1 : 0] axi4MemoryIF_M_AXI_BRESP, \
    logic [MEMORY_AXI4_BUSER_WIDTH-1 : 0] axi4MemoryIF_M_AXI_BUSER, \
    logic  axi4MemoryIF_M_AXI_BVALID, \
output \
    logic  axi4MemoryIF_M_AXI_BREADY, \
    logic [MEMORY_AXI4_READ_ID_WIDTH-1 : 0] axi4MemoryIF_M_AXI_ARID, \
    logic [MEMORY_AXI4_ADDR_BIT_SIZE-1 : 0] axi4MemoryIF_M_AXI_ARADDR, \
    logic [7 : 0] axi4MemoryIF_M_AXI_ARLEN, \
    logic [2 : 0] axi4MemoryIF_M_AXI_ARSIZE, \
    logic [1 : 0] axi4MemoryIF_M_AXI_ARBURST, \
    logic  axi4MemoryIF_M_AXI_ARLOCK, \
    logic [3 : 0] axi4MemoryIF_M_AXI_ARCACHE, \
    logic [2 : 0] axi4MemoryIF_M_AXI_ARPROT, \
    logic [3 : 0] axi4MemoryIF_M_AXI_ARQOS, \
    logic [MEMORY_AXI4_ARUSER_WIDTH-1 : 0] axi4MemoryIF_M_AXI_ARUSER, \
    logic  axi4MemoryIF_M_AXI_ARVALID, \
input \
    logic  axi4MemoryIF_M_AXI_ARREADY, \
    logic [MEMORY_AXI4_READ_ID_WIDTH-1 : 0] axi4MemoryIF_M_AXI_RID, \
    logic [MEMORY_AXI4_DATA_BIT_NUM-1 : 0] axi4MemoryIF_M_AXI_RDATA, \
    logic [1 : 0] axi4MemoryIF_M_AXI_RRESP, \
    logic  axi4MemoryIF_M_AXI_RLAST, \
    logic [MEMORY_AXI4_RUSER_WIDTH-1 : 0] axi4MemoryIF_M_AXI_RUSER, \
    logic  axi4MemoryIF_M_AXI_RVALID, \
output \
    logic  axi4MemoryIF_M_AXI_RREADY,

`define CONNECT_AXI4MEMORY_IF \
    axi4MemoryIF.M_AXI_ACLK = axi4MemoryIF_M_AXI_ACLK; \
    axi4MemoryIF.M_AXI_ARESETN = axi4MemoryIF_M_AXI_ARESETN; \
    axi4MemoryIF_M_AXI_AWID = axi4MemoryIF.M_AXI_AWID; \
    axi4MemoryIF_M_AXI_AWADDR = axi4MemoryIF.M_AXI_AWADDR; \
    axi4MemoryIF_M_AXI_AWLEN = axi4MemoryIF.M_AXI_AWLEN; \
    axi4MemoryIF_M_AXI_AWSIZE = axi4MemoryIF.M_AXI_AWSIZE; \
    axi4MemoryIF_M_AXI_AWBURST = axi4MemoryIF.M_AXI_AWBURST; \
    axi4MemoryIF_M_AXI_AWLOCK = axi4MemoryIF.M_AXI_AWLOCK; \
    axi4MemoryIF_M_AXI_AWCACHE = axi4MemoryIF.M_AXI_AWCACHE; \
    axi4MemoryIF_M_AXI_AWPROT = axi4MemoryIF.M_AXI_AWPROT; \
    axi4MemoryIF_M_AXI_AWQOS = axi4MemoryIF.M_AXI_AWQOS; \
    axi4MemoryIF_M_AXI_AWUSER = axi4MemoryIF.M_AXI_AWUSER; \
    axi4MemoryIF_M_AXI_AWVALID = axi4MemoryIF.M_AXI_AWVALID; \
    axi4MemoryIF.M_AXI_AWREADY = axi4MemoryIF_M_AXI_AWREADY; \
    axi4MemoryIF_M_AXI_WDATA = axi4MemoryIF.M_AXI_WDATA; \
    axi4MemoryIF_M_AXI_WSTRB = axi4MemoryIF.M_AXI_WSTRB; \
    axi4MemoryIF_M_AXI_WLAST = axi4MemoryIF.M_AXI_WLAST; \
    axi4MemoryIF_M_AXI_WUSER = axi4MemoryIF.M_AXI_WUSER; \
    axi4MemoryIF_M_AXI_WVALID = axi4MemoryIF.M_AXI_WVALID; \
    axi4MemoryIF.M_AXI_WREADY = axi4MemoryIF_M_AXI_WREADY; \
    axi4MemoryIF.M_AXI_BID = axi4MemoryIF_M_AXI_BID; \
    axi4MemoryIF.M_AXI_BRESP = axi4MemoryIF_M_AXI_BRESP; \
    axi4MemoryIF.M_AXI_BUSER = axi4MemoryIF_M_AXI_BUSER; \
    axi4MemoryIF.M_AXI_BVALID = axi4MemoryIF_M_AXI_BVALID; \
    axi4MemoryIF_M_AXI_BREADY = axi4MemoryIF.M_AXI_BREADY; \
    axi4MemoryIF_M_AXI_ARID = axi4MemoryIF.M_AXI_ARID; \
    axi4MemoryIF_M_AXI_ARADDR = axi4MemoryIF.M_AXI_ARADDR; \
    axi4MemoryIF_M_AXI_ARLEN = axi4MemoryIF.M_AXI_ARLEN; \
    axi4MemoryIF_M_AXI_ARSIZE = axi4MemoryIF.M_AXI_ARSIZE; \
    axi4MemoryIF_M_AXI_ARBURST = axi4MemoryIF.M_AXI_ARBURST; \
    axi4MemoryIF_M_AXI_ARLOCK = axi4MemoryIF.M_AXI_ARLOCK; \
    axi4MemoryIF_M_AXI_ARCACHE = axi4MemoryIF.M_AXI_ARCACHE; \
    axi4MemoryIF_M_AXI_ARPROT = axi4MemoryIF.M_AXI_ARPROT; \
    axi4MemoryIF_M_AXI_ARQOS = axi4MemoryIF.M_AXI_ARQOS; \
    axi4MemoryIF_M_AXI_ARUSER = axi4MemoryIF.M_AXI_ARUSER; \
    axi4MemoryIF_M_AXI_ARVALID = axi4MemoryIF.M_AXI_ARVALID; \
    axi4MemoryIF.M_AXI_ARREADY = axi4MemoryIF_M_AXI_ARREADY; \
    axi4MemoryIF.M_AXI_RID = axi4MemoryIF_M_AXI_RID; \
    axi4MemoryIF.M_AXI_RDATA = axi4MemoryIF_M_AXI_RDATA; \
    axi4MemoryIF.M_AXI_RRESP = axi4MemoryIF_M_AXI_RRESP; \
    axi4MemoryIF.M_AXI_RLAST = axi4MemoryIF_M_AXI_RLAST; \
    axi4MemoryIF.M_AXI_RUSER = axi4MemoryIF_M_AXI_RUSER; \
    axi4MemoryIF.M_AXI_RVALID = axi4MemoryIF_M_AXI_RVALID; \
    axi4MemoryIF_M_AXI_RREADY = axi4MemoryIF.M_AXI_RREADY;


`define EXPAND_CONTROL_REGISTER_PORT \
input \
    logic axi4LitePlToPsControlRegisterIF_S_AXI_ACLK, \
    logic axi4LitePlToPsControlRegisterIF_S_AXI_ARESETN, \
    logic [PS_PL_CTRL_REG_ADDR_BIT_SIZE-1 : 0] axi4LitePlToPsControlRegisterIF_S_AXI_ARADDR, \
    logic [2 : 0] axi4LitePlToPsControlRegisterIF_S_AXI_ARPROT, \
    logic  axi4LitePlToPsControlRegisterIF_S_AXI_ARVALID, \
output \
    logic  axi4LitePlToPsControlRegisterIF_S_AXI_ARREADY, \
    logic [PS_PL_CTRL_REG_DATA_BIT_SIZE-1 : 0] axi4LitePlToPsControlRegisterIF_S_AXI_RDATA, \
    logic [1 : 0] axi4LitePlToPsControlRegisterIF_S_AXI_RRESP, \
    logic  axi4LitePlToPsControlRegisterIF_S_AXI_RVALID, \
input \
    logic  axi4LitePlToPsControlRegisterIF_S_AXI_RREADY, \
    logic axi4LitePsToPlControlRegisterIF_S_AXI_ACLK, \
    logic axi4LitePsToPlControlRegisterIF_S_AXI_ARESETN, \
    logic [PS_PL_CTRL_REG_ADDR_BIT_SIZE-1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_AWADDR, \
    logic [2 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_AWPROT, \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_AWVALID, \
output \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_AWREADY, \
input \
    logic [PS_PL_CTRL_REG_DATA_BIT_SIZE-1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_WDATA, \
    logic [(PS_PL_CTRL_REG_DATA_BIT_SIZE/8)-1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_WSTRB, \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_WVALID, \
output \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_WREADY, \
    logic [1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_BRESP, \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_BVALID, \
input \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_BREADY, \
    logic [PS_PL_CTRL_REG_ADDR_BIT_SIZE-1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_ARADDR, \
    logic [2 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_ARPROT, \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_ARVALID, \
output \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_ARREADY, \
    logic [PS_PL_CTRL_REG_DATA_BIT_SIZE-1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_RDATA, \
    logic [1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_RRESP, \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_RVALID, \
input \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_RREADY

`define CONNECT_CONTROL_REGISTER_IF \
    axi4LitePlToPsControlRegisterIF.S_AXI_ACLK = axi4LitePlToPsControlRegisterIF_S_AXI_ACLK; \
    axi4LitePlToPsControlRegisterIF.S_AXI_ARESETN = axi4LitePlToPsControlRegisterIF_S_AXI_ARESETN; \
    axi4LitePlToPsControlRegisterIF.S_AXI_ARADDR = axi4LitePlToPsControlRegisterIF_S_AXI_ARADDR; \
    axi4LitePlToPsControlRegisterIF.S_AXI_ARPROT = axi4LitePlToPsControlRegisterIF_S_AXI_ARPROT; \
    axi4LitePlToPsControlRegisterIF.S_AXI_ARVALID = axi4LitePlToPsControlRegisterIF_S_AXI_ARVALID; \
    axi4LitePlToPsControlRegisterIF_S_AXI_ARREADY = axi4LitePlToPsControlRegisterIF.S_AXI_ARREADY; \
    axi4LitePlToPsControlRegisterIF_S_AXI_RDATA = axi4LitePlToPsControlRegisterIF.S_AXI_RDATA; \
    axi4LitePlToPsControlRegisterIF_S_AXI_RRESP = axi4LitePlToPsControlRegisterIF.S_AXI_RRESP; \
    axi4LitePlToPsControlRegisterIF_S_AXI_RVALID = axi4LitePlToPsControlRegisterIF.S_AXI_RVALID; \
    axi4LitePlToPsControlRegisterIF.S_AXI_RREADY = axi4LitePlToPsControlRegisterIF_S_AXI_RREADY; \
    axi4LitePsToPlControlRegisterIF.S_AXI_ACLK = axi4LitePsToPlControlRegisterIF_S_AXI_ACLK; \
    axi4LitePsToPlControlRegisterIF.S_AXI_ARESETN = axi4LitePsToPlControlRegisterIF_S_AXI_ARESETN; \
    axi4LitePsToPlControlRegisterIF.S_AXI_AWADDR = axi4LitePsToPlControlRegisterIF_S_AXI_AWADDR; \
    axi4LitePsToPlControlRegisterIF.S_AXI_AWPROT = axi4LitePsToPlControlRegisterIF_S_AXI_AWPROT; \
    axi4LitePsToPlControlRegisterIF.S_AXI_AWVALID = axi4LitePsToPlControlRegisterIF_S_AXI_AWVALID; \
    axi4LitePsToPlControlRegisterIF_S_AXI_AWREADY = axi4LitePsToPlControlRegisterIF.S_AXI_AWREADY; \
    axi4LitePsToPlControlRegisterIF.S_AXI_WDATA = axi4LitePsToPlControlRegisterIF_S_AXI_WDATA; \
    axi4LitePsToPlControlRegisterIF.S_AXI_WSTRB = axi4LitePsToPlControlRegisterIF_S_AXI_WSTRB; \
    axi4LitePsToPlControlRegisterIF.S_AXI_WVALID = axi4LitePsToPlControlRegisterIF_S_AXI_WVALID; \
    axi4LitePsToPlControlRegisterIF_S_AXI_WREADY = axi4LitePsToPlControlRegisterIF.S_AXI_WREADY; \
    axi4LitePsToPlControlRegisterIF_S_AXI_BRESP = axi4LitePsToPlControlRegisterIF.S_AXI_BRESP; \
    axi4LitePsToPlControlRegisterIF_S_AXI_BVALID = axi4LitePsToPlControlRegisterIF.S_AXI_BVALID; \
    axi4LitePsToPlControlRegisterIF.S_AXI_BREADY = axi4LitePsToPlControlRegisterIF_S_AXI_BREADY; \
    axi4LitePsToPlControlRegisterIF.S_AXI_ARADDR = axi4LitePsToPlControlRegisterIF_S_AXI_ARADDR; \
    axi4LitePsToPlControlRegisterIF.S_AXI_ARPROT = axi4LitePsToPlControlRegisterIF_S_AXI_ARPROT; \
    axi4LitePsToPlControlRegisterIF.S_AXI_ARVALID = axi4LitePsToPlControlRegisterIF_S_AXI_ARVALID; \
    axi4LitePsToPlControlRegisterIF_S_AXI_ARREADY = axi4LitePsToPlControlRegisterIF.S_AXI_ARREADY; \
    axi4LitePsToPlControlRegisterIF_S_AXI_RDATA = axi4LitePsToPlControlRegisterIF.S_AXI_RDATA; \
    axi4LitePsToPlControlRegisterIF_S_AXI_RRESP = axi4LitePsToPlControlRegisterIF.S_AXI_RRESP; \
    axi4LitePsToPlControlRegisterIF_S_AXI_RVALID = axi4LitePsToPlControlRegisterIF.S_AXI_RVALID; \
    axi4LitePsToPlControlRegisterIF.S_AXI_RREADY = axi4LitePsToPlControlRegisterIF_S_AXI_RREADY;
