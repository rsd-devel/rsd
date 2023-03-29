// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


// 
// --- Types related to a rename logic.
//

package RenameLogicTypes;

import MicroOpTypes::*;
import BasicTypes::*;
import LoadStoreUnitTypes::*;

//
// --- RMT
//

// RMTはint/fpで共通
localparam RMT_ENTRY_NUM = LREG_NUM;
localparam RMT_INDEX_BIT_SIZE = LREG_NUM_BIT_WIDTH;

`ifdef RSD_MARCH_FP_PIPE
localparam RMT_REG_OPERAND_NUM = 4;
`else
localparam RMT_REG_OPERAND_NUM = 3;
`endif

`ifdef RSD_MARCH_FP_PIPE
    // PRegNumPathの最上位ビットはint/fpを表すが、
    // そのビットはRMTに保存しない
    localparam RMT_ENTRY_BIT_SIZE = PREG_NUM_BIT_WIDTH - 1;
`else
    localparam RMT_ENTRY_BIT_SIZE = PREG_NUM_BIT_WIDTH;
`endif

//
// --- Free list
//
// 全ての物理レジスタは
// - 論理レジスタに割り当てられている
// - フリーリストに繋がれている
// のどちらかの状態にあるため、
//
// 物理レジスタ数＝論理レジスタ数＋フリーリストの長さ
//
// であり、これを移項することでフリーリストの長さを求める公式が得られる
//

// Free list for general (scalar) registers
localparam SCALAR_FREE_LIST_ENTRY_NUM = PSCALAR_NUM - LSCALAR_NUM;
localparam SCALAR_FREE_LIST_ENTRY_NUM_BIT_WIDTH =
    $clog2( SCALAR_FREE_LIST_ENTRY_NUM );
typedef logic [SCALAR_FREE_LIST_ENTRY_NUM_BIT_WIDTH-1:0] ScalarFreeListIndexPath;
typedef logic [SCALAR_FREE_LIST_ENTRY_NUM_BIT_WIDTH:0] ScalarFreeListCountPath;

// Free list for fp registers
localparam SCALAR_FP_FREE_LIST_ENTRY_NUM = PSCALAR_FP_NUM - LSCALAR_FP_NUM;
localparam SCALAR_FP_FREE_LIST_ENTRY_NUM_BIT_WIDTH =
    $clog2( SCALAR_FP_FREE_LIST_ENTRY_NUM );
typedef logic [SCALAR_FP_FREE_LIST_ENTRY_NUM_BIT_WIDTH-1:0] ScalarFPFreeListIndexPath;
typedef logic [SCALAR_FP_FREE_LIST_ENTRY_NUM_BIT_WIDTH:0] ScalarFPFreeListCountPath;


//
// -- Recovery Mode
//
localparam RECOVERY_FROM_RRMT = FALSE;
localparam RECOVERY_FROM_ACTIVE_LIST = TRUE;

endpackage
