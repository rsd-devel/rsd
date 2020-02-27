# set the workspace
setws $env(RSD_ROOT)/Processor/Project/Vivado/TargetBoards/Zedboard/rsd/rsd.sdk
#
# CREATE FSBL FROM TEMPLATE
#
app create -name fsbl -template {Zynq FSBL} -proc ps7_cortexa9_0 -hw $env(RSD_ROOT)/Processor/Project/Vivado/TargetBoards/Zedboard/rsd/design_1_wrapper.xsa -os standalone
app config -name fsbl build-config release
app build -name fsbl
