// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.



// `timescale 1 ns / 1 ps

import BasicTypes::*;
import MemoryTypes::*;

module Axi4LiteDualPortBlockRAM
(
    Axi4LiteControlMemoryIF.Axi4Lite port
);

    // AXI4LITE signals
    logic [PS_PL_MEMORY_ADDR_BIT_SIZE-1 : 0] axi_awaddr;
    logic axi_awready;
    logic axi_wready;
    logic [1 : 0] axi_bresp;
    logic axi_bvalid;
    logic [PS_PL_MEMORY_ADDR_BIT_SIZE-1 : 0] axi_araddr;
    logic axi_arready;
    logic [DATA_WIDTH-1 : 0] axi_rdata;
    logic [1 : 0] axi_rresp;
    logic axi_rvalid;
    logic axi_reading;


    // Example-specific design signals
    // local parameter for addressing 32 bit / 64 bit DATA_WIDTH
    // PS_PL_MEMORY_ADDR_LSB is used for addressing 32/64 bit registers/memories
    // PS_PL_MEMORY_ADDR_LSB = 2 for 32 bits (n downto 2)
    // PS_PL_MEMORY_ADDR_LSB = 3 for 64 bits (n downto 3)
    // localparam integer PS_PL_MEMORY_ADDR_LSB = (DATA_WIDTH/32) + 1;
    // localparam integer OPT_MEM_ADDR_BITS = 4;
    logic slv_reg_rden;
    logic slv_reg_wren;
    logic [DATA_WIDTH-1:0] reg_data_out;
    logic aw_en;

    // I/O Connections assignments

    assign port.S_AXI_AWREADY = axi_awready;
    assign port.S_AXI_WREADY  = axi_wready;
    assign port.S_AXI_BRESP      = axi_bresp;
    assign port.S_AXI_BVALID  = axi_bvalid;
    assign port.S_AXI_ARREADY = axi_arready;
    assign port.S_AXI_RDATA      = axi_rdata;
    assign port.S_AXI_RRESP      = axi_rresp;
    assign port.S_AXI_RVALID  = axi_rvalid;
    // Implement axi_awready generation
    // axi_awready is asserted for one port.S_AXI_ACLK clock cycle when both
    // port.S_AXI_AWVALID and port.S_AXI_WVALID are asserted. axi_awready is
    // de-asserted when reset is low.

    always_ff @( posedge port.S_AXI_ACLK )
    begin
      if ( port.S_AXI_ARESETN == 1'b0 )
        begin
          axi_awready <= 1'b0;
          aw_en <= 1'b1;
        end 
      else
        begin    
          if (~axi_awready && port.S_AXI_AWVALID && port.S_AXI_WVALID && aw_en)
            begin
              // slave is ready to accept write address when 
              // there is a valid write address and write data
              // on the write address and data bus. This design 
              // expects no outstanding transactions. 
              axi_awready <= 1'b1;
              aw_en <= 1'b0;
            end
            else if (port.S_AXI_BREADY && axi_bvalid)
                begin
                  aw_en <= 1'b1;
                  axi_awready <= 1'b0;
                end
          else           
            begin
              axi_awready <= 1'b0;
            end
        end 
    end       

    // Implement axi_awaddr latching
    // This process is used to latch the address when both 
    // port.S_AXI_AWVALID and port.S_AXI_WVALID are valid. 

    always_ff @( posedge port.S_AXI_ACLK )
    begin
      if ( port.S_AXI_ARESETN == 1'b0 )
        begin
          axi_awaddr <= 0;
        end 
      else
        begin    
          if (~axi_awready && port.S_AXI_AWVALID && port.S_AXI_WVALID && aw_en)
            begin
              // Write Address latching 
              axi_awaddr <= port.S_AXI_AWADDR;
            end
        end 
    end       

    // Implement axi_wready generation
    // axi_wready is asserted for one port.S_AXI_ACLK clock cycle when both
    // port.S_AXI_AWVALID and port.S_AXI_WVALID are asserted. axi_wready is 
    // de-asserted when reset is low. 

    always_ff @( posedge port.S_AXI_ACLK )
    begin
      if ( port.S_AXI_ARESETN == 1'b0 )
        begin
          axi_wready <= 1'b0;
        end 
      else
        begin    
          if (~axi_wready && port.S_AXI_WVALID && port.S_AXI_AWVALID && aw_en )
            begin
              // slave is ready to accept write data when 
              // there is a valid write address and write data
              // on the write address and data bus. This design 
              // expects no outstanding transactions. 
              axi_wready <= 1'b1;
            end
          else
            begin
              axi_wready <= 1'b0;
            end
        end 
    end       

    // Implement memory mapped register select and write logic generation
    // The write data is accepted and written to memory mapped registers when
    // axi_awready, port.S_AXI_WVALID, axi_wready and port.S_AXI_WVALID are asserted. Write strobes are used to
    // select byte enables of slave registers while writing.
    // These registers are cleared when reset (active low) is applied.
    // Slave register write enable is asserted when valid address and data are available
    // and the slave is ready to accept the write address and write data.
    assign slv_reg_wren = axi_wready && port.S_AXI_WVALID && axi_awready && port.S_AXI_AWVALID;


    // Implement write response logic generation
    // The write response and response valid signals are asserted by the slave 
    // when axi_wready, port.S_AXI_WVALID, axi_wready and port.S_AXI_WVALID are asserted.  
    // This marks the acceptance of address and indicates the status of 
    // write transaction.

    always_ff @( posedge port.S_AXI_ACLK )
    begin
      if ( port.S_AXI_ARESETN == 1'b0 )
        begin
          axi_bvalid  <= 0;
          axi_bresp   <= 2'b0;
        end 
      else
        begin    
          if (axi_awready && port.S_AXI_AWVALID && ~axi_bvalid && axi_wready && port.S_AXI_WVALID)
            begin
              // indicates a valid write response is available
              axi_bvalid <= 1'b1;
              axi_bresp  <= 2'b0; // 'OKAY' response 
            end                   // work error responses in future
          else
            begin
              if (port.S_AXI_BREADY && axi_bvalid) 
                //check if bready is asserted while bvalid is high) 
                //(there is a possibility that bready is always asserted high)   
                begin
                  axi_bvalid <= 1'b0; 
                end  
            end
        end
    end   

    // Implement axi_arready generation
    // axi_arready is asserted for one port.S_AXI_ACLK clock cycle when
    // port.S_AXI_ARVALID is asserted. axi_awready is 
    // de-asserted when reset (active low) is asserted. 
    // The read address is also latched when port.S_AXI_ARVALID is 
    // asserted. axi_araddr is reset to zero on reset assertion.

    always_ff @( posedge port.S_AXI_ACLK )
    begin
      if ( port.S_AXI_ARESETN == 1'b0 )
        begin
          axi_arready <= 1'b0;
          axi_araddr  <= 32'b0;
        end 
      else
        begin    
          if (~axi_arready && port.S_AXI_ARVALID)
            begin
              // indicates that the slave has acceped the valid read address
              axi_arready <= 1'b1;
              // Read address latching
              axi_araddr  <= port.S_AXI_ARADDR;
            end
          else
            begin
              axi_arready <= 1'b0;
            end
        end 
    end       

    // Implement axi_arvalid generation
    // axi_rvalid is asserted for one port.S_AXI_ACLK clock cycle when both 
    // port.S_AXI_ARVALID and axi_arready are asserted. The slave registers 
    // data are available on the axi_rdata bus at this instance. The 
    // assertion of axi_rvalid marks the validity of read data on the 
    // bus and axi_rresp indicates the status of read transaction.axi_rvalid 
    // is deasserted on reset (active low). axi_rresp and axi_rdata are 
    // cleared to zero on reset (active low). 

    
    always_ff @( posedge port.S_AXI_ACLK )
    begin
      if ( port.S_AXI_ARESETN == 1'b0 )
        begin
          axi_rvalid  <= 0;
          axi_rresp   <= 0;
          axi_reading <= 0;
        end 
      else
        begin    
          if (axi_arready && port.S_AXI_ARVALID && ~axi_rvalid && -axi_reading)
            begin
              // Valid read data is available at the read data bus
              //axi_rvalid <= 1'b1;
              axi_rresp   <= 2'b0; // 'OKAY' response
              axi_reading <= 1'b1;
            end   
          else if (axi_reading)
              begin
              axi_rvalid  <= 1'b1;
              axi_reading <= 1'b0;
            end
          else if (axi_rvalid && port.S_AXI_RREADY)
            begin
              // Read data is accepted by the master
              axi_rvalid <= 1'b0;
            end                
        end
    end    

    // Implement memory mapped register select and read logic generation
    // Slave register read enable is asserted when valid address is available
    // and the slave is ready to accept the read address.
    assign slv_reg_rden = axi_reading;

    // Output register or memory read data
    always_ff @( posedge port.S_AXI_ACLK )
    begin
      if ( port.S_AXI_ARESETN == 1'b0 )
        begin
          axi_rdata  <= 0;
        end 
      else
        begin    
          // When there is a valid read address (port.S_AXI_ARVALID) with 
          // acceptance of read address by the slave (axi_arready), 
          // output the read dada 
          if (slv_reg_rden)
            begin
              axi_rdata <= reg_data_out;     // register read data
            end   
        end
    end    

    BlockDualPortRAM #( 
        .INDEX_BIT_SIZE(PS_PL_MEMORY_SIZE), 
        .ENTRY_BIT_SIZE(DATA_WIDTH)
    ) ram ( 
        port.S_AXI_ACLK,
        slv_reg_wren,
        axi_awaddr[PS_PL_MEMORY_ADDR_BIT_SIZE-1:PS_PL_MEMORY_ADDR_LSB],
        port.S_AXI_WDATA,
        axi_araddr[PS_PL_MEMORY_ADDR_BIT_SIZE-1:PS_PL_MEMORY_ADDR_LSB],
        reg_data_out
    );

endmodule : Axi4LiteDualPortBlockRAM

