
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
	MicroArchConf.sv \
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

# テスト時のみ使用し、合成時は使用しない module の定義があるファイルを指定する．
# TestMainはDumperに依存するので後にくること
TEST_MODULES = \
	Verification/TestBenchClockGenerator.sv \
	Verification/Dumper.sv \
	Verification/TestMain.sv \

# それ以外の module, interface の定義があるファイルを指定する．
# ここの順番は適当でも大丈夫．
MODULES = \
	Main_Zynq_Wrapper.sv \
	Main_Zynq.sv \
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
	Memory/Axi4LiteControlRegisterIF.sv \
	Memory/Axi4LiteControlRegister.sv \
	Memory/ControlQueue.sv \
	Memory/Axi4Memory.sv \
	Memory/Axi4MemoryIF.sv \
	Memory/MemoryReadReqQueue.sv \
	Memory/MemoryWriteDataQueue.sv \
	Memory/MemoryLatencySimulator.sv \

# Header files
# This list is used when generating Vivado custom IP of RSD
HEADERS = \
	BasicMacros.sv \
	SysDeps/SynthesisMacros.svh \
	SysDeps/XilinxMacros.vh \
