// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import BasicTypes::*;
import CacheSystemTypes::*;
import OpFormatTypes::*;

module TestCacheSystemTop #(
    parameter INIT_HEX_FILE = "../../Src/Verification/TestCode/C/Dhrystone/code-100k.hex"
)(
    input
        logic clk_p, clk_n, rstTrigger,
    output
        logic rstOut,
    input
        logic       icRE,
        AddrPath    icNextReadAddrIn,
        logic       [ MEM_ISSUE_WIDTH-1:0 ] dcRE,
        AddrPath    [ MEM_ISSUE_WIDTH-1:0 ] dcReadAddrIn,
        logic       dcWE,
        DataPath    dcWriteDataIn,
        AddrPath    dcWriteAddrIn,
        MemAccessSizeType dcWriteAccessSize,
    output
        logic       [ FETCH_WIDTH-1:0 ] icReadHit,
        DataPath    [ FETCH_WIDTH-1:0 ] icReadDataOut,
        logic       [ MEM_ISSUE_WIDTH-1:0 ] dcReadHit,
        DataPath    [ MEM_ISSUE_WIDTH-1:0 ] dcReadDataOut,
        logic       dcWriteHit,
        MemAccessResult dcMemAccessResult,
        logic dcFillReq, dcFillAck,
        logic dcMiss, dcReplace,
        logic dcFillerBusy,
        AddrPath dcFillAddr, dcMissAddr, dcReplaceAddr,
        WayPtr dcFillWayPtr, dcVictimWayPtr,
        LineDataPath dcFillData, dcReplaceData
    );
    
    // Clock and Reset
    logic clk, memCLK, rst, mmcmLocked;
    `ifdef RSD_SYNTHESIS
        /*
        SingleClock clkgen( clk_p, clk_n, clk );
        assign memCLK = clk;
        assign mmcmLocked = TRUE;
        */
        MultiClock clkgen(
            .CLK_IN1_P(clk_p),
            .CLK_IN1_N(clk_n),
            .CLK_OUT1(clk),
            .CLK_OUT2(memCLK),
            .RESET(rstTrigger),
            .LOCKED(mmcmLocked)
        );
    `else
        assign clk = clk_p;
        initial memCLK <= FALSE;
        always_ff @ (posedge clk) memCLK <= ~memCLK;
        assign mmcmLocked = TRUE;
    `endif
    
    ResetController rstController(.*);
    assign rstOut = rst;
    
    // signals
    AddrPath icReadAddrIn;
    
    // interfaces
    FetchStageIF ifStageIF( clk, rst );
    LoadStoreUnitIF loadStoreUnitIF( clk, rst );
    CacheSystemIF cacheSystemIF( clk, rst, memCLK );
    
    // processor modules
    ICache iCache( ifStageIF, cacheSystemIF );
    ICacheFiller iCacheFiller( cacheSystemIF );
    DCache dCache( loadStoreUnitIF, cacheSystemIF );
    DCacheFiller dCacheFiller( cacheSystemIF );
    Memory #( .INIT_HEX_FILE(INIT_HEX_FILE) ) memory ( cacheSystemIF );
    
    always_comb begin
        // Input of this module.
        ifStageIF.icRE = icRE;
        ifStageIF.icReadAddrIn = icReadAddrIn;
        ifStageIF.icNextReadAddrIn = icNextReadAddrIn;
        loadStoreUnitIF.dcWE = dcWE;
        loadStoreUnitIF.dcWriteDataIn = dcWriteDataIn;
        loadStoreUnitIF.dcWriteAddrIn = dcWriteAddrIn;
        loadStoreUnitIF.dcWriteAccessSize = dcWriteAccessSize;
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            loadStoreUnitIF.dcRE[i] = dcRE[i];
            loadStoreUnitIF.dcReadAddrIn[i] = dcReadAddrIn[i];
        end
        
        // Output of this module.
        for ( int i = 0; i < FETCH_WIDTH; i++ ) begin
            icReadHit[i] = ifStageIF.icReadHit[i];
            icReadDataOut[i] = ifStageIF.icReadDataOut[i];
        end
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            dcReadHit[i] = loadStoreUnitIF.dcReadHit[i];
            dcReadDataOut[i] = loadStoreUnitIF.dcReadDataOut[i];
        end
        dcWriteHit = loadStoreUnitIF.dcWriteHit;
        
        // Debug
        dcMemAccessResult = cacheSystemIF.dcMemAccessResult;
        dcFillReq = cacheSystemIF.dcFillReq;
        dcFillAck = cacheSystemIF.dcFillAck;
        dcMiss = cacheSystemIF.dcMiss;
        dcReplace = cacheSystemIF.dcReplace;
        dcFillerBusy = cacheSystemIF.dcFillerBusy;
        dcFillAddr = cacheSystemIF.dcFillAddr;
        dcMissAddr = cacheSystemIF.dcMissAddr;
        dcReplaceAddr = cacheSystemIF.dcReplaceAddr;
        dcFillWayPtr = cacheSystemIF.dcFillWayPtr;
        dcVictimWayPtr = cacheSystemIF.dcVictimWayPtr;
        dcFillData = cacheSystemIF.dcFillData;
        dcReplaceData = cacheSystemIF.dcReplaceData;
    end
    
    always_ff @(posedge clk) begin
        if ( rst )
            icReadAddrIn <= 0;
        else
            icReadAddrIn <= icNextReadAddrIn;
    end
endmodule
