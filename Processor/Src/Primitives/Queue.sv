// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Controller implementation of a queue (FIFO).
//

`include "BasicMacros.sv"

import BasicTypes::*;

//
// 1-input/1-output queue.
// The "tailPtr" points the address of a next pushed entry.
//
module QueuePointer #( parameter
    SIZE = 1,
    INITIAL_HEAD_PTR = 0,
    INITIAL_TAIL_PTR = 0,
    INITIAL_COUNT = 0
)(
input
    logic clk,
    logic rst,
    logic push,
    logic pop,
output
    logic full,
    logic empty,
    logic [$clog2(SIZE)-1:0] headPtr,
    logic [$clog2(SIZE)-1:0] tailPtr
);

    localparam BIT_WIDTH = $clog2( SIZE );
    typedef logic [BIT_WIDTH-1:0] IndexPath;
    typedef logic [BIT_WIDTH:0] CountPath;

    IndexPath regHeadStorage, nextHeadStorage;
    IndexPath regTailStorage, nextTailStorage;
    CountPath regCount, nextCount;

    always_ff @( posedge clk ) begin
        if (rst) begin
            regHeadStorage <= INITIAL_HEAD_PTR;
            regTailStorage <= INITIAL_TAIL_PTR;
            regCount <= INITIAL_COUNT;

            //assert( INITIAL_HEAD + INITIAL_COUNT == INITIAL_TAIL );
        end
        else begin
            regHeadStorage <= nextHeadStorage;
            regTailStorage <= nextTailStorage;
            regCount <= nextCount;
        end
    end

    always_comb begin
        full = ( regCount == SIZE ) ? TRUE : FALSE;
        empty = ( regCount == 0 ) ? TRUE : FALSE;

        nextHeadStorage = regHeadStorage;
        nextTailStorage = regTailStorage;
        nextCount = regCount;

        if (push) begin
            if (regTailStorage == SIZE-1) begin
                nextTailStorage = 0;
            end
            else begin
                nextTailStorage++;
            end

            nextCount++;
        end

        if (pop) begin
            if (regHeadStorage == SIZE-1) begin
                nextHeadStorage = 0;
            end
            else begin
                nextHeadStorage++;
            end

            nextCount--;
        end

        headPtr = regHeadStorage;
        tailPtr = regTailStorage;
    end

    // Assertion
    `RSD_ASSERT_CLK(clk, !(full && push), "Push to a full queue.");
    `RSD_ASSERT_CLK(clk, !(empty && pop), "Pop from an empty queue.");
endmodule

//
// 1-input/1-output queue with its entry count.
// The "tailPtr" points the address of a next pushed entry.
//
module QueuePointerWithEntryCount #( parameter
    SIZE = 1,
    INITIAL_HEAD_PTR = 0,
    INITIAL_TAIL_PTR = 0,
    INITIAL_COUNT = 0
)( 
input 
    logic clk,
    logic rst,
    logic push,
    logic pop,
output
    logic full,
    logic empty,
    logic [$clog2(SIZE)-1:0] headPtr,
    logic [$clog2(SIZE)-1:0] tailPtr,
    logic [$clog2(SIZE):0] count
);

    localparam BIT_WIDTH = $clog2( SIZE );
    typedef logic [BIT_WIDTH-1:0] IndexPath;
    typedef logic [BIT_WIDTH:0] CountPath;

    IndexPath regHeadStorage, nextHeadStorage;
    IndexPath regTailStorage, nextTailStorage;
    CountPath regCount, nextCount;

    always_ff @( posedge clk ) begin
        if (rst) begin
            regHeadStorage <= INITIAL_HEAD_PTR;
            regTailStorage <= INITIAL_TAIL_PTR;
            regCount <= INITIAL_COUNT;
            
            //assert( INITIAL_HEAD + INITIAL_COUNT == INITIAL_TAIL );
        end
        else begin
            regHeadStorage <= nextHeadStorage;
            regTailStorage <= nextTailStorage;
            regCount <= nextCount;
        end
    end
    
    always_comb begin
        full = ( regCount == SIZE ) ? TRUE : FALSE;
        empty = ( regCount == 0 ) ? TRUE : FALSE;
    
        nextHeadStorage = regHeadStorage;
        nextTailStorage = regTailStorage;
        nextCount = regCount;

        if (push) begin
            if (regTailStorage == SIZE-1) begin
                nextTailStorage = 0;
            end
            else begin
                nextTailStorage++;
            end

            nextCount++;
        end
        if (pop) begin
            if (regHeadStorage == SIZE-1) begin
                nextHeadStorage = 0;
            end
            else begin
                nextHeadStorage++;
            end

            nextCount--;
        end
        
        headPtr = regHeadStorage;
        tailPtr = regTailStorage;
        count = regCount;
    end

    // Assertion
    `RSD_ASSERT_CLK(clk, !(full && push), "Push to a full queue.");
    `RSD_ASSERT_CLK(clk, !(empty && pop), "Pop from an empty queue.");

endmodule

//
// N-input/N-output queue.
// The "tailPtr" points the address of a next pushed entry.
//
module MultiWidthQueuePointer #( parameter
    SIZE = 1,
    INITIAL_HEAD_PTR = 0,
    INITIAL_TAIL_PTR = 0,
    INITIAL_COUNT = 0,
    PUSH_WIDTH = 1,
    POP_WIDTH = 1,
    ENABLE_SPECIFIED_ENTRY_NUM = FALSE
)(
input
    logic clk,
    logic rst,
    logic push,
    logic pop,
    logic [$clog2(PUSH_WIDTH):0] pushCount,
    logic [$clog2(POP_WIDTH):0] popCount,
output
    logic [$clog2(SIZE)-1:0] headPtr,
    logic [$clog2(SIZE)-1:0] tailPtr,
    logic [$clog2(SIZE):0] count
);

    localparam INDEX_BIT_WIDTH = $clog2(SIZE);
    typedef logic [INDEX_BIT_WIDTH-1:0] IndexPath;
    typedef logic unsigned [INDEX_BIT_WIDTH:0] CountPath;

    IndexPath regHead, nextHead;
    IndexPath regTail, nextTail;
    CountPath regCount, nextCount;

    always_ff @(posedge clk) begin
        if(rst) begin
            regHead <= INITIAL_HEAD_PTR;
            regTail <= INITIAL_TAIL_PTR;
            regCount <= INITIAL_COUNT;
        end
        else begin
            regHead <= nextHead;
            regTail <= nextTail;
            regCount <= nextCount;
        end
    end

    always_comb begin
        nextTail = regTail;
        if (push) begin
            nextTail += pushCount;

            if (nextTail >= SIZE) begin
                nextTail -= SIZE;
            end
        end
    end

    always_comb begin
        nextHead = regHead;
        if (pop) begin
            nextHead += popCount;

            if (nextHead >= SIZE) begin
                nextHead -= SIZE;
            end
        end
        
    end

    always_comb begin
        nextCount = regCount;
        if(push) begin
            nextCount += pushCount;
        end
        if(pop) begin
            nextCount -= popCount;
        end

        headPtr = regHead;
        tailPtr = regTail;
        count = regCount;
    end

    `RSD_ASSERT_CLK(clk, rst || regCount <= SIZE, "The count of a queue exceeds its size.");

