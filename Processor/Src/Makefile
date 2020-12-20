# Specify test code and simulation cycles
MAX_TEST_CYCLES = 50000
SHOW_SERIAL_OUT = 1
ENABLE_PC_GOAL = 1
#TEST_CODE = Verification/TestCode/Asm/CacheFlush
TEST_CODE = Verification/TestCode/C/HelloWorld

SOURCE_ROOT  = ./
TOOLS_ROOT   = ../Tools/
PROJECT_WORK =  ../Project/ModelSim
TEST_CODE_HEX = $(TEST_CODE)/code.hex

# Specify a top module name for test
UNIT_NAME         = Main

# Library name and a top level module（simulation target）
TEST_BENCH_MODULE = Test$(UNIT_NAME)
TOP_MODULE        = $(UNIT_NAME)

# Output files
RSD_LOG_FILE_RTL       			= RSD.log
KANATA_LOG_FILE_RTL       		= Kanata.log
DEBUG_LOG_FILE_RTL       		= Debug.log
REG_CSV_FILE 					= Register.csv


# Include core source code definition
include Makefiles/CoreSources.inc.mk

# Additional files
TYPES += \
	# Verification/Dumper.sv 
MODULES += \

# VLOG_OPTIONS is referenced in Makefile.inc.
# VLOG_OPTIONS is used in all simulation/post synthesis simulation 
VLOG_OPTIONS = \
	$(RSD_SRC_CFG) \

# Simulation options
VSIM_OPTIONS = \
	+MAX_TEST_CYCLES=$(MAX_TEST_CYCLES) \
	+TEST_CODE=$(TEST_CODE) \
	+ENABLE_PC_GOAL=$(ENABLE_PC_GOAL) \
	+SHOW_SERIAL_OUT=$(SHOW_SERIAL_OUT) \
	-suppress 8233 \
	+autofindloop \

VSIM_OPTIONS_RTL = \
	+RSD_LOG_FILE=$(RSD_LOG_FILE_RTL) \
	+DEBUG_LOG_FILE=$(DEBUG_LOG_FILE_RTL) \

VSIM_OPTIONS_DUMP = \
	+REG_CSV_FILE=$(REG_CSV_FILE) \



# -------------------------------
# Commands
#

# Include basic command definitions.
include Makefile.inc

# Convert a RSD log to a Kanata log.
KANATA_CONVERTER = python ../Tools/KanataConverter/KanataConverter.py

kanata: rtl-kanata

rtl-kanata: rtl-run
	$(KANATA_CONVERTER) $(RSD_LOG_FILE_RTL) $(KANATA_LOG_FILE_RTL)

# -------------------------------
# Test related items are defined in this file
RUN_TEST = python ../Tools/TestDriver/RunTest.py
RUN_TEST_OMIT_MSG = python ../Tools/TestDriver/RunTest.py -o
include Makefiles/TestCommands.inc.mk

# -------------------------------
# Dump : Run test and dump values of register files for each cycle.
#        This is only for pre-translate simulation.
dump:
	$(VSIM) $(TARGET_MODULE_RTL) $(VSIM_OPTIONS) $(VSIM_OPTIONS_RTL) $(VSIM_OPTIONS_DUMP) -do "run -all"
