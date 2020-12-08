// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Cache flush management unit
//

`include "BasicMacros.sv"

import BasicTypes::*;
import OpFormatTypes::*;
import CacheSystemTypes::*;
import OpFormatTypes::*;
import MemoryMapTypes::*;
import LoadStoreUnitTypes::*;

module CacheFlushManager(
    CacheFlushManagerIF.CacheFlushManager port,
    CacheSystemIF.CacheFlushManager cacheSystem
);

    typedef enum logic[1:0]
    {
        PHASE_FREE          = 0,  // This unit is free
        PHASE_SEND_REQUEST  = 1,  // This unit sends flush requests to caches
        PHASE_PROCESSING    = 2,  // This unit is waiting for completion signals from caches
        PHASE_WAITING       = 3   // Wait for issuing ifence from replayqueue
    } CacheFlushPhase;

    // CacheFlushManager <-> ICache, DCache
    logic icFlushReq, dcFlushReq;

    CacheFlushPhase regPhase, nextPhase;
    logic regIcFlushComplete, nextIcFlushComplete;
    logic regDcFlushComplete, nextDcFlushComplete;

    // CacheFlushManager <-> MemExecStage, ReplayQueue
    logic cacheFlushComplete;

    always_ff @( posedge port.clk ) begin
        if ( port.rst ) begin
            regPhase <= PHASE_FREE;
        end
        else begin
            regPhase <= nextPhase;
        end
    end

    always_comb begin
        nextPhase = regPhase;
        nextIcFlushComplete = regIcFlushComplete;
        nextDcFlushComplete = regDcFlushComplete;

        // to ICache, DCache
        icFlushReq = FALSE;
        dcFlushReq = FALSE;

        // to MemExecStage, ReplayQUeue
        cacheFlushComplete = FALSE;

        case (regPhase)
        default: begin
            nextPhase = PHASE_FREE;
        end
        PHASE_FREE: begin
            if (port.cacheFlushReq) begin
                nextPhase = PHASE_SEND_REQUEST;
            end
        end
        PHASE_SEND_REQUEST: begin
            if (cacheSystem.icFlushReqAck && cacheSystem.dcFlushReqAck) begin
                icFlushReq = TRUE;
                dcFlushReq = TRUE;
                nextIcFlushComplete = FALSE;
                nextDcFlushComplete = FALSE;
                nextPhase = PHASE_PROCESSING;
            end
        end
        PHASE_PROCESSING: begin
            if (cacheSystem.icFlushComplete) begin
                nextIcFlushComplete = TRUE;
            end
            if (cacheSystem.dcFlushComplete) begin
                nextDcFlushComplete = TRUE;
            end

            if ((nextIcFlushComplete || regIcFlushComplete) &&
                (nextDcFlushComplete || regDcFlushComplete)) begin
                nextPhase = PHASE_WAITING;
            end
        end
        PHASE_WAITING: begin
            cacheFlushComplete = TRUE;
            if (port.cacheFlushReq) begin
                nextPhase = PHASE_FREE;
            end
        end
        endcase

        // to ICache, DCache
        cacheSystem.icFlushReq = icFlushReq;
        cacheSystem.dcFlushReq = dcFlushReq;
        cacheSystem.flushComplete = cacheFlushComplete;

        // to MemExecStage, ReplayQUeue
        port.cacheFlushComplete = cacheFlushComplete;
    end

    // Cache flush state
    always_ff @( posedge port.clk ) begin
        if ( port.rst ) begin
            regIcFlushComplete <= FALSE;
            regDcFlushComplete <= FALSE;
        end
        else begin
            regIcFlushComplete <= nextIcFlushComplete;
            regDcFlushComplete <= nextDcFlushComplete;
        end
    end


endmodule : CacheFlushManager