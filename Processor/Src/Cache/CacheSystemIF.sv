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

    // CacheFlushManager
    logic icFlushReqAck;
    logic icFlushComplete;
    logic icFlushReq;
    logic dcFlushReqAck;
    logic dcFlushComplete;
    logic dcFlushReq;
    logic flushComplete;
    
    
    modport ICache(
    input
        clk,
        rst,
        icMemAccessResult,
        icMemAccessReqAck,
        icFlushReq,
        flushComplete,
    output
        icMemAccessReq,
        icFlushReqAck,
        icFlushComplete
    );
    
    modport DCache(
    input
        clk,
        rst,
        dcMemAccessResult,
        dcMemAccessReqAck,
        dcMemAccessResponse,
        dcFlushReq,
        flushComplete,
    output
        dcMemAccessReq,
        dcFlushReqAck,
        dcFlushComplete
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

    modport CacheFlushManager(
    input
        icFlushReqAck,
        icFlushComplete,
        dcFlushReqAck,
        dcFlushComplete,
    output
        icFlushReq,
        dcFlushReq,
        flushComplete
    );
    
endinterface : CacheSystemIF

