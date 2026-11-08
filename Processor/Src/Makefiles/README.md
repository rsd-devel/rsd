# Build entry points

Run from `Processor/Src`:

```sh
make -j8                         # Verilator (default)
make test-1
make SIM=modelsim                # ModelSim/QuestaSim
make SIM=xsim                    # XSim
make SIM=xsim test-1
make test-unit                   # ModelSim/QuestaSim RTL unit tests
make -f Makefiles/Vivado.mk       # Vivado board build
make -f Makefiles/Synplify.mk     # Synplify netlist / Vivado board flow
make -f Makefiles/VCS.mk          # VCS post-implementation timing test
```

RTL backends (`Verilator.mk`, `ModelSim.mk`, `XSim.mk`) are included by the main
Makefile; use `SIM` to select them. The former `Makefile.<tool>.mk` entry points
have been removed. Unit-test Makefiles include `Makefiles/ModelSim.inc.mk`
instead of the former `Makefile.inc`. VCS currently provides timing verification,
not a `SIM=vcs` RTL backend. See the [test instructions](../Verification/TestCode/README.md)
for prerequisites and post-synthesis commands.

- `CoreSources.inc.mk`: the stable source/configuration manifest. **sv-tests
  parses `TYPES` and `CORE_MODULES` directly**, without evaluating Make. Preserve
  its path, variable names, literal source paths, continuation lines, and order.
- `Build.inc.mk`: source dependencies and generated RTL rules shared by core
  simulation and synthesis.
- The main `Makefile`: simulator selection, manual run arguments, TestDriver
  commands, and unit-test aggregation. Unit tests keep their ModelSim build
  directory regardless of the selected core simulator.
- `TestCommands.inc.mk`: program builds, test suites, and tool checks.
- `ModelSim.inc.mk`: compiler/runtime recipes shared by the core and unit tests.
- `PostSynthesis.inc.mk`: XSim functional verification shared by Vivado and
  Synplify, with each backend supplying its netlist and required defines.
- `Vivado.inc.mk`: shared board implementation and existing PS Linux build rules.

Tool-specific options and output directories stay in their backends. Test
programs and individual unit tests retain local Makefiles. Generated files stay
in their existing directories; selecting another simulator does not move them.
