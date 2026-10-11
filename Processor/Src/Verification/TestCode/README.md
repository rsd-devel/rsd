# Test programs

Run the commands below from `Processor/Src`. Build the simulator before running tests.

```sh
make -j"$(nproc)" -f Makefile.verilator.mk test-build-basic
make -f Makefile.verilator.mk test-1
```

`test-1` also builds the assembly and C test HEX files as needed.
Use `test-clean-basic` to remove their generated files.
For `cfg.xml`, execution limits, and result checking, see the
[TestDriver documentation](../../../Tools/TestDriver/README.md).

## FP test selection

`RSD_MARCH_FP_PIPE` in [CoreSources.inc.mk](../../Makefiles/CoreSources.inc.mk) enables
the assembly and C FP tests in `test-1`. Without it, basic builds omit FP
tests and use `rv32ima` instead of `rv32imaf`; explicitly requesting an FP
test fails. When changing the configuration, clean and rebuild both the
simulator and test programs (`make -f Makefile.verilator.mk clean test-clean-basic`,
then rebuild with the same `RSD_SRC_CFG` used to run the tests).

## CoreMark

```sh
make -f Makefile.verilator.mk test-fetch-Coremark
make -j"$(nproc)" -f Makefile.verilator.mk test-build-Coremark
make -f Makefile.verilator.mk test-Coremark test-Coremark_for_RV32I
```

The fetch target checks out the public `eembc/coremark` repository at the commit
pinned in [Coremark/Makefile](Coremark/Makefile), under its `External/`
directory. Builds use this checkout without network access or `RSD_ENV`.
The test targets also build their HEX and serial references as needed.
RV32IM and RV32I builds keep separate objects, including startup code, and select
matching GCC runtime libraries. Both run without an FP pipeline.

These are one-iteration functional tests with the original synthetic 10-tick
timing; their printed timing is not a performance measurement. Fixed CRC values
and complete serial output validate the result. Only the compiler version in the
reference is filled in during the build. Instruction budgets allow about twice
the measured work; no-commit waits are limited to 500 cycles.

`test-clean-Coremark` removes generated files and preserves `External/` and the
test configurations. Clean before changing compilers or build flags.
`Coremark_for_Synthesis` is outside this simulation-test migration.

## Dhrystone

```sh
make -f Makefile.verilator.mk test-fetch-Dhrystone
make -j"$(nproc)" -f Makefile.verilator.mk test-build-Dhrystone
make -f Makefile.verilator.mk test-Dhrystone
```

