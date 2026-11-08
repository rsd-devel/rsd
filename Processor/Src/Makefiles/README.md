# Build entry points

The root `Makefile` is a symlink to `Processor/Src/Makefile`. When invoked outside
`Processor/Src`, that Makefile forwards targets, variables and parallel jobs there.
Both directories support the normal `make` commands and target completion.
Relative path arguments such as `TEST_CODE` are resolved from `Processor/Src`.
Use `Processor/Src` for the tool-specific `-f Makefiles/...` commands below:

```sh
make -j8                         # Verilator (default)
make test-1
make SIM=modelsim                # ModelSim/QuestaSim
make SIM=xsim                    # XSim
make SIM=xsim test-1
make test-unit                   # Verilator RTL unit tests
make SIM=modelsim test-unit       # ModelSim/QuestaSim RTL unit tests
make -f Makefiles/Vivado.mk       # Vivado board build
make -f Makefiles/Synplify.mk     # Synplify netlist / Vivado board flow
make -f Makefiles/VCS.mk          # VCS post-implementation timing test
```

RTL backends (`Verilator.mk`, `ModelSim.mk`, `XSim.mk`) are included by the main
Makefile; use `SIM` to select them. The former `Makefile.<tool>.mk` entry points
have been removed. Unit-test Makefiles include `Makefiles/UnitTest.inc.mk`
instead of the former `Makefile.inc`. VCS currently provides timing verification,
not a `SIM=vcs` RTL backend. See the [test instructions](../Verification/TestCode/README.md)
for prerequisites and post-synthesis commands.

- `CoreSources.inc.mk`: the stable source/configuration manifest. **sv-tests
  parses `TYPES` and `CORE_MODULES` directly**, without evaluating Make. Preserve
  its path, variable names, literal source paths, continuation lines, and order.
- `Build.inc.mk`: source dependencies and generated RTL rules shared by core
  simulation and synthesis.
- The main `Makefile`: simulator selection, manual run arguments, TestDriver
  commands, and unit-test aggregation. Unit tests follow `SIM`; `UNIT_SIM`
  can select Verilator or ModelSim independently.
- `TestCommands.inc.mk`: program builds, test suites, and tool checks.
- `UnitTest.inc.mk`: unit-test simulator selection, build and execution.
- `Verilator.inc.mk`: Verilator options shared by the core and unit tests.
- `ModelSim.inc.mk`: compiler/runtime recipes shared by the core and unit tests.
- `PostSynthesis.inc.mk`: XSim functional verification shared by Vivado and
  Synplify, with each backend supplying its netlist and required defines.
- `Vivado.inc.mk`: shared board implementation and existing PS Linux build rules.

Tool-specific options and output directories stay in their backends. Test
programs and individual unit tests retain local Makefiles. Generated files stay
under `Processor/Project`. Verilator units use `Verilator/UnitTest/<unit>`;
ModelSim units use `ModelSim/<unit>`.
