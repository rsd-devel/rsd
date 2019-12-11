set hwdsgn [hsi::open_hw_design $env(RSD_ROOT)/Processor/Project/Vivado/Zedboard/rsd/rsd.sdk/design_1_wrapper.hdf]
hsi::generate_app -hw $hwdsgn -os standalone -proc ps7_cortexa9_0 -app zynq_fsbl -compile -sw fsbl -dir $env(RSD_ROOT)/Processor/Project/Vivado/Zedboard/rsd/rsd.sdk/zynq_fsbl
