open_project $env(RSD_ROOT)/Processor/Project/Vivado/TargetBoards/Zedboard/rsd_post_synthesis/rsd_post_synthesis.xpr

# -mode post-(synthesis|implementation)
# -type (functional|timing)
launch_simulation -mode [lindex $argv 0] -type [lindex $argv 1]
run all
