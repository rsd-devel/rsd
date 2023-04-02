
# Makefile for synthesizing on Vivado only (not using Synplify netlist)

# Specify test code and simulation cycles
MAX_TEST_CYCLES = 10000
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

XSIM_OPTIONS = \
	-testplusarg MAX_TEST_CYCLES=$(MAX_TEST_CYCLES) \
	-testplusarg TEST_CODE=$(TEST_CODE) \
	-testplusarg DUMMY_DATA_FILE=$(DUMMY_DATA_FILE) \
	-testplusarg ENABLE_PC_GOAL=$(ENABLE_PC_GOAL) \
	-testplusarg SHOW_SERIAL_OUT=$(SHOW_SERIAL_OUT) \
	-testplusarg RSD_LOG_FILE=$(RSD_LOG_FILE_RTL) \

# Vivado sim may require the following additonal components:
# sudo apt install libncurses5 libtinfo5
all: Makefiles/CoreSources.inc.mk
	mkdir $(PROJECT_WORK) -p
	# compile
	cd $(PROJECT_WORK) && $(XVLOG) -sv $(XVLOG_OPTIONS) -i $(SOURCE_ROOT) $(DEPS_RTL)
	# elaboration
	cd $(PROJECT_WORK) && $(XELAB) -relax $(TEST_BENCH_MODULE)
	@echo "==== Build Successful ===="

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
# Post synthesis simulation
#
# -------------------------------
# Synthesis
# This procedure uses Vivado only.
VIVADO_PROJECT_ROOT = ../Project/Vivado/TargetBoards/Zedboard
VIVADO_POST_SYNTHESIS_PROJECT_ROOT = $(VIVADO_PROJECT_ROOT)/rsd_post_synthesis
VIVADO_POST_SYNTHESIS_PROJECT_FILE = $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT)/rsd_post_synthesis.xpr
POST_SYNTHESIS_CODE_HEX = $(TEST_CODE)/code.hex

POST_SYNTHESIS_MODULE = $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT)/rsd_post_synthesis.runs/synth_1/Main_Zynq_Wrapper.dcp
POST_IMPLEMENTATION_MODULE = $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT)/rsd_post_synthesis.runs/impl_1/Main_Zynq_Wrapper.dcp

POST_SYNTHESIS_SIMULATION_ROOT = $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT)/rsd_post_synthesis.sim/sim_1
POST_SYNTHESIS_FUNCTIONAL_WORK = $(POST_SYNTHESIS_SIMULATION_ROOT)/synth/func/xsim
POST_SYNTHESIS_TIMING_WORK = $(POST_SYNTHESIS_SIMULATION_ROOT)/synth/timing/xsim
POST_IMPLEMENTATION_FUNCTIONAL_WORK = $(POST_SYNTHESIS_SIMULATION_ROOT)/impl/func/xsim
POST_IMPLEMENTATION_TIMING_WORK = $(POST_SYNTHESIS_SIMULATION_ROOT)/impl/timing/xsim

RSD_LOG_FILE_POST_SYNTHESIS 	        = $(POST_SYNTHESIS_FUNCTIONAL_WORK)/RSD-post-synthesis.log
RSD_LOG_FILE_POST_SYNTHESIS_TIMING      = $(POST_SYNTHESIS_TIMING_WORK)/RSD-post-synthesis.log
RSD_LOG_FILE_POST_IMPLEMENTATION        = $(POST_IMPLEMENTATION_FUNCTIONAL_WORK)/RSD-post-synthesis.log
RSD_LOG_FILE_POST_IMPLEMENTATION_TIMING = $(POST_IMPLEMENTATION_TIMING_WORK)/RSD-post-synthesis.log

KANATA_LOG_FILE_POST_SYNTHESIS 	           = $(POST_SYNTHESIS_FUNCTIONAL_WORK)/Kanata-post-synthesis.log
KANATA_LOG_FILE_POST_SYNTHESIS_TIMING      = $(POST_SYNTHESIS_TIMING_WORK)/Kanata-post-synthesis.log
KANATA_LOG_FILE_POST_IMPLEMENTATION        = $(POST_IMPLEMENTATION_FUNCTIONAL_WORK)/Kanata-post-synthesis.log
KANATA_LOG_FILE_POST_IMPLEMENTATION_TIMING = $(POST_IMPLEMENTATION_TIMING_WORK)/Kanata-post-synthesis.log

