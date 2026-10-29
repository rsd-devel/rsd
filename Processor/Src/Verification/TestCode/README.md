# Tests

Run the commands below from `Processor/Src`. For program tests, first build the
Verilator simulator, then run the basic tests:

```sh
make -j"$(nproc)" -f Makefile.verilator.mk
make -f Makefile.verilator.mk test-1
```

`test-1` also builds the assembly and C test HEX files as needed.
Use `test-clean-basic` to remove their generated files.
For `cfg.xml`, execution limits, and result checking, see the
[TestDriver documentation](../../../Tools/TestDriver/README.md).

## Choosing a test suite

| Target | What it checks | Preparation |
| --- | --- | --- |
| `test-all` | `test-1` (ASM/C) and `test-2` (CoreMark/Dhrystone) | Build the Verilator model; fetch the benchmark sources below. |
| `test-ex` | ACT4 and Zephyr | Build the Verilator model; run each suite's fetch/setup below. |
| `test-unit` | Nine RTL unit tests: RAMs, queue pointers, free list, dividers, memory and caches | Install ModelSim/QuestaSim and set `RSD_QUESTASIM_PATH` to its executable directory. |
| `test-tools` | TestDriver and the DevContainer launcher | Use the dev container or a Linux host with Python 3, Bash and `flock`. |

```sh
make -j4 -f Makefile.verilator.mk test-all
make -j4 -f Makefile.verilator.mk test-ex
make -j4 test-unit
make -j2 -f Makefile.verilator.mk test-tools
```

`test-all` covers the normal program tests; request the other groups explicitly.
Specify `test-all test-ex` together to run both program-test groups.
They build HEX files as needed. `test-build` builds the normal test programs;
`test-build-ex` builds ACT4 and Zephyr. `test-clean` cleans both groups while
preserving downloaded sources and installed dependencies.

`test-unit` uses the ModelSim/QuestaSim Makefile and builds its own testbenches.
Select one unit with, for example, `make test-unit-Divider`.
`test-tools` uses stubs for the launcher and runner CLI. Its simulation-limit
checks also run when the Verilator binary and Fibonacci HEX exist; otherwise
those checks are reported as skipped. It does not build models, download tools
or start containers. The [TestDriver documentation](../../../Tools/TestDriver/README.md)
lists the individual tool-test targets.

For synthesized cores, build the test HEX first (for example, with
`make -f Makefile.verilator.mk test-build-basic`). Then use
`make -f Makefile.vivado.mk test-post-synthesis` for Vivado + XSim, or
`make -f Makefile.synplify.mk test-post-synthesis` for Synplify + XSim.
`make -f Makefile.vcs.mk test-post-implementation` uses Vivado placement/routing
and VCS with SDF delays. These require separately installed CAD tools and
`RSD_VIVADO_BIN`; they default to HelloWorld and accept `TEST_CODE` to select a
UART-checked program. They are separate from the four groups above.

TestDriver leaves each program's simulator log and UART output in its test
directory. ACT4 also writes `riscv-arch-test/Build/summary.log` for the selected
cases. For benchmark scores, use the `bench-*` targets described below.

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

GCC's libc builtins are enabled by default for Dhrystone. To disable them, use:

```sh
make -f Makefile.verilator.mk test-Dhrystone DHRYSTONE_BUILTINS=0
```

The default is `DHRYSTONE_BUILTINS=1`, which appends `-fbuiltin`
after the shared freestanding flags, while retaining the RV32IM bare-metal
environment and separate compilation. GCC may expand constant-size string and
memory operations inline; calls it cannot expand still use the linked libc.
With GCC 14.2.0, Dhrystone's constant-string `strcpy` calls are expanded, while
the `strcmp` in `Func_2` still calls picolibc. Its structure copies already use
inline loads/stores. Changing this option automatically rebuilds the objects.
Report the builtin setting with any performance measurements.

`test-clean-Dhrystone` preserves the checkout and test inputs;
clean before changing compilers or build flags.

## Cycle measurements

