// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// ARM shifter unit (32bit)
//
// Todo: Rotation operation in a register mode when its shift amount is zero is 
// not implemented correctly and must be fixed.
// 

import BasicTypes::*;
import OpFormatTypes::*;


//
// An straightforward implementation of a shifter unit.
// Do not remove this implementation because this implementation is used for
// verification.
//
module OrgShifter(
input
    ShiftOperandType shiftOperandType,
    ShiftType shiftType,
    ShiftAmountPath immShiftAmount,
    ShiftAmountPath regShiftAmount,
    DataPath dataIn,
    logic carryIn,
output
    DataPath dataOut,
    logic carryOut
);

    typedef struct {
        DataPath dataOut; 
        logic    carryOut;
    } ShiftResult;
    
    //
    // --- Immediate shift
    //
    function automatic ShiftResult OpImmShift(
        ShiftType shiftType, 
        ShiftAmountPath shiftAmount,
        DataPath dataIn,
        logic    carryIn 
    );
        logic [DATA_WIDTH:0] shiftTmp;  // not DataPath
        ShiftResult result;
        DataPath dataOut;
        logic    carryOut;
        
        case( shiftType ) 

        // Logical shift left
        default: begin
        //ST_LSL: begin
            if( shiftAmount == 0 ) begin
                dataOut  = dataIn;
                carryOut = carryIn;
            end
            else begin
                shiftTmp = dataIn << shiftAmount;
                dataOut  = shiftTmp[DATA_WIDTH-1:0];
                carryOut = shiftTmp[DATA_WIDTH];
            end
        end
        
        // Logical shift right
        ST_LSR: begin
            if( shiftAmount == 0 ) begin
                dataOut  = 0;
                carryOut = dataIn[DATA_WIDTH-1];
            end
            else begin
                shiftTmp = {dataIn, 1'b0} >> shiftAmount;
                dataOut  = shiftTmp[DATA_WIDTH:1];
                carryOut = shiftTmp[0];
            end
        end
                    
        // Arithmetic shift right
        ST_ASR: begin
            if( shiftAmount == 0 ) begin
                if( dataIn[DATA_WIDTH-1] == 0 ) begin
                    dataOut  = 0;
                    carryOut = dataIn[DATA_WIDTH-1];
                end
                else begin
                    dataOut  = 32'hffffffff;
                    carryOut = dataIn[DATA_WIDTH-1];
                end
            end 
            else begin
                shiftTmp = {{DATA_WIDTH{dataIn[DATA_WIDTH-1]}}, dataIn, 1'b0} >> shiftAmount;
                dataOut  = shiftTmp[DATA_WIDTH:1];
                carryOut = shiftTmp[0];
            end
        end

        // RRX/Rotate
        ST_ROR: begin
            if( shiftAmount == 0 ) begin
                dataOut  = {carryIn, dataIn[DATA_WIDTH-1:1]};
                carryOut = dataIn[0];
            end
            else begin
                shiftTmp = {dataIn, dataIn, 1'b0} >> shiftAmount;
                dataOut  = shiftTmp[DATA_WIDTH:1];
                carryOut = shiftTmp[0];
            end
        end
        endcase
        
        result.dataOut = dataOut;
        result.carryOut = carryOut;
        return result;
    endfunction : OpImmShift
    
    
    
    //
    // --- Register shift
    // 
    //  Todo:シフト量が32を超えた場合の挙動がおかしい
    //
    function automatic ShiftResult OpRegShift(
    input
        ShiftType shiftType, 
        ShiftAmountPath shiftAmount,
        DataPath           dataIn,
        logic [4:0]        shiftIn,
        logic              carryIn 
    );

        logic [DATA_WIDTH:0] shiftTmp;  // not DataPath
        DataPath    dataOut;
        logic       carryOut;
        ShiftResult result;
        
        case( shiftType ) 

        // Logical shift left
        //ST_LSL: begin
        default: begin
            if( shiftIn == 0 ) begin
                dataOut  = dataIn;
                carryOut = carryIn;
            end
            else begin
                shiftTmp = dataIn << shiftIn;
                dataOut  = shiftTmp[DATA_WIDTH-1:0];
                carryOut = shiftTmp[DATA_WIDTH];
            end
        end
        
        // Logical shift right
        ST_LSR: begin
            if( shiftIn == 0 ) begin
                dataOut  = 0;
                carryOut = dataIn[DATA_WIDTH-1];
            end
            else begin
                shiftTmp = {dataIn, 1'b0} >> shiftIn;
                dataOut  = shiftTmp[DATA_WIDTH:1];
                carryOut = shiftTmp[0];
            end
        end
                    
        // Arithmetic shift right
        ST_ASR: begin
            if( shiftIn == 0 ) begin
                if( dataIn[DATA_WIDTH-1] == 0 ) begin
                    dataOut  = 0;
                    carryOut = dataIn[DATA_WIDTH-1];
                end
                else begin
                    dataOut  = 32'hffffffff;
                    carryOut = dataIn[DATA_WIDTH-1];
                end
            end 
            else begin
                shiftTmp = {{DATA_WIDTH{dataIn[DATA_WIDTH-1]}}, dataIn, 1'b0} >> shiftAmount;
                dataOut  = shiftTmp[DATA_WIDTH:1];
                carryOut = shiftTmp[0];
            end
        end

        // Rotate
        ST_ROR: begin
            if( shiftIn == 0 ) begin
                dataOut  = {carryIn, dataIn[DATA_WIDTH-1:1]};
                carryOut = dataIn[0];
            end
            else begin
                shiftTmp = {dataIn, dataIn, 1'b0} >> shiftIn;
                dataOut  = shiftTmp[DATA_WIDTH:1];
                carryOut = shiftTmp[0];
            end
        end
        endcase

        result.dataOut = dataOut;
        result.carryOut = carryOut;
        return result;
    endfunction : OpRegShift

    
    ShiftResult shiftResult;
    always_comb begin
        case( shiftType )

        // Immediate
        //SOT_IMM: begin

        // Immediate shift
        default: begin
        //SOT_IMM_SHIFT: begin
            shiftResult = OpImmShift( shiftType, immShiftAmount, dataIn, carryIn );
        end
        
        // Register shift
        SOT_REG_SHIFT: begin
            shiftResult = OpRegShift( shiftType, immShiftAmount, dataIn, regShiftAmount, carryIn );
        end

        endcase
        
        dataOut = shiftResult.dataOut;
        carryOut = shiftResult.carryOut;
    end
    

endmodule : OrgShifter



//
// --- An optimized implementation of a shifter unit.
//
module Shifter(
input
    ShiftOperandType shiftOperandType,
    ShiftType shiftType,
    ShiftAmountPath immShiftAmount,
    ShiftAmountPath regShiftAmount,
    DataPath dataIn,
    logic carryIn,
output
    DataPath dataOut,
    logic carryOut
);

    ShiftAmountPath shiftAmount;

    // This shifter unit is implemented with an unified 65-to-33 right shifter.
    logic [DATA_WIDTH*2+1:0] unifiedShiftTmp;
    DataPath unifiedShiftHighIn;
    DataPath unifiedShiftLowIn;
    logic [DATA_WIDTH+1:0] unifiedShiftOut;
    logic [SHIFT_AMOUNT_BIT_SIZE:0] unifiedShiftAmount;
    logic isShiftZero;

    always_comb begin
        
        //
        // --- Select a shift amount.
        //
        case( shiftOperandType )

            // Immediate shift
            default: begin        //SOT_IMM_SHIFT: begin
                shiftAmount = immShiftAmount;
            end
            
            // Register shift
            SOT_REG_SHIFT: begin
                shiftAmount = regShiftAmount;
            end

        endcase
        

        isShiftZero = (shiftAmount == 0) ? TRUE : FALSE;
        

        case( shiftType ) 

        // Logical shift left
        ST_LSL: begin
            //if( shiftAmount == 0 ) begin
            //    dataOut  = dataIn;
            //    carryOut = carryIn;
            //end
            //else begin
            //    shiftTmp = dataIn << shiftAmount;
            //    dataOut  = shiftTmp[DATA_WIDTH-1:0];
            //    carryOut = shiftTmp[DATA_WIDTH];
            //end        
            unifiedShiftAmount = DATA_WIDTH - shiftAmount;
            unifiedShiftHighIn = dataIn;
            unifiedShiftLowIn = 0;
        end
        
        // Logical shift right
        ST_LSR: begin
        
            //if( shiftAmount == 0 ) begin
            //    dataOut  = 0;
            //    carryOut = dataIn[DATA_WIDTH-1];
            //end
            //else begin
            //    shiftTmp = {dataIn, 1'b0} >> shiftAmount;
            //    dataOut  = shiftTmp[DATA_WIDTH:1];
            //    carryOut = shiftTmp[0];
            //end        
        
            //unifiedShiftAmount = isShiftZero ? DATA_WIDTH : shiftAmount;
            unifiedShiftAmount = shiftAmount;
            unifiedShiftHighIn = 0;
            unifiedShiftLowIn = dataIn;
        end
                    
        // Arithmetic shift right
        ST_ASR: begin
            //if( shiftAmount == 0 ) begin
            //    if( dataIn[DATA_WIDTH-1] == 0 ) begin
            //        dataOut  = 0;
            //        carryOut = dataIn[DATA_WIDTH-1];
            //    end
            //    else begin
            //        dataOut  = 32'hffffffff;
            //        carryOut = dataIn[DATA_WIDTH-1];
            //    end
            //end 
            //else begin
            //    shiftTmp = {dataIn, 1'b0} >>> shiftAmount;
            //    dataOut  = shiftTmp[DATA_WIDTH:1];
            //    carryOut = shiftTmp[0];
            //end
            //unifiedShiftAmount = isShiftZero ? DATA_WIDTH : shiftAmount;
            unifiedShiftAmount = shiftAmount;
            unifiedShiftHighIn = {DATA_WIDTH{dataIn[DATA_WIDTH-1]}};
            unifiedShiftLowIn = dataIn;
        end

        // RRX/Rotate
        ST_ROR: begin
            //if( shiftAmount == 0 ) begin
            //    dataOut  = {carryIn, dataIn[DATA_WIDTH-1:1]};
            //    carryOut = dataIn[0];
            //end
            //else begin
            //    shiftTmp = {dataIn, dataIn, 1'b0} >> shiftAmount;
            //    dataOut  = shiftTmp[DATA_WIDTH:1];
            //    carryOut = shiftTmp[0];
            //end
            //unifiedShiftAmount = isShiftZero ? 1 : shiftAmount;
            unifiedShiftAmount = shiftAmount;
            unifiedShiftHighIn = {dataIn[DATA_WIDTH-1:1], (isShiftZero ? carryIn : dataIn[0])};
            unifiedShiftLowIn = dataIn;
        end
        endcase


        // Source of a 65-to-33 right shifter.
        unifiedShiftTmp = {carryIn, unifiedShiftHighIn, unifiedShiftLowIn, 1'b0};
        

        // Optimized implementation of 65-to-33 right shifter.
        // Original implementation:
        //   unifiedShiftOut = unifiedShiftTmp >> unifiedShiftAmount;
        /*
        unifiedShiftTmp = unifiedShiftAmount[5] ? unifiedShiftTmp[65:32] : unifiedShiftTmp[64:0];
        unifiedShiftTmp = unifiedShiftAmount[4] ? unifiedShiftTmp[64:16] : unifiedShiftTmp[48:0];
        unifiedShiftTmp = unifiedShiftAmount[3] ? unifiedShiftTmp[48:8] :  unifiedShiftTmp[40:0];
        unifiedShiftTmp = unifiedShiftAmount[2] ? unifiedShiftTmp[40:4] :  unifiedShiftTmp[36:0];
        unifiedShiftTmp = unifiedShiftAmount[1] ? unifiedShiftTmp[36:2] :  unifiedShiftTmp[34:0];
        unifiedShiftTmp = unifiedShiftAmount[0] ? unifiedShiftTmp[34:1] :  unifiedShiftTmp[33:0];
        */
        
        // Each 4:1 selector will be synthesized to 6:1 LUT.
        case(unifiedShiftAmount[5:4])
            2'h3: unifiedShiftTmp = 49'hx;
            2'h2: unifiedShiftTmp = {15'hx, unifiedShiftTmp[65:32]};
            2'h1: unifiedShiftTmp = unifiedShiftTmp[64:16];
            2'h0: unifiedShiftTmp = unifiedShiftTmp[48:0];
        endcase
        case(unifiedShiftAmount[3:2])
            2'h3: unifiedShiftTmp = unifiedShiftTmp[48:12];
            2'h2: unifiedShiftTmp = unifiedShiftTmp[44:8];
            2'h1: unifiedShiftTmp = unifiedShiftTmp[40:4];
            2'h0: unifiedShiftTmp = unifiedShiftTmp[36:0];
        endcase
        case(unifiedShiftAmount[1:0])
            2'h3: unifiedShiftTmp = unifiedShiftTmp[36:3];
            2'h2: unifiedShiftTmp = unifiedShiftTmp[35:2];
            2'h1: unifiedShiftTmp = unifiedShiftTmp[34:1];
            2'h0: unifiedShiftTmp = unifiedShiftTmp[33:0];
        endcase

        unifiedShiftOut = unifiedShiftTmp;
        
        
        // Output results.
        dataOut = unifiedShiftOut[DATA_WIDTH:1];
        
        case( shiftType ) 
            // Logical shift left
            ST_LSL: carryOut = unifiedShiftOut[DATA_WIDTH+1];
            
            // Logical shift right
            // Arithmetic shift right
            // RRX/Rotate
            default: carryOut = unifiedShiftOut[0];
        endcase
    end
    

endmodule : Shifter

