// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Axi4MemoryIF
//

`include "SysDeps/XilinxMacros.vh"

import BasicTypes::*;
import MemoryTypes::*;
import CacheSystemTypes::*;

interface Axi4MemoryIF;

    // // Initiate AXI transactions
    // input wire  INIT_AXI_TXN;
    // // Asserts when transaction is complete
    // output wire  TXN_DONE;
    // // Asserts when ERROR is detected
    // output reg  ERROR;
    // Global Clock Signal.
    logic  M_AXI_ACLK;
    // Global Reset Singal. This Signal is Active Low
    logic  M_AXI_ARESETN;
    // Master Interface Write Address ID
    logic [`MEMORY_AXI4_WRITE_ID_WIDTH-1 : 0] M_AXI_AWID;
    // Master Interface Write Address
    logic [`MEMORY_AXI4_ADDR_BIT_SIZE-1 : 0] M_AXI_AWADDR;
    // Burst length. The burst length gives the exact number of transfers in a burst
    logic [`MEMORY_AXI4_AWLEN_WIDTH-1 : 0] M_AXI_AWLEN;
    // Burst size. This signal indicates the size of each transfer in the burst
    logic [`MEMORY_AXI4_AWSIZE_WIDTH-1 : 0] M_AXI_AWSIZE;
    // Burst type. The burst type and the size information; 
    // determine how the address for each transfer within the burst is calculated.
    logic [`MEMORY_AXI4_AWBURST_WIDTH-1 : 0] M_AXI_AWBURST;
    // Lock type. Provides additional information about the
    // atomic characteristics of the transfer.
    logic  M_AXI_AWLOCK;
    // Memory type. This signal indicates how transactions
    // are required to progress through a system.
    logic [`MEMORY_AXI4_AWCACHE_WIDTH-1 : 0] M_AXI_AWCACHE;
    // Protection type. This signal indicates the privilege
    // and security level of the transaction; and whether
    // the transaction is a data access or an instruction access.
    logic [`MEMORY_AXI4_AWPROT_WIDTH-1 : 0] M_AXI_AWPROT;
    // Quality of Service; QoS identifier sent for each write transaction.
    logic [`MEMORY_AXI4_AWQOS_WIDTH-1 : 0] M_AXI_AWQOS;
    // Optional User-defined signal in the write address channel.
    logic [`MEMORY_AXI4_AWUSER_WIDTH-1 : 0] M_AXI_AWUSER;
    // Write address valid. This signal indicates that
    // the channel is signaling valid write address and control information.
    logic  M_AXI_AWVALID;
    // Write address ready. This signal indicates that
    // the slave is ready to accept an address and associated control signals
    logic  M_AXI_AWREADY;
    // Master Interface Write Data.
    logic [`MEMORY_AXI4_DATA_BIT_NUM-1 : 0] M_AXI_WDATA;
    // Write strobes. This signal indicates which byte
    // lanes hold valid data. There is one write strobe
    // bit for each eight bits of the write data bus.
    logic [`MEMORY_AXI4_WSTRB_WIDTH-1 : 0] M_AXI_WSTRB;
    // Write last. This signal indicates the last transfer in a write burst.
    logic  M_AXI_WLAST;
    // Optional User-defined signal in the write data channel.
    logic [`MEMORY_AXI4_WUSER_WIDTH-1 : 0] M_AXI_WUSER;
    // Write valid. This signal indicates that valid write
    // data and strobes are available
    logic  M_AXI_WVALID;
    // Write ready. This signal indicates that the slave
    // can accept the write data.
    logic  M_AXI_WREADY;
    // Master Interface Write Response.
    logic [`MEMORY_AXI4_WRITE_ID_WIDTH-1 : 0] M_AXI_BID;
    // Write response. This signal indicates the status of the write transaction.
    logic [`MEMORY_AXI4_BRESP_WIDTH-1 : 0] M_AXI_BRESP;
    // Optional User-defined signal in the write response channel
    logic [`MEMORY_AXI4_BUSER_WIDTH-1 : 0] M_AXI_BUSER;
    // Write response valid. This signal indicates that the
    // channel is signaling a valid write response.
    logic  M_AXI_BVALID;
    // Response ready. This signal indicates that the master
    // can accept a write response.
    logic  M_AXI_BREADY;
    // Master Interface Read Address.
    logic [`MEMORY_AXI4_READ_ID_WIDTH-1 : 0] M_AXI_ARID;
    // Read address. This signal indicates the initial
    // address of a read burst transaction.
    logic [`MEMORY_AXI4_ADDR_BIT_SIZE-1 : 0] M_AXI_ARADDR;
    // Burst length. The burst length gives the exact number of transfers in a burst
    logic [`MEMORY_AXI4_ARLEN_WIDTH-1 : 0] M_AXI_ARLEN;
    // Burst size. This signal indicates the size of each transfer in the burst
    logic [`MEMORY_AXI4_ARSIZE_WIDTH-1 : 0] M_AXI_ARSIZE;
    // Burst type. The burst type and the size information; 
    // determine how the address for each transfer within the burst is calculated.
    logic [`MEMORY_AXI4_ARBURST_WIDTH-1 : 0] M_AXI_ARBURST;
    // Lock type. Provides additional information about the
    // atomic characteristics of the transfer.
    logic  M_AXI_ARLOCK;
    // Memory type. This signal indicates how transactions
    // are required to progress through a system.
    logic [`MEMORY_AXI4_ARCACHE_WIDTH-1 : 0] M_AXI_ARCACHE;
    // Protection type. This signal indicates the privilege
    // and security level of the transaction; and whether
    // the transaction is a data access or an instruction access.
    logic [`MEMORY_AXI4_ARPROT_WIDTH-1 : 0] M_AXI_ARPROT;
    // Quality of Service; QoS identifier sent for each read transaction
    logic [`MEMORY_AXI4_ARQOS_WIDTH-1 : 0] M_AXI_ARQOS;
    // Optional User-defined signal in the read address channel.
    logic [`MEMORY_AXI4_ARUSER_WIDTH-1 : 0] M_AXI_ARUSER;
    // Write address valid. This signal indicates that
    // the channel is signaling valid read address and control information
    logic  M_AXI_ARVALID;
    // Read address ready. This signal indicates that
    // the slave is ready to accept an address and associated control signals
    logic  M_AXI_ARREADY;
    // Read ID tag. This signal is the identification tag
    // for the read data group of signals generated by the slave.
    logic [`MEMORY_AXI4_READ_ID_WIDTH-1 : 0] M_AXI_RID;
    // Master Read Data
    logic [`MEMORY_AXI4_DATA_BIT_NUM-1 : 0] M_AXI_RDATA;
    // Read response. This signal indicates the status of the read transfer
    logic [`MEMORY_AXI4_RRESP_WIDTH-1 : 0] M_AXI_RRESP;
    // Read last. This signal indicates the last transfer in a read burst
    logic  M_AXI_RLAST;
    // Optional User-defined signal in the read address channel.
    logic [`MEMORY_AXI4_RUSER_WIDTH-1 : 0] M_AXI_RUSER;
    // Read valid. This signal indicates that the channel
    // is signaling the required read data.
    logic  M_AXI_RVALID;
    // Read ready. This signal indicates that the master can
    // accept the read data and response information.
    logic  M_AXI_RREADY;

    modport Axi4(
    input 
        M_AXI_ACLK,
        M_AXI_ARESETN,
    output
        M_AXI_AWID,
        M_AXI_AWADDR,
        M_AXI_AWLEN,
        M_AXI_AWSIZE,
        M_AXI_AWBURST,
        M_AXI_AWLOCK,
        M_AXI_AWCACHE,
        M_AXI_AWPROT,
        M_AXI_AWQOS,
        M_AXI_AWUSER,
        M_AXI_AWVALID,
    input
        M_AXI_AWREADY,
    output
        M_AXI_WDATA,
        M_AXI_WSTRB,
        M_AXI_WLAST,
        M_AXI_WUSER,
        M_AXI_WVALID,
    input
        M_AXI_WREADY,
        M_AXI_BID,
        M_AXI_BRESP,
        M_AXI_BUSER,
        M_AXI_BVALID,
    output
        M_AXI_BREADY,
        M_AXI_ARID,
        M_AXI_ARADDR,
        M_AXI_ARLEN,
        M_AXI_ARSIZE,
        M_AXI_ARBURST,
        M_AXI_ARLOCK,
        M_AXI_ARCACHE,
        M_AXI_ARPROT,
        M_AXI_ARQOS,
        M_AXI_ARUSER,
        M_AXI_ARVALID,
    input
        M_AXI_ARREADY,
        M_AXI_RID,
        M_AXI_RDATA,
        M_AXI_RRESP,
        M_AXI_RLAST,
        M_AXI_RUSER,
        M_AXI_RVALID,
    output
        M_AXI_RREADY
    );

    modport Axi4Write(
    input 
        M_AXI_ACLK,
        M_AXI_ARESETN,
    output
        M_AXI_AWID,
        M_AXI_AWADDR,
        M_AXI_AWLEN,
        M_AXI_AWSIZE,
        M_AXI_AWBURST,
        M_AXI_AWLOCK,
        M_AXI_AWCACHE,
        M_AXI_AWPROT,
        M_AXI_AWQOS,
        M_AXI_AWUSER,
        M_AXI_AWVALID,
    input
        M_AXI_AWREADY,
    output
        M_AXI_WDATA,
        M_AXI_WSTRB,
        M_AXI_WLAST,
        M_AXI_WUSER,
        M_AXI_WVALID,
    input
        M_AXI_WREADY,
        M_AXI_BID,
        M_AXI_BRESP,
        M_AXI_BUSER,
        M_AXI_BVALID,
    output
        M_AXI_BREADY
    );

    modport Axi4Read(
    input 
        M_AXI_ACLK,
        M_AXI_ARESETN,
    output
        M_AXI_ARID,
        M_AXI_ARADDR,
        M_AXI_ARLEN,
        M_AXI_ARSIZE,
        M_AXI_ARBURST,
        M_AXI_ARLOCK,
        M_AXI_ARCACHE,
        M_AXI_ARPROT,
        M_AXI_ARQOS,
        M_AXI_ARUSER,
        M_AXI_ARVALID,
    input
        M_AXI_ARREADY,
        M_AXI_RID,
        M_AXI_RDATA,
        M_AXI_RRESP,
        M_AXI_RLAST,
        M_AXI_RUSER,
        M_AXI_RVALID,
    output
        M_AXI_RREADY
    );

endinterface : Axi4MemoryIF

