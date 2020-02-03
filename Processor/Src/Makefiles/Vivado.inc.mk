# -------------------------------

# For Vivado
VIVADO_BOARD_PROJECT = rsd
VIVADO_POST_SYNTHESIS_PROJECT = rsd_post_synthesis

VIVADO_PROJECT_ROOT = ../Project/Vivado/$(TARGET_BOARD)
VIVADO_BOARD_PROJECT_ROOT = $(VIVADO_PROJECT_ROOT)/$(VIVADO_BOARD_PROJECT)
VIVADO_POST_SYNTHESIS_PROJECT_ROOT = $(VIVADO_PROJECT_ROOT)/$(VIVADO_POST_SYNTHESIS_PROJECT)
VIVADO_BOARD_PROJECT_IMPL = $(VIVADO_BOARD_PROJECT_ROOT)/$(VIVADO_BOARD_PROJECT).runs/impl_1
VIVADO_BOARD_PROJECT_SDK = $(VIVADO_BOARD_PROJECT_ROOT)/$(VIVADO_BOARD_PROJECT).sdk
VIVADO_XSA_FILE = $(VIVADO_BOARD_PROJECT_ROOT)/design_1_wrapper.xsa
VIVADO_BIT_FILE = $(VIVADO_BOARD_PROJECT_IMPL)/design_1_wrapper.bit
VIVADO_FSBL_FILE = $(VIVADO_BOARD_PROJECT_SDK)/fsbl/Release/fsbl.elf

# Synplify用

SYNPLIFY_ROOT = ../Project/Synplify
SYNPLIFY_PROJECT_ROOT = $(SYNPLIFY_ROOT)/$(TARGET_BOARD)
SYNPLIFY_POST_SYNTHESIS_PROJECT_ROOT = $(SYNPLIFY_ROOT)/$(TARGET_BOARD)_post_synthesis

# Linux(ARM)用

# ターゲットボードを追加したらここも追加
ifeq ($(TARGET_BOARD),Zedboard)
	UBOOT_CONFIG = zynq_zed_config
	DEVICETREE_CONFIG = zynq-zed
else
	ifeq ($(TARGET_BOARD),ZC706)
		UBOOT_CONFIG = zynq_zc706_config
		DEVICETREE_CONFIG = zynq-zc706
	else
		UBOOT_CONFIG = none
		DEVICETREE_CONFIG = none
	endif
endif

KERNEL_CONFIG = xilinx_zynq_defconfig
ARM_CROSSCOMPILE = arm-linux-gnueabihf-

ARM_LINUX_ROOT = $(RSD_ARM_LINUX)
KERNEL_ROOT = $(RSD_ARM_LINUX)/linux-xlnx
UBOOT_ROOT = $(RSD_ARM_LINUX)/u-boot-xlnx
DTC_ROOT = $(RSD_ARM_LINUX)/dtc
INITRD = $(RSD_ARM_LINUX)/arm_ramdisk.image.gz
ARM_LINUX_BOOT = $(ARM_LINUX_ROOT)/boot

ARM_LINUX_SRC_ROOT = $(RSD_ROOT)/Processor/Project/Linux/ARM
KERNEL_SRC_ROOT = $(ARM_LINUX_SRC_ROOT)/linux-xlnx
UBOOT_SRC_ROOT = $(ARM_LINUX_SRC_ROOT)/u-boot-xlnx
BIF_FILE = $(ARM_LINUX_SRC_ROOT)/boot.bif
UINITRD_FILE = $(ARM_LINUX_BOOT)/uramdisk.image.gz
BIT_FILE = $(ARM_LINUX_BOOT)/boot.bin
DEVICETREE_FILE = $(ARM_LINUX_BOOT)/devicetree.dtb
FSBL_FILE = $(ARM_LINUX_BOOT)/fsbl.elf
UBOOT_FILE = $(ARM_LINUX_BOOT)/u-boot.elf
UKERNEL_FILE = $(ARM_LINUX_BOOT)/uImage

KERNEL_BRANCH = v2019.2.01
UBOOT_BRANCH = v2019.2
KERNEL_TAG = xilinx-v2019.2.01
UBOOT_TAG = xilinx-v2019.2

# -------------------------------
# Vivado : Make RSD project, run synthesis and run implementation for TARGET_BOARD.
#

VIVADO_PROJECT_FILE = $(VIVADO_BOARD_PROJECT_ROOT)/rsd.xpr
SYNPLIFY_NETLIST = $(SYNPLIFY_PROJECT_ROOT)/rsd.vm

