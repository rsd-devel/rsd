# ModelSim/QuestaSim RTL backend, included by the main Makefile.
#TEST_CODE = Verification/TestCode/Asm/CacheFlush
#TEST_CODE = Verification/TestCode/C/HelloWorld
TEST_CODE = Verification/TestCode/C/FP
#TEST_CODE = Verification/TestCode/Asm/FP

PROJECT_WORK = ../Project/ModelSim
UNIT_NAME = Main
TEST_BENCH_MODULE = Test$(UNIT_NAME)
TOP_MODULE = $(UNIT_NAME)
VLOG_OPTIONS = $(RSD_SRC_CFG)
VSIM_OPTIONS = $(addprefix +,$(SIM_PLUSARGS)) -suppress 8233 +autofindloop
VSIM_OPTIONS_RTL = +RSD_LOG_FILE=$(RSD_LOG_FILE_RTL) +DEBUG_LOG_FILE=$(DEBUG_LOG_FILE_RTL)
VSIM_OPTIONS_DUMP = +REG_CSV_FILE=$(REG_CSV_FILE)

include Makefiles/ModelSim.inc.mk

kanata: rtl-kanata
rtl-kanata: rtl-run
	$(KANATA_CONVERTER) $(RSD_LOG_FILE_RTL) $(KANATA_LOG_FILE_RTL)

dump:
	$(VSIM) $(TARGET_MODULE_RTL) $(VSIM_OPTIONS) $(VSIM_OPTIONS_RTL) $(VSIM_OPTIONS_DUMP) -do "run -all"
