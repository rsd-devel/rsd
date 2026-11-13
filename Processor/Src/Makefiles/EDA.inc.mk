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
	platform/zynq/build:Vivado:xilinx-arm-linux \
	platform/zynq/all:Vivado:xilinx-arm-linux-all \
	platform/zynq/clean:Vivado:xilinx-arm-linux-clean \
	platform/zynq/fetch:Vivado:xilinx-arm-linux-clone-all \
	platform/zynq/kernel/build:Vivado:xilinx-arm-linux-kernel \
	platform/zynq/kernel/fetch:Vivado:xilinx-arm-linux-kernel-fetch \
	platform/zynq/kernel/clean:Vivado:xilinx-arm-linux-kernel-clean \
	platform/zynq/u-boot/build:Vivado:xilinx-arm-linux-u-boot \
	platform/zynq/u-boot/fetch:Vivado:xilinx-arm-linux-u-boot-fetch \
	platform/zynq/u-boot/clean:Vivado:xilinx-arm-linux-u-boot-clean \
	platform/zynq/dtc/build:Vivado:xilinx-arm-linux-dtc \
	platform/zynq/dtc/clean:Vivado:xilinx-arm-linux-dtc-clean \
	platform/zynq/initrd/build:Vivado:xilinx-arm-linux-initrd \
	platform/zynq/initrd/clean:Vivado:xilinx-arm-linux-initrd-clean \
	platform/zynq/device-tree/build:Vivado:xilinx-arm-linux-device-tree \
	platform/zynq/bootbin/build:Vivado:xilinx-arm-linux-bootbin \
	platform/zynq/bootbin/clean:Vivado:xilinx-arm-linux-bootbin-clean \
	platform/zynq/rootfs/fetch:Vivado:xilinx-arm-linux-download-rootfs \
	platform/zynq/rootfs/clean:Vivado:xilinx-arm-linux-rootfs-clean \
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
