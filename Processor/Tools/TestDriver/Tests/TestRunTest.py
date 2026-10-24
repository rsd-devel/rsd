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
if os.environ.get('FAKE_TIMING_VIOLATION'):
    print('Timing violation in test cell', flush=True)
if name != 'xelab':
    test_code = next(arg.lstrip('+').split('=', 1)[1] for arg in sys.argv[1:]
                     if arg.lstrip('+').startswith('TEST_CODE='))
    test_dir = Path(test_code)
    if not os.environ.get('FAKE_SKIP_REGISTER_DUMP'):
        (test_dir / 'reg.out.hex').write_text('0x00000000\\n' * 65)
    serial_output = bytes.fromhex(os.environ['FAKE_SERIAL_HEX']) if 'FAKE_SERIAL_HEX' in os.environ else b'done\\n'
    (test_dir / 'serial.out.txt').write_bytes(serial_output)
    parameters = dict(arg.lstrip('+').split('=', 1) for arg in sys.argv[1:] if '=' in arg)
    default_reason = ('pc_goal' if parameters['ENABLE_PC_GOAL'] == '1' else
                      'instruction_limit' if int(parameters['MAX_TEST_INSTRUCTIONS']) else 'cycle_limit')
    reason = os.environ.get('FAKE_RESULT', default_reason)
    prefix = '# ' if name == 'vsim' else ''
    if reason != 'missing':
        print(prefix + 'Simulation result: ' + reason, flush=True)
        if os.environ.get('FAKE_DUPLICATE_RESULT'):
            print(prefix + 'Simulation result: ' + reason, flush=True)
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
            '<Config><MaxTestInstructions>10000</MaxTestInstructions>'
            '<MaxNoCommitCycles>500</MaxNoCommitCycles>'
            '<RegisterValues><R0>0</R0></RegisterValues></Config>')
        (self.case / 'serial.ref.txt').write_text('done\n')
        self.runner = self.root / 'Processor/Tools/TestDriver/RunTest.py'
        self.runner.parent.mkdir(parents=True)
        shutil.copy2(RUNNER, self.runner)
        self.bin_dir = self.root / 'simulator-bin'
        self.bin_dir.mkdir()
        model = self.root / 'Processor/Project/Verilator/obj_dir/VTestMain'
        model.parent.mkdir(parents=True)
        self.vivado_cwd = self.root / 'Processor/Project/VivadoSim/work'
        self.vivado_cwd.mkdir(parents=True)
        self.executables = {
            'verilator': model,
            'modelsim': self.bin_dir / 'vsim',
            'vivadosim': self.bin_dir / 'xsim',
        }
        for path in [*self.executables.values(), self.bin_dir / 'xelab', self.case / 'simv']:
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

    def test_post_synthesis_checks_uart_and_termination_without_register_dump(self):
        self.env['FAKE_SKIP_REGISTER_DUMP'] = '1'
        self.env.pop('RSD_QUESTASIM_PATH', None)
        for reason, serial, expected in [('pc_goal', b'done\n', 0),
                                         ('pc_goal', b'wrong\n', 1),
                                         ('no_commit_limit', b'done\n', 3),
                                         ('missing', b'done\n', 3)]:
            with self.subTest(reason=reason, serial=serial):
                self.env.update(FAKE_RESULT=reason, FAKE_SERIAL_HEX=serial.hex())
                result = self.run_runner('post-synthesis', '-o')
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                self.assertFalse((self.case / 'reg.out.hex').exists())
                self.assertNotIn('registers have correct values', result.stdout)
                call = self.calls()[0]
                self.assertEqual(Path(call['cwd']), self.case)
                self.assertEqual(call['name'], 'xsim')
                self.assertIn('post_synthesis', call['args'])
                self.assertIn('MAX_TEST_INSTRUCTIONS=10000', call['args'])
                self.assertIn('TEST_CODE=.', call['args'])
                self.assertTrue((self.case / 'xsim.log').is_file())
        self.env.update(FAKE_RESULT='pc_goal', FAKE_STATUS_xsim='7')
        self.assert_simulation_failure(self.run_runner('post-synthesis'))

    def test_post_synthesis_requires_nonempty_uart_reference(self):
        reference = self.case / 'serial.ref.txt'
        reference.write_bytes(b'')
        for missing in (False, True):
            if missing:
                reference.unlink()
            for simulator in ('post-synthesis', 'post-synthesis-vcs'):
                result = self.run_runner(simulator)
                self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
                self.assertIn('requires a nonempty serial.ref.txt', result.stderr)
                self.assertEqual(self.calls(), [])

    def test_vcs_checks_termination_uart_and_timing_without_register_dump(self):
        self.env['FAKE_SKIP_REGISTER_DUMP'] = '1'
        self.env.pop('RSD_VIVADO_BIN', None)
        for reason, serial, violation, expected in [
                ('pc_goal', b'done\n', '', 0),
                ('pc_goal', b'wrong\n', '', 1),
                ('no_commit_limit', b'done\n', '', 3),
                ('missing', b'done\n', '', 3),
                ('pc_goal', b'done\n', '1', 3)]:
            with self.subTest(reason=reason, serial=serial, violation=violation):
                self.env.update(FAKE_RESULT=reason, FAKE_SERIAL_HEX=serial.hex(),
                                FAKE_TIMING_VIOLATION=violation)
                result = self.run_runner('post-synthesis-vcs', '-o')
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                self.assertFalse((self.case / 'reg.out.hex').exists())
                self.assertEqual(Path(self.calls()[0]['cwd']), self.case)
                self.assertTrue((self.case / 'vcs.log').is_file())
        self.env.update(FAKE_RESULT='pc_goal', FAKE_TIMING_VIOLATION='', FAKE_STATUS_simv='7')
        self.assert_simulation_failure(self.run_runner('post-synthesis-vcs'))

    def test_benchmark_scores_after_validation(self):
        self.env['FAKE_SERIAL_HEX'] = (
            b'done\nRSD benchmark: iterations=100 cycles=0x00030d40\n').hex()
        for simulator in self.executables:
            for benchmark, expected in [('coremark', 'CoreMark/MHz: 500.000000'),
                                        ('dhrystone', 'Dhrystone DMIPS/MHz: 0.284576')]:
                with self.subTest(simulator=simulator, benchmark=benchmark):
                    result = self.run_runner(simulator, '--benchmark=' + benchmark, '-o')
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn(expected, result.stdout)
                    self.assertIn('100 iterations, 200000 cycles', result.stdout)

    def test_benchmark_rejects_invalid_measurements(self):
        record = b'RSD benchmark: iterations=1 cycles=0x00000001\n'
        for suffix in [b'', b'partial', record + record,
                       record.replace(b'iterations=1', b'iterations=0'),
                       record.replace(b'iterations=1', b'iterations=4294967296'),
                       record.replace(b'0x00000001', b'0x00000000')]:
            with self.subTest(suffix=suffix):
                self.env['FAKE_SERIAL_HEX'] = (b'done\n' + suffix).hex()
                result = self.run_runner('verilator', '--benchmark=coremark')
                self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
                self.assertNotIn('CoreMark/MHz:', result.stdout)

    def test_dhrystone_cycle_and_instruction_report(self):
        report = b'done\nRSD measured cycles : 474383\nRSD measured instructions : 656036\n'
        self.env['FAKE_SERIAL_HEX'] = report.hex()
        for simulator in self.executables:
            with self.subTest(simulator=simulator):
                result = self.run_runner(simulator, '--benchmark=dhrystone',
                                         '--benchmark-iterations=2000', '-o')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('Dhrystone DMIPS/MHz: 2.399546', result.stdout)
        result = self.run_runner('verilator', '--benchmark=dhrystone')
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        for invalid in (report.replace(b'474383', b'0'),
                        report.replace(b'474383', b'4294967296'),
                        report.replace(b'656036', b'0'),
                        report.replace(b'656036', b'4294967296'),
                        report + b'extra\n'):
            with self.subTest(invalid=invalid):
                self.env['FAKE_SERIAL_HEX'] = invalid.hex()
                result = self.run_runner('verilator', '--benchmark=dhrystone',
                                         '--benchmark-iterations=2000')
                self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
                self.assertNotIn('DMIPS/MHz:', result.stdout)

    def test_benchmark_rejects_iteration_mismatch(self):
        self.env['FAKE_SERIAL_HEX'] = (
            b'done\nRSD benchmark: iterations=100 cycles=0x00030d40\n').hex()
        result = self.run_runner('verilator', '--benchmark=coremark',
                                 '--benchmark-iterations=2000')
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertNotIn('CoreMark/MHz:', result.stdout)

    def test_instruction_budget_override_reaches_every_backend(self):
        for simulator in self.executables:
            with self.subTest(simulator=simulator):
                result = self.run_runner(simulator, '--max-test-instructions=2000000')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                arguments = [arg.lstrip('+') for arg in self.calls()[-1]['args']]
                self.assertIn('MAX_TEST_INSTRUCTIONS=2000000', arguments)
        for invalid in ('0', '-1', '9223372036854775808'):
            with self.subTest(invalid=invalid):
                result = self.run_runner('verilator', '--max-test-instructions=' + invalid)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(self.calls(), [])

    def test_benchmark_requires_reference_and_correct_results(self):
        self.env['FAKE_SERIAL_HEX'] = (
            b'wrong\nRSD benchmark: iterations=1 cycles=0x00000001\n').hex()
        result = self.run_runner('verilator', '--benchmark=coremark')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertNotIn('CoreMark/MHz:', result.stdout)
        self.env['FAKE_SERIAL_HEX'] = (
            b'done\nRSD benchmark: iterations=1 cycles=0x00000001\n').hex()
        config = self.case / 'cfg.xml'
        config.write_text(config.read_text().replace('<R0>0</R0>', '<R0>1</R0>'))
        result = self.run_runner('verilator', '--benchmark=coremark')
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertNotIn('CoreMark/MHz:', result.stdout)
        self.env['FAKE_RESULT'] = 'no_commit_limit'
        result = self.run_runner('verilator', '--benchmark=coremark')
        self.assert_simulation_failure(result)
        self.assertNotIn('CoreMark/MHz:', result.stdout)
        del self.env['FAKE_RESULT']
        (self.case / 'serial.ref.txt').unlink()
        result = self.run_runner('verilator', '--benchmark=coremark')
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertEqual(self.calls(), [])

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
                    self.assertEqual(args.count('-testplusarg'), 6)
                    self.assertIn('TEST_CODE=../../../Src/Verification/TestCode/Case with spaces', args)
                else:
                    self.assertEqual(calls[0]['cwd'], str(self.src))
                    prefix = '+' if simulator in ('modelsim', 'verilator') else ''
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
        self.assertIn('+ENABLE_PC_GOAL=0', self.calls()[0]['args'])

    def test_serial_mismatch_respects_result_exit_option(self):
        self.env['FAKE_SERIAL_HEX'] = b'don'.hex()
        result = self.run_runner('verilator', '-e', '0')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Serial output text is incorrect', result.stdout)

    def test_progress_parameters_reach_every_backend(self):
        for simulator in self.executables:
            for limits, expected in (
                ('<MaxTestInstructions>6000000000</MaxTestInstructions>'
                 '<MaxNoCommitCycles>900</MaxNoCommitCycles>',
                 ['MAX_TEST_INSTRUCTIONS=6000000000', 'MAX_NO_COMMIT_CYCLES=900', 'MAX_TEST_CYCLES=0']),
                ('<MaxTestCycles>10000</MaxTestCycles>',
                 ['MAX_TEST_INSTRUCTIONS=0', 'MAX_NO_COMMIT_CYCLES=500', 'MAX_TEST_CYCLES=10000']),
                ('<MaxTestInstructions>10000</MaxTestInstructions><MaxTestCycles>20000</MaxTestCycles>',
                 ['MAX_TEST_INSTRUCTIONS=10000', 'MAX_NO_COMMIT_CYCLES=500', 'MAX_TEST_CYCLES=20000']),
            ):
                with self.subTest(simulator=simulator, limits=limits):
                    (self.case / 'cfg.xml').write_text('<Config>' + limits + '<RegisterValues/></Config>')
                    result = self.run_runner(simulator)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    arguments = [arg.lstrip('+') for arg in self.calls()[-1]['args']]
                    for argument in expected:
                        self.assertIn(argument, arguments)

    def test_invalid_limits_fail_before_starting_simulator(self):
        for limits in (
            '', '<MaxTestInstructions>0</MaxTestInstructions>',
            '<MaxTestInstructions>-1</MaxTestInstructions>',
            '<MaxTestInstructions>1.5</MaxTestInstructions>',
            '<MaxTestInstructions/>',
            '<MaxTestInstructions>9223372036854775808</MaxTestInstructions>',
            '<MaxTestInstructions>100</MaxTestInstructions><MaxNoCommitCycles>0</MaxNoCommitCycles>',
            '<MaxTestInstructions>100</MaxTestInstructions><MaxNoCommitCycles>-2</MaxNoCommitCycles>',
            '<MaxTestInstructions>100</MaxTestInstructions><MaxTestCycles>-1</MaxTestCycles>',
            '<MaxTestInstructions>100</MaxTestInstructions><EnablePC_Goal>2</EnablePC_Goal>',
        ):
            with self.subTest(limits=limits):
                (self.case / 'cfg.xml').write_text('<Config>' + limits + '<RegisterValues/></Config>')
                result = self.run_runner('verilator')
                self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
                self.assertIn('Invalid configuration', result.stderr)
                self.assertNotIn('Traceback', result.stderr)
                self.assertEqual(self.calls(), [])

    def test_premature_termination_fails_even_with_zero_process_status(self):
        for simulator in self.executables:
            for reason in ('instruction_limit', 'no_commit_limit', 'cycle_limit',
                           'unexpected_finish', 'runtime_error', 'missing'):
                for options in ((), ('-o',), ('-e', '0')):
                    with self.subTest(simulator=simulator, reason=reason, options=options):
                        self.env['FAKE_RESULT'] = reason
                        result = self.run_runner(simulator, *options)
                        self.assert_simulation_failure(result)
                        self.assertIn('rebuild the simulator' if reason == 'missing' else reason, result.stderr)

    def test_duplicate_simulation_result_is_rejected(self):
        self.env['FAKE_DUPLICATE_RESULT'] = '1'
        for simulator in self.executables:
            with self.subTest(simulator=simulator):
                self.assert_simulation_failure(self.run_runner(simulator))

    def test_execution_only_test_requires_its_instruction_budget(self):
        (self.case / 'cfg.xml').write_text(
            '<Config><MaxTestInstructions>10000</MaxTestInstructions>'
            '<MaxTestCycles>20000</MaxTestCycles><EnablePC_Goal>0</EnablePC_Goal>'
            '<RegisterValues/></Config>')
        (self.case / 'serial.ref.txt').unlink()
        for simulator in self.executables:
            for reason in ('instruction_limit', 'pc_goal', 'cycle_limit', 'no_commit_limit'):
                with self.subTest(simulator=simulator, reason=reason):
                    self.env['FAKE_RESULT'] = reason
                    result = self.run_runner(simulator)
                    if reason == 'instruction_limit':
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertIn('Execution completed (instruction_limit)', result.stdout)
                        self.assertNotIn('0 registers have correct values', result.stdout)
                    else:
                        self.assert_simulation_failure(result)

    def test_legacy_continuous_test_accepts_cycle_budget(self):
        (self.case / 'cfg.xml').write_text(
            '<Config><MaxTestCycles>10000</MaxTestCycles><EnablePC_Goal>0</EnablePC_Goal>'
            '<RegisterValues/></Config>')
        for simulator in self.executables:
            with self.subTest(simulator=simulator):
                result = self.run_runner(simulator)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('Execution completed (cycle_limit)', result.stdout)


if __name__ == '__main__':
    unittest.main()
