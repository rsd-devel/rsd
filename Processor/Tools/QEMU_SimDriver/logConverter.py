# -*- coding: utf-8 -*-

# python3 logConverter dumpFile
#
# QEMUが出力したダンプファイル(make qemu-dumpコマンドで出力されるQEMU.log)
# をCSV形式に変換する。
#
# 2017/5/30現在, QEMU.logにはret,jr後の命令の実行結果が表示されない(実行はされている)ため,
# 疑似的にそれらの後の命令のPCのみを挿入してregister.csvの形式と合わせている。

import os
import sys
import subprocess
import struct
import re
from optparse import OptionParser

xRegs = ['zero', 'ra', 'sp', 'gp', 'tp', 't0', 't1', 't2',
          'fp', 's1', 'a0', 'a1', 'a2', 'a3', 'a4', 'a5',
          'a6', 'a7', 's2', 's3', 's4', 's5', 's6', 's7',
          's8', 's9', 's10', 's11', 't3', 't4', 't5', 't6',
          'pc']

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
    print ("Error : no log file specified.")
    sys.exit(2)

logFileName = argList[0]
csvFileName = argList[1]

#
# Convert a dumped log file to a register-csv.
#

logFile = open(logFileName, "r");
csvFile = open(csvFileName, 'w' )
splitList = []
outputLine = ""
retFlag = False
while True:
    readLine = logFile.readline()
    if readLine == "" :
        break
    splitList = readLine.split()

    if len(splitList) == 0:
        break

    #if splitList[0] == "=>":    #Instruction Line
    # 2017/5/30現在, QEMU.logにはret,jr後の命令の実行結果が表示されない(実行はされている)ため,
    # 疑似的にそれらの後の命令のPCのみを挿入してregister.csvの形式と合わせている。
    #if readLine "ret" or splitList[3] == "jr" or splitList[3] == "jalr":
    #    retFlag = True
    #print(readLine)
    if re.search(r"(csr)|(jr)|(jalr)|(ret)", readLine):
        retFlag = True

    if splitList[0] in xRegs:
        if splitList[0] == "pc":
            #pc = "0x" + splitList[1][6:]   # lower 16bits only
            pc = splitList[1]
            if retFlag:
                #prevPC = hex(int(splitList[1][6:],16)-4)
                prevPC = hex(int(splitList[1],16)-4)
                csvFile.write('\n')
                retFlag = False
            outputLine = pc+",0x00000000"+outputLine
            csvFile.write(outputLine+'\n')
            outputLine = ""
        else:
            outputLine+=','+splitList[1]
csvFile.close()
