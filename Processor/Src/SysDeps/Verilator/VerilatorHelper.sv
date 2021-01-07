// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

// Parameters defined in SV are exported from VerilatorHelper package.
//
// Members in packed struct cannot be accessed from cpp test bench, 
// so we use proxy functions defined by several macros to access the members.
//
// * VerilatorHelper.sv
//   RSD_MAKE_STRUCT_ACCESSOR(typeName, memberTypeName, memberName)
//   This macros defines the following function
//      memberTypeName typeName_memberName(o) begin
//         return o.memberName
//      end
//
// * VerilatorHelper.h
//    #define RSD_MAKE_STRUCT_ACCESSOR(typeName, memberTypeName, memberName) \
//        d->memberName = h->DebugRegister_##memberName(r); \
//    This macro extracts a member value by using the macros defined in VerilatorHelper.sv 
//
//    GetDebugRegister function copies all the members in DebugRegister using the 
//    above macros.
// 
// * TestMain.cpp
//    It calls GetDebugRegister and extracts values in DebugRegister.
//    The extracted values are passed to Dumper.

package VerilatorHelper;

import DebugTypes::*;
import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import LoadStoreUnitTypes::*;
import PipelineTypes::*;
import MemoryMapTypes::*;

`define RSD_MAKE_PARAMETER(packageName, name) \
    localparam name /*verilator public*/ = packageName::name;

`RSD_MAKE_PARAMETER(MemoryMapTypes, PC_GOAL);
`RSD_MAKE_PARAMETER(MemoryMapTypes, PHY_ADDR_SECTION_0_BASE);
`RSD_MAKE_PARAMETER(MemoryMapTypes, PHY_ADDR_SECTION_1_BASE);

`RSD_MAKE_PARAMETER(BasicTypes, LSCALAR_NUM);
`RSD_MAKE_PARAMETER(BasicTypes, FETCH_WIDTH);
`RSD_MAKE_PARAMETER(BasicTypes, DECODE_WIDTH);
`RSD_MAKE_PARAMETER(BasicTypes, RENAME_WIDTH);
`RSD_MAKE_PARAMETER(BasicTypes, DISPATCH_WIDTH);
`RSD_MAKE_PARAMETER(BasicTypes, COMMIT_WIDTH);

`RSD_MAKE_PARAMETER(BasicTypes, INT_ISSUE_WIDTH);
`RSD_MAKE_PARAMETER(BasicTypes, COMPLEX_ISSUE_WIDTH);
`RSD_MAKE_PARAMETER(BasicTypes, MEM_ISSUE_WIDTH);

`RSD_MAKE_PARAMETER(SchedulerTypes, ISSUE_QUEUE_ENTRY_NUM);
`RSD_MAKE_PARAMETER(SchedulerTypes, COMPLEX_EXEC_STAGE_DEPTH);


`define RSD_MAKE_ENUM(packageName, name) \
    typedef packageName::name name /*verilator public*/;

`RSD_MAKE_ENUM(MicroOpTypes, MemMicroOpSubType);


`define RSD_MAKE_STRUCT_ACCESSOR(typeName, memberTypeName, memberName) \
    function automatic memberTypeName typeName``_``memberName(typeName e); \
        /*verilator public*/ \
        return e.memberName; \
    endfunction \


`RSD_MAKE_STRUCT_ACCESSOR(ActiveListEntry, logic, writeReg);
`RSD_MAKE_STRUCT_ACCESSOR(ActiveListEntry, LRegNumPath, logDstRegNum);
`RSD_MAKE_STRUCT_ACCESSOR(ActiveListEntry, PRegNumPath, phyDstRegNum);
`RSD_MAKE_STRUCT_ACCESSOR(ActiveListEntry, PC_Path, pc);

`RSD_MAKE_STRUCT_ACCESSOR(OpId, OpSerial, sid);
`RSD_MAKE_STRUCT_ACCESSOR(OpId, MicroOpIndex, mid);

`RSD_MAKE_STRUCT_ACCESSOR(PipelineControll, logic, stall);
`RSD_MAKE_STRUCT_ACCESSOR(PipelineControll, logic, clear);



