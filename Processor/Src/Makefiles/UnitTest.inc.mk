# Shared unit-test entry points. SIM follows the core simulator by default.
.DEFAULT_GOAL := all
# Generate address types and constants needed by individual unit tests.
include $(SOURCE_ROOT)Makefiles/GenerateMemoryMap.inc.mk
$(SOURCE_ROOT)Memory/MemoryMapTypes.sv: $(RSD_MEMORY_MAP_OUTPUTS)
SIM ?= verilator
UNIT_SIM ?= $(SIM)

ifeq ($(UNIT_SIM),modelsim)
PROJECT_WORK ?= $(SOURCE_ROOT)../Project/ModelSim
include $(SOURCE_ROOT)Makefiles/ModelSim.inc.mk
else ifeq ($(UNIT_SIM),verilator)
PROJECT_WORK ?= $(SOURCE_ROOT)../Project/Verilator/UnitTest
LIBRARY_WORK_RTL = $(PROJECT_WORK)/$(UNIT_NAME)
TOP_MODULE = $(TEST_BENCH_MODULE)
# Keep each test's existing include paths and configuration defines.
RSD_VERILATOR_DEFINITION = +define+RSD_FUNCTIONAL_SIMULATION $(filter +define+% +incdir+%,$(VLOG_OPTIONS))
include $(SOURCE_ROOT)Makefiles/Verilator.inc.mk
# Small unit testbenches do not all declare a timescale.
VERILATOR_DISABLED_WARNING += -Wno-TIMESCALEMOD
DEPS_RTL = $(addprefix $(SOURCE_ROOT),$(TYPES) $(MODULES) $(TEST_MODULES))

.PHONY: all default rtl test run rtl-run clean rtl-clean
all default: rtl
# Re-elaborate to reflect command-line configuration and included headers.
rtl: $(DEPS_RTL) $(MAKEFILE_LIST)
	mkdir -p $(LIBRARY_WORK_RTL)
	$(VERILATOR_BIN) $(VERILATOR_OPTION) $(DEPS_RTL)
	$(MAKE) -C $(LIBRARY_WORK_RTL) -f $(VERILATED_TOP_MODULE_NAME).mk

# Run from the test directory so relative data files resolve identically.
test run rtl-run: rtl
	$(LIBRARY_WORK_RTL)/$(VERILATED_TOP_MODULE_NAME)

clean rtl-clean:
	rm -rf $(LIBRARY_WORK_RTL)
else
$(error Unsupported UNIT_SIM '$(UNIT_SIM)'; use verilator or modelsim)
endif
