// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Branch target buffer
//

import BasicTypes::*;
import MemoryMapTypes::*;
import FetchUnitTypes::*;

module BTB(
    NextPCStageIF.BTB port,
    FetchStageIF.BTB fetch
);

    function automatic logic HasBankConflict(PHT_IndexPath addr1, PHT_IndexPath addr2);
        localparam BANK_NUM = FETCH_WIDTH > INT_ISSUE_WIDTH ? FETCH_WIDTH : INT_ISSUE_WIDTH;
        localparam BANK_NUM_BIT_WIDTH = $clog2(BANK_NUM);
        if (addr1[BANK_NUM_BIT_WIDTH-1:0] == addr2[BANK_NUM_BIT_WIDTH-1:0]) begin
            return TRUE;
        end
        else begin
            return FALSE;
        end
    endfunction

    // BTB access
    logic btbWE[INT_ISSUE_WIDTH];
    BTB_IndexPath btbWA[INT_ISSUE_WIDTH];
    BTB_Entry btbWV[INT_ISSUE_WIDTH];
    BTB_IndexPath btbRA[FETCH_WIDTH];
    BTB_Entry btbRV[FETCH_WIDTH];
    
    // Output
    PC_Path btbOut[FETCH_WIDTH];
    logic btbHit[FETCH_WIDTH];
    logic readIsCondBr[FETCH_WIDTH];
    
    PC_Path pcIn;
    
    PC_Path [FETCH_WIDTH-1 : 0] tagReg;
    PC_Path [FETCH_WIDTH-1 : 0] nextTagReg;
    
    logic pushBtbQueue, popBtbQueue;
    logic full, empty;

    BTBQueueEntry btbQueue[BTB_QUEUE_SIZE];
    BTBQueuePointerPath headPtr, tailPtr;
    BTBQueueEntry btbQueueWV;

    generate
        BlockMultiBankRAM #(
            .ENTRY_NUM( BTB_ENTRY_NUM ),
            .ENTRY_BIT_SIZE( $bits( BTB_Entry ) ),
            .READ_NUM( FETCH_WIDTH ),
            .WRITE_NUM( INT_ISSUE_WIDTH )
        ) 
        btbEntryArray( 
            .clk(port.clk),
            .we(btbWE),
            .wa(btbWA),
            .wv(btbWV),
            .ra(btbRA),
            .rv(btbRV)
        );

        QueuePointer #(
            .SIZE( BTB_QUEUE_SIZE )
        )
        btbQueuePointer(
            .clk(port.clk),
            .rst(port.rst),
            .push(pushBtbQueue),
            .pop(popBtbQueue),
            .full(full),
            .empty(empty),
            .headPtr(headPtr),
            .tailPtr(tailPtr)    
        );
    endgenerate
    
    
    // Counter for reset sequence.
    BTB_IndexPath resetIndex;
    always_ff @(posedge port.clk) begin
        if(port.rstStart) begin
            resetIndex <= 0;
        end
        else begin
            resetIndex <= resetIndex + 1;
        end
        
        if (port.rst) begin
            tagReg <= '0;
        end
        else begin
            tagReg <= nextTagReg;
        end
    end

    always_ff @(posedge port.clk) begin
        // Push btb Queue
        if (pushBtbQueue) begin
            btbQueue[tailPtr] <= btbQueueWV;
        end 
    end


    always_comb begin
        
        pcIn = port.predNextPC;
        
        // Address inputs for read entry.
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            btbRA[i] = ToBTB_Index(pcIn + i*INSN_BYTE_WIDTH);
            nextTagReg[i] = pcIn + i*INSN_BYTE_WIDTH;
        end
            
        // Make logic for using at other module.
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            btbHit[i] = btbRV[i].valid && (btbRV[i].tag == ToBTB_Tag(tagReg[i]));
            btbOut[i] = ToRawAddrFromBTB_Addr(btbRV[i].data, tagReg[i]);
            readIsCondBr[i] = btbRV[i].isCondBr;
        end

        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            btbWE[i] = port.brResult[i].valid && port.brResult[i].execTaken;
            btbWA[i] = ToBTB_Index(port.brResult[i].brAddr);
            btbWV[i].tag = ToBTB_Tag(port.brResult[i].brAddr);
            btbWV[i].data = ToBTB_Addr(port.brResult[i].nextAddr);
            btbWV[i].valid = TRUE;
            btbWV[i].isCondBr = port.brResult[i].isCondBr;
        end

        pushBtbQueue = FALSE;
        // check whether bank conflict occurs
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            // When branch instruction is executed, update BTB.
            if (i > 0 && btbWE[i]) begin
                for (int j = 0; j < i; j++) begin
                    if (!btbWE[j]) begin
                        continue;
                    end

                    if (HasBankConflict(btbWA[i], btbWA[j])) begin
                        btbWE[i] = FALSE;
                        pushBtbQueue = TRUE;
                        btbQueueWV.wv = btbWV[i];
                        btbQueueWV.wa = btbWA[i];
                        break;
                    end
                end
            end
        end

        // Pop BTB Queue
        popBtbQueue = FALSE;
        if (!empty) begin
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin : outer
                if (btbWE[i]) begin
                    continue;
                end

                for (int j = 0; j < INT_ISSUE_WIDTH; j++) begin
                    if (i == j || !btbWE[j]) begin
                        continue;
                    end

                    if (HasBankConflict(btbQueue[headPtr].wa, btbWA[j])) begin
                        disable outer;
                    end
                end

                popBtbQueue = TRUE;
                btbWE[i] = TRUE;
                btbWA[i] = btbQueue[headPtr].wa;
                btbWV[i] = btbQueue[headPtr].wv;
            end
        end

        
        // In reset sequence, the write port 0 is used for initializing, and 
        // the other write ports are disabled.
        if (port.rst) begin
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                btbWE[i] = (i == 0) ? TRUE : FALSE;
                btbWA[i] = resetIndex;
                btbWV[i].tag = 0;
                btbWV[i].data = 0;
                btbWV[i].valid = FALSE;
            end

            // To avoid writing to the same bank (avoid error message)
            for (int i = 0; i < FETCH_WIDTH; i++) begin
                btbRA[i] = i;
            end
            
            pushBtbQueue = FALSE;
            popBtbQueue = FALSE;
        end

        fetch.readIsCondBr = readIsCondBr;
        fetch.btbOut = btbOut;
        fetch.btbHit = btbHit;
        
    end


endmodule : BTB
