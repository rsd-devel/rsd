// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Debug
//

import BasicTypes::*;
import MemoryMapTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import LoadStoreUnitTypes::*;
import PipelineTypes::*;
import DebugTypes::*;

module Debug (
    DebugIF.Debug port,
    output PC_Path lastCommittedPC
);

`ifndef RSD_DISABLE_DEBUG_REGISTER
    DebugRegister next;
    
    always_comb begin
        // Signal from each stage
        for ( int i = 0; i < FETCH_WIDTH; i++ ) begin
            next.npReg[i] = port.npReg[i];
            next.ifReg[i] = port.ifReg[i];
        end
        for ( int i = 0; i < DECODE_WIDTH; i++ ) begin
            next.idReg[i] = port.idReg[i];
        end
        for ( int i = 0; i < DECODE_WIDTH; i++ ) begin
            next.pdReg[i] = port.pdReg[i];
        end
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            next.rnReg[i] = port.rnReg[i];
        end
        for ( int i = 0; i < DISPATCH_WIDTH; i++ ) begin
            next.dsReg[i] = port.dsReg[i];
        end
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            next.intIsReg[i] = port.intIsReg[i];
            next.intRrReg[i] = port.intRrReg[i];
            next.intExReg[i] = port.intExReg[i];
            next.intRwReg[i] = port.intRwReg[i];
        end

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            next.complexIsReg[i] = port.complexIsReg[i];
            next.complexRrReg[i] = port.complexRrReg[i];
            next.complexExReg[i] = port.complexExReg[i];
            next.complexRwReg[i] = port.complexRwReg[i];
        end
`endif
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            next.memIsReg[i] = port.memIsReg[i];
            next.memRrReg[i] = port.memRrReg[i];
            next.memExReg[i] = port.memExReg[i];
            next.maReg[i] = port.maReg[i];
            next.mtReg[i] = port.mtReg[i];
            next.memRwReg[i] = port.memRwReg[i];
        end
`ifdef RSD_MARCH_FP_PIPE
        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            next.fpIsReg[i] = port.fpIsReg[i];
            next.fpRrReg[i] = port.fpRrReg[i];
            next.fpExReg[i] = port.fpExReg[i];
            next.fpRwReg[i] = port.fpRwReg[i];
        end
`endif
        for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
            next.cmReg[i] = port.cmReg[i];
        end
        
        for ( int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++ ) begin
            next.scheduler[i]  = port.scheduler[i];
            next.issueQueue[i] = port.issueQueue[i];
        end

        next.toRecoveryPhase = port.toRecoveryPhase;
        next.activeListHeadPtr = port.activeListHeadPtr;
        next.activeListCount = port.activeListCount;
        
        // PipelineControl
        next.npStagePipeCtrl = port.npStagePipeCtrl;
        next.ifStagePipeCtrl = port.ifStagePipeCtrl;
        next.pdStagePipeCtrl = port.pdStagePipeCtrl;
        next.idStagePipeCtrl = port.idStagePipeCtrl;
        next.rnStagePipeCtrl = port.rnStagePipeCtrl;
        next.dsStagePipeCtrl = port.dsStagePipeCtrl;
        next.backEndPipeCtrl = port.backEndPipeCtrl;
        next.cmStagePipeCtrl = port.cmStagePipeCtrl;
        next.stallByDecodeStage = port.stallByDecodeStage;
        
        // last committed PC
        lastCommittedPC = port.lastCommittedPC;
        
        // Others
        next.loadStoreUnitAllocatable = port.loadStoreUnitAllocatable;
        next.storeCommitterPhase = port.storeCommitterPhase;
        next.storeQueueCount = port.storeQueueCount;
        next.busyInRecovery = port.busyInRecovery;
        next.storeQueueEmpty = port.storeQueueEmpty;

`ifdef RSD_FUNCTIONAL_SIMULATION
        // Performance monitoring counters are exported to DebugRegister only on simulation.
        next.perfCounter = port.perfCounter;
`endif
    end

    DebugRegister debugRegister;
    always_ff @(posedge port.clk) begin
        debugRegister <= next;
    end
    
    always_comb begin
        port.debugRegister = debugRegister;
    end
`else
    always_comb begin
        port.debugRegister = FALSE; // Suppressing warning.
    end
`endif
endmodule : Debug
