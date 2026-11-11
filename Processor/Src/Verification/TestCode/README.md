# Tests

Run the commands below from `Processor/Src`. For program tests, first build the
Verilator simulator, then run the basic tests:

```sh
make -j"$(nproc)"
make test/level-1/run
```

`test/level-1/run` also builds the assembly and C test HEX files as needed.
Use `test/level-1/clean` to remove their generated files. Individual cases follow
the source directories, for example `test/Asm/FP/run` and `test/C/HelloWorld/run`.
Use `test/Asm/build` or `test/C/build` to build one source group.
Build tools are checked when rebuilding is necessary, so up-to-date artifacts
can be reused without the cross-compiler or external test build environments.
Keep the source checkout and intermediate files: copying only HEX files does
not preserve Make's dependency graph. If inputs changed, rebuild tools are required.
For `cfg.xml`, execution limits, and result checking, see the
[TestDriver documentation](../../../Tools/TestDriver/README.md).

## Choosing a test suite

| Target | What it checks | Preparation |
| --- | --- | --- |
| `test/all/run` | `test/level-1/run` (ASM/C) and `test/level-2/run` (CoreMark/Dhrystone) | Build the Verilator model; fetch the benchmark sources below. |
| `test/ex/run` | ACT4 and Zephyr | Build the Verilator model; run each suite's fetch/setup below. |
| `test/unit/run` | RTL unit tests: RAMs, queue pointers, free list, dividers, memory and caches | Use the dev container (Verilator), or select ModelSim/QuestaSim as described below. |
| `test/tools/run` | TestDriver and the DevContainer launcher | Use the dev container or a Linux host with Python 3, Bash and `flock`. |

```sh
make -j4 test/all/run
make -j4 test/ex/run
make -j4 test/unit/run
make -j2 test/tools/run
```

`test/all/run` covers the normal program tests; request the other groups explicitly.
Specify `test/all/run test/ex/run` together to run both program-test groups.
They build HEX files as needed. `test/all/build` builds the normal test programs;
`test/level-1/build` builds ASM/C, `test/level-2/build` builds CoreMark/Dhrystone,
and `test/ex/build` builds ACT4 and Zephyr. `test/clean` cleans both groups while
preserving downloaded sources and installed dependencies.

The default core simulator is Verilator. Use `SIM=modelsim` or `SIM=xsim`
for both the build and program-test commands to select another simulator.
`test/unit/run` builds and runs its own testbenches with Verilator by default.
Use `make SIM=modelsim test/unit/run` for ModelSim/QuestaSim, setting
`RSD_QUESTASIM_PATH` to its executable directory. Units support `verilator` and
`modelsim`; `UNIT_SIM` selects them independently (for example,
`make SIM=xsim UNIT_SIM=verilator test/unit/run`). `UNIT_PROJECT_WORK` overrides
their output directory. ModelSim/QuestaSim also checks unknown (`X`) values
that Verilator's two-state simulation cannot detect.
Select one unit with, for example, `make test/unit/Divider/run`.
`test/tools/run` also checks configuration generation (`test/tools/Config/run`) and
uses stubs for the launcher and runner CLI. Its simulation-limit
checks also run when the Verilator binary and Fibonacci HEX exist; otherwise
those checks are reported as skipped. It does not build models, download tools
or start containers. The [TestDriver documentation](../../../Tools/TestDriver/README.md)
lists the individual tool-test targets.

For synthesized cores, build the test HEX first (for example, with
`make test/level-1/build`). Then use
`make synth/vivado/post-synthesis/test` for Vivado + XSim, or
`make synth/synplify/post-synthesis/test` for Synplify + XSim.
`make sim/vcs/post-implementation/test` uses Vivado placement/routing
and VCS with SDF delays. These require separately installed CAD tools and
`RSD_VIVADO_BIN`; they default to HelloWorld and accept `TEST_CODE` to select a
UART-checked program. They are separate from the four groups above.

TestDriver leaves each program's simulator log and UART output in its test
directory. ACT4 also writes `riscv-arch-test/Build/summary.log` for the selected
cases. For benchmark scores, use the `bench/*/run` targets described below.

## FP test selection

`enable_fp_pipe: true` in [MicroArch.yml](../../../Config/MicroArch.yml) enables
the assembly and C FP tests in `test/level-1/run`. Setting it to `false` makes basic builds omit FP
tests and use `rv32ima` instead of `rv32imaf`; explicitly requesting an FP
test fails. When changing the configuration, clean and rebuild both the
simulator and test programs (`make clean test/level-1/clean`,
then rebuild with the same `RSD_SRC_CFG` used to run the tests).

