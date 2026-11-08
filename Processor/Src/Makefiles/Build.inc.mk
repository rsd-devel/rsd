# Shared core source dependencies and generated RTL; run from Processor/Src.
SOURCE_ROOT ?= ./
TOOLS_ROOT ?= ../Tools/
include Makefiles/Environment.inc.mk

# Keep this manifest in place with literal TYPES/CORE_MODULES lists for sv-tests.
include Makefiles/CoreSources.inc.mk

DEPS_RTL = $(addprefix $(SOURCE_ROOT),$(TYPES) $(MODULES) $(TEST_MODULES))

$(CORE_TEMPLATE_FILES): $(wildcard Generator/*.py) default.yml $(CORE_TEMPLATE_FILES:.sv=.template.sv)
	python3 Generator/cpu_generator.py --rsd-root $(RSD_ROOT)
