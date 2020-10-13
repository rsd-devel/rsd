// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.



package CacheSystemTypes;

    import BasicTypes::*;
    import MemoryMapTypes::*;

    //
    // --- DCache
    //

    // Main cache parameters.
    // The remaining cache parameters must be fixed or calculated by the following
    // parameters.
    localparam DCACHE_WAY_NUM = 2;           // Way Num
    localparam DCACHE_INDEX_BIT_WIDTH = 9 - $clog2(DCACHE_WAY_NUM);   // The number of index bits
    localparam DCACHE_LINE_BYTE_NUM = 8;    // Line size
    localparam MSHR_NUM = 2;                 // The nubmer of MSHR entries.

    // Index bits
    localparam DCACHE_INDEX_NUM = 1 << DCACHE_INDEX_BIT_WIDTH;
    typedef logic [DCACHE_INDEX_BIT_WIDTH-1:0] DCacheIndexPath;

    // They number of the ports of tag/data array.
    localparam DCACHE_ARRAY_PORT_NUM = 2;    // Block ram has 2 ports.
    localparam DCACHE_ARRAY_PORT_NUM_BIT_WIDTH = $clog2(DCACHE_ARRAY_PORT_NUM);
    typedef logic [DCACHE_ARRAY_PORT_NUM_BIT_WIDTH-1 : 0] DCacheArrayPortIndex;

    // Line size
    localparam DCACHE_LINE_BYTE_NUM_BIT_WIDTH = $clog2(DCACHE_LINE_BYTE_NUM);
    localparam DCACHE_LINE_BIT_WIDTH = DCACHE_LINE_BYTE_NUM * 8;
    typedef logic [DCACHE_LINE_BIT_WIDTH-1:0] DCacheLinePath;

    typedef logic [DCACHE_LINE_BYTE_NUM-1:0] DCacheByteEnablePath;

    // Tag bits
    localparam DCACHE_TAG_BIT_WIDTH = 
        PHY_ADDR_WIDTH - DCACHE_INDEX_BIT_WIDTH - DCACHE_LINE_BYTE_NUM_BIT_WIDTH;
    typedef logic [DCACHE_TAG_BIT_WIDTH-1:0] DCacheTagPath;

    // Tag+Index bits
    typedef logic [PHY_ADDR_WIDTH-DCACHE_LINE_BYTE_NUM_BIT_WIDTH-1:0] DCacheLineAddr;

    typedef struct packed {
        logic valid;
        DCacheTagPath tag;
    } DCacheTagValidPath;

    // Way bits
    localparam DCACHE_WAY_BIT_NUM = (DCACHE_WAY_NUM != 1) ? $clog2(DCACHE_WAY_NUM)-1 : 0;
    typedef logic [DCACHE_WAY_BIT_NUM:0] DCacheWayPath;

    // NRU Access state bits
    // (N-way NRU -> N bits)
    // These bits correspond to the cache way:
    //   if bit[way] == 1 then the way is referenced recently
    typedef logic [DCACHE_WAY_NUM-1:0] DCacheNRUAccessStatePath;

    // Subset of index for MSHR identifier in ReplayQueue
    // This value MUST be less than or equal to DCACHE_INDEX_BIT_WIDTH.
    localparam DCACHE_INDEX_SUBSET_BIT_WIDTH = 5;
    typedef logic [DCACHE_INDEX_SUBSET_BIT_WIDTH-1:0] DCacheIndexSubsetPath;

    // Memory Access Serial
    // 同時にoutstanding可能なリードトランザクションの最大数を決める
    // D-Cacheからの要求の最大数はMSHR_NUM，I-Cacheからの要求は1，最大要求数はMSHR_NUM+1となる
    // 今後I-Cacheからの同時発行可能な要求数を増やすのであればここを変更
    // NOTE: if you modify this value, you need to modify 
    // MEMORY_AXI4_READ_ID_WIDTH in XilinxMacros.vh
    localparam MEM_ACCESS_SERIAL_BIT_SIZE = $clog2( MSHR_NUM+1 );
    typedef logic [MEM_ACCESS_SERIAL_BIT_SIZE-1 : 0] MemAccessSerial;

    // 同時にoutstanding可能なライトトランザクションの最大数を決める
    // D-Cacheからの要求の最大数はMSHR_NUMなので，最大要求数もMSHR_NUMとなる
    // NOTE: if you modify this value, you need to modify 
    // MEMORY_AXI4_WRITE_ID_WIDTH in XilinxMacros.vh
    localparam MEM_WRITE_SERIAL_BIT_SIZE = $clog2( MSHR_NUM );
    typedef logic [MEM_WRITE_SERIAL_BIT_SIZE-1 : 0] MemWriteSerial;

    //
    // MSHR
    //
    localparam MSHR_NUM_BIT_WIDTH = $clog2(MSHR_NUM);
    typedef logic [MSHR_NUM_BIT_WIDTH-1:0] MSHR_IndexPath;
    typedef logic [MSHR_NUM_BIT_WIDTH:0] MSHR_CountPath;

    typedef enum logic [3:0]
    {
        MSHR_PHASE_INVALID = 0,                   // This entry is invalid

        // Victim is read from the cache.
        MSHR_PHASE_VICTIM_REQEUST       = 1,      //
        MSHR_PHASE_VICTIM_RECEIVE_TAG   = 2,      //
        MSHR_PHASE_VICTIM_RECEIVE_DATA  = 3,      // Receive dirty data.
        MSHR_PHASE_VICTIM_WRITE_TO_MEM  = 4,      // Victim is written to a main memory.
        MSHR_PHASE_VICTIM_WRITE_COMPLETE = 5,     // Wait until victim writeback is complete.

        MSHR_PHASE_MISS_MERGE_STORE_DATA = 6,     // Merge the allocator store's data and the fetched line.

        MSHR_PHASE_MISS_READ_MEM_REQUEST = 7,     // Read from a main memory to a cache.
        MSHR_PHASE_MISS_READ_MEM_RECEIVE = 8,     // Read from a main memory to a cache.
        MSHR_PHASE_UNCACHABLE_WRITE_TO_MEM = 9,       // (Uncachable store) Write data to a main memory.
        MSHR_PHASE_UNCACHABLE_WRITE_COMPLETE = 10,    // (Uncachable store) Write data to a main memory.
        // MSHR_PHASE_MISS_WRITE_CACHE_REQUEST and MSHR_PHASE_MISS_HANDLING_COMPLETE 
        // must be the highest numbers in the following order.
        MSHR_PHASE_MISS_WRITE_CACHE_REQUEST = 11, // (Cachable load/store) Write data to a cache.
        MSHR_PHASE_MISS_HANDLING_COMPLETE = 12

    } MSHR_Phase;

    typedef struct packed   // MissStatusHandlingRegister;
    {
        logic valid;

        MSHR_Phase phase;

        logic victimDirty;
        logic victimValid;
        logic victimReceived;
        PhyAddrPath victimAddr;

        logic newValid;
        PhyAddrPath newAddr;

        MemAccessSerial memSerial; // Read request serial
        MemWriteSerial memWSerial; // Write request serial

        // Line data is shared by "new" and "victim".
        DCacheLinePath line;

        // An MSHR entry can be invalid when
        // its allocator is load and has bypassed data.
        logic canBeInvalid;

        // An MSHR entry which has been allocated by store must integrate the store's data into a fetched cache line.
        logic isAllocatedByStore;

        // TRUE if this is uncachable access.
        logic isUncachable;

        DCacheWayPath evictWay;
    } MissStatusHandlingRegister;

    typedef struct packed   // DCachePortMultiplexerIn
    {
        DCacheIndexPath indexIn;

        logic           tagWE;
        DCacheTagPath   tagDataIn;
        logic           tagValidIn;

        logic                   dataWE_OnTagHit;
        logic                   dataWE;
        DCacheLinePath          dataDataIn;
        DCacheByteEnablePath    dataByteWE;
        logic                   dataDirtyIn;

        // To notify MSHR that this request is by allocator load.
        logic           makeMSHRCanBeInvalid;

        DCacheWayPath   evictWay;
        logic           nruStateWE;
    } DCachePortMultiplexerIn;

    typedef struct packed   // DCachePortMultiplexerTagOut
    {
        DCacheTagPath   tagDataOut;
        logic           tagValidOut;
        logic           tagHit;
        logic           mshrConflict;
        logic           mshrAddrHit;
        MSHR_IndexPath  mshrAddrHitMSHRID;
        logic           mshrReadHit;
        DCacheLinePath  mshrReadData;
        DCacheWayPath   selectWay;
    } DCachePortMultiplexerTagOut;

    typedef struct packed   // DCachePortMultiplexerDataOut
    {
        DCacheLinePath  dataDataOut;
        logic           dataDirtyOut;
    } DCachePortMultiplexerDataOut;

    typedef struct packed   // MemoryPortMultiplexerIn
    {
        PhyAddrPath addr;
        DCacheLinePath data;
        logic we;
    } MemoryPortMultiplexerIn;

    typedef struct packed   // MemoryPortMultiplexerOut
    {
        logic ack;              // Request is accpeted or not.
        MemAccessSerial serial; // Request serial
        MemWriteSerial wserial; // Request serial
    } MemoryPortMultiplexerOut;


    // ports
    // Read: for load[LOAD_ISSUE_WIDTH], for store(commit), read victim[MSHR_NUM]
    // Write: WriteNew[MSHR_NUM];
    localparam DCACHE_LSU_READ_PORT_NUM = LOAD_ISSUE_WIDTH;
    localparam DCACHE_LSU_WRITE_PORT_NUM = 1;       // +1 for store commit.
    localparam DCACHE_LSU_PORT_NUM = DCACHE_LSU_READ_PORT_NUM + DCACHE_LSU_WRITE_PORT_NUM;

    localparam DCACHE_LSU_READ_PORT_BEGIN  = 0;
    localparam DCACHE_LSU_WRITE_PORT_BEGIN = DCACHE_LSU_READ_PORT_NUM;

    localparam DCACHE_MUX_PORT_NUM = DCACHE_LSU_PORT_NUM + MSHR_NUM;

    typedef logic [$clog2(DCACHE_MUX_PORT_NUM)-1:0] DCacheMuxPortIndexPath;


    //
    // --- ICache
    //

    // Main cache parameters.
    // The remaining cache parameters must be fixed or calculated by the following
    // parameters.
    localparam ICACHE_WAY_NUM = 2;           // Way Num
    localparam ICACHE_INDEX_BIT_WIDTH = 9 - $clog2(ICACHE_WAY_NUM);   // The number of index bits
    localparam ICACHE_LINE_BYTE_NUM = 8;    // Line size

    // Index bits
    localparam ICACHE_INDEX_NUM = 1 << ICACHE_INDEX_BIT_WIDTH;
    typedef logic [ICACHE_INDEX_BIT_WIDTH-1:0] ICacheIndexPath;

    // Line size
    localparam ICACHE_LINE_BYTE_NUM_BIT_WIDTH = $clog2(ICACHE_LINE_BYTE_NUM);
    localparam ICACHE_LINE_BIT_WIDTH = ICACHE_LINE_BYTE_NUM * 8;
    typedef logic [ICACHE_LINE_BIT_WIDTH-1:0] ICacheLinePath;

    // Line as insn list
    localparam ICACHE_LINE_INSN_NUM = ICACHE_LINE_BYTE_NUM / INSN_BYTE_WIDTH;
    typedef logic [$clog2(ICACHE_LINE_INSN_NUM)-1:0] ICacheLineInsnIndexPath;
    typedef logic [$clog2(ICACHE_LINE_INSN_NUM)  :0] ICacheLineInsnCountPath;
    typedef InsnPath [ICACHE_LINE_INSN_NUM-1:0] ICacheLineInsnPath;

    // Tag bits
    localparam ICACHE_TAG_BIT_WIDTH = 
        PHY_ADDR_WIDTH - ICACHE_INDEX_BIT_WIDTH - ICACHE_LINE_BYTE_NUM_BIT_WIDTH;
    typedef logic [ICACHE_TAG_BIT_WIDTH-1:0] ICacheTagPath;

    // Tag+Index bits
    typedef logic [PHY_ADDR_WIDTH - ICACHE_LINE_BYTE_NUM_BIT_WIDTH - 1:0] ICacheLineAddr;

    typedef struct packed {
        logic valid;
        ICacheTagPath tag;
    } ICacheTagValidPath;

    // Way bits
    typedef logic [$clog2(ICACHE_WAY_NUM)-1:0] ICacheWayPath;

    // NRU Access state bits
    // (N-way NRU -> N bits)
    // These bits correspond to the cache way:
    //   if bit[way] == 1 then the way is referenced recently
    typedef logic [ICACHE_WAY_NUM-1:0] NRUAccessStatePath;

    //
    // --- Memory Access
    //
    typedef struct packed {
        logic ack;              // Request is accpeted or not.
        MemAccessSerial serial; // Read request serial
        MemWriteSerial wserial; // Write request serial
    } MemAccessReqAck;

    typedef struct packed {
        logic valid;
        logic we;
        PhyAddrPath addr;
        DCacheLinePath data;
    } MemAccessReq;

    typedef struct packed {
        logic valid;
        PhyAddrPath addr;
    } MemReadAccessReq;

    typedef struct packed {
        logic valid;
        MemAccessSerial serial;
        DCacheLinePath data;
    } MemAccessResult;

    typedef struct packed {
        logic valid;
        MemWriteSerial serial;
    } MemAccessResponse;

endpackage
