include Makefiles/Environment.inc.mk

# Synplify synthesis and Vivado implementation.
.DEFAULT_GOAL := vivado

include Makefiles/Build.inc.mk

SYNPLIFY_ROOT = ../Project/Synplify
SYNPLIFY_PROJECT_ROOT = $(SYNPLIFY_ROOT)/$(TARGET_BOARD)

MAKEFILE = Makefiles/Synplify.mk

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


# Functional simulation of a synthesized Zedboard core using XSim.
# Build TEST_CODE first; each invocation synthesizes its HEX into internal RAM.
SYNPLIFY ?= synplify_premier_dp
POST_SYNTHESIS_WORK = $(abspath ../Project/PostSynthesis/synplify/$(notdir $(TEST_CODE)))

POST_SYNTHESIS_SCRIPT = $(abspath ../Tools/XilinxTools/PostSynthesisSynplify.tcl)

.PHONY: test-post-synthesis post-synthesis-build
post-synthesis-build: $(CORE_TEMPLATE_FILES)
	test -s $(TEST_CODE)/code.hex && test -s $(TEST_CODE)/serial.ref.txt
	test -x $(RSD_VIVADO_BIN)/xsim
	mkdir -p $(POST_SYNTHESIS_WORK)
	cp $(TEST_CODE)/code.hex $(TEST_CODE)/cfg.xml $(TEST_CODE)/serial.ref.txt $(POST_SYNTHESIS_WORK)/
	rm -f $(POST_SYNTHESIS_WORK)/netlist.vm
	cd $(POST_SYNTHESIS_WORK) && $(SYNPLIFY) -batch $(POST_SYNTHESIS_SCRIPT)
	test -s $(POST_SYNTHESIS_WORK)/netlist.vm

POST_SYNTHESIS_NETLIST = netlist.vm
include Makefiles/PostSynthesis.inc.mk

.PHONY: post-synthesis-clean
post-synthesis-clean:
	rm -rf ../Project/PostSynthesis/synplify
