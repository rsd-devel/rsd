# Build entry points

From the repository root or `Processor/Src`:

```sh
make -j"$(nproc)"                  # Verilator simulator
make test/level-1/run              # Basic program tests
```

Select another RTL simulator with `SIM=modelsim` or `SIM=xsim`.

The Makefiles are organized as follows:

- `../Makefile` is the common entry point, also linked from the repository root.
  It selects the simulator and includes the shared rules below.
- `Environment.inc.mk` determines `RSD_ROOT` and provides tool-setting checks.
- `Build.inc.mk` combines `CoreSources.inc.mk` (the RTL source list) and
  `GenerateConfig.inc.mk` (generation from `Processor/Config/*.toml`).
- `*Core.inc.mk` contains each RTL simulator's build and run rules.
  `Verilator.inc.mk` and `ModelSim.inc.mk` share settings with unit tests.
- `TestCommands.inc.mk` defines program-test suites; `UnitTest.inc.mk` supplies
  the rules included by individual RTL unit-test Makefiles.
- `EDA.inc.mk` forwards synthesis and platform targets to `Vivado.mk`,
  `Synplify.mk`, or `VCS.mk`, which share applicable `.inc.mk` rules.

Files ending in `.inc.mk` are included by other Makefiles. The tool-specific
`.mk` entry points can also be invoked directly from `Processor/Src`.

The detailed reference is maintained in the Wiki:

- [Build entry points and Makefile structure](https://github.com/rsd-devel/rsd/wiki/en-devel-build)
- [Test programs and suites](https://github.com/rsd-devel/rsd/wiki/en-test-program)
- [TestDriver limits and result checking](https://github.com/rsd-devel/rsd/wiki/en-test-driver)
