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
localparam BTB_TAG_HIGH_WIDTH = 3;
localparam BTB_TAG_LOW_WIDTH = 4;
localparam BTB_TAG_WIDTH = BTB_TAG_HIGH_WIDTH + BTB_TAG_LOW_WIDTH;
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
    BTB_BranchType brType;
} BTB_Entry;

// The predecessor supplies the set. The current fetch group supplies the tag and offset.
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
    PC_Path groupNumber;
    groupNumber = ToFetchGroupNumber(addr);
    // The predecessor supplies the set. Keep both nearby and distant successors distinguishable.
    tag.block = {groupNumber[$clog2(BTB_SET_NUM) +: BTB_TAG_HIGH_WIDTH], groupNumber[BTB_TAG_LOW_WIDTH-1:0]};
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

// Select Gshare (TRUE) or Bimodal (FALSE) for direction prediction.
localparam bit USE_GSHARE = TRUE;
localparam BRANCH_GLOBAL_HISTORY_BIT_WIDTH = CONF_BRANCH_GLOBAL_HISTORY_BIT_WIDTH;
typedef logic [BRANCH_GLOBAL_HISTORY_BIT_WIDTH-1 : 0] BranchGlobalHistoryPath;

// Mix the low five word-address bits of each taken branch into the path history.
function automatic BranchGlobalHistoryPath AdvanceTakenHistory(BranchGlobalHistoryPath history, PC_Path branchPC);
    return (history << 1) ^ BranchGlobalHistoryPath'(branchPC[INSN_ADDR_BIT_WIDTH +: 5]);
endfunction


//
// PHT
//

localparam PHT_ENTRY_NUM = CONF_PHT_ENTRY_NUM;
localparam PHT_ENTRY_NUM_BIT_WIDTH = $clog2(PHT_ENTRY_NUM);
typedef logic [PHT_ENTRY_NUM_BIT_WIDTH-1:0] PHT_IndexPath;

localparam PHT_ENTRY_WIDTH = 2;
localparam PHT_ENTRY_MAX = (1 << PHT_ENTRY_WIDTH) - 1;
typedef logic [PHT_ENTRY_WIDTH-1:0] PHT_EntryPath;


localparam PHT_QUEUE_SIZE = 4;


localparam PHT_ROW_NUM = PHT_ENTRY_NUM / FETCH_WIDTH;
typedef logic [$clog2(PHT_ROW_NUM > 1 ? PHT_ROW_NUM : 2)-1:0] PHT_RowIndexPath;
typedef logic [(FETCH_WIDTH > 1 ? $clog2(FETCH_WIDTH) : 1)-1:0] PHT_RowOffsetPath;

// Read the successor's counter group using the predecessor's PC and entry history.
function automatic PHT_RowIndexPath ToPHT_Row(PC_Path pc, BranchGlobalHistoryPath history);
    PHT_IndexPath index;
    index = PHT_IndexPath'(pc >> INSN_ADDR_BIT_WIDTH);
    index[PHT_ENTRY_NUM_BIT_WIDTH-1 -: BRANCH_GLOBAL_HISTORY_BIT_WIDTH] ^= history;
    return PHT_RowIndexPath'(index / FETCH_WIDTH);
endfunction

// After the row arrives, the current group's PC selects the order within each counter pair.
function automatic PHT_RowOffsetPath ToPHT_CounterOffset(PC_Path pc, PHT_RowOffsetPath groupOffset);
    if (FETCH_WIDTH == 1)
        return '0;
    return groupOffset ^ PHT_RowOffsetPath'(pc[11]);
endfunction

function automatic PHT_IndexPath ToPHT_TrainingIndex(PHT_RowIndexPath row, PC_Path branchPC);
    PHT_RowOffsetPath offset;
    offset = ToPHT_CounterOffset(branchPC, PHT_RowOffsetPath'(ToFetchGroupOffset(branchPC)));
    return PHT_IndexPath'(row * FETCH_WIDTH + offset);
endfunction

// Carry the predecessor's RAM addresses with this group's predictions for training.
typedef struct packed {
    logic valid;
    BTB_SetIndexPath btbSet;
    PHT_RowIndexPath phtRow;
} BranchLookupPath;

// Restart a successor with its entry history and the row read by its predecessor.
typedef struct packed {
    BranchGlobalHistoryPath history;
    BTB_SetIndexPath btbSet;
    PHT_RowIndexPath phtRow;
} BranchRecoveryPath;

typedef struct packed {
    logic valid;
    PC_Path pc;
    logic restorePredCtx;
    BranchRecoveryPath predCtx;
} FetchRedirectPath;

//
// Result/prediction
//

typedef struct packed // struct BranchResult
{
    PC_Path brAddr;     // The address of a executed branch.
    PC_Path nextAddr;   // The next address of a executed branch.
    logic execTaken;    // The execution result of a branch's direction.
    logic predTaken;    // The prediction result of a branch's direction.
    BTB_BranchType brType;
    logic mispred;      // Whether the prediction result of this branch is incorrect.
    logic btbHit;       // Tag hit at Fetch, even if Decode changed the target.
    BranchLookupPath brLookup;
    BTB_WayIndexPath btbHitWay;
    logic btbEntryCorrect;  // The hit entry needs no type or target update.
    logic valid;        // Whether this result is valid or not.

    BranchGlobalHistoryPath globalHistory;  // The global history of branches.
    PHT_EntryPath phtPrevValue;             // PHT's counter value
} BranchResult;

typedef struct packed // struct BranchPred
{
    PC_Path takenAddr;            // Selected target when predTaken is set.
    logic btbHit;
    BranchLookupPath brLookup;
    BTB_WayIndexPath btbHitWay;
    BTB_BranchType btbBrType;     // Original BTB classification for training.
    logic usedRAS;                // Fetch selected the RAS target.
    logic takenAddrChangedAtDecode; // Decode supplied the target on a redirect.
    logic predTaken;                        // result of bpred
    
    BranchGlobalHistoryPath globalHistory;  // The global history of branches.
    PHT_EntryPath phtPrevValue;             // PHT's counter value
} BranchPred;

endpackage : FetchUnitTypes
