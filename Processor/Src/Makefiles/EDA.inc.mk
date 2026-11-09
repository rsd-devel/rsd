# Public target:backend makefile:backend target. Explicit phony targets let
# standard bash-completion show one slash-separated level at a time.
# Submakes isolate each tool's variables, defaults, and internal target names.
RSD_EDA_TARGETS := \
	vivado/build:Vivado:vivado-synthesis \
	vivado/open:Vivado:vivado \
	vivado/clean:Vivado:vivado-clean \
	vivado/post-synthesis/build:Vivado:post-synthesis-build \
	vivado/post-synthesis/test:Vivado:test-post-synthesis \
	vivado/post-synthesis/clean:Vivado:post-synthesis-clean \
	vivado/post-synthesis/open:Vivado:post-synthesis-open \
	vivado/post-synthesis/timing/test:Vivado:post-synthesis-timing \
	vivado/post-synthesis/timing/run:Vivado:post-synthesis-timing-run \
	vivado/post-synthesis/timing/gui:Vivado:post-synthesis-timing-run-gui \
	vivado/post-synthesis/timing/kanata:Vivado:post-synthesis-timing-kanata \
	vivado/post-implementation/build:Vivado:post-implementation-build \
	vivado/post-implementation/test:Vivado:post-implementation \
	vivado/post-implementation/run:Vivado:post-implementation-run \
	vivado/post-implementation/gui:Vivado:post-implementation-run-gui \
	vivado/post-implementation/kanata:Vivado:post-implementation-kanata \
	vivado/post-implementation/timing/test:Vivado:post-implementation-timing \
	vivado/post-implementation/timing/run:Vivado:post-implementation-timing-run \
	vivado/post-implementation/timing/gui:Vivado:post-implementation-timing-run-gui \
	vivado/post-implementation/timing/kanata:Vivado:post-implementation-timing-kanata \
	vivado/arm-linux/build:Vivado:xilinx-arm-linux \
	vivado/arm-linux/all:Vivado:xilinx-arm-linux-all \
	vivado/arm-linux/clean:Vivado:xilinx-arm-linux-clean \
	vivado/arm-linux/fetch:Vivado:xilinx-arm-linux-clone-all \
	vivado/arm-linux/kernel/build:Vivado:xilinx-arm-linux-kernel \
	vivado/arm-linux/kernel/fetch:Vivado:xilinx-arm-linux-kernel-fetch \
	vivado/arm-linux/kernel/clean:Vivado:xilinx-arm-linux-kernel-clean \
	vivado/arm-linux/u-boot/build:Vivado:xilinx-arm-linux-u-boot \
	vivado/arm-linux/u-boot/fetch:Vivado:xilinx-arm-linux-u-boot-fetch \
	vivado/arm-linux/u-boot/clean:Vivado:xilinx-arm-linux-u-boot-clean \
	vivado/arm-linux/dtc/build:Vivado:xilinx-arm-linux-dtc \
	vivado/arm-linux/dtc/clean:Vivado:xilinx-arm-linux-dtc-clean \
	vivado/arm-linux/initrd/build:Vivado:xilinx-arm-linux-initrd \
	vivado/arm-linux/initrd/clean:Vivado:xilinx-arm-linux-initrd-clean \
	vivado/arm-linux/device-tree/build:Vivado:xilinx-arm-linux-device-tree \
	vivado/arm-linux/bootbin/build:Vivado:xilinx-arm-linux-bootbin \
	vivado/arm-linux/bootbin/clean:Vivado:xilinx-arm-linux-bootbin-clean \
	vivado/arm-linux/rootfs/fetch:Vivado:xilinx-arm-linux-download-rootfs \
	vivado/arm-linux/rootfs/clean:Vivado:xilinx-arm-linux-rootfs-clean \
	synplify/build:Synplify:vivado-synthesis \
	synplify/open:Synplify:vivado \
	synplify/clean:Synplify:vivado-clean \
	synplify/post-synthesis/build:Synplify:post-synthesis-build \
	synplify/post-synthesis/test:Synplify:test-post-synthesis \
	synplify/post-synthesis/clean:Synplify:post-synthesis-clean \
	vcs/post-implementation/build:VCS:post-implementation-build \
	vcs/post-implementation/test:VCS:test-post-implementation \
	vcs/post-implementation/run:VCS:post-implementation-run

define RSD_EDA_FORWARD
.PHONY: $(word 1,$(1))
$(word 1,$(1)):
	$$(MAKE) -f Makefiles/$(word 2,$(1)).mk $(word 3,$(1))
endef
$(foreach target,$(RSD_EDA_TARGETS),$(eval $(call RSD_EDA_FORWARD,$(subst :, ,$(target)))))
