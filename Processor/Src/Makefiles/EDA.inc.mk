# Public target:backend makefile:backend target. Explicit phony targets let
# standard bash-completion show one slash-separated level at a time.
# Submakes isolate each tool's variables, defaults, and internal target names.
RSD_EDA_TARGETS := \
	synth/vivado/build:Vivado:vivado-synthesis \
	synth/vivado/open:Vivado:vivado \
	synth/vivado/clean:Vivado:vivado-clean \
	synth/vivado/post-synthesis/build:Vivado:post-synthesis-build \
	synth/vivado/post-synthesis/test:Vivado:test-post-synthesis \
	synth/vivado/post-synthesis/clean:Vivado:post-synthesis-clean \
	synth/vivado/post-synthesis/open:Vivado:post-synthesis-open \
	synth/vivado/post-synthesis/timing/test:Vivado:post-synthesis-timing \
	synth/vivado/post-synthesis/timing/run:Vivado:post-synthesis-timing-run \
	synth/vivado/post-synthesis/timing/gui:Vivado:post-synthesis-timing-run-gui \
	synth/vivado/post-synthesis/timing/kanata:Vivado:post-synthesis-timing-kanata \
	synth/vivado/post-implementation/build:Vivado:post-implementation-build \
	synth/vivado/post-implementation/test:Vivado:post-implementation \
	synth/vivado/post-implementation/run:Vivado:post-implementation-run \
	synth/vivado/post-implementation/gui:Vivado:post-implementation-run-gui \
	synth/vivado/post-implementation/kanata:Vivado:post-implementation-kanata \
	synth/vivado/post-implementation/timing/test:Vivado:post-implementation-timing \
	synth/vivado/post-implementation/timing/run:Vivado:post-implementation-timing-run \
	synth/vivado/post-implementation/timing/gui:Vivado:post-implementation-timing-run-gui \
	synth/vivado/post-implementation/timing/kanata:Vivado:post-implementation-timing-kanata \
	synth/synplify/build:Synplify:vivado-synthesis \
	synth/synplify/open:Synplify:vivado \
	synth/synplify/clean:Synplify:vivado-clean \
	synth/synplify/post-synthesis/build:Synplify:post-synthesis-build \
	synth/synplify/post-synthesis/test:Synplify:test-post-synthesis \
	synth/synplify/post-synthesis/clean:Synplify:post-synthesis-clean \
	sim/vcs/post-implementation/build:VCS:post-implementation-build \
	sim/vcs/post-implementation/test:VCS:test-post-implementation \
	sim/vcs/post-implementation/run:VCS:post-implementation-run

define RSD_EDA_FORWARD
.PHONY: $(word 1,$(1))
$(word 1,$(1)):
	$$(MAKE) -f Makefiles/$(word 2,$(1)).mk $(word 3,$(1))
endef
$(foreach target,$(RSD_EDA_TARGETS),$(eval $(call RSD_EDA_FORWARD,$(subst :, ,$(target)))))

# Linux builds do not require Vivado, a simulator or a RISC-V compiler.
RSD_ZYNQ_TARGETS := $(addprefix platform/zynq/,fetch build clean)
.PHONY: $(RSD_ZYNQ_TARGETS)
$(RSD_ZYNQ_TARGETS): platform/zynq/%:
	$(MAKE) -C ../Project/Vivado/ARM_Linux $*

.PHONY: platform/zynq/hardware/build platform/zynq/bootbin/build platform/zynq/image/build platform/zynq/image/write
platform/zynq/bootbin/build:
	$(MAKE) -C ../Project/Vivado/ARM_Linux bootbin

platform/zynq/image/build:
	$(MAKE) -C ../Project/Vivado/ARM_Linux image

platform/zynq/image/write:
	$(MAKE) -C ../Project/Vivado/ARM_Linux image-write

platform/zynq/hardware/build:
	$(MAKE) -f Makefiles/Vivado.mk zynq-hardware
