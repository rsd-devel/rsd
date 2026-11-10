# Shared XSim checks for Vivado and Synplify netlists.
# The synthesis backend supplies POST_SYNTHESIS_NETLIST and optional defines.
# Match the netlist configuration, including synthesis-only overrides.
export RSD_VIVADO_BIN
export RSD_POST_SYNTHESIS_SRC = $(CURDIR)
POST_SYNTHESIS_XILINX = $(abspath $(RSD_VIVADO_BIN)/../data/verilog/src)

.PHONY: test-post-synthesis post-synthesis post-synthesis-run
# These targets need UART output; command-line TEST_CODE overrides this default.
test-post-synthesis post-synthesis-build: TEST_CODE = Verification/TestCode/C/HelloWorld

test-post-synthesis: post-synthesis-build
	cd $(POST_SYNTHESIS_WORK) && $(RSD_VIVADO_BIN)/xvlog -sv \
		-i $(CURDIR) $(patsubst +define+%,-d %,$(RSD_SYNTHESIS_SRC_CFG)) \
		-d RSD_FUNCTIONAL_SIMULATION -d RSD_POST_SYNTHESIS_SIMULATION \
		$(addprefix -d ,$(POST_SYNTHESIS_DEFINES)) \
		$(abspath $(filter-out $(TEST_MODULES),$(TYPES)) $(TEST_MODULES))
	cd $(POST_SYNTHESIS_WORK) && $(RSD_VIVADO_BIN)/xvlog $(POST_SYNTHESIS_NETLIST) $(POST_SYNTHESIS_XILINX)/glbl.v
	cd $(POST_SYNTHESIS_WORK) && $(RSD_VIVADO_BIN)/xelab -relax -timescale 1ns/1ps -L unisims_ver \
		-s post_synthesis work.TestMain work.glbl
	timeout 12h python3 ../Tools/TestDriver/RunTest.py --simulator=post-synthesis $(POST_SYNTHESIS_WORK)

post-synthesis post-synthesis-run: test-post-synthesis
