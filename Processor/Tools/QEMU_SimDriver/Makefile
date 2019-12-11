# テストコードとシミュレーション命令数を指定

MAX_TEST_CYCLES = 5000000
TEST_CODE = ./Testbench/Coremark

QEMU_LOG_FILE = QEMU.log
QEMU_REG_CSV_FILE = QEMU_Register.csv

# -------------------------------
# QEMU Dump : Run QEMU simulation and dump values of register files for each instruction.
#             It need to set the QEMU and GDB path.
QEMU = /opt/riscv-qemu/bin/qemu-riscv32
GDB = /opt/gcc/riscv/7.1.0/bin/riscv32-unknown-elf-gdb

QEMU_SIM_ELF = $(addsuffix /code.elf,$(TEST_CODE))
GDB_COMMAND_FILE = ./GDB_CommandFile
GDB_COMMAND_FILE_GENERATOR = ./GDB_CommandFileGenerator.py
QEMU_LOG_CONVERTER = ./logConverter.py
QEMU_GDB_PORT_NUM = 11234

qemu-dump:
	python3 $(GDB_COMMAND_FILE_GENERATOR) $(GDB_COMMAND_FILE) $(MAX_TEST_CYCLES) $(QEMU_GDB_PORT_NUM)
	$(QEMU) -g $(QEMU_GDB_PORT_NUM) $(QEMU_SIM_ELF) &
	$(GDB) $(QEMU_SIM_ELF) -x $(GDB_COMMAND_FILE) > $(QEMU_LOG_FILE)
	python3 $(QEMU_LOG_CONVERTER) $(QEMU_LOG_FILE) $(QEMU_REG_CSV_FILE)
