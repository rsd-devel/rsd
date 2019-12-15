# Specify test code and simulation cycles
MAX_TEST_CYCLES = 10000
SHOW_SERIAL_OUT = 1
ENABLE_PC_GOAL  = 1
TEST_CODE       = $(SOURCE_ROOT)Verification/TestCode/C/Fibonacci
DUMMY_DATA_FILE = $(SOURCE_ROOT)Verification/DummyData.hex


# Directory to run simulation
PROJECT_WORK = ../Project/VivadoSim/work

SOURCE_ROOT  = ../Src/

# Specify a top module name for test
UNIT_NAME         = Main
# Simulation target
TEST_BENCH_MODULE = Test$(UNIT_NAME)

# Simulation tools
XVLOG = xvlog
XELAB = xelab
XSIM  = xsim

# Convert a RSD log to a Kanata log.
KANATA_CONVERTER = python ../Tools/KanataConverter/KanataConverter.py
RSD_LOG_FILE_RTL = RSD.log
KANATA_LOG_FILE_RTL = Kanata.log


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

kanata:
	$(KANATA_CONVERTER) $(PROJECT_WORK)/$(RSD_LOG_FILE_RTL) $(KANATA_LOG_FILE_RTL)

clean:
	rm -r -f $(PROJECT_WORK)


# -------------------------------
# Test related items are defined in this file
RUN_TEST = @python ../Tools/TestDriver/RunTest.py --simulator=vivadosim
RUN_TEST_OMIT_MSG = \
	@python ../Tools/TestDriver/RunTest.py -o --simulator=vivadosim
include Makefiles/TestCommands.inc.mk
