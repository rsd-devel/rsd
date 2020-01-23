open_project $env(RSD_ROOT)/Processor/Project/Vivado/Zedboard/rsd_post_synthesis/rsd_post_synthesis.xpr
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

