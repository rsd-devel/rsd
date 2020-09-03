open_project $env(RSD_ROOT)/Processor/Project/Vivado/TargetBoards/Zedboard/rsd_post_synthesis/rsd_post_synthesis.xpr
reset_run synth_1
launch_runs impl_1 -jobs 4
wait_on_run impl_1
close_project
