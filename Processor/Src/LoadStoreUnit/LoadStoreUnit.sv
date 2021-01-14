// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Load/store unit.
//

`include "BasicMacros.sv"

import BasicTypes::*;
import OpFormatTypes::*;
import LoadStoreUnitTypes::*;
import MemoryMapTypes::*;
import DebugTypes::*;
import CacheSystemTypes::*;

module LoadStoreUnit(
    LoadStoreUnitIF.LoadStoreUnit port,
    ControllerIF.LoadStoreUnit ctrl
);
    // DCache/MSHR のラインとして読んだロードデータを、
    // アドレスのオフセットに合わせてシフト
    function automatic DataPath ShiftCacheLineData(DCacheLinePath srcLine, PhyAddrPath addr);
        DataPath data;
        data = srcLine >> (addr[DCACHE_LINE_BYTE_NUM_BIT_WIDTH-1:0] * 8);
        return data;
    endfunction
    function automatic DataPath ShiftForwardedData(LSQ_BlockDataPath srcLine, PhyAddrPath addr);
        DataPath data;
        data = srcLine >> (addr[LSQ_BLOCK_BYTE_WIDTH_BIT_SIZE-1:0] * 8);
        return data;
    endfunction

    // ゼロ拡張or符号拡張
    function automatic DataPath ExtendLoadData(DataPath loadData,MemAccessMode mode);
        case (mode.size)
        MEM_ACCESS_SIZE_BYTE:
            return mode.isSigned ?
                { { 24{ loadData[7] } }, loadData[7:0] }:
                { { 24{ 1'b0 } }, loadData[7:0] };
        MEM_ACCESS_SIZE_HALF_WORD:
            return mode.isSigned ?
                { { 16{ loadData[15] } }, loadData[15:0] } :
                { { 16{ 1'b0 } }, loadData[15:0] };
        default: //MEM_ACCESS_SIZE_WORD,MEM_ACCESS_SIZE_VEC:
            return loadData;
        endcase
    endfunction


    // Pipeline:
    // ----------------------------->
    // ADDR  | D$TAG | D$DATA | WB
    //       |  LSQ  |        |
    //
    // LSQ is accessed in the D$TAG stage (MemoryTagAccessStage) and D$DATA is accessed
    // after this stage, thus forwarded results must be latched.

    logic storeLoadForwardedReg[LOAD_ISSUE_WIDTH];
    LSQ_BlockDataPath forwardedLoadDataReg[LOAD_ISSUE_WIDTH];
    // MSHRからのLoad
    logic mshrReadHitReg[LOAD_ISSUE_WIDTH];
    DCacheLinePath mshrReadDataReg[LOAD_ISSUE_WIDTH];

    AddrPath loadAddrReg[LOAD_ISSUE_WIDTH];
    MemAccessMode loadMemAccessSizeReg[LOAD_ISSUE_WIDTH];

    always_ff@(posedge port.clk)
    begin
        for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            if (port.rst) begin
                storeLoadForwardedReg[i] <= FALSE;
                forwardedLoadDataReg[i] <= '0;
                mshrReadHitReg[i] <= FALSE;
                mshrReadDataReg[i] <= '0;
                loadAddrReg[i] <= '0;
                loadMemAccessSizeReg[i] <= MEM_ACCESS_SIZE_BYTE;
            end
            else if (!ctrl.backEnd.stall) begin
                storeLoadForwardedReg[i] <= port.storeLoadForwarded[i];
                forwardedLoadDataReg[i] <= port.forwardedLoadData[i];
                mshrReadHitReg[i] <= port.mshrReadHit[i];
                mshrReadDataReg[i] <= port.mshrReadData[i];
                loadAddrReg[i] <=  port.executedLoadAddr[i];
                loadMemAccessSizeReg[i] <= port.executedLoadMemAccessMode[i];
            end
        end
    end


    LSQ_BlockDataPath loadLSQ_BlockData[LOAD_ISSUE_WIDTH];
    DataPath shiftedLoadData[LOAD_ISSUE_WIDTH];
    DataPath extendedLoadData[LOAD_ISSUE_WIDTH];
    always_comb begin
        for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            port.executedLoadVectorData[i] = 0;
        end
        
        for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            loadLSQ_BlockData[i] = 
                storeLoadForwardedReg[i] ? forwardedLoadDataReg[i] :
                mshrReadHitReg[i] ? mshrReadDataReg[i] :
                                    port.dcReadData[i];
            port.executedLoadVectorData[i] = loadLSQ_BlockData[i];

            shiftedLoadData[i] = 
                storeLoadForwardedReg[i] ? ShiftForwardedData(forwardedLoadDataReg[i], loadAddrReg[i]) :
                mshrReadHitReg[i] ? ShiftCacheLineData(mshrReadDataReg[i], loadAddrReg[i]) :
                                    ShiftCacheLineData(port.dcReadData[i], loadAddrReg[i]);
            extendedLoadData[i] = ExtendLoadData(shiftedLoadData[i], loadMemAccessSizeReg[i]);
        end

        port.executedLoadData = extendedLoadData;
    end


    // From the rename stage.
    always_comb begin
        port.allocatable = port.loadQueueAllocatable &&    
            port.storeQueueAllocatable && !port.busyInRecovery;
    end

endmodule : LoadStoreUnit

