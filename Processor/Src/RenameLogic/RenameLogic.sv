// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// RenameLogic
//

import BasicTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;


module RenameLogic (
    RenameLogicIF.RenameLogic port,
    ActiveListIF.RenameLogic activeList,
    RecoveryManagerIF.RenameLogic recovery
);

    logic allocatePhyReg [ RENAME_WIDTH ];
    PRegNumPath allocatedPhyRegNum [ RENAME_WIDTH ];

    logic allocatePhyScalarReg [ RENAME_WIDTH ];
    PScalarRegNumPath allocatedPhyScalarRegNum [ RENAME_WIDTH ];
    logic releasePhyScalarReg [ COMMIT_WIDTH ];
    PScalarRegNumPath releasedPhyScalarRegNum [ COMMIT_WIDTH ];
    ScalarFreeListCountPath scalarFreeListCount;

`ifdef RSD_MARCH_FP_PIPE
    logic allocatePhyScalarFPReg [ RENAME_WIDTH ];
    PScalarFPRegNumPath allocatedPhyScalarFPRegNum [ RENAME_WIDTH ];
    logic releasePhyScalarFPReg [ COMMIT_WIDTH ];
    PScalarFPRegNumPath releasedPhyScalarFPRegNum [ COMMIT_WIDTH ];
    ScalarFPFreeListCountPath scalarFPFreeListCount;
`endif

    ActiveListEntry alReadData [ COMMIT_WIDTH ];

    //
    // --- Free lists for registers.
    //
    MultiWidthFreeList #(
        .SIZE( SCALAR_FREE_LIST_ENTRY_NUM ),
        .ENTRY_BIT_SIZE( PSCALAR_NUM_BIT_WIDTH ),
        .PUSH_WIDTH( COMMIT_WIDTH ),
        .POP_WIDTH( RENAME_WIDTH ),
        .INITIAL_LENGTH( SCALAR_FREE_LIST_ENTRY_NUM )
    ) scalarFreeList (
        .clk( port.clk ),
        .rst( port.rst ),
        .rstStart( port.rstStart ),
        .count( scalarFreeListCount ),

        .pop( allocatePhyScalarReg ),
        .poppedData( allocatedPhyScalarRegNum ),

        .push( releasePhyScalarReg ),
        .pushedData( releasedPhyScalarRegNum )
    );

