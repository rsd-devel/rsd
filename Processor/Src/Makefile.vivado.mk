
# Makefile for synthesizing on Vivado only (not using Synplify netlist)

# Specify test code and progress limits (independent of cfg.xml)
MAX_TEST_INSTRUCTIONS = 100000
MAX_NO_COMMIT_CYCLES = 500
MAX_TEST_CYCLES = 0
SHOW_SERIAL_OUT = 1
ENABLE_PC_GOAL  = 1
TEST_CODE       = $(SOURCE_ROOT)Verification/TestCode/C/Fibonacci
DUMMY_DATA_FILE = $(SOURCE_ROOT)Verification/DummyData.hex


SOURCE_ROOT  = $(RSD_ROOT)/Processor/Src/
# Directory to run simulation
PROJECT_WORK = ../Project/VivadoSim/work
TOOLS_ROOT   = ../Tools/

# Specify a top module name for test
UNIT_NAME         = Main
# Simulation target
TEST_BENCH_MODULE = Test$(UNIT_NAME)

# Simulation tools
XVLOG = $(RSD_VIVADO_BIN)/xvlog
XELAB = $(RSD_VIVADO_BIN)/xelab
XSIM  = $(RSD_VIVADO_BIN)/xsim

# Convert a RSD log to a Kanata log.
KANATA_CONVERTER = python3 ../Tools/KanataConverter/KanataConverter.py
RSD_LOG_FILE_RTL = RSD.log
KANATA_LOG_FILE_RTL = Kanata.log

MAKEFILE = Makefile.vivado.mk
MAKE = make -f $(MAKEFILE)

# Include core source code definition
include Makefiles/CoreSources.inc.mk

DEPS_RTL = \
	$(TYPES:%=$(SOURCE_ROOT)%) \
	$(MODULES:%=$(SOURCE_ROOT)%) \
	$(TEST_MODULES:%=$(SOURCE_ROOT)%) \

# Additional files
TYPES += Verification/Dumper.sv


# Simulation options
XVLOG_OPTIONS = \
	-d RSD_FUNCTIONAL_SIMULATION \
	-d RSD_VIVADO_SIMULATION \
	$(patsubst +define+%,-d %,$(RSD_SRC_CFG)) \

XSIM_OPTIONS = \
	-testplusarg MAX_TEST_INSTRUCTIONS=$(MAX_TEST_INSTRUCTIONS) \
	-testplusarg MAX_NO_COMMIT_CYCLES=$(MAX_NO_COMMIT_CYCLES) \
	-testplusarg MAX_TEST_CYCLES=$(MAX_TEST_CYCLES) \
	-testplusarg TEST_CODE=$(TEST_CODE) \
	-testplusarg DUMMY_DATA_FILE=$(DUMMY_DATA_FILE) \
	-testplusarg ENABLE_PC_GOAL=$(ENABLE_PC_GOAL) \
	-testplusarg SHOW_SERIAL_OUT=$(SHOW_SERIAL_OUT) \
	-testplusarg RSD_LOG_FILE=$(RSD_LOG_FILE_RTL) \

# Vivado sim may require the following additonal components:
# sudo apt install libncurses5 libtinfo5
all: $(CORE_TEMPLATE_FILES) Makefiles/CoreSources.inc.mk
	mkdir $(PROJECT_WORK) -p
	# compile
	cd $(PROJECT_WORK) && $(XVLOG) -sv $(XVLOG_OPTIONS) -i $(SOURCE_ROOT) $(DEPS_RTL)
	# elaboration
	cd $(PROJECT_WORK) && $(XELAB) -relax $(TEST_BENCH_MODULE)
	@echo "==== Build Successful ===="