# Run and verify post-synthesis simulation
post-synthesis: post-synthesis-run
	diff $(POST_SYNTHESIS_FUNCTIONAL_WORK)/serial.out.txt $(TEST_CODE)/serial.ref.txt
	@echo "==== Post Synthesis Functional Simulation Successful ===="

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
post-synthesis-run: $(RSD_LOG_FILE_POST_SYNTHESIS)
post-synthesis-timing-run: $(RSD_LOG_FILE_POST_SYNTHESIS_TIMING)
post-implementation-run: $(RSD_LOG_FILE_POST_IMPLEMENTATION)
post-implementation-timing-run: $(RSD_LOG_FILE_POST_IMPLEMENTATION_TIMING)

# Run post-synthesis simulation with GUI
post-synthesis-run-gui: $(POST_SYNTHESIS_MODULE)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode gui -source scripts/post_synthesis/sim_post_synthesis.tcl \
		-tclargs post-synthesis functional

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
post-synthesis-kanata: $(KANATA_LOG_FILE_POST_SYNTHESIS)
post-synthesis-timing-kanata: $(KANATA_LOG_FILE_POST_SYNTHESIS_TIMING)
post-implementation-kanata: $(KANATA_LOG_FILE_POST_IMPLEMENTATION)
post-implementation-timing-kanata: $(KANATA_LOG_FILE_POST_IMPLEMENTATION_TIMING)


# Remove post-synthesis simulation related files
post-synthesis-clean:
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
	touch $(POST_SYNTHESIS_MODULE) # Update timestamp to avoid re-synthesis

$(POST_IMPLEMENTATION_MODULE): $(VIVADO_POST_SYNTHESIS_PROJECT_FILE)
	cp $(TEST_CODE)/code.hex $(VIVADO_PROJECT_ROOT)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode batch -source scripts/post_synthesis/run_implementation.tcl
	touch $(POST_IMPLEMENTATION_MODULE) # Update timestamp to avoid re-synthesis

$(VIVADO_POST_SYNTHESIS_PROJECT_FILE):
	$(MAKE) post-synthesis-create || $(MAKE) post-synthesis-clean

$(RSD_LOG_FILE_POST_SYNTHESIS): $(POST_SYNTHESIS_MODULE)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode batch -source scripts/post_synthesis/sim_post_synthesis.tcl \
		-tclargs post-synthesis functional

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

$(KANATA_LOG_FILE_POST_SYNTHESIS): $(RSD_LOG_FILE_POST_SYNTHESIS)
	$(KANATA_CONVERTER) $(RSD_LOG_FILE_POST_SYNTHESIS) $(KANATA_LOG_FILE_POST_SYNTHESIS)

$(KANATA_LOG_FILE_POST_SYNTHESIS_TIMING): $(RSD_LOG_FILE_POST_SYNTHESIS_TIMING)
	$(KANATA_CONVERTER) $(RSD_LOG_FILE_POST_SYNTHESIS) $(KANATA_LOG_FILE_POST_SYNTHESIS_TIMING)

$(KANATA_LOG_FILE_POST_IMPLEMENTATION): $(RSD_LOG_FILE_POST_IMPLEMENTATION)
	$(KANATA_CONVERTER) $(RSD_LOG_FILE_POST_SYNTHESIS) $(KANATA_LOG_FILE_POST_IMPLEMENTATION)

$(KANATA_LOG_FILE_POST_IMPLEMENTATION_TIMING): $(RSD_LOG_FILE_POST_IMPLEMENTATION_TIMING)
	$(KANATA_CONVERTER) $(RSD_LOG_FILE_POST_SYNTHESIS) $(KANATA_LOG_FILE_POST_IMPLEMENTATION_TIMING)

# -------------------------------
# Test related items are defined in this file
RUN_TEST = @python3 ../Tools/TestDriver/RunTest.py --simulator=vivadosim
RUN_TEST_OMIT_MSG = \
	@python3 ../Tools/TestDriver/RunTest.py -o --simulator=vivadosim
include Makefiles/TestCommands.inc.mk
