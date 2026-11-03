UNIT_NAME = InterruptController
TEST_BENCH_MODULE = Test$(UNIT_NAME)
SOURCE_ROOT = ../../../
PROJECT_WORK = ../../../../Project/ModelSim

include $(SOURCE_ROOT)Makefiles/CoreSources.inc.mk
MODULES = \
	ControllerIF.sv \
	Pipeline/FetchStage/NextPCStageIF.sv \
	Recovery/RecoveryManagerIF.sv \
	Privileged/CSR_UnitIF.sv \
	IO/PLIC_UnitIF.sv \
	IO/IO_UnitIF.sv \
	Debug/PerformanceCounterIF.sv \
	IO/PLIC_Unit.sv \
	Privileged/CSR_Unit.sv \
	Privileged/InterruptController.sv
TEST_MODULES = Verification/UnitTest/InterruptController/TestInterruptController.sv
VLOG_OPTIONS = $(RSD_SRC_CFG) +incdir+$(SOURCE_ROOT) -suppress 2605
VSIM_OPTIONS = -suppress 2605 -suppress 8233
# Known failure: make test VSIM_OPTIONS_RTL=+CHECK_MIXED_DELEGATION.

include ../../../Makefile.inc
