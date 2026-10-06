"""Exercise the runner CLI without requiring simulator installations."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


RUNNER = Path(__file__).resolve().parents[1] / 'RunTest.py'
FAKE_SIMULATOR = '''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import signal
import sys

name = Path(sys.argv[0]).name
with open(os.environ['FAKE_CALLS_LOG'], 'a') as log:
    log.write(json.dumps({'name': name, 'args': sys.argv[1:], 'cwd': os.getcwd()}) + '\\n')
print('simulator stdout: ' + name, flush=True)
print('simulator stderr: ' + name, file=sys.stderr, flush=True)
if name != 'xelab':
    test_code = next(arg.lstrip('+').split('=', 1)[1] for arg in sys.argv[1:]
                     if arg.lstrip('+').startswith('TEST_CODE='))
    test_dir = Path(test_code)
    (test_dir / 'reg.out.hex').write_text('0x00000000\\n' * 65)
    serial_output = bytes.fromhex(os.environ['FAKE_SERIAL_HEX']) if 'FAKE_SERIAL_HEX' in os.environ else b'done\\n'
    (test_dir / 'serial.out.txt').write_bytes(serial_output)
if os.environ.get('FAKE_SIGNAL') == name:
    os.kill(os.getpid(), signal.SIGTERM)
sys.exit(int(os.environ.get('FAKE_STATUS_' + name, '0')))
'''


class RunTestProcessTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='rsd-run-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.src = self.root / 'Processor/Src'
        self.case = self.src / 'Verification/TestCode/Case'
        self.case.mkdir(parents=True)
        (self.case / 'cfg.xml').write_text(
            '<Config><MaxTestCycles>10</MaxTestCycles>'
            '<RegisterValues><R0>0</R0></RegisterValues></Config>')
        (self.case / 'serial.ref.txt').write_text('done\n')
        self.runner = self.root / 'Processor/Tools/TestDriver/RunTest.py'
        self.runner.parent.mkdir(parents=True)
        shutil.copy2(RUNNER, self.runner)
        self.bin_dir = self.root / 'simulator-bin'
        self.bin_dir.mkdir()
        model = self.root / 'Processor/Project/Verilator/obj_dir/VMain_Zynq_Wrapper'
        model.parent.mkdir(parents=True)
        self.vivado_cwd = self.root / 'Processor/Project/VivadoSim/work'
        self.vivado_cwd.mkdir(parents=True)
        self.executables = {
            'verilator': model,
            'modelsim': self.bin_dir / 'vsim',
            'vivadosim': self.bin_dir / 'xsim',
        }
        for path in [*self.executables.values(), self.bin_dir / 'xelab']:
            path.write_text(FAKE_SIMULATOR)
            path.chmod(0o755)
        self.calls_path = self.root / 'calls.jsonl'
        self.env = os.environ.copy()
        self.env.update(RSD_QUESTASIM_PATH=str(self.bin_dir),
                        RSD_VIVADO_BIN=str(self.bin_dir),
                        FAKE_CALLS_LOG=str(self.calls_path))

    def run_runner(self, simulator, *options):
        self.calls_path.unlink(missing_ok=True)
        return subprocess.run(
            [sys.executable, str(self.runner), '--simulator=' + simulator,
             *options, str(self.case.relative_to(self.src))],
            cwd=self.src, env=self.env, capture_output=True, text=True, timeout=10)

    def calls(self):
        if not self.calls_path.exists():
            return []
        return [json.loads(line) for line in self.calls_path.read_text().splitlines()]

    def assert_simulation_failure(self, result):
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertNotIn('OK (', result.stdout)
        self.assertIn('NG (', result.stderr)
        self.assertIn('log:', result.stderr)

    def test_success_and_logging_in_both_output_modes(self):
        for simulator, executable in self.executables.items():
            for options in ((), ('-o',)):
                with self.subTest(simulator=simulator, options=options):
                    result = self.run_runner(simulator, *options)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn('1 registers have correct values', result.stdout)
                    self.assertIn('Serial output text is correct', result.stdout)
                    log_name = {'verilator': 'verilator.log', 'modelsim': 'vsim.log',
                                'vivadosim': 'xsim.log'}[simulator]
                    log = (self.case / log_name).read_text()
                    self.assertIn('simulator stdout: ' + executable.name, log)
                    self.assertIn('simulator stderr: ' + executable.name, log)
                    if options:
                        self.assertNotIn('simulator stdout:', result.stdout)
                        self.assertNotIn('simulator stderr:', result.stdout)
                    else:
                        self.assertIn('simulator stdout:', result.stdout)
                        self.assertIn('simulator stderr:', result.stdout)

    def test_nonzero_status_rejects_even_matching_result_files(self):
        for simulator, executable in self.executables.items():
            self.env['FAKE_STATUS_' + executable.name] = '7'
            try:
                for options in ((), ('-o',), ('-e', '0')):
                    with self.subTest(simulator=simulator, options=options):
                        result = self.run_runner(simulator, *options)
                        self.assert_simulation_failure(result)
                        self.assertIn('exited with status 7', result.stderr)
                        self.assertEqual((self.case / 'serial.out.txt').read_text(), 'done\n')
            finally:
                del self.env['FAKE_STATUS_' + executable.name]

    def test_signal_termination_is_a_failure(self):
        for simulator, executable in self.executables.items():
            with self.subTest(simulator=simulator):
                self.env['FAKE_SIGNAL'] = executable.name
                result = self.run_runner(simulator)
                self.assert_simulation_failure(result)
                self.assertIn('exited with status -15', result.stderr)

    def test_elaboration_failure_does_not_start_xsim(self):
        self.env['FAKE_STATUS_xelab'] = '9'
        for options in ((), ('-o',)):
            with self.subTest(options=options):
                result = self.run_runner('vivadosim', *options)
                self.assert_simulation_failure(result)
                self.assertIn('exited with status 9', result.stderr)
                self.assertIn('xelab.log', result.stderr)
                self.assertEqual([call['name'] for call in self.calls()], ['xelab'])
                self.assertIn('simulator stderr: xelab', (self.case / 'xelab.log').read_text())

    def test_missing_executable_is_a_failure(self):
        for simulator, executable in self.executables.items():
            with self.subTest(simulator=simulator):
                executable.unlink()
                result = self.run_runner(simulator, '-o')
                self.assert_simulation_failure(result)
                self.assertIn('Cannot run', result.stderr)
                self.assertNotIn('Traceback', result.stderr)

    def test_arguments_with_spaces_and_backend_working_directories(self):
        new_case = self.case.with_name('Case with spaces')
        self.case.rename(new_case)
        self.case = new_case
        new_bin = self.bin_dir.with_name('simulator bin')
        self.bin_dir.rename(new_bin)
        self.env.update(RSD_QUESTASIM_PATH=str(new_bin), RSD_VIVADO_BIN=str(new_bin))
        for simulator in self.executables:
            with self.subTest(simulator=simulator):
                result = self.run_runner(simulator, '-q', '-l', 'trace with spaces.log')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                calls = self.calls()
                if simulator == 'vivadosim':
                    self.assertEqual([call['name'] for call in calls], ['xelab', 'xsim'])
                    self.assertTrue(all(call['cwd'] == str(self.vivado_cwd) for call in calls))
                    args = calls[-1]['args']
                    self.assertEqual(args.count('-testplusarg'), 4)
                    self.assertIn('TEST_CODE=../../../Src/Verification/TestCode/Case with spaces', args)
                else:
                    self.assertEqual(calls[0]['cwd'], str(self.src))
                    prefix = '+' if simulator == 'modelsim' else ''
                    self.assertIn(prefix + 'RSD_LOG_FILE=trace with spaces.log', calls[0]['args'])
                    if simulator == 'modelsim':
                        self.assertEqual(calls[0]['args'][-2:], ['-do', 'run -all'])

    def test_serial_output_requires_exact_match_by_default(self):
        for simulator in self.executables:
            for output, matched in (
                (b'done\n', True),
                (b'', False),
                (b'don', False),
                (b'done', False),
                (b'done\nmore\n', False),
                (b'wrong\n', False),
                (b'do\xffne\n', False),
                (b'do\rne\n', False),
            ):
                with self.subTest(simulator=simulator, output=output):
                    self.env['FAKE_SERIAL_HEX'] = output.hex()
                    result = self.run_runner(simulator)
                    self.assertEqual(result.returncode, 0 if matched else 1,
                                     result.stdout + result.stderr)
                    self.assertIn('Serial output text is ' + ('correct' if matched else 'incorrect'),
                                  result.stdout)
                    self.assertNotIn('Traceback', result.stderr)

    def test_serial_prefix_requires_the_entire_reference(self):
        for simulator in self.executables:
            for output, matched in (
                (b'done\n', True),
                (b'done\nmore\n', True),
                (b'', False),
                (b'don', False),
                (b'done', False),
                (b'wrong\ndone\n', False),
                (b'do\xffne\n', False),
            ):
                with self.subTest(simulator=simulator, output=output):
                    self.env['FAKE_SERIAL_HEX'] = output.hex()
                    result = self.run_runner(simulator, '--serial-prefix')
                    self.assertEqual(result.returncode, 0 if matched else 1,
                                     result.stdout + result.stderr)
                    self.assertIn('Serial output text is ' + ('correct' if matched else 'incorrect'),
                                  result.stdout)

    def test_empty_reference_only_accepts_silence_in_exact_mode(self):
        (self.case / 'serial.ref.txt').write_bytes(b'')
        for options in ((), ('--serial-prefix',)):
            for output in (b'', b'unexpected\n', b'\xff'):
                with self.subTest(options=options, output=output):
                    self.env['FAKE_SERIAL_HEX'] = output.hex()
                    result = self.run_runner('verilator', *options)
                    matched = not options and not output
                    self.assertEqual(result.returncode, 0 if matched else 1,
                                     result.stdout + result.stderr)

    def test_serial_line_endings_are_normalized(self):
        for reference, output in ((b'done\r\n', b'done\n'), (b'done\n', b'done\r\n'),
                                  (b'done\r', b'done\n'), (b'done\n', b'done\r')):
            for options in ((), ('--serial-prefix',)):
                with self.subTest(reference=reference, output=output, options=options):
                    (self.case / 'serial.ref.txt').write_bytes(reference)
                    self.env['FAKE_SERIAL_HEX'] = output.hex()
                    result = self.run_runner('verilator', *options)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_no_serial_reference_skips_serial_comparison(self):
        (self.case / 'serial.ref.txt').unlink()
        for options in ((), ('--serial-prefix',)):
            with self.subTest(options=options):
                result = self.run_runner('verilator', *options)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn('Serial output', result.stdout)

    def test_disabling_pc_goal_does_not_allow_incomplete_serial_output(self):
        config = self.case / 'cfg.xml'
        config.write_text(config.read_text().replace('<Config>', '<Config><EnablePC_Goal>0</EnablePC_Goal>'))
        self.env['FAKE_SERIAL_HEX'] = b'don'.hex()
        result = self.run_runner('verilator')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('ENABLE_PC_GOAL=0', self.calls()[0]['args'])

    def test_serial_mismatch_respects_result_exit_option(self):
        self.env['FAKE_SERIAL_HEX'] = b'don'.hex()
        result = self.run_runner('verilator', '-e', '0')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Serial output text is incorrect', result.stdout)


if __name__ == '__main__':
    unittest.main()
