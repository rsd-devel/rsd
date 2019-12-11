# -*- coding: utf-8 -*-

#
# バイナリファイルを、RSDで用いるHEXファイルに変換する。
#
# HEXファイルの内容は雷上動のメモリにロードされるもので、
# $readmemhを使う都合でフォーマットが決まっている。
# 具体的には、HEXファイルの1行がメモリの1エントリに対応し、
# 1行の中ではアドレスが大きい方から順に並ぶようにする。
#
# 1番目の引数で変換前のバイナリファイル名を、
# 2番目の引数で変換後のHEXファイル名を指定する。
# 3番目の引数は任意で、変換するサイズをバイト数で指定する。
#

import os, sys
import struct

# メモリの1エントリ当たりのバイト数
ENTRY_BYTE_SIZE = 16

#
# Entry point
#
if len(sys.argv) < 3:
    print "Usage: %s BinaryFileName HexFileName [ Size ]" % ( sys.argv[0] )

binFileName = sys.argv[1]
hexFileName = sys.argv[2]

# Read a binary file.
binFile = open( binFileName, 'rb' )
binData = binFile.read()
binFile.close()

if len(sys.argv) >= 4:
    convertSize = int( sys.argv[3], 0 )
else:
    convertSize = len( binData )

# Generate a hex string.
strListPerByte = []
for ptr in range( 0, convertSize ):
    ( byteData, ) = struct.unpack( "<B", binData[ ptr ] )
    byteDataString = "%02x" % ( byteData )
    strListPerByte.append(byteDataString)

strListPerEntry = []
for offset in range(0, convertSize, ENTRY_BYTE_SIZE):
    tmpList = strListPerByte[ offset : offset + ENTRY_BYTE_SIZE ]
    # 行内ではアドレスが大きい順に並ぶようにするため、
    # スライスの3つ目のパラメータで逆順にする
    entryString = ''.join( tmpList[::-1] )
    strListPerEntry.append(entryString)

strHexFile = '\n'.join( strListPerEntry )

# Write a hex file.
hexFile = open( hexFileName, 'wb' )
hexFile.write( strHexFile )
hexFile.close()
