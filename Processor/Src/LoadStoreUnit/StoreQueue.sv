// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Store queue
//

`include "BasicMacros.sv"

import BasicTypes::*;
import CacheSystemTypes::*;
import OpFormatTypes::*;
import LoadStoreUnitTypes::*;
import MemoryMapTypes::*;



module StoreQueue(
    LoadStoreUnitIF.StoreQueue port,
    RecoveryManagerIF.StoreQueue recovery
);

    // ストアデータをアドレスのオフセットに合わせてシフト
    // ベクトルデータの場合は、そのまま
    function automatic void GenerateStoreData(
        output LSQ_BlockDataPath dataOut,
        input DataPath dataIn,
        input LSQ_BlockDataPath blockDataIn,
        input PhyAddrPath addr,
        input MemAccessMode mode
    );
`ifdef RSD_ENABLE_VECTOR_PATH
        // Disable vector data path
        if (mode.size == MEM_ACCESS_SIZE_VEC) begin
            dataOut = blockDataIn;  // Vector
        end
        else begin
            dataOut = dataIn;
            dataOut = dataOut << ( addr[ LSQ_BLOCK_BYTE_WIDTH_BIT_SIZE-1:0 ] * BYTE_WIDTH );
        end
`else
        dataOut = dataIn;
        dataOut = dataOut << ( addr[ LSQ_BLOCK_BYTE_WIDTH_BIT_SIZE-1:0 ] * BYTE_WIDTH );
`endif
    endfunction

    //
    // Signals
    //

    // The content of the head of a SQ.
    StoreQueueAddrEntry headAddrEntry;
    StoreQueueDataEntry headDataEntry;

    // The pointer of released entry.
    StoreQueueIndexPath releasedStoreQueuePtr;

    // The head/tail pointers of a store queue.
    StoreQueueIndexPath headPtr;
    StoreQueueIndexPath tailPtr;

    // FIFO controller.
    RenameLaneCountPath pushCount;
    StoreQueueCountPath curCount;
    logic push;

    // Parameter: Size, Initial head pos., Initial tail pos., Initial count
    SetTailMultiWidthQueuePointer #( STORE_QUEUE_ENTRY_NUM, 0, 0, 0, RENAME_WIDTH, COMMIT_WIDTH )
        storeQueuePointer(
            .clk(port.clk),
            .rst(port.rst), // On flush, pointers are recovered by the store committer.
            .pop(port.releaseStoreQueueHead),
            .popCount(port.releaseStoreQueueHeadEntryNum),
            .push(push),
            .pushCount(pushCount),
            .setTail(recovery.toRecoveryPhase),
            .setTailPtr(recovery.storeQueueRecoveryTailPtr),
            .count(curCount),
            .headPtr(headPtr),
            .tailPtr(tailPtr)
        );

    always_comb begin

        pushCount = 0;
        for (int i = 0; i < RENAME_WIDTH; i++) begin
            if (tailPtr + pushCount < STORE_QUEUE_ENTRY_NUM) begin
                port.allocatedStoreQueuePtr[i] = tailPtr + pushCount;
            end
            else begin
                // Out of range of store queue
                port.allocatedStoreQueuePtr[i] = 
                    tailPtr + pushCount - STORE_QUEUE_ENTRY_NUM;
            end
            pushCount += port.allocateStoreQueue[i];
        end
        push = pushCount > 0;

        port.storeQueueCount = curCount;
        port.storeQueueAllocatable =
            (curCount <= STORE_QUEUE_ENTRY_NUM - RENAME_WIDTH - 1) ? TRUE : FALSE;
        port.storeQueueEmpty = curCount == 0;

        recovery.storeQueueHeadPtr = headPtr;
    end


    //
    // SQ's address and data storage.
    //

    // The address part of a SQ.
    StoreQueueAddrEntry storeQueue[STORE_QUEUE_ENTRY_NUM-1:0];

    logic  executeStore[STORE_ISSUE_WIDTH];
    LSQ_BlockAddrPath executedStoreAddr[STORE_ISSUE_WIDTH];
    LSQ_BlockWordEnablePath executedStoreWordWE[STORE_ISSUE_WIDTH];
    LSQ_WordByteEnablePath executedStoreByteWE[STORE_ISSUE_WIDTH];
    logic executedStoreCondEnabled[STORE_ISSUE_WIDTH];
    logic executedStoreRegValid[STORE_ISSUE_WIDTH];
    StoreQueueIndexPath executedStoreQueuePtrByStore[STORE_ISSUE_WIDTH];

    always_ff @(posedge port.clk) begin
        if(port.rst) begin
            for( int i = 0; i < STORE_QUEUE_ENTRY_NUM; i++) begin
                storeQueue[i].finished <= FALSE;
                storeQueue[i].address <= '0;
                storeQueue[i].wordWE <= '0;
                storeQueue[i].byteWE <= '0;
            end
        end
        else begin
            for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
                if( executeStore[i] ) begin
                    storeQueue[ executedStoreQueuePtrByStore[i] ].regValid <= executedStoreRegValid[i];
                    storeQueue[ executedStoreQueuePtrByStore[i] ].finished <= executedStoreCondEnabled[i];
                    storeQueue[ executedStoreQueuePtrByStore[i] ].address <= executedStoreAddr[i];
                    storeQueue[ executedStoreQueuePtrByStore[i] ].wordWE <= executedStoreWordWE[i];
                    storeQueue[ executedStoreQueuePtrByStore[i] ].byteWE <= executedStoreByteWE[i];
                end
            end

            for (int i = 0; i < RENAME_WIDTH; i++) begin
                if (port.allocateStoreQueue[i]) begin
                    storeQueue[ port.allocatedStoreQueuePtr[i] ].finished <= FALSE;
                end
            end
        end
    end

    always_comb begin
        // Pick store execution results.
        for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
            executeStore[i] = port.executeStore[i];
            executedStoreAddr[i] =
                LSQ_ToBlockAddr(port.executedStoreAddr[i]);
            executedStoreCondEnabled[i] = port.executedStoreCondEnabled[i];
            executedStoreRegValid[i] = port.executedStoreRegValid[i];
            executedStoreQueuePtrByStore[i] = port.executedStoreQueuePtrByStore[i];

            executedStoreWordWE[i] =
                LSQ_ToBlockWordEnable(
                    port.executedStoreAddr[i],
                    port.executedStoreMemAccessMode[i]
                );
            executedStoreByteWE[i] =
                LSQ_ToWordByteEnable(
                    port.executedStoreAddr[i],
                    port.executedStoreMemAccessMode[i]
                );
        end
    end



    // Forwarding from a store queue.
    StoreQueueDataEntry forwardedDataEntry[LOAD_ISSUE_WIDTH];
    LSQ_BlockWordEnablePath executedLoadWordRE[LOAD_ISSUE_WIDTH];
    LSQ_WordByteEnablePath executedLoadByteRE[LOAD_ISSUE_WIDTH];

    // A picker of forwarded entries.
    StoreQueueOneHotPath addrMatch[LOAD_ISSUE_WIDTH];
    StoreQueueIndexPath pickedPtr[LOAD_ISSUE_WIDTH];
    logic picked[LOAD_ISSUE_WIDTH];
    StoreQueueIndexPath executedStoreQueuePtrByLoad[LOAD_ISSUE_WIDTH];

    generate
        for(genvar i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            CircularRangePicker #(
                .ENTRY_NUM( STORE_QUEUE_ENTRY_NUM )
            ) picker(
                .headPtr(headPtr),
                .tailPtr(executedStoreQueuePtrByLoad[i]),
                .request(addrMatch[i]),
                .grantPtr(pickedPtr[i]),
                .picked(picked[i])
            );
        end
    endgenerate

    always_comb begin
        for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            executedStoreQueuePtrByLoad[i] = port.executedStoreQueuePtrByLoad[i];
        end
    end


    // The data part of the SQ.
    StoreQueueIndexPath sqReadPtr[LOAD_ISSUE_WIDTH + 1];  // +1 for commit.
    StoreQueueDataEntry sqReadData[LOAD_ISSUE_WIDTH + 1];
    logic sqWE[STORE_ISSUE_WIDTH];
    StoreQueueDataEntry sqWriteData[STORE_ISSUE_WIDTH];

    LSQ_BlockDataPath sqWriteStoreData[STORE_ISSUE_WIDTH];

    DistributedMultiPortRAM #(
        .ENTRY_NUM( STORE_QUEUE_ENTRY_NUM ),
        .ENTRY_BIT_SIZE( $bits(StoreQueueDataEntry) ),
        .READ_NUM(LOAD_ISSUE_WIDTH + 1),    // +1 for commit.
        .WRITE_NUM(STORE_ISSUE_WIDTH)
    ) storeQueueData (
        .clk(port.clk),
        .we(sqWE),
        .wa(executedStoreQueuePtrByStore),
        .wv(sqWriteData),
        .ra(sqReadPtr),
        .rv(sqReadData)
    );

    // Write
    always_comb begin
        for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
            GenerateStoreData(
                sqWriteStoreData[i],
                port.executedStoreData[i],
                port.executedStoreVectorData[i],
                port.executedStoreAddr[i],
                port.executedStoreMemAccessMode[i]
            );

            sqWE[i] = executeStore[i];
            sqWriteData[i].data = sqWriteStoreData[i];
            sqWriteData[i].condEnabled = executedStoreCondEnabled[i];
            sqWriteData[i].wordWE = executedStoreWordWE[i];
            sqWriteData[i].byteWE = executedStoreByteWE[i];
        end
    end

    // Store-Load Forwarding
    logic storeLoadForwarded [ LOAD_ISSUE_WIDTH ];
    LSQ_BlockDataPath forwardedLoadData [ LOAD_ISSUE_WIDTH ];
    logic forwardMiss[ LOAD_ISSUE_WIDTH ];

    always_comb begin

        // --- Commit
        // A read pointer is specified by a store commit unit.
        releasedStoreQueuePtr = port.retiredStoreQueuePtr;

        // The last read port is used for commitment.
        sqReadPtr[LOAD_ISSUE_WIDTH] = releasedStoreQueuePtr;
        headDataEntry = sqReadData[LOAD_ISSUE_WIDTH];
        headAddrEntry = storeQueue[releasedStoreQueuePtr];

        port.retiredStoreLSQ_BlockAddr = headAddrEntry.address;

        port.retiredStoreData = headDataEntry.data;
        port.retiredStoreCondEnabled = headDataEntry.condEnabled;
        port.retiredStoreWordWE = headDataEntry.wordWE;
        port.retiredStoreByteWE = headDataEntry.byteWE;

        port.storeQueueHeadPtr = headPtr;


        // --- Forwarding
        for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            sqReadPtr[i] = pickedPtr[i] >= STORE_QUEUE_ENTRY_NUM ?
                pickedPtr[i] - STORE_QUEUE_ENTRY_NUM : pickedPtr[i];
            forwardedDataEntry[i] = sqReadData[i];

            executedLoadWordRE[i] =
                LSQ_ToBlockWordEnable(
                    port.executedLoadAddr[i],
                    port.executedLoadMemAccessMode[i]
                );
            executedLoadByteRE[i] =
                LSQ_ToWordByteEnable(
                    port.executedLoadAddr[i],
                    port.executedLoadMemAccessMode[i]
                );
        end

        // Detect store-load forwarding between already executed stores and
        // a currently executed load.
        for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            for (int j = 0; j < STORE_QUEUE_ENTRY_NUM; j++) begin
                addrMatch[i][j] =
                    storeQueue[j].finished &&
                    storeQueue[j].address == LSQ_ToBlockAddr(port.executedLoadAddr[i]) &&
                    ((storeQueue[j].wordWE & executedLoadWordRE[i]) != '0) &&
                    ((storeQueue[j].byteWE & executedLoadByteRE[i]) != '0);
            end
        end

        for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            // ロードのフォワーディングの依存元となるストアは1つに限られる。
            // ストアがwriteしてないバイトを、ロードがreadしようとした場合、
            // フォワーディングは失敗となる。
            if (pickedPtr[i] < STORE_QUEUE_ENTRY_NUM) begin
                forwardMiss[i] = !storeQueue[pickedPtr[i]].regValid ||
                    ((~forwardedDataEntry[i].wordWE & executedLoadWordRE[i]) != '0) ||
                    ((~forwardedDataEntry[i].byteWE & executedLoadByteRE[i]) != '0);
                forwardedLoadData[i] = forwardedDataEntry[i].data;
            end
            else begin
                // Out of range of store queue
                forwardMiss[i] = FALSE;
                forwardedLoadData[i] = '0;
            end
            storeLoadForwarded[i] = port.executeLoad[i] && picked[i];
        end

        port.forwardedLoadData = forwardedLoadData;
        port.forwardMiss = forwardMiss;
        port.storeLoadForwarded = storeLoadForwarded;
    end

    //
    // Assertions
    //
    generate
        for (genvar i = 0; i < LOAD_ISSUE_WIDTH; i++) begin : assertionBlock
            //  |-L--h***S***t-------|
            `RSD_ASSERT_CLK(
                port.clk,
                !(port.executeLoad[i] && headPtr < tailPtr && port.executedStoreQueuePtrByLoad[i] < headPtr),
                "1:A load's executedStoreQueuePtr is illegal."
            );

            //  |----h******t--L----|
            `RSD_ASSERT_CLK(
                port.clk,
                !(port.executeLoad[i] && headPtr < tailPtr && tailPtr < port.executedStoreQueuePtrByLoad[i]),
                "2:A load's executedStoreQueuePtr is illegal."
            );

            //  |******t--L--h*******|
            `RSD_ASSERT_CLK(
                port.clk,
                !(port.executeLoad[i] && tailPtr <= headPtr &&
                tailPtr < port.executedStoreQueuePtrByLoad[i] && port.executedStoreQueuePtrByLoad[i] < headPtr),
                "3:A load's executedStoreQueuePtr is illegal."
            );
        end
    endgenerate

    `RSD_ASSERT_CLK(
        port.clk,
        port.rst || !((port.releaseStoreQueueHead ) && curCount == 0),
        "Pop from a empty store queue."
    );


endmodule : StoreQueue

