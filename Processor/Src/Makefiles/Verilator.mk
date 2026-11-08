# Verilator RTL backend, included by the main Makefile.
TEST_CODE = Verification/TestCode/Asm/FP
#TEST_CODE = Verification/TestCode/C/FP
#TEST_CODE = Verification/TestCode/C/HelloWorld

PROJECT_WORK = ../Project/Verilator
LIBRARY_WORK_RTL = $(PROJECT_WORK)/obj_dir
TOP_MODULE = TestMain
include Makefiles/Verilator.inc.mk

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
