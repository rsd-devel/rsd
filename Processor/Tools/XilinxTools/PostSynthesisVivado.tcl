# Called by Makefile.vivado.mk from an isolated output directory.
set src $env(RSD_POST_SYNTHESIS_SRC)
set timing [expr {[lindex $argv 0] eq "timing"}]
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
set period 10.000
if {$timing} {
    set period [lindex $argv 1]
}
create_clock -name core_clk -period $period [get_ports clk_p]
if {$timing} {
    # Keep the hierarchical debug signals read by the common testbench.
    set_property DONT_TOUCH true [get_nets -segments -regexp {debugRegister\[[0-9]+\]}]
    opt_design
    place_design
    route_design
}
report_utilization -file utilization.rpt
report_timing_summary -report_unconstrained -file timing.rpt
write_checkpoint -force netlist.dcp
if {$timing} {
    write_sdf -force -process_corner slow slow.sdf
    write_sdf -force -process_corner fast fast.sdf
    write_verilog -force -mode timesim -sdf_anno true netlist.v
} else {
    write_verilog -force -mode funcsim netlist.v
}
