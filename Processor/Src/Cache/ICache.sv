// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A set-associative instruction cache (non-blocking)
// Replacement policy: NRU (not-recently used)
//

`include "BasicMacros.sv"

import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryMapTypes::*;

module ICacheArray(
    input  logic           clk, rst, rstStart,
    input  logic           we,
    input  ICacheIndexPath writeIndex,
    input  ICacheTagPath   writeTag,
    input  ICacheLinePath  writeLineData,
    input  ICacheIndexPath readIndex, // The result comes after 1 cycle from the request
    input  ICacheTagPath   readTag,
    output ICacheLinePath  readLineData,
    output logic           hit, valid
);

    typedef struct packed {
        ICacheLinePath     data;
        ICacheTagValidPath meta;
    } WayData;

    logic weWay;
    ICacheIndexPath rstIndex;
    ICacheIndexPath writeWayIndex;
    WayData readWayData, writeWayData;

    // tag + instruction array
    BlockDualPortRAM #( 
        .ENTRY_NUM( ICACHE_INDEX_NUM ),
        .ENTRY_BIT_SIZE( $bits(WayData)  )
    ) tagValidArray ( 
        .clk( clk ),
        .we( weWay ),
        .wa( writeWayIndex ),
        .wv( writeWayData ),
        .ra( readIndex ),
        .rv( readWayData )
    );

    always_comb begin
        // ICacheTagPath-array write
        if ( rst ) begin
            weWay = TRUE;
            writeWayIndex = rstIndex;
            writeWayData.meta.valid = FALSE;
        end
        else begin
            weWay = we;
            writeWayIndex = writeIndex;
            writeWayData.meta.valid = TRUE;
        end
        writeWayData.meta.tag = writeTag;
        writeWayData.data = writeLineData;
        readLineData = readWayData.data;
        // Result of tag-array read
        valid = readWayData.meta.valid;
        hit = valid && readWayData.meta.tag == readTag;
    end

    
    // Reset Index
    always_ff @ ( posedge clk ) begin
        if ( rstStart ) begin
            rstIndex <= '0;
        end
        else begin
            rstIndex <= rstIndex + 1;
        end
    end

endmodule

//
// NRUStateArray
//
module ICacheNRUStateArray(
    input  logic              clk, rst, rstStart,
    input  ICacheIndexPath    writeIndex,
    input  ICacheWayPath      writeWay,
    input  logic              writeHit,
    input  NRUAccessStatePath writeNRUState,
    input  ICacheIndexPath    readIndex,
    output NRUAccessStatePath readNRUState,
    output ICacheIndexPath rstIndex
);
    
    logic we;
    ICacheIndexPath writeNRUStateIndex;
    NRUAccessStatePath writeNRUStateData;

    // NRUStateArray array
    BlockDualPortRAM #(
        .ENTRY_NUM( ICACHE_INDEX_NUM ),
        .ENTRY_BIT_SIZE( $bits( NRUAccessStatePath ) )
    ) nruStateArray (
        .clk( clk ),
        .we( we ),
        .wa( writeNRUStateIndex ),
        .wv( writeNRUStateData ),
        .ra( readIndex ),
        .rv( readNRUState )
    );

    always_comb begin
        if ( rst ) begin
            we = TRUE;
            writeNRUStateIndex = rstIndex;
            writeNRUStateData = '0;
        end
        else begin
            we = writeHit;
            writeNRUStateIndex = writeIndex;
            writeNRUStateData = writeNRUState;
        end
    end
    // Reset Index
    always_ff @ ( posedge clk ) begin
        if ( rstStart ) begin
            rstIndex <= '0;
        end
        else begin
            rstIndex <= rstIndex + 1;
        end
    end

endmodule

//
// Generate hit signals for each word.
//
module ICacheHitLogic(
input
    logic hitIn,
    ICacheLineInsnIndexPath headWordPtr,
output
    logic hitOut [ FETCH_WIDTH ]
);
    ICacheLineInsnCountPath wordPtr [ FETCH_WIDTH ];
    
    always_comb begin
        for ( int i = 0; i < FETCH_WIDTH; i++ ) begin
            wordPtr[i] = headWordPtr + i;
            if ( wordPtr[i][ $clog2(ICACHE_LINE_INSN_NUM) ] ) begin
                // If this condition is satisfied, word[i] is not on the same line as word[0].
                // It means cache-miss.
                hitOut[i] = FALSE;
            end
            else begin
                hitOut[i] = hitIn;
            end
        end
    end

endmodule

module ICache(
    NextPCStageIF.ICache port,
    FetchStageIF.ICache next,
    CacheSystemIF.ICache cacheSystem
);
    
    //
    // ICacheIndexPath, ICacheTagPath -> Physical Address
    //
    function automatic PhyAddrPath GetFullPhyAddr ( ICacheIndexPath index, ICacheTagPath tag );
        return { tag, index, { ICACHE_LINE_BYTE_NUM_BIT_WIDTH{1'b0} } };
    endfunction
    
    //
    // PC -> ICacheIndexPath, ICacheTagPath etc.
    //
    function automatic ICacheIndexPath GetICacheIndex( PhyAddrPath addr );
        return addr [
            PHY_ADDR_WIDTH - ICACHE_TAG_BIT_WIDTH - 1 : 
            ICACHE_LINE_BYTE_NUM_BIT_WIDTH 
        ];
    endfunction
    
    function automatic ICacheTagPath GetICacheTag( PhyAddrPath addr );
        return addr [ 
            PHY_ADDR_WIDTH - 1 : 
            PHY_ADDR_WIDTH - ICACHE_TAG_BIT_WIDTH 
        ];
    endfunction
    
    function automatic ICacheLineInsnIndexPath GetICacheLineInsnIndex( PhyAddrPath addr );
        return addr [ 
            ICACHE_LINE_BYTE_NUM_BIT_WIDTH-1 : 
            INSN_ADDR_BIT_WIDTH 
        ];
    endfunction
    
    //
    // NRUState, Access -> NRUState
    // NRUState         -> Evicted way (one-hot)
    //
    function automatic NRUAccessStatePath UpdateNRUState( NRUAccessStatePath NRUState, ICacheWayPath way );

        if ( (NRUState | (1 << way)) == (1 << ICACHE_WAY_NUM) - 1 ) begin 
            // if all NRU state bits are high, NRU state needs to clear
            return 1 << way;
        end
        else begin
            // Update indicated NRU state bit 
            return NRUState | (1 << way);
        end
    endfunction

    function automatic NRUAccessStatePath DecideWayToEvictByNRUState( NRUAccessStatePath NRUState );
        // return the position of the rightmost 0-bit
        // e.g. NRUState = 10011 -> return 00100
        return (NRUState | NRUState + 1) ^ NRUState;
    endfunction

    //
    // Phase of ICache
    //
    typedef enum logic [2:0]
    {
        ICACHE_PHASE_READ_CACHE = 0,
        ICACHE_PHASE_MISS_READ_MEM_REQUEST = 1,   // Read from a main memory to a cache.
        ICACHE_PHASE_MISS_READ_MEM_RECEIVE = 2,   // Read from a main memory to a cache.
        ICACHE_PHASE_MISS_WRITE_CACHE = 3,        // Write data to a cache.
        ICACHE_PHASE_FLUSH_PREPARE = 4,           // Prepare for ICache flush.
        ICACHE_PHASE_FLUSH_PROCESSING = 5,        // ICache flush is processing.
        ICACHE_PHASE_FLUSH_COMPLETE = 6           // ICache flush is completed.
    } ICachePhase;
    ICachePhase regPhase, nextPhase;

    always_ff @( posedge port.clk ) begin
        if ( port.rst ) begin
            regPhase <= ICACHE_PHASE_READ_CACHE;
        end
        else begin
            regPhase <= nextPhase;
        end
    end
    
    // for flush
    logic regFlushStart, nextFlushStart;
    logic regFlush, nextFlush;
    logic regFlushReqAck, nextFlushReqAck;
    logic flushComplete;

    //
    // ICacheArray
    //
    logic valid[ICACHE_WAY_NUM];
    logic hit;
    logic[ICACHE_WAY_NUM-1:0] hitArray;
    ICacheWayPath hitWay;
    logic we[ICACHE_WAY_NUM];
    ICacheIndexPath readIndex, writeIndex, nextReadIndex;
    ICacheTagPath readTag, writeTag;
    ICacheLineInsnPath readLineInsnList[ICACHE_WAY_NUM];

    generate
        for ( genvar i = 0; i < ICACHE_WAY_NUM; i++ ) begin
            ICacheArray array(
                .clk( port.clk ),
                .rst( (port.rst) ? port.rst : regFlush ),
                .rstStart( (port.rstStart) ? port.rstStart : regFlushStart ),
                .we( we[i] ),
                .writeIndex( writeIndex ),
                .writeTag( writeTag ),
                .writeLineData( cacheSystem.icMemAccessResult.data ),
                .readIndex( nextReadIndex ),
                .readTag( readTag ),
                .hit( hitArray[i] ),
                .valid( valid[i] ),
                .readLineData( readLineInsnList[i] )
            );
        end
    endgenerate
    
    always_comb begin
        // Set signal about read address.
        readIndex  = GetICacheIndex( next.icReadAddrIn );
        readTag = GetICacheTag( next.icReadAddrIn );
        
        nextReadIndex = GetICacheIndex( port.icNextReadAddrIn );

        // Check cache hit 
        hit = |hitArray;
        hitWay = '0;
        for (int i = 0; i < ICACHE_WAY_NUM; i++) begin
            if (hitArray[i]) begin
                // Detect which way is hit
                hitWay = i;
                break;
            end
        end
    end

    //
    // ICacheNRUStateArray
    //
    NRUAccessStatePath updatedNRUState, readNRUState;
    NRUAccessStatePath wayToEvictOneHot;
    ICacheWayPath wayToEvict;
    logic nruStateWE;
    ICacheIndexPath rstIndex;
    ICacheNRUStateArray nruStateArray(
        .clk( port.clk ),
        .rst( (port.rst) ? port.rst : regFlush ),
        .rstStart( (port.rstStart) ? port.rstStart : regFlushStart ),
        .writeIndex( readIndex ),
        .writeWay( hitWay ),
        .writeHit( nruStateWE ),
        .writeNRUState( updatedNRUState ),
        .readIndex( nextReadIndex ),
        .readNRUState( readNRUState ),
        .rstIndex( rstIndex )
    );

    always_comb begin
        updatedNRUState = UpdateNRUState(readNRUState, hitWay);
        wayToEvictOneHot = DecideWayToEvictByNRUState(readNRUState);
        wayToEvict = '0;

        for ( int i = 0; i < ICACHE_WAY_NUM; i++ ) begin
            if ( wayToEvictOneHot[i] ) begin
                wayToEvict = i;
                break;
            end
        end
    end

    //
    // HitLogic
    // Check whether each read request is satisfied
    //
    ICacheLineInsnIndexPath wordPtr[ FETCH_WIDTH ];
    ICacheHitLogic iCacheHitLogic (
        .hitIn( hit && regPhase == ICACHE_PHASE_READ_CACHE && next.icRE ),
        .headWordPtr( wordPtr[0] ),
        .hitOut( next.icReadHit )
    );
    
    //
    // ICache Read
    //
    
    always_comb begin
        wordPtr[0] = GetICacheLineInsnIndex( next.icReadAddrIn );
        for ( int i = 1; i < FETCH_WIDTH; i++ ) begin
            wordPtr[i] = wordPtr[0] + i;
        end
        
        // Send i-cache read data to FetchStage
        for ( int i = 0; i < FETCH_WIDTH; i++ ) begin
            next.icReadDataOut[i] = readLineInsnList[hitWay][ wordPtr[i] ];
        end
    end
    
    
    //
    // ICache Miss Handling
    //
    logic regMissValid, nextMissValid;
    ICacheIndexPath regMissIndex, nextMissIndex;
    ICacheTagPath regMissTag, nextMissTag;
    MemAccessSerial regSerial, nextSerial;
    
    always_comb begin
        for ( int i = 0; i < ICACHE_WAY_NUM; i++ ) begin
            we[i] = FALSE;
        end
        nruStateWE = FALSE;

        nextPhase = regPhase;
        
        nextMissValid = regMissValid;
        nextMissIndex = regMissIndex;
        nextMissTag = regMissTag;
        nextSerial = regSerial;

        // for flush
        nextFlushStart = regFlushStart;
        nextFlush = regFlush;
        nextFlushReqAck = regFlushReqAck;
        flushComplete = FALSE;
        
        // Non-blocking i-cache state machine
        case (regPhase)
        default: begin
            nextPhase = ICACHE_PHASE_READ_CACHE;
        end
        ICACHE_PHASE_READ_CACHE: begin
            // Not processing cache miss now
            if (cacheSystem.icFlushReq) begin
                nextPhase = ICACHE_PHASE_FLUSH_PREPARE;
                nextFlushStart = TRUE;
                nextFlush = TRUE;
                nextFlushReqAck = FALSE;
            end
            else if ( next.icRE && !hit ) begin
                // Read request -> i-cache miss:
                // Change state to process a cache miss
                nextPhase = ICACHE_PHASE_MISS_READ_MEM_REQUEST;
                nextMissValid = TRUE;
                nextMissIndex = readIndex;
                nextMissTag = readTag;
                nextFlushReqAck = FALSE;
            end
            else if ( next.icRE )begin
                // Read request -> i-cache hit:
                // Update nru state
                nruStateWE = TRUE;
            end
        end
        ICACHE_PHASE_MISS_READ_MEM_REQUEST: begin
            // Send read request to lower level memory
            if ( cacheSystem.icMemAccessReqAck.ack ) begin
                nextPhase = ICACHE_PHASE_MISS_READ_MEM_RECEIVE;
                nextMissValid = FALSE;
                nextSerial = cacheSystem.icMemAccessReqAck.serial;
            end
        end
        ICACHE_PHASE_MISS_READ_MEM_RECEIVE: begin
            // Read response has come
            if (
                cacheSystem.icMemAccessResult.valid &&
                cacheSystem.icMemAccessResult.serial == regSerial
            ) begin
                // Receive memory read data and write it to i-cache
                nextPhase = ICACHE_PHASE_MISS_WRITE_CACHE;
                we[wayToEvict] = TRUE;
            end
        end
        ICACHE_PHASE_MISS_WRITE_CACHE: begin
            // Cannot read the write data in the same cycle,
            // therefore wait 1-cycle
            nextFlushReqAck = TRUE;
            nextPhase = ICACHE_PHASE_READ_CACHE;
        end
        ICACHE_PHASE_FLUSH_PREPARE: begin
            // 1 cycle to reset rstIndex.
            nextFlushStart = FALSE;
            nextMissTag = '0;
            nextPhase = ICACHE_PHASE_FLUSH_PROCESSING;
        end
        ICACHE_PHASE_FLUSH_PROCESSING: begin
            if (&rstIndex) begin
                nextFlush = FALSE;
                nextPhase = ICACHE_PHASE_FLUSH_COMPLETE;
            end
        end
        ICACHE_PHASE_FLUSH_COMPLETE: begin
            flushComplete = TRUE;
            if (cacheSystem.flushComplete) begin
                nextFlushReqAck = TRUE;
                nextPhase = ICACHE_PHASE_READ_CACHE;
            end
        end
        endcase // regPhase

        writeIndex = regMissIndex;
        writeTag = regMissTag;

        cacheSystem.icMemAccessReq.valid = regMissValid;
        cacheSystem.icMemAccessReq.addr = 
            GetFullPhyAddr( regMissIndex, regMissTag );

        // for flush
        cacheSystem.icFlushReqAck = regFlushReqAck;
        cacheSystem.icFlushComplete = flushComplete;
    end
    
    always_ff @( posedge port.clk ) begin
        if ( port.rst ) begin
            regMissValid <= FALSE;
            regMissIndex <= '0;
            regMissTag <= '0;
            regSerial <= '0;
        end
        else begin
            regMissValid <= nextMissValid;
            regMissIndex <= nextMissIndex;
            regMissTag <= nextMissTag;
            regSerial <= nextSerial;
        end
        
    end

    // for flush
    always_ff @( posedge port.clk ) begin
        if ( port.rst ) begin
            regFlush <= FALSE;
            regFlushStart <= FALSE;
            regFlushReqAck <= TRUE;
        end
        else begin
            regFlush <= nextFlush;
            regFlushStart <= nextFlushStart;
            regFlushReqAck <= nextFlushReqAck;
        end
    end
    
`ifndef RSD_SYNTHESIS
    `ifndef RSD_VIVADO_SIMULATION
        initial begin
            regMissIndex <= '0;
            regMissTag <= '0;
            regSerial <= '0;
        end
        `RSD_ASSERT_CLK(port.clk, $onehot0(we), "Signal we is not one-hot or 0.");
        `RSD_ASSERT_CLK(port.clk, $onehot0(hit), "Signal hit is not one-hot or 0.");
    `endif
`endif
    

endmodule
