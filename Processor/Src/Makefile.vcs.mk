# Routed timing simulation with VCS using a Vivado netlist.
# Build TEST_CODE first. Use post-implementation-run to reuse the routed netlist.
.DEFAULT_GOAL := test-post-implementation

include Makefiles/CoreSources.inc.mk

TEST_CODE ?= Verification/TestCode/C/HelloWorld
POST_SYNTHESIS_WORK = $(abspath ../Project/PostSynthesis/vivado-timing/$(notdir $(TEST_CODE)))

VCS ?= vcs
VCS_JOBS ?= 4
VCS_CORNER ?= slow
VCS_DELAY ?= max
VCS_XILINX ?= $(abspath $(RSD_VIVADO_BIN)/../data/verilog/src)
POST_IMPLEMENTATION_CLOCK_NS ?= 32
VCS_NETLIST = $(POST_SYNTHESIS_WORK)/netlist.v
VCS_SDF = $(POST_SYNTHESIS_WORK)/$(VCS_CORNER).sdf
VCS_SDF_TOOL = $(abspath ../Tools/XilinxTools/VcsSdf.py)

.PHONY: test-post-implementation post-implementation-build post-implementation-run
test-post-implementation: post-implementation-build

# Vivado owns synthesis, placement, routing, and netlist/SDF export.
post-implementation-build:
	$(MAKE) -f Makefile.vivado.mk post-implementation-build \
		TEST_CODE="$(TEST_CODE)" POST_SYNTHESIS_WORK="$(POST_SYNTHESIS_WORK)" \
		POST_IMPLEMENTATION_CLOCK_NS=$(POST_IMPLEMENTATION_CLOCK_NS)

test-post-implementation post-implementation-run:
	test "$(VCS_CORNER)" = slow || test "$(VCS_CORNER)" = fast
	test "$(VCS_DELAY)" = min || test "$(VCS_DELAY)" = max
	# RAM initialization is embedded in the netlist: rebuild when the HEX changes.
	cmp $(TEST_CODE)/code.hex $(POST_SYNTHESIS_WORK)/code.hex
	cp $(TEST_CODE)/cfg.xml $(TEST_CODE)/serial.ref.txt $(POST_SYNTHESIS_WORK)/
	python3 $(VCS_SDF_TOOL) expand $(VCS_SDF) $(POST_SYNTHESIS_WORK)/$(notdir $(VCS_NETLIST:.v=.sdf))
	cd $(POST_SYNTHESIS_WORK) && rm -f simv sdfAnnotateInfo compile.log
	cd $(POST_SYNTHESIS_WORK) && timeout 2h $(VCS) -full64 -sverilog -j$(VCS_JOBS) \
		-timescale=1ps/1ps -tcheckvecsplit +define+XIL_TIMING +$(VCS_DELAY)delays \
		+neg_tchk +transport_int_delays +pulse_r/0 +pulse_e/0 +pulse_int_r/0 +pulse_int_e/0 +sdfverbose \
		-top TestMain -top glbl -pvalue+TestMain.CLOCK_PERIOD_NS=$(POST_IMPLEMENTATION_CLOCK_NS) \
		+define+RSD_FUNCTIONAL_SIMULATION+RSD_VIVADO_SIMULATION+RSD_POST_SYNTHESIS_SIMULATION+RSD_SYNTHESIS_VIVADO \
		$(RSD_SRC_CFG) +incdir+$(CURDIR)+$(CURDIR)/SysDeps \
		-y $(VCS_XILINX)/unisims +libext+.v \
		$(VCS_NETLIST) $(VCS_XILINX)/glbl.v \
		$(abspath $(filter-out $(TEST_MODULES),$(TYPES)) $(TEST_MODULES)) \
		-o simv -l compile.log > /dev/null || { tail -n 50 compile.log; exit 1; }
	python3 $(VCS_SDF_TOOL) check $(POST_SYNTHESIS_WORK)
	timeout 12h python3 ../Tools/TestDriver/RunTest.py --simulator=post-synthesis-vcs $(POST_SYNTHESIS_WORK)
