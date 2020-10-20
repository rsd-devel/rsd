// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Micro op decoder
//


import BasicTypes::*;
import MicroOpTypes::*;
import OpFormatTypes::*;


function automatic void EmitInvalidOp(
    output OpInfo op
);
    op = '0;
    op.valid = FALSE;
endfunction


//
// Modify micro op information.
//

function automatic OpInfo ModifyMicroOp(
    input OpInfo src,
    input MicroOpIndex mid,
    input logic split,
    input logic last
);
    OpInfo op;
    op = src;
    op.mid = mid;
    op.split = split;
    op.last = last;
    return op;
endfunction


//
//  RISCV Instruction Decoder
//


//
// --- 即値整数演算, シフト含む
//
function automatic void RISCV_EmitOpImm(
    output OpInfo  opInfo,
    input RISCV_ISF_Common isf,
    input LScalarRegNumPath srcRegNumA,
    input LScalarRegNumPath srcRegNumB,
    input LScalarRegNumPath dstRegNum,
    input logic unsupported
);
    RISCV_ISF_I isfI;
    RISCV_ISF_R isfR;
    OpFunct3 opFunct3;
    ShiftFunct7 shiftFunct7;
    RISCV_IntOperandImmShift intOperandImmShift;
    logic isShift;

    IntALU_Code aluCode;

    isfI = isf;
    isfR = isf;
    opFunct3 = OpFunct3'(isfR.funct3);
    shiftFunct7 = ShiftFunct7'(isfR.funct7);
    isShift = ( ( opFunct3 == OP_FUNCT3_SLL ) || ( opFunct3 == OP_FUNCT3_SRL_SRA ) );


    // 論理レジスタ番号
`ifdef RSD_ENABLE_VECTOR_PATH
    opInfo.operand.intOp.dstRegNum.isVector  = FALSE;
    opInfo.operand.intOp.srcRegNumA.isVector = FALSE;
    opInfo.operand.intOp.srcRegNumB.isVector = FALSE;
`endif
    opInfo.operand.intOp.dstRegNum.regNum  = dstRegNum;
    opInfo.operand.intOp.srcRegNumA.regNum = srcRegNumA;
    opInfo.operand.intOp.srcRegNumB.regNum = srcRegNumB;

    // 即値
    opInfo.operand.intOp.shiftType = SOT_IMM_SHIFT ;

    intOperandImmShift.shift        =  isShift ? isfR.rs2 : '0;
    intOperandImmShift.shiftType    =  ( opFunct3 == OP_FUNCT3_SLL ) ? ST_LSL :
                                    ( ( opFunct3 == OP_FUNCT3_SRL_SRA ) && ( shiftFunct7 == SHIFT_FUNCT7_SRL ) ) ? ST_LSR :
                                    ( ( opFunct3 == OP_FUNCT3_SRL_SRA ) && ( shiftFunct7 == SHIFT_FUNCT7_SRA ) ) ? ST_ASR :
                                    ST_ROR;
    intOperandImmShift.isRegShift   = FALSE;
    intOperandImmShift.imm          = isShift ? ShamtExtention( isfR ) : I_TypeImmExtention( isfI );
    intOperandImmShift.immType      = RISCV_IMM_I;

    opInfo.operand.intOp.shiftIn   = intOperandImmShift;


    // ALU
    RISCV_DecodeOpImmFunct3( aluCode, opFunct3 );
    opInfo.operand.intOp.aluCode = aluCode;

    // レジスタ書き込みを行うかどうか
    // ゼロレジスタへの書き込みは書き込みフラグをFALSEとする
    opInfo.writeReg  = ( dstRegNum != ZERO_REGISTER ) ? TRUE : FALSE;

    // 論理レジスタを読むかどうか
    opInfo.opTypeA = OOT_REG;
    opInfo.opTypeB = OOT_IMM;

    // 命令の種類
    opInfo.mopType = MOP_TYPE_INT;
    opInfo.mopSubType.intType = isShift ? INT_MOP_TYPE_SHIFT : INT_MOP_TYPE_ALU;

    // 条件コード
    opInfo.cond = COND_AL;

    // 未定義命令
    opInfo.unsupported = unsupported;
    opInfo.undefined = FALSE;

    // Serialized
    opInfo.serialized = FALSE;

    // Control
    opInfo.valid = TRUE;    // Valid outputs
endfunction

function automatic void RISCV_DecodeOpImm(
    output OpInfo [MICRO_OP_MAX_NUM-1:0] microOps,
    output InsnInfo insnInfo,
    input RISCV_ISF_Common isf
);
    OpInfo intOp;
    OpInfo shiftOp;
    OpInfo rijOp;
    OpInfo selectOp;
    MicroOpIndex mid;

    //RISCVでは複数micro opへの分割は基本的に必要ないはず

    RISCV_EmitOpImm(
        .opInfo( intOp ),
        .isf( isf ),
        .srcRegNumA( isf.rs1 ),
        .srcRegNumB( 0 ),
        .dstRegNum( isf.rd ),
        .unsupported( FALSE )
    );

    mid = 0;
    for(int i = 0; i < MICRO_OP_MAX_NUM; i++) begin
        EmitInvalidOp(microOps[i]);
    end

    // --- 1
    // It begins at 1 for aligning outputs to DecodeIntReg.
    microOps[1] = ModifyMicroOp(intOp, mid, FALSE, TRUE);
    mid += 1;

    insnInfo.writePC = FALSE;
    insnInfo.isCall = FALSE;
    insnInfo.isReturn = FALSE;
    insnInfo.isRelBranch = FALSE;
    insnInfo.isSerialized = FALSE;

endfunction


//
// --- レジスタ整数演算, シフト含む
//
function automatic void RISCV_EmitOp(
    output OpInfo  opInfo,
    input RISCV_ISF_Common isf,
    input LScalarRegNumPath srcRegNumA,
    input LScalarRegNumPath srcRegNumB,
    input LScalarRegNumPath dstRegNum,
    input logic unsupported
);
    RISCV_ISF_R isfR;
    OpFunct3 opFunct3;
    OpFunct7 opFunct7;
    ShiftFunct7 shiftFunct7;
    RISCV_IntOperandImmShift intOperandImmShift;
    logic isShift;

    IntALU_Code aluCode;

    isfR = isf;
    opFunct3 = OpFunct3'(isfR.funct3);
    opFunct7 = OpFunct7'(isfR.funct7);
    shiftFunct7 = ShiftFunct7'(isfR.funct7);
    isShift = ( ( opFunct3 == OP_FUNCT3_SLL ) || ( opFunct3 == OP_FUNCT3_SRL_SRA ) );

    // 論理レジスタ番号
`ifdef RSD_ENABLE_VECTOR_PATH
    opInfo.operand.intOp.dstRegNum.isVector  = FALSE;
    opInfo.operand.intOp.srcRegNumA.isVector = FALSE;
    opInfo.operand.intOp.srcRegNumB.isVector = FALSE;
`endif
    opInfo.operand.intOp.dstRegNum.regNum  = dstRegNum;
    opInfo.operand.intOp.srcRegNumA.regNum = srcRegNumA;
    opInfo.operand.intOp.srcRegNumB.regNum = srcRegNumB;

    // 即値
    opInfo.operand.intOp.shiftType = SOT_REG_SHIFT ;

    intOperandImmShift.shift        =  isShift ? isfR.rs2 : '0;
    intOperandImmShift.shiftType    =  ( opFunct3 == OP_FUNCT3_SLL ) ? ST_LSL :
                                    ( ( opFunct3 == OP_FUNCT3_SRL_SRA ) && ( shiftFunct7 == SHIFT_FUNCT7_SRL ) ) ? ST_LSR :
                                    ( ( opFunct3 == OP_FUNCT3_SRL_SRA ) && ( shiftFunct7 == SHIFT_FUNCT7_SRA ) ) ? ST_ASR :
                                    ST_ROR;
    intOperandImmShift.isRegShift   = TRUE;
    intOperandImmShift.imm          = '0;
    intOperandImmShift.immType      = RISCV_IMM_R;

    opInfo.operand.intOp.shiftIn   = intOperandImmShift;


    // ALU
    //RISCV_DecodeOpFunct3( isfR.funct3, isfR.funct7, opInfo.operand.intOp.aluCode);
    RISCV_DecodeOpFunct3( aluCode, opFunct3, opFunct7 );
    opInfo.operand.intOp.aluCode = aluCode;

    // レジスタ書き込みを行うかどうか
    // ゼロレジスタへの書き込みは書き込みフラグをFALSEとする
    opInfo.writeReg  = ( dstRegNum != ZERO_REGISTER ) ? TRUE : FALSE;

    // 論理レジスタを読むかどうか
    opInfo.opTypeA = OOT_REG;
    opInfo.opTypeB = OOT_REG;

    // 命令の種類
    opInfo.mopType = MOP_TYPE_INT;
    opInfo.mopSubType.intType = isShift ? INT_MOP_TYPE_SHIFT : INT_MOP_TYPE_ALU;

    // 条件コード
    opInfo.cond = COND_AL;

    // 未定義命令
    opInfo.unsupported = unsupported;
    opInfo.undefined = FALSE;

    // Serialized
    opInfo.serialized = FALSE;

    // Control
    opInfo.valid = TRUE;    // Valid outputs
endfunction

function automatic void RISCV_DecodeOp(
    output OpInfo [MICRO_OP_MAX_NUM-1:0] microOps,
    output InsnInfo insnInfo,
    input RISCV_ISF_Common isf
);
    OpInfo intOp;
    OpInfo shiftOp;
    OpInfo rijOp;
    OpInfo selectOp;
    MicroOpIndex mid;

    //RISCVでは複数micro opへの分割は基本的に必要ないはず

    RISCV_EmitOp(
        .opInfo( intOp ),
        .isf( isf ),
        .srcRegNumA( isf.rs1 ),
        .srcRegNumB( isf.rs2 ),
        .dstRegNum( isf.rd ),
        .unsupported( FALSE )
    );

    mid = 0;
    for(int i = 0; i < MICRO_OP_MAX_NUM; i++) begin
        EmitInvalidOp(microOps[i]);
    end

    // --- 1
    // It begins at 1 for aligning outputs to DecodeIntReg.
    microOps[1] = ModifyMicroOp(intOp, mid, FALSE, TRUE);
    mid += 1;

    insnInfo.writePC = FALSE;
    insnInfo.isCall = FALSE;
    insnInfo.isReturn = FALSE;
    insnInfo.isRelBranch = FALSE;
    insnInfo.isSerialized = FALSE;

endfunction


//
// --- RISCV LUI, AUIPC
//
function automatic void RISCV_EmitUTypeInst(
    output OpInfo  opInfo,
    input RISCV_ISF_Common isf,
    input LScalarRegNumPath srcRegNumA,
    input LScalarRegNumPath srcRegNumB,
    input LScalarRegNumPath dstRegNum,
    input logic unsupported
);
    RISCV_ISF_U isfU;
    RISCV_IntOperandImmShift intOperandImmShift;

    isfU = isf;

    // 論理レジスタ番号
