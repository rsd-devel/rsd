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
    print(f"Usage: {sys.argv[0]} BinaryFileName HexFileName [ Size ]")

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


with open( hexFileName, 'w' ) as hexFile:
    # 各行内ではアドレスが大きい順で並ぶ必要があるので，適宜逆順にしながら出力する
    for offset in range(0, convertSize, ENTRY_BYTE_SIZE):
        tmpList = binData[offset : offset + ENTRY_BYTE_SIZE]
        if tmpList:
            s = ''.join(map(lambda x: f"{x:02x}", tmpList[::-1])) + '\n'
        else:
            s = '0' * ENTRY_BYTE_SIZE * 2 + '\n'
        hexFile.write(s)

