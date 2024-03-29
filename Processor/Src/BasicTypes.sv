// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

package BasicTypes;

import MicroArchConf::*;


localparam TRUE  = 1'b1;
localparam FALSE = 1'b0;

// SID
localparam OP_SERIAL_WIDTH = 10;
typedef logic [OP_SERIAL_WIDTH-1:0] OpSerial;

// Byte
localparam BYTE_WIDTH = 8; // 1バイトのビット幅
typedef logic [ BYTE_WIDTH-1:0 ] BytePath;

// Instruction width
localparam INSN_WIDTH = 32;
typedef logic [INSN_WIDTH-1:0] InsnPath;

localparam INSN_BYTE_WIDTH = INSN_WIDTH / BYTE_WIDTH;
localparam INSN_ADDR_BIT_WIDTH = $clog2(INSN_BYTE_WIDTH);

// Address
localparam ADDR_WIDTH = 32;
localparam ADDR_WIDTH_BIT_SIZE = $clog2(ADDR_WIDTH);
localparam ADDR_BYTE_WIDTH = ADDR_WIDTH / BYTE_WIDTH;
typedef logic [ADDR_WIDTH-1:0] AddrPath;

// Data width
localparam DATA_WIDTH = 32;
localparam DATA_BYTE_WIDTH = DATA_WIDTH / BYTE_WIDTH;
localparam DATA_BYTE_WIDTH_BIT_SIZE = $clog2(DATA_BYTE_WIDTH);
typedef logic [DATA_WIDTH-1:0] DataPath;
typedef logic signed [DATA_WIDTH-1:0] SignedDataPath;
localparam DATA_MASK = 32'hffffffff;
localparam DATA_ZERO = 32'h00000000;

// Vector Data width
localparam VEC_WIDTH = 128;
localparam VEC_WORD_WIDTH = VEC_WIDTH / DATA_WIDTH;
localparam VEC_BYTE_WIDTH = VEC_WIDTH / BYTE_WIDTH;
localparam VEC_BYTE_WIDTH_BIT_SIZE = $clog2(VEC_BYTE_WIDTH);
localparam VEC_ADDR_MASK = 32'hfffffff0; // 下位VEC_BYTE_WIDTH_BIT_SIZEビットが0
typedef logic [VEC_WIDTH-1:0] VectorPath;

//
// --- Register File
//

// Logical register number width
localparam LSCALAR_NUM = 32;
localparam LSCALAR_NUM_BIT_WIDTH = $clog2( LSCALAR_NUM );
typedef logic [LSCALAR_NUM_BIT_WIDTH-1:0] LScalarRegNumPath;

// Physical register number width
localparam PSCALAR_NUM = CONF_PSCALAR_NUM;
localparam PSCALAR_NUM_BIT_WIDTH = $clog2( PSCALAR_NUM );
typedef logic [PSCALAR_NUM_BIT_WIDTH-1:0] PScalarRegNumPath;

// Logical fp register number width
localparam LSCALAR_FP_NUM = 32;
localparam LSCALAR_FP_NUM_BIT_WIDTH = $clog2( LSCALAR_FP_NUM );
typedef logic [LSCALAR_FP_NUM_BIT_WIDTH-1:0] LScalarFPRegNumPath;

// Physical fp register number width
localparam PSCALAR_FP_NUM = CONF_PSCALAR_FP_NUM;
localparam PSCALAR_FP_NUM_BIT_WIDTH = $clog2( PSCALAR_FP_NUM );
typedef logic [PSCALAR_FP_NUM_BIT_WIDTH-1:0] PScalarFPRegNumPath;

// Logical general register ( scalar int register + fp register) number width
`ifdef RSD_MARCH_FP_PIPE
localparam LREG_NUM = LSCALAR_NUM + LSCALAR_FP_NUM;
`else
localparam LREG_NUM = LSCALAR_NUM;
`endif
localparam LREG_NUM_BIT_WIDTH = $clog2( LREG_NUM );
typedef struct packed { // LRegNumPath
`ifdef RSD_MARCH_FP_PIPE
    logic isFP; // If TRUE, the register is for FP.
    logic [ LREG_NUM_BIT_WIDTH-2:0 ] regNum;
`else
    logic [ LREG_NUM_BIT_WIDTH-1:0 ] regNum;
`endif
} LRegNumPath;

// Physical general register ( scalar int register + fp register ) number width
`ifdef RSD_MARCH_FP_PIPE
localparam PREG_NUM = PSCALAR_NUM + PSCALAR_FP_NUM;
localparam PREG_NUM_BIT_WIDTH = $clog2( PREG_NUM );
typedef struct packed { // PRegNumPath
    logic isFP; // If TRUE, the register is for FP.
    logic [ PREG_NUM_BIT_WIDTH-2:0 ] regNum;
} PRegNumPath;
`else
localparam PREG_NUM = PSCALAR_NUM;
localparam PREG_NUM_BIT_WIDTH = $clog2( PREG_NUM );
typedef struct packed { // PRegNumPath
    logic [ PREG_NUM_BIT_WIDTH-1:0 ] regNum;
} PRegNumPath;
`endif


//
// --- Pipeline
//

// Fetch width
localparam FETCH_WIDTH = CONF_FETCH_WIDTH;
localparam FETCH_WIDTH_BIT_SIZE = $clog2( FETCH_WIDTH ); // log2(FETCH_WIDTH)
typedef logic [ FETCH_WIDTH_BIT_SIZE-1:0 ] FetchLaneIndexPath;

// Decode width
localparam DECODE_WIDTH = FETCH_WIDTH;
localparam DECODE_WIDTH_BIT_SIZE = FETCH_WIDTH_BIT_SIZE; // log2(DECODE_WIDTH)
typedef logic [ DECODE_WIDTH_BIT_SIZE-1:0 ] DecodeLaneIndexPath;

// Rename width
localparam RENAME_WIDTH = FETCH_WIDTH;
localparam RENAME_WIDTH_BIT_SIZE = FETCH_WIDTH_BIT_SIZE; // log2(RENAME_WIDTH)
typedef logic [ RENAME_WIDTH_BIT_SIZE-1:0 ] RenameLaneIndexPath;
typedef logic unsigned [ $clog2(RENAME_WIDTH):0 ] RenameLaneCountPath;

// Dispatch width
localparam DISPATCH_WIDTH = FETCH_WIDTH;
localparam DISPATCH_WIDTH_BIT_SIZE = FETCH_WIDTH_BIT_SIZE; // log2(DISPATCH_WIDTH)
typedef logic [ DISPATCH_WIDTH_BIT_SIZE-1:0 ] DispatchLaneIndexPath;

// Issue width
localparam INT_ISSUE_WIDTH = CONF_INT_ISSUE_WIDTH;
localparam INT_ISSUE_WIDTH_BIT_SIZE = 1; // log2(INT_ISSUE_WIDTH)
typedef logic [ INT_ISSUE_WIDTH_BIT_SIZE-1:0 ] IntIssueLaneIndexPath;
typedef logic unsigned [ $clog2(INT_ISSUE_WIDTH):0 ] IntIssueLaneCountPath;

localparam MULDIV_ISSUE_WIDTH = 1;
localparam MULDIV_STAGE_DEPTH = 3;

localparam COMPLEX_ISSUE_WIDTH = CONF_COMPLEX_ISSUE_WIDTH;
localparam COMPLEX_ISSUE_WIDTH_BIT_SIZE = 1; // log2(COMPLEX_ISSUE_WIDTH)
typedef logic [ COMPLEX_ISSUE_WIDTH_BIT_SIZE-1:0 ] ComplexIssueLaneIndexPath;
typedef logic unsigned [ $clog2(COMPLEX_ISSUE_WIDTH):0 ] ComplexIssueLaneCountPath;

localparam LOAD_ISSUE_WIDTH = CONF_LOAD_ISSUE_WIDTH;
localparam STORE_ISSUE_WIDTH = CONF_STORE_ISSUE_WIDTH;
localparam MEM_ISSUE_WIDTH = CONF_MEM_ISSUE_WIDTH;
localparam STORE_ISSUE_LANE_BEGIN = CONF_STORE_ISSUE_LANE_BEGIN;   // Load and store share the same lanes


localparam MEM_ISSUE_WIDTH_BIT_SIZE = 1; // log2(MEM_ISSUE_WIDTH)
typedef logic [ MEM_ISSUE_WIDTH_BIT_SIZE-1:0 ] MemIssueLaneIndexPath;
typedef logic unsigned [ $clog2(MEM_ISSUE_WIDTH):0 ] MemIssueLaneCountPath;

localparam FP_DIVSQRT_ISSUE_WIDTH = 1;
localparam FP_ISSUE_WIDTH = CONF_FP_ISSUE_WIDTH;
localparam FP_ISSUE_WIDTH_BIT_SIZE = (FP_ISSUE_WIDTH == 1) ? 1 : $clog2(FP_ISSUE_WIDTH);
`ifdef RSD_MARCH_FP_PIPE
typedef logic [ FP_ISSUE_WIDTH_BIT_SIZE-1:0 ] FPIssueLaneIndexPath;
typedef logic unsigned [ $clog2(FP_ISSUE_WIDTH):0 ] FPIssueLaneCountPath;
`endif

localparam ISSUE_WIDTH = INT_ISSUE_WIDTH + COMPLEX_ISSUE_WIDTH + MEM_ISSUE_WIDTH + FP_ISSUE_WIDTH;
localparam ISSUE_WIDTH_BIT_SIZE = $clog2(ISSUE_WIDTH); // log2(ISSUE_WIDTH)
typedef logic [ ISSUE_WIDTH_BIT_SIZE-1:0 ] IssueLaneIndexPath;
typedef logic unsigned [ ISSUE_WIDTH_BIT_SIZE:0 ] IssueLaneCountPath;

// Commit width
localparam COMMIT_WIDTH = CONF_COMMIT_WIDTH;     //must be more than RENAME_WIDTH for recovery
localparam COMMIT_WIDTH_BIT_SIZE = $clog2(COMMIT_WIDTH); // log2(COMMIT_WIDTH)
typedef logic [ COMMIT_WIDTH_BIT_SIZE-1:0 ] CommitLaneIndexPath;
typedef logic unsigned [ COMMIT_WIDTH_BIT_SIZE:0 ] CommitLaneCountPath;


// Complex Pipeline depth
localparam COMPLEX_EXEC_STAGE_DEPTH = 3;

// FP Pipeline depth
localparam FP_EXEC_STAGE_DEPTH = 5;

//
// --- Op
//
typedef struct packed // OpSrc
{
    PRegNumPath phySrcRegNumA;
    PRegNumPath phySrcRegNumB;
`ifdef RSD_MARCH_FP_PIPE
    PRegNumPath phySrcRegNumC;
`endif
} OpSrc;

typedef struct packed // OpDst
{
    logic writeReg;
    PRegNumPath phyDstRegNum;
} OpDst;


//
// --- Physical register data
//
localparam PREG_DATA_WIDTH = DATA_WIDTH + 1; // +1 is for a valid flag.
typedef struct packed 
{
    logic valid;
    DataPath data;
} PRegDataPath;

//
// --- Shifter
//
localparam SHIFTER_WIDTH = 12;
localparam RISCV_SHIFTER_WIDTH = 30;
typedef logic [ RISCV_SHIFTER_WIDTH-1:0 ] ShifterPath;

localparam SHIFT_AMOUNT_BIT_SIZE = 5;
typedef logic [SHIFT_AMOUNT_BIT_SIZE-1:0] ShiftAmountPath;

//
// --- Interrupt
//
localparam RSD_EXTERNAL_INTERRUPT_CODE_WIDTH = 5;
typedef logic [RSD_EXTERNAL_INTERRUPT_CODE_WIDTH-1:0] ExternalInterruptCodePath;


endpackage

