include ../../Src/Makefiles/CoreSources.inc.mk

all:
	RSD_DC_SOURCE_FILES="$(TYPES) $(CORE_MODULES)" \
	$(RSD_DC_SHELL_BIN) -f compile.tcl | tee compile.log

clean:
	rm -rf work *.svf *.log