`ifdef RSD_ENABLE_VECTOR_PATH
    opInfo.operand.intOp.dstRegNum.isVector  = FALSE;
    opInfo.operand.intOp.srcRegNumA.isVector = FALSE;
    opInfo.operand.intOp.srcRegNumB.isVector = FALSE;
`endif
    opInfo.operand.intOp.dstRegNum.regNum  = dstRegNum;
    opInfo.operand.intOp.srcRegNumA.regNum = srcRegNumA;
    opInfo.operand.intOp.srcRegNumB.regNum = srcRegNumB;

    // 即値
    opInfo.operand.intOp.shiftType = SOT_REG_SHIFT ;

    intOperandImmShift.shift        = '0;
    intOperandImmShift.shiftType    = ST_ROR;
    intOperandImmShift.isRegShift   = TRUE;
    intOperandImmShift.imm          = isfU.imm;
    intOperandImmShift.immType      = RISCV_IMM_U;

    opInfo.operand.intOp.shiftIn   = intOperandImmShift;


    // ALU
    opInfo.operand.intOp.aluCode = AC_ADD;

    // レジスタ書き込みを行うかどうか
    // ゼロレジスタへの書き込みは書き込みフラグをFALSEとする
    opInfo.writeReg  = ( dstRegNum != ZERO_REGISTER ) ? TRUE : FALSE;

    // 論理レジスタを読むかどうか
    opInfo.opTypeA = isf.opCode == RISCV_AUIPC ? OOT_PC : OOT_REG;
    opInfo.opTypeB = OOT_IMM;

    // 命令の種類
    opInfo.mopType = MOP_TYPE_INT;
    opInfo.mopSubType.intType = INT_MOP_TYPE_ALU;

    // 条件コード
    opInfo.cond = COND_AL;

    // 未定義命令
    opInfo.unsupported = unsupported;
    opInfo.undefined = FALSE;

    // Serialized
    opInfo.serialized = FALSE;

    // Control
    opInfo.valid = TRUE;    // Valid outputs
endfunction

function automatic void RISCV_DecodeUTypeInst(
    output OpInfo [MICRO_OP_MAX_NUM-1:0] microOps,
    output InsnInfo insnInfo,
    input RISCV_ISF_Common isf
);
    OpInfo intOp;
    MicroOpIndex mid;

    //RISCVでは複数micro opへの分割は基本的に必要ないはず

    RISCV_EmitUTypeInst(
        .opInfo( intOp ),
        .isf( isf ),
        .srcRegNumA( 0 ),
        .srcRegNumB( 0 ),
        .dstRegNum( isf.rd ),
        .unsupported( FALSE )
    );

    mid = 0;
    for(int i = 0; i < MICRO_OP_MAX_NUM; i++) begin
        EmitInvalidOp(microOps[i]);
    end

    // --- 1
    // It begins at 1 for aligning outputs to DecodeIntReg.
    microOps[1] = ModifyMicroOp(intOp, mid, FALSE, TRUE);
    mid += 1;

    insnInfo.writePC = FALSE;
    insnInfo.isCall = FALSE;
    insnInfo.isReturn = FALSE;
    insnInfo.isRelBranch = FALSE;
    insnInfo.isSerialized = FALSE;

endfunction


//
// --- RISCV JAL
//
function automatic void RISCV_EmitJAL(
    output OpInfo  opInfo,
    input RISCV_ISF_Common isf
);
    RISCV_ISF_U isfU;
    isfU = isf;

    // 論理レジスタ番号
`ifdef RSD_ENABLE_VECTOR_PATH
    opInfo.operand.brOp.dstRegNum.isVector  = FALSE;
    opInfo.operand.brOp.srcRegNumA.isVector = FALSE;
    opInfo.operand.brOp.srcRegNumB.isVector = FALSE;
`endif
    opInfo.operand.brOp.dstRegNum.regNum  = isfU.rd;
    opInfo.operand.brOp.srcRegNumA.regNum = '0;
    opInfo.operand.brOp.srcRegNumB.regNum = '0;

    // レジスタ書き込みを行うかどうか
    // 比較系の命令はレジスタに書き込みを行わない
    // ゼロレジスタへの書き込みは書き込みフラグをFALSEとする
    opInfo.writeReg  = ( isfU.rd != ZERO_REGISTER ) ? TRUE : FALSE;

    // 論理レジスタを読むかどうか
    opInfo.opTypeA = OOT_PC;
    opInfo.opTypeB = OOT_IMM;

    // 命令の種類
    opInfo.mopType = MOP_TYPE_INT;
    opInfo.mopSubType.intType = INT_MOP_TYPE_BR;

    // 条件コード
    opInfo.cond = COND_AL;

    // 分岐ターゲット
    opInfo.operand.brOp.brDisp = GetJAL_Target( isf );
    opInfo.operand.brOp.padding = 0;

    // 未定義命令
    opInfo.unsupported = FALSE;
    opInfo.undefined = FALSE;

    // Serialized
    opInfo.serialized = FALSE;

    // Control
    opInfo.valid = TRUE;    // Valid outputs
endfunction

function automatic void RISCV_DecodeJAL(
    output OpInfo [MICRO_OP_MAX_NUM-1:0] microOps,
    output InsnInfo insnInfo,
    input RISCV_ISF_Common isf
);
    OpInfo brOp;
    MicroOpIndex mid;

    //RISCVでは複数micro opへの分割は基本的に必要ないはず

    RISCV_EmitJAL(
        .opInfo( brOp ),
        .isf( isf )
    );

    // Initizalize
    mid = 0;
    for(int i = 0; i < MICRO_OP_MAX_NUM; i++) begin
        EmitInvalidOp(microOps[i]);
    end

    // --- 1
    // It begins at 1 for aligning outputs to DecodeIntReg.
    microOps[1] = ModifyMicroOp(brOp, mid, FALSE, TRUE);

    insnInfo.writePC = TRUE;
    insnInfo.isCall = ( brOp.writeReg && ( brOp.operand.brOp.dstRegNum.regNum == LINK_REGISTER ) ) ? TRUE : FALSE;
    insnInfo.isReturn = FALSE;
    insnInfo.isRelBranch = TRUE;
    insnInfo.isSerialized = FALSE;

endfunction


//
// --- RISCV Decode JALR
//
function automatic void RISCV_EmitJALR(
    output OpInfo  opInfo,
    input RISCV_ISF_Common isf
);

    RISCV_ISF_I isfI;
    isfI = isf;

    // 論理レジスタ番号
