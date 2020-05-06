#!/usr/bin/python3
# -*- Coding: utf-8 -*-

import os
import re
import sys

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

# Copy from other template file
def write_header(fout):
    file_name = os.environ['RSD_ROOT'] + \
        "/Processor/Tools/XilinxTools/project_template_header.tcl"
    with open(file_name) as fin:
        fout.write(fin.read())

# Copy from other template file
def write_footer(fout):
    file_name = os.environ['RSD_ROOT'] + \
        "/Processor/Tools/XilinxTools/project_template_footer.tcl"
    with open(file_name) as fin:
        fout.write(fin.read())

# Target
TARGET_BOARD = sys.argv[1]
project_file = os.environ['RSD_ROOT'] + \
    "/Processor/Project/Vivado/TargetBoards/" + TARGET_BOARD + \
    "/scripts/post_synthesis/create_project_for_vivadosim.tcl"

# Read source file list from Makefile
srcs = parse_makefile_for_core_sources()

# Generate project
with open(project_file, mode="w") as fout:
    write_header(fout)

    # Write out source file list
    for src in srcs:
        fout.write(' [file normalize "${origin_dir}/../../../../Src/%s"] \\\n' \
            % src["name"])
    fout.write(' [file normalize "${origin_dir}/code.hex"] \\\n'
        ']\nadd_files -norecurse -fileset $obj $files\n\n'
        '# Set \'sources_1\' fileset file properties for remote files\n')

    for src in srcs:
        fout.write('set file "$origin_dir/../../../../Src/%s"\n' % src["name"])
        fout.write('set file [file normalize $file]\n')
        fout.write('set file_obj [get_files -of_objects [get_filesets sources_1] [list "*$file"]]\n')
        fout.write('set_property -name "file_type" -objects $file_obj ')
        if src["is_header"]:
            fout.write('-value "Verilog Header"\n\n')
        else:
            fout.write('-value "SystemVerilog"\n\n')

    write_footer(fout)

