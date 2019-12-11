// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- MemoryIF
//

import BasicTypes::*;
import CacheSystemTypes::*;

interface CacheSystemIF( input logic clk, rst );
    
    // ICache
    MemReadAccessReq icMemAccessReq;
    MemAccessReqAck icMemAccessReqAck;
    MemAccessResult icMemAccessResult;
    
    // DCache
    MemAccessReq dcMemAccessReq;
    MemAccessReqAck dcMemAccessReqAck;
    MemAccessResult dcMemAccessResult;
    MemAccessResponse dcMemAccessResponse;
    
    
    modport ICache(
    input
        clk,
        rst,
        icMemAccessResult,
        icMemAccessReqAck,
    output
        icMemAccessReq
    );
    
    modport DCache(
    input
        clk,
        rst,
        dcMemAccessResult,
        dcMemAccessReqAck,
        dcMemAccessResponse,
    output
        dcMemAccessReq
    );

    modport MemoryAccessController(
    input
        clk,
        rst,
        icMemAccessReq,
        dcMemAccessReq,
    output
        icMemAccessResult,
        dcMemAccessResult,
        icMemAccessReqAck,
        dcMemAccessReqAck,
        dcMemAccessResponse
    );
    
endinterface : CacheSystemIF