`ifdef RSD_ENABLE_VECTOR_PATH
    opInfo.operand.brOp.dstRegNum.isVector  = FALSE;
    opInfo.operand.brOp.srcRegNumA.isVector = FALSE;
    opInfo.operand.brOp.srcRegNumB.isVector = FALSE;
`endif
    opInfo.operand.brOp.dstRegNum.regNum  = isfI.rd;
    opInfo.operand.brOp.srcRegNumA.regNum = isfI.rs1;
    opInfo.operand.brOp.srcRegNumB.regNum = 0;

    // レジスタ書き込みを行うかどうか
    // 比較系の命令はレジスタに書き込みを行わない
    // ゼロレジスタへの書き込みは書き込みフラグをFALSEとする
    opInfo.writeReg  = ( isfI.rd != ZERO_REGISTER ) ? TRUE : FALSE;

    // 論理レジスタを読むかどうか
    opInfo.opTypeA = OOT_REG;
    opInfo.opTypeB = OOT_IMM;

    // 命令の種類
    opInfo.mopType = MOP_TYPE_INT;
    opInfo.mopSubType.intType = INT_MOP_TYPE_RIJ;

    // 条件コード
    opInfo.cond = COND_AL;

    // 分岐ターゲット
    opInfo.operand.brOp.brDisp = GetJALR_Target( isfI );
    opInfo.operand.brOp.padding = '0;

    // 未定義命令
    opInfo.unsupported = FALSE;
    opInfo.undefined = FALSE;

    // Serialized
    opInfo.serialized = FALSE;

    // Control
    opInfo.valid = TRUE;    // Valid outputs
endfunction

function automatic void RISCV_DecodeJALR(
    output OpInfo [MICRO_OP_MAX_NUM-1:0] microOps,
    output InsnInfo insnInfo,
    input RISCV_ISF_Common isf
);
    OpInfo brOp;
    MicroOpIndex mid;

    //RISCVでは複数micro opへの分割は基本的に必要ないはず

    RISCV_EmitJALR(
        .opInfo( brOp ),
        .isf( isf )
    );

    // Initizalize
    mid = 0;
    for(int i = 0; i < MICRO_OP_MAX_NUM; i++) begin
        EmitInvalidOp(microOps[i]);
    end

    // --- 1
    // It begins at 1 for aligning outputs to DecodeIntReg.
    microOps[1] = ModifyMicroOp(brOp, mid, FALSE, TRUE);

    insnInfo.writePC = TRUE;
    insnInfo.isCall = ( brOp.writeReg && ( brOp.operand.brOp.dstRegNum.regNum == LINK_REGISTER ) ) ? TRUE : FALSE;
    insnInfo.isReturn = ( ( brOp.operand.brOp.srcRegNumA.regNum == LINK_REGISTER )
                        && ( brOp.operand.brOp.dstRegNum.regNum == ZERO_REGISTER ) ) ? TRUE : FALSE;
    insnInfo.isRelBranch = FALSE;
    insnInfo.isSerialized = FALSE;

endfunction


//
// --- RISCV BRANCH
//
function automatic void RISCV_EmitBranch(
    output OpInfo  opInfo,
    input RISCV_ISF_Common isf
);
    RISCV_ISF_R isfR;
    BrFunct3 brFunct3;
    CondCode condCode;

    isfR = isf;
    brFunct3 = BrFunct3'(isfR.funct3);

    // 論理レジスタ番号
`ifdef RSD_ENABLE_VECTOR_PATH
    opInfo.operand.brOp.dstRegNum.isVector  = FALSE;
    opInfo.operand.brOp.srcRegNumA.isVector = FALSE;
    opInfo.operand.brOp.srcRegNumB.isVector = FALSE;
`endif
    opInfo.operand.brOp.dstRegNum.regNum  = 0;
    opInfo.operand.brOp.srcRegNumA.regNum = isfR.rs1;
    opInfo.operand.brOp.srcRegNumB.regNum = isfR.rs2;

    // レジスタ書き込みを行うかどうか
    // 比較系の命令はレジスタに書き込みを行わない
    // ゼロレジスタへの書き込みは書き込みフラグをFALSEとする
    opInfo.writeReg  = FALSE;

    // 論理レジスタを読むかどうか
    opInfo.opTypeA = OOT_REG;
    opInfo.opTypeB = OOT_REG;

    // 命令の種類
    opInfo.mopType = MOP_TYPE_INT;
    opInfo.mopSubType.intType = INT_MOP_TYPE_BR;

    // 条件コード
    //RISCV_DecodeBrFunct3(isfR.funct3, opInfo.cond);
    RISCV_DecodeBrFunct3( condCode, brFunct3 );
    opInfo.cond = condCode;

    // 分岐ターゲット
    opInfo.operand.brOp.brDisp = GetBranchDisplacement( isfR );
    opInfo.operand.brOp.padding = '0;

    // 未定義命令
    opInfo.unsupported = FALSE;
    opInfo.undefined = FALSE;

    // Serialized
    opInfo.serialized = FALSE;

    // Control
    opInfo.valid = TRUE;    // Valid outputs
endfunction

function automatic void RISCV_DecodeBranch(
    output OpInfo [MICRO_OP_MAX_NUM-1:0] microOps,
    output InsnInfo insnInfo,
    input RISCV_ISF_Common isf
);
    OpInfo brOp;
    MicroOpIndex mid;

    //RISCVでは複数micro opへの分割は基本的に必要ないはず

    RISCV_EmitBranch(
        .opInfo( brOp ),
        .isf( isf )
    );

    // Initizalize
    mid = 0;
    for(int i = 0; i < MICRO_OP_MAX_NUM; i++) begin
        EmitInvalidOp(microOps[i]);
    end

    // --- 1
    // It begins at 1 for aligning outputs to DecodeIntReg.
    microOps[1] = ModifyMicroOp(brOp, mid, FALSE, TRUE);

    insnInfo.writePC    = TRUE;
    insnInfo.isCall     = FALSE;
    insnInfo.isReturn   = FALSE;
    insnInfo.isRelBranch = TRUE;
    insnInfo.isSerialized = FALSE;

endfunction

//
// --- EISCV MEMORY OP
//
function automatic void RISCV_EmitMemOp(
    output OpInfo  opInfo,
    input RISCV_ISF_Common isf
);
    RISCV_ISF_S isfS;
    RISCV_ISF_I isfI;
    MemFunct3 memFunct3;
    logic isLoad;

    MemAccessMode memAccessMode;

    isfS = isf;
    isfI = isf;
    memFunct3 = MemFunct3'(isfS.funct3);
    isLoad = ( isfI.opCode == RISCV_LD );

    // 論理レジスタ番号