$(CORE_TEMPLATE_FILES): $(wildcard Generator/*.py) default.yml $(CORE_TEMPLATE_FILES:.sv=.template.sv)
	python3 Generator/cpu_generator.py --rsd-root $(RSD_ROOT)

run:
	# simulation
	cd $(PROJECT_WORK) && $(XSIM) -runall $(XSIM_OPTIONS) $(TEST_BENCH_MODULE)

run-gui:
	# simulation
	cd $(PROJECT_WORK) && $(XSIM) -gui $(XSIM_OPTIONS) $(TEST_BENCH_MODULE)

kanata:
	$(KANATA_CONVERTER) $(PROJECT_WORK)/$(RSD_LOG_FILE_RTL) $(KANATA_LOG_FILE_RTL)

clean:
	rm -r -f $(PROJECT_WORK)
	rm -f $(CORE_TEMPLATE_FILES)

# -------------------------------
# Synthesis
# This procedure uses Vivado only.
#   1. Create Vivado Custom IP of RSD by using our script
#   2. Synthesize RSD using Vivado
#

# -------------------------------
# Vivado synthesis related items are defined in this file
include Makefiles/Vivado.inc.mk

VIVADO_PROJECT_FILE_DEPS = \
	Makefiles/CoreSources.inc.mk \
	$(TOOLS_ROOT)/XilinxTools/IP_Generator.py \
	$(TOOLS_ROOT)/XilinxTools/ip_template.xml \
	$(VIVADO_PROJECT_ROOT)/scripts/synthesis/create_project.tcl

# Create Vivado project file for synthesis
$(VIVADO_PROJECT_FILE): $(VIVADO_PROJECT_FILE_DEPS)
	python3 $(TOOLS_ROOT)/XilinxTools/IP_Generator.py $(TARGET_BOARD) # Generate Xilinx IP of RSD
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode batch -source scripts/synthesis/create_project.tcl

# -------------------------------
# Project-based timing and post-implementation simulation.
# Functional post-synthesis tests use the XSim flow below.
VIVADO_PROJECT_ROOT = ../Project/Vivado/TargetBoards/Zedboard
VIVADO_POST_SYNTHESIS_PROJECT_ROOT = $(VIVADO_PROJECT_ROOT)/rsd_post_synthesis
VIVADO_POST_SYNTHESIS_PROJECT_FILE = $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT)/rsd_post_synthesis.xpr

POST_SYNTHESIS_MODULE = $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT)/rsd_post_synthesis.runs/synth_1/Main_Zynq_Wrapper.dcp
POST_IMPLEMENTATION_MODULE = $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT)/rsd_post_synthesis.runs/impl_1/Main_Zynq_Wrapper_routed.dcp

export RSD_POST_SYNTHESIS_DEFINES = $(patsubst +define+%,%,$(RSD_SRC_CFG))

POST_SYNTHESIS_SIMULATION_ROOT = $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT)/rsd_post_synthesis.sim/sim_1
POST_SYNTHESIS_TIMING_WORK = $(POST_SYNTHESIS_SIMULATION_ROOT)/synth/timing/xsim
POST_IMPLEMENTATION_FUNCTIONAL_WORK = $(POST_SYNTHESIS_SIMULATION_ROOT)/impl/func/xsim
POST_IMPLEMENTATION_TIMING_WORK = $(POST_SYNTHESIS_SIMULATION_ROOT)/impl/timing/xsim

RSD_LOG_FILE_POST_SYNTHESIS_TIMING      = $(POST_SYNTHESIS_TIMING_WORK)/RSD-post-synthesis.log
RSD_LOG_FILE_POST_IMPLEMENTATION        = $(POST_IMPLEMENTATION_FUNCTIONAL_WORK)/RSD-post-synthesis.log
RSD_LOG_FILE_POST_IMPLEMENTATION_TIMING = $(POST_IMPLEMENTATION_TIMING_WORK)/RSD-post-synthesis.log

KANATA_LOG_FILE_POST_SYNTHESIS_TIMING      = $(POST_SYNTHESIS_TIMING_WORK)/Kanata-post-synthesis.log
KANATA_LOG_FILE_POST_IMPLEMENTATION        = $(POST_IMPLEMENTATION_FUNCTIONAL_WORK)/Kanata-post-synthesis.log
KANATA_LOG_FILE_POST_IMPLEMENTATION_TIMING = $(POST_IMPLEMENTATION_TIMING_WORK)/Kanata-post-synthesis.log

# Run and verify timing and post-implementation simulation.
post-synthesis-timing: post-synthesis-timing-run
	diff $(POST_SYNTHESIS_TIMING_WORK)/serial.out.txt $(TEST_CODE)/serial.ref.txt
	@echo "==== Post Synthesis Timing Simulation Successful ===="

post-implementation: post-implementation-run
	diff $(POST_IMPLEMENTATION_FUNCTIONAL_WORK)/serial.out.txt $(TEST_CODE)/serial.ref.txt
	@echo "==== Post Implementation Functional Simulation Successful ===="

post-implementation-timing: post-implementation-timing-run
	diff $(POST_IMPLEMENTATION_TIMING_WORK)/serial.out.txt $(TEST_CODE)/serial.ref.txt
	@echo "==== Post Implementation Timing Simulation Successful ===="

# Open post-synthesis project
post-synthesis-open: $(VIVADO_POST_SYNTHESIS_PROJECT_FILE)
	$(RSD_VIVADO_BIN)/vivado $(VIVADO_POST_SYNTHESIS_PROJECT_FILE) & 

# Run post-synthesis simulation
post-synthesis-timing-run: $(RSD_LOG_FILE_POST_SYNTHESIS_TIMING)
post-implementation-run: $(RSD_LOG_FILE_POST_IMPLEMENTATION)
post-implementation-timing-run: $(RSD_LOG_FILE_POST_IMPLEMENTATION_TIMING)

# Run post-synthesis simulation with GUI
post-synthesis-timing-run-gui: $(POST_SYNTHESIS_MODULE)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode gui -source scripts/post_synthesis/sim_post_synthesis.tcl \
		-tclargs post-synthesis timing

post-implementation-run-gui: $(POST_IMPLEMENTATION_MODULE)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode gui -source scripts/post_synthesis/sim_post_synthesis.tcl \
		-tclargs post-implementation functional

post-implementation-timing-run-gui: $(POST_IMPLEMENTATION_MODULE)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode gui -source scripts/post_synthesis/sim_post_synthesis.tcl \
		-tclargs post-implementation timing


# Generate post-synthesis Kanata log file
post-synthesis-timing-kanata: $(KANATA_LOG_FILE_POST_SYNTHESIS_TIMING)
post-implementation-kanata: $(KANATA_LOG_FILE_POST_IMPLEMENTATION)
post-implementation-timing-kanata: $(KANATA_LOG_FILE_POST_IMPLEMENTATION_TIMING)


# Remove post-synthesis simulation related files
.PHONY: post-synthesis-clean
post-synthesis-clean:
	rm -rf ../Project/PostSynthesis/vivado
	rm -f -r $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT)
	rm -f vivado*.jou
	rm -f vivado*.log
	rm -f vivado*.zip
	rm -f vivado*.str

# Do NOT use these commands.
# These commands are called automatically if needed.
post-synthesis-create:
	python3 $(TOOLS_ROOT)/XilinxTools/VivadoProjectCreator.py $(TARGET_BOARD)
	cp $(TEST_CODE)/code.hex $(VIVADO_PROJECT_ROOT)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode batch -source scripts/post_synthesis/create_project_for_vivadosim.tcl

$(POST_SYNTHESIS_MODULE): $(VIVADO_POST_SYNTHESIS_PROJECT_FILE)
	cp $(TEST_CODE)/code.hex $(VIVADO_PROJECT_ROOT)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode batch -source scripts/post_synthesis/run_synthesis.tcl
	test -s $(POST_SYNTHESIS_MODULE)
	touch $(POST_SYNTHESIS_MODULE) # Update timestamp to avoid re-synthesis

$(POST_IMPLEMENTATION_MODULE): $(POST_SYNTHESIS_MODULE)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode batch -source scripts/post_synthesis/run_implementation.tcl
	test -s $(POST_IMPLEMENTATION_MODULE)
	touch $(POST_IMPLEMENTATION_MODULE) # Update timestamp to avoid re-synthesis

$(VIVADO_POST_SYNTHESIS_PROJECT_FILE):
	$(MAKE) post-synthesis-create || { rm -rf $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT); exit 1; }

$(RSD_LOG_FILE_POST_SYNTHESIS_TIMING): $(POST_SYNTHESIS_MODULE)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode batch -source scripts/post_synthesis/sim_post_synthesis.tcl \
		-tclargs post-synthesis timing

$(RSD_LOG_FILE_POST_IMPLEMENTATION): $(POST_IMPLEMENTATION_MODULE)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode batch -source scripts/post_synthesis/sim_post_synthesis.tcl \
		-tclargs post-implementation functional

$(RSD_LOG_FILE_POST_IMPLEMENTATION_TIMING): $(POST_IMPLEMENTATION_MODULE)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode batch -source scripts/post_synthesis/sim_post_synthesis.tcl \
		-tclargs post-implementation timing

$(KANATA_LOG_FILE_POST_SYNTHESIS_TIMING): $(RSD_LOG_FILE_POST_SYNTHESIS_TIMING)
	$(KANATA_CONVERTER) $< $@

$(KANATA_LOG_FILE_POST_IMPLEMENTATION): $(RSD_LOG_FILE_POST_IMPLEMENTATION)
	$(KANATA_CONVERTER) $< $@

$(KANATA_LOG_FILE_POST_IMPLEMENTATION_TIMING): $(RSD_LOG_FILE_POST_IMPLEMENTATION_TIMING)
	$(KANATA_CONVERTER) $< $@

# -------------------------------
# Test related items are defined in this file
RUN_TEST = @python3 ../Tools/TestDriver/RunTest.py --simulator=vivadosim
RUN_TEST_OMIT_MSG = \
	@python3 ../Tools/TestDriver/RunTest.py -o --simulator=vivadosim
include Makefiles/TestCommands.inc.mk

# Functional simulation of a synthesized Zedboard core using XSim.
# Build TEST_CODE first; each invocation synthesizes its HEX into internal RAM.
POST_SYNTHESIS_WORK = $(abspath ../Project/PostSynthesis/vivado/$(notdir $(TEST_CODE)))

export RSD_VIVADO_BIN
export RSD_POST_SYNTHESIS_SRC = $(CURDIR)
export RSD_POST_SYNTHESIS_SOURCES = $(abspath $(filter-out $(TEST_MODULES),$(TYPES)) $(MODULES))
POST_SYNTHESIS_SCRIPT = $(abspath ../Tools/XilinxTools/PostSynthesisVivado.tcl)
POST_SYNTHESIS_XILINX = $(abspath $(RSD_VIVADO_BIN)/../data/verilog/src)

.PHONY: test-post-synthesis post-synthesis-build
# These targets need UART output; command-line TEST_CODE overrides this default.
test-post-synthesis post-synthesis-build: TEST_CODE = Verification/TestCode/C/HelloWorld
post-synthesis-build: $(CORE_TEMPLATE_FILES)
	test -s $(TEST_CODE)/code.hex && test -s $(TEST_CODE)/serial.ref.txt
	test -x $(RSD_VIVADO_BIN)/xsim
	mkdir -p $(POST_SYNTHESIS_WORK)
	cp $(TEST_CODE)/code.hex $(TEST_CODE)/cfg.xml $(TEST_CODE)/serial.ref.txt $(POST_SYNTHESIS_WORK)/
	rm -f $(POST_SYNTHESIS_WORK)/netlist.v
	cd $(POST_SYNTHESIS_WORK) && $(RSD_VIVADO_BIN)/vivado -mode batch -source $(POST_SYNTHESIS_SCRIPT)
	test -s $(POST_SYNTHESIS_WORK)/netlist.v

test-post-synthesis: post-synthesis-build
	cd $(POST_SYNTHESIS_WORK) && $(RSD_VIVADO_BIN)/xvlog -sv \
		-i $(CURDIR) $(patsubst +define+%,-d %,$(RSD_SRC_CFG)) \
		-d RSD_FUNCTIONAL_SIMULATION -d RSD_POST_SYNTHESIS_SIMULATION \
		-d RSD_SYNTHESIS_VIVADO \
		$(abspath $(filter-out $(TEST_MODULES),$(TYPES)) $(TEST_MODULES))
	cd $(POST_SYNTHESIS_WORK) && $(RSD_VIVADO_BIN)/xvlog netlist.v $(POST_SYNTHESIS_XILINX)/glbl.v
	cd $(POST_SYNTHESIS_WORK) && $(RSD_VIVADO_BIN)/xelab -relax -timescale 1ns/1ps -L unisims_ver \
		-s post_synthesis work.TestMain work.glbl
	timeout 12h python3 ../Tools/TestDriver/RunTest.py --simulator=post-synthesis $(POST_SYNTHESIS_WORK)

# Keep the existing entry points on the same XSim test flow.
.PHONY: post-synthesis post-synthesis-run
post-synthesis post-synthesis-run: test-post-synthesis
