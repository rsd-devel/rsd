# -*- coding: utf-8 -*-

# python3 GDB_CommandFileGenerator GDB_CommandFile SimCycle
#
# QEMUでのシミュレーションに必要なGDBのコマンドファイルを生成します
# わざわざコマンドファイルを生成しているのは
# GDBに, MakefileのMAX_TEST_CYCLESを渡す方法がわからなかったからです

import os
import sys
import subprocess
import struct
import re
from optparse import OptionParser

command = \
"define dumpReg\n \
set $numExecInsn = simCycle\n \
set $i = 0\n \
	while($i<$numExecInsn)\n \
		set $i = $i + 1\n \
		info registers\n \
		x/i $pc\n \
		stepi\n \
	end\n \
end \n \
\n \
target remote localhost:gdbPortNum\n \
dumpReg\n \
quit\n \
y"

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
    print ("Error : no command file specified.")
    sys.exit(2)

commandFileName = argList[0]
simCycle = argList[1]
gdbPortNum = argList[2]

#
# generate GDB command file
#
#
commandFile = open(commandFileName, "w")
cmd = command
cmd = cmd.replace("simCycle", simCycle)
cmd = cmd.replace("gdbPortNum", gdbPortNum)
commandFile.write(cmd)
commandFile.close()