```sh
make -f Makefile.verilator.mk bench-Coremark
make -f Makefile.verilator.mk bench-Dhrystone
# Compare Dhrystone without GCC libc builtins:
make -f Makefile.verilator.mk bench-Dhrystone DHRYSTONE_BUILTINS=0
# Short run for comparison:
make -f Makefile.verilator.mk bench-Dhrystone DHRYSTONE_BENCH_ITERATIONS=100
```

These targets build with `BENCHMARK=1`, retain the normal result checks, and
append counter measurements to the UART output. Only after validation,
TestDriver prints `CoreMark/MHz = iterations * 1000000 / cycles` or
`DMIPS/MHz = iterations * 1000000 / (cycles * 1757)`.
The measured interval covers the existing loop timing hooks, excluding startup,
initialization, result checking and UART output. CSR timing overhead is included.

These are short simulation estimates: one CoreMark iteration or 2000 Dhrystone
iterations, starting from reset. `DHRYSTONE_BENCH_ITERATIONS` changes the latter;
changing it automatically rebuilds the benchmark. Normal `test-Dhrystone`
still uses 100 iterations. The benchmark instruction budget defaults to
2000000; set `MAX_TEST_INSTRUCTIONS` when requesting a longer run.
They do not meet the minimum-duration rules for
published benchmark scores. The upstream synthetic timing remains solely for
functional checks; the estimates use only the separate real cycle counts.
RSD's 32-bit counter requires intervals shorter than `2^32` cycles.

Dhrystone measures `mcycle` and reports the iteration count with the cycle count.
Make passes the same iteration count to GCC and TestDriver. GCC builtins and
8-byte function/loop alignment are set explicitly for Dhrystone because both
strongly affect its score. Code/data placement can still affect performance;
report the compiler version and build settings when comparing measurements.

Run benchmark and normal test modes separately: they reuse the same output
directories. Mode changes automatically rebuild; normal `test-*` targets restore
`BENCHMARK=0` and the original exact UART comparison. `test-all` does not run
the benchmark targets.

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

The default integer/privileged subset runs 70 cases: I (39), M (8), Zaamo (9),
Zalrsc (2), Zba (3), Zicond (2), Zicsr (6), and the generated M-mode
`ExceptionsSm-00.S`. A is split into Zaamo (AMO) and Zalrsc (LR/SC) in upstream.
Zba and Zicond are included only when their `RSD_ENABLE_ZBA` / `RSD_ENABLE_ZICOND`
defines are enabled in `RSD_SRC_CFG`; disabled extensions reject explicit selection.
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
make -f Makefile.verilator.mk test-riscv-arch-test ACT_EXTENSIONS=M,Zaamo,Zalrsc,Zba,Zicond
make -j16 -f Makefile.verilator.mk test-riscv-arch-test ACT_EXTENSIONS=F
make -f Makefile.verilator.mk test-riscv-arch-test ACT_TESTS="I-addi-00 I-sub-00"
```

Only the selected cases are built and run; unknown selections fail.
PC-based termination is disabled because the LED
exposes only the low 16 bits. Each case runs to its instruction budget, then
TestDriver requires `a0 = 0` and the exact ACT4 UART pass message for that filename.
The build generates each `serial.ref.txt`; no-commit limits detect stalls.
Successful cases wait in their termination loop until the budget is reached.
Integer/CSR cases have a 20,000-instruction budget, SC and FP cases have 50,000,
and the exception case has 100,000 for trap-handler work;
all use a 500-cycle no-commit limit.
ACT4 prints failures, including the test number, instruction, approximate PC,
actual value and expected value, to
`Build/Cases/<suite>/<test>/serial.out.txt`. The exception case checks ECALL,
EBREAK, illegal instructions, and misaligned branch/jump/load/store traps in M-mode.
The current RTL passes all 70 integer/privileged cases, including `mepc` bit 1 readback and
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
`test-ex` includes this suite; `test-build-ex` builds it, and `test-clean` also
removes its generated files. Run the fetch/setup steps above before `test-ex`
or `test-build-ex`.
`test-clean-riscv-arch-test` removes generated tests and keeps the installed tools.
