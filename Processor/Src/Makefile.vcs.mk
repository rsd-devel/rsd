# Specify test code and simulation cycles
MAX_TEST_CYCLES = 500000
SHOW_SERIAL_OUT = 0
ENABLE_PC_GOAL = 1

TEST_CODE = Verification/TestCode/C/HelloWorld
# TEST_CODE = Verification/TestCode/Dhrystone/Dhrystone
# TEST_CODE = Verification/TestCode/Coremark/Coremark

SOURCE_ROOT  = ./
TOOLS_ROOT   = ../Tools/
PROJECT_WORK =  ../Project/VCS

# Convert a RSD log to a Kanata log.
KANATA_CONVERTER = python ../Tools/KanataConverter/KanataConverter.py
RSD_LOG_FILE_RTL = RSD.log
KANATA_LOG_FILE_RTL = Kanata.log


# Include core source code definition
include Makefiles/CoreSources.inc.mk

DEPS_RTL = \
	$(TYPES:%=$(SOURCE_ROOT)%) \
	$(MODULES:%=$(SOURCE_ROOT)%) \
	$(DEBUG_HELPERS:%=$(SOURCE_ROOT)%) \
	$(TEST_MODULES:%=$(SOURCE_ROOT)%) \

# RSD specific constants
RSD_VCS_DEFINITION = \
	+define+RSD_FUNCTIONAL_SIMULATION \
	+define+RSD_DISABLE_INITIAL \
	+define+RSD_VCS_SIMULATION \
	$(RSD_SRC_CFG) \

	# +define+RSD_DISABLE_HARDWARE_COUNTER \

VCS_OPTION = \
	+incdir+$(RSD_ROOT)/Processor/Src \
	-full64 \
	+v2k \
	-Mdirectory=$(PROJECT_WORK) \
	+nospecify \
	+notimingcheck \
	-o $(PROJECT_WORK)/simv


all: $(DEPS_RTL) Makefiles/CoreSources.inc.mk
	mkdir -p $(PROJECT_WORK)
	$(RSD_VCS_BIN) $(VCS_OPTION) \
	-sverilog $(DEPS_RTL) \
	-debug \
	$(RSD_VCS_DEFINITION)
	@echo "==== Build Successful ===="

run: $(PROJECT_WORK)/simv
	$(PROJECT_WORK)/simv \
		+MAX_TEST_CYCLES=$(MAX_TEST_CYCLES) \
		+TEST_CODE=$(TEST_CODE) \
		+ENABLE_PC_GOAL=$(ENABLE_PC_GOAL) \
		+SHOW_SERIAL_OUT=$(SHOW_SERIAL_OUT)

kanata:
	$(PROJECT_WORK)/simv \
		+MAX_TEST_CYCLES=$(MAX_TEST_CYCLES) \
		+TEST_CODE=$(TEST_CODE) \
		+ENABLE_PC_GOAL=$(ENABLE_PC_GOAL) \
		+SHOW_SERIAL_OUT=$(SHOW_SERIAL_OUT) \
		+RSD_LOG_FILE=$(RSD_LOG_FILE_RTL)
	$(KANATA_CONVERTER) $(RSD_LOG_FILE_RTL) $(KANATA_LOG_FILE_RTL)

clean:
	rm -rf $(PROJECT_WORK)

$(PROJECT_WORK)/simv: all


# -------------------------------
# Test related items are defined in this file
RUN_TEST = @python ../Tools/TestDriver/RunTest.py --simulator=vcs
RUN_TEST_OMIT_MSG = \
	@python ../Tools/TestDriver/RunTest.py -o --simulator=vcs 
include Makefiles/TestCommands.inc.mk