# vivadoプロジェクトを作成して開く．すでに作成されている場合は開くのみ．
vivado: $(SYNPLIFY_NETLIST) $(VIVADO_PROJECT_FILE)
	$(RSD_VIVADO_BIN)/vivado $(VIVADO_PROJECT_FILE) &

# vivadoプロジェクトの削除
vivado-clean:
	rm -f -r $(VIVADO_BOARD_PROJECT_ROOT)
	rm -f vivado*.jou
	rm -f vivado*.log
	rm -f vivado*.zip
	rm -f vivado*.str

# Do NOT use this command.
# This command is called automatically if you need.
vivado-create:
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode batch -source make_project.tcl

$(VIVADO_PROJECT_FILE):
	$(MAKE) vivado-create || $(MAKE) vivado-clean

$(SYNPLIFY_NETLIST): $(TYPES) $(TEST_MODULES) $(MODULES)
	@ echo "(Re-)build post-synthesis netlist using Synplify!"
	$(MAKE) vivado-clean
	@ exit 1

# -------------------------------
# ARM-Linux : Make fsbl, initrd, u-boot, kernel, device-tree and boot.bin for TARGET_BOARD.
#

arm-linux: $(ARM_LINUX_BOOT) $(FSBL_FILE) $(BIT_FILE)
	$(MAKE) arm-linux-u-boot
	$(MAKE) arm-linux-kernel
	$(MAKE) arm-linux-device-tree
	$(MAKE) arm-linux-bootbin

arm-linux-clean:
	$(MAKE) arm-linux-kernel-clean
	$(MAKE) arm-linux-u-boot-clean
	$(MAKE) arm-linux-initrd-clean
	$(MAKE) arm-linux-bootbin-clean

# Do NOT use this command.
arm-linux-clone-all: $(ARM_LINUX_ROOT) $(KERNEL_ROOT) $(UBOOT_ROOT) $(DTC_ROOT)/dtc $(INITRD) $(ARM_LINUX_BOOT)
	@echo "All repos have been already cloned."

$(ARM_LINUX_ROOT):
	mkdir $(ARM_LINUX_ROOT)

$(KERNEL_ROOT):
	$(MAKE) arm-linux-kernel-fetch; \
	cd $(KERNEL_ROOT); \
	patch -p1 < $(KERNEL_SRC_ROOT)/linux-xlnx.rsd.diff || $(MAKE) arm-linux-kernel-clean

# Do NOT use this command.
arm-linux-kernel-fetch:
	git clone https://github.com/Xilinx/linux-xlnx.git $(KERNEL_ROOT)
	@cd $(KERNEL_ROOT); \
	git checkout -b $(KERNEL_BRANCH) refs/tags/$(KERNEL_TAG)

# Do NOT use this command.
arm-linux-kernel-clean:
	rm -f -r $(KERNEL_ROOT)

$(UBOOT_ROOT):
	$(MAKE) arm-linux-u-boot-fetch; \
	cd $(UBOOT_ROOT); \
	patch -p1 < $(UBOOT_SRC_ROOT)/u-boot-xlnx.rsd.diff || $(MAKE) arm-linux-u-boot-clean

# Do NOT use this command.
arm-linux-u-boot-fetch:
	git clone https://github.com/Xilinx/u-boot-xlnx.git $(UBOOT_ROOT)
	@cd $(UBOOT_ROOT); \
	git checkout -b $(UBOOT_BRANCH) refs/tags/$(UBOOT_TAG)

# Do NOT use this command.
arm-linux-u-boot-clean:
	rm -f -r $(UBOOT_ROOT)

$(DTC_ROOT)/dtc:
	$(MAKE) arm-linux-dtc || $(MAKE) arm-linux-dtc-clean

# Do NOT use this command.
arm-linux-dtc:
	git clone https://git.kernel.org/pub/scm/utils/dtc/dtc.git $(DTC_ROOT)
	@cd $(DTC_ROOT); \
	$(MAKE) CC=gcc CXX=g++

# Do NOT use this command.
arm-linux-dtc-clean:
	rm -f -r $(DTC_ROOT)

$(INITRD):
	wget -N -P $(ARM_LINUX_ROOT) http://www.wiki.xilinx.com/file/view/arm_ramdisk.image.gz/419243558/arm_ramdisk.image.gz

$(ARM_LINUX_BOOT):
	mkdir $(ARM_LINUX_BOOT)

