// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.



// `timescale 1 ns / 1 ps

`include "BasicMacros.sv"
`include "SysDeps/XilinxMacros.vh"

import BasicTypes::*;
import MemoryTypes::*;
import CacheSystemTypes::*;

module Axi4Memory
(
Axi4MemoryIF.Axi4 port,
input
    AddrPath memAccessAddr,
    MemoryEntryDataPath memAccessWriteData,
    logic memAccessRE,
    logic memAccessWE,
output
    logic memAccessReadBusy,    // メモリリードアクセス要求を受け付けられない
    logic memAccessWriteBusy,    // メモリライトアクセス要求を受け付けられない
    MemAccessSerial nextMemReadSerial, // RSDの次の読み出し要求に割り当てられるシリアル(id)
    MemWriteSerial nextMemWriteSerial, // RSDの次の書き込み要求に割り当てられるシリアル(id)
    logic memReadDataReady, // TRUEなら、メモリの読出しデータあり
    MemoryEntryDataPath memReadData, // メモリの読出しデータ
    MemAccessSerial memReadSerial, // メモリの読み出しデータのシリアル
    MemAccessResponse memAccessResponse // メモリ書き込み完了通知
);

    // RD/WR addr must be buffered for the correct operation.
    logic [`MEMORY_AXI4_ADDR_BIT_SIZE-1:0] next_addr;

    always_ff @(posedge port.M_AXI_ACLK) begin
        if (port.M_AXI_ARESETN == 0) begin
            next_addr <= '0;
        end
        else begin
            next_addr <= memAccessAddr[`MEMORY_AXI4_ADDR_BIT_SIZE-1:0];
        end
    end

    // function called clogb2 that returns an integer which has the
    //value of the ceiling of the log base 2

      // function called clogb2 that returns an integer which has the 
      // value of the ceiling of the log base 2.                      
      function automatic integer clogb2 (input integer bit_depth);              
      begin                                                           
        for(clogb2=0; bit_depth>0; clogb2=clogb2+1)                   
          bit_depth = bit_depth >> 1;                                 
        end                                                           
      endfunction                                                     

    // The burst length of AXI4
    // RSDのメモリアクセス単位はキャッシュライン幅単位なので，それをAXI4バスのデータ幅で割った数
    localparam MEMORY_AXI4_BURST_LEN = MEMORY_ENTRY_BIT_NUM/`MEMORY_AXI4_DATA_BIT_NUM;

    // C_TRANSACTIONS_NUM is the width of the index counter for 
    // number of write or read transaction.
     localparam integer C_TRANSACTIONS_NUM = clogb2(MEMORY_AXI4_BURST_LEN-1);

    // Burst length for transactions, in `MEMORY_AXI4_DATA_BIT_NUMs.
    // Non-2^n lengths will eventually cause bursts across 4K address boundaries.
     localparam integer C_MASTER_LENGTH    = 12;
    // total number of burst transfers is master length divided by burst length and burst size
     localparam integer C_NO_BURSTS_REQ = C_MASTER_LENGTH-clogb2((MEMORY_AXI4_BURST_LEN * `MEMORY_AXI4_DATA_BIT_NUM /8)-1);
    // Example State machine to initialize counter, initialize write transactions, 
    // initialize read transactions and comparison of read data with the 
    // written data words.
    parameter [1:0] IDLE = 2'b00, // This state initiates AXI4Lite transaction 
            // after the state machine changes state to INIT_WRITE 
            // when there is 0 to 1 transition on INIT_AXI_TXN
        INIT_WRITE   = 2'b01, // This state initializes write transaction,
            // once writes are done, the state machine 
            // changes state to INIT_READ 
        INIT_READ = 2'b10, // This state initializes read transaction
            // once reads are done, the state machine 
            // changes state to INIT_COMPARE 
        INIT_COMPARE = 2'b11; // This state issues the status of comparison 
            // of the written data with the read data    

     reg [1:0] mst_exec_state;

    // AXI4LITE signals
    //AXI4 internal temp signals
    // reg [`MEMORY_AXI4_ADDR_BIT_SIZE-1 : 0]     axi_awaddr;
    logic [`MEMORY_AXI4_ADDR_BIT_SIZE-1 : 0]     axi_awaddr;
    // reg      axi_awvalid;
    logic axi_awvalid;
    //reg [`MEMORY_AXI4_DATA_BIT_NUM-1 : 0]     axi_wdata;
    logic [`MEMORY_AXI4_DATA_BIT_NUM-1 : 0]     axi_wdata;
    reg      axi_wlast;
    reg      axi_wvalid;
    reg      axi_bready;
    //reg [`MEMORY_AXI4_ADDR_BIT_SIZE-1 : 0]     axi_araddr;
    logic [`MEMORY_AXI4_ADDR_BIT_SIZE-1 : 0]     axi_araddr;
    reg      axi_arvalid;
    reg      axi_rready;
    //write beat count in a burst
    reg [C_TRANSACTIONS_NUM : 0]     write_index;
    //read beat count in a burst
    reg [C_TRANSACTIONS_NUM : 0]     read_index;
    //size of MEMORY_AXI4_BURST_LEN length burst in bytes
    wire [C_TRANSACTIONS_NUM+2 : 0]     burst_size_bytes;
    //The burst counters are used to track the number of burst transfers of MEMORY_AXI4_BURST_LEN burst length needed to transfer 2^C_MASTER_LENGTH bytes of data.
    reg [C_NO_BURSTS_REQ : 0]     write_burst_counter;
    reg [C_NO_BURSTS_REQ : 0]     read_burst_counter;
    reg      start_single_burst_write;
    reg      start_single_burst_read;
    reg      writes_done;
    reg      reads_done;
    reg      error_reg;
    // reg      compare_done;
    reg      read_mismatch;
    reg      burst_write_active;
    reg      burst_read_active;
    reg [`MEMORY_AXI4_DATA_BIT_NUM-1 : 0]     expected_rdata;
    //Interface response error flags
    wire      write_resp_error;
    wire      read_resp_error;
    wire      wnext;
    wire      rnext;
    reg      init_txn_ff;
    reg      init_txn_ff2;
    reg      init_txn_edge;
    wire      init_txn_pulse;

//
// --- memoryReadReqIDFreeList
//
    // Readリクエストのための定義
    // 1なら使用済みreadReqIDをpushする
    logic pushFreeReadReqID;
    logic [`MEMORY_AXI4_READ_ID_WIDTH-1: 0] pushedFreeReadReqID;
    // 1ならフリーのreadReqIDをpopする
    logic popFreeReadReqID;
    logic [`MEMORY_AXI4_READ_ID_WIDTH-1: 0] popedFreeReadReqID;
    // 1ならmemoryReadReqIDFreeListがfull
    logic readReqIDFreeListFull;
    // 1ならmemoryReadReqIDFreeListが空
    logic readReqIDFreeListEmpty;

    // memoryReadReqQueueにpushするmemoryReadReq
    MemoryReadReq pushedMemoryReadReq;
    // 1ならmemoryReadReqQueueにpushする
    logic pushMemoryReadReq;
    // 1ならmemoryReadReqQueueからpopする
    logic popMemoryReadReq;
    // 1ならmemoryReadReqQueueがfull
    logic memoryReadReqQueueFull;
    // 1ならmemoryReadReqQueueが空
    logic memoryReadReqQueueEmpty;
    // memoryReadReqQueueの先頭にあるmemoryReadReq
    MemoryReadReq popedMemoryReadReq;

    //
    MemoryEntryDataPath nextMemoryReadData;
    logic memoryReadDataTableWE;
    logic [`MEMORY_AXI4_READ_ID_WIDTH-1: 0] memoryReadDataID;
    MemoryEntryDataPath memoryReadData;
    

//
// --- memoryReadReqIDFreeList
//
    FreeList #(
        .SIZE(`MEMORY_AXI4_READ_ID_NUM),
        .ENTRY_WIDTH(`MEMORY_AXI4_READ_ID_WIDTH)
    ) memoryReadReqIDFreeList ( 
        .clk(port.M_AXI_ACLK),
        .rst(~port.M_AXI_ARESETN),
        .push(pushFreeReadReqID),
        .pop(popFreeReadReqID),
        .pushedData(pushedFreeReadReqID),
        .full(readReqIDFreeListFull),
        .empty(readReqIDFreeListEmpty),
        .headData(popedFreeReadReqID)
    );

    // 利用可能なreadReqIDがなければ新しいリードリクエストは受け付けられない
    assign memAccessReadBusy = readReqIDFreeListEmpty;

    // メモリからのデータの読み出しが完了し，coreにデータを送ったら対応するIDはフリーになる
    assign pushFreeReadReqID = memReadDataReady;
    assign pushedFreeReadReqID = memoryReadDataID;

    // 利用可能なreadReqIDがあり，かつリード要求がcoreから来ていたら新しいreadReqIDをpopする
    assign popFreeReadReqID = (~readReqIDFreeListEmpty && memAccessRE) ? 1'd1 : 1'd0;

    // 次のRSDのリード要求に割り当てられるシリアルはFreelistの先頭にある
    assign nextMemReadSerial = popedFreeReadReqID;

//
// --- memoryReadReqQueue
//
    MemoryReadReqQueue memoryReadReqQueue ( 
        .clk(port.M_AXI_ACLK),
        .rst(~port.M_AXI_ARESETN),
        .push(pushMemoryReadReq),
        .pop(popMemoryReadReq),
        .pushedData(pushedMemoryReadReq),
        .full(memoryReadReqQueueFull),
        .empty(memoryReadReqQueueEmpty),
        .headData(popedMemoryReadReq)
    );

    // freelistからpopされたreadReqIDをmemoryReadReqQueueに入力する
    assign pushedMemoryReadReq.id = popedFreeReadReqID;

    // coreからのリードリクエストのアドレスをmemoryReadReqQueueに入力する
    assign pushedMemoryReadReq.addr = memAccessAddr[`MEMORY_AXI4_ADDR_BIT_SIZE-1:0];

    // freelistからreadReqIDがpopされた場合，coreからリクエストが来ていて，かつ受付可能であることを意味しているのでpush
    assign pushMemoryReadReq = popFreeReadReqID;

    // リクエストキューにリクエストが存在し，かつそのリクエストをハンドシェイクによってメモリに伝達できた場合そのリクエストをpopする
    assign popMemoryReadReq = (~memoryReadReqQueueEmpty && port.M_AXI_ARREADY && axi_arvalid) ? 1'd1 : 1'd0;

//
// --- memoryReadDataTable
//
    DistributedDualPortRAM #( 
        .ENTRY_NUM(`MEMORY_AXI4_READ_ID_NUM), 
        .ENTRY_BIT_SIZE(MEMORY_ENTRY_BIT_NUM)
    ) memoryReadDataTable ( 
        .clk(port.M_AXI_ACLK),
        .we(memoryReadDataTableWE),
        .wa(memoryReadDataID),
        .wv(nextMemoryReadData),
        .ra(memoryReadDataID),
        .rv(memoryReadData)
    );

    // メモリからデータを受け取ったらテーブル内のデータを更新
    assign memoryReadDataTableWE = (port.M_AXI_RVALID && axi_rready) ? 1'd1: 1'd0;
    // memoryReadDataTableのアドレスはメモリから届いたデータのID
    assign memoryReadDataID = port.M_AXI_RID;
    // データがメモリから届いたら，テーブルのエントリの上位ビットに挿入する
    generate 
        if (MEMORY_ENTRY_BIT_NUM == `MEMORY_AXI4_DATA_BIT_NUM) begin
            assign nextMemoryReadData = port.M_AXI_RDATA;
        end
        else begin
            assign nextMemoryReadData = {port.M_AXI_RDATA, memoryReadData[MEMORY_ENTRY_BIT_NUM-1: `MEMORY_AXI4_DATA_BIT_NUM]};
        end
    endgenerate

    // バースト転送が終わったらそのエントリはデータの受信が完了したのでcoreにデータを送る．
    assign memReadDataReady = (port.M_AXI_RVALID && axi_rready && port.M_AXI_RLAST) ? 1'd1 : 1'd0;
    assign memReadData = nextMemoryReadData;
    assign memReadSerial = memoryReadDataID;
  

//
// --- definition for AXI4 write
//
    // memoryReadReqQueueにpushするmemoryReadReq
    MemoryEntryDataPath pushedMemoryWriteData;
    // 1ならmemoryReadReqQueueにpushする
    logic pushMemoryWriteData;
    // 1ならmemoryReadReqQueueからpopする
    logic popMemoryWriteData;
    // 1ならmemoryReadReqQueueがfull
    logic memoryWriteDataQueueFull;
    // 1ならmemoryReadReqQueueが空
    logic memoryWriteDataQueueEmpty;
    // memoryReadReqQueueの先頭にあるmemoryReadReq
    MemoryEntryDataPath popedMemoryWriteData;
    // memoryReadReqQueueのポインタ
    MemWriteSerial memoryWriteDataQueueHeadPtr;
    MemWriteSerial memoryWriteDataQueueTailPtr;
    // シフトするためのデータバッファ
    MemoryEntryDataPath memoryWriteData;

//
// --- memoryReadReqQueue
//
    MemoryWriteDataQueue memoryWriteDataQueue ( 
        .clk(port.M_AXI_ACLK),
        .rst(~port.M_AXI_ARESETN),
        .push(pushMemoryWriteData),
        .pop(popMemoryWriteData),
        .pushedData(pushedMemoryWriteData),
        .full(memoryWriteDataQueueFull),
        .empty(memoryWriteDataQueueEmpty),
        .headData(popedMemoryWriteData),
        .headPtr(memoryWriteDataQueueHeadPtr),
        .tailPtr(memoryWriteDataQueueTailPtr)
    );

    // メモリがライトリクエストを受け入れ可能で，かつcoreがライトリクエストを送信したらキューにデータを入れる
    assign pushMemoryWriteData = (memAccessWE && port.M_AXI_AWREADY && ~memoryWriteDataQueueFull) ? 1'd1 : 1'd0;

    // coreからのデータをmemoryWriteDataQueueにpushする
    assign pushedMemoryWriteData = memAccessWriteData;

    // headデータの書き込みが完了したらpopする
    assign popMemoryWriteData = (port.M_AXI_BVALID && axi_bready) ? 1'd1 : 1'd0;
                              //(port.M_AXI_BVALID && axi_bready && (memoryWriteDataQueueHeadPtr == port.M_AXI_BID)) ? 1'd1 : 1'd0;

    // メモリがライトリクエストを受け入れ不可能か，memoryWriteDataQueueがフルなら新しいリクエストは受付不可能
    assign memAccessWriteBusy = (~port.M_AXI_AWREADY || memoryWriteDataQueueFull) ? 1'd1 : 1'd0;

    // AXIバスから書き込み完了応答がきたら，RSDに通知する
    assign memAccessResponse.valid = (port.M_AXI_BVALID && axi_bready) ? 1'd1 : 1'd0;
    assign memAccessResponse.serial = port.M_AXI_BID;

    // RSDからのライト要求を入れるmemoryWriteDataQueueのエントリインデックスがその要求のシリアルになる．
    assign nextMemWriteSerial = memoryWriteDataQueueTailPtr;

//
// --- axi4 signals
//
    // リード要求アドレスはmemoryReadReqQueueの先頭のリクエストに入っている．
    assign axi_araddr = popedMemoryReadReq.addr;

    // coreからのライトリクエストをバスに出力する
    assign axi_awvalid = memAccessWE;

    // coreからのライトリクエストと同時にくるアドレスをバスに出力する
    assign axi_awaddr = memAccessAddr[`MEMORY_AXI4_ADDR_BIT_SIZE-1:0];

    // I/O Connections assignments

    //I/O Connections. Write Address (AW)
    // 対応するデータをmemoryWriteDataQueueにpushするポインタがIDとなる
    assign port.M_AXI_AWID    = memoryWriteDataQueueTailPtr;//'b0;
    //The AXI address is a concatenation of the target base address + active offset range
    assign port.M_AXI_AWADDR    = `MEMORY_AXI4_BASE_ADDR + axi_awaddr;
    //Burst LENgth is number of transaction beats, minus 1
    assign port.M_AXI_AWLEN    = MEMORY_AXI4_BURST_LEN - 1;
    //Size should be `MEMORY_AXI4_DATA_BIT_NUM, in 2^SIZE bytes, otherwise narrow bursts are used
    assign port.M_AXI_AWSIZE    = clogb2((`MEMORY_AXI4_DATA_BIT_NUM/8)-1);
    //INCR burst type is usually used, except for keyhole bursts
    // Burst type (AWBURST) is INCR (2'b01). 
    assign port.M_AXI_AWBURST    = 2'b01;
    // AXI4 does NOT support locked transactions.
    assign port.M_AXI_AWLOCK    = 1'b0;
    //Update value to 4'b0011 if coherent accesses to be used via the Zynq ACP port. Not Allocated, Modifiable, not Bufferable. Not Bufferable since this example is meant to test memory, not intermediate cache. 
    assign port.M_AXI_AWCACHE    = 4'b0010;
    assign port.M_AXI_AWPROT    = 3'h0;
    assign port.M_AXI_AWQOS    = 4'h0;
    // AWUSER is ignored with HP0~3. It should be set appropriately with ACP ports.
    assign port.M_AXI_AWUSER    = 'b1;
    assign port.M_AXI_AWVALID    = axi_awvalid;
    //Write Data(W)
    assign port.M_AXI_WDATA    = axi_wdata;
    //All bursts are complete and aligned in this example
    assign port.M_AXI_WSTRB    = {(`MEMORY_AXI4_DATA_BIT_NUM/8){1'b1}};
    assign port.M_AXI_WLAST    = axi_wlast;
    // WUSER is ignored.
    assign port.M_AXI_WUSER    = 'b0;
    assign port.M_AXI_WVALID    = axi_wvalid;
    //Write Response (B)
    assign port.M_AXI_BREADY    = axi_bready;
    //Read Address (AR)
    // memoryReadReqQueueの先頭に発行するリードリクエストのidが入っている
    assign port.M_AXI_ARID    = popedMemoryReadReq.id;//'b0;
    assign port.M_AXI_ARADDR    = `MEMORY_AXI4_BASE_ADDR + axi_araddr;
    //Burst LENgth is number of transaction beats, minus 1
    assign port.M_AXI_ARLEN    = MEMORY_AXI4_BURST_LEN - 1;
    //Size should be `MEMORY_AXI4_DATA_BIT_NUM, in 2^n bytes, otherwise narrow bursts are used
    assign port.M_AXI_ARSIZE    = clogb2((`MEMORY_AXI4_DATA_BIT_NUM/8)-1);
    //INCR burst type is usually used, except for keyhole bursts
    // Burst type (ARBURST) is INCR (2'b01). 
    assign port.M_AXI_ARBURST    = 2'b01;
    // AXI4 does NOT support locked transactions.
    assign port.M_AXI_ARLOCK    = 1'b0;
    //Update value to 4'b0011 if coherent accesses to be used via the Zynq ACP port. Not Allocated, Modifiable, not Bufferable. Not Bufferable since this example is meant to test memory, not intermediate cache. 
    assign port.M_AXI_ARCACHE    = 4'b0010;
    assign port.M_AXI_ARPROT    = 3'h0;
    assign port.M_AXI_ARQOS    = 4'h0;
    // ARUSER is ignored with HP0~3. It should be set appropriately with ACP ports.
    assign port.M_AXI_ARUSER    = 'b1;
    assign port.M_AXI_ARVALID    = axi_arvalid;
    //Read and Read Response (R)
    assign port.M_AXI_RREADY    = axi_rready;
    //Example design I/O
    // assign TXN_DONE    = compare_done;
    //Burst size in bytes
    assign burst_size_bytes    = MEMORY_AXI4_BURST_LEN * `MEMORY_AXI4_DATA_BIT_NUM/8;
    // assign init_txn_pulse    = (!init_txn_ff2) && init_txn_ff;


    // //Generate a pulse to initiate AXI transaction.
    // always_ff @(posedge port.M_AXI_ACLK)                                              
    //   begin                                                                        
    //     // Initiates AXI transaction delay    
    //     if (port.M_AXI_ARESETN == 0 )                                                   
    //       begin                                                                    
    //         init_txn_ff <= 1'b0;                                                   
    //         init_txn_ff2 <= 1'b0;                                                   
    //       end                                                                               
    //     else                                                                       
    //       begin  
    //         init_txn_ff <= INIT_AXI_TXN;
    //         init_txn_ff2 <= init_txn_ff;                                                                 
    //       end                                                                      
    //   end     


    //--------------------
    //Write Address Channel
    //--------------------

    // The purpose of the write address channel is to request the address and 
    // command information for the entire transaction.  It is a single beat
    // of information.

    // The AXI4 Write address channel in this example will continue to initiate
    // write commands as fast as it is allowed by the slave/interconnect.
    // The address will be incremented on each accepted address transaction,
    // by burst_size_byte to point to the next address. 

      // always_ff @(posedge port.M_AXI_ACLK)                                   
      // begin                                                                
                                                                           
      //   if (port.M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1 )                                           
      //     begin                                                            
      //       axi_awvalid <= 1'b0;                                           
      //     end                                                              
      //   // If previously not valid , start next transaction                
      //   else if (~axi_awvalid && start_single_burst_write)                 
      //     begin                                                            
      //       axi_awvalid <= 1'b1;                                           
      //     end                                                              
      //   /* Once asserted, VALIDs cannot be deasserted, so axi_awvalid      
      //   must wait until transaction is accepted */                         
      //   else if (port.M_AXI_AWREADY && axi_awvalid)                             
      //     begin                                                            
      //       axi_awvalid <= 1'b0;                                           
      //     end                                                              
      //   else                                                               
      //     axi_awvalid <= axi_awvalid;                                      
      //   end                                                                
                                                                           
                                                                           
    // Next address after AWREADY indicates previous address acceptance    
      // always_ff @(posedge port.M_AXI_ACLK)                                         
      // begin                                                                
      //   if (port.M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)                                            
      //     begin                                                            
      //       axi_awaddr <= 'b0;                                             
      //     end                                                              
      //   else if (port.M_AXI_AWREADY && axi_awvalid)                             
      //     begin                                                            
      //       axi_awaddr <= next_addr;                   
      //     end                                                              
      //   else                                                               
      //     axi_awaddr <= axi_awaddr;                                        
      //   end                                                                


    //--------------------
    //Write Data Channel
    //--------------------

    //The write data will continually try to push write data across the interface.

    //The amount of data accepted will depend on the AXI slave and the AXI
    //Interconnect settings, such as if there are FIFOs enabled in interconnect.

    //Note that there is no explicit timing relationship to the write address channel.
    //The write channel has its own throttling flag, separate from the AW channel.

    //Synchronization between the channels must be determined by the user.

    //The simpliest but lowest performance would be to only issue one address write
    //and write data burst at a time.

    //In this example they are kept in sync by using the same address increment
    //and burst sizes. Then the AW and W channels have their transactions measured
    //with threshold counters as part of the user logic, to make sure neither 
    //channel gets too far ahead of each other.

    //Forward movement occurs when the write channel is valid and ready

      assign wnext = port.M_AXI_WREADY & axi_wvalid;                                   
                                                                                        
    // WVALID logic, similar to the axi_awvalid always block above                      
      always_ff @(posedge port.M_AXI_ACLK)                                                      
      begin                                                                             
        if (port.M_AXI_ARESETN == 0 )                                                        
          begin                                                                         
            axi_wvalid <= 1'b0;                                                         
          end                                                                           
        // If previously not valid, start next transaction                              
        else if (~axi_wvalid && start_single_burst_write)                               
          begin                                                                         
            axi_wvalid <= 1'b1;                                                         
          end                                                                           
        /* If WREADY and too many writes, throttle WVALID                               
        Once asserted, VALIDs cannot be deasserted, so WVALID                           
        must wait until burst is complete with WLAST */                                 
        else if (wnext && axi_wlast)                                                    
          axi_wvalid <= 1'b0;                                                           
        else                                                                            
          axi_wvalid <= axi_wvalid;                                                     
      end                                                                               
                                                                                        
                                                                                        
    //WLAST generation on the MSB of a counter underflow                                
    // WVALID logic, similar to the axi_awvalid always block above                      
      always_ff @(posedge port.M_AXI_ACLK)                                                      
      begin                                                                             
        if (port.M_AXI_ARESETN == 0 )                                                        
          begin                                                                         
            axi_wlast <= 1'b0;                                                          
          end                                                                           
        // axi_wlast is asserted when the write index                                   
        // count reaches the penultimate count to synchronize                           
        // with the last write data when write_index is b1111                           
        // else if (&(write_index[C_TRANSACTIONS_NUM-1:1])&& ~write_index[0] && wnext)  
        else if (((write_index == MEMORY_AXI4_BURST_LEN-2 && MEMORY_AXI4_BURST_LEN >= 2) && wnext) || (MEMORY_AXI4_BURST_LEN == 1 ))
          begin                                                                         
            axi_wlast <= 1'b1;                                                          
          end                                                                           
        // Deassrt axi_wlast when the last write data has been                          
        // accepted by the slave with a valid response                                  
        else if (wnext)                                                                 
          axi_wlast <= 1'b0;                                                            
        else if (axi_wlast && MEMORY_AXI4_BURST_LEN == 1)                                   
          axi_wlast <= 1'b0;                                                            
        else                                                                            
          axi_wlast <= axi_wlast;                                                       
      end                                                                               
                                                                                        
                                                                                        
    /* Burst length counter. Uses extra counter register bit to indicate terminal       
     count to reduce decode logic */                                                    
      always_ff @(posedge port.M_AXI_ACLK)                                                      
      begin                                                                             
        if (port.M_AXI_ARESETN == 0 || start_single_burst_write == 1'b1)    
          begin                                                                         
            write_index <= 0;                                                           
          end                                                                           
        else if (wnext && (write_index != MEMORY_AXI4_BURST_LEN-1))                         
          begin                                                                         
            write_index <= write_index + 1;                                             
          end                                                                           
        else                                                                            
          write_index <= write_index;                                                   
      end                                                                               

    generate 
        // バースト転送のため書き込みデータを1転送ごとにシフトしていく
        if (MEMORY_ENTRY_BIT_NUM == `MEMORY_AXI4_DATA_BIT_NUM) begin
            always_ff @(posedge port.M_AXI_ACLK)                                                      
            begin                                                                             
                if (port.M_AXI_ARESETN == 0)                                                         
                memoryWriteData <= '0;                                                                                                                
                else if (start_single_burst_write)                                                                            
                // バースト転送開始時にmemoryWriteDataQueueの先頭のデータをコピーする
                memoryWriteData <= popedMemoryWriteData;
                else if (wnext)
                // 1ワード(AXIバス幅単位)の送信が終わったら送信するデータをシフトする
                memoryWriteData <= memoryWriteData;
            end         
        end
        else begin
            always_ff @(posedge port.M_AXI_ACLK)                                                      
            begin                                                                             
                if (port.M_AXI_ARESETN == 0)                                                         
                memoryWriteData <= '0;                                                                                                                
                else if (start_single_burst_write)                                                                            
                // バースト転送開始時にmemoryWriteDataQueueの先頭のデータをコピーする
                memoryWriteData <= popedMemoryWriteData;
                else if (wnext)
                // 1ワード(AXIバス幅単位)の送信が終わったら送信するデータをシフトする
                memoryWriteData <= {{`MEMORY_AXI4_DATA_BIT_NUM{1'd0}}, memoryWriteData[MEMORY_ENTRY_BIT_NUM-1:`MEMORY_AXI4_DATA_BIT_NUM]};
            end         
        end
    endgenerate 
    
      assign axi_wdata = memoryWriteData[`MEMORY_AXI4_DATA_BIT_NUM-1: 0]; 
                                                                                        
    // /* Write Data Generator                                                             
    //  Data pattern is only a simple incrementing count from 0 for each burst  */         
    //   always_ff @(posedge port.M_AXI_ACLK)                                                      
    //   begin                                                                             
    //     if (port.M_AXI_ARESETN == 0)                                                         
    //       axi_wdata <= '0;                                                             
    //     // //else if (wnext && axi_wlast)                                                  
    //     // //  axi_wdata <= 'b0;                                                           
    //     // else if (wnext)                                                                 
    //     //   axi_wdata <= axi_wdata + 1;                                                   
    //     else                                                                            
    //       axi_wdata <= memoryWriteData[`MEMORY_AXI4_DATA_BIT_NUM-1: 0];                                                       
    //   end                                                                             

      always_ff @(posedge port.M_AXI_ACLK)                                                      
      begin    
        if (port.M_AXI_ARESETN == 0) begin
          start_single_burst_write <= 1'b0; 
        end
        if (~start_single_burst_write && ~burst_write_active && ~memoryWriteDataQueueEmpty)                       
          begin                                                                                     
            start_single_burst_write <= 1'b1;                                                       
          end                                                                                       
        else                                                                                        
          begin                                                                                     
            start_single_burst_write <= 1'b0; //Negate to generate a pulse                          
          end   
      end

    //----------------------------
    //Write Response (B) Channel
    //----------------------------

    //The write response channel provides feedback that the write has committed
    //to memory. BREADY will occur when all of the data and the write address
    //has arrived and been accepted by the slave.

    //The write issuance (number of outstanding write addresses) is started by 
    //the Address Write transfer, and is completed by a BREADY/BRESP.

    //While negating BREADY will eventually throttle the AWREADY signal, 
    //it is best not to throttle the whole data channel this way.

    //The BRESP bit [1] is used indicate any errors from the interconnect or
    //slave for the entire write burst. This example will capture the error 
    //into the ERROR output. 

      always_ff @(posedge port.M_AXI_ACLK)                                     
      begin                                                                 
        if (port.M_AXI_ARESETN == 0)                                            
          begin                                                             
            axi_bready <= 1'b0;                                             
          end                                                               
        // accept/acknowledge bresp with axi_bready by the master           
        // when port.M_AXI_BVALID is asserted by slave                           
        else if (port.M_AXI_BVALID && ~axi_bready)                               
          begin                                                             
            axi_bready <= 1'b1;                                             
          end                                                               
        // deassert after one clock cycle                                   
        else if (axi_bready)                                                
          begin                                                             
            axi_bready <= 1'b0;                                             
          end                                                               
        // retain the previous value                                        
        else                                                                
          axi_bready <= axi_bready;                                         
      end                                                                   
                                                                            
                                                                            
    //Flag any write response errors                                        
      assign write_resp_error = axi_bready & port.M_AXI_BVALID & port.M_AXI_BRESP[1]; 


    //----------------------------
    //Read Address Channel
    //----------------------------

    //The Read Address Channel (AW) provides a similar function to the
    //Write Address channel- to provide the tranfer qualifiers for the burst.

    //In this example, the read address increments in the same
    //manner as the write address channel.

      always_ff @(posedge port.M_AXI_ACLK)                                 
      begin                                                              
                                                                         
        if (port.M_AXI_ARESETN == 0)                                         
          begin                                                          
            axi_arvalid <= 1'b0;                                         
          end                                                            
        // If previously not valid , start next transaction 
        // memoryReadReqQueueが空でない場合，送信すべきリクエストがあるので送信する
        else if (~axi_arvalid && ~memoryReadReqQueueEmpty)                
          begin                                                          
            axi_arvalid <= 1'b1;                                         
          end                                                            
        else if (port.M_AXI_ARREADY && axi_arvalid)                           
          begin                                                          
            axi_arvalid <= 1'b0;                                         
          end                                                            
        else                                                             
          axi_arvalid <= axi_arvalid;                                    
      end                                                                
                                                   

    // // Next address after ARREADY indicates previous address acceptance  
    //   always_ff @(posedge port.M_AXI_ACLK)                                       
    //   begin                                                              
    //     if (port.M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)                                          
    //       begin                                                          
    //         axi_araddr <= 'b0;                                           
    //       end                                                            
    //     else if (port.M_AXI_ARREADY && axi_arvalid)                           
    //       begin                                                          
    //         axi_araddr <= next_addr;                 
    //       end                                                            
    //     else                                                             
    //       axi_araddr <= axi_araddr;                                      
    //   end                                                                


    //--------------------------------
    //Read Data (and Response) Channel
    //--------------------------------

     // Forward movement occurs when the channel is valid and ready   
      //assign rnext = port.M_AXI_RVALID && axi_rready;                            
                                                                            
                                                                            
    // // Burst length counter. Uses extra counter register bit to indicate    
    // // terminal count to reduce decode logic                                
    //   always_ff @(posedge port.M_AXI_ACLK)                                          
    //   begin                                                                 
    //     if (port.M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1 || start_single_burst_read)                  
    //       begin                                                             
    //         read_index <= 0;                                                
    //       end                                                               
    //     else if (rnext && (read_index != MEMORY_AXI4_BURST_LEN-1))              
    //       begin                                                             
    //         read_index <= read_index + 1;                                   
    //       end                                                               
    //     else                                                                
    //       read_index <= read_index;                                         
    //   end                                                                   
                                                                            
                                                                            
    /*                                                                      
     The Read Data channel returns the results of the read request          
                                                                            
     In this example the data checker is always able to accept              
     more data, so no need to throttle the RREADY signal                    
     */                                                                     
      always_ff @(posedge port.M_AXI_ACLK)                                          
      begin                                                                 
        if (port.M_AXI_ARESETN == 0)                  
          begin                                                             
            axi_rready <= 1'b0;                                             
          end                                                               
        // accept/acknowledge rdata/rresp with axi_rready by the master     
        // when port.M_AXI_RVALID is asserted by slave                           
        else if (port.M_AXI_RVALID)                       
          begin                                      
             if (port.M_AXI_RLAST && axi_rready)          
              begin                                  
                axi_rready <= 1'b0;                  
              end                                    
             else                                    
               begin                                 
                 axi_rready <= 1'b1;                 
               end                                   
          end                                        
        // retain the previous value                 
      end                                            
                                                                            
    // //Check received read data against data generator                       
    //   always_ff @(posedge port.M_AXI_ACLK)                                          
    //   begin                                                                 
    //     if (port.M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)                   
    //       begin                                                             
    //         read_mismatch <= 1'b0;                                          
    //       end                                                               
    //     //Only check data when RVALID is active                             
    //     else if (rnext && (port.M_AXI_RDATA != expected_rdata))                  
    //       begin                                                             
    //         read_mismatch <= 1'b1;                                          
    //       end                                                               
    //     else                                                                
    //       read_mismatch <= 1'b0;                                            
    //   end                                                                   
                                                                            
    //Flag any read response errors                                         
      assign read_resp_error = axi_rready & port.M_AXI_RVALID & port.M_AXI_RRESP[1];  


    //----------------------------------------
    //Example design read check data generator
    //-----------------------------------------

    //Generate expected read data to check against actual read data

      // always_ff @(posedge port.M_AXI_ACLK)                     
      // begin                                                  
      //   if (port.M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)// || port.M_AXI_RLAST)             
      //       expected_rdata <= 'b1;                            
      //   else if (port.M_AXI_RVALID && axi_rready)                  
      //       expected_rdata <= expected_rdata + 1;             
      //   else                                                  
      //       expected_rdata <= expected_rdata;                 
      // end                                                    


    //----------------------------------
    //Example design error register
    //----------------------------------

    //Register and hold any data mismatches, or read/write interface errors 

      always_ff @(posedge port.M_AXI_ACLK)                                 
      begin                                                              
        if (port.M_AXI_ARESETN == 0)                                          
          begin                                                          
            error_reg <= 1'b0;                                           
          end                                                            
        else if (write_resp_error || read_resp_error)   
          begin                                                          
            error_reg <= 1'b1;                                           
          end                                                            
        else                                                             
          error_reg <= error_reg;                                        
      end                                                                


    // //--------------------------------
    // //Example design throttling
    // //--------------------------------

    // // For maximum port throughput, this user example code will try to allow
    // // each channel to run as independently and as quickly as possible.

    // // However, there are times when the flow of data needs to be throtted by
    // // the user application. This example application requires that data is
    // // not read before it is written and that the write channels do not
    // // advance beyond an arbitrary threshold (say to prevent an 
    // // overrun of the current read address by the write address).

    // // From AXI4 Specification, 13.13.1: "If a master requires ordering between 
    // // read and write transactions, it must ensure that a response is received 
    // // for the previous transaction before issuing the next transaction."

    // // This example accomplishes this user application throttling through:
    // // -Reads wait for writes to fully complete
    // // -Address writes wait when not read + issued transaction counts pass 
    // // a parameterized threshold
    // // -Writes wait when a not read + active data burst count pass 
    // // a parameterized threshold

    //  // write_burst_counter counter keeps track with the number of burst transaction initiated            
    //  // against the number of burst transactions the master needs to initiate                                   
    //   always_ff @(posedge port.M_AXI_ACLK)                                                                              
    //   begin                                                                                                     
    //     if (port.M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1 )                                                                                 
    //       begin                                                                                                 
    //         write_burst_counter <= 'b0;                                                                         
    //       end                                                                                                   
    //     else if (port.M_AXI_AWREADY && axi_awvalid)                                                                  
    //       begin                                                                                                 
    //         if (write_burst_counter[C_NO_BURSTS_REQ] == 1'b0)                                                   
    //           begin                                                                                             
    //             write_burst_counter <= write_burst_counter + 1'b1;                                              
    //             //write_burst_counter[C_NO_BURSTS_REQ] <= 1'b1;                                                 
    //           end                                                                                               
    //       end                                                                                                   
    //     else                                                                                                    
    //       write_burst_counter <= write_burst_counter;                                                           
    //   end                                                                                                       
                                                                                                                
    //  // read_burst_counter counter keeps track with the number of burst transaction initiated                   
    //  // against the number of burst transactions the master needs to initiate                                   
    //   always_ff @(posedge port.M_AXI_ACLK)                                                                              
    //   begin                                                                                                     
    //     if (port.M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)                                                                                 
    //       begin                                                                                                 
    //         read_burst_counter <= 'b0;                                                                          
    //       end                                                                                                   
    //     else if (port.M_AXI_ARREADY && axi_arvalid)                                                                  
    //       begin                                                                                                 
    //         if (read_burst_counter[C_NO_BURSTS_REQ] == 1'b0)                                                    
    //           begin                                                                                             
    //             read_burst_counter <= read_burst_counter + 1'b1;                                                
    //             //read_burst_counter[C_NO_BURSTS_REQ] <= 1'b1;                                                  
    //           end                                                                                               
    //       end                                                                                                   
    //     else                                                                                                    
    //       read_burst_counter <= read_burst_counter;                                                             
    //   end                                                                                                       
                                                                                                                
                                                                                                                
    //   //implement master command interface state machine                                                        
                                                                                                                
    //   always_ff @ ( posedge port.M_AXI_ACLK)                                                                            
    //   begin                                                                                                     
    //     if (port.M_AXI_ARESETN == 1'b0 )                                                                             
    //       begin                                                                                                 
    //         // reset condition                                                                                  
    //         // All the signals are assigned default values under reset condition                                
    //         mst_exec_state      <= IDLE;                                                                
    //         start_single_burst_write <= 1'b0;                                                                   
    //         start_single_burst_read  <= 1'b0;                                                                   
    //         compare_done      <= 1'b0;                                                                          
    //         ERROR <= 1'b0;   
    //       end                                                                                                   
    //     else                                                                                                    
    //       begin                                                                                                 
                                                                                                                
    //         // state transition                                                                                 
    //         case (mst_exec_state)                                                                               
                                                                                                                
    //           IDLE:                                                                                     
    //             // This state is responsible to wait for user defined C_M_START_COUNT                           
    //             // number of clock cycles.                                                                      
    //             if ( init_txn_pulse == 1'b1)                                                      
    //               begin                                                                                         
    //                 mst_exec_state  <= INIT_WRITE;                                                              
    //                 ERROR <= 1'b0;
    //                 compare_done <= 1'b0;
    //               end                                                                                           
    //             else                                                                                            
    //               begin                                                                                         
    //                 mst_exec_state  <= IDLE;                                                            
    //               end                                                                                           
                                                                                                                
    //           INIT_WRITE:                                                                                       
    //             // This state is responsible to issue start_single_write pulse to                               
    //             // initiate a write transaction. Write transactions will be                                     
    //             // issued until burst_write_active signal is asserted.                                          
    //             // write controller                                                                             
    //             if (writes_done)                                                                                
    //               begin                                                                                         
    //                 mst_exec_state <= INIT_READ;//                                                              
    //               end                                                                                           
    //             else                                                                                            
    //               begin                                                                                         
    //                 mst_exec_state  <= INIT_WRITE;                                                              
                                                                                                                
    //                 if (~axi_awvalid && ~start_single_burst_write && ~burst_write_active)                       
    //                   begin                                                                                     
    //                     start_single_burst_write <= 1'b1;                                                       
    //                   end                                                                                       
    //                 else                                                                                        
    //                   begin                                                                                     
    //                     start_single_burst_write <= 1'b0; //Negate to generate a pulse                          
    //                   end                                                                                       
    //               end                                                                                           
                                                                                                                
    //           INIT_READ:                                                                                        
    //             // This state is responsible to issue start_single_read pulse to                                
    //             // initiate a read transaction. Read transactions will be                                       
    //             // issued until burst_read_active signal is asserted.                                           
    //             // read controller                                                                              
    //             if (reads_done)                                                                                 
    //               begin                                                                                         
    //                 mst_exec_state <= INIT_COMPARE;                                                             
    //               end                                                                                           
    //             else                                                                                            
    //               begin                                                                                         
    //                 mst_exec_state  <= INIT_READ;                                                               
                                                                                                                
    //                 if (~axi_arvalid && ~burst_read_active && ~start_single_burst_read)                         
    //                   begin                                                                                     
    //                     start_single_burst_read <= 1'b1;                                                        
    //                   end                                                                                       
    //                else                                                                                         
    //                  begin                                                                                      
    //                    start_single_burst_read <= 1'b0; //Negate to generate a pulse                            
    //                  end                                                                                        
    //               end                                                                                           
                                                                                                                
    //           INIT_COMPARE:                                                                                     
    //             // This state is responsible to issue the state of comparison                                   
    //             // of written data with the read data. If no error flags are set,                               
    //             // compare_done signal will be asseted to indicate success.                                     
    //             //if (~error_reg)                                                                               
    //             begin                                                                                           
    //               ERROR <= error_reg;
    //               mst_exec_state <= IDLE;                                                               
    //               compare_done <= 1'b1;                                                                         
    //             end                                                                                             
    //           default :                                                                                         
    //             begin                                                                                           
    //               mst_exec_state  <= IDLE;                                                              
    //             end                                                                                             
    //         endcase                                                                                             
    //       end                                                                                                   
    //   end //MASTER_EXECUTION_PROC                                                                               
                                                                                                                
                                                                                                                
      // burst_write_active signal is asserted when there is a burst write transaction                          
      // is initiated by the assertion of start_single_burst_write. burst_write_active                          
      // signal remains asserted until the burst write is accepted by the slave                                 
      always_ff @(posedge port.M_AXI_ACLK)                                                                              
      begin                                                                                                     
        if (port.M_AXI_ARESETN == 0)                                                                                 
          burst_write_active <= 1'b0;                                                                           
                                                                                                                
        //The burst_write_active is asserted when a write burst transaction is initiated                        
        else if (start_single_burst_write)                                                                      
          burst_write_active <= 1'b1;                                                                           
        else if (port.M_AXI_BVALID && axi_bready)                                                                    
          burst_write_active <= 0;                                                                              
      end                                                                                                       
                                                                                                                
    //  // Check for last write completion.                                                                        
                                                                                                                
    //  // This logic is to qualify the last write count with the final write                                      
    //  // response. This demonstrates how to confirm that a write has been                                        
    //  // committed.                                                                                              
                                                                                                                
    //   always_ff @(posedge port.M_AXI_ACLK)                                                                              
    //   begin                                                                                                     
    //     if (port.M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)                                                                                 
    //       writes_done <= 1'b0;                                                                                  
                                                                                                                
    //     //The writes_done should be associated with a bready response                                           
    //     //else if (port.M_AXI_BVALID && axi_bready && (write_burst_counter == {(C_NO_BURSTS_REQ-1){1}}) && axi_wlast)
    //     else if (port.M_AXI_BVALID && (write_burst_counter[C_NO_BURSTS_REQ]) && axi_bready)                          
    //       writes_done <= 1'b1;                                                                                  
    //     else                                                                                                    
    //       writes_done <= writes_done;                                                                           
    //     end                                                                                                     
                                                                                                                
    //   // burst_read_active signal is asserted when there is a burst write transaction                           
    //   // is initiated by the assertion of start_single_burst_write. start_single_burst_read                     
    //   // signal remains asserted until the burst read is accepted by the master                                 
    //   always_ff @(posedge port.M_AXI_ACLK)                                                                              
    //   begin                                                                                                     
    //     if (port.M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)                                                                                 
    //       burst_read_active <= 1'b0;                                                                            
                                                                                                                
    //     //The burst_write_active is asserted when a write burst transaction is initiated                        
    //     else if (start_single_burst_read)                                                                       
    //       burst_read_active <= 1'b1;                                                                            
    //     else if (port.M_AXI_RVALID && axi_rready && port.M_AXI_RLAST)                                                     
    //       burst_read_active <= 0;                                                                               
    //     end                                                                                                     
                                                                                                                
                                                                                                                
    //  // Check for last read completion.                                                                         
                                                                                                                
    //  // This logic is to qualify the last read count with the final read                                        
    //  // response. This demonstrates how to confirm that a read has been                                         
    //  // committed.                                                                                              
                                                                                                                
    //   always_ff @(posedge port.M_AXI_ACLK)                                                                              
    //   begin                                                                                                     
    //     if (port.M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)                                                                                 
    //       reads_done <= 1'b0;                                                                                   
                                                                                                                
    //     //The reads_done should be associated with a rready response                                            
    //     //else if (port.M_AXI_BVALID && axi_bready && (write_burst_counter == {(C_NO_BURSTS_REQ-1){1}}) && axi_wlast)
    //     else if (port.M_AXI_RVALID && axi_rready && (read_index == MEMORY_AXI4_BURST_LEN-1) && (read_burst_counter[C_NO_BURSTS_REQ]))
    //       reads_done <= 1'b1;                                                                                   
    //     else                                                                                                    
    //       reads_done <= reads_done;                                                                             
    //     end                                                                                                     

    // Add user logic here

    // User logic ends

    // The data width of AXI4 bus and memory access serial must be the same value
    `RSD_STATIC_ASSERT(
        `MEMORY_AXI4_READ_ID_WIDTH == MEM_ACCESS_SERIAL_BIT_SIZE, 
        ("The data width of AXI4 read ID(%x) and memory access serial(%x) are not matched.", 
          `MEMORY_AXI4_READ_ID_WIDTH, MEM_ACCESS_SERIAL_BIT_SIZE)
    );

    `RSD_STATIC_ASSERT(
        `MEMORY_AXI4_WRITE_ID_WIDTH == MEM_WRITE_SERIAL_BIT_SIZE, 
        ("The data width of AXI4 write ID(%x) and memory write serial(%x) are not matched.", 
          `MEMORY_AXI4_WRITE_ID_WIDTH, MEM_WRITE_SERIAL_BIT_SIZE)
    );

    endmodule
