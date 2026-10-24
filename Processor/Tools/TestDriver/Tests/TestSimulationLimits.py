"""Exercise progress limits using the built Verilator model and Fibonacci HEX."""

from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


PROCESSOR = Path(__file__).resolve().parents[3]
SOURCE = PROCESSOR / 'Src'
MODEL = PROCESSOR / 'Project/Verilator/obj_dir/VMain_Zynq_Wrapper'
FIBONACCI = SOURCE / 'Verification/TestCode/C/Fibonacci/code.hex'


@unittest.skipUnless(MODEL.is_file() and FIBONACCI.is_file(),
                     'Build the Verilator model and test-build-basic first')
class SimulationLimitTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='rsd-simulation-limits-')
        self.addCleanup(temporary.cleanup)
        self.case = Path(temporary.name)
        shutil.copy2(FIBONACCI, self.case / 'code.hex')

    def run_model(self, instructions=10000, no_commit=500, cycles=0, goal=True):
        result = subprocess.run(
            [str(MODEL), 'TEST_CODE=' + str(self.case),
             'MAX_TEST_INSTRUCTIONS=' + str(instructions),
             'MAX_NO_COMMIT_CYCLES=' + str(no_commit),
             'MAX_TEST_CYCLES=' + str(cycles),
             'ENABLE_PC_GOAL=' + str(int(goal)), 'SHOW_SERIAL_OUT=1'],
            cwd=SOURCE, capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        statistics = {}
        for key, pattern in (
            ('instructions', r'Num of committed RISC-V-ops: (\d+)'),
            ('cycles', r'Elapsed cycles: (\d+)'),
            ('max_no_commit', r'Max consecutive no-commit cycles: (\d+)'),
            ('ipc', r'IPC \(RISC-V instruction\): ([\d.]+)'),
            ('reason', r'Simulation result: (\w+)'),
        ):
            match = re.search(pattern, output)
            self.assertIsNotNone(match, output)
            value = match.group(1)
            statistics[key] = value if key == 'reason' else float(value) if key == 'ipc' else int(value)
        return result, statistics

    def use_infinite_loop(self):
        # jal x0, 0 at the ROM reset vector (0x1000).
        padding = '00000013000000130000001300000013\n' * (0x1000 // 16)
        (self.case / 'code.hex').write_text(padding + '0000001300000013000000130000006f\n')

    def test_goal_at_instruction_and_no_commit_boundaries(self):
        result, measured = self.run_model()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(measured['reason'], 'pc_goal')
        self.assertGreater(measured['instructions'], 0)
        self.assertGreater(measured['max_no_commit'], 1)
        self.assertAlmostEqual(measured['ipc'], measured['instructions'] / measured['cycles'], places=6)

        result, boundary = self.run_model(instructions=measured['instructions'],
                                          no_commit=measured['max_no_commit'])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(boundary, measured)

        result, short = self.run_model(instructions=measured['instructions'] - 1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(short['reason'], 'instruction_limit')

        result, stalled = self.run_model(no_commit=measured['max_no_commit'] - 1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(stalled['reason'], 'no_commit_limit')
        self.assertEqual(stalled['max_no_commit'], measured['max_no_commit'])

    def test_instruction_budget_only_succeeds_when_goal_is_disabled(self):
        self.use_infinite_loop()
        for goal in (True, False):
            with self.subTest(goal=goal):
                result, stats = self.run_model(instructions=1000, goal=goal)
                self.assertEqual(result.returncode, 1 if goal else 0, result.stdout + result.stderr)
                self.assertEqual(stats['reason'], 'instruction_limit')
                self.assertGreaterEqual(stats['instructions'], 1000)
                # More cycles than the watchdog limit proves it resets on commit.
                self.assertGreater(stats['cycles'], 500)
                self.assertLessEqual(stats['max_no_commit'], 500)

    def test_no_commit_limit_stops_before_any_instruction(self):
        for goal in (True, False):
            with self.subTest(goal=goal):
                result, stats = self.run_model(no_commit=1, goal=goal)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(stats['reason'], 'no_commit_limit')
                self.assertEqual(stats['instructions'], 0)
                self.assertEqual(stats['cycles'], 2)
                self.assertEqual(stats['max_no_commit'], 2)

    def test_cycle_cap_cannot_complete_an_instruction_budget(self):
        for goal in (True, False):
            with self.subTest(goal=goal):
                result, stats = self.run_model(cycles=10, goal=goal)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(stats['reason'], 'cycle_limit')
                self.assertEqual(stats['cycles'], 10)

    def test_cycle_only_compatibility_still_requires_goal_when_enabled(self):
        for goal in (True, False):
            with self.subTest(goal=goal):
                result, stats = self.run_model(instructions=0, cycles=10, goal=goal)
                self.assertEqual(result.returncode, 1 if goal else 0, result.stdout + result.stderr)
                self.assertEqual(stats['reason'], 'cycle_limit')


if __name__ == '__main__':
    unittest.main()
