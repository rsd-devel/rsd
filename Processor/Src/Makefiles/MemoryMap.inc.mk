# Keep generation separate from CoreSources.inc.mk so callers can use it
# without overwriting their own TYPES/MODULES lists (notably unit tests).
# CoreSources.inc.mk also serves as a source manifest parsed directly by
# sv-tests and Xilinx tools.
# Shared by RTL builds and software/test builds, including direct invocations.
# Include Environment.inc.mk first to set RSD_ROOT.
MEMORY_MAP_ROOT := $(RSD_ROOT)/Processor/Src
MEMORY_MAP_OUTPUTS := $(MEMORY_MAP_ROOT)/Memory/MemoryMapTypes.sv \
	$(addprefix $(MEMORY_MAP_ROOT)/Verification/TestCode/,rsd-memory-map.h rsd-memory-map.ld rsd-memory-map.mk)

$(MEMORY_MAP_OUTPUTS) &: $(wildcard $(MEMORY_MAP_ROOT)/Generator/*.py) $(MEMORY_MAP_ROOT)/MemoryMap.yml $(MEMORY_MAP_ROOT)/Memory/MemoryMapTypes.template.sv
	python3 $(MEMORY_MAP_ROOT)/Generator/cpu_generator.py --rsd-root $(RSD_ROOT)