## CFI test selection

`enable_zicfilp: true` in [MicroArch.yml](../../../Config/MicroArch.yml)
enables landing-pad protection and its `test/level-1/run` test. Set it to `false`
to build without CFI; an explicit `test/Asm/LandingPad/run` request then fails.
Clean and rebuild the simulator and basic test programs when changing this
configuration, as for FP above. The YAML settings also generate the synthesis
macros. A command-line `RSD_SRC_CFG` override affects simulation and software
builds only; omit a macro to disable it rather than defining it as `0`.

## CoreMark

```sh
make test/External/Coremark/fetch
make -j"$(nproc)" test/External/Coremark/build
make test/External/Coremark/run test/External/Coremark/Coremark_for_RV32I/run
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

`test/External/Coremark/clean` removes generated files and preserves `External/` and the
test configurations. Clean before changing compilers or build flags.
`Coremark_for_Synthesis` is outside this simulation-test migration.

## Dhrystone

```sh
make test/External/Dhrystone/fetch
make -j"$(nproc)" test/External/Dhrystone/build
make test/External/Dhrystone/run
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
make test/External/Dhrystone/run DHRYSTONE_BUILTINS=0
```

The default is `DHRYSTONE_BUILTINS=1`, which appends `-fbuiltin`
after the shared freestanding flags, while retaining the RV32IM bare-metal
environment and separate compilation. GCC may expand constant-size string and
memory operations inline; calls it cannot expand still use the linked libc.
With GCC 14.2.0, Dhrystone's constant-string `strcpy` calls are expanded, while
the `strcmp` in `Func_2` still calls picolibc. Its structure copies already use
inline loads/stores. Changing this option automatically rebuilds the objects.
Report the builtin setting with any performance measurements.

`test/External/Dhrystone/clean` preserves the checkout and test inputs;
clean before changing compilers or build flags.

## Cycle measurements

```sh
make bench/Coremark/run
make bench/Dhrystone/run
# Compare Dhrystone without GCC libc builtins:
make bench/Dhrystone/run DHRYSTONE_BUILTINS=0
# Short run for comparison:
make bench/Dhrystone/run DHRYSTONE_BENCH_ITERATIONS=100
```

These targets build with `BENCHMARK=1`, retain the normal result checks, and
append counter measurements to the UART output. Only after validation,
TestDriver prints `CoreMark/MHz = iterations * 1000000 / cycles` or
`DMIPS/MHz = iterations * 1000000 / (cycles * 1757)`.
The measured interval covers the existing loop timing hooks, excluding startup,
initialization, result checking and UART output. CSR timing overhead is included.

These are short simulation estimates: one CoreMark iteration or 2000 Dhrystone
iterations, starting from reset. `DHRYSTONE_BENCH_ITERATIONS` changes the latter;
changing it automatically rebuilds the benchmark. Normal `test/External/Dhrystone/run`
still uses 100 iterations. The benchmark instruction budget defaults to
2000000; set `MAX_TEST_INSTRUCTIONS` when requesting a longer run.
They do not meet the minimum-duration rules for
published benchmark scores. The upstream synthetic timing remains solely for
functional checks; the estimates use only the separate real cycle counts.
The measurement code reads the lower 32 bits of the 64-bit `mcycle` counter,
so measured intervals must be shorter than `2^32` cycles.

Dhrystone measures `mcycle` and reports the iteration count with the cycle count.
Make passes the same iteration count to GCC and TestDriver. GCC builtins and
8-byte function/loop alignment are set explicitly for Dhrystone because both
strongly affect its score. Code/data placement can still affect performance;
report the compiler version and build settings when comparing measurements.

Run benchmark and normal test modes separately: they reuse the same output
directories. Mode changes automatically rebuild; normal correctness-test targets restore
`BENCHMARK=0` and the original exact UART comparison. `test/all/run` does not run
the benchmark targets.

## Zephyr

```sh
make test/External/Zephyr/fetch
make test/External/Zephyr/setup
make test/External/Zephyr/run
```

The [Zephyr Makefile](Zephyr/Makefile) pins public Zephyr 4.4.0 under
`Zephyr/External/zephyr`; its Python environment and outputs stay under
`Zephyr/Build/`. HelloWorld, Philosophers and Synchronization use the unmodified
upstream samples, built with RSD's out-of-tree board/SoC, Ubuntu's RISC-V GCC
and Zephyr's minimal libc. No `RSD_ENV`, west, SDK or external modules are needed.
The dev container provides CMake, Ninja, gperf and the devicetree compiler.
Fetch/setup require network access; builds and tests do not download anything.
`test/External/Zephyr/run` runs all three; individual targets include `test/External/Zephyr/Philosophers/run`
and `test/External/Zephyr/Synchronization/run`. Each runs through TestDriver to its instruction
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
`test/External/Zephyr/clean` preserves the downloaded source and Python environment.

## riscv-arch-test (ACT4)

In the Ubuntu 26.04 dev container, explicitly fetch the source and install its dependencies:

```sh
make test/External/riscv-arch-test/fetch
make test/External/riscv-arch-test/setup
make test/External/riscv-arch-test/check
make -j"$(nproc)"
make -j16 test/External/riscv-arch-test/run
```

The [ACT4 Makefile](riscv-arch-test/Makefile) pins the upstream commit, Bundler,
and Sail release. Sources are checked out under `riscv-arch-test/External/`;
its Python/Ruby environments, download caches, and checksum-verified Sail binary stay
under `riscv-arch-test/Build/`. Setup uses Ubuntu's Python, Ruby and LLVM 22
without building a compiler or installing mise/uv. Fetch and setup need network
access; the check target uses the installed tools without downloads.
UDB's regenerated architecture data uses `/tmp/rsd-arch-test-<uid>/data/` inside
the container because its read-only exclusive locks fail on NFS.

The integer/privileged subset runs 90 cases: I (39), M (8), Zaamo (9),
Zalrsc (2), Zba (3), Zicond (2), Zicsr (6), Zifencei (1), and the generated
`ExceptionsSm`, `ExceptionsZaamo`, `ExceptionsZalrsc` (one each) and `InterruptsSm` (17).
A is split into Zaamo (AMO) and Zalrsc (LR/SC) in upstream.
Zba and Zicond are included only when their `RSD_ENABLE_ZBA` / `RSD_ENABLE_ZICOND`
defines are enabled in `RSD_SRC_CFG`; disabled extensions reject explicit selection.
F is included by default when `RSD_MARCH_FP_PIPE` is enabled, for 371 cases in
the default RTL configuration. Use `ACT_EXTENSIONS=F` to run only F: the pinned
generator divides the upstream testplan into 281 files, targeting 250 testcases
per ELF to fit RSD's existing RAM layout. All coverpoints are retained, without
upstream patches.
FP-disabled configurations exclude F and reject explicit F selections.
The pinned `testgen` generates privileged sources under `Build/Generated/`;
exception suites boot in M-mode; interrupts run from M/S/U-mode, including
S-mode delegation and external interrupts through the PLIC.
`test/External/riscv-arch-test/build` builds them without downloads: ACT4 compiles
a signature ELF, runs Sail to obtain expected values, and embeds those values
in a self-checking ELF. The RSD adapter supplies the reset entry, UART output
and termination; the HEX includes ROM and RAM contents. Generated tests and
simulation output stay under `riscv-arch-test/Build/`.
Test code and its platform helpers execute from RAM; reset code stays in ROM.

`test/External/riscv-arch-test/run` runs all selected cases through the normal TestDriver,
with a fresh simulator process for each. Make's `-j` controls Verilator test
parallelism (`-j16` runs up to 16 cases, `-j1` runs sequentially).
Failures do not stop the remaining cases; each case has a `result.log`, and
`Build/summary.log` lists all results in test-name order after execution finishes.
Any failure makes the command fail. Vivado retains sequential execution.
Narrow the selection for debugging:

```sh
make test/External/riscv-arch-test/run ACT_EXTENSIONS=I
make test/External/riscv-arch-test/run ACT_EXTENSIONS=Zicsr,ExceptionsSm
make test/External/riscv-arch-test/run ACT_EXTENSIONS=M,Zaamo,Zalrsc,Zba,Zicond
make test/External/riscv-arch-test/run ACT_EXTENSIONS=ExceptionsZaamo,ExceptionsZalrsc
make test/External/riscv-arch-test/run ACT_EXTENSIONS=InterruptsSm
make test/External/riscv-arch-test/run ACT_EXTENSIONS=Zifencei
make -j16 test/External/riscv-arch-test/run ACT_EXTENSIONS=F
make test/External/riscv-arch-test/run ACT_TESTS="I-addi-00 I-sub-00"
```

Only the selected cases are built and run; unknown selections fail.
PC-based termination is disabled because the LED
exposes only the low 16 bits. Each case runs to its instruction budget, then
TestDriver requires `a0 = 0` and the exact ACT4 UART pass message for that filename.
The build generates each `serial.ref.txt`; no-commit limits detect stalls.
Successful cases wait in their termination loop until the budget is reached.
Integer/CSR cases have a 20,000-instruction budget, SC and FP cases have 50,000,
and exception/interrupt cases have 100,000 for trap-handler work and timer waits.
Interrupt trigger and enable-priority cases use 300,000 for their larger sweeps.
The no-commit limit is 500 cycles, or 2,500 for Zifencei and privileged tests
whose trap-handler cleanup flushes dirty cache lines.
ACT4 prints failures, including the test number, instruction, approximate PC,
actual value and expected value, to
`Build/Cases/<suite>/<test>/serial.out.txt`. Exception cases check ECALL, EBREAK,
illegal instructions, and misaligned/access-fault traps for instruction fetch,
loads/stores and AMO/LR/SC. Atomic cases check destination-register preservation;
LR/SC also checks scratch memory. The existing `test/Asm/Aext/run` separately checks
memory preservation on cached/uncached AMO faults.
InterruptsSm checks MEI/MSI/MTI and SEI/SSI/STI enable masks, Direct/Vectored
entry, delegation, mixed priorities and WFI polling with a delayed timer.
Trap signatures check cause, status, pending bits and interrupt count, without
comparing asynchronous trap PCs. Priority cases are staged with a wait before
clearing requests, allowing the pipeline to drain and deliver pending interrupts.
Interrupt cases enable `EnableUART_Interrupts` in their generated `cfg.xml`.
The shared RTL testbench consumes UART DC1/DC3 (`0x11`/`0x13`) to assert/deassert
PLIC source 1; other tests retain every UART byte. The adapter configures the M/S
context and performs normal claim/complete accesses. This stimulus is simulation-only,
unavailable in post-synthesis tests or hardware; no CSR pending bits are forced.
Requests pass through module input ports to Core. The synthesis wrapper ties them
low until a board interrupt device is connected.
Zifencei checks self-modifying code in RAM, including ignored nonzero rs1/rd/funct12
fields and preservation of rd. Select `ACT_EXTENSIONS=Zifencei` to run it alone.
The CSR cases also check `mepc` bit 1 readback.
Reference settings match RSD's access-fault priority over misalignment on unmapped
addresses and `mtval = 0` for illegal instructions and instruction access faults.
Any case failure makes the command fail after collecting all results.
The F suite checks numerical results and exception flags across all five
rounding modes, including division and square root.
The FP reference profile enables standard `mstatus.FS` state for instruction
execution. The basic `Asm/CSR` test separately checks FS/SD state, FP access
while FS is Off, and dirty tracking.
The S-mode profile remains Bare-only; paging and full S-mode ISA compliance
are outside this subset.
`test/ex/run` includes this suite; `test/ex/build` builds it, and `test/clean` also
removes its generated files. Run the fetch/setup steps above before `test/ex/run`
or `test/ex/build`.
`test/External/riscv-arch-test/clean` removes generated tests and keeps the installed tools.

## Memory map

[`Processor/Config/MemoryMap.yml`](../../../Config/MemoryMap.yml) defines the RTL and shared software addresses.
The [configuration generator](../../../Tools/ConfigGenerator/ConfigGenerator.py)
generates their definitions. Make regenerates the RTL file
`../../Config/MemoryMapTypes.sv` and the software files
`rsd-memory-map.h`, `rsd-memory-map.ld`, and `rsd-memory-map.mk` in this directory
through `../../Makefiles/GenerateConfig.inc.mk`. Keep these generated files in Git so
external RTL consumers can compile a checkout without running the generator.
All memory-map `END` constants denote the last valid address (inclusive).
An image starting at physical address zero has `PHYSICAL_END + 1` bytes;
`objcopy --pad-to` uses the exclusive logical bound, `END + 1`.

The common startup, UART helpers, linker scripts, ACT4 adapter, and Zephyr board
use these constants. Linker scripts retain their own section layout and program
limits. Directed assembly tests and their expected register values still assume
the default map; changing the map does not automatically relocate those tests.
The ACT4 Sail configuration also has reference-model-specific device addresses.
