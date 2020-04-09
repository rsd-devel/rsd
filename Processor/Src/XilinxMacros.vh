
//
// RSDがAXI4を用いてメモリアクセスする場合のAXI4バスのパラメータ
//

// RSDのメモリ空間とPS(ARM)のメモリ空間のオフセット
// PS(ARM)のプロセスはここで指定したアドレス以降の空間をRSDとの明示的データ共有以外の目的で使用してはいけない．

`define MEMORY_AXI4_BASE_ADDR 32'h10000000
// AXI4バスのデータ幅
`define MEMORY_AXI4_DATA_BIT_NUM 64

`define MEMORY_AXI4_BURST_LEN (MEMORY_ENTRY_BIT_NUM/`MEMORY_AXI4_DATA_BIT_NUM)
`define MEMORY_AXI4_BURST_BIT_NUM $clog2(`MEMORY_AXI4_BURST_LEN)

`define MEMORY_AXI4_READ_ID_WIDTH 2
`define MEMORY_AXI4_READ_ID_NUM (1<<`MEMORY_AXI4_READ_ID_WIDTH)

`define MEMORY_AXI4_WRITE_ID_WIDTH 1
`define MEMORY_AXI4_WRITE_ID_NUM (1<<`MEMORY_AXI4_WRITE_ID_WIDTH)

`define MEMORY_AXI4_ADDR_BIT_SIZE 32

// *USERはすべて未使用のため，専用線は削除
`define MEMORY_AXI4_AWUSER_WIDTH 0
`define MEMORY_AXI4_ARUSER_WIDTH 0
`define MEMORY_AXI4_WUSER_WIDTH 0
`define MEMORY_AXI4_RUSER_WIDTH 0
`define MEMORY_AXI4_BUSER_WIDTH 0