The fetch target checks out [SiFive's Dhrystone C 2.1](https://github.com/sifive/benchmark-dhrystone)
under `Dhrystone/External/`, at the commit pinned in
[Dhrystone/Makefile](Dhrystone/Makefile). Builds need neither network access nor
`RSD_ENV`. The test target also builds its HEX as needed.

The RSD port runs 100 iterations, as the previous test did, using the downloaded
source without patches. Dedicated `malloc`, `time`, and `printf` functions supply
two static records, synthetic zero time, and final-result checking. Six local
values are checked through the original final report; globals are checked
directly, with full string comparisons. Missing local reports also fail the test.
This is an RV32IM functional test, without a timing score or an FP pipeline
requirement. Success requires a zero return value and the complete serial
reference. The instruction budget allows about twice the measured work;
no-commit waits are limited to 500 cycles.
`test-clean-Dhrystone` preserves the checkout and test inputs;
clean before changing compilers or build flags. The contest variant is outside
this migration.

## Zephyr

```sh
make -f Makefile.verilator.mk test-fetch-Zephyr
make -f Makefile.verilator.mk test-setup-Zephyr
make -f Makefile.verilator.mk test-Zephyr
```

The [Zephyr Makefile](Zephyr/Makefile) pins public Zephyr 4.4.0 under
`Zephyr/External/zephyr`; its Python environment and outputs stay under
`Zephyr/Build/`. HelloWorld, Philosophers and Synchronization use the unmodified
upstream samples, built with RSD's out-of-tree board/SoC, Ubuntu's RISC-V GCC
and Zephyr's minimal libc. No `RSD_ENV`, west, SDK or external modules are needed.
The dev container provides CMake, Ninja, gperf and the devicetree compiler.
Fetch/setup require network access; builds and tests do not download anything.
`test-Zephyr` runs all three; individual targets include `test-Zephyr-Philosophers`
and `test-Zephyr-Synchronization`. Each runs through TestDriver to its instruction
budget with the normal no-commit limit. HelloWorld requires the exact UART greeting.
Synchronization uses TestDriver's `--serial-prefix` to require the first four
A/B/A/B greetings, allowing subsequent output and an incomplete final UART line.
Philosophers uses [CheckOutput.py](Zephyr/CheckOutput.py) after TestDriver to check
fork states and two eating/thinking rounds per philosopher after sleep/wakeup,
allowing mutex priority inheritance and interleaved UART fragments. Its check
ignores the final incomplete UART line and rejects kernel error messages.
The simulation board uses a virtual 1 MHz clock to shorten sample sleeps without
changing the RTL or upstream source. Philosophers uses upstream `DEBUG_PRINTF=1`
to disable terminal cursor control and `CONFIG_PRINTK_SYNC=y` to synchronize each
print call. Zephyr Dhrystone remains outside this migration.
`test-clean-Zephyr` preserves the downloaded source and Python environment.

## riscv-arch-test (ACT4)

In the Ubuntu 26.04 dev container, explicitly fetch the source and install its dependencies:

```sh
make -f Makefile.verilator.mk test-fetch-riscv-arch-test
make -f Makefile.verilator.mk test-setup-riscv-arch-test
make -f Makefile.verilator.mk test-check-riscv-arch-test
make -j"$(nproc)" -f Makefile.verilator.mk
make -j16 -f Makefile.verilator.mk test-riscv-arch-test
```

The [ACT4 Makefile](riscv-arch-test/Makefile) pins the upstream commit, Bundler,
and Sail release. Sources are checked out under `riscv-arch-test/External/`;
its Python/Ruby environments, download caches, and checksum-verified Sail binary stay
under `riscv-arch-test/Build/`. Setup uses Ubuntu's Python, Ruby and LLVM 22
without building a compiler or installing mise/uv. Fetch and setup need network
access; the check target uses the installed tools without downloads.
UDB's regenerated architecture data uses `/tmp/rsd-arch-test-<uid>/data/` inside
the container because its read-only exclusive locks fail on NFS.

The default integer/privileged subset runs 46 cases: 39 unmodified upstream `rv32i/I/*.S`
files, six `rv32i/Zicsr/*.S` files and the generated M-mode `ExceptionsSm-00.S`.
F is temporarily opt-in while the remaining RTL fixes are deferred. With
`RSD_HAS_FP=1`, select it using `ACT_EXTENSIONS=F`: the pinned generator divides
the upstream testplan into 281 files, targeting 250 testcases per ELF to fit
RSD's existing RAM layout. All coverpoints are retained, without upstream patches.
FP-disabled configurations exclude F and reject explicit F selections.
The pinned `testgen` generates exception sources under `Build/Generated/`;
only the M-mode case is selected, without its S/U-mode delegation variants.
`test-build-riscv-arch-test` builds them without downloads: ACT4 compiles
a signature ELF, runs Sail to obtain expected values, and embeds those values
in a self-checking ELF. The RSD adapter supplies the reset entry, UART output
and termination; the HEX includes ROM and RAM contents. Generated tests and
simulation output stay under `riscv-arch-test/Build/`.
The larger cases execute from RAM.

`test-riscv-arch-test` runs all selected cases through the normal TestDriver,
with a fresh simulator process for each. Make's `-j` controls Verilator test
parallelism (`-j16` runs up to 16 cases, `-j1` runs sequentially).
Failures do not stop the remaining cases; each case has a `result.log`, and
`Build/summary.log` lists all results in test-name order after execution finishes.
Any failure makes the command fail. Vivado retains sequential execution.
Narrow the selection for debugging:

```sh
make -f Makefile.verilator.mk test-riscv-arch-test ACT_EXTENSIONS=I
make -f Makefile.verilator.mk test-riscv-arch-test ACT_EXTENSIONS=Zicsr,ExceptionsSm
make -j16 -f Makefile.verilator.mk test-riscv-arch-test ACT_EXTENSIONS=F
make -f Makefile.verilator.mk test-riscv-arch-test ACT_TESTS="I-addi-00 I-sub-00"
```

Only the selected cases are built and run; unknown selections fail.
PC-based termination is disabled because the LED
exposes only the low 16 bits. Each case runs to its instruction budget, then
TestDriver requires `a0 = 0` and the exact ACT4 UART pass message for that filename.
The build generates each `serial.ref.txt`; no-commit limits detect stalls.
Successful cases wait in their termination loop until the budget is reached.
Integer/CSR cases have a 20,000-instruction budget, FP cases have 50,000,
and the exception case has 100,000 for trap-handler work;
all use a 500-cycle no-commit limit.
ACT4 prints failures, including the test number, instruction, approximate PC,
actual value and expected value, to
`Build/Cases/<suite>/<test>/serial.out.txt`. The exception case checks ECALL,
EBREAK, illegal instructions, and misaligned branch/jump/load/store traps in M-mode.
The current RTL passes all 46 integer/privileged cases, including `mepc` bit 1 readback and
`mtval = 0` for illegal instructions. RSD does not retain instruction encodings
for trap values; the ACT4 and Sail configurations match this choice.
Any case failure makes the command fail after collecting all results.
The F suite currently has 99 passes and 182 failures. The first mismatch is
`fflags` in eight division/square-root files and the numerical result in 174
rounding-mode coverpoints. Addition/multiplication/FMA report NV, OF, UF and NX
under RNE; division/square root report NV, and division also reports DZ.
Other rounding modes and division/square-root rounding flags need RTL work.
These failures remain visible when F is explicitly selected.
The FP reference profile enables standard `mstatus.FS` state for instruction
execution; this suite does not validate RSD's FS gating or dirty tracking.
Interrupt, S/U-mode and FENCE.I tests are outside this subset; Zifencei is
excluded. The preloaded exception handler uses
writable `mtvec`, so its setup/cleanup does not need instruction-code writes.
`test-2` and `test-all` include this suite; `test-build` and `test-clean` also use it.
Run the fetch/setup steps above before aggregate build or test targets.
`test-clean-riscv-arch-test` removes generated tests and keeps the installed tools.
