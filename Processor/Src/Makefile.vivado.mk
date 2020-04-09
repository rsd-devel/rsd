# Specify test code and simulation cycles
MAX_TEST_CYCLES = 10000
SHOW_SERIAL_OUT = 1
ENABLE_PC_GOAL  = 1
TEST_CODE       = $(SOURCE_ROOT)Verification/TestCode/C/Fibonacci
DUMMY_DATA_FILE = $(SOURCE_ROOT)Verification/DummyData.hex


# Directory to run simulation
TOOLS_ROOT   = ../Tools/
PROJECT_WORK = ../Project/VivadoSim/work

SOURCE_ROOT  = ../Src/

# Specify a top module name for test
UNIT_NAME         = Main
# Simulation target
TEST_BENCH_MODULE = Test$(UNIT_NAME)

# Simulation tools
XVLOG = $(RSD_VIVADO_BIN)/xvlog
XELAB = $(RSD_VIVADO_BIN)/xelab
XSIM  = $(RSD_VIVADO_BIN)/xsim

# Convert a RSD log to a Kanata log.
KANATA_CONVERTER = python ../Tools/KanataConverter/KanataConverter.py
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


all: Makefiles/CoreSources.inc.mk
	mkdir $(PROJECT_WORK) -p
	# compile
	cd $(PROJECT_WORK) && $(XVLOG) -sv $(XVLOG_OPTIONS) -i $(SOURCE_ROOT) $(DEPS_RTL)
	@echo "==== Build Successful ===="

run:
	# elaboration
	cd $(PROJECT_WORK) && $(XELAB) -relax $(TEST_BENCH_MODULE)
	# simulation
	cd $(PROJECT_WORK) && $(XSIM) -runall $(XSIM_OPTIONS) $(TEST_BENCH_MODULE)

run-gui:
	# elaboration
	cd $(PROJECT_WORK) && $(XELAB) -relax $(TEST_BENCH_MODULE) -debug all
	# simulation
	cd $(PROJECT_WORK) && $(XSIM) -gui $(XSIM_OPTIONS) $(TEST_BENCH_MODULE)

kanata:
	$(KANATA_CONVERTER) $(PROJECT_WORK)/$(RSD_LOG_FILE_RTL) $(KANATA_LOG_FILE_RTL)

clean:
	rm -r -f $(PROJECT_WORK)


# -------------------------------
# Vivado synthesis related items are defined in this file
include Makefiles/Vivado.inc.mk

# -------------------------------
# Post synthesis simulation
#
VIVADO_PROJECT_ROOT = ../Project/Vivado/TargetBoards/Zedboard
VIVADO_POST_SYNTHESIS_PROJECT_ROOT = $(VIVADO_PROJECT_ROOT)/rsd_post_synthesis
VIVADO_POST_SYNTHESIS_PROJECT_FILE = $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT)/rsd_post_synthesis.xpr
POST_SYNTHESIS_MODULE = $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT)/rsd_post_synthesis.runs/synth_1/Main_Zynq_Wrapper.dcp
POST_SYNTHESIS_CODE_HEX = $(TEST_CODE)/code.hex
POST_SYNTHESIS_WORK = $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT)/rsd_post_synthesis.sim/sim_1/synth/func/xsim

RSD_LOG_FILE_POST_SYNTHESIS 	= $(POST_SYNTHESIS_WORK)/RSD-post-synthesis.log
KANATA_LOG_FILE_POST_SYNTHESIS 	= Kanata-post-synthesis.log

# Run and verify post-synthesis simulation
post-synthesis: post-synthesis-run
	diff $(POST_SYNTHESIS_WORK)/serial.out.txt $(TEST_CODE)/serial.ref.txt
	@echo "==== Post Synthesis Simulation Successful ===="

# Open post-synthesis project
post-synthesis-open: $(VIVADO_POST_SYNTHESIS_PROJECT_FILE)
	$(RSD_VIVADO_BIN)/vivado $(VIVADO_POST_SYNTHESIS_PROJECT_FILE) & 

# Run post-synthesis simulation
post-synthesis-run: $(POST_SYNTHESIS_MODULE)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode batch -source scripts/sim_post_synthesis.tcl

post-synthesis-kanata: #$(RSD_LOG_FILE_POST_SYNTHESIS)
	$(KANATA_CONVERTER) $(RSD_LOG_FILE_POST_SYNTHESIS) $(KANATA_LOG_FILE_POST_SYNTHESIS)

# Run post-synthesis simulation with GUI
post-synthesis-run-gui: $(POST_SYNTHESIS_MODULE)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode gui -source scripts/sim_post_synthesis.tcl

# Remove post-synthesis simulation related files
post-synthesis-clean:
	rm -f -r $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT)
	rm -f vivado*.jou
	rm -f vivado*.log
	rm -f vivado*.zip
	rm -f vivado*.str

# Do NOT use this command.
# This command is called automatically if needed.
post-synthesis-create:
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode batch -source scripts/create_post_synthesis_project.tcl

$(POST_SYNTHESIS_MODULE): $(VIVADO_POST_SYNTHESIS_PROJECT_FILE)
	cp $(TEST_CODE)/code.hex $(VIVADO_PROJECT_ROOT)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode batch -source scripts/run_post_synthesis.tcl
	touch $(POST_SYNTHESIS_MODULE) # Update timestamp to avoid re-synthesis

$(VIVADO_POST_SYNTHESIS_PROJECT_FILE):
	$(MAKE) post-synthesis-create || $(MAKE) post-synthesis-clean

$(RSD_LOG_FILE_POST_SYNTHESIS): post-synthesis-run

# -------------------------------
# Test related items are defined in this file
RUN_TEST = @python ../Tools/TestDriver/RunTest.py --simulator=vivadosim
RUN_TEST_OMIT_MSG = \
	@python ../Tools/TestDriver/RunTest.py -o --simulator=vivadosim
include Makefiles/TestCommands.inc.mk
