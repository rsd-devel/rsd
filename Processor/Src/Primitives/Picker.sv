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
            
            // Scan backwards so the lowest index wins by overwriting.
            for (int e = ENTRY_NUM - 1; e >= 0; e--) begin
                if(reqTmp[e]) begin
                    granted[p] = '1;
                    grantPtr[p] = e;
                end
            end
            // Remove only the final choice before selecting the next grant.
            if (granted[p]) begin
                grant[grantPtr[p]] = '1;
                reqTmp[grantPtr[p]] = '0;
            end
        end
    end
    
endmodule : Picker


// Pick one request, returning its encoded position and validity.
// By default, prefer the lowest index, as Picker does.
module EncodedPicker #(
    parameter ENTRY_NUM = 4,
    parameter bit HIGH_INDEX_FIRST = 1'b0
)(
    input logic [ENTRY_NUM-1:0] req,
    output logic [$clog2(ENTRY_NUM)-1:0] grantPtr,
    output logic granted
);
    always_comb begin
        grantPtr = '0;
        granted = 1'b0;
        for (int e = 0; e < ENTRY_NUM; e++) begin
            // Visit higher-priority entries last so they overwrite earlier choices.
            int index;
            index = HIGH_INDEX_FIRST ? e : ENTRY_NUM - 1 - e;
            if (req[index]) begin
                grantPtr = index;
                granted = 1'b1;
            end
        end
    end
endmodule : EncodedPicker


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
    logic [ENTRY_NUM-1:0] headMask;
    logic [ENTRY_NUM-1:0] tailMask;
    logic [ENTRY_NUM-1:0] rangeMask;
    logic [ENTRY_NUM-1:0] validRequest;
    logic [ENTRY_NUM-1:0] maskedRequest;
    logic [INDEX_BIT_SIZE-1:0] wholePtr;
    logic [INDEX_BIT_SIZE-1:0] maskedPtr;
    logic wholePicked;
    logic maskedPicked;

    generate
        for (genvar i = 0; i < ENTRY_NUM; i++) begin
            assign headMask[i] = i < headPtr;
            assign tailMask[i] = i < tailPtr;
        end
    endgenerate
    // Filter both pickers to [headPtr, tailPtr); head == tail is empty.
    assign rangeMask = (tailPtr >= headPtr) ?
        (tailMask & ~headMask) : (tailMask | ~headMask);
    assign validRequest = request & rangeMask;
    assign maskedRequest = validRequest & tailMask;

    EncodedPicker #(
        .ENTRY_NUM(ENTRY_NUM), .HIGH_INDEX_FIRST(1'b1)
    ) wholePicker (
        .req(validRequest),
        .grantPtr(wholePtr), .granted(wholePicked)
    );
    EncodedPicker #(
        .ENTRY_NUM(ENTRY_NUM), .HIGH_INDEX_FIRST(1'b1)
    ) maskedPicker (
        .req(maskedRequest),
        .grantPtr(maskedPtr), .granted(maskedPicked)
    );

    assign picked = maskedPicked | wholePicked;

    always_comb begin
        // Prefer requests below tail, wrapping to the whole vector if empty.
        // With no in-range requests, keep the unused pointer defined at tail.
        grantPtr = tailPtr;
        if (maskedPicked) begin
            grantPtr = maskedPtr;
        end
        else if (wholePicked) begin
            grantPtr = wholePtr;
        end
    end
endmodule : CircularRangePicker
