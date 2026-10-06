# Test execution limits

`RunTest.py` reads each test's `cfg.xml`. For example:

```xml
<Config>
  <MaxTestInstructions>10000</MaxTestInstructions>
  <MaxNoCommitCycles>500</MaxNoCommitCycles>
  <RegisterValues>
    <R10>0</R10>
  </RegisterValues>
</Config>
```

- `MaxTestInstructions` limits committed RISC-V instructions, including startup
  code. An instruction is counted when its last micro-op commits. Speculative
  execution and replay do not consume this budget.
- `MaxNoCommitCycles` limits consecutive cycles without any micro-op committing,
  starting at reset release. The default is 500; exceeding the limit fails the
  test. Cache-flush tests need larger values.
- `EnablePC_Goal` defaults to `1`: the program must reach the existing goal PC
  before exhausting its budget. Reaching the goal on the boundary succeeds.
  Set it to `0` for a continuous test that should complete its instruction budget.
- `MaxTestCycles` is an optional additional cap, disabled when absent or zero.
  With an instruction budget, hitting this cap fails the test. Legacy cycle-only
  configurations remain accepted; with `EnablePC_Goal=0`, their cycle cap is still
  the intended end of execution.

Register and serial expectations are checked after successful execution. An empty
`RegisterValues` element is allowed for execution-only or serial-only tests.
Limits are checked once per cycle, so simultaneous commits can take the instruction
count slightly past its budget. Logs record the termination reason, committed
instruction and micro-op counts, elapsed cycles, longest no-commit interval, and
IPC. IPC uses cycles since reset release and is informational, not a pass criterion.

The in-repository instruction budgets allow roughly twice the measured work,
rounded up to 10,000-instruction increments. Normal tests allow 500 no-commit
cycles; `CacheFlush` and `Fence` allow 5,000 and 2,500 respectively because their
measured cache-flush waits were 2,338 and 1,170 cycles.

Rebuild the simulator after changing its test bench; the runner rejects models
that do not report a termination reason. `make run`, `make kanata`, and `make dump`
use Makefile variables rather than `cfg.xml`; pass `MAX_TEST_INSTRUCTIONS`,
`MAX_NO_COMMIT_CYCLES`, and optionally `MAX_TEST_CYCLES` to override their limits.

Run the driver tests from the repository root:

```sh
python3 -B -m unittest discover -s Processor/Tools/TestDriver/Tests -p 'Test*.py' -v
```

The CLI tests use simulator stubs. The model tests also run when the Verilator
binary and Fibonacci HEX have been built with `make -f Makefile.verilator.mk` and
`make -f Makefile.verilator.mk test-build-basic` in `Processor/Src`.
