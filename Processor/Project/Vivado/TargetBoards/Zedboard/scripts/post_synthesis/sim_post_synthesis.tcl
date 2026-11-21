open_project $env(RSD_ROOT)/Processor/Project/Vivado/TargetBoards/Zedboard/rsd_post_synthesis/rsd_post_synthesis.xpr

# -mode post-(synthesis|implementation)
# -type (functional|timing)
# Vivado 2019.2 includes global headers even when used_in_simulation is false.
set header [get_files */SysDeps/SynthesisMacros.svh]
set_property is_global_include false $header
catch {
    launch_simulation -mode [lindex $argv 0] -type [lindex $argv 1]
    run all
} result options
set_property is_global_include true $header
return -options $options $result
