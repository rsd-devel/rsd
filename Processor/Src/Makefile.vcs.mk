# Specify test code and simulation cycles
MAX_TEST_CYCLES = 500000
SHOW_SERIAL_OUT = 0
ENABLE_PC_GOAL = 1

TEST_CODE = Verification/TestCode_64KB/C/HelloWorld
# TEST_CODE = Verification/TestCode_64KB/Dhrystone/Dhrystone
# TEST_CODE = Verification/TestCode_64KB/Coremark/Coremark


SOURCE_ROOT  = ./
TOOLS_ROOT   = ../Tools/
PROJECT_WORK =  ../Project/VCS

# Convert a RSD log to a Kanata log.
KANATA_CONVERTER = python ../Tools/KanataConverter/KanataConverter.py
RSD_LOG_FILE_RTL = RSD.log
KANATA_LOG_FILE_RTL = Kanata.log

# CAUTION! These macros must be defined in SynthesisMacros.sv on synthesis
# Definitions related to microarchitecture configuration
# * RSD_MARCH_UNIFIED_LDST_MEM_PIPE:  Use unified LS/ST pipeline
# * RSD_MARCH_INT_ISSUE_WIDTH=N: Set issue width to N
# * RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE: Integrate mul/div to a memory pipe
RSD_SRC_CFG = \
	+define+RSD_MARCH_INT_ISSUE_WIDTH=2 \

#	+define+RSD_MARCH_UNIFIED_LDST_MEM_PIPE \
#	+define+RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE \



# TYPES には型定義を含む package を含んだファイルを指定する．
# ファイルごとの依存関係に気をつけて，依存先が依存元より前にくるようにならべること．
TYPES = \
	BasicTypes.sv \
	Memory/MemoryMapTypes.sv \
	Cache/CacheSystemTypes.sv \
	Memory/MemoryTypes.sv \
	Decoder/OpFormat.sv \
	Decoder/MicroOp.sv \
	RegisterFile/BypassTypes.sv \
	FetchUnit/FetchUnitTypes.sv \
	LoadStoreUnit/LoadStoreUnitTypes.sv \
	RenameLogic/RenameLogicTypes.sv \
	Scheduler/SchedulerTypes.sv \
	Pipeline/PipelineTypes.sv \
	IO/IO_UnitTypes.sv \
	Privileged/CSR_UnitTypes.sv \
	Debug/DebugTypes.sv \
	Verification/Dumper.sv \

# テスト時のみ使用し、合成時は使用しない module の定義があるファイルを指定する．
# ここの順番は適当でも大丈夫．
TEST_MODULES = \
	Verification/TestBenchClockGenerator.sv \
	Verification/TestMain.sv \

