open_project $env(RSD_ROOT)/Processor/Project/Vivado/TargetBoards/Zedboard/rsd/rsd.xpr
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 16
wait_on_run impl_1
file mkdir $env(RSD_ROOT)/Processor/Project/Vivado/TargetBoards/Zedboard/rsd/rsd.sdk
write_hw_platform -fixed -force  -include_bit -file $env(RSD_ROOT)/Processor/Project/Vivado/TargetBoards/Zedboard/rsd/design_1_wrapper.xsa
close_project
