# テスト対象となるモジュールの名前を指定．
UNIT_NAME         = CacheSystem

# ライブラリ名とトップレベルモジュール（シミュレーション対象）
TEST_BENCH_MODULE = Test$(UNIT_NAME)
TOP_MODULE        = $(TEST_BENCH_MODULE)Top

SOURCE_ROOT  = ../../../
TOOLS_ROOT   = ../../../../Tools/
PROJECT_WORK = ../../../../Project/ModelSim
ISE_PROJECT_ROOT = ../../../../Project/Synplify/$(UNIT_NAME)/pr_1/

# TYPES には型定義を含む package を含んだファイルを指定する．
# ファイルごとの依存関係に気をつけて，依存先が依存元より前にくるようにならべること．
TYPES = \
	BasicTypes.sv \
	Cache/CacheSystemTypes.sv \
	Decoder/OpFormat.sv \
	Decoder/MicroOp.sv \
	RegisterFile/BypassTypes.sv \
	RenameLogic/RenameLogicTypes.sv \
	LoadStoreUnit/LoadStoreUnitTypes.sv \
	Scheduler/SchedulerTypes.sv \
	Pipeline/PipelineTypes.sv \

# テスト時のみ使用し、合成時は使用しない module の定義があるファイルを指定する．
# ここの順番は適当でも大丈夫．
TEST_MODULES = \
	Verification/TestBenchClockGenerator.sv \
	Verification/UnitTest/CacheSystem/TestCacheSystem.sv \

# それ以外の module, interface の定義があるファイルを指定する．
# ここの順番は適当でも大丈夫．
MODULES = \
	ResetController.sv \
	Primitives/LRU_Counter.sv \
	Primitives/RAM.sv \
	Pipeline/FetchStage/FetchStageIF.sv \
	Pipeline/MemoryBackEnd/MemoryAccessStageIF.sv \
	LoadStoreUnit/LoadStoreUnitIF.sv \
	Cache/CacheSystemIF.sv \
	Cache/DCache.sv \
	Cache/DCacheFiller.sv \
	Cache/ICache.sv \
	Cache/ICacheFiller.sv \
	Cache/CachePrimitives.sv \
	Cache/Memory.sv \
	Verification/UnitTest/CacheSystem/TestCacheSystemTop.sv \

# 合成時に、特定の警告を非表示にする
VLOG_OPTIONS = \
	-suppress 2605 \

# シミュレーション時に、特定の警告を非表示にする
VSIM_OPTIONS = \
	-suppress 2605 \
	-suppress 8233 \

include ../../../Makefile.inc
