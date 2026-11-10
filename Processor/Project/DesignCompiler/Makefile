include ../../Src/Makefiles/Environment.inc.mk
.DEFAULT_GOAL := all
include ../../Src/Makefiles/GenerateConfig.inc.mk
$(call REQUIRE_ENV,RSD_DC_SHELL_BIN)

include ../../Src/Makefiles/CoreSources.inc.mk

all: $(RSD_CONFIG_OUTPUTS)
	RSD_DC_SOURCE_FILES="$(TYPES) $(CORE_MODULES)" \
	RSD_DC_DEFINES="$(patsubst +define+%,%,$(RSD_SYNTHESIS_SRC_CFG))" \
	$(RSD_DC_SHELL_BIN) -f compile.tcl | tee compile.log

clean:
	rm -rf work *.svf *.log