`define RSD_MAKE_STRUCT_ACCESSOR_LV2(typeName, memberName0, member1TypeName, memberName1) \
    function automatic member1TypeName typeName``_``memberName0``_``memberName1(typeName e); \
        /*verilator public*/ \
        return e.memberName0.memberName1; \
    endfunction \

`define RSD_MAKE_STRUCT_ACCESSOR_ARRAY(typeName, memberTypeName, memberName) \
    task typeName``_``memberName(output memberTypeName o, input typeName e, input int i); \
        /*verilator public*/ \
        o = e.memberName[i]; \
    endtask \

`define RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(typeName, memberName0, member1TypeName, memberName1) \
    function automatic member1TypeName typeName``_``memberName0``_``memberName1(typeName e, int i); \
        /*verilator public*/ \
        return e.memberName0[i].memberName1; \
    endfunction \
    
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, npReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, npReg, OpSerial, sid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, ifReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, ifReg, OpSerial, sid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, ifReg, logic, flush);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, ifReg, logic, icMiss);

`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, pdReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, pdReg, OpSerial, sid);

`ifdef RSD_FUNCTIONAL_SIMULATION
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, pdReg, IntALU_Code, aluCode);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, pdReg, IntMicroOpSubType, opType);
`endif

`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, idReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, idReg, logic, flushed);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, idReg, logic, flushTriggering);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, idReg, OpId, opId);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, idReg, AddrPath, pc);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, idReg, InsnPath, insn);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, idReg, logic, undefined);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, idReg, logic, unsupported);

`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, rnReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, rnReg, OpId, opId);

`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, OpId, opId);

`ifdef RSD_FUNCTIONAL_SIMULATION
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, logic, readRegA);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, LRegNumPath, logSrcRegA);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, PRegNumPath, phySrcRegA);

`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, logic, readRegB);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, LRegNumPath, logSrcRegB);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, PRegNumPath, phySrcRegB);

`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, logic, writeReg);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, LRegNumPath, logDstReg);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, PRegNumPath, phyDstReg);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, PRegNumPath, phyPrevDstReg);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, IssueQueueIndexPath, issueQueuePtr);
`endif



`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intIsReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intIsReg, logic, flush);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intIsReg, OpId, opId);

`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intRrReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intRrReg, logic, flush);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intRrReg, OpId, opId);

`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, logic, flush);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, OpId, opId);
`ifdef RSD_FUNCTIONAL_SIMULATION
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, DataPath, dataOut);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, DataPath, fuOpA);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, DataPath, fuOpB);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, IntALU_Code, aluCode);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, IntMicroOpSubType, opType);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, logic, brPredMiss);
`endif



`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intRwReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intRwReg, logic, flush);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intRwReg, OpId, opId);


`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE

    `RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexIsReg, logic, valid);
    `RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexIsReg, logic, flush);
    `RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexIsReg, OpId, opId);

    `RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexRrReg, logic, valid);
    `RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexRrReg, logic, flush);
    `RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexRrReg, OpId, opId);

    // Output only the first execution stage of a complex pipeline
    `RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, logic, flush);
    //`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, logic [ COMPLEX_EXEC_STAGE_DEPTH-1:0 ], valid);
    //`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, logic [ COMPLEX_EXEC_STAGE_DEPTH-1:0 ], opId);
    function automatic logic DebugRegister_complexExReg_valid(DebugRegister e, int i);
        /*verilator public*/
        return e.complexExReg[i].valid[0];
    endfunction
    function automatic OpId DebugRegister_complexExReg_opId(DebugRegister e, int i);
        /*verilator public*/
        return e.complexExReg[i].opId[0];
    endfunction

    `ifdef RSD_FUNCTIONAL_SIMULATION
    `RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, DataPath, dataOut);
    `RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, DataPath, fuOpA);
    `RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, DataPath, fuOpB);
    //`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, VectorPath, vecDataOut);
    //`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, VectorPath, fuVecOpA);
    //`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, VectorPath, fuVecOpB);
    `endif

    `RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexRwReg, logic, valid);
    `RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexRwReg, logic, flush);
    `RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexRwReg, OpId, opId);

