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

## riscv-arch-test (ACT4)

In the Ubuntu 26.04 dev container, explicitly fetch the source and install its dependencies:

```sh
make -f Makefile.verilator.mk test-fetch-riscv-arch-test
make -f Makefile.verilator.mk test-setup-riscv-arch-test
make -f Makefile.verilator.mk test-check-riscv-arch-test
```

The [ACT4 Makefile](riscv-arch-test/Makefile) pins the upstream commit, Bundler,
and Sail release. Sources are checked out under `riscv-arch-test/External/`;
its Python/Ruby environments, download caches, and checksum-verified Sail binary stay
under `riscv-arch-test/Build/`. Setup uses Ubuntu's Python, Ruby and LLVM 22
without building a compiler or installing mise/uv. Fetch and setup need network
access; the check target uses the installed tools without downloads.
UDB's regenerated architecture data uses `/tmp/rsd-arch-test-<uid>/data/` inside
the container because its read-only exclusive locks fail on NFS.
This prepares the environment; the RSD configuration and execution adapter
will be added separately. Existing legacy compliance tests remain available.

## Legacy riscv-compliance

```sh
make -f Makefile.verilator.mk test-fetch-riscv-compliance
make -j"$(nproc)" -f Makefile.verilator.mk test-build-riscv-compliance
make -f Makefile.verilator.mk test-riscv-compliance
```

The fetch target downloads the public 2018 suite at the commit pinned in
[riscv-compliance/Makefile](riscv-compliance/Makefile), under `riscv-compliance/External/`.
Builds use unmodified upstream sources and signature references, without network
access or `RSD_ENV`. Each case directory contains generated files; the RSD entry
point and serial signature adapter are maintained here. Test targets build these
files as needed. `test-clean-riscv-compliance` preserves the checkout and adapters;
clean before changing compilers or build flags.

The existing 54 RV32I cases remain enabled, including CSR and exception tests.
`I-FENCE.I-01` is built but remains excluded from the default test list.
The FP compliance targets use the separate `old-framework-2.x` generation and
are outside this RV32I migration. This preserves the legacy regression suite;
it does not establish coverage of the current RISC-V architecture tests.
