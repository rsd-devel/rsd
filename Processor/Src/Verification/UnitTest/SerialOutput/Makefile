include ../../../Makefiles/Environment.inc.mk

UNIT_NAME = SerialOutput
TEST_BENCH_MODULE = Test$(UNIT_NAME)
SOURCE_ROOT = ../../../

include $(SOURCE_ROOT)Makefiles/CoreSources.inc.mk
MODULES = \
	IO/IO_UnitIF.sv \
	IO/PLIC_UnitIF.sv \
	Privileged/CSR_UnitIF.sv \
	IO/IO_Unit.sv \
	Memory/Axi4LiteControlRegisterIF.sv \
	Memory/Axi4LiteControlRegister.sv \
	Memory/ControlQueue.sv \
	Primitives/Queue.sv
TEST_MODULES = Verification/UnitTest/SerialOutput/TestSerialOutput.sv
VLOG_OPTIONS = $(RSD_SRC_CFG) +incdir+$(SOURCE_ROOT) -suppress 2605
VSIM_OPTIONS = -suppress 2605 -suppress 8233

include ../../../Makefiles/UnitTest.inc.mk
