open_project $env(RSD_ROOT)/Processor/Project/Vivado/Zedboard/rsd/rsd.xpr
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
file mkdir $env(RSD_ROOT)/Processor/Project/Vivado/Zedboard/rsd/rsd.sdk
file copy -force $env(RSD_ROOT)/Processor/Project/Vivado/Zedboard/rsd/rsd.runs/impl_1/design_1_wrapper.sysdef $env(RSD_ROOT)/Processor/Project/Vivado/Zedboard/rsd/rsd.sdk/design_1_wrapper.hdf
close_project
