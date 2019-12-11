# -*- coding: utf-8 -*-

import sys
import re
import pprint


class RISCV_Disassembler( object ):
    """ 32bit RISCV disassembler """
    def __init__( self ):
        pass

    def Disassemble( self, codeStr ):
        try:
            if( codeStr == "" or codeStr == "xxxxxxxx" ):
                return "invalid:" + codeStr

            code = int( codeStr, 16 )

            common = self.InstructionCommon( code )
            insn = common

            if common.IsLoad():
                insn = self.InstructionLoad( code )
            elif common.IsStore():
                insn = self.InstructionStore( code )
            elif common.IsBranch():
                insn = self.InstructionBranch( code )
            elif common.IsJALR():
                insn = self.InstructionJALR( code )
            elif common.IsJAL():
                insn = self.InstructionJAL( code )
            elif common.IsOpImm():
                insn = self.InstructionOpImm( code )
            elif common.IsOp():
                insn = self.InstructionOp( code )
            elif common.IsAUIPC():
                insn = self.InstructionAUIPC( code )
            elif common.IsLUI():
                insn = self.InstructionLUI( code )
            elif common.IsMiscMem():
                insn = self.InstructionMiscMem( code )
            elif common.IsSystem():
                insn = self.InstructionSystem( code )
            return insn.__str__()

        except ValueError:
            return "invalid: %s" % codeStr


    class InstructionBase( object ):
        """ RISCV distribution """
        RV32I = True
        RV64I = False
        RV32M = True
        RV64M = False
        RV32A = False
        RV64A = False
        RV32F = False
        RV64F = False
        RV32D = False
        RV64D = False

        def __init__( self, code ):
            self.code = code

        def Bits( self, source, higherPosition, lowerPosition ):
            """ Extract bits from source data. """
            length = higherPosition - lowerPosition + 1
            mask = (1 << length) - 1
            return (source >> lowerPosition) & mask

        def __str__( self ):
            return "unknown %x" % self.code


    class InstructionCommon( InstructionBase ):
        """ Common instruction """

        OC_LOAD     = "0000011"
        OC_STORE    = "0100011"
        OC_BRANCH   = "1100011"
        OC_JALR     = "1100111"
        OC_JAL      = "1101111"
        OC_OP_IMM   = "0010011"
        OC_OP       = "0110011"
        OC_AUIPC    = "0010111"
        OC_LUI      = "0110111"
        OC_MISC_MEM = "0001111"
        OC_SYSTEM   = "1110011"

        intRegName = ['zero', 'ra', 'sp', 'gp', 'tp', 't0', 't1', 't2',
                          's0/fp', 's1', 'a0', 'a1', 'a2', 'a3', 'a4', 'a5',
                          'a6', 'a7', 's2', 's3', 's4', 's5', 's6', 's7',
                          's8', 's9', 's10', 's11', 't3', 't4', 't5', 't6']

        floatRegName = ['ft0', 'ft1', 'ft2', 'ft3', 'ft4', 'ft5', 'ft6', 'ft7',
                          'fs0', 'fs1', 'fa0', 'fa1', 'fa2', 'fa3', 'fa4', 'fa5',
                          'fa6', 'fa7', 'fs2', 'fs3', 'fs4', 'fs5', 'fs6', 'fs7',
                          'fs8', 'fs9', 'fs10', 'fs11', 'ft8', 'ft9', 'ft10', 'ft11']


        def __init__( self, code ):
            RISCV_Disassembler.InstructionBase.__init__( self, code )

            inst = "{0:032b}".format(self.Bits(code, 31, 0))

            self.opCode = inst[-7:]
            self.funct3 = inst[-15:-12]
            self.funct7 = inst[-32:-25]
            self.funct6 = inst[-32:-26]
            self.funct5 = inst[-25:-20]
            self.funct12 = inst[-32:-20]
            self.rd  = self.intRegName[int(inst[-12:-7], 2)]
            self.rs1 = self.intRegName[int(inst[-20:-15], 2)]
            self.rs2 = self.intRegName[int(inst[-25:-20], 2)]

            # Hex Style
            self.shamt5 = str(hex(int(inst[-25:-20], 2)))
            self.shamt6 = str(hex(int(inst[-26:-20], 2)))
            self.I_Imm = str(hex(int(inst[-32] * 21 + inst[-31:-20], 2)))
            self.S_Imm = str(hex(int(inst[-32] * 21 + inst[-31:-25] + inst[-12:-7], 2)))
            self.B_Imm = str(hex(int(inst[-32] * 20 + inst[-8] + inst[-31:-25]
                                + inst[-12:-8] + '0', 2)))
            self.U_Imm = str(hex(int(inst[-32] + inst[-31:-20] + inst[-20:-12]
                                + '0' * 12, 2)))
            self.J_Imm = str(hex(int(inst[-32] * 12 + inst[-20:-12] + inst[-21]
                                + inst[-31:-21] + '0', 2)))

        def IsLoad( self ):
            return self.opCode == self.OC_LOAD

        def IsStore( self ):
            return self.opCode == self.OC_STORE

        def IsBranch( self ):
            return self.opCode == self.OC_BRANCH

        def IsJALR( self ):
            return self.opCode == self.OC_JALR

        def IsJAL( self ):
            return self.opCode == self.OC_JAL

        def IsOpImm( self ):
            return self.opCode == self.OC_OP_IMM

        def IsOp( self ):
            return self.opCode == self.OC_OP

        def IsAUIPC( self ):
            return self.opCode == self.OC_AUIPC

        def IsLUI( self ):
            return self.opCode == self.OC_LUI

        def IsMiscMem( self ):
            return self.opCode == self.OC_MISC_MEM

        def IsSystem( self ):
            return self.opCode == self.OC_SYSTEM

    class InstructionLoad( InstructionCommon ):
        """ Load instruction """

        def __init__( self, code ):
            RISCV_Disassembler.InstructionCommon.__init__( self, code )

        def __str__( self ):
            if self.funct3 == '000' and self.RV32I:
                opType = 'lb '
            elif self.funct3 == '001' and self.RV32I:
                opType = 'lh '
            elif self.funct3 == '010' and self.RV32I:
                opType = 'lw '
            elif self.funct3 == '011' and self.RV64I:
                opType = 'ld '  # self.RV64I
            elif self.funct3 == '100' and self.RV32I:
                opType = 'lbu '
            elif self.funct3 == '101' and self.RV32I:
                opType = 'lhu '
            elif self.funct3 == '110' and self.RV32I:
                opType = 'lwu '
            else:
                opType = 'Unknown'
            asmStr = opType + self.rd + ', ' + self.I_Imm + '(' + self.rs1 + ')'
            return asmStr


    class InstructionStore( InstructionCommon ):
        """ Store instruction """

        def __init__( self, code ):
            RISCV_Disassembler.InstructionCommon.__init__( self, code )

        def __str__( self ):
            if self.funct3 == '000' and self.RV32I:
                opType = 'sb '
            elif self.funct3 == '001' and self.RV32I:
                opType = 'sh '
            elif self.funct3 == '010' and self.RV32I:
                opType = 'sw '
            elif self.funct3 == '011' and self.RV64I:
                opType = 'sd '
            else:
                opType = 'Unknown'
            asmStr = opType + self.rs2 + ', ' + self.rs1 + ', ' + self.S_Imm
            return asmStr

    class InstructionBranch( InstructionCommon ):
        """ Branch instruction """

        def __init__( self, code ):
            RISCV_Disassembler.InstructionCommon.__init__( self, code )

        def __str__( self ):
            if self.funct3 == '000':
                opType = 'beq '
            elif self.funct3 == '001':
                opType = 'bne '
            elif self.funct3 == '100':
                opType = 'blt '
            elif self.funct3 == '101':
                opType = 'bge '
            elif self.funct3 == '110':
                opType = 'bltu '
            elif self.funct3 == '111':
                opType = 'bgeu '
            else:
                opType = 'Unknown'
            asmStr = opType + self.rs1 + ', ' + self.rs2 + ', ' + self.B_Imm
            return asmStr

    class InstructionJALR( InstructionCommon ):
        """ JALR instruction """

        def __init__( self, code ):
            RISCV_Disassembler.InstructionCommon.__init__( self, code )

        def __str__( self ):
            opType = 'jalr '
            asmStr = opType + self.rd + ', ' + self.I_Imm + '(' + self.rs1 + ')'
            return asmStr

    class InstructionJAL( InstructionCommon ):
        """ JAL instruction """

        def __init__( self, code ):
            RISCV_Disassembler.InstructionCommon.__init__( self, code )

        def __str__( self ):
            opType = 'jal '
            asmStr = opType + self.rd + ', ' + self.J_Imm
            return asmStr

    class InstructionOpImm( InstructionCommon ):
        """ OpImm instruction """

        def __init__( self, code ):
            RISCV_Disassembler.InstructionCommon.__init__( self, code )

        def __str__( self ):
            imm = self.I_Imm
            if self.funct3 == '000' and self.RV32I:
                opType = 'addi '
            elif self.funct3 == '001':
                if self.funct6 == '000000' and self.RV64I:
                    opType = 'slli '
                    imm = self.shamt6
                elif self.funct7 == '0000000' and self.RV32I:
                    opType = 'slli '
                    imm = self.shamt5
                else:
                    opType = 'Unknown'
            elif self.funct3 == '101':
                if self.funct6 == '000000' and self.RV64I:
                    opType = 'srli '
                    imm = self.shamt6
                elif self.funct6 == '010000' and self.RV64I:
                    opType = 'srai '
                    imm = self.shamt6
                elif self.funct7 == '0000000' and self.RV32I:
                    opType = 'srli '
                    imm = self.shamt5
                elif self.funct7 == '0100000' and self.RV32I:
                    opType = 'srai '
                    imm = self.shamt5
                else:
                    opType = 'Unknown'
            elif self.funct3 == '010' and self.RV32I:
                opType = 'slti '
            elif self.funct3 == '011' and self.RV32I:
                opType = 'sltiu '
            elif self.funct3 == '100' and self.RV32I:
                opType = 'xori '
            elif self.funct3 == '110' and self.RV32I:
                opType = 'ori '
            elif self.funct3 == '111' and self.RV32I:
                opType = 'andi '
            else:
                opType = 'Unknown'
            asmStr = opType + self.rd + ', ' + self.rs1 + ', ' + imm
            return asmStr


    class InstructionOp( InstructionCommon ):
        """ Op instruction """

        def __init__( self, code ):
            RISCV_Disassembler.InstructionCommon.__init__( self, code )

        def __str__( self ):
            if self.funct7 == '0000001' and self.RV32M:
                if self.funct3 == '000':
                    opType = 'mul '
                elif self.funct3 == '001':
                    opType = 'mulh '
                elif self.funct3 == '010':
                    opType = 'mulhsu '
                elif self.funct3 == '011':
                    opType = 'mulhu '
                elif self.funct3 == '100':
                    opType = 'div '
                elif self.funct3 == '101':
                    opType = 'divu '
                elif self.funct3 == '110':
                    opType = 'rem '
                elif self.funct3 == '111':
                    opType = 'remu '
                else:
                    opType = 'Unknown'
            elif self.RV32I:
                if self.funct3 == '000' and self.funct7 == '0000000':
                    opType = 'add '
                elif self.funct3 == '000' and self.funct7 == '0100000':
                    opType = 'sub '
                elif self.funct3 == '001' and self.funct7 == '0000000':
                    opType = 'sll '
                elif self.funct3 == '010' and self.funct7 == '0000000':
                    opType = 'slt '
                elif self.funct3 == '011' and self.funct7 == '0000000':
                    opType = 'sltu '
                elif self.funct3 == '100' and self.funct7 == '0000000':
                    opType = 'xor '
                elif self.funct3 == '101' and self.funct7 == '0000000':
                    opType = 'srl '
                elif self.funct3 == '101' and self.funct7 == '0100000':
                    opType = 'sra '
                elif self.funct3 == '110' and self.funct7 == '0000000':
                    opType = 'or '
                elif self.funct3 == '111' and self.funct7 == '0000000':
                    opType = 'and '
                else:
                    opType = 'Unknown'
            else:
                opType = 'Unknown'

            asmStr = opType + self.rd + ', ' + self.rs1 + ', ' + self.rs2
            return asmStr


    class InstructionAUIPC( InstructionCommon ):
        """ AUIPC instruction """

        def __init__( self, code ):
            RISCV_Disassembler.InstructionCommon.__init__( self, code )

        def __str__( self ):
            opType = 'auipc '
            asmStr = opType + self.rd + ', ' + self.U_Imm
            return asmStr


    class InstructionLUI( InstructionCommon ):
        """ Load instruction """

        def __init__( self, code ):
            RISCV_Disassembler.InstructionCommon.__init__( self, code )

        def __str__( self ):
            opType = 'lui '
            asmStr = opType + self.rd + ', ' + self.U_Imm
            return asmStr

    class InstructionMiscMem( InstructionCommon ):
        """ Misc Memory instruction """

        def __init__( self, code ):
            RISCV_Disassembler.InstructionCommon.__init__( self, code )

        def __str__( self ):
            if self.funct3 == "000":
                opType = 'fence ' + "{0:08b}".format(self.Bits(self.code, 27, 20))
            elif self.funct3 == "001":
                opType = 'fence.i '
            else:
                opType = 'unknown misc mem'
            asmStr = opType
            return asmStr

    class InstructionSystem( InstructionCommon ):
        """ Misc Memory instruction """

        def __init__( self, code ):
            RISCV_Disassembler.InstructionCommon.__init__( self, code )

        def __str__( self ):
            csr =  "0x{0:03x}".format(self.Bits(self.code, 31, 20))
            zimm = "0x{0:03x}".format(self.Bits(self.code, 19, 15))

            if self.funct3 == '000':
                if self.funct12 == '000000000000':
                    opType = 'ecall'
                elif self.funct12 == '000000000001':
                    opType = 'ebreak'
                elif self.funct12 == '000000000010':
                    opType = 'uret'
                elif self.funct12 == '000100000010':
                    opType = 'sret'
                elif self.funct12 == '001100000010':
                    opType = 'mret'
                elif self.funct12 == '000100000101':
                    opType = 'wfi'
                elif self.funct12[0:7] == '0001001':
                    opType = 'sfence.vma ' + self.rs1 + ', ' + self.rs2
                else:
                    opType = 'unknown system'
            elif self.funct3 == "001":
                opType = 'csrrw ' + self.rd + ', ' + csr + ', ' + self.rs1
            elif self.funct3 == "010":
                opType = 'csrrs ' + self.rd + ', ' + csr + ', ' + self.rs1
            elif self.funct3 == "011":
                opType = 'csrrc ' + self.rd + ', ' + csr + ', ' + self.rs1
            elif self.funct3 == "101":
                opType = 'csrrwi ' + self.rd + ', ' + csr + ', ' + zimm
            elif self.funct3 == "110":
                opType = 'csrrsi ' + self.rd + ', ' + csr + ', ' + zimm
            elif self.funct3 == "111":
                opType = 'csrrci ' + self.rd + ', ' + csr + ', ' + zimm
            else:
                opType = 'unknown system'
            asmStr = opType
            return asmStr