endmodule

//
// N-input/N-output queue.
// The "tailPtr" points the address of a next pushed entry.
// Tail pointer and count is recovered in one cycle.
//
module SetTailMultiWidthQueuePointer #( parameter
    SIZE = 1,
    INITIAL_HEAD_PTR = 0,
    INITIAL_TAIL_PTR = 0,
    INITIAL_COUNT = 0,
    PUSH_WIDTH = 1,
    POP_WIDTH = 1
)(
input
    logic clk,
    logic rst,
    logic push,
    logic pop,
    logic [$clog2(PUSH_WIDTH):0] pushCount,
    logic [$clog2(POP_WIDTH):0] popCount,
    logic setTail,
    logic [$clog2(SIZE)-1:0] setTailPtr,
output
    logic [$clog2(SIZE)-1:0] headPtr,
    logic [$clog2(SIZE)-1:0] tailPtr,
    logic [$clog2(SIZE):0] count
);

    localparam INDEX_BIT_WIDTH = $clog2(SIZE);
    typedef logic [INDEX_BIT_WIDTH-1:0] IndexPath;
    typedef logic unsigned [INDEX_BIT_WIDTH:0] CountPath;

    IndexPath regHead, nextHead;
    IndexPath regTail, nextTail;
    IndexPath roundedSetTailPtr;
    CountPath regCount, nextCount;
    always_ff @(posedge clk) begin
        if (rst) begin
            regHead <= INITIAL_HEAD_PTR;
            regTail <= INITIAL_TAIL_PTR;
            regCount <= INITIAL_COUNT;

            //assert( INITIAL_HEAD + INITIAL_COUNT == INITIAL_TAIL );
        end
        else begin
            regHead <= nextHead;
            regTail <= nextTail;
            regCount <= nextCount;
        end
    end

    always_comb begin
        nextTail = regTail;
        if (push) begin
            nextTail += pushCount;
        
            if (nextTail >= SIZE) begin
                nextTail -= SIZE;
            end
        end
        else if (setTail) begin
            nextTail = roundedSetTailPtr;
        end
    end

    always_comb begin
        nextHead = regHead;
        if (pop) begin
            nextHead += popCount;

            if (nextHead >= SIZE) begin
                nextHead -= SIZE;
            end
        end
    end

    always_comb begin
        nextCount = regCount;
        roundedSetTailPtr = setTailPtr;
        if (push) begin
            nextCount += pushCount;
        end
        else if (setTail) begin
            if (setTailPtr >= SIZE) begin
                roundedSetTailPtr = setTailPtr - SIZE;
            end

            nextCount = ( regHead <= roundedSetTailPtr ) ? 
                roundedSetTailPtr - regHead : SIZE + roundedSetTailPtr - regHead;
        end
        if (pop) begin
            nextCount -= popCount;
        end

        headPtr = regHead;
        tailPtr = regTail;
        count = regCount;
    end

    `RSD_ASSERT_CLK(clk, rst || regCount <= SIZE, "The count of a queue exceeds its size.");

endmodule



//
// N-input/N-output queue.
// In this queue, the tail pointer can be popped and pushed.
// The "tailPtr" points the address of a next pushed entry.
//
module BiTailMultiWidthQueuePointer #( parameter
    SIZE = 1,
    INITIAL_HEAD_PTR = 0,
    INITIAL_TAIL_PTR = 0,
    INITIAL_COUNT = 0,
    PUSH_WIDTH = 1,
    POP_WIDTH = 1
)(
input
    logic clk,
    logic rst,
    logic pushTail,
    logic popTail,
    logic popHead,
    logic [$clog2(PUSH_WIDTH):0] pushTailCount,
    logic [$clog2(POP_WIDTH):0] popTailCount,
    logic [$clog2(POP_WIDTH):0] popHeadCount,
output
    logic [$clog2(SIZE)-1:0] headPtr,
    logic [$clog2(SIZE)-1:0] tailPtr,
    logic [$clog2(SIZE):0] count
);

    localparam INDEX_BIT_WIDTH = $clog2(SIZE);
    typedef logic [INDEX_BIT_WIDTH-1:0] IndexPath;
    typedef logic unsigned [INDEX_BIT_WIDTH:0] CountPath;

    IndexPath regHead, nextHead;
    IndexPath regTail, nextTail;
    CountPath regCount, nextCount;

    always_ff @(posedge clk) begin
        if(rst) begin
            regHead <= INITIAL_HEAD_PTR;
            regTail <= INITIAL_TAIL_PTR;
            regCount <= INITIAL_COUNT;
        end
        else begin
            regHead <= nextHead;
            regTail <= nextTail;
            regCount <= nextCount;
        end
    end

    always_comb begin
        nextHead = regHead;

        if (popHead) begin
            nextHead += popHeadCount;
            if (nextHead >= SIZE) begin
                nextHead -= SIZE;
            end
        end
    end

    always_comb begin
        nextTail = regTail;

        if (pushTail) begin
            nextTail += pushTailCount;
            
            if (nextTail >= SIZE) begin
                nextTail -= SIZE;
            end
        end
        else if (popTail) begin
            nextTail -= popTailCount;

            if (nextTail >= SIZE) begin
                nextTail += SIZE;
            end
        end
    end

    always_comb begin
        nextCount = regCount;
        if (pushTail) begin
            nextCount += pushTailCount;

        end
        else if (popTail) begin
            nextCount -= popTailCount;
        end

        if(popHead) begin
            nextCount -= popHeadCount;
        end

        headPtr = regHead;
        tailPtr = regTail;
        count = regCount;
    end

    // Assertion
    `RSD_ASSERT_CLK(clk, rst || regCount <= SIZE, "The count of a queue exceeds its size.");
    `RSD_ASSERT_CLK(clk, rst || !(pushTail && popTail), "BiTailMultiWidthQueuePointer is pushed and popped simultaneously.");

endmodule


//
// N-input/N-output queue.
// In this queue, the tail pointer can be popped and pushed.
// The "tailPtr" points the address of a next pushed entry.
// Tail pointer and count is recovered in one cycle.
//
module SetTailBiTailMultiWidthQueuePointer #( parameter
    SIZE = 1,
    INITIAL_HEAD_PTR = 0,
    INITIAL_TAIL_PTR = 0,
    INITIAL_COUNT = 0,
    PUSH_WIDTH = 1,
    POP_WIDTH = 1
)(
input
    logic clk,
    logic rst,
    logic pushTail,
    logic popTail,
    logic popHead,
    logic [$clog2(PUSH_WIDTH):0] pushTailCount,
    logic [$clog2(POP_WIDTH):0] popTailCount,
    logic [$clog2(POP_WIDTH):0] popHeadCount,
    logic setTail,
    logic [$clog2(SIZE)-1:0] setTailPtr,
output
    logic [$clog2(SIZE)-1:0] headPtr,
    logic [$clog2(SIZE)-1:0] tailPtr,
    logic [$clog2(SIZE):0] count
);

    localparam INDEX_BIT_WIDTH = $clog2(SIZE);
    typedef logic [INDEX_BIT_WIDTH-1:0] IndexPath;
    typedef logic unsigned [INDEX_BIT_WIDTH:0] CountPath;

    IndexPath regHead, nextHead;
    IndexPath regTail, nextTail;
    IndexPath roundedSetTailPtr;
    CountPath regCount, nextCount;

    always_ff @(posedge clk) begin
        if(rst) begin
            regHead <= INITIAL_HEAD_PTR;
            regTail <= INITIAL_TAIL_PTR;
            regCount <= INITIAL_COUNT;

            //assert( INITIAL_HEAD + INITIAL_COUNT == INITIAL_TAIL );
        end
        else begin
            regHead <= nextHead;
            regTail <= nextTail;
            regCount <= nextCount;
        end
    end

    always_comb begin
        nextHead = regHead;

        if (popHead) begin
            nextHead += popHeadCount;
            if (nextHead >= SIZE) begin
                nextHead -= SIZE;
            end
        end
    end

    always_comb begin
        nextTail = regTail;

        if (pushTail) begin
            nextTail += pushTailCount;
            
            if (nextTail >= SIZE) begin
                nextTail -= SIZE;
            end
        end
        else if (popTail) begin
            nextTail -= popTailCount;

            if (nextTail >= SIZE) begin
                nextTail += SIZE;
            end
        end
        else if (setTail) begin
            nextTail = roundedSetTailPtr;
        end
    end

    always_comb begin
        nextCount = regCount;
        roundedSetTailPtr = setTailPtr;
        
        if (pushTail) begin
            nextCount += pushTailCount;
        end
        else if (popTail) begin
            nextCount -= popTailCount;
        end
        else if (setTail) begin
            if (setTailPtr >= SIZE) begin
                roundedSetTailPtr = setTailPtr - SIZE;
            end

            nextCount = ( regHead <= roundedSetTailPtr ) 
                ? roundedSetTailPtr - regHead : SIZE + roundedSetTailPtr - regHead;
        end

        if (popHead) begin
            nextCount -= popHeadCount;
        end

        headPtr = regHead;
        tailPtr = regTail;
        count = regCount;
    end

    `RSD_ASSERT_CLK(clk, rst || regCount <= SIZE, "The count of a queue exceeds its size.");
    `RSD_ASSERT_CLK(clk, rst || !(pushTail && popTail), "BiTailMultiWidthQueuePointer is pushed and popped simultaneously.");

endmodule

