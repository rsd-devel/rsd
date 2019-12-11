
# instantiation
set design_name Core

# Specify library files
set link_library {
    "*"
}
#    ~/workspace/RSD/lib/gscl45nm.db

#set target_library {
#    ~/workspace/RSD/lib/gscl45nm.db
#}

# Include search path
lappend search_path "../../Src/"

# Working directory
define_design_lib WORK -path "./work"

# Specify source files
set file_names {
    ../../Src/SynthesisMacros.sv
    ../../Src/BasicTypes.sv
    ../../Src/Memory/MemoryMapTypes.sv
    ../../Src/Cache/CacheSystemTypes.sv
    ../../Src/Memory/MemoryTypes.sv
    ../../Src/Decoder/OpFormat.sv
    ../../Src/Decoder/MicroOp.sv
    ../../Src/RegisterFile/BypassTypes.sv
    ../../Src/FetchUnit/FetchUnitTypes.sv
    ../../Src/LoadStoreUnit/LoadStoreUnitTypes.sv
    ../../Src/RenameLogic/RenameLogicTypes.sv
    ../../Src/Scheduler/SchedulerTypes.sv
    ../../Src/Pipeline/PipelineTypes.sv
    ../../Src/IO/IO_UnitTypes.sv
    ../../Src/Privileged/CSR_UnitTypes.sv
    ../../Src/Debug/DebugTypes.sv
    ../../Src/Core.sv
    ../../Src/Pipeline/FetchStage/PC.sv
    ../../Src/Pipeline/FetchStage/NextPCStage.sv
    ../../Src/Pipeline/FetchStage/NextPCStageIF.sv
    ../../Src/Pipeline/FetchStage/FetchStage.sv
    ../../Src/Pipeline/FetchStage/FetchStageIF.sv
    ../../Src/Pipeline/PreDecodeStage.sv
    ../../Src/Pipeline/PreDecodeStageIF.sv
    ../../Src/Pipeline/DecodeStage.sv
    ../../Src/Pipeline/DecodeStageIF.sv
    ../../Src/Pipeline/RenameStage.sv
    ../../Src/Pipeline/RenameStageIF.sv
    ../../Src/Pipeline/DispatchStage.sv
    ../../Src/Pipeline/DispatchStageIF.sv
    ../../Src/Pipeline/ScheduleStage.sv
    ../../Src/Pipeline/ScheduleStageIF.sv
    ../../Src/Pipeline/IntegerBackEnd/IntegerIssueStage.sv
    ../../Src/Pipeline/IntegerBackEnd/IntegerIssueStageIF.sv
    ../../Src/Pipeline/IntegerBackEnd/IntegerRegisterReadStage.sv
    ../../Src/Pipeline/IntegerBackEnd/IntegerRegisterReadStageIF.sv
    ../../Src/Pipeline/IntegerBackEnd/IntegerExecutionStageIF.sv
    ../../Src/Pipeline/IntegerBackEnd/IntegerExecutionStage.sv
    ../../Src/Pipeline/IntegerBackEnd/IntegerRegisterWriteStageIF.sv
    ../../Src/Pipeline/IntegerBackEnd/IntegerRegisterWriteStage.sv
    ../../Src/Pipeline/ComplexIntegerBackEnd/ComplexIntegerIssueStage.sv
    ../../Src/Pipeline/ComplexIntegerBackEnd/ComplexIntegerIssueStageIF.sv
    ../../Src/Pipeline/ComplexIntegerBackEnd/ComplexIntegerRegisterReadStage.sv
    ../../Src/Pipeline/ComplexIntegerBackEnd/ComplexIntegerRegisterReadStageIF.sv
    ../../Src/Pipeline/ComplexIntegerBackEnd/ComplexIntegerExecutionStageIF.sv
    ../../Src/Pipeline/ComplexIntegerBackEnd/ComplexIntegerExecutionStage.sv
    ../../Src/Pipeline/ComplexIntegerBackEnd/ComplexIntegerRegisterWriteStage.sv
    ../../Src/Pipeline/MemoryBackEnd/MemoryIssueStage.sv
    ../../Src/Pipeline/MemoryBackEnd/MemoryIssueStageIF.sv
    ../../Src/Pipeline/MemoryBackEnd/MemoryRegisterReadStage.sv
    ../../Src/Pipeline/MemoryBackEnd/MemoryRegisterReadStageIF.sv
    ../../Src/Pipeline/MemoryBackEnd/MemoryExecutionStageIF.sv
    ../../Src/Pipeline/MemoryBackEnd/MemoryExecutionStage.sv
    ../../Src/Pipeline/MemoryBackEnd/MemoryAccessStageIF.sv
    ../../Src/Pipeline/MemoryBackEnd/MemoryAccessStage.sv
    ../../Src/Pipeline/MemoryBackEnd/MemoryTagAccessStageIF.sv
    ../../Src/Pipeline/MemoryBackEnd/MemoryTagAccessStage.sv
    ../../Src/Pipeline/MemoryBackEnd/MemoryRegisterWriteStageIF.sv
    ../../Src/Pipeline/MemoryBackEnd/MemoryRegisterWriteStage.sv
    ../../Src/Pipeline/CommitStageIF.sv
    ../../Src/Pipeline/CommitStage.sv
    ../../Src/RegisterFile/RegisterFile.sv
    ../../Src/RegisterFile/RegisterFileIF.sv
    ../../Src/RegisterFile/BypassController.sv
    ../../Src/RegisterFile/BypassNetwork.sv
    ../../Src/RegisterFile/BypassNetworkIF.sv
    ../../Src/RegisterFile/VectorBypassNetwork.sv
    ../../Src/ExecUnit/BitCounter.sv
    ../../Src/ExecUnit/IntALU.sv
    ../../Src/ExecUnit/Shifter.sv
    ../../Src/ExecUnit/MultiplierUnit.sv
    ../../Src/ExecUnit/DividerUnit.sv
    ../../Src/ExecUnit/VectorUnit.sv
    ../../Src/MulDivUnit/MulDivUnit.sv
    ../../Src/MulDivUnit/MulDivUnitIF.sv
    ../../Src/LoadStoreUnit/LoadStoreUnit.sv
    ../../Src/LoadStoreUnit/LoadStoreUnitIF.sv
    ../../Src/LoadStoreUnit/LoadQueue.sv
    ../../Src/LoadStoreUnit/StoreQueue.sv
    ../../Src/LoadStoreUnit/StoreCommitter.sv
    ../../Src/RenameLogic/RenameLogic.sv
    ../../Src/RenameLogic/RenameLogicIF.sv
    ../../Src/RenameLogic/ActiveListIF.sv
    ../../Src/RenameLogic/ActiveList.sv
    ../../Src/RenameLogic/RMT.sv
    ../../Src/RenameLogic/RetirementRMT.sv
    ../../Src/RenameLogic/RenameLogicCommitter.sv
    ../../Src/Decoder/Decoder.sv
    ../../Src/Decoder/DecodedBranchResolver.sv
    ../../Src/FetchUnit/BTB.sv
    ../../Src/FetchUnit/BranchPredictor.sv
    ../../Src/FetchUnit/Gshare.sv
    ../../Src/FetchUnit/Bimodal.sv
    ../../Src/Scheduler/SchedulerIF.sv
    ../../Src/Scheduler/IssueQueue.sv
    ../../Src/Scheduler/ReplayQueue.sv
    ../../Src/Scheduler/WakeupSelectIF.sv
    ../../Src/Scheduler/DestinationRAM.sv
    ../../Src/Scheduler/ReadyBitTable.sv
    ../../Src/Scheduler/Scheduler.sv
    ../../Src/Scheduler/SelectLogic.sv
    ../../Src/Scheduler/SourceCAM.sv
    ../../Src/Scheduler/WakeupLogic.sv
    ../../Src/Scheduler/WakeupPipelineRegister.sv
    ../../Src/Scheduler/ProducerMatrix.sv
    ../../Src/Scheduler/MemoryDependencyPredictor.sv
    ../../Src/Cache/CacheSystemIF.sv
    ../../Src/Cache/DCache.sv
    ../../Src/Cache/DCacheIF.sv
    ../../Src/Cache/ICache.sv
    ../../Src/Cache/CachePrimitives.sv
    ../../Src/Cache/MemoryAccessController.sv
    ../../Src/ControllerIF.sv
    ../../Src/Controller.sv
    ../../Src/ResetController.sv
    ../../Src/Privileged/InterruptController.sv
    ../../Src/Privileged/CSR_Unit.sv
    ../../Src/Privileged/CSR_UnitIF.sv
    ../../Src/IO/IO_Unit.sv
    ../../Src/IO/IO_UnitIF.sv
    ../../Src/Primitives/FlipFlop.sv
    ../../Src/Primitives/FreeList.sv
    ../../Src/Primitives/Queue.sv
    ../../Src/Primitives/RAM.sv
    ../../Src/Primitives/LRU_Counter.sv
    ../../Src/Primitives/Picker.sv
    ../../Src/Primitives/Multiplier.sv
    ../../Src/Primitives/Divider.sv
    ../../Src/Debug/Debug.sv
    ../../Src/Debug/DebugIF.sv
    ../../Src/Debug/HardwareCounter.sv
    ../../Src/Debug/HardwareCounterIF.sv
    ../../Src/Recovery/RecoveryManager.sv
    ../../Src/Recovery/RecoveryManagerIF.sv
}

foreach file_name $file_names {
	analyze -format sverilog -define RSD_SYNTHESIS,RSD_SYNTHESIS_DESIGN_COMPILER $file_name
}


elaborate $design_name -work WORK

# eliminate old library cells
suppress_message TRANS-1

current_design $design_name
set_local_link_library $link_library

# Report check_design
redirect check_design.log { check_design }
# write -f ddc -o read.ddc -hier $design_name

link

exit
