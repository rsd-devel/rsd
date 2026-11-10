# Build entry points

The root `Makefile` is a symlink to `Processor/Src/Makefile`. When invoked outside
`Processor/Src`, that Makefile forwards targets, variables and parallel jobs there.
Both directories support the normal `make` commands and target completion.
Relative path arguments such as `TEST_CODE` are resolved from `Processor/Src`.

```sh
make -j8                         # Verilator (default)
make test-1
make SIM=modelsim                # ModelSim/QuestaSim
make SIM=xsim                    # XSim
make SIM=xsim test-1
make test-unit                   # Verilator RTL unit tests
make SIM=modelsim test-unit       # ModelSim/QuestaSim RTL unit tests
make vivado/build                # Board synthesis through bitstream generation
make vivado/post-synthesis/test  # Vivado + XSim functional test
make synplify/post-synthesis/test # Synplify + XSim functional test
make vcs/post-implementation/test # Vivado implementation + VCS timing test
```

RTL backends (`VerilatorCore.inc.mk`, `ModelSimCore.inc.mk`, `XSimCore.inc.mk`)
are included by the main Makefile; use `SIM` to select them. The former `Makefile.<tool>.mk` entry points
have been removed. Unit-test Makefiles include `Makefiles/UnitTest.inc.mk`
instead of the former `Makefile.inc`. VCS currently provides timing verification,
not a `SIM=vcs` RTL backend. See the [test instructions](../Verification/TestCode/README.md)
for prerequisites and post-synthesis commands.

EDA targets use `vivado/`, `synplify/`, and `vcs/` prefixes. Standard Bash completion
shows these groups before their individual targets, without a custom completion
script. `EDA.inc.mk` maps them to separate tool submakes, preserving command-line
variables and parallel job limits. The backend `Vivado.mk`, `Synplify.mk`, and
`VCS.mk` files remain directly usable with `make -f Makefiles/<tool>.mk` from
`Processor/Src`; include-only files use the `.inc.mk` suffix.

`vivado/build` and `synplify/build` include board implementation and bitstream
generation. The latter still requires a separately prepared Synplify board
netlist. Post-synthesis `build`/`test` targets generate their verification netlists
automatically. `vcs/post-implementation/run` reuses an existing routed netlist,
while `test` also builds it. Existing ARM Linux commands are under
`vivado/arm-linux/`; their tool and source requirements are unchanged.

- `CoreSources.inc.mk`: the stable source/configuration manifest. **sv-tests
  parses `TYPES` and `CORE_MODULES` directly**, without evaluating Make. Preserve
  its path, variable names, literal source paths, continuation lines, and order.
- `GenerateConfig.inc.mk`: regeneration rules for `Config/MemoryMap.yml` and
  `Config/MicroArch.yml`. `MicroArch.inc.mk` is generated and supplies the shared
  CPU macro defaults; synthesis uses the generated `MicroArchMacros.svh`.
  YAML `overrides.simulation` and `overrides.synthesis` replace common parameters
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