`ifdef RSD_ENABLE_VECTOR_PATH
    opInfo.operand.memOp.dstRegNum.isVector  = FALSE;
    opInfo.operand.memOp.srcRegNumA.isVector = FALSE;
    opInfo.operand.memOp.srcRegNumB.isVector = FALSE;
`endif
    opInfo.operand.memOp.dstRegNum.regNum  = isLoad ? isfI.rd : '0;
    opInfo.operand.memOp.srcRegNumA.regNum = isfI.rs1;
    opInfo.operand.memOp.srcRegNumB.regNum = isLoad ? '0 : isfS.rs2;
    opInfo.operand.memOp.csrCtrl = '0; // unused
    opInfo.operand.memOp.padding = '0;

    // レジスタ書き込みを行うかどうか
    // ゼロレジスタへの書き込みは書き込みフラグをFALSEとする
    opInfo.writeReg  = ( isfI.rd != ZERO_REGISTER ) & isLoad;

    // 論理レジスタを読むかどうか
    // ストア時はBを読む
    opInfo.opTypeA = OOT_REG;
    opInfo.opTypeB = isLoad ? OOT_IMM : OOT_REG;

    // 命令の種類
    opInfo.mopType = MOP_TYPE_MEM;
    opInfo.mopSubType.memType = isLoad ? MEM_MOP_TYPE_LOAD : MEM_MOP_TYPE_STORE;

    // 条件コード
    opInfo.cond = COND_AL;

    // アドレッシング
    opInfo.operand.memOp.addrIn    = isLoad ? isfI.imm : {isfS.imm2, isfS.imm1};
    opInfo.operand.memOp.isAddAddr = TRUE;
    opInfo.operand.memOp.isRegAddr = TRUE;
    RISCV_DecodeMemAccessMode( memAccessMode, memFunct3 );
    opInfo.operand.memOp.memAccessMode = memAccessMode;

    opInfo.valid = TRUE;

    opInfo.unsupported = FALSE;
    opInfo.undefined = FALSE;

    // Serialized
    opInfo.serialized = FALSE;
endfunction

function automatic void RISCV_DecodeMemOp(
    output OpInfo [MICRO_OP_MAX_NUM-1:0] microOps,
    output InsnInfo insnInfo,
    input RISCV_ISF_Common isf
);
    OpInfo memOp;
    MicroOpIndex mid;

    //RISCVでは複数micro opへの分割は基本的に必要ないはず

    RISCV_EmitMemOp(
        .opInfo( memOp ),
        .isf( isf )
    );

    // Initizalize
    mid = 0;
    for(int i = 0; i < MICRO_OP_MAX_NUM; i++) begin
        EmitInvalidOp(microOps[i]);
    end

    // --- 1
    // It begins at 1 for aligning outputs to DecodeIntReg.
    microOps[1] = ModifyMicroOp(memOp, mid, FALSE, TRUE);

    insnInfo.writePC    = FALSE;
    insnInfo.isCall     = FALSE;
    insnInfo.isReturn   = FALSE;
    insnInfo.isRelBranch = FALSE;
    insnInfo.isSerialized = FALSE;

endfunction


//
// --- Complex Op (RISC-VではRV32M)
//
function automatic void RISCV_EmitComplexOp(
    output OpInfo  opInfo, 
    input RISCV_ISF_Common isf,
    input LScalarRegNumPath srcRegNumA,
    input LScalarRegNumPath srcRegNumB,
    input LScalarRegNumPath dstRegNum,
    input logic unsupported
);
    RISCV_ISF_R isfR;
    OpFunct3 opFunct3;
    OpFunct7 opFunct7;
    RV32MFunct3 rv32mFunct3;
    RV32MFunct7 rv32mFunct7;
    logic isMul;

    IntMUL_Code mulCode;
    IntDIV_Code divCode;

    isfR = isf;
    opFunct3 = OpFunct3'(isfR.funct3);
    opFunct7 = OpFunct7'(isfR.funct7);
    rv32mFunct3 = RV32MFunct3'(isfR.funct3);
    rv32mFunct7 = RV32MFunct7'(isfR.funct7);
    isMul = ( rv32mFunct3 < RV32M_FUNCT3_DIV );

    // 論理レジスタ番号
`ifdef RSD_ENABLE_VECTOR_PATH
    opInfo.operand.complexOp.dstRegNum.isVector  = FALSE;
    opInfo.operand.complexOp.srcRegNumA.isVector = FALSE;
    opInfo.operand.complexOp.srcRegNumB.isVector = FALSE;
`endif
    opInfo.operand.complexOp.dstRegNum.regNum  = dstRegNum;
    opInfo.operand.complexOp.srcRegNumA.regNum = srcRegNumA;
    opInfo.operand.complexOp.srcRegNumB.regNum = srcRegNumB;
    
    // 乗算の有効な結果の位置
    opInfo.operand.complexOp.mulGetUpper = ( rv32mFunct3 > RV32M_FUNCT3_MUL) ;

    // ALU
    RISCV_DecodeComplexOpFunct3( mulCode, divCode, rv32mFunct3 );
    opInfo.operand.complexOp.mulCode = mulCode;
    opInfo.operand.complexOp.divCode = divCode;
    opInfo.operand.complexOp.padding = '0;
    opInfo.operand.complexOp.riscv_padding = '0;

    // レジスタ書き込みを行うかどうか
    // ゼロレジスタへの書き込みは書き込みフラグをFALSEとする   
    opInfo.writeReg  = ( dstRegNum != ZERO_REGISTER ) ? TRUE : FALSE;

    // 論理レジスタを読むかどうか
    opInfo.opTypeA = OOT_REG;
    opInfo.opTypeB = OOT_REG;

    // 命令の種類
`ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    // Mem pipe で処理
    opInfo.mopType = MOP_TYPE_MEM;
    opInfo.mopSubType.memType = isMul ? MEM_MOP_TYPE_MUL : MEM_MOP_TYPE_DIV;
`else
    // 剰余は除算と演算器を共有するためCOMPLEX_MOP_TYPE_DIVとする
    opInfo.mopType = MOP_TYPE_COMPLEX;
    opInfo.mopSubType.complexType = isMul ? COMPLEX_MOP_TYPE_MUL : COMPLEX_MOP_TYPE_DIV;
