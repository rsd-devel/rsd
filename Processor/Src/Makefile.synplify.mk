# Makefile for Synplify synthesis and Vivado implementation.

SYNPLIFY_ROOT = ../Project/Synplify
SYNPLIFY_PROJECT_ROOT = $(SYNPLIFY_ROOT)/$(TARGET_BOARD)

MAKEFILE = Makefile.synplify.mk

# -------------------------------
# Synthesis
# This procedure uses both Synplify and Vivado.
#   1. Create Synplify netlist (launch Synplify manually and 
#	    open project $(RSD_ROOT)/Processor/Project/Synplify/ver2017-03.prj)
#   2. Synthesize RSD using Vivado
#

SYNPLIFY_NETLIST = $(SYNPLIFY_PROJECT_ROOT)/rsd.vm

# Vivado synthesis related items are defined in this file
include Makefiles/Vivado.inc.mk

$(VIVADO_PROJECT_FILE): $(SYNPLIFY_NETLIST)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode batch \
		-source scripts/synthesis/create_project_using_synplify_netlist.tcl
	
$(SYNPLIFY_NETLIST): $(TYPES) $(TEST_MODULES) $(MODULES)
	@ echo "(Re-)build board netlist using Synplify!"
	$(MAKE) -f $(MAKEFILE) vivado-clean
	@ exit 1

include Makefiles/CoreSources.inc.mk

# Functional simulation of a synthesized Zedboard core using XSim.
# Build TEST_CODE first; each invocation synthesizes its HEX into internal RAM.
SYNPLIFY ?= synplify_premier_dp
POST_SYNTHESIS_WORK = $(abspath ../Project/PostSynthesis/synplify/$(notdir $(TEST_CODE)))

export RSD_VIVADO_BIN
export RSD_POST_SYNTHESIS_SRC = $(CURDIR)
POST_SYNTHESIS_SCRIPT = $(abspath ../Tools/XilinxTools/PostSynthesisSynplify.tcl)
POST_SYNTHESIS_XILINX = $(abspath $(RSD_VIVADO_BIN)/../data/verilog/src)

$(CORE_TEMPLATE_FILES): $(wildcard Generator/*.py) default.yml $(CORE_TEMPLATE_FILES:.sv=.template.sv)
	python3 Generator/cpu_generator.py --rsd-root $(abspath ../..)

.PHONY: test-post-synthesis post-synthesis-build
# These targets need UART output; command-line TEST_CODE overrides this default.
test-post-synthesis post-synthesis-build: TEST_CODE = Verification/TestCode/C/HelloWorld
post-synthesis-build: $(CORE_TEMPLATE_FILES)
	test -s $(TEST_CODE)/code.hex && test -s $(TEST_CODE)/serial.ref.txt
	test -x $(RSD_VIVADO_BIN)/xsim
	mkdir -p $(POST_SYNTHESIS_WORK)
	cp $(TEST_CODE)/code.hex $(TEST_CODE)/cfg.xml $(TEST_CODE)/serial.ref.txt $(POST_SYNTHESIS_WORK)/
	rm -f $(POST_SYNTHESIS_WORK)/netlist.vm
	cd $(POST_SYNTHESIS_WORK) && $(SYNPLIFY) -batch $(POST_SYNTHESIS_SCRIPT)
	test -s $(POST_SYNTHESIS_WORK)/netlist.vm

test-post-synthesis: post-synthesis-build
	cd $(POST_SYNTHESIS_WORK) && $(RSD_VIVADO_BIN)/xvlog -sv \
		-i $(CURDIR) $(patsubst +define+%,-d %,$(RSD_SRC_CFG)) \
		-d RSD_FUNCTIONAL_SIMULATION -d RSD_POST_SYNTHESIS_SIMULATION \
		$(abspath $(filter-out $(TEST_MODULES),$(TYPES)) $(TEST_MODULES))
	cd $(POST_SYNTHESIS_WORK) && $(RSD_VIVADO_BIN)/xvlog netlist.vm $(POST_SYNTHESIS_XILINX)/glbl.v
	cd $(POST_SYNTHESIS_WORK) && $(RSD_VIVADO_BIN)/xelab -relax -timescale 1ns/1ps -L unisims_ver \
		-s post_synthesis work.TestMain work.glbl
	timeout 12h python3 ../Tools/TestDriver/RunTest.py --simulator=post-synthesis $(POST_SYNTHESIS_WORK)

# Keep the existing entry points on the same XSim test flow.
.PHONY: post-synthesis post-synthesis-run post-synthesis-clean
post-synthesis post-synthesis-run: test-post-synthesis

post-synthesis-clean:
	rm -rf ../Project/PostSynthesis/synplify