// Axi4Memory
`define MEMORY_AXI4_ADDR_BIT_SIZE 32
`define MEMORY_AXI4_AWLEN_WIDTH 8
`define MEMORY_AXI4_AWSIZE_WIDTH 3
`define MEMORY_AXI4_AWBURST_WIDTH 2
`define MEMORY_AXI4_AWCACHE_WIDTH 4
`define MEMORY_AXI4_AWPROT_WIDTH 3
`define MEMORY_AXI4_AWQOS_WIDTH 2

`define MEMORY_AXI4_BRESP_WIDTH 2
`define MEMORY_AXI4_ARLEN_WIDTH 8
`define MEMORY_AXI4_ARSIZE_WIDTH 3
`define MEMORY_AXI4_ARBURST_WIDTH 2
`define MEMORY_AXI4_ARCACHE_WIDTH 4
`define MEMORY_AXI4_ARPROT_WIDTH 3
`define MEMORY_AXI4_ARQOS_WIDTH 4
`define MEMORY_AXI4_RRESP_WIDTH 2

// Axi4LiteControlRegister


// PS-PL Memoryサイズ
`define PS_PL_MEMORY_DATA_BIT_SIZE 32
`define PS_PL_MEMORY_ADDR_BIT_SIZE 11
`define PS_PL_MEMORY_ADDR_LSB (`PS_PL_MEMORY_DATA_BIT_SIZE/32)+1 // 32-bit: 2, 64-bit: 3
`define PS_PL_MEMORY_SIZE 1<<(`PS_PL_MEMORY_ADDR_BIT_SIZE-`PS_PL_MEMORY_ADDR_LSB) // 512

// PS-PL ControlRegister
`define PS_PL_CTRL_REG_DATA_BIT_SIZE 32
`define PS_PL_CTRL_REG_ADDR_BIT_SIZE 7
`define PS_PL_CTRL_REG_ADDR_LSB (`PS_PL_CTRL_REG_DATA_BIT_SIZE/32)+1 // 32-bit: 2, 64-bit: 3
`define PS_PL_CTRL_REG_SIZE (1<<(`PS_PL_CTRL_REG_ADDR_BIT_SIZE-`PS_PL_CTRL_REG_ADDR_LSB)) // 32

`define PS_PL_CTRL_REG_AWPROT_WIDTH 3
`define PS_PL_CTRL_REG_BRESP_WIDTH 2
`define PS_PL_CTRL_REG_ARPROT_WIDTH 3
`define PS_PL_CTRL_REG_RRESP_WIDTH 2

// PS-PL ControlQueue
`define PS_PL_CTRL_QUEUE_DATA_BIT_SIZE `PS_PL_CTRL_REG_DATA_BIT_SIZE
`define PS_PL_CTRL_QUEUE_ADDR_BIT_SIZE 6
`define PS_PL_CTRL_QUEUE_SIZE 1<<`PS_PL_CTRL_QUEUE_ADDR_BIT_SIZE // 64


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
    logic [`MEMORY_AXI4_WRITE_ID_WIDTH-1 : 0] axi4MemoryIF_M_AXI_AWID, \
    logic [`MEMORY_AXI4_ADDR_BIT_SIZE-1 : 0] axi4MemoryIF_M_AXI_AWADDR, \
    logic [`MEMORY_AXI4_AWLEN_WIDTH-1 : 0] axi4MemoryIF_M_AXI_AWLEN, \
    logic [`MEMORY_AXI4_AWSIZE_WIDTH-1 : 0] axi4MemoryIF_M_AXI_AWSIZE, \
    logic [`MEMORY_AXI4_AWBURST_WIDTH-1 : 0] axi4MemoryIF_M_AXI_AWBURST, \
    logic  axi4MemoryIF_M_AXI_AWLOCK, \
    logic [`MEMORY_AXI4_AWCACHE_WIDTH-1 : 0] axi4MemoryIF_M_AXI_AWCACHE, \
    logic [`MEMORY_AXI4_AWPROT_WIDTH-1 : 0] axi4MemoryIF_M_AXI_AWPROT, \
    logic [`MEMORY_AXI4_AWQOS_WIDTH-1 : 0] axi4MemoryIF_M_AXI_AWQOS, \
    logic [`MEMORY_AXI4_AWUSER_WIDTH-1 : 0] axi4MemoryIF_M_AXI_AWUSER, \
    logic  axi4MemoryIF_M_AXI_AWVALID, \
input \
    logic  axi4MemoryIF_M_AXI_AWREADY, \
output \
    logic [`MEMORY_AXI4_DATA_BIT_NUM-1 : 0] axi4MemoryIF_M_AXI_WDATA, \
    logic [`MEMORY_AXI4_DATA_BIT_NUM/8-1 : 0] axi4MemoryIF_M_AXI_WSTRB, \
    logic  axi4MemoryIF_M_AXI_WLAST, \
    logic [`MEMORY_AXI4_WUSER_WIDTH-1 : 0] axi4MemoryIF_M_AXI_WUSER, \
    logic  axi4MemoryIF_M_AXI_WVALID, \
input \
    logic  axi4MemoryIF_M_AXI_WREADY, \
    logic [`MEMORY_AXI4_WRITE_ID_WIDTH-1 : 0] axi4MemoryIF_M_AXI_BID, \
    logic [`MEMORY_AXI4_BRESP_WIDTH-1 : 0] axi4MemoryIF_M_AXI_BRESP, \
    logic [`MEMORY_AXI4_BUSER_WIDTH-1 : 0] axi4MemoryIF_M_AXI_BUSER, \
    logic  axi4MemoryIF_M_AXI_BVALID, \
output \
    logic  axi4MemoryIF_M_AXI_BREADY, \
    logic [`MEMORY_AXI4_READ_ID_WIDTH-1 : 0] axi4MemoryIF_M_AXI_ARID, \
    logic [`MEMORY_AXI4_ADDR_BIT_SIZE-1 : 0] axi4MemoryIF_M_AXI_ARADDR, \
    logic [`MEMORY_AXI4_ARLEN_WIDTH-1 : 0] axi4MemoryIF_M_AXI_ARLEN, \
    logic [`MEMORY_AXI4_ARSIZE_WIDTH-1 : 0] axi4MemoryIF_M_AXI_ARSIZE, \
    logic [`MEMORY_AXI4_ARBURST_WIDTH-1 : 0] axi4MemoryIF_M_AXI_ARBURST, \
    logic  axi4MemoryIF_M_AXI_ARLOCK, \
    logic [`MEMORY_AXI4_ARCACHE_WIDTH-1 : 0] axi4MemoryIF_M_AXI_ARCACHE, \
    logic [`MEMORY_AXI4_ARPROT_WIDTH-1 : 0] axi4MemoryIF_M_AXI_ARPROT, \
    logic [`MEMORY_AXI4_ARQOS_WIDTH-1 : 0] axi4MemoryIF_M_AXI_ARQOS, \
    logic [`MEMORY_AXI4_ARUSER_WIDTH-1 : 0] axi4MemoryIF_M_AXI_ARUSER, \
    logic  axi4MemoryIF_M_AXI_ARVALID, \
