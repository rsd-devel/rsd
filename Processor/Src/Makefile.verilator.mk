# Specify test code and simulation cycles
MAX_TEST_CYCLES = 100000
SHOW_SERIAL_OUT = 1
ENABLE_PC_GOAL = 1
TEST_CODE = Verification/TestCode/Asm/FP
#TEST_CODE = Verification/TestCode/C/FP
#TEST_CODE = Verification/TestCode/C/HelloWorld

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
KANATA_CONVERTER = python3 ../Tools/KanataConverter/KanataConverter.py
RSD_LOG_FILE_RTL = RSD.log
KANATA_LOG_FILE_RTL = Kanata.log

# Include core source code definition
include Makefiles/CoreSources.inc.mk


DEBUG_HELPERS =

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
	-CFLAGS "-Os -include limits" \
	-output-split 15000 \
	#-CFLAGS "-O0 -g" \
	#--MMD \
	#-O3 \

VERILATOR_TARGET_CXXFLAGS= \
	-D RSD_FUNCTIONAL_SIMULATION_VERILATOR \
	-D RSD_FUNCTIONAL_SIMULATION \
	-D RSD_VERILATOR_TRACE \
	-D RSD_MARCH_FP_PIPE \
	-Wno-attributes \

VERYL_TARGET_DIR = ./target
VERYL_SOURCES = $(shell find . -name '*.veryl' -print)

.PHONY: build veryl-build veryl-clean clean
build: all

veryl-build: $(VERYL_GENERATED_RTL)

$(VERYL_GENERATED_RTL): Veryl.toml $(VERYL_SOURCES)
	veryl build
	perl -0pi -e 'my %m; while (/^\s*localparam\s+(?:[A-Za-z_][A-Za-z0-9_]*\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s+([A-Za-z_][A-Za-z0-9_]*_[A-Za-z0-9_]*);/mg) { $$m{$$2} = $$1; } for my $$k (sort { length($$b) <=> length($$a) } keys %m) { my $$v = $$m{$$k}; s/\b\Q$$k\E\b/$$v/g; } s/^\s*localparam\s+(?:[A-Za-z_][A-Za-z0-9_]*\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s+\1;\s*\n//mg;' target/rsd_pkg_if.sv
	perl -0pi -e 's/^(\s*localparam\b[^\n=]*\b(?:PC_GOAL|PHY_ADDR_SECTION_0_BASE|PHY_ADDR_SECTION_1_BASE|LSCALAR_NUM|LSCALAR_FP_NUM|LREG_NUM|FETCH_WIDTH|DECODE_WIDTH|RENAME_WIDTH|DISPATCH_WIDTH|COMMIT_WIDTH|INT_ISSUE_WIDTH|COMPLEX_ISSUE_WIDTH|MEM_ISSUE_WIDTH|FP_ISSUE_WIDTH|ISSUE_QUEUE_ENTRY_NUM|COMPLEX_EXEC_STAGE_DEPTH|FP_EXEC_STAGE_DEPTH)\b)(\s*=)/$$1 \/*verilator public*\/$$2/mg; s/typedef MicroOpTypes::MemMicroOpSubType MemMicroOpSubType;/typedef MicroOpTypes::MemMicroOpSubType MemMicroOpSubType \/*verilator public*\/;/' target/rsd_pkg_if.sv

all: $(LIBRARY_WORK_RTL) $(VERYL_GENERATED_RTL) $(DEPS_RTL) Makefiles/CoreSources.inc.mk
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
	veryl clean
	rm $(LIBRARY_WORK_RTL) -f -r


# -------------------------------
# Test related items are defined in this file
RUN_TEST = @python3 ../Tools/TestDriver/RunTest.py --simulator=verilator
RUN_TEST_OMIT_MSG = \
	@python3 ../Tools/TestDriver/RunTest.py -o --simulator=verilator 
include Makefiles/TestCommands.inc.mk


