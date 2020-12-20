# Specify test code and simulation cycles
MAX_TEST_CYCLES = 10000
SHOW_SERIAL_OUT = 1
ENABLE_PC_GOAL = 1
#TEST_CODE = Verification/TestCode/Asm/ControlTransfer
TEST_CODE = Verification/TestCode/C/HelloWorld

ifndef RSD_VERILATOR_BIN
VERILATOR_BIN = verilator
else
VERILATOR_BIN = $(RSD_VERILATOR_BIN)
endif


SOURCE_ROOT  = ./
TOOLS_ROOT   = ../Tools/
PROJECT_WORK =  ../Project/Verilator
LIBRARY_WORK_RTL = $(PROJECT_WORK)/obj_dir

TOP_MODULE = Main_Zynq_Wrapper
VERILATED_TOP_MODULE_NAME = V$(TOP_MODULE)

# Convert a RSD log to a Kanata log.
KANATA_CONVERTER = python ../Tools/KanataConverter/KanataConverter.py
RSD_LOG_FILE_RTL = RSD.log
KANATA_LOG_FILE_RTL = Kanata.log

# Include core source code definition
include Makefiles/CoreSources.inc.mk


DEBUG_HELPERS = \
	SysDeps/Verilator/VerilatorHelper.sv

DEPS_RTL = \
	$(TYPES:%=$(SOURCE_ROOT)%) \
	$(MODULES:%=$(SOURCE_ROOT)%) \
	$(DEBUG_HELPERS:%=$(SOURCE_ROOT)%) \
	# $(TEST_MODULES:%=$(SOURCE_ROOT)%) \

# Temporally disabled warnings
VERILATOR_DISABLED_WARNING = \
     -Wno-WIDTH \
     -Wno-INITIALDLY \
     -Wno-UNOPTFLAT \

# RSD specific constants
# RSD_SRC_CFG is defined in Makefiles/CoreSources.inc.mk
RSD_VERILATOR_DEFINITION = \
	+define+RSD_FUNCTIONAL_SIMULATION \
	+define+RSD_FUNCTIONAL_SIMULATION_VERILATOR \
	$(RSD_SRC_CFG) \


# --assert: Enable all assertions. 
# --Mdir: Name of output object directory.
# We use "-Os" and "-output-split 15000" for faster compilation.
# See https://www.veripool.org/papers/Verilator_Accelerated_OSDA2020.pdf
VERILATOR_OPTION = \
	--cc \
	--assert \
	-sv \
	--exe ./SysDeps/Verilator/TestMain.cpp \
	--top-module $(TOP_MODULE) \
	$(VERILATOR_DISABLED_WARNING) \
	$(RSD_VERILATOR_DEFINITION) \
	--Mdir $(LIBRARY_WORK_RTL) \
	+incdir+. \
	--trace \
	-CFLAGS -Os \
	-output-split 15000 \
	#-CFLAGS "-O0 -g" \
	#--MMD \
	#-O3 \

VERILATOR_TARGET_CXXFLAGS= \
	-D RSD_FUNCTIONAL_SIMULATION_VERILATOR \
	-D RSD_FUNCTIONAL_SIMULATION \
	-D RSD_VERILATOR_TRACE \
	-D RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE \
	-Wno-attributes \

all: $(LIBRARY_WORK_RTL) $(DEPS_RTL) Makefiles/CoreSources.inc.mk
	$(VERILATOR_BIN) $(VERILATOR_OPTION) $(DEPS_RTL)
	cd $(LIBRARY_WORK_RTL); \
		VPATH=../../../Src \
		CXXFLAGS="$(VERILATOR_TARGET_CXXFLAGS)" \
			$(MAKE) -f $(VERILATED_TOP_MODULE_NAME).mk
	@echo "==== Build Successful ===="

run:
	$(LIBRARY_WORK_RTL)/$(VERILATED_TOP_MODULE_NAME) \
		MAX_TEST_CYCLES=$(MAX_TEST_CYCLES) \
		TEST_CODE=$(TEST_CODE) ENABLE_PC_GOAL=$(ENABLE_PC_GOAL) SHOW_SERIAL_OUT=$(SHOW_SERIAL_OUT)

kanata:
	$(LIBRARY_WORK_RTL)/$(VERILATED_TOP_MODULE_NAME) \
		MAX_TEST_CYCLES=$(MAX_TEST_CYCLES) \
		TEST_CODE=$(TEST_CODE) ENABLE_PC_GOAL=$(ENABLE_PC_GOAL) SHOW_SERIAL_OUT=$(SHOW_SERIAL_OUT) \
		REG_CSV_FILE=Register.csv \
		RSD_LOG_FILE=RSD.log 
	$(KANATA_CONVERTER) $(RSD_LOG_FILE_RTL) $(KANATA_LOG_FILE_RTL)


# -------------------------------
# Dump : Run test and dump values of register files for each cycle.
#        This is only for pre-translate simulation.
#
dump:	
	$(LIBRARY_WORK_RTL)/$(VERILATED_TOP_MODULE_NAME) \
		MAX_TEST_CYCLES=$(MAX_TEST_CYCLES) \
		TEST_CODE=$(TEST_CODE) ENABLE_PC_GOAL=$(ENABLE_PC_GOAL) SHOW_SERIAL_OUT=$(SHOW_SERIAL_OUT) \
		REG_CSV_FILE=Register.csv \
		RSD_LOG_FILE=RSD.log \
		WAVE_LOG_FILE=simx.vcd
	$(KANATA_CONVERTER) $(RSD_LOG_FILE_RTL) $(KANATA_LOG_FILE_RTL)

$(LIBRARY_WORK_RTL):
	mkdir $(PROJECT_WORK) -p

clean:
	rm $(LIBRARY_WORK_RTL) -f -r


# -------------------------------
# Test related items are defined in this file
RUN_TEST = @python ../Tools/TestDriver/RunTest.py --simulator=verilator
RUN_TEST_OMIT_MSG = \
	@python ../Tools/TestDriver/RunTest.py -o --simulator=verilator 
include Makefiles/TestCommands.inc.mk


