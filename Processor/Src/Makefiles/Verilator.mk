# Verilator RTL backend, included by the main Makefile.
TEST_CODE = Verification/TestCode/Asm/FP
#TEST_CODE = Verification/TestCode/C/FP
#TEST_CODE = Verification/TestCode/C/HelloWorld

ifndef RSD_VERILATOR_BIN
VERILATOR_BIN = verilator
else
VERILATOR_BIN = $(RSD_VERILATOR_BIN)
endif


PROJECT_WORK =  ../Project/Verilator
LIBRARY_WORK_RTL = $(PROJECT_WORK)/obj_dir

TOP_MODULE = TestMain
VERILATED_TOP_MODULE_NAME = V$(TOP_MODULE)

# Temporally disabled warnings
# MULTIDRIVEN: simulation-only initializers also write always_ff registers.
VERILATOR_DISABLED_WARNING = \
     -Wno-WIDTH \
     -Wno-INITIALDLY \
     -Wno-UNOPTFLAT \
     -Wno-MULTIDRIVEN \

# RSD specific constants
# RSD_SRC_CFG is defined in Makefiles/CoreSources.inc.mk
RSD_VERILATOR_DEFINITION = \
	+define+RSD_FUNCTIONAL_SIMULATION \
	$(RSD_SRC_CFG) \


# --main/--timing: Generate the execution loop for the shared SV testbench.
# --assert: Enable all assertions.
# --Mdir: Name of output object directory.
# We use "-Os" and "-output-split 15000" for faster compilation.
# See https://www.veripool.org/papers/Verilator_Accelerated_OSDA2020.pdf
VERILATOR_OPTION = \
	--cc \
	--main \
	--timing \
	--timescale 1ns/1ps \
	--exe \
	--assert \
	-sv \
	--top-module $(TOP_MODULE) \
	$(VERILATOR_DISABLED_WARNING) \
	$(RSD_VERILATOR_DEFINITION) \
	--Mdir $(LIBRARY_WORK_RTL) \
	+incdir+. \
	--trace \
	-CFLAGS "-Os" \
	-output-split 15000 \
	#-CFLAGS "-O0 -g" \
	#--MMD \
	#-O3 \

all: $(CORE_TEMPLATE_FILES) $(LIBRARY_WORK_RTL) $(DEPS_RTL) Makefiles/CoreSources.inc.mk
	$(VERILATOR_BIN) $(VERILATOR_OPTION) $(DEPS_RTL)
	$(MAKE) -C $(LIBRARY_WORK_RTL) -f $(VERILATED_TOP_MODULE_NAME).mk
	@echo "==== Build Successful ===="

run:
	$(LIBRARY_WORK_RTL)/$(VERILATED_TOP_MODULE_NAME) \
		$(addprefix +,$(SIM_PLUSARGS))

kanata:
	$(LIBRARY_WORK_RTL)/$(VERILATED_TOP_MODULE_NAME) \
		$(addprefix +,$(SIM_PLUSARGS)) \
		+REG_CSV_FILE=Register.csv \
		+RSD_LOG_FILE=RSD.log
	$(KANATA_CONVERTER) $(RSD_LOG_FILE_RTL) $(KANATA_LOG_FILE_RTL)


# -------------------------------
# Dump : Run test and dump values of register files for each cycle.
#        This is only for pre-translate simulation.
#
dump:
	$(LIBRARY_WORK_RTL)/$(VERILATED_TOP_MODULE_NAME) \
		$(addprefix +,$(SIM_PLUSARGS)) \
		+REG_CSV_FILE=Register.csv \
		+RSD_LOG_FILE=RSD.log \
		+WAVE_LOG_FILE=simx.vcd
	$(KANATA_CONVERTER) $(RSD_LOG_FILE_RTL) $(KANATA_LOG_FILE_RTL)

$(LIBRARY_WORK_RTL):
	mkdir $(PROJECT_WORK) -p

clean:
	rm $(LIBRARY_WORK_RTL) -f -r
	rm $(CORE_TEMPLATE_FILES) -f
