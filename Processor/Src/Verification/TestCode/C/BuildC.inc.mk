# 各ディレクトリ内の Makefile から include して使用する
# それぞれの Makefile では XCFLAGS と SRCS を設定する


# クロスコンパイル環境の読み込み
include ../../Makefile.inc

OBJS = $(SRCS:.c=.o)

all: code.hex

%.o: %.c Makefile
	$(CC) $(CFLAGS) $(XCFLAGS) -o $@ -c $<


# LD の引数の順にアドレス空間に配置されるため，
# CRTOBJ は必ず先頭に置く必要がある
# また，$(LIBGCC) $(LIBC) -T$(LDSCRIPT) $(LDFLAGS) は
# $(OBJS) が依存しているためその後ろに置く必要がある．
code.elf: $(OBJS) $(CRTOBJ) $(LDOBJ) Makefile
	$(LD) -o code.elf $(CRTOBJ) $(LDOBJ) $(OBJS) $(LIBGCC) $(LIBC) -T$(LDSCRIPT) $(LDFLAGS)

# ELF から必要なセクションを取り出した code.rom.bin を作る
# cat を使って，先頭 4KB のダミー，ROM の順に結合
# ダミーは ROM が 0x1000 がはじまるため
code.bin: code.elf $(DUMMY_ROM)
	$(OBJDUMP) -D $< > $(basename $<).dump	# for debug
	$(ROM_COPY) $< $(basename $<).rom.bin
	cat $(DUMMY_ROM) $(basename $<).rom.bin > $@	

code.hex: code.bin
	$(BIN_TO_HEX) code.bin $@ $(BIN_SIZE)



clean:
	rm $(OBJS) code.hex code.dump code.bin code.rom.bin code.elf -f
	
