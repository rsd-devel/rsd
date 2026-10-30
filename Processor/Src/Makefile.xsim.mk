# RTL simulation with XSim (Vivado Simulator).

# Specify test code and progress limits (independent of cfg.xml)
MAX_TEST_INSTRUCTIONS = 100000
MAX_NO_COMMIT_CYCLES = 500
MAX_TEST_CYCLES = 0
SHOW_SERIAL_OUT = 1
ENABLE_PC_GOAL  = 1
TEST_CODE       = $(SOURCE_ROOT)Verification/TestCode/C/Fibonacci


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

MAKEFILE = Makefile.xsim.mk

# Include core source code definition
include Makefiles/CoreSources.inc.mk

DEPS_RTL = \
	$(TYPES:%=$(SOURCE_ROOT)%) \
	$(MODULES:%=$(SOURCE_ROOT)%) \
	$(TEST_MODULES:%=$(SOURCE_ROOT)%) \

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
# Test related items are defined in this file
RUN_TEST = @python3 ../Tools/TestDriver/RunTest.py --simulator=vivadosim
RUN_TEST_OMIT_MSG = \
	@python3 ../Tools/TestDriver/RunTest.py -o --simulator=vivadosim
include Makefiles/TestCommands.inc.mk