`ifdef RSD_MARCH_FP_PIPE
    MultiWidthFreeList #(
        .SIZE( SCALAR_FP_FREE_LIST_ENTRY_NUM ),
        .ENTRY_BIT_SIZE( PSCALAR_FP_NUM_BIT_WIDTH ),
        .PUSH_WIDTH( COMMIT_WIDTH ),
        .POP_WIDTH( RENAME_WIDTH ),
        .INITIAL_LENGTH( SCALAR_FP_FREE_LIST_ENTRY_NUM )
    ) scalarFPFreeList (
        .clk( port.clk ),
        .rst( port.rst ),
        .rstStart( port.rstStart ),
        .count( scalarFPFreeListCount ),

        .pop( allocatePhyScalarFPReg ),
        .poppedData( allocatedPhyScalarFPRegNum ),

        .push( releasePhyScalarFPReg ),
        .pushedData( releasedPhyScalarFPRegNum )
    );
`endif

    // Index address for recoverying the RMT by copying from the retirement RMT.
    LRegNumPath rmtRecoveryIndex;
    logic [LREG_NUM_BIT_WIDTH:0] rmtRecoveryCount;
    logic inRecoveryRMT;
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            rmtRecoveryCount <= 0;
            rmtRecoveryIndex <= 0;
        end
        else if (recovery.toRecoveryPhase) begin
            rmtRecoveryCount <= LREG_NUM;
            rmtRecoveryIndex <= 0;
        end
        else begin
            if(rmtRecoveryCount > COMMIT_WIDTH) begin
                rmtRecoveryCount <= rmtRecoveryCount - COMMIT_WIDTH;
            end
            else begin
                rmtRecoveryCount <= 0;
            end

            if (!RECOVERY_FROM_RRMT) begin
                rmtRecoveryIndex <= rmtRecoveryIndex + COMMIT_WIDTH;
            end
            else begin
                rmtRecoveryIndex <= rmtRecoveryIndex + RENAME_WIDTH;
            end
        end
    end

    // RMT control signals, which are generated in RenameLogic.
    logic [ COMMIT_WIDTH-1:0 ] rmtWriteReg;
    PRegNumPath  rmtWriteReg_PhyRegNum[ COMMIT_WIDTH ];
    LRegNumPath  rmtWriteReg_LogRegNum[ COMMIT_WIDTH ];

    // Write port for WAT
    logic watWriteReg[ COMMIT_WIDTH ];
    LRegNumPath watWriteLogRegNum[ COMMIT_WIDTH ];
    IssueQueueIndexPath  watWriteIssueQueuePtr[ COMMIT_WIDTH ];

    LRegNumPath retRMT_ReadReg_LogRegNum[RENAME_WIDTH];

    always_comb begin
        for (int i = 0; i < RENAME_WIDTH; i++) begin
            retRMT_ReadReg_LogRegNum[i] = '0;
        end

        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            // Don't care
            rmtWriteReg[i] = FALSE;
            rmtWriteReg_PhyRegNum[i] = '0;
            rmtWriteReg_LogRegNum[i] = '0;
        end

        // Destinations.
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
`ifdef RSD_MARCH_FP_PIPE
            allocatedPhyRegNum[i].isFP = port.logDstReg[i].isFP;
            allocatedPhyRegNum[i].regNum =
                (port.logDstReg[i].isFP ? allocatedPhyScalarFPRegNum[i] : allocatedPhyScalarRegNum[i]);
`else
            allocatedPhyRegNum[i].regNum = allocatedPhyScalarRegNum[i];
`endif
        end

        port.phyDstReg = allocatedPhyRegNum;

        // Whether rmt is in a recovery phase or not.
        inRecoveryRMT = RECOVERY_FROM_RRMT ? ( rmtRecoveryCount != 0 ) : recovery.inRecoveryAL;
        recovery.renameLogicRecoveryRMT = inRecoveryRMT;
        alReadData = activeList.readData;   //for RECOVERY_FROM_ACTIVE_LIST mode

        // Empty flag.
`ifdef RSD_MARCH_FP_PIPE
        port.allocatable =
            !inRecoveryRMT &&   // In a recovery mode, the front-end is stalled.
            (scalarFreeListCount >= RENAME_WIDTH) &&
            (scalarFPFreeListCount >= RENAME_WIDTH);
`else
        port.allocatable =
            !inRecoveryRMT &&   // In a recovery mode, the front-end is stalled.
            (scalarFreeListCount >= RENAME_WIDTH);
`endif

        // Allocation from the free lists.
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            allocatePhyReg[i] = port.updateRMT[i] && port.writeReg[i];

`ifdef RSD_MARCH_FP_PIPE
            allocatePhyScalarReg[i] = allocatePhyReg[i] && !port.logDstReg[i].isFP;
            allocatePhyScalarFPReg[i] = allocatePhyReg[i] && port.logDstReg[i].isFP;
`else
            allocatePhyScalarReg[i] = allocatePhyReg[i];
`endif
        end

        // Release to the free lists.
        for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
`ifdef RSD_MARCH_FP_PIPE
            releasePhyScalarReg[i] =
                port.releaseReg[i] && !port.phyReleasedReg[i].isFP;
            releasePhyScalarFPReg[i] =
                port.releaseReg[i] && port.phyReleasedReg[i].isFP;
            releasedPhyScalarFPRegNum[i] = port.phyReleasedReg[i].regNum;
