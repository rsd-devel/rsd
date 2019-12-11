// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Pick requests.
// a.k.a. priority encoder.
//
module Picker #( 
    parameter ENTRY_NUM = 4,
    parameter GRANT_NUM = 2
)( 
input
    logic [ENTRY_NUM-1:0] req,
output
    logic [ENTRY_NUM-1:0] grant,
    logic [$clog2(ENTRY_NUM)-1:0] grantPtr[GRANT_NUM],
    logic granted[GRANT_NUM]
);
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    
    logic [ENTRY_NUM-1:0] reqTmp;
    
    always_comb begin

        reqTmp = req;
        grant = '0;
        for (int p = 0; p < GRANT_NUM; p++) begin
            
            granted[p] = '0;
            grantPtr[p] = '0;
            
            for (int e = 0; e < ENTRY_NUM; e++) begin
                if(reqTmp[e]) begin
                    grant[e] = '1;
                    granted[p] = '1;
                    grantPtr[p] = e;
                    reqTmp[e] = '0;
                    break;
                end
            end
        end
    end
    
endmodule : Picker


//
// Requests are interleaved.
// ex. ENTRY_NUM = 4, GRANT_NUM = 2 case:
//   granted[0] = pick(req[0], req[2]);
//   granted[0] = pick(req[1], req[3]);
//
//
module InterleavedPicker #( 
    parameter ENTRY_NUM = 4,
    parameter GRANT_NUM = 2
)( 
input
    logic [ENTRY_NUM-1:0] req,
output
    logic [ENTRY_NUM-1:0] grant,
    logic [$clog2(ENTRY_NUM)-1:0] grantPtr[GRANT_NUM],
    logic granted[GRANT_NUM]
);
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    
    logic [ENTRY_NUM-1:0] reqTmp;
    
    always_comb begin

        reqTmp = req;
        grant = '0;
        for (int p = 0; p < GRANT_NUM; p++) begin
            
            granted[p] = '0;
            grantPtr[p] = 0;
            
            for (int e = p; e < ENTRY_NUM; e += GRANT_NUM) begin
                if(reqTmp[e]) begin
                    grant[e] = '1;
                    granted[p] = '1;
                    grantPtr[p] = e;
                    reqTmp[e] = '0;
                    break;
                end
            end
        end
    end
    
endmodule : InterleavedPicker




//
// Pick a request between a head and a tail.
// It outputs an encoded picked position.
// A request that is closer to a tail has a higher priority.
// "tailPtr" refers 1 + "the end of a valid region", thus all requests are invalid
//  if head=tail.
//

module CircularRangePicker #( 
    parameter ENTRY_NUM = 16
)( 
input
    logic [$clog2(ENTRY_NUM)-1:0] headPtr,
    logic [$clog2(ENTRY_NUM)-1:0] tailPtr,
    logic [ENTRY_NUM-1:0] request,
output
    logic [$clog2(ENTRY_NUM)-1:0] grantPtr,
    logic picked
);
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    //localparam ENTRY_NUM = 1 << INDEX_BIT_SIZE;
    
    logic [ENTRY_NUM*2-1:0] rightShifterIn;
    logic [ENTRY_NUM-1:0] shiftedReq;
    logic [INDEX_BIT_SIZE-1:0] shiftedGrant;
    
    // Generate a right shifter.
    // When the width of a shifter is greater than 16, a hand-implemented shifter 
    // is faster than a verilog shift operator.
    generate 
        // Generate special version.
        if(ENTRY_NUM == 16) begin 
            CircularRangePickerRightShifter16 rightShifter(rightShifterIn[30:0], tailPtr, shiftedReq);
        end
        else begin
            CircularRangePickerRightShifter#(ENTRY_NUM*2, INDEX_BIT_SIZE, ENTRY_NUM) 
                rightShifter(rightShifterIn, tailPtr, shiftedReq);
        end
    endgenerate
    
    always_comb begin
        
        // Shift and move a tail to a higer position.
        //  a9876543210  a9876543210
        // <---t***h---><---t***h---> >> tp(7) => <----------t><***h------->
        // <***h---t***><***h---t***> >> tp(3) => <---***h---t><******h---->
        
        // This is equivalent to "shiftedReq = {request, request} >> tailPtr;"
        rightShifterIn = {request, request};

        // Pick the highest request.
        picked = 1'b0;
        shiftedGrant = 0;
        
        for(int i = 0; i < ENTRY_NUM; i++) begin
            if(shiftedReq[i]) begin
                shiftedGrant = i;
                picked = 1'b1;
            end
        end
        
        // Shift and restore original poistion.
        //  a9876543210  a9876543210              a9876543210  a9876543210
        // <-----------><***h-------> + tp(7) => <----***h---><----------->
        // <-----------><******h----> + tp(3) => <--------***><***h------->
        if (shiftedGrant + tailPtr < ENTRY_NUM) begin
            grantPtr = shiftedGrant + tailPtr;
        end
        else begin
            grantPtr = shiftedGrant + tailPtr - ENTRY_NUM;
        end

        //$display("t:%x, h:%x, sr:%b sg:%x, sp:%x", tailPtr, headPtr, shiftedReq, shiftedGrant, grantPtr);


        // Invalidate invalid grant.
        
        // Implementation A: it is faster than B by 1 LUT, but its area is larger 
        // than that of B by 22 LUTs.
        if(tailPtr >= headPtr) begin
            if(ENTRY_NUM + headPtr - tailPtr > shiftedGrant) begin
                picked = 1'b0;
            end
        end 
        else begin
            if(headPtr - tailPtr > shiftedGrant) begin
                picked = 1'b0;
            end
        end

        /*
        // Implementation B.
        if(tailPtr >= headPtr) begin
            if(headPtr > grantPtr || grantPtr >= tailPtr) begin
                picked = 1'b0;
            end
        end begin
            if(headPtr > grantPtr && grantPtr >= tailPtr) begin
                picked = 1'b0;
            end
        end
        */
        
    end
endmodule : CircularRangePicker


//
// --- Internal sub modules.
//

// A special version of a right shift operation for 16 entries.
module CircularRangePickerRightShifter16(
    input logic [30:0] shiftIn,
    input logic [3:0] shiftAmount,
    output logic [15:0] shiftOut
);
    logic [16*2-1:0] shiftTmp;
    always_comb begin
        shiftTmp = shiftIn;
        // A 4:1 selecter will be  mapped to 6 input LUT.
        case(shiftAmount[3:2])
            2'h3: shiftTmp = shiftTmp[30:12];
            2'h2: shiftTmp = shiftTmp[26:8];
            2'h1: shiftTmp = shiftTmp[22:4];
            //2'h0: 
            default: shiftTmp = shiftTmp[18:0];
        endcase
        case(shiftAmount[1:0])
            2'h3: shiftTmp = shiftTmp[18:3];
            2'h2: shiftTmp = shiftTmp[17:2];
            2'h1: shiftTmp = shiftTmp[16:1];
            //2'h0: 
            default: shiftTmp = shiftTmp[15:0];
        endcase
        shiftOut = shiftTmp;
    end
endmodule

// A generic version of a right shift operation.
module CircularRangePickerRightShifter #( 
    parameter INPUT_WIDTH = 32,
    parameter SHIFT_AMOUNT_WIDTH = 4,
    parameter OUTPUT_WIDTH = 16
)(
    input logic [INPUT_WIDTH-1:0] shiftIn,
    input logic [SHIFT_AMOUNT_WIDTH-1:0] shiftAmount,
    output logic [OUTPUT_WIDTH-1:0] shiftOut
);
    always_comb begin
        shiftOut = shiftIn >> shiftAmount;
    end
endmodule
