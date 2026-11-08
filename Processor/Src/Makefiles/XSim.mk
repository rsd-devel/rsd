# XSim RTL backend, included by the main Makefile.
SIM_REQUIRED_ENV = RSD_VIVADO_BIN
SOURCE_ROOT = $(RSD_ROOT)/Processor/Src/
TEST_CODE = $(SOURCE_ROOT)Verification/TestCode/C/Fibonacci
PROJECT_WORK = ../Project/VivadoSim/work
UNIT_NAME = Main
TEST_BENCH_MODULE = Test$(UNIT_NAME)

# Simulation tools
XVLOG = $(call REQUIRE_ENV,RSD_VIVADO_BIN)$(RSD_VIVADO_BIN)/xvlog
XELAB = $(call REQUIRE_ENV,RSD_VIVADO_BIN)$(RSD_VIVADO_BIN)/xelab
XSIM  = $(call REQUIRE_ENV,RSD_VIVADO_BIN)$(RSD_VIVADO_BIN)/xsim

# Simulation options
XVLOG_OPTIONS = \
	-d RSD_FUNCTIONAL_SIMULATION \
	-d RSD_VIVADO_SIMULATION \
	$(patsubst +define+%,-d %,$(RSD_SRC_CFG)) \

XSIM_OPTIONS = $(addprefix -testplusarg ,$(SIM_PLUSARGS) RSD_LOG_FILE=$(RSD_LOG_FILE_RTL))

# Vivado sim may require the following additonal components:
# sudo apt install libncurses5 libtinfo5
all: $(CORE_TEMPLATE_FILES) Makefiles/CoreSources.inc.mk
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
	rm -f $(CORE_TEMPLATE_FILES)
