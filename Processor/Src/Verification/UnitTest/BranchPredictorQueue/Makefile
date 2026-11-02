UNIT_NAME = BranchPredictorQueue
TEST_BENCH_MODULE = Test$(UNIT_NAME)
SOURCE_ROOT = ../../../
PROJECT_WORK = ../../../../Project/ModelSim

TYPES = \
	MicroArchConf.sv \
	BasicTypes.sv \
	Memory/MemoryMapTypes.sv \
	RenameLogic/ActiveListIndexTypes.sv \
	Cache/CacheSystemTypes.sv \
	FloatingPointUnit/FPUTypes.sv \
	Decoder/OpFormat.sv \
	Decoder/MicroOp.sv \
	RegisterFile/BypassTypes.sv \
	FetchUnit/FetchUnitTypes.sv \
	LoadStoreUnit/LoadStoreUnitTypes.sv \
	RenameLogic/RenameLogicTypes.sv \
	Scheduler/SchedulerTypes.sv \
	Pipeline/PipelineTypes.sv

MODULES = \
	Primitives/RAM.sv \
	Primitives/Queue.sv \
	ControllerIF.sv \
	Pipeline/FetchStage/NextPCStageIF.sv \
	Pipeline/FetchStage/FetchStageIF.sv \
	FetchUnit/BTB.sv \
	FetchUnit/Gshare.sv \
	FetchUnit/Bimodal.sv

TEST_MODULES = Verification/UnitTest/BranchPredictorQueue/TestBranchPredictorQueue.sv
VLOG_OPTIONS = -suppress 2605 +incdir+$(SOURCE_ROOT) +define+RSD_MARCH_INT_ISSUE_WIDTH=2
VSIM_OPTIONS = -suppress 2605 -suppress 8233

include ../../../Makefile.inc
