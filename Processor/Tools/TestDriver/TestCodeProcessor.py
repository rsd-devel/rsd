# -*- coding: utf-8 -*-

import sys, re

class TestCodeProcessor:
    
    LINE_TYPE_PSEUDO_OP = "P"
    LINE_TYPE_OP = "O"
    LINE_TYPE_LABEL = "L"
    LINE_TYPE_COMMENT = "C"

    class Op( object ):
        CONDITION_STR_LIST = [
            "eq", "ne", "cs", "cc",
            "mi", "pl", "vs", "vc",
            "hi", "ls", "ge", "lt",
            "gt", "le", 
        ]

    # 命令を複数の命令に分解する際、
    # それらの命令を管理するためのクラス
    class InsnList( Op ):
        def __init__( self ):
            self.firstInsnList = []
            self.insnList = []
            self.lastInsnList = []

        # リストの先頭に置かなければならない命令を追加。
        #   - 例: ldm/stmにおけるベースレジスタの更新
        # 既に先頭に置くとされた命令がある場合はエラーとなる。
        def AddFirst( self, insnStr ):
            if ( len(self.firstInsnList) != 0 ):
                raise BaseException( "InsnList::AddFirst cannot be called more than once for each InsnList instance." )

            self.firstInsnList.append( insnStr )

        # 命令を追加
        def Add( self, insnStr ):
            self.insnList.append( insnStr )

        # リストの末尾に置かなければならない命令を追加。
        #   - 例: ldm/stm における PC or ベースレジスタ へのロード
        # 既に先頭に置くとされた命令がある場合はエラーとなる。
        #   - 例: ldm/stm における PCとベースレジスタの両方にロードする場合
        def AddLast( self, insnStr ):
            if ( len(self.lastInsnList) != 0 ):
                raise BaseException( "InsnList::AddLast cannot be called more than once for each InsnList instance." )

            self.lastInsnList.append( insnStr )

        # Addされた命令群を、アセンブリコードの形(1命令1行)の文字列にして出力
        def GetCode( self ):
            codeStr = ""

            for insnStr in self.firstInsnList:
                codeStr += "\t" + insnStr
            for insnStr in self.insnList:
                codeStr += "\t" + insnStr
            for insnStr in self.lastInsnList:
                codeStr += "\t" + insnStr

            return codeStr

    class OpMultipleLoadStore( Op ):
        ADDR_MODE_POST_INCREMENT = 'POST_INC'
        ADDR_MODE_PRE_INCREMENT = 'PRE_INC'
        ADDR_MODE_POST_DECREMENT = 'POST_DEC'
        ADDR_MODE_PRE_DECREMENT = 'PRE_DEC'

        ADDR_MODE_STR_LIST = [
            "da", "db", "fa", "fd", 
            "ia", "ib", "ea", "ed",
        ]


        def __init__( self, line ):
            # Parse line
            m = re.search( '\t(\w+)\t(\w+)(!?).*{(.*)}.*', line )
            opcode = m.group(1)
            self.baseRegName = m.group(2)
            self.baseRegWE = ( m.group(3) == "!" )
            self.srcRegNameList = re.split('\W+', m.group(4))

            # ldm/stmのどちらか判断
            opcode = opcode.lower()
            if ( opcode.find( "ldm" ) == 0 ):
                self.isLoad = True
                opOptionsStr = opcode[len( "ldm" ):]
            elif ( opcode.find( "stm" ) == 0 ):
                self.isLoad = False
                opOptionsStr = opcode[len( "stm" ):]
            else:
                print ( "Error: " + opcode + " is not a multiple load/store instruction." )
                raise BaseException

            # オペコードのldm/stm以降の文字列を解析
            # 条件コードやアドレッシングモードがわかる
            self.cond = None
            self.mode = None
            while opOptionsStr != "":
                opOption = opOptionsStr[:2]
                if opOption in self.CONDITION_STR_LIST:
                    self.cond = opOption
                elif opOption in self.ADDR_MODE_STR_LIST:
                    if ( self.isLoad ):
                        if ( opOption in [ "da", "fa" ] ):
                            self.mode = self.ADDR_MODE_POST_DECREMENT
                        elif ( opOption in [ "ia", "fd" ] ):
                            self.mode = self.ADDR_MODE_POST_INCREMENT
                        elif ( opOption in [ "db", "ea" ] ):
                            self.mode = self.ADDR_MODE_PRE_DECREMENT
                        elif ( opOption in [ "ib", "ed", ] ):
                            self.mode = self.ADDR_MODE_PRE_INCREMENT
                    else:
                        if ( opOption in [ "da", "ed" ] ):
                            self.mode = self.ADDR_MODE_POST_DECREMENT
                        elif ( opOption in [ "ia", "ea" ] ):
                            self.mode = self.ADDR_MODE_POST_INCREMENT
                        elif ( opOption in [ "db", "fd" ] ):
                            self.mode = self.ADDR_MODE_PRE_DECREMENT
                        elif ( opOption in [ "ib", "fa" ] ):
                            self.mode = self.ADDR_MODE_PRE_INCREMENT
                else:
                    print ( "Error: Cannot parse opcode: " + opcode )
                    raise BaseException
                opOptionsStr = opOptionsStr.lstrip( opOption )

            if self.mode is None:
                print ( "Error: Unknown opcode: " + opcode )
                raise BaseException

        def GetAlternativeCode( self ):
            opcode = "ldr" if self.isLoad else "str"
            opcodeAdd = "add"
            if self.cond is not None:
                opcode += self.cond
                opcodeAdd += self.cond

            if ( self.mode in [ self.ADDR_MODE_POST_INCREMENT, self.ADDR_MODE_PRE_INCREMENT ] ):
                offset = 0
                finalOffset = 4 * len( self.srcRegNameList )
            else: # ADDR_MODE_POST_DECREMENT or self.ADDR_MODE_PRE_DECREMENT
                offset = - 4 * len( self.srcRegNameList )
                finalOffset = - 4 * len( self.srcRegNameList )

            insnList =  TestCodeProcessor.InsnList()

            # BaseReg is updated before multiple-loads for load-PC instruction.
            if ( self.baseRegWE ):
                insnList.AddFirst( "%s\t%s, #%d\n" % ( opcodeAdd, self.baseRegName, finalOffset ) )

            for regName in self.srcRegNameList:
                # Adjust offset
                if ( self.mode in [ self.ADDR_MODE_PRE_INCREMENT, self.ADDR_MODE_POST_DECREMENT ] ):
                    offset += 4
                if ( self.baseRegWE ):
                    fixedOffset = offset - finalOffset
                else:
                    fixedOffset = offset
                
                # Add an insn string to insnList
                insnStr = "%s\t%s, [%s, #%d]\n" % ( opcode, regName, self.baseRegName, fixedOffset )
                if ( regName in [ self.baseRegName, "pc" ] ):
                    insnList.AddLast( insnStr )
                else:
                    insnList.Add( insnStr )

                # Adjust offset
                if ( self.mode in [ self.ADDR_MODE_POST_INCREMENT, self.ADDR_MODE_PRE_DECREMENT ] ):
                    offset += 4

            return insnList.GetCode()


    def __init__( self ):
        self.labelNum = 0

    def CreateNewLabel( self ):
        self.labelNum += 1
        return ".Label_RSD%d" % self.labelNum

    def GetLineType( self, line ):
        if ( line[0] == '\t' ):
            if ( line[1] == '.' ):
                return self.LINE_TYPE_PSEUDO_OP
            elif ( line[1] == '@' ):
                return self.LINE_TYPE_COMMENT
            else:
                return self.LINE_TYPE_OP
        else:
            return self.LINE_TYPE_LABEL

    # ldm/stm
    def ProcessMultipleLoadStore( self, line ):
        op = self.OpMultipleLoadStore( line )
        return op.GetAlternativeCode()

    # fldm/fstm (vpush/vpop)
    def ProcessVectorMultipleLoadStore( self, line ):
        return ""

    def ProcessPseudoOp ( self, line ):
        return line

    def ProcessOp ( self, line ):
        text = line.lstrip().rstrip()
        if ( text.find( "ldm" ) == 0 or text.find ( "stm" ) == 0 ):
            line = self.ProcessMultipleLoadStore( line )
        elif ( text.find( "fldm" ) == 0 or text.find ( "fstm" ) == 0 ):
            line = self.ProcessVectorMultipleLoadStore( line )
        return line
    
    def ProcessLine( self, line ):
        lineType = self.GetLineType( line )

        if ( lineType == self.LINE_TYPE_OP ):
            return self.ProcessOp( line )
        elif ( lineType == self.LINE_TYPE_PSEUDO_OP ):
            return self.ProcessPseudoOp( line )
        else:
            return line

    def Process( self, fileName ):
        self.processedString = ""

        file = open( fileName, "r" )
        while True:
            line = file.readline()
            if ( line == "" ):
                break
            self.processedString += self.ProcessLine( line )
        file.close()

    def Write( self, fileName ):
        file = open( fileName, "w" )
        file.write( self.processedString )
        file.close()

#
# The entry point of this program.
#
if ( len(sys.argv) < 3 ):
    print( "usage: %(exe)s in-file out-file" % { 'exe': sys.argv[0] } )
    exit(1)

testCodeProcessor = TestCodeProcessor()
testCodeProcessor.Process( sys.argv[1] )
testCodeProcessor.Write( sys.argv[2] )
   