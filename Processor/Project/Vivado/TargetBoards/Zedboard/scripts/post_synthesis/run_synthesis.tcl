open_project $env(RSD_ROOT)/Processor/Project/Vivado/TargetBoards/Zedboard/rsd_post_synthesis/rsd_post_synthesis.xpr
set_property is_global_include true [get_files */SysDeps/SynthesisMacros.svh]
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
close_project
