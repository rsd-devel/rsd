# Keep configuration generation separate from CoreSources.inc.mk so callers can use it
# without overwriting their own TYPES/MODULES lists (notably unit tests).
# CoreSources.inc.mk also serves as a source manifest parsed directly by
# sv-tests and Xilinx tools.
# Shared by RTL builds and software/test builds, including direct invocations.
# Include Environment.inc.mk first to set RSD_ROOT.
RSD_MEMORY_MAP_OUTPUTS := $(RSD_ROOT)/Processor/Src/Memory/MemoryMapTypes.sv \
	$(addprefix $(RSD_ROOT)/Processor/Src/Verification/TestCode/,rsd-memory-map.h rsd-memory-map.ld rsd-memory-map.mk)

$(RSD_MEMORY_MAP_OUTPUTS) &: $(RSD_ROOT)/Processor/Tools/ConfigGenerator/ConfigGenerator.py $(RSD_ROOT)/Processor/Config/MemoryMap.yml $(RSD_ROOT)/Processor/Src/Memory/MemoryMapTypes.template.sv
	python3 $(RSD_ROOT)/Processor/Tools/ConfigGenerator/ConfigGenerator.py --rsd-root $(RSD_ROOT) --only memory-map

RSD_MICRO_ARCH_OUTPUTS := $(addprefix $(RSD_ROOT)/Processor/Src/,MicroArchConf.sv MicroArchMacros.svh Makefiles/MicroArch.inc.mk)

$(RSD_MICRO_ARCH_OUTPUTS) &: $(RSD_ROOT)/Processor/Tools/ConfigGenerator/ConfigGenerator.py $(RSD_ROOT)/Processor/Config/MicroArch.yml $(RSD_ROOT)/Processor/Src/MicroArchConf.template.sv
	python3 $(RSD_ROOT)/Processor/Tools/ConfigGenerator/ConfigGenerator.py --rsd-root $(RSD_ROOT) --only microarch

RSD_CONFIG_OUTPUTS := $(RSD_MEMORY_MAP_OUTPUTS) $(RSD_MICRO_ARCH_OUTPUTS)
