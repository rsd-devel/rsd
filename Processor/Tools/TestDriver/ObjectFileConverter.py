# -*- coding: utf-8 -*-

# python ObjectFileConverter dumpFile [--large-mem] [ --datafile=dataFile ] [--before-link]
#
# コンパイル済のオブジェクトファイルをダンプしたもの（objdump -D の出力）を、
# ARCコンテストで使用するバイナリファイル(256KB)に変換する。
#
# -s オプションは、リンク前のオブジェクトファイルを使う時に指定する。

import os
import sys
import subprocess
import struct
import re
from optparse import OptionParser


#
# Please customize this for each environment!
#

# Size of a word and a cache line.
BYTE_PER_WORD = 4 # 4 byte / word

# The value stored to uninitilized area.
HEX_STRING_DEFAULT_VALUE = '0x00000000'

# Memory size
HEX_STRING_MEM_SIZE = '0x18000'


class RSD_Memory( object ):

    def __init__( self, wordNum, bytePerWord ):
        self.wordNum = wordNum
        self.bytePerWord = bytePerWord

        # メモリ領域全体を HEX_STRING_DEFAULT_VALUE で初期化する
        # 初期化せずにx(不定)の値が残ってしまうと、
        # 合成前後でシミュレーション結果が変わってしまう
        defaultValue = int( HEX_STRING_DEFAULT_VALUE, 16 )
        self.wordList = [defaultValue] * wordNum

    def SetWord( self, addr, word ):
        if addr % 4 == 0:
            self.wordList[ addr / self.bytePerWord ] = word
        if ( addr % 4 == 1 ) or ( addr % 4 == 3 ):
            print("this alignment does not assumed!",hex(addr),hex(word))
            sys.exit(1)
        if addr % 4 == 2:
            # 4バイト境界をまたがるようなデータの格納
            upperWord = self.wordList[ ( addr + 2 ) / self.bytePerWord ]
            upperWord = upperWord & 0xffff0000
            upperWord = upperWord | ( ( word >> 16 ) & 0x0000ffff ) #論理シフト
            self.wordList[ ( addr + 2 ) / self.bytePerWord ] = upperWord
            lowerWord = self.wordList[ ( addr - 2 ) / self.bytePerWord ]
            lowerWord = lowerWord & 0x0000ffff
            lowerWord = lowerWord | ( ( word & 0x0000ffff ) << 16 ) #論理シフト
            self.wordList[ ( addr - 2 ) / self.bytePerWord ] = lowerWord

    def SetHalfWord( self, addr, halfWord ):
        upper = ( ( addr%self.bytePerWord ) == 2)
        word = self.wordList[ addr / self.bytePerWord ]
        if upper:
            word = word & 0x0000ffff
            word = word | ( halfWord << 16 )
            self.wordList[ addr / self.bytePerWord ] = word
        else:
            word = word & 0xffff0000
            word = word | halfWord
            self.wordList[ addr / self.bytePerWord ] = word

    def SetByte( self, addr, byte ):
        align = addr%self.bytePerWord
        word = self.wordList[ addr / self.bytePerWord ]
        if align == 0:
            word = word & 0xffffff00
            word = word | byte
            self.wordList[ addr / self.bytePerWord ] = word
        elif align == 1:
            word = word & 0xffff00ff
            word = word | ( byte << 8 )
            self.wordList[ addr / self.bytePerWord ] = word
        elif align == 2:
            word = word & 0xff00ffff
            word = word | ( byte << 16 )
            self.wordList[ addr / self.bytePerWord ] = word
        elif align == 3:
            word = word & 0x00ffffff
            word = word | ( byte << 24 )
            self.wordList[ addr / self.bytePerWord ] = word

    def WriteBinFile( self, binFileName ):
        binFile = open( binFileName, 'wb' )
        for word in self.wordList:
            binFile.write( struct.pack( "<I", word ) )
        binFile.close()

#
# The entry point of this program.
#

#
# Parse arguments
#

parser = OptionParser()
parser.add_option('--before-link', action='store_true', dest='isBeforeLink', default=False,
                  help='Specify this option if the object file is before linking.')
options, argList = parser.parse_args()

if not argList:
    print ("Error : no obj file specified.")
    sys.exit(2)

objFileName = argList[0]
binFileName = re.sub('\.[^\.]+$', '.bin', objFileName ) # 拡張子をbinに変更

#
# Instantiate RSD_Memory
#
memorySize = int( HEX_STRING_MEM_SIZE, 16 )
rsdMemory = RSD_Memory( memorySize / BYTE_PER_WORD, BYTE_PER_WORD )

#
# Convert a dumped file to a hex.
#

file = open(objFileName, "r");

while True:
    line = file.readline()
    if line == "" :
        break
    if "debug" in line :
        break
    match = re.match( r"\s*([0-9|a-f|A-F]+)\:[\s]+([0-9|a-f|A-F]+).*", line )
    if match is not None:
        addr = int( match.group(1), 16 )
        word = int( match.group(2), 16 )

        if len(match.group(2)) == 8:
            rsdMemory.SetWord( addr, word )
        elif len(match.group(2)) == 4:
            rsdMemory.SetHalfWord( addr, word )
        elif len(match.group(2)) == 2:
            rsdMemory.SetByte( addr, word )

#
# Write a hex file.
#
rsdMemory.WriteBinFile( binFileName )
