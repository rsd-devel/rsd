// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// CAM based wakeup logic
//

import BasicTypes::*;
import SchedulerTypes::*;

// Use a matrix scheduler.
`define RSD_WAKEUP_MATRIX_SCHEDULER 1

module WakeupLogic (
    WakeupSelectIF.WakeupLogic port
);
    // Source status of dispatched instructions.
    logic dispatchedSrcRegValid  [ DISPATCH_WIDTH ][ ISSUE_QUEUE_SRC_REG_NUM ];

    PRegNumPath  dispatchedSrcRegNum  [ DISPATCH_WIDTH ][ ISSUE_QUEUE_SRC_REG_NUM ];

    // Destination status of dispatched instructions.
    logic dispatchedDstRegValid  [ DISPATCH_WIDTH ];

    PRegNumPath  dispatchedDstRegNum  [ DISPATCH_WIDTH ];

    // Destination status of wokeup instructions.
    logic wakeupDstRegValid  [ WAKEUP_WIDTH ];

    PRegNumPath  wakeupDstRegNum  [ WAKEUP_WIDTH ];

    // Connection between srcCAM and readyBitTbl
    logic dispatchedSrcRegReady[ DISPATCH_WIDTH ][ ISSUE_QUEUE_SRC_REG_NUM ];

    // Dependency matrix.
    IssueQueueOneHotPath wakeupDstVector[ WAKEUP_WIDTH + STORE_ISSUE_WIDTH ];
    IssueQueueIndexPath [ DISPATCH_WIDTH-1:0 ][ ISSUE_QUEUE_SRC_REG_NUM-1:0 ] dispatchedSrcRegPtr;
    logic opMatrixReady[ ISSUE_QUEUE_ENTRY_NUM ];

    logic [ISSUE_QUEUE_ENTRY_NUM-1:0] dependStoreBitVector[DISPATCH_WIDTH];
    logic [ISSUE_QUEUE_ENTRY_NUM-1:0] storeBitVector;
    logic [ISSUE_QUEUE_ENTRY_NUM-1:0] storeBitVectorReg;

    logic dispatchStore[DISPATCH_WIDTH];
    logic dispatchLoad[DISPATCH_WIDTH];
    logic [ISSUE_QUEUE_ENTRY_NUM-1:0] notIssued;

    logic memDependencyPred[DISPATCH_WIDTH];

    //
    // Ready bit tables.
    //
    ReadyBitTable #(
        .SRC_OP_NUM( ISSUE_QUEUE_SRC_REG_NUM ),
        .REG_NUM_BIT_WIDTH( PREG_NUM_BIT_WIDTH ),
        .ENTRY_NUM( PREG_NUM )
    ) regReadyBitTbl (
        .clk( port.clk ),
        .rst( port.rst ),
        .rstStart( port.rstStart ),
        .wakeup( port.wakeup ),
        .wakeupDstValid( wakeupDstRegValid ),
        .wakeupDstRegNum( wakeupDstRegNum ),
        .dispatch( port.write ),
        .dispatchedDstValid( dispatchedDstRegValid ),
        .dispatchedDstRegNum( dispatchedDstRegNum ),
        .dispatchedSrcValid( dispatchedSrcRegValid ),
        .dispatchedSrcRegNum( dispatchedSrcRegNum ),
        .dispatchedSrcReady( dispatchedSrcRegReady  )
    );

    always_comb begin
        // Dispatch
        for ( int i = 0; i < DISPATCH_WIDTH; i++ ) begin
            dispatchedDstRegValid[i]   = port.writeDstTag[i].regTag.valid;
            dispatchedDstRegNum[i]     = port.writeDstTag[i].regTag.num;

            for ( int j = 0; j < ISSUE_QUEUE_SRC_REG_NUM; j++ ) begin
                dispatchedSrcRegNum[i][j] = port.writeSrcTag[i].regTag[j].num;
                dispatchedSrcRegValid[i][j] = port.writeSrcTag[i].regTag[j].valid;
            end
        end

        // Wake up
        for ( int i = 0; i < WAKEUP_WIDTH; i++ ) begin
            wakeupDstRegValid[i]   = port.wakeupDstTag[i].regTag.valid;
            wakeupDstRegNum[i]     = port.wakeupDstTag[i].regTag.num;
        end
    end


`ifndef RSD_WAKEUP_MATRIX_SCHEDULER

    //
    // Source CAMs.
    //

    // Ready of each instruction
    IssueQueueOneHotPath opRegReady;

    // Wakeup Logic for registers.
    SourceCAM #(
        .SRC_OP_NUM( ISSUE_QUEUE_SRC_REG_NUM ),
        .REG_NUM_BIT_WIDTH( PREG_NUM_BIT_WIDTH )
    ) regSrcCAM (
        .clk( port.clk ),
        .rst( port.rst ),
        .dispatch( port.write ),
        .dispatchPtr( port.writePtr ),
        .dispatchedSrcRegNum( dispatchedSrcRegNum ),
        .dispatchedSrcReady( dispatchedSrcRegReady ),
        .wakeup( port.wakeup ),
        .wakeupDstValid( wakeupDstRegValid ),
        .wakeupDstRegNum( wakeupDstRegNum ),
        .opReady( opRegReady )
    );

    always_comb begin
        // Ready of each instruction
        for( int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++ ) begin
            port.opReady[i] = opRegReady[i];
        end
    end

`else

    //
    // Wakeup Matrix.
    //

    // Wakeup dst valid は，無条件でビットを下ろしておけば良いのでいらない．
    ProducerMatrix producerMatrix(
        .clk( port.clk ),
        .dispatch( port.write ),
        .dispatchedSrcRegReady( dispatchedSrcRegReady ),
        .dispatchedSrcRegPtr( dispatchedSrcRegPtr ),
        .dependStoreBitVector ( dependStoreBitVector ),
        .dispatchPtr( port.writePtr ),
        .wakeupDstVector( wakeupDstVector ),
        .opReady(opMatrixReady)
    );

    always_ff @(posedge port.clk) begin
        // Update store bit vector register.
        if (port.rst) begin
            storeBitVectorReg <= 0;
        end
        else begin
            storeBitVectorReg <= storeBitVector;
        end
    end

    always_comb begin

        // Get logic from IF
        dispatchStore = port.dispatchStore;
        dispatchLoad = port.dispatchLoad;
        notIssued = port.notIssued;

        // Wakeup
        for (int w = 0; w < WAKEUP_WIDTH + STORE_ISSUE_WIDTH; w++) begin
            wakeupDstVector[w] = port.wakeupVector[w];
        end

        // Dispatch
        for ( int i = 0; i < DISPATCH_WIDTH; i++ ) begin

            for ( int j = 0; j < ISSUE_QUEUE_SRC_REG_NUM; j++ ) begin
                dispatchedSrcRegPtr[i][j] = port.writeSrcTag[i].regPtr[j].ptr;
            end
        end

        // Update store bit vector according to information about getting out from IQ.
        storeBitVector = storeBitVectorReg & notIssued;
        // Memory dependent prediction
        memDependencyPred = port.memDependencyPred;

        for (int i = 0; i < DISPATCH_WIDTH; i++) begin
            if (dispatchStore[i]) begin
                // Update store bit vector (Set the corresponding bit).
                dependStoreBitVector[i] = 0;
                storeBitVector[port.writePtr[i]] = TRUE;
            end
            else if (dispatchLoad[i] && memDependencyPred[i]) begin
                // Issue load inst speculatively according to memory dependent prediction.
                // Add store bit vector to the dependency destination bit.
                // This will be processed in Producer Matrix.
                dependStoreBitVector[i] = storeBitVector;
            end
            else begin
                // Reset store bit vector for which add dependency destination bit.
                dependStoreBitVector[i] = 0;
            end
        end


    end

    always_comb begin
        // Ready of each instruction
        for( int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++ ) begin
            port.opReady[i] = opMatrixReady[i]; // Matrix
        end
    end
`endif


endmodule : WakeupLogic