`endif

    // 条件コード
    opInfo.cond = COND_AL;

    // 未定義命令
    opInfo.unsupported = unsupported;
    opInfo.undefined = FALSE;

    // Serialized
    opInfo.serialized = FALSE;

    // Control
    opInfo.valid = TRUE;    // Valid outputs
endfunction

function automatic void RISCV_DecodeComplexOp( 
    output OpInfo [MICRO_OP_MAX_NUM-1:0] microOps,
    output InsnInfo insnInfo,
    input RISCV_ISF_Common isf
);
    OpInfo complexOp;
    MicroOpIndex mid;

    //RISCVでは複数micro opへの分割は基本的に必要ないはず

    RISCV_EmitComplexOp(
        .opInfo( complexOp ),
        .isf( isf ),
        .srcRegNumA( isf.rs1 ),
        .srcRegNumB( isf.rs2 ),
        .dstRegNum( isf.rd ),
        .unsupported( FALSE )
    );

    mid = 0;
    for(int i = 0; i < MICRO_OP_MAX_NUM; i++) begin
        EmitInvalidOp(microOps[i]);
    end

    // --- 1
    // It begins at 1 for aligning outputs to DecodeIntReg.
    microOps[1] = ModifyMicroOp(complexOp, mid, FALSE, TRUE);
    mid += 1;

    insnInfo.writePC = FALSE;
    insnInfo.isCall = FALSE;
    insnInfo.isReturn = FALSE;
    insnInfo.isRelBranch = FALSE;
    insnInfo.isSerialized = FALSE;

endfunction

//
// --- Misc-Mem
//
function automatic void RISCV_EmitMiscMemOp(
    output OpInfo  opInfo,
    input RISCV_ISF_Common isf
);
    RISCV_ISF_MISC_MEM isfMiscMem;
    MiscMemFunct3 opFunct3;
    MiscMemMicroOpOperand miscMemOp;

    isfMiscMem = isf;
    opFunct3 = MiscMemFunct3'(isfMiscMem.funct3);

    // 論理レジスタ番号
`ifdef RSD_ENABLE_VECTOR_PATH
    miscMemOp.dstRegNum.isVector  = FALSE;
    miscMemOp.srcRegNumA.isVector = FALSE;
    miscMemOp.srcRegNumB.isVector = FALSE;
`endif
    miscMemOp.dstRegNum.regNum  = '0;
    miscMemOp.srcRegNumA.regNum = '0;
    miscMemOp.srcRegNumB.regNum = '0;
    miscMemOp.padding = '0;
    miscMemOp.riscv_padding = '0;

    if (opFunct3 == MISC_MEM_FUNCT3_FENCE) begin
        miscMemOp.fence = TRUE;
        miscMemOp.fenceI = FALSE;
    end 
    else if (opFunct3 == MISC_MEM_FUNCT3_FENCE_I) begin
        miscMemOp.fence = TRUE;
        miscMemOp.fenceI = TRUE;
    end 
    else begin
        miscMemOp.fence = FALSE;
        miscMemOp.fenceI = FALSE;
    end

    opInfo.operand.miscMemOp = miscMemOp;

    // レジスタ書き込みを行うかどうか
    // FENCE/FENCE.I Does not write any registers 
    opInfo.writeReg  = FALSE;

    // 論理レジスタを読むかどうか
    opInfo.opTypeA = OOT_IMM;
    opInfo.opTypeB = OOT_IMM;

    // 命令の種類
    opInfo.mopType = MOP_TYPE_MEM;
    opInfo.mopSubType.memType = MEM_MOP_TYPE_FENCE;

    // 条件コード
    opInfo.cond = COND_AL;


    opInfo.valid = TRUE;

    opInfo.unsupported = FALSE;
    if (miscMemOp.fence) begin
        opInfo.undefined = FALSE;
    end
    else begin
        // Unknown misc mem
        opInfo.undefined = TRUE;
    end

    // Serialized
    opInfo.serialized = TRUE;
endfunction

function automatic void RISCV_DecodeMiscMem(
    output OpInfo [MICRO_OP_MAX_NUM-1:0] microOps,
    output InsnInfo insnInfo,
    input RISCV_ISF_Common isf
);
    OpInfo miscMemOp;
    MicroOpIndex mid;

    //RISCVでは複数micro opへの分割は基本的に必要ないはず

    RISCV_EmitMiscMemOp(
        .opInfo(miscMemOp),
        .isf(isf)
    );

    // Initizalize
    mid = 0;
    for (int i = 0; i < MICRO_OP_MAX_NUM; i++) begin
        EmitInvalidOp(microOps[i]);
    end

    // --- 1
    // It begins at 1 for aligning outputs to DecodeIntReg.
    microOps[1] = ModifyMicroOp(miscMemOp, mid, FALSE, TRUE);

    insnInfo.writePC    = FALSE;
    insnInfo.isCall     = FALSE;
    insnInfo.isReturn   = FALSE;
    insnInfo.isRelBranch = FALSE;
    insnInfo.isSerialized = TRUE;

endfunction


//
// --- System
//
function automatic void RISCV_EmitCSR_Op(
    output OpInfo opInfo,
    input RISCV_ISF_Common isf
);
    RISCV_ISF_SYSTEM isfSystem;
    SystemFunct3 opFunct3;
    MemMicroOpOperand memOp;    // Decoded as a memory op

    isfSystem = isf;
    opFunct3 = SystemFunct3'(isfSystem.funct3);

    // 論理レジスタ番号
`ifdef RSD_ENABLE_VECTOR_PATH
    memOp.dstRegNum.isVector  = FALSE;
    memOp.srcRegNumA.isVector = FALSE;
    memOp.srcRegNumB.isVector = FALSE;