`endif // RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE



`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memIsReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memIsReg, logic, flush);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memIsReg, OpId, opId);

`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memRrReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memRrReg, logic, flush);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memRrReg, OpId, opId);

`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, logic, flush);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, OpId, opId);
`ifdef RSD_FUNCTIONAL_SIMULATION
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, AddrPath, addrOut);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, DataPath, fuOpA);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, DataPath, fuOpB);
//`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, VectorPath, fuVecOpB);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, MemMicroOpSubType, opType);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, MemAccessSizeType, size);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, logic, isSigned);
`endif



`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, logic, flush);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, OpId, opId);
`ifdef RSD_FUNCTIONAL_SIMULATION
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, logic, executeLoad);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, AddrPath, executedLoadAddr);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, logic, mshrAllocated);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, logic, mshrHit);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, DataPath, mshrEntryID);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, logic, executeStore);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, AddrPath, executedStoreAddr);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, DataPath, executedStoreData);
//`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, VectorPath, executedStoreVecData);
`endif

`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, maReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, maReg, logic, flush);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, maReg, OpId, opId);
`ifdef RSD_FUNCTIONAL_SIMULATION
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, maReg, logic, executeLoad);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, maReg, DataPath, executedLoadData);
//`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, maReg, VectorPath, executedLoadVecData);
`endif

`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memRwReg, logic, valid);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memRwReg, logic, flush);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memRwReg, OpId, opId);


`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, cmReg, logic, commit);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, cmReg, logic, flush);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, cmReg, OpId, opId);
`ifdef RSD_FUNCTIONAL_SIMULATION
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, cmReg, logic, releaseReg);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, cmReg, PRegNumPath, phyReleasedReg);
`endif

`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, scheduler, logic, valid);

`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, issueQueue, logic, flush);
`RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, issueQueue, OpId, opId);

`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, logic, toRecoveryPhase);
`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, ActiveListIndexPath, activeListHeadPtr);
`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, ActiveListCountPath, activeListCount);

`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, PipelineControll, npStagePipeCtrl);
`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, PipelineControll, ifStagePipeCtrl);
`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, PipelineControll, pdStagePipeCtrl);
`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, PipelineControll, idStagePipeCtrl);
`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, PipelineControll, rnStagePipeCtrl);
`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, PipelineControll, dsStagePipeCtrl);
`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, PipelineControll, backEndPipeCtrl);
`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, PipelineControll, cmStagePipeCtrl);
`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, logic, stallByDecodeStage);

`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, logic, loadStoreUnitAllocatable);
`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, logic, storeCommitterPhase);
`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, StoreQueueCountPath, storeQueueCount);
`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, logic, busyInRecovery);
`RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, logic, storeQueueEmpty);

`ifdef RSD_FUNCTIONAL_SIMULATION
`RSD_MAKE_STRUCT_ACCESSOR_LV2(DebugRegister, perfCounter, DataPath, numIC_Miss)
`RSD_MAKE_STRUCT_ACCESSOR_LV2(DebugRegister, perfCounter, DataPath, numLoadMiss)
`RSD_MAKE_STRUCT_ACCESSOR_LV2(DebugRegister, perfCounter, DataPath, numStoreMiss)
`RSD_MAKE_STRUCT_ACCESSOR_LV2(DebugRegister, perfCounter, DataPath, numStoreLoadForwardingFail)
`RSD_MAKE_STRUCT_ACCESSOR_LV2(DebugRegister, perfCounter, DataPath, numMemDepPredMiss)
`RSD_MAKE_STRUCT_ACCESSOR_LV2(DebugRegister, perfCounter, DataPath, numBranchPredMiss)
`RSD_MAKE_STRUCT_ACCESSOR_LV2(DebugRegister, perfCounter, DataPath, numBranchPredMissDetectedOnDecode)
`endif

endpackage


