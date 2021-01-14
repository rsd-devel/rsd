// Copyright 2021- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


package MicroArchConf;

// ---- Front-end
// Fetch width (instructions). This parameter is configurable.
localparam CONF_FETCH_WIDTH = 2;

// These parameters cannot be changed and currently must be equal to FETCH_WIDTH.
localparam CONF_DECODE_WIDTH = CONF_FETCH_WIDTH;      // Decode width
localparam CONF_RENAME_WIDTH = CONF_FETCH_WIDTH;      // Rename width
localparam CONF_DISPATCH_WIDTH = CONF_FETCH_WIDTH;    // Dispatch width


// ---- Commit
// Commit width (instructions). This parameter is configurable.
// must be equal or larger than RENAME_WIDTH (FETCH_WIDTH) for recovery
localparam CONF_COMMIT_WIDTH = 2;     


// --- Back-end
// The number of physical registers
localparam CONF_PSCALAR_NUM = 64;

// The number of issue-queue entries
localparam CONF_ISSUE_QUEUE_ENTRY_NUM = 16;

// The number of active-list (ROB: reorder buffer) entries
localparam CONF_ACTIVE_LIST_ENTRY_NUM = 64;

// The number of replay-queue entries
localparam CONF_REPLAY_QUEUE_ENTRY_NUM = 20;

// The following macros can be defined from outside this file.
//  (e.g., CoreSources.mk or SynthesisMacros.sv)
// * RSD_MARCH_INT_ISSUE_WIDTH=N:       Set integer issue width to N
// * RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE: Integrate mul/div to a memory pipe
// * RSD_MARCH_UNIFIED_LDST_MEM_PIPE:   Use unified LS/ST pipeline

// The issue width of integer pipelines.
// CONF_INT_ISSUE_WIDTH must be 1 or 2
`ifdef RSD_MARCH_INT_ISSUE_WIDTH
    localparam CONF_INT_ISSUE_WIDTH =`RSD_MARCH_INT_ISSUE_WIDTH;
`else
    localparam CONF_INT_ISSUE_WIDTH = 2;
`endif

// The issue width of complex pipelines.
// CONF_COMPLEX_ISSUE_WIDTH must be zero or one and cannot be changed manually.
`ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    localparam CONF_COMPLEX_ISSUE_WIDTH = 0;
`else
    localparam CONF_COMPLEX_ISSUE_WIDTH = 1;
`endif

// The issue width of memory pipelines.
// These parameters cannot be changed manually.
localparam CONF_LOAD_ISSUE_WIDTH = 1;       // must be 1
localparam CONF_STORE_ISSUE_WIDTH = 1;      // must be 1
`ifdef RSD_MARCH_UNIFIED_LDST_MEM_PIPE
    localparam CONF_MEM_ISSUE_WIDTH = 1;
    localparam CONF_STORE_ISSUE_LANE_BEGIN = 0;   // Load and store share the same lane
`else
    localparam CONF_MEM_ISSUE_WIDTH = 2;
    localparam CONF_STORE_ISSUE_LANE_BEGIN = CONF_LOAD_ISSUE_WIDTH;    // Store uses a dedicated lane
`endif


// --- Load store unit
// These parameters must be a power of two.
localparam CONF_LOAD_QUEUE_ENTRY_NUM = 16;  // The size of a load queue
localparam CONF_STORE_QUEUE_ENTRY_NUM = 16; // The size of a store queue

// --- Predictors
// Branch predictor
localparam CONF_BTB_ENTRY_NUM = 1024;
localparam CONF_PHT_ENTRY_NUM = 2048;
localparam CONF_BRANCH_GLOBAL_HISTORY_BIT_WIDTH = 10;   // Global history length for g-share 

// Memory dependency predictor
localparam CONF_MDT_ENTRY_NUM = 1024;   // The number of prediction table entries.


// --- D-cache
// Total capacity = CONF_DCACHE_WAY_NUM * 2^CONF_DCACHE_INDEX_BIT_WIDTH * CONF_DCACHE_LINE_BYTE_NUM
// The number of ways in a single set
// This parameter must be a power of two. 1 is OK.
localparam CONF_DCACHE_WAY_NUM = 2;

// The number of index bits
localparam CONF_DCACHE_INDEX_BIT_WIDTH = 9 - $clog2(CONF_DCACHE_WAY_NUM);   

// Line size. This parameter must be a power of two.
localparam CONF_DCACHE_LINE_BYTE_NUM = 8;     

// The number of MSHR entries.
localparam CONF_DCACHE_MSHR_NUM = 2;   


// --- I-cache
// The number of ways in a single set
// This parameter must be a power of two. It must be larger than 1.
localparam CONF_ICACHE_WAY_NUM = 2;

// The number of index bits
localparam CONF_ICACHE_INDEX_BIT_WIDTH = 9 - $clog2(CONF_ICACHE_WAY_NUM);

// Line size. This parameter must be a power of two.
localparam CONF_ICACHE_LINE_BYTE_NUM = 8;    // Line size


endpackage : MicroArchConf

