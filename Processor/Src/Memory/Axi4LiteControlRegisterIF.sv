// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Axi4LiteControlRegisterIF
//

`include "SysDeps/XilinxMacros.vh"

import BasicTypes::*;
import MemoryTypes::*;

interface Axi4LiteControlRegisterIF;

    // Global Clock Signal
    logic S_AXI_ACLK;
    // Global Reset Signal. This Signal is Active LOW
    logic S_AXI_ARESETN;
    // Write address (issued by master, acceped by Slave)
    logic [`PS_PL_CTRL_REG_ADDR_BIT_SIZE-1 : 0] S_AXI_AWADDR;
    // Write channel Protection type. This signal indicates the
        // privilege and security level of the transaction, and whether
        // the transaction is a data access or an instruction access.
    logic [`PS_PL_CTRL_REG_AWPROT_WIDTH-1 : 0] S_AXI_AWPROT;
    // Write address valid. This signal indicates that the master signaling
        // valid write address and control information.
    logic  S_AXI_AWVALID;
    // Write address ready. This signal indicates that the slave is ready
        // to accept an address and associated control signals.
    logic  S_AXI_AWREADY;
    // Write data (issued by master, acceped by Slave) 
    logic [`PS_PL_CTRL_REG_DATA_BIT_SIZE-1 : 0] S_AXI_WDATA;
    // Write strobes. This signal indicates which byte lanes hold
        // valid data. There is one write strobe bit for each eight
        // bits of the write data bus.    
    logic [`PS_PL_CTRL_REG_WSTRB_WIDTH-1 : 0] S_AXI_WSTRB;
    // Write valid. This signal indicates that valid write
        // data and strobes are available.
    logic  S_AXI_WVALID;
    // Write ready. This signal indicates that the slave
        // can accept the write data.
    logic  S_AXI_WREADY;
    // Write response. This signal indicates the status
        // of the write transaction.
    logic [`PS_PL_CTRL_REG_BRESP_WIDTH-1 : 0] S_AXI_BRESP;
    // Write response valid. This signal indicates that the channel
        // is signaling a valid write response.
    logic  S_AXI_BVALID;
    // Response ready. This signal indicates that the master
        // can accept a write response.
    logic  S_AXI_BREADY;
    // Read address (issued by master, acceped by Slave)
    logic [`PS_PL_CTRL_REG_ADDR_BIT_SIZE-1 : 0] S_AXI_ARADDR;
    // Protection type. This signal indicates the privilege
        // and security level of the transaction, and whether the
        // transaction is a data access or an instruction access.
    logic [`PS_PL_CTRL_REG_ARPROT_WIDTH-1 : 0] S_AXI_ARPROT;
    // Read address valid. This signal indicates that the channel
        // is signaling valid read address and control information.
    logic  S_AXI_ARVALID;
    // Read address ready. This signal indicates that the slave is
        // ready to accept an address and associated control signals.
    logic  S_AXI_ARREADY;
    // Read data (issued by slave)
    logic [`PS_PL_CTRL_REG_DATA_BIT_SIZE-1 : 0] S_AXI_RDATA;
    // Read response. This signal indicates the status of the
        // read transfer.
    logic [`PS_PL_CTRL_REG_RRESP_WIDTH-1 : 0] S_AXI_RRESP;
    // Read valid. This signal indicates that the channel is
        // signaling the required read data.
    logic  S_AXI_RVALID;
    // Read ready. This signal indicates that the master can
        // accept the read data and response information.
    logic  S_AXI_RREADY;

    modport Axi4Lite(
    input
        S_AXI_ACLK,
        S_AXI_ARESETN,
        S_AXI_AWADDR,
        S_AXI_AWPROT,
        S_AXI_AWVALID,
    output
        S_AXI_AWREADY,
    input
        S_AXI_WDATA,
        S_AXI_WSTRB,
        S_AXI_WVALID,
    output
        S_AXI_WREADY,
        S_AXI_BRESP,
        S_AXI_BVALID,
    input
        S_AXI_BREADY,
        S_AXI_ARADDR,
        S_AXI_ARPROT,
        S_AXI_ARVALID,
    output
        S_AXI_ARREADY,
        S_AXI_RDATA,
        S_AXI_RRESP,
        S_AXI_RVALID,
    input
        S_AXI_RREADY
    );

    modport Axi4LiteWrite(
    input
        S_AXI_ACLK,
        S_AXI_ARESETN,
        S_AXI_AWADDR,
        S_AXI_AWPROT,
        S_AXI_AWVALID,
    output
        S_AXI_AWREADY,
    input
        S_AXI_WDATA,
        S_AXI_WSTRB,
        S_AXI_WVALID,
    output
        S_AXI_WREADY,
        S_AXI_BRESP,
        S_AXI_BVALID,
    input
        S_AXI_BREADY
    );

    modport Axi4LiteRead(
    input
        S_AXI_ACLK,
        S_AXI_ARESETN,
        S_AXI_ARADDR,
        S_AXI_ARPROT,
        S_AXI_ARVALID,
    output
        S_AXI_ARREADY,
        S_AXI_RDATA,
        S_AXI_RRESP,
        S_AXI_RVALID,
    input
        S_AXI_RREADY
    );

endinterface : Axi4LiteControlRegisterIF