# それ以外の module, interface の定義があるファイルを指定する．
# ここの順番は適当でも大丈夫．
MODULES = \
	Main_ASIC.sv \
	Core.sv \
	Pipeline/FetchStage/NextPCStage.sv \
	Pipeline/FetchStage/NextPCStageIF.sv \
	Pipeline/FetchStage/FetchStage.sv \
	Pipeline/FetchStage/FetchStageIF.sv \
	Pipeline/FetchStage/PC.sv \
	Pipeline/PreDecodeStage.sv \
	Pipeline/PreDecodeStageIF.sv \
	Pipeline/DecodeStage.sv \
	Pipeline/DecodeStageIF.sv \
	Pipeline/RenameStage.sv \
	Pipeline/RenameStageIF.sv \
	Pipeline/DispatchStage.sv \
	Pipeline/DispatchStageIF.sv \
	Pipeline/ScheduleStage.sv \
	Pipeline/ScheduleStageIF.sv \
	Pipeline/IntegerBackEnd/IntegerIssueStage.sv \
	Pipeline/IntegerBackEnd/IntegerIssueStageIF.sv \
	Pipeline/IntegerBackEnd/IntegerRegisterReadStage.sv \
	Pipeline/IntegerBackEnd/IntegerRegisterReadStageIF.sv \
	Pipeline/IntegerBackEnd/IntegerExecutionStageIF.sv \
	Pipeline/IntegerBackEnd/IntegerExecutionStage.sv \
	Pipeline/IntegerBackEnd/IntegerRegisterWriteStageIF.sv \
	Pipeline/IntegerBackEnd/IntegerRegisterWriteStage.sv \
	Pipeline/ComplexIntegerBackEnd/ComplexIntegerIssueStage.sv \
	Pipeline/ComplexIntegerBackEnd/ComplexIntegerIssueStageIF.sv \
	Pipeline/ComplexIntegerBackEnd/ComplexIntegerRegisterReadStage.sv \
	Pipeline/ComplexIntegerBackEnd/ComplexIntegerRegisterReadStageIF.sv \
	Pipeline/ComplexIntegerBackEnd/ComplexIntegerExecutionStageIF.sv \
	Pipeline/ComplexIntegerBackEnd/ComplexIntegerExecutionStage.sv \
	Pipeline/ComplexIntegerBackEnd/ComplexIntegerRegisterWriteStage.sv \
	Pipeline/MemoryBackEnd/MemoryIssueStage.sv \
	Pipeline/MemoryBackEnd/MemoryIssueStageIF.sv \
	Pipeline/MemoryBackEnd/MemoryRegisterReadStage.sv \
	Pipeline/MemoryBackEnd/MemoryRegisterReadStageIF.sv \
	Pipeline/MemoryBackEnd/MemoryExecutionStageIF.sv \
	Pipeline/MemoryBackEnd/MemoryExecutionStage.sv \
	Pipeline/MemoryBackEnd/MemoryAccessStageIF.sv \
	Pipeline/MemoryBackEnd/MemoryAccessStage.sv \
	Pipeline/MemoryBackEnd/MemoryTagAccessStageIF.sv \
	Pipeline/MemoryBackEnd/MemoryTagAccessStage.sv \
	Pipeline/MemoryBackEnd/MemoryRegisterWriteStageIF.sv \
	Pipeline/MemoryBackEnd/MemoryRegisterWriteStage.sv \
	Pipeline/CommitStageIF.sv \
	Pipeline/CommitStage.sv \
	RegisterFile/RegisterFile.sv \
	RegisterFile/RegisterFileIF.sv \
	RegisterFile/BypassController.sv \
	RegisterFile/BypassNetwork.sv \
	RegisterFile/BypassNetworkIF.sv \
	RegisterFile/VectorBypassNetwork.sv \
	ExecUnit/BitCounter.sv \
	ExecUnit/IntALU.sv \
	ExecUnit/Shifter.sv \
	ExecUnit/MultiplierUnit.sv \
	ExecUnit/VectorUnit.sv \
	ExecUnit/PipelinedRefDivider.sv \
	ExecUnit/DividerUnit.sv \
	MulDivUnit/MulDivUnitIF.sv \
	MulDivUnit/MulDivUnit.sv \
	LoadStoreUnit/LoadStoreUnit.sv \
	LoadStoreUnit/LoadStoreUnitIF.sv \
	LoadStoreUnit/LoadQueue.sv \
	LoadStoreUnit/StoreQueue.sv \
	LoadStoreUnit/StoreCommitter.sv \
	RenameLogic/RenameLogic.sv \
	RenameLogic/RenameLogicIF.sv \
	RenameLogic/ActiveListIF.sv \
	RenameLogic/ActiveList.sv \
	RenameLogic/RMT.sv \
	RenameLogic/RetirementRMT.sv \
	RenameLogic/RenameLogicCommitter.sv \
	Decoder/Decoder.sv \
	Decoder/DecodedBranchResolver.sv \
	FetchUnit/BTB.sv \
	FetchUnit/BranchPredictor.sv \
	FetchUnit/Gshare.sv \
	Scheduler/SchedulerIF.sv \
	Scheduler/IssueQueue.sv \
	Scheduler/ReplayQueue.sv \
	Scheduler/WakeupSelectIF.sv \
	Scheduler/DestinationRAM.sv \
	Scheduler/ReadyBitTable.sv \
	Scheduler/Scheduler.sv \
	Scheduler/SelectLogic.sv \
	Scheduler/WakeupLogic.sv \
	Scheduler/WakeupPipelineRegister.sv \
	Scheduler/ProducerMatrix.sv \
	Scheduler/MemoryDependencyPredictor.sv \
	Cache/CacheSystemIF.sv \
	Cache/DCache.sv \
	Cache/DCacheIF.sv \
	Cache/ICache.sv \
	Cache/CachePrimitives.sv \
	Cache/MemoryAccessController.sv \
	Memory/Memory.sv \
	Recovery/RecoveryManager.sv \
	Recovery/RecoveryManagerIF.sv \
	ControllerIF.sv \
	Controller.sv \
	ResetController.sv \
	Privileged/InterruptController.sv \
	Privileged/CSR_Unit.sv \
	Privileged/CSR_UnitIF.sv \
	IO/IO_Unit.sv \
	IO/IO_UnitIF.sv \
	Primitives/FlipFlop.sv \
	Primitives/FreeList.sv \
	Primitives/Queue.sv \
	Primitives/RAM_ASIC.sv \
	Primitives/LRU_Counter.sv \
	Primitives/Picker.sv \
	Primitives/Multiplier.sv \
	Primitives/Divider.sv \
	Debug/Debug.sv \
	Debug/DebugIF.sv \
	Debug/HardwareCounter.sv \
	Debug/HardwareCounterIF.sv \
	Memory/MemoryRequestQueue.sv \

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
