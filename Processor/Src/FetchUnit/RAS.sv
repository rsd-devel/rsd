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
    // A return predicts within its own aligned 256 KiB region.
    localparam RAS_REGION_OFFSET_WIDTH = 18;
    typedef logic [RAS_REGION_OFFSET_WIDTH-1:INSN_ADDR_BIT_WIDTH] RAS_WordOffsetPath;
    RAS_WordOffsetPath top[1];
    RAS_IndexPath rasPtr, nextRAS_Ptr;
    logic pushRAS, popRAS, rasWE;
    PC_Path returnPC;
    AddrPath rasWriteAddr, fetchAddr;
    always_ff @(posedge port.clk) begin
        rasPtr <= nextRAS_Ptr;
    end

    ResettableDistributedMultiPortRAM #(
        .ENTRY_NUM(RAS_ENTRY_NUM), .ENTRY_BIT_SIZE($bits(RAS_WordOffsetPath)),
        .READ_NUM(1), .WRITE_NUM(1), .RESET_VALUE('0)
    ) entries (
        .clk(port.clk), .rst(port.rst), .rstStart(port.rstStart),
        .we('{rasWE}), .wa('{nextRAS_Ptr}), .wv('{rasWriteAddr[RAS_REGION_OFFSET_WIDTH-1:INSN_ADDR_BIT_WIDTH]}),
        .ra('{rasPtr}), .rv(top)
    );

    // Fetch reads the current top and checkpoints the pointer before the group advances.
    always_comb begin
        fetchAddr = ToAddrFromPC(port.pcOut);
        port.rasTopPC = ToPC_FromAddr({fetchAddr[ADDR_WIDTH-1:RAS_REGION_OFFSET_WIDTH],
                                       top[0], {INSN_ADDR_BIT_WIDTH{1'b0}}});
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
        rasWriteAddr = ToAddrFromPC(returnPC);
        if (port.rst)
            nextRAS_Ptr = '0;
        else if (recovery.fetchRedirect.valid || port.interruptAddrWE) begin
            // Cold redirects have no checkpoint. Preserve the circular stack as a prediction hint.
            if (recovery.fetchRedirect.restorePredCtx && recovery.fetchRedirect.valid && !port.interruptAddrWE) begin
                nextRAS_Ptr = recovery.fetchRedirect.predCtx.rasPtr;
                rasWE = recovery.fetchRedirect.rasPush;
                rasWriteAddr = ToAddrFromPC(recovery.fetchRedirect.rasReturnPC);
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
