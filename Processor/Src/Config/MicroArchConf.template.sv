// Copyright 2021- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

// Generated from Config/MicroArch.toml and Src/Config/MicroArchConf.template.sv.
// Edit the TOML settings or the template, not MicroArchConf.sv.
// Parameter meanings, units, and constraints are documented in the TOML.

package MicroArchConf;

// ---- Front-end
localparam CONF_FETCH_WIDTH = {{ FETCH_WIDTH }};

// These parameters cannot be changed and currently must be equal to FETCH_WIDTH.
localparam CONF_DECODE_WIDTH = CONF_FETCH_WIDTH;      // Decode width
localparam CONF_RENAME_WIDTH = CONF_FETCH_WIDTH;      // Rename width
localparam CONF_DISPATCH_WIDTH = CONF_FETCH_WIDTH;    // Dispatch width


// ---- Commit
localparam CONF_COMMIT_WIDTH = {{ COMMIT_WIDTH }};


// --- Back-end
localparam CONF_PSCALAR_NUM = {{ PSCALAR_NUM }};
localparam CONF_PSCALAR_FP_NUM = {{ PSCALAR_FP_NUM }};

localparam CONF_ISSUE_QUEUE_ENTRY_NUM = {{ ISSUE_QUEUE_ENTRY_NUM }};

localparam CONF_ACTIVE_LIST_ENTRY_NUM = {{ ACTIVE_LIST_ENTRY_NUM }};

localparam CONF_REPLAY_QUEUE_ENTRY_NUM = {{ REPLAY_QUEUE_ENTRY_NUM }};

// Build macros select the pipeline structure; the fallback also supports
// external consumers that compile the source manifest without Make.
`ifdef RSD_MARCH_INT_ISSUE_WIDTH
    localparam CONF_INT_ISSUE_WIDTH =`RSD_MARCH_INT_ISSUE_WIDTH;
`else
    localparam CONF_INT_ISSUE_WIDTH = {{ INT_ISSUE_WIDTH }};
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

// The issue width of fp pipelines.
`ifdef RSD_MARCH_FP_PIPE
    localparam CONF_FP_ISSUE_WIDTH = 1;
`else
    localparam CONF_FP_ISSUE_WIDTH = 0;
`endif

// --- Load store unit
localparam CONF_LOAD_QUEUE_ENTRY_NUM = {{ LOAD_QUEUE_ENTRY_NUM }};
localparam CONF_STORE_QUEUE_ENTRY_NUM = {{ STORE_QUEUE_ENTRY_NUM }};

// --- Predictors
// Branch predictor
localparam CONF_BTB_ENTRY_NUM = {{ BTB_ENTRY_NUM }};
localparam CONF_PHT_ENTRY_NUM = {{ PHT_ENTRY_NUM }};
localparam CONF_BRANCH_GLOBAL_HISTORY_BIT_WIDTH = {{ BRANCH_GLOBAL_HISTORY_BIT_WIDTH }};

// Memory dependency predictor
localparam CONF_MDT_ENTRY_NUM = {{ MDT_ENTRY_NUM }};


// --- D-cache
localparam CONF_DCACHE_WAY_NUM = {{ DCACHE_WAY_NUM }};

localparam CONF_DCACHE_INDEX_BIT_WIDTH = {{ DCACHE_INDEX_BIT_WIDTH_BASE }} - $clog2(CONF_DCACHE_WAY_NUM);

localparam CONF_DCACHE_LINE_BYTE_NUM = {{ DCACHE_LINE_BYTE_NUM }};

localparam CONF_DCACHE_MSHR_NUM = {{ DCACHE_MSHR_NUM }};


// --- I-cache
localparam CONF_ICACHE_WAY_NUM = {{ ICACHE_WAY_NUM }};

localparam CONF_ICACHE_INDEX_BIT_WIDTH = {{ ICACHE_INDEX_BIT_WIDTH_BASE }} - $clog2(CONF_ICACHE_WAY_NUM);

localparam CONF_ICACHE_LINE_BYTE_NUM = {{ ICACHE_LINE_BYTE_NUM }};


endpackage : MicroArchConf
