# Common RTL simulation and test entry point. Synthesis uses Makefiles/*.mk.
.DEFAULT_GOAL := all
SOURCE_DIRECTORY := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))

# Resolve the root symlink and keep all existing paths relative to Src.
ifneq ($(realpath $(CURDIR))/,$(SOURCE_DIRECTORY))
.DEFAULT_GOAL := _forward
.PHONY: _forward $(MAKECMDGOALS)
# Forward goals together, preserving variables and the jobserver.
# Recursive make also exposes the child database to standard shell completion.
$(MAKECMDGOALS): _forward ;
_forward:
	$(MAKE) -C "$(SOURCE_DIRECTORY)" $(MAKECMDGOALS)

else

SIM ?= verilator
ifneq ($(words $(SIM)),1)
$(error Select one SIM: verilator, modelsim or xsim)
endif
ifeq ($(filter verilator modelsim xsim,$(SIM)),)
$(error Unsupported SIM '$(SIM)'; use verilator, modelsim or xsim)
endif

include Makefiles/Build.inc.mk

# Manual simulation limits are independent of each test's cfg.xml.
MAX_TEST_INSTRUCTIONS = 100000
MAX_NO_COMMIT_CYCLES = 500
MAX_TEST_CYCLES = 0
SHOW_SERIAL_OUT = 1
ENABLE_PC_GOAL = 1
SIM_PLUSARGS = \
	MAX_TEST_INSTRUCTIONS=$(MAX_TEST_INSTRUCTIONS) \
	MAX_NO_COMMIT_CYCLES=$(MAX_NO_COMMIT_CYCLES) \
	MAX_TEST_CYCLES=$(MAX_TEST_CYCLES) \
	TEST_CODE=$(TEST_CODE) \
	ENABLE_PC_GOAL=$(ENABLE_PC_GOAL) \
	SHOW_SERIAL_OUT=$(SHOW_SERIAL_OUT)

KANATA_CONVERTER = python3 $(TOOLS_ROOT)KanataConverter/KanataConverter.py
RSD_LOG_FILE_RTL = RSD.log
KANATA_LOG_FILE_RTL = Kanata.log
DEBUG_LOG_FILE_RTL = Debug.log
REG_CSV_FILE = Register.csv

# TestDriver retains its existing name for the XSim backend.
TEST_SIMULATOR = $(if $(filter xsim,$(SIM)),vivadosim,$(SIM))
RUN_TEST = @$(call REQUIRE_ENV,$(SIM_REQUIRED_ENV))python3 $(TOOLS_ROOT)TestDriver/RunTest.py --simulator=$(TEST_SIMULATOR)
RUN_TEST_OMIT_MSG = $(RUN_TEST) -o

ifeq ($(SIM),verilator)
include Makefiles/Verilator.mk
else ifeq ($(SIM),modelsim)
include Makefiles/ModelSim.mk
else
include Makefiles/XSim.mk
endif
include Makefiles/TestCommands.inc.mk

# Units follow SIM; UNIT_SIM can select them independently of the core.
UNIT_SIM ?= $(SIM)
UNIT_PROJECT_WORK ?= $(if $(filter command line,$(origin PROJECT_WORK)),$(PROJECT_WORK),$(if $(filter modelsim,$(UNIT_SIM)),../Project/ModelSim,../Project/Verilator/UnitTest))
UNIT_TESTS = \
	InitializedBlockRAM \
	BlockDualPortRAM \
	DistributedDualPortRAM \
	DistributedMultiPortRAM \
	MultiBankRAM \
	MultiWidthQueuePointer \
	MultiWidthFreeList \
	Divider \
	MulDivUnit \
	Memory \
	ICache \
	DCache \
	DecodeStage \
	InterruptController
ifneq ($(findstring +define+RSD_MARCH_FP_PIPE,$(RSD_SRC_CFG)),)
UNIT_TESTS += FPDivSqrtUnit
endif
UNIT_TEST_TARGETS = $(UNIT_TESTS:%=test-unit-%)

.PHONY: test-unit $(UNIT_TEST_TARGETS)
test-unit: $(UNIT_TEST_TARGETS)
	@echo "==== Test Successful (test-unit) ===="

# Generate shared RTL before starting unit submakes, including parallel runs.
$(UNIT_TEST_TARGETS): test-unit-%: $(CORE_TEMPLATE_FILES)
	$(MAKE) -C Verification/UnitTest/$* test UNIT_SIM="$(UNIT_SIM)" PROJECT_WORK="$(abspath $(UNIT_PROJECT_WORK))"
	@echo "==== Test Successful (test-unit-$*) ===="

endif
