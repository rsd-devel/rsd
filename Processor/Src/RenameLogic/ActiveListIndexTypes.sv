// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

//
// Active list related types
// RSD partially flushes the pipeline using active list pointers over 
// a wide area within the processor. To avoid circular references, the related
// types/functions are defined in this file.
//
package ActiveListIndexTypes;

import BasicTypes::*;
import MicroArchConf::*;

localparam ACTIVE_LIST_ENTRY_NUM = CONF_ACTIVE_LIST_ENTRY_NUM;
localparam ACTIVE_LIST_ENTRY_NUM_BIT_WIDTH = $clog2( ACTIVE_LIST_ENTRY_NUM );
typedef logic [ACTIVE_LIST_ENTRY_NUM_BIT_WIDTH-1:0] ActiveListIndexPath;
typedef logic [ACTIVE_LIST_ENTRY_NUM_BIT_WIDTH:0] ActiveListCountPath;

function automatic logic SelectiveFlushDetector(
    input logic detectRange,
    input ActiveListIndexPath headPtr,
    input ActiveListIndexPath tailPtr,
    input logic flushAllInsns,
    input ActiveListIndexPath opPtr
);
    if(!detectRange) begin
        return FALSE;
    end
    else if (flushAllInsns) begin
        return TRUE;
    end
    else if(detectRange && tailPtr >= headPtr) begin
        //  |---h***i***t-------|
        if(opPtr >= headPtr && opPtr < tailPtr) begin
            return TRUE;
        end
        else begin
            return FALSE;
        end
    end
    else if(detectRange && tailPtr < headPtr) begin
        //  |*****t----h***i****|
        if(opPtr >= headPtr && opPtr > tailPtr) begin
            return TRUE;
        end
        //  |**i***t----h*******|
        else if(opPtr < headPtr && opPtr < tailPtr) begin
            return TRUE;
        end
        else begin
            return FALSE;
        end
    end
    else begin
        return FALSE;
    end
endfunction


endpackage

