# クロスコンパイラ環境の設定

HOST_TYPE = $(shell uname)

# Platform: linux
ifneq (,$(findstring Linux,$(HOST_TYPE)))
RSD_GCC_NATIVE = $(RSD_GCC_PATH)
RSD_ENV_NATIVE = $(RSD_ENV)
RSD_ROOT_NATIVE = $(RSD_ROOT)
endif

# Platform: cygwin
ifneq (,$(findstring CYGWIN,$(HOST_TYPE)))
RSD_GCC_NATIVE = $(shell cygpath -u "$$RSD_GCC_PATH")
RSD_ENV_NATIVE = $(shell cygpath -u "$$RSD_ENV")
RSD_ROOT_NATIVE = $(shell cygpath -u "$$RSD_ROOT")
endif

RSD_TEST_CODE_ROOT = $(RSD_ROOT_NATIVE)/Processor/Src/Verification/TestCode
RSD_TOOL_ROOT      = $(RSD_ROOT_NATIVE)/Processor/Tools
RSD_TEST_TOOL_ROOT = $(RSD_ROOT_NATIVE)/Processor/Tools/TestDriver


#
# コンパイラの設定
#
CC = $(RSD_GCC_NATIVE)/$(RSD_GCC_PREFIX)gcc
AS = $(RSD_GCC_NATIVE)/$(RSD_GCC_PREFIX)as
LD = $(RSD_GCC_NATIVE)/$(RSD_GCC_PREFIX)ld
OBJDUMP = $(RSD_GCC_NATIVE)/$(RSD_GCC_PREFIX)objdump
OBJCOPY = $(RSD_GCC_NATIVE)/$(RSD_GCC_PREFIX)objcopy
STRIP = $(RSD_GCC_NATIVE)/$(RSD_GCC_PREFIX)strip


#
# コンパイルオプションとリンクオプション
#
CFLAGS = \
	-g \
	-O3 \
	-fno-stack-protector \
	-fno-zero-initialized-in-bss \
	-ffreestanding \
	-fno-builtin \
	-nostdlib \
	-nodefaultlibs \
	-nostartfiles \
	-mstrict-align \
	-march=rv32im \

LDFLAGS= \
    -static \

LIBC =
LIBGCC = \
	-L$(RSD_GCC_NATIVE)/../lib/gcc/riscv32-unknown-elf/$(RSD_GCC_VERSION) \
	-lgcc \
	-lgcov \
	-L$(RSD_GCC_NATIVE)/../riscv32-unknown-elf/lib \
	-lm



# --------
# RSD 用スタートアップルーチンとリンカスクリプト
#
CRTOBJ = $(RSD_TEST_CODE_ROOT)/rsd-crt.o
CRTASM = $(RSD_TEST_CODE_ROOT)/rsd-crt.s
LDSCRIPT = $(RSD_TEST_CODE_ROOT)/rsd-ld.script

# ROM の先頭 0x1000 までに結合するためのダミーの ROM
# 中身が 0 のバイナリを作成する
DUMMY_ROM = $(RSD_TEST_CODE_ROOT)/dummy_rom.bin

# スタートアップルーチンのコンパイル
$(CRTOBJ): $(CRTASM) $(DUMMY_ROM) $(RSD_TEST_CODE_ROOT)/Asm/rsd-asm-macros.h
	$(CC) $(CFLAGS) -x assembler-with-cpp -o $@ -c $<

$(DUMMY_ROM):
	head -c $(ROM_PADDING_SIZE) /dev/zero > $(DUMMY_ROM)

# --------
# テストコードのバイナリ設定t

# 生成するバイナリのアドレス
# ROM, RAM の順に結合する
# RAM は ELF 内の START_ADDR から END_ADDR までを取り出して作成する
ROM_PADDING_SIZE = 4096 # 0x1000
ROM_START_ADDR = 0x00001000
ROM_END_ADDR   = 0x00010000
RAM_START_ADDR = 0x80000000
RAM_END_ADDR   = 0x80018000

ROM_SIZE   = 65536      # 0x1000 + (0x10000 - 0x1000) = 0x10000
RAM_SIZE   = 0x18000

# BIN_SIZE は ROM+CODE の合計サイズ
BIN_SIZE   = 0x28000

# .text* と .rodata* だけ ROM として取り出すコマンド
# （.text* は，名前が .text から始まるセクションすべて）
# 詳細は ../../rsd-ld.script を参照
ROM_COPY = $(OBJCOPY) \
		-O binary --strip-all --strip-debug \
		--only-section .text* \
		--only-section .rodata* \
		--only-section .eh_frame* \
		--only-section .srodata* \
		--set-start=$(ROM_START_ADDR) \
		--pad-to=$(ROM_END_ADDR) \

# それ以外は RAM へ
RAM_COPY = $(OBJCOPY) \
		-O binary --strip-all --strip-debug \
		--remove-section .text* \
		--remove-section .rodata* \
		--remove-section .eh_frame* \
		--remove-section .srodata* \
		--set-start=$(RAM_START_ADDR) \
		--pad-to=$(RAM_END_ADDR) \

# --------
# テストコード生成ツール
#

# バイナリファイルを、RSDのシミュレーションで使える形式のhexに変換
BIN_TO_HEX = \
	python $(RSD_TEST_TOOL_ROOT)/BinaryToHex.py

HEX_TO_IHEX = \
  python3 $(RSD_TOOL_ROOT)/Hex2IHex/hex2ihex.py


# --------
# このファイルをインクルードする Makefile 内でデフォルトターゲットを
# 指定するためにデフォルトターゲットをリセット
.DEFAULT_GOAL =

