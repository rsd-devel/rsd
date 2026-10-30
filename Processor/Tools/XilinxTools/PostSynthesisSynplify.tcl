# Called by Makefile.synplify.mk from an isolated output directory.
set src $env(RSD_POST_SYNTHESIS_SRC)
# Reuse the project's source order and options without writing beside it.
set input [open $src/../Project/Synplify/ver2017-03.prj r]
set project_text [string map [list ../../Src $src] [read $input]]
close $input
set output [open rsd.prj w]
puts $output $project_text
close $output
project -load [file normalize rsd.prj]
impl -active Zedboard_post_synthesis
set_option -hdl_param -set MEM_INIT_HEX_FILE [file normalize code.hex]
project -result_file [file normalize netlist.vm]
project -run synthesis
