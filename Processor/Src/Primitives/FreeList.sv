// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A free list for an issue queue entries.
//

import BasicTypes::*;

module FreeList #(
    parameter SIZE = 1,
    parameter ENTRY_WIDTH = 1 // MultiWidthFreeListではENTRY_WIDTH
)( 
input 
    logic clk,
    logic rst,
    logic push,
    logic pop,
    logic [ ENTRY_WIDTH-1:0 ] pushedData,
output
    logic full,
    logic empty,
    logic [ ENTRY_WIDTH-1:0 ] headData
);

    localparam BIT_WIDTH = $clog2( SIZE );
    typedef logic [BIT_WIDTH-1:0] IndexPath;

    IndexPath headPtr;
    IndexPath tailPtr;

    // size, initial head, initial tail, initial count
    QueuePointer #( SIZE, 0, 0, SIZE )
        pointer(
            .clk( clk ),
            .rst( rst ),
            .push( push ),
            .pop( pop ),
            .full( full ),
            .empty( empty ),
            .headPtr( headPtr ),
            .tailPtr( tailPtr )
        );
        

    logic [ ENTRY_WIDTH-1:0 ] freeList[ SIZE-1:0 ];

    always_ff @( posedge clk ) begin
        if( rst ) begin
            for( int i = 0; i < SIZE; i++ ) begin
                freeList[i] <= i;
            end
        end
        else begin
            if( push ) begin
                freeList[ tailPtr ] <= pushedData;
            end
        end
    end
    
    always_comb begin
        headData = freeList[ headPtr ];
    end

endmodule : FreeList

module MultiWidthFreeList #(
    parameter SIZE = 16,
    parameter ENTRY_BIT_SIZE = 4,
    parameter PUSH_WIDTH = 4,
    parameter POP_WIDTH = 4,
    parameter INITIAL_LENGTH = SIZE
)( 
input 
    logic clk,
    logic rst,
    logic rstStart,
    logic push [ PUSH_WIDTH ],
    logic pop [ POP_WIDTH ],
    logic [ ENTRY_BIT_SIZE-1:0 ] pushedData [ PUSH_WIDTH ],
output
    logic [ $clog2(SIZE):0 ] count,
    logic [ ENTRY_BIT_SIZE-1:0 ] poppedData [ POP_WIDTH ]
);

    localparam INDEX_BIT_SIZE = $clog2(SIZE);
    typedef logic [INDEX_BIT_SIZE-1: 0] IndexPath;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    typedef logic [INDEX_BIT_SIZE:0] CountPath;
    
    // --- Control headPtr, tailPtr and count
    IndexPath headPtr;
    IndexPath tailPtr;
    logic [ $clog2(PUSH_WIDTH):0 ] pushCount;
    logic [ $clog2(POP_WIDTH):0 ] popCount;
    
        
    MultiWidthQueuePointer #(
        .SIZE( SIZE ),
        .INITIAL_HEAD_PTR( 0 ), 
        .INITIAL_TAIL_PTR( INITIAL_LENGTH ),
        .INITIAL_COUNT( INITIAL_LENGTH ),
        .PUSH_WIDTH( PUSH_WIDTH ),
        .POP_WIDTH( POP_WIDTH )
    ) queuePointer (
        .clk( clk ),
        .rst( rst ),
        .push( pushCount != 0 ),
        .pop( popCount != 0 ),
        .pushCount( pushCount ),
        .popCount( popCount ),
        .headPtr( headPtr ),
        .tailPtr( tailPtr ),
        .count( count )
    );


    // --- Data Array of Free List
    logic we[PUSH_WIDTH];
    Value wv[PUSH_WIDTH];
    IndexPath wa[PUSH_WIDTH];

    Value rv[POP_WIDTH];
    IndexPath ra[POP_WIDTH];
    
    IndexPath rstIndex;

    //NarrowDistributedMultiPortRAM #( 
    DistributedMultiBankRAM #( 
        .ENTRY_NUM( SIZE ), 
        .ENTRY_BIT_SIZE( ENTRY_BIT_SIZE ),
        .READ_NUM( POP_WIDTH ),
        .WRITE_NUM( PUSH_WIDTH )
    ) freeList (
        .clk( clk ),
        .wa( wa ),
        .we( we ),
        .wv( wv ),
        .ra( ra ),
        .rv( rv )
    );
    
    // リセット時に、各エントリの内容をエントリの番号で初期化する
    // すなわち、 entry[0] = 0, entry[1] = 1, entry[2] = 2 ... となる
    always_ff @ (posedge clk) begin
        if (rstStart) begin
            rstIndex <= 0;
        end
        else if ( rstIndex >= SIZE - PUSH_WIDTH ) begin
            rstIndex <= 0;
        end
        else begin
            rstIndex <= rstIndex + PUSH_WIDTH;
        end
    end
    
    
    always_comb begin

        pushCount = 0;
        for (int i = 0; i < PUSH_WIDTH; i++) begin
            if ((tailPtr + pushCount) >= SIZE) begin
                // Compensate the index to point in the freelist
                wa[i] = tailPtr + pushCount - SIZE;
            end
            else begin
                wa[i] = tailPtr + pushCount;
            end
            wv[i] = pushedData[i];
            we[i] = push[i];
            if (push[i]) begin
                pushCount += 1;
            end
        end
        
        // "ra" is serialized for multi-banking.
        for (int i = 0; i < POP_WIDTH; i++) begin
            if ((headPtr + i) >= SIZE) begin
                ra[i] = headPtr + i - SIZE;
            end
            else begin
                ra[i] = headPtr + i;
            end
        end

        popCount = 0;
        for (int i = 0; i < POP_WIDTH; i++) begin
            poppedData[i] = rv[popCount];
            if (pop[i]) begin
                popCount += 1;
            end
        end
        
        if (rst) begin
            for (int i = 0; i < PUSH_WIDTH; i++) begin
                wa[i] = rstIndex + i;
                wv[i] = rstIndex + i;
                // エントリ数が PUSH_WIDTH の整数倍じゃなかった場合の処理
                we[i] = (wa[i] >= rstIndex) && (wa[i] < SIZE);
            end
        end
    end
    
endmodule : MultiWidthFreeList

