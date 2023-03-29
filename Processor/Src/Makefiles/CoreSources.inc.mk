
# CAUTION! The following macros must be defined in SynthesisMacros.sv on synthesis.
#
# Definitions related to microarchitecture configuration:
# * RSD_MARCH_UNIFIED_LDST_MEM_PIPE:  Use unified LS/ST pipeline
# * RSD_MARCH_INT_ISSUE_WIDTH=N: Set issue width to N
# * RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE: Integrate mul/div to a memory pipe
RSD_SRC_CFG = \
	+define+RSD_MARCH_INT_ISSUE_WIDTH=2 \
	+define+RSD_MARCH_FP_PIPE \

#	+define+RSD_MARCH_UNIFIED_LDST_MEM_PIPE \
#	+define+RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE \


# TYPES specifies files that include packages that contain type definitions.
# Be careful about the order of these files.
# A file containing a imported package should be placed first.
TYPES = \
	MicroArchConf.sv \
	BasicTypes.sv \
	Memory/MemoryMapTypes.sv \
	RenameLogic/ActiveListIndexTypes.sv \
	Cache/CacheSystemTypes.sv \
	Memory/MemoryTypes.sv \
	Decoder/OpFormat.sv \
	Decoder/MicroOp.sv \
	RegisterFile/BypassTypes.sv \
	FetchUnit/FetchUnitTypes.sv \
	FloatingPointUnit/FPUTypes.sv \
	LoadStoreUnit/LoadStoreUnitTypes.sv \
	RenameLogic/RenameLogicTypes.sv \
	Scheduler/SchedulerTypes.sv \
	Pipeline/PipelineTypes.sv \
	IO/IO_UnitTypes.sv \
	Privileged/CSR_UnitTypes.sv \
	Debug/DebugTypes.sv \

# CORE_MODULES specifies files that defines the RSD core.
# The order of the files in this section is arbitrary.
CORE_MODULES = \
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
	Pipeline/FPBackEnd/FPIssueStage.sv \
	Pipeline/FPBackEnd/FPIssueStageIF.sv \
	Pipeline/FPBackEnd/FPRegisterReadStage.sv \
	Pipeline/FPBackEnd/FPRegisterReadStageIF.sv \
	Pipeline/FPBackEnd/FPExecutionStageIF.sv \
	Pipeline/FPBackEnd/FPExecutionStage.sv \
	Pipeline/FPBackEnd/FPRegisterWriteStage.sv \
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
	FloatingPointUnit/FP32PipelinedAdder.sv \
	FloatingPointUnit/FP32PipelinedMultiplier.sv \
	FloatingPointUnit/FP32PipelinedFMA.sv \
	FloatingPointUnit/FP32PipelinedOther.sv \
	FloatingPointUnit/FP32DivSqrter.sv \
	FloatingPointUnit/FPDivSqrtUnit.sv \
	FloatingPointUnit/FPDivSqrtUnitIF.sv \
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
	FetchUnit/Bimodal.sv \
	Scheduler/SchedulerIF.sv \
	Scheduler/IssueQueue.sv \
	Scheduler/ReplayQueue.sv \
	Scheduler/WakeupSelectIF.sv \
	Scheduler/DestinationRAM.sv \
	Scheduler/ReadyBitTable.sv \
	Scheduler/Scheduler.sv \
	Scheduler/SelectLogic.sv \
	Scheduler/SourceCAM.sv \
	Scheduler/WakeupLogic.sv \
	Scheduler/WakeupPipelineRegister.sv \
	Scheduler/ProducerMatrix.sv \
	Scheduler/MemoryDependencyPredictor.sv \
	Cache/CacheSystemIF.sv \
	Cache/DCache.sv \
	Cache/DCacheIF.sv \
	Cache/ICache.sv \
	Cache/MemoryAccessController.sv \
	Cache/CacheFlushManager.sv \
	Cache/CacheFlushManagerIF.sv \
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
	Primitives/RAM.sv \
	Primitives/LRU_Counter.sv \
	Primitives/Picker.sv \
	Primitives/Multiplier.sv \
	Primitives/Divider.sv \
	Debug/Debug.sv \
	Debug/DebugIF.sv \
	Debug/PerformanceCounter.sv \
	Debug/PerformanceCounterIF.sv \

# MODULES specifies what to compile for simulation.
MODULES = \
	Main_Zynq_Wrapper.sv \
	Main_Zynq.sv \
	Memory/Axi4LiteControlRegisterIF.sv \
	Memory/Axi4LiteControlRegister.sv \
	Memory/ControlQueue.sv \
	Memory/Axi4Memory.sv \
	Memory/Axi4MemoryIF.sv \
	Memory/MemoryReadReqQueue.sv \
	Memory/MemoryWriteDataQueue.sv \
	Memory/MemoryLatencySimulator.sv \
	$(CORE_MODULES) \

# Specify files with module definitions that are used only for testing and not used for synthesis.
# TestMain depends on Dumper and should come later.
TEST_MODULES = \
	Verification/TestBenchClockGenerator.sv \
	Verification/Dumper.sv \
	Verification/TestMain.sv \

# Header files
# This list is used when generating Vivado custom IP of RSD
HEADERS = \
	BasicMacros.sv \
	SysDeps/SynthesisMacros.svh \
	SysDeps/XilinxMacros.vh \
