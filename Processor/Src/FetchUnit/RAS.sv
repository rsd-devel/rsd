// Copyright 2026- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

import BasicTypes::*;
import FetchUnitTypes::*;
import MemoryMapTypes::*;

module RAS(
    FetchStageIF.RAS port,
    RecoveryManagerIF.FetchStage recovery
);
    // Fetch speculates on BTB call/return types. Only an accepted group changes the stack.
    PC_Path entries[RAS_ENTRY_NUM];
    RAS_IndexPath rasPtr, nextRAS_Ptr;
    logic pushRAS, popRAS, rasWE;
    PC_Path returnPC, rasWritePC;
    always_ff @(posedge port.clk) begin
        rasPtr <= nextRAS_Ptr;
        if (port.rst) begin
            for (int i = 0; i < RAS_ENTRY_NUM; i++)
                entries[i] <= '0;
        end
        else if (rasWE)
            entries[nextRAS_Ptr] <= rasWritePC;
    end

    // Fetch reads the current top and checkpoints the pointer before the group advances.
    always_comb begin
        port.rasTopPC = entries[rasPtr];
        port.rasPtr = rasPtr;
    end

    always_comb begin
        pushRAS = FALSE;
        popRAS = FALSE;
        returnPC = '0;
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            // A held I-cache response carries its original prediction until it advances.
            if (port.nextStage.valid[i] && port.nextStage.brPred[i].predTaken) begin
                pushRAS = port.nextStage.brPred[i].btbBrType == BTB_CALL;
                popRAS = port.nextStage.brPred[i].btbBrType inside {BTB_RETURN, BTB_RETURN_OFFSET};
                returnPC = port.nextStage.pc + PC_Path'((i + 1) * INSN_BYTE_WIDTH);
            end
        end
    end

    always_comb begin
        nextRAS_Ptr = rasPtr;
        rasWE = FALSE;
        rasWritePC = returnPC;
        if (port.rst)
            nextRAS_Ptr = '0;
        else if (recovery.fetchRedirect.valid || port.interruptAddrWE) begin
            // Cold redirects have no checkpoint. Preserve the circular stack as a prediction hint.
            if (recovery.fetchRedirect.restorePredCtx && recovery.fetchRedirect.valid && !port.interruptAddrWE) begin
                nextRAS_Ptr = recovery.fetchRedirect.predCtx.rasPtr;
                rasWE = recovery.fetchRedirect.rasPush;
                rasWritePC = recovery.fetchRedirect.rasReturnPC;
            end
        end
        else if (pushRAS) begin
            nextRAS_Ptr = rasPtr + RAS_IndexPath'(1);
            rasWE = TRUE;
        end
        else if (popRAS)
            nextRAS_Ptr = rasPtr - RAS_IndexPath'(1);
    end
endmodule : RAS
