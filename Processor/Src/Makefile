# Verilator is the default core simulator. Keep its explicit entry point usable.
include Makefile.verilator.mk

# RTL unit tests still use ModelSim/QuestaSim and its separate build directory.
.PHONY: test-unit force-unit-test
test-unit:
	$(MAKE) -f Makefile.modelsim.mk $@

test-unit-%: force-unit-test
	$(MAKE) -f Makefile.modelsim.mk $@

force-unit-test:
