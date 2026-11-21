# Build & clean startup routine
include Makefile.inc

.PHONY: build clean

build: $(CRTOBJ) $(LDOBJ) $(DUMMY_ROM)

clean:
	rm -f $(CRTOBJ)
	rm -f $(DUMMY_ROM)
	rm -f $(LDOBJ)
	rm -f $(CRTOBJ:.o=.d) $(LDOBJ:.o=.d)
