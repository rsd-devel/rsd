// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


import BasicTypes::*;

//
// Select a way for cache-replacement.
//
module VictimWaySelecter #( parameter WAY_NUM = 2 ) 
(
input
    logic [ WAY_NUM-1:0 ] valid,
    logic unsigned [ $clog2(WAY_NUM)-1:0 ] victimCandidateWayPtr,
output
    logic unsigned [ $clog2(WAY_NUM)-1:0 ] victimWayPtr
);
    logic existInvalidWay;
    logic [ $clog2(WAY_NUM)-1:0 ] invalidWayPtr;
    
    always_comb begin
        existInvalidWay = FALSE;
        invalidWayPtr = 0;
        
        for ( int i = 0; i < WAY_NUM; i++ ) begin
            if ( !valid[i] ) begin
                existInvalidWay = TRUE;
                invalidWayPtr = i;
                break;
            end
        end
        
        victimWayPtr = existInvalidWay ? invalidWayPtr : victimCandidateWayPtr;
    end
endmodule

