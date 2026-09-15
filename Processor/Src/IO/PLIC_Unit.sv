// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

module PLIC_Unit(
    PLIC_UnitIF.PLIC_Unit port,
    CSR_UnitIF.IO_Unit csrUnit,
    IO_UnitIF.IO_Unit ioUnit
);

    function PhyRawAddrPath getPLIC_SourcePriorityAddr(input int source);
        return PHY_ADDR_PLIC_SOURCE_PRIORITY_BASE + source*4;
    endfunction

    function PhyRawAddrPath getPLIC_PendingAddr(input int regIndex);
        return PHY_ADDR_PLIC_PENDING_BASE + regIndex*4;
    endfunction

    function PhyRawAddrPath getPLIC_EnableAddr(input int ctx, input int regIndex);
        return PHY_ADDR_PLIC_ENABLE_BASE + ctx*PhyRawAddrPath'(32'h80) + regIndex*4;
    endfunction

    function PhyRawAddrPath getPLIC_PriorityThresholdAddr(input int ctx);
        return PHY_ADDR_PLIC_PRIORITY_THRESHOLD_BASE + ctx*PhyRawAddrPath'(32'h1000);
    endfunction

    function PhyRawAddrPath getPLIC_ClaimCompleteAddr(input int ctx);
        return PHY_ADDR_PLIC_CLAIM_COMPLETE_BASE + ctx*PhyRawAddrPath'(32'h1000);
    endfunction

    // plic memory-mapped registers
    PLIC_UnitRegisters plicReg, plicNext;

    logic gateInterruptRequests [PLIC_NUM_SOURCES:0];
    logic nextGateInterruptRequests [PLIC_NUM_SOURCES:0];

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            plicReg <= '0;
            for (int i = PLIC_NUM_SOURCES_BEGIN; i < PLIC_NUM_SOURCES_END; i++) begin
                gateInterruptRequests[i] <= FALSE;
            end
        end
        else begin
            plicReg <= plicNext;
            for (int i = PLIC_NUM_SOURCES_BEGIN; i < PLIC_NUM_SOURCES_END; i++) begin
                gateInterruptRequests[i] <= nextGateInterruptRequests[i];
            end
        end
    end

    logic flattenedEnable [PLIC_NUM_CONTEXTS-1:0][PLIC_NUM_SOURCES:0]; // source 0 is unused
    logic [PLIC_NUM_SOURCES_LOG-1:0] selectedSource [PLIC_NUM_CONTEXTS-1:0]; 
    logic [31:0] selectedSourcePriority [PLIC_NUM_CONTEXTS-1:0];
    logic [PLIC_NUM_SOURCES_LOG-1:0] writeSourceId;

    // All accesses to PLIC are assumed to be 32-BITS aligned ATOMIC LW/SW.
    // """
    // The memory-mapped registers specified in this chapter have a width of 32-bits.
    // The bits are accessed atomically with LW and SW instructions.
    // """
    always_comb begin
        plicNext = plicReg;
        nextGateInterruptRequests = gateInterruptRequests;
        port.ioReadDataOut = '0;

        // flatten enable bits
        for (int i = 0; i < PLIC_NUM_CONTEXTS; i++) begin
            flattenedEnable[i][0] = FALSE;
            for (int j = PLIC_NUM_SOURCES_BEGIN; j < PLIC_NUM_SOURCES_END; j++) begin
                flattenedEnable[i][j] = plicReg.enable[i][j/32][j%32];
            end
        end

        // source priority
        for (int i = PLIC_NUM_SOURCES_BEGIN; i < PLIC_NUM_SOURCES_END; i++) begin
            if (port.phyRawReadAddrIn == getPLIC_SourcePriorityAddr(i)) begin
                port.ioReadDataOut = plicReg.sourcePriority[i];
            end
            if (port.ioWE && port.phyRawWriteAddrIn == getPLIC_SourcePriorityAddr(i)) begin
                plicNext.sourcePriority[i] = port.ioWriteDataIn;
            end
        end

        // interrupt pending
        for (int i = 0; i < PLIC_NUM_PENDING_REGS; i++) begin
            if (port.phyRawReadAddrIn == getPLIC_PendingAddr(i)) begin
                port.ioReadDataOut = plicReg.pending[i*32 +: 32];
            end
        end

        // enable
        for (int i = 0; i < PLIC_NUM_CONTEXTS; i++) begin
            for (int j = 0; j < PLIC_NUM_ENABLE_REGS; j++) begin
                if (port.phyRawReadAddrIn == getPLIC_EnableAddr(i, j)) begin
                    port.ioReadDataOut = plicReg.enable[i][j];
                end
                if (port.ioWE && port.phyRawWriteAddrIn == getPLIC_EnableAddr(i, j)) begin
                    if (j == 0) begin
                        plicNext.enable[i][j] = port.ioWriteDataIn & (32'hffff_fffe);
                    end else begin
                        plicNext.enable[i][j] = port.ioWriteDataIn;
                    end
                end
            end
        end

        // priority threshold
        for (int i = 0; i < PLIC_NUM_CONTEXTS; i++) begin
            if (port.phyRawReadAddrIn == getPLIC_PriorityThresholdAddr(i)) begin
                port.ioReadDataOut = plicReg.priorityThreshold[i];
            end
            if (port.ioWE && port.phyRawWriteAddrIn == getPLIC_PriorityThresholdAddr(i)) begin
                plicNext.priorityThreshold[i] = port.ioWriteDataIn;
            end
        end

        // decide which interrupt to claim
        for (int i = 0; i < PLIC_NUM_CONTEXTS; i++) begin
            selectedSource[i] = '0;
            selectedSourcePriority[i] = '0;
            port.reqExternalInterrupt[i] = FALSE;
            for (int j = PLIC_NUM_SOURCES_BEGIN; j < PLIC_NUM_SOURCES_END; j++) begin
                if (flattenedEnable[i][j] &&
                    plicReg.pending[j] == TRUE &&
                    plicReg.sourcePriority[j] > selectedSourcePriority[i]
                ) begin
                    selectedSource[i] = j[PLIC_NUM_SOURCES_LOG-1:0];
                    selectedSourcePriority[i] = plicReg.sourcePriority[j];
                    // """The PLIC will mask all PLIC interrupts of a priority less than or equal to threshold."""
                    port.reqExternalInterrupt[i] = plicReg.sourcePriority[j] > plicReg.priorityThreshold[i] ? TRUE : FALSE;
                end
            end
        end

        // claim/complete
        writeSourceId = port.ioWriteDataIn[PLIC_NUM_SOURCES_LOG-1:0];
        for (int i = 0; i < PLIC_NUM_CONTEXTS; i++) begin
            // claim
            if (port.ioRE && port.phyRawReadAddrIn == getPLIC_ClaimCompleteAddr(i)) begin
                port.ioReadDataOut = selectedSource[i];
                if (selectedSource[i] != '0) begin
                    // clear pending bit of selected source
                    plicNext.pending[selectedSource[i]] = FALSE;
                end
            end
            // complete
            if (port.ioWE && port.phyRawWriteAddrIn == getPLIC_ClaimCompleteAddr(i)) begin
                // """
                // If the completion ID does not match an interrupt source that is 
                // currently enabled for the target, the completion is silently ignored.
                // """
                if (1 <= port.ioWriteDataIn &&
                    port.ioWriteDataIn <= PLIC_NUM_SOURCES &&
                    flattenedEnable[i][writeSourceId]
                ) begin
                    // """
                    // The gateway will only forward additional interrupts to the 
                    // PLIC core after receiving the completion message
                    // """
                    nextGateInterruptRequests[writeSourceId] = FALSE;
                end
            end
        end

        // handle interrupt from interrupt source
        for (int i = PLIC_NUM_SOURCES_BEGIN; i < PLIC_NUM_SOURCES_END; i++) begin
            if (gateInterruptRequests[i] == FALSE && port.interruptReqFromInterruptSource[i]) begin
                plicNext.pending[i] = TRUE;
                nextGateInterruptRequests[i] = TRUE;
            end
        end
    end

endmodule
