open_project $env(RSD_ROOT)/Processor/Project/Vivado/Zedboard/rsd_post_synthesis/rsd_post_synthesis.xpr
launch_simulation -mode post-synthesis -type functional
run all