`else
            releasePhyScalarReg[i] = port.releaseReg[i];
`endif
            releasedPhyScalarRegNum[i] = port.phyReleasedReg[i].regNum;
        end

        // Write control of RMTs.
        if( |port.updateRMT ) begin
            // Update the RMT.
            for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
                rmtWriteReg[i] = port.updateRMT[i] && port.writeReg[i];
                rmtWriteReg_PhyRegNum[i] = allocatedPhyRegNum[i];
                rmtWriteReg_LogRegNum[i] = port.logDstReg[i];
            end

            //Recovery-only write port
            for ( int i = RENAME_WIDTH; i < COMMIT_WIDTH; i++ ) begin
                rmtWriteReg[i] = FALSE;

            end
        end
        else if (inRecoveryRMT) begin
            if ( RECOVERY_FROM_RRMT ) begin
                // Copy from the retirement RMT in a recovery mode.
                for (int i = 0; i < RENAME_WIDTH; i++) begin
                    rmtWriteReg[i] = TRUE;
                    rmtWriteReg_PhyRegNum[i] = port.retRMT_ReadReg_PhyRegNum[i];
                    rmtWriteReg_LogRegNum[i] = rmtRecoveryIndex + i;
                    retRMT_ReadReg_LogRegNum[i] = rmtRecoveryIndex + i;
                end

                // RMTの書き込みポート数はコミット幅であるが，RRMTの読み出しポート数はリネーム幅のため，
                // RMTの巻き戻しは１サイクルにつきリネーム幅しか行えない．
                // したがって，RMTの空いた書き込みポートを落としておく．
                for (int i = RENAME_WIDTH; i < COMMIT_WIDTH; i++) begin
                    rmtWriteReg[i] = FALSE;
                    rmtWriteReg_PhyRegNum[i] = '0;
                    rmtWriteReg_LogRegNum[i] = '0;
                end
            end
            else begin //recovery from active list
                for (int i = 0; i < COMMIT_WIDTH; i++) begin
                    rmtWriteReg[i] = ( i < activeList.popTailNum ) ? TRUE : FALSE;
                    rmtWriteReg_PhyRegNum[i] = alReadData[i].phyPrevDstRegNum;
                    rmtWriteReg_LogRegNum[i] = alReadData[i].logDstRegNum;
                end
            end
        end

        // WAT
        // Not support for recovering from RRMT
        if (!inRecoveryRMT) begin
            // Get dependent instruction's issue queue pointer
            for (int i = 0; i < RENAME_WIDTH; i++) begin
                watWriteReg[i] = port.watWriteRegFromPipeReg[i];
                watWriteLogRegNum[i] = port.logDstReg[i];
                watWriteIssueQueuePtr[i] = port.watWriteIssueQueuePtrFromPipeReg[i];
            end

            // This is recovery dedicated port so fixed at NEGATIVE
            for (int i = RENAME_WIDTH; i < COMMIT_WIDTH; i++) begin
                watWriteReg[i] = '0;
                watWriteLogRegNum[i] = '0;
                watWriteIssueQueuePtr[i] = '0;
            end
        end
        else begin
            // Recovery WAT from activelist
            for (int i = 0; i < COMMIT_WIDTH; i++) begin
                // Whether recovery WAT (whether this instruction would write register)
                watWriteReg[i] =  ( i < activeList.popTailNum ) ? alReadData[i].writeReg : FALSE;
                // Information for recovering WAT
                watWriteLogRegNum[i] = alReadData[i].logDstRegNum;
                watWriteIssueQueuePtr[i] = alReadData[i].prevDependIssueQueuePtr;
            end
        end

        // Output
        port.rmtWriteReg = rmtWriteReg;
        port.rmtWriteReg_PhyRegNum = rmtWriteReg_PhyRegNum;
        port.rmtWriteReg_LogRegNum = rmtWriteReg_LogRegNum;

        port.watWriteReg = watWriteReg;
        port.watWriteLogRegNum = watWriteLogRegNum;
        port.watWriteIssueQueuePtr = watWriteIssueQueuePtr;
        port.retRMT_ReadReg_LogRegNum = retRMT_ReadReg_LogRegNum;
    end

endmodule : RenameLogic