`endif
    memOp.dstRegNum.regNum  = isfSystem.rd;
    memOp.srcRegNumA.regNum = isfSystem.rs1;
    memOp.srcRegNumB.regNum = '0;
    memOp.padding = '0;

    // Don't care
    memOp.isAddAddr = FALSE;
    memOp.isRegAddr = FALSE;
    memOp.memAccessMode = '0;

    // コードの設定
    unique case (opFunct3)
        default: begin  // SYSTEM_FUNCT3_PRIV or unknown
            memOp.csrCtrl.code = CSR_WRITE;
        end
        SYSTEM_FUNCT3_CSR_RW, SYSTEM_FUNCT3_CSR_RW_I: begin
            memOp.csrCtrl.code = CSR_WRITE;
        end
        SYSTEM_FUNCT3_CSR_RS, SYSTEM_FUNCT3_CSR_RS_I: begin
            memOp.csrCtrl.code = CSR_SET;
        end
        SYSTEM_FUNCT3_CSR_RC, SYSTEM_FUNCT3_CSR_RC_I: begin
            memOp.csrCtrl.code = CSR_CLEAR;
        end
    endcase

    // CSR number
    memOp.addrIn = isfSystem.funct12;

    // CSR 命令の即値だけは特殊なので REG にしておき，ユニット側で対処する
    memOp.csrCtrl.isImm = 
        (opFunct3 inside {
            SYSTEM_FUNCT3_CSR_RW, 
            SYSTEM_FUNCT3_CSR_RS, 
            SYSTEM_FUNCT3_CSR_RC
        }) ? FALSE : TRUE;
    memOp.csrCtrl.imm = isfSystem.rs1;   // rs1 がちょうど即値になる

    opInfo.operand.memOp = memOp;

    // レジスタ書き込みを行うかどうか
    // CSR 系は基本全て書き込む
    // ゼロレジスタへの書き込みは書き込みフラグをFALSEとする
    opInfo.writeReg  = (isfSystem.rd != ZERO_REGISTER) ? TRUE : FALSE;


    // 論理レジスタを読むかどうか
    // CSR 命令の即値だけは特殊なので REG にしておき，ユニット側で対処する
    opInfo.opTypeA = OOT_REG;  
    opInfo.opTypeB = OOT_IMM;

    // 命令の種類
    opInfo.mopType = MOP_TYPE_MEM;
    opInfo.mopSubType.memType = MEM_MOP_TYPE_CSR;

    // 条件コード
    opInfo.cond = COND_AL;

    opInfo.valid = TRUE;

    opInfo.unsupported = FALSE;
    opInfo.undefined = 
        opFunct3 == SYSTEM_FUNCT3_UNDEFINED ? TRUE : FALSE;

    // Serialized
    opInfo.serialized = TRUE;
endfunction


function automatic void RISCV_EmitSystemOp(
    output OpInfo  opInfo,
    input RISCV_ISF_Common isf
);
    RISCV_ISF_SYSTEM isfSystem;
    SystemFunct3  opFunct3;
    SystemFunct12 opFunct12;
    SystemMicroOpOperand systemOp;
    logic undefined;

    isfSystem = isf;
    opFunct3 = SystemFunct3'(isfSystem.funct3);
    opFunct12 = SystemFunct12'(isfSystem.funct12);

    // 論理レジスタ番号
`ifdef RSD_ENABLE_VECTOR_PATH
    systemOp.dstRegNum.isVector  = FALSE;
    systemOp.srcRegNumA.isVector = FALSE;
    systemOp.srcRegNumB.isVector = FALSE;
`endif
    systemOp.dstRegNum.regNum  = '0;
    systemOp.srcRegNumA.regNum = '0;
    systemOp.srcRegNumB.regNum = '0;
    systemOp.isEnv = TRUE;
    systemOp.padding = '0;
    systemOp.imm = '0;

    undefined = FALSE;

    // コードの設定
    if (opFunct12 == SYSTEM_FUNCT12_WFI) begin
        // NOP 扱いにしておく
        opInfo.mopType = MOP_TYPE_INT;
        opInfo.mopSubType.intType = INT_MOP_TYPE_ALU;
        systemOp.envCode = ENV_BREAK;
    end
    else begin
        unique case(SystemFunct12'(isfSystem.funct12))
            SYSTEM_FUNCT12_ECALL:  systemOp.envCode = ENV_CALL;
            SYSTEM_FUNCT12_EBREAK: systemOp.envCode = ENV_BREAK;
            SYSTEM_FUNCT12_MRET:   systemOp.envCode = ENV_MRET;
            default: begin// Unknown
                systemOp.envCode = ENV_BREAK;            
                undefined = TRUE;
            end
        endcase

        // 命令の種類
        opInfo.mopType = MOP_TYPE_MEM;
        opInfo.mopSubType.memType = MEM_MOP_TYPE_ENV;
    end

    opInfo.operand.systemOp = systemOp;

    // レジスタ書き込みを行うかどうか
    opInfo.writeReg  = FALSE;

    // 論理レジスタを読むかどうか
    opInfo.opTypeA = OOT_IMM;
    opInfo.opTypeB = OOT_IMM;


    // 条件コード
    opInfo.cond = COND_AL;

    opInfo.valid = TRUE;

    opInfo.unsupported = FALSE;
    opInfo.undefined = undefined;

    // Serialized
    opInfo.serialized = TRUE;
endfunction


function automatic void RISCV_DecodeSystem(
    output OpInfo [MICRO_OP_MAX_NUM-1:0] microOps,
    output InsnInfo insnInfo,
    input RISCV_ISF_Common isf
);
    OpInfo opInfo;
    MicroOpIndex mid;

    //RISCVでは複数micro opへの分割は基本的に必要ないはず

    if (SystemFunct3'(isf.funct3) == SYSTEM_FUNCT3_PRIV) begin
        RISCV_EmitSystemOp(.opInfo(opInfo), .isf(isf));
    end
    else begin 
        RISCV_EmitCSR_Op(.opInfo(opInfo), .isf(isf));
    end

    // Initizalize
    mid = 0;
    for (int i = 0; i < MICRO_OP_MAX_NUM; i++) begin
        EmitInvalidOp(microOps[i]);
    end

    // --- 1
    // It begins at 1 for aligning outputs to DecodeIntReg.
    microOps[1] = ModifyMicroOp(opInfo, mid, FALSE, TRUE);

    insnInfo.writePC    = FALSE;
    insnInfo.isCall     = FALSE;
    insnInfo.isReturn   = FALSE;
    insnInfo.isRelBranch = FALSE;
    insnInfo.isSerialized = TRUE;   // A system instruction must be serialized

endfunction


function automatic void RISCV_EmitIllegalOp(
    output OpInfo opInfo,
    input logic illegalPC
);
    RISCV_ISF_SYSTEM isfSystem;
    SystemFunct3  opFunct3;
    SystemFunct12 opFunct12;
    SystemMicroOpOperand systemOp;
    logic undefined;

    // 論理レジスタ番号
`ifdef RSD_ENABLE_VECTOR_PATH
    systemOp.dstRegNum.isVector  = FALSE;
    systemOp.srcRegNumA.isVector = FALSE;
    systemOp.srcRegNumB.isVector = FALSE;
