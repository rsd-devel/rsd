// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Commit/recovery logic related to a rename logic.
//

`include "BasicMacros.sv"

import BasicTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;


module RenameLogicCommitter(
    RenameLogicIF.RenameLogicCommitter port,
    ActiveListIF.RenameLogicCommitter activeList,
    RecoveryManagerIF.RenameLogicCommitter recovery
);
    // State machine
    typedef enum logic[1:0]
    {
        PHASE_COMMIT = 0,
        PHASE_RECOVER_0 = 1,
        PHASE_RECOVER_1 = 2
    } Phase;
    Phase phase;
    Phase nextPhase;

    ActiveListCountPath recoveryCount;
    ActiveListCountPath nextRecoveryCount;

    always_ff@( posedge port.clk ) begin
        phase <= nextPhase;
        recoveryCount <= nextRecoveryCount;
    end

    `RSD_ASSERT_CLK(port.clk, !(recovery.toRecoveryPhase && phase != PHASE_COMMIT), "");

    // State machine
    always_comb begin

        if(port.rst) begin
            nextPhase = PHASE_COMMIT;
            nextRecoveryCount = 0;
        end
        else if (recovery.toRecoveryPhase) begin
            // Trigger a recovery mode.
            nextPhase = PHASE_RECOVER_0;
            nextRecoveryCount = 0;
        end
        else if(phase == PHASE_RECOVER_0) begin
            // In the first step of recovery, count the number of ops in the active list.
            nextPhase = PHASE_RECOVER_1;
            nextRecoveryCount = activeList.recoveryEntryNum;
        end
        else if(phase == PHASE_RECOVER_1) begin
            // Release all entries in a mispredicted path, move to a normal phase.
            nextPhase = (recoveryCount == 0) ? PHASE_COMMIT : PHASE_RECOVER_1;
            nextRecoveryCount = (recoveryCount > COMMIT_WIDTH) ? recoveryCount - COMMIT_WIDTH : 0;
        end
        else begin
            nextPhase = phase;
            nextRecoveryCount = recoveryCount;
        end
    end

    //
    // Pipeline registers for released physical registers.
    //
    typedef struct packed
    {
        logic releaseReg;
        PRegNumPath phyReleasedReg;
    } ReleasedRegister;
    ReleasedRegister regReleasedReg[COMMIT_WIDTH];
    ReleasedRegister nextReleasedReg[COMMIT_WIDTH];

    always_ff@(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < COMMIT_WIDTH; i++) begin
                regReleasedReg[i] <= '0;
            end
        end
        else begin
            regReleasedReg <= nextReleasedReg;
        end
    end

    always_comb begin
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            port.releaseReg[i] = regReleasedReg[i].releaseReg;
            port.phyReleasedReg[i] = regReleasedReg[i].phyReleasedReg;
        end
    end

    //
    // Commitment/recovery
    //
    ActiveListEntry alReadData [ COMMIT_WIDTH ];
    CommitLaneCountPath releaseNum;
    CommitLaneCountPath flushNum;
    always_comb begin

        // The head and tail entries of an active list.
        alReadData = activeList.readData;

        // Update control signals for the active list and the free lists in
        //  a rename logic.
        if(phase == PHASE_COMMIT) begin
            // Commit mode.
            activeList.popTailNum = 0;

            // Pop the head entries of the active list and release registers
            // to the free lists in the rename logic.
            if ( port.commit ) begin
                activeList.popHeadNum = port.commitNum;
            end
            else begin
                activeList.popHeadNum = 0;
            end

            for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
                if( port.commit && i < port.commitNum) begin
                    // A head op can commit.
                    // Release registers to the free lists.
                    nextReleasedReg[i].releaseReg = alReadData[i].writeReg;
                end
                else begin
                    // A head op cannot commit.
                    // The active list and the free lists are not updated.
                    nextReleasedReg[i].releaseReg = FALSE;
                end

                // Released registers are set from the head entry of the active list.
                nextReleasedReg[i].phyReleasedReg = alReadData[i].phyPrevDstRegNum;
            end

            recovery.inRecoveryAL = FALSE;
            flushNum = 0;
        end
        else if(phase == PHASE_RECOVER_0) begin
            activeList.popHeadNum = 0;
            activeList.popTailNum = 0;
            for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
                nextReleasedReg[i].releaseReg = FALSE;
                nextReleasedReg[i].phyReleasedReg = 0;
            end
            recovery.inRecoveryAL = TRUE;
            flushNum = 0;
        end
        else begin

            if( RECOVERY_FROM_RRMT ) begin
                releaseNum = COMMIT_WIDTH;
                if (releaseNum > recoveryCount) begin
                    releaseNum = recoveryCount;
                end
                flushNum = releaseNum;
                activeList.popHeadNum = releaseNum;
                activeList.popTailNum = 0;

                for (int i = 0; i < COMMIT_WIDTH; i++) begin
                    if (i < releaseNum) begin
                        // A head op can commit.
                        // Release registers to the free lists.
                        nextReleasedReg[i].releaseReg = alReadData[i].writeReg;
                    end
                    else begin
                        // A head op cannot commit.
                        // The active list and the free lists are not updated.
                        nextReleasedReg[i].releaseReg = FALSE;
                    end

                    // Released registers are set from the head entry of the active list.
                    nextReleasedReg[i].phyReleasedReg = alReadData[i].phyDstRegNum;
                end

                recovery.inRecoveryAL = TRUE;
            end else begin
                releaseNum = COMMIT_WIDTH;
                if (releaseNum > recoveryCount) begin
                    releaseNum = recoveryCount;
                end
                flushNum = releaseNum;
                activeList.popHeadNum = 0;
                activeList.popTailNum = releaseNum;

                for (int i = 0; i < COMMIT_WIDTH; i++) begin
                    if ( (i < releaseNum)) begin
                        // A head op can commit.
                        // Release registers to the free lists.
                        nextReleasedReg[i].releaseReg = alReadData[i].writeReg;
                    end
                    else begin
                        // A head op cannot commit.
                        // The active list and the free lists are not updated.
                        nextReleasedReg[i].releaseReg = FALSE;
                    end

                    // Released registers are set from the tail entry of the active list.
                    nextReleasedReg[i].phyReleasedReg = alReadData[i].phyDstRegNum;
                end

                recovery.inRecoveryAL = TRUE;
            end
        end

        port.flushNum = flushNum;
    end



endmodule
