open_project $env(RSD_ROOT)/Processor/Project/Vivado/TargetBoards/Zedboard/rsd_post_synthesis/rsd_post_synthesis.xpr
reset_run impl_1
launch_runs impl_1 -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementation failed: [get_property STATUS [get_runs impl_1]]"
}
close_project