`endif
    systemOp.dstRegNum.regNum  = '0;
    systemOp.srcRegNumA.regNum = '0;
    systemOp.srcRegNumB.regNum = '0;
    systemOp.isEnv = TRUE;
    systemOp.padding = '0;
    systemOp.imm = '0;

    undefined = FALSE;

    // コードの設定
    systemOp.envCode = illegalPC ? ENV_INSN_VIOLATION : ENV_INSN_ILLEGAL;

    // 命令の種類
    opInfo.mopType = MOP_TYPE_MEM;
    opInfo.mopSubType.memType = MEM_MOP_TYPE_ENV;

    opInfo.operand.systemOp = systemOp;

    // レジスタ書き込みを行うかどうか
    opInfo.writeReg  = FALSE;

    // 論理レジスタを読むかどうか
    opInfo.opTypeA = OOT_IMM;
    opInfo.opTypeB = OOT_IMM;

    // 条件コード
    opInfo.cond = COND_AL;
    opInfo.valid = TRUE;
    opInfo.unsupported = FALSE;
    opInfo.undefined = undefined;

    // Serialized
    opInfo.serialized = TRUE;
endfunction

function automatic void RISCV_DecodeIllegal(
    output OpInfo [MICRO_OP_MAX_NUM-1:0] microOps,
    output InsnInfo insnInfo,
    input RISCV_ISF_Common isf,
    input illegalPC
);
    OpInfo opInfo;
    MicroOpIndex mid;

    RISCV_EmitIllegalOp(opInfo, illegalPC);

    // Initizalize
    mid = 0;
    for (int i = 0; i < MICRO_OP_MAX_NUM; i++) begin
        EmitInvalidOp(microOps[i]);
    end

    // --- 1
    // It begins at 1 for aligning outputs to DecodeIntReg.
    microOps[1] = ModifyMicroOp(opInfo, mid, FALSE, TRUE);

    insnInfo.writePC    = FALSE;
    insnInfo.isCall     = FALSE;
    insnInfo.isReturn   = FALSE;
    insnInfo.isRelBranch = FALSE;
    insnInfo.isSerialized = TRUE;   // A system instruction must be serialized

endfunction
//
// --- DecodeStageでインスタンシエートされるモジュール
//
module Decoder(
input
    InsnPath insn,      // Input instruction
    logic illegalPC,
output
    OpInfo [MICRO_OP_MAX_NUM-1:0] microOps,  // Outputed micro ops
    InsnInfo insnInfo  // Whether this instruction is branch or not.
);
    RISCV_ISF_Common isf;
    RV32MFunct7 rv32mFunct7;
    logic undefined;
    
    always_comb begin
        isf  = insn;
        rv32mFunct7 = RV32MFunct7'(isf.funct7);
        
        insnInfo.writePC = FALSE;
        insnInfo.isCall = FALSE;
        insnInfo.isReturn = FALSE;
        insnInfo.isRelBranch = FALSE;
        insnInfo.isSerialized = FALSE;

        case (isf.opCode)

            // S: LOAD, STORE
            RISCV_LD, RISCV_ST : begin
                RISCV_DecodeMemOp(microOps, insnInfo, insn);
            end

            // B: BRANCH
            RISCV_BR : begin
                RISCV_DecodeBranch(microOps, insnInfo, insn);
            end
            // I: JALR
            RISCV_JALR : begin
                RISCV_DecodeJALR(microOps, insnInfo, insn);
            end
            // J: JAL
            RISCV_JAL : begin
                RISCV_DecodeJAL(microOps, insnInfo, insn);
            end

            // I: OP-IMM
            RISCV_OP_IMM : begin
                RISCV_DecodeOpImm(microOps, insnInfo, insn);
            end

            // R: OP
            RISCV_OP : begin
                if (rv32mFunct7 == RV32M_FUNCT7_ALL) begin
                    RISCV_DecodeComplexOp(microOps, insnInfo, insn);
                end
                else begin
                    RISCV_DecodeOp(microOps, insnInfo, insn);
                end
            end

            // U: AUIPC, LUI
            RISCV_AUIPC, RISCV_LUI : begin
                RISCV_DecodeUTypeInst(microOps, insnInfo, insn);
            end

            // I: MISC-MEM (fence/fence.i)
            RISCV_MISC_MEM : begin
                RISCV_DecodeMiscMem(microOps, insnInfo, insn);
            end

            // I: SYSTEM (ebreak/ecall/csr)
            RISCV_SYSTEM : begin
                RISCV_DecodeSystem(microOps, insnInfo, insn);
            end

            default : begin
                RISCV_DecodeIllegal(microOps, insnInfo, insn, illegalPC);
            end
        endcase

        undefined = FALSE;
        for(int i = 0; i < MICRO_OP_MAX_NUM; i++) begin
            if(microOps[i].undefined || microOps[i].unsupported) begin
                undefined = TRUE;
            end
        end

        if (undefined || illegalPC) begin
            RISCV_DecodeIllegal(microOps, insnInfo, insn, illegalPC);
        end

    end



endmodule : Decoder



