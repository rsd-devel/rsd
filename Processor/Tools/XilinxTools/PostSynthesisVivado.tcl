# Called by Makefile.vivado.mk from an isolated output directory.
set src $env(RSD_POST_SYNTHESIS_SRC)
set_param general.maxThreads 4
create_project -in_memory -part xc7z020clg484-1
set_property target_language Verilog [current_project]
set_property include_dirs [list $src] [current_fileset]
set_property verilog_define {RSD_POST_SYNTHESIS} [current_fileset]
read_verilog -sv $src/SysDeps/SynthesisMacros.svh
set header [get_files *SynthesisMacros.svh]
set_property file_type {Verilog Header} $header
set_property is_global_include true $header
read_verilog -sv $env(RSD_POST_SYNTHESIS_SOURCES)
synth_design -top Main_Zynq_Wrapper -part xc7z020clg484-1 -mode out_of_context
create_clock -name core_clk -period 10.000 [get_ports clk_p]
report_utilization -file utilization.rpt
report_timing_summary -file timing.rpt
write_checkpoint -force netlist.dcp
write_verilog -force -mode funcsim netlist.v
