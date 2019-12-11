// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.



import BasicTypes::*;
import SchedulerTypes::*;

//`define ALWAYS_SPECULATIVE
//`define ALWAYS_NOT_SPECULATIVE

module MemoryDependencyPredictor(
    RenameStageIF.MemoryDependencyPredictor port,
    LoadStoreUnitIF.MemoryDependencyPredictor loadStoreUnit
);

    logic mdtWE[STORE_ISSUE_WIDTH];
    MDT_IndexPath mdtWA[STORE_ISSUE_WIDTH];
    MDT_Entry mdtWV[STORE_ISSUE_WIDTH];
    MDT_IndexPath mdtRA[RENAME_WIDTH];
    MDT_Entry mdtRV[RENAME_WIDTH];

    logic prediction[RENAME_WIDTH];

    generate
        // NOTE: Need to implement write request queue when increase STORE_ISSUE_WIDTH
        BlockMultiBankRAM #(
            .ENTRY_NUM( MDT_ENTRY_NUM ),
            .ENTRY_BIT_SIZE( $bits( MDT_Entry ) ),
            .READ_NUM( RENAME_WIDTH ),
            .WRITE_NUM( STORE_ISSUE_WIDTH )
        ) 
        mdt( 
            .clk(port.clk),
            .we(mdtWE),
            .wa(mdtWA),
            .wv(mdtWV),
            .ra(mdtRA),
            .rv(mdtRV)
        );
    endgenerate

    // Counter for reset sequence.
    MDT_IndexPath resetIndex;
    always_ff @(posedge port.clk) begin
        if (port.rstStart) begin
            resetIndex <= 0;
        end
        else begin
            resetIndex <= resetIndex + 1;
        end
    end

    always_comb begin

        // Process read request
        for (int i = 0; i < RENAME_WIDTH; i++) begin
            // convert PC_Path to MDT_IndexPath
            mdtRA[i] = ToMDT_Index(port.pc[0] + i*INSN_BYTE_WIDTH);
        end

        // Decide whether issue speculatively
        for (int i = 0; i < RENAME_WIDTH; i++) begin
`ifdef ALWAYS_SPECULATIVE
            prediction[i] = FALSE;
`elsif ALWAYS_NOT_SPECULATIVE
            prediction[i] = TRUE;
`else
            // Predict according to mdt entry
            prediction[i] = mdtRV[i].counter;
`endif
        end

        // Connect to IF.
        port.memDependencyPred = prediction;

        // Process write request
        for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
            // Make write request when store detect conflict with load
            mdtWE[i] = 
                loadStoreUnit.memAccessOrderViolation[i];

            // Learn memory order violation
            mdtWA[i] = ToMDT_Index(loadStoreUnit.conflictLoadPC[i]);
            mdtWV[i].counter = TRUE;
        end

        // In reset sequence, the write port 0 is used for initializing, and 
        // the other write ports are disabled.
        if (port.rst) begin
            for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
                mdtWE[i] = (i == 0);
                mdtWA[i] = resetIndex;
                mdtWV[i].counter = FALSE;
            end

            // To avoid writing to the same bank (avoid error message)
            for (int i = 0; i < RENAME_WIDTH; i++) begin
                mdtRA[i] = i;
            end
        end
    end

endmodule : MemoryDependencyPredictor