# Do NOT use this command.
arm-linux-all:
	$(MAKE) arm-linux-fsbl
	$(MAKE) arm-linux-u-boot
	$(MAKE) arm-linux-initrd
	$(MAKE) arm-linux-kernel
	$(MAKE) arm-linux-bitstream
	$(MAKE) arm-linux-bootbin

$(FSBL_FILE): $(VIVADO_FSBL_FILE)
	cp $(VIVADO_FSBL_FILE) $(ARM_LINUX_BOOT)/fsbl.elf

$(VIVADO_FSBL_FILE): $(VIVADO_XSA_FILE)
	xsct $(VIVADO_PROJECT_ROOT)/make_fsbl.tcl

$(VIVADO_XSA_FILE): $(VIVADO_BIT_FILE)
#	$(RSD_VIVADO_BIN)/vivado -mode batch -source $(VIVADO_PROJECT_ROOT)/export_xsa.tcl
#	cp $(VIVADO_BOARD_PROJECT_IMPL)/design_1_wrapper.sysdef $(VIVADO_XSA_FILE)
#	@echo "(Re-)build hdf using Vivado!"
#	exit 1

$(UBOOT_FILE): $(UBOOT_ROOT)
	$(MAKE) arm-linux-u-boot

# Do NOT use this command.
arm-linux-u-boot: $(UBOOT_ROOT)
	cd $(UBOOT_ROOT); \
	$(MAKE) $(UBOOT_CONFIG) CROSS_COMPILE=$(ARM_CROSSCOMPILE) -j4; \
	$(MAKE) CROSS_COMPILE=$(ARM_CROSSCOMPILE) -j4; \
	cp $(UBOOT_ROOT)/u-boot $(ARM_LINUX_BOOT)/u-boot.elf

$(UINITRD_FILE): $(UBOOT_FILE) $(INITRD)
	$(MAKE) arm-linux-initrd

# Do NOT use this command.
arm-linux-initrd: $(INITRD)
	$(UBOOT_ROOT)/tools/mkimage -A arm -T ramdisk -C gzip -d $(INITRD) $(ARM_LINUX_BOOT)/uramdisk.image.gz

# Do NOT use this command.
arm-linux-initrd-clean:
	rm -f $(ARM_LINUX_BOOT)/uramdisk.image.gz
	rm -f $(INITRD)

$(UKERNEL_FILE):
	$(MAKE) arm-linux-kernel

# Do NOT use this command.
arm-linux-kernel: $(KERNEL_ROOT)
	cd $(KERNEL_ROOT); \
	$(MAKE) ARCH=arm CROSS_COMPILE=$(ARM_CROSSCOMPILE) $(KERNEL_CONFIG) -j4; \
	$(MAKE) ARCH=arm CROSS_COMPILE=$(ARM_CROSSCOMPILE) UIMAGE_LOADADDR=0x8000 uImage -j4
	cp $(KERNEL_ROOT)/arch/arm/boot/uImage $(ARM_LINUX_BOOT)
	cp $(ARM_LINUX_BOOT)/uImage $(ARM_LINUX_BOOT)/uImage.bin

$(DEVICETREE_FILE): $(UKERNEL_FILE)
	$(MAKE) arm-linux-device-tree

# Do NOT use this command.
arm-linux-device-tree: $(UKERNEL_FILE)
	cd $(KERNEL_ROOT); \
	$(MAKE) ARCH=arm CROSS_COMPILE=$(ARM_CROSSCOMPILE) $(DEVICETREE_CONFIG).dtb
	cp $(KERNEL_ROOT)/arch/arm/boot/dts/zynq-zed.dtb $(ARM_LINUX_BOOT)/devicetree.dtb

$(BIT_FILE): $(VIVADO_BIT_FILE)
	cp $(VIVADO_BIT_FILE) $(ARM_LINUX_BOOT)/boot.bit

$(VIVADO_BIT_FILE): $(SYNPLIFY_NETLIST) $(VIVADO_PROJECT_FILE)
	$(RSD_VIVADO_BIN)/vivado -mode batch -source $(VIVADO_PROJECT_ROOT)/make_bitstream.tcl

# Do NOT use this command.
arm-linux-bootbin:
	cd $(ARM_LINUX_BOOT); \
	bootgen -w -image $(BIF_FILE) -o i boot.bin

# Do NOT use this command.
arm-linux-bootbin-clean:
	rm -r -f $(ARM_LINUX_BOOT)
