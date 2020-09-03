open_project $env(RSD_ROOT)/Processor/Project/Vivado/TargetBoards/Zedboard/rsd_post_synthesis/rsd_post_synthesis.xpr
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1 -name synth_1
write_verilog -force -mode funcsim $env(RSD_ROOT)/Processor/Project/Vivado/TargetBoards/Zedboard/Main_post_synthesis.v
close_project
