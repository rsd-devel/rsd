#!/usr/bin/python3
# -*- Coding: utf-8 -*-

import os
import re
import sys
from xml.etree import ElementTree
import xml.dom.minidom as md

def parse_makefile_for_core_sources():
    file_name = os.environ['RSD_ROOT'] + "/Processor/Src/Makefiles/CoreSources.inc.mk"
    sources = []
    is_header = False
    print("Parsing %s..." % file_name)
    with open(file_name) as fin:
        for line in fin:
            line = line.split("#")[0] # Remove comment
            m = re.match("HEADERS =", line)
            if m:
                is_header = True
                continue

            m = re.match("\t([^\s]+.(svh|sv|v|vh)) \\\\", line)
            if m:
                sources.append({"name": m.group(1), "is_header": is_header})

    return sources

TARGET_BOARD = sys.argv[1]
srcs = parse_makefile_for_core_sources()

template_file =  os.environ['RSD_ROOT'] + "/Processor/Tools/XilinxTools/ip_template.xml"
ip_path = os.environ['RSD_ROOT'] + "/Processor/Project/Vivado/TargetBoards/" + \
    TARGET_BOARD + "/rsd_ip/Vivado/"
target_file = ip_path + "/component.xml"

readbuf = ""
# Parse template file of Xilinx custom IP.
# To create a custom IP for RSD, parse Makefiles/CoreSources.inc.mk and 
# add RSD's source files to the custom IP description.
with open(template_file) as fin:
    for line in fin:
        m = re.match("^\s*(.+)$", line)
        readbuf += m.group(1)

root = ElementTree.fromstring( readbuf )

# Namespace in template xml file
ns = ".//{http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009}"

# Find the part that describes source files
fileSets = root.find(ns + "fileSets")
fileSet = fileSets[0]
for src in srcs:
    file_name = src["name"]
    if file_name.split("/")[0] == "Verification":
        continue

    file = ElementTree.SubElement(fileSet, "ns0:file")
    ElementTree.SubElement(file, "ns0:name").text =  "../../../../../../Src/" + file_name
    ElementTree.SubElement(file, "ns0:fileType").text = "systemVerilogSource"
    ElementTree.SubElement(file, "ns0:userFileType").text = "IMPORTED_FILE"
    if src["is_header"]:
        ElementTree.SubElement(file, "ns0:isIncludeFile").text = "true"

# 文字列パースを介してminidomへ移す
document = md.parseString(ElementTree.tostring(root))
document = document.toprettyxml(indent="  ", newl="\n")
with open(target_file, mode='w') as fout:
    fout.write(document)
print("Succeeded to generate RSD IP file!")
