
# instantiation
set design_name Core

# Specify library files
set link_library {
    "*"
}

#set target_library {
#    ~/workspace/RSD/lib/---.db
#}

# Include search path
lappend search_path "../../Src/"

# Working directory
define_design_lib WORK -path "./work"



# Specify source files
set file_names $env(RSD_DC_SOURCE_FILES)

foreach file_name $file_names {
	analyze -format sverilog -define RSD_SYNTHESIS,RSD_SYNTHESIS_DESIGN_COMPILER $file_name
}


elaborate $design_name -work WORK

# eliminate old library cells
suppress_message TRANS-1

current_design $design_name
set_local_link_library $link_library

# Report check_design
redirect check_design.log { check_design }
# write -f ddc -o read.ddc -hier $design_name

link

exit