input \
    logic  axi4MemoryIF_M_AXI_ARREADY, \
    logic [`MEMORY_AXI4_READ_ID_WIDTH-1 : 0] axi4MemoryIF_M_AXI_RID, \
    logic [`MEMORY_AXI4_DATA_BIT_NUM-1 : 0] axi4MemoryIF_M_AXI_RDATA, \
    logic [`MEMORY_AXI4_RRESP_WIDTH-1 : 0] axi4MemoryIF_M_AXI_RRESP, \
    logic  axi4MemoryIF_M_AXI_RLAST, \
    logic [`MEMORY_AXI4_RUSER_WIDTH-1 : 0] axi4MemoryIF_M_AXI_RUSER, \
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
    logic [`PS_PL_CTRL_REG_ADDR_BIT_SIZE-1 : 0] axi4LitePlToPsControlRegisterIF_S_AXI_ARADDR, \
    logic [`PS_PL_CTRL_REG_AWPROT_WIDTH-1 : 0] axi4LitePlToPsControlRegisterIF_S_AXI_ARPROT, \
    logic  axi4LitePlToPsControlRegisterIF_S_AXI_ARVALID, \
output \
    logic  axi4LitePlToPsControlRegisterIF_S_AXI_ARREADY, \
    logic [`PS_PL_CTRL_REG_DATA_BIT_SIZE-1 : 0] axi4LitePlToPsControlRegisterIF_S_AXI_RDATA, \
    logic [`PS_PL_CTRL_REG_RRESP_WIDTH-1 : 0] axi4LitePlToPsControlRegisterIF_S_AXI_RRESP, \
    logic  axi4LitePlToPsControlRegisterIF_S_AXI_RVALID, \
input \
    logic  axi4LitePlToPsControlRegisterIF_S_AXI_RREADY, \
    logic axi4LitePsToPlControlRegisterIF_S_AXI_ACLK, \
    logic axi4LitePsToPlControlRegisterIF_S_AXI_ARESETN, \
    logic [`PS_PL_CTRL_REG_ADDR_BIT_SIZE-1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_AWADDR, \
    logic [`PS_PL_CTRL_REG_AWPROT_WIDTH-1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_AWPROT, \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_AWVALID, \
output \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_AWREADY, \
input \
    logic [`PS_PL_CTRL_REG_DATA_BIT_SIZE-1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_WDATA, \
    logic [(`PS_PL_CTRL_REG_DATA_BIT_SIZE/8)-1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_WSTRB, \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_WVALID, \
output \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_WREADY, \
    logic [`PS_PL_CTRL_REG_BRESP_WIDTH-1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_BRESP, \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_BVALID, \
input \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_BREADY, \
    logic [`PS_PL_CTRL_REG_ADDR_BIT_SIZE-1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_ARADDR, \
    logic [`PS_PL_CTRL_REG_ARPROT_WIDTH-1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_ARPROT, \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_ARVALID, \
output \
    logic  axi4LitePsToPlControlRegisterIF_S_AXI_ARREADY, \
    logic [`PS_PL_CTRL_REG_DATA_BIT_SIZE-1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_RDATA, \
    logic [`PS_PL_CTRL_REG_RRESP_WIDTH-1 : 0] axi4LitePsToPlControlRegisterIF_S_AXI_RRESP, \
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
