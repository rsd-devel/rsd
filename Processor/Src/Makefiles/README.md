# Build entry points

The root `Makefile` is a symlink to `Processor/Src/Makefile`. When invoked outside
`Processor/Src`, that Makefile forwards targets, variables and parallel jobs there.
Both directories support the normal `make` commands and target completion.
Relative path arguments such as `TEST_CODE` are resolved from `Processor/Src`.

```sh
make -j8                             # Same as sim/build; Verilator by default
make sim/run TEST_CODE=Verification/TestCode/C/HelloWorld
make test/level-1/run
make SIM=modelsim sim/build          # ModelSim/QuestaSim
make SIM=xsim sim/build              # XSim
make SIM=xsim test/level-1/run
make test/unit/run                      # Verilator RTL unit tests
make SIM=modelsim test/unit/run          # ModelSim/QuestaSim RTL unit tests
make synth/vivado/build              # Board synthesis through bitstream generation
make synth/vivado/post-synthesis/test # Vivado + XSim functional test
make synth/synplify/post-synthesis/test # Synplify + XSim functional test
make sim/vcs/post-implementation/test # Vivado implementation + VCS timing test
```

RTL backends (`VerilatorCore.inc.mk`, `ModelSimCore.inc.mk`, `XSimCore.inc.mk`)
are included by the main Makefile; use `SIM` to select them. The former `Makefile.<tool>.mk` entry points
have been removed. Unit-test Makefiles include `Makefiles/UnitTest.inc.mk`
instead of the former `Makefile.inc`. VCS currently provides timing verification,
not a `SIM=vcs` RTL backend. See the [test instructions](../Verification/TestCode/README.md)
for prerequisites and post-synthesis commands.

Public targets use `sim/`, `synth/`, `test/`, `bench/`, and `platform/` prefixes.
Test targets end in an operation, for example `test/level-1/build`,
`test/level-1/run`, and `test/External/Coremark/build`. `External` groups
Coremark, Dhrystone, Zephyr, and riscv-arch-test without moving their source
directories. Test `run` targets execute and check results; score measurement uses
`bench/Coremark/run` and `bench/Dhrystone/run`.
Standard Bash completion shows one slash-separated level at a time, without a
custom completion script. `make`/`make all` and `make clean` remain shorthand for
`sim/build` and `sim/clean`. `test/level-1/run`, `test/level-2/run`, `test/ex/run`, and
`test/all/run` retain the former test suites and scope; `test/all/run` includes
only `test/level-1/run` and `test/level-2/run`.
`EDA.inc.mk` forwards EDA and platform targets to separate tool submakes,
preserving command-line variables and parallel job limits. The backend
`Vivado.mk`, `Synplify.mk`, and `VCS.mk` files remain directly usable with `make -f Makefiles/<tool>.mk` from
`Processor/Src`; include-only files use the `.inc.mk` suffix.

`synth/vivado/build` and `synth/synplify/build` include board implementation and bitstream
generation. The latter still requires a separately prepared Synplify board
netlist. Post-synthesis `build`/`test` targets generate their verification netlists
automatically. `sim/vcs/post-implementation/run` reuses an existing routed netlist,
while `test` also builds it. Existing ARM Linux commands are under
`platform/zynq/`; their tool and source requirements are unchanged.

- `CoreSources.inc.mk`: the stable source/configuration manifest. **sv-tests
  parses `TYPES` and `CORE_MODULES` directly**, without evaluating Make. Preserve
  its path, variable names, literal source paths, continuation lines, and order.
- `GenerateConfig.inc.mk`: regeneration rules for `Config/MemoryMap.toml` and
  `Config/MicroArch.toml`. `MicroArch.inc.mk` is generated and supplies the shared
  CPU macro defaults; synthesis uses the generated `Config/MicroArchMacros.svh`.
  RTL definitions, templates, and synthesis settings live under `Src/Config/`;
  editable TOML inputs remain under `Processor/Config/`.
  TOML `overrides.simulation` and `overrides.synthesis` replace common parameters
  for their mode. Netlist testbenches use `RSD_SYNTHESIS_SRC_CFG` to match synthesis.
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
programs and individual unit tests retain local Makefiles. Build products stay
under `Processor/Project`; generated configuration definitions are kept beside
the sources and checked into Git for external consumers. Verilator units use `Verilator/UnitTest/<unit>`;
ModelSim units use `ModelSim/<unit>`.

The dev container supplies environment settings automatically. For manual setup,
copy and edit [SetEnv.sh](../../Tools/SetEnv/SetEnv.sh), then source `MySetEnv.sh`.
`RSD_ROOT` always comes from the Makefile location and is exported to child
processes; it needs no manual setting. Program builds require `RSD_GCC_PATH` and `RSD_GCC_PREFIX`. ModelSim/Questa requires `RSD_QUESTASIM_PATH`, and Vivado/XSim
requires `RSD_VIVADO_BIN`. Verilator, Synplify and VCS can use commands from PATH.
RTL/EDA and standalone test-suite entry points include `Environment.inc.mk` first.
Ordinary test programs initialize it in their shared `TestCode/Makefile.inc`,
also used by `BuildC.inc.mk`, so individual program Makefiles need no setup.
Configuration rules use the initialized environment without loading it again.
Make's query mode skips the checks so target completion works before setup.
