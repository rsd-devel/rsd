// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


// 
// --- Fetch unit types
//

package FetchUnitTypes;

import MicroArchConf::*;
import BasicTypes::*;
import MemoryMapTypes::*;

//
// BTB
//

localparam FETCH_GROUP_BYTE_NUM = FETCH_WIDTH * INSN_BYTE_WIDTH;
localparam BTB_ENTRY_NUM = CONF_BTB_ENTRY_NUM;

// The two-way replacement policy allocates the way opposite the last write to the set.
localparam BTB_WAY_NUM = 2;
localparam BTB_SET_NUM = BTB_ENTRY_NUM / BTB_WAY_NUM;
localparam BTB_TAG_WIDTH = 4;
localparam BTB_CONTENTS_ADDR_WIDTH = 13;

typedef logic [(BTB_SET_NUM > 1 ? $clog2(BTB_SET_NUM) : 1)-1:0] BTB_SetIndexPath;
typedef logic [$clog2(BTB_WAY_NUM)-1:0] BTB_WayIndexPath;
typedef logic [(FETCH_WIDTH > 1 ? $clog2(FETCH_WIDTH) : 1)-1:0] BTB_OffsetPath;
typedef logic [BTB_CONTENTS_ADDR_WIDTH-1:0] BTB_AddrPath;

typedef struct packed {
    logic [BTB_TAG_WIDTH-1:0] block; // Partial tag of the aligned fetch group.
    BTB_OffsetPath offset;            // Instruction position within that group.
} BTB_Tag;

localparam BTB_QUEUE_SIZE = 4;
localparam BTB_QUEUE_SIZE_BIT_WIDTH = $clog2(BTB_QUEUE_SIZE);
typedef logic [BTB_QUEUE_SIZE_BIT_WIDTH-1:0] BTBQueuePointerPath;

typedef struct packed {
    BTB_Tag tag;
    BTB_AddrPath data;
    logic isCondBr;
} BTB_Entry;

// The BTB takes its set and partial tag from the fetch group number.
function automatic PC_Path ToFetchGroupNumber(PC_Path addr);
    return addr / FETCH_GROUP_BYTE_NUM;
endfunction

// Byte address of the first instruction in the fetch group.
function automatic PC_Path ToFetchGroupBase(PC_Path addr);
    return addr & ~PC_Path'(FETCH_GROUP_BYTE_NUM - 1);
endfunction

function automatic BTB_OffsetPath ToFetchGroupOffset(PC_Path addr);
    return BTB_OffsetPath'((addr >> INSN_ADDR_BIT_WIDTH) % FETCH_WIDTH);
endfunction

function automatic BTB_SetIndexPath ToBTB_Set(PC_Path addr);
    return BTB_SetIndexPath'(ToFetchGroupNumber(addr) % BTB_SET_NUM);
endfunction

function automatic BTB_Tag ToBTB_Tag(PC_Path addr);
    BTB_Tag tag;
    tag.block = BTB_TAG_WIDTH'(ToFetchGroupNumber(addr) >> $clog2(BTB_SET_NUM));
    tag.offset = ToFetchGroupOffset(addr);
    return tag;
endfunction

function automatic BTB_AddrPath ToBTB_Addr(PC_Path addr);
    return addr[
        INSN_ADDR_BIT_WIDTH + BTB_CONTENTS_ADDR_WIDTH - 1:
        INSN_ADDR_BIT_WIDTH
    ];
endfunction

function automatic PC_Path ToRawAddrFromBTB_Addr(BTB_AddrPath addr, PC_Path pc);
    return 
    {
        pc[PC_WIDTH-1 : BTB_CONTENTS_ADDR_WIDTH + 2],
        addr[BTB_CONTENTS_ADDR_WIDTH-1 : 0],
        2'b0
    };
endfunction


//
// GShare
//

localparam BRANCH_GLOBAL_HISTORY_BIT_WIDTH = CONF_BRANCH_GLOBAL_HISTORY_BIT_WIDTH;
typedef logic [BRANCH_GLOBAL_HISTORY_BIT_WIDTH-1 : 0] BranchGlobalHistoryPath;


//
// PHT
//

localparam PHT_ENTRY_NUM = CONF_PHT_ENTRY_NUM;
localparam PHT_ENTRY_NUM_BIT_WIDTH = $clog2(PHT_ENTRY_NUM);
typedef logic [PHT_ENTRY_NUM_BIT_WIDTH-1:0] PHT_IndexPath;

localparam PHT_ENTRY_WIDTH = 2;
localparam PHT_ENTRY_MAX = (1 << PHT_ENTRY_WIDTH) - 1;
typedef logic [PHT_ENTRY_WIDTH-1:0] PHT_EntryPath;


localparam PHT_QUEUE_SIZE = 32;
localparam PHT_QUEUE_SIZE_BIT_WIDTH = $clog2(PHT_QUEUE_SIZE);
typedef logic [PHT_QUEUE_SIZE_BIT_WIDTH-1:0] PhtQueuePointerPath;

typedef struct packed // struct PhtQueueEntry
{
    AddrPath phtWA;            // Write Address
    PHT_EntryPath phtWV;                        // result of bpred
} PhtQueueEntry;


//
// Result/prediction
//

typedef struct packed // struct BranchResult
{
    PC_Path brAddr;     // The address of a executed branch.
    PC_Path nextAddr;   // The next address of a executed branch.
    logic execTaken;    // The execution result of a branch's direction.
    logic predTaken;    // The prediction result of a branch's direction.
    logic isCondBr;     // Whether this branch is conditional one or not.
    logic mispred;      // Whether the prediction result of this branch is incorrect.
    logic btbHit;       // Tag hit at Fetch, even if Decode changed the target.
    BTB_WayIndexPath btbHitWay;
    logic btbTargetCorrect; // A BTB hit supplied the resolved target.
    logic valid;        // Whether this result is valid or not.

    BranchGlobalHistoryPath globalHistory;  // The global history of branches.
    PHT_EntryPath phtPrevValue;             // PHT's counter value
} BranchResult;

typedef struct packed // struct BranchPred
{
    PC_Path takenAddr;            // Predicted taken target, independent of the predicted direction.
    logic btbHit;
    BTB_WayIndexPath btbHitWay;
    logic takenAddrChangedAtDecode; // Decode replaced the taken address supplied by Fetch.
    logic predTaken;                        // result of bpred
    
    BranchGlobalHistoryPath globalHistory;  // The global history of branches.
    PHT_EntryPath phtPrevValue;             // PHT's counter value
} BranchPred;

endpackage : FetchUnitTypes
