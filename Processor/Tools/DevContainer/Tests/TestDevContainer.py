"""Check launcher behavior without building an image or starting Docker."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


LAUNCHER = Path(__file__).resolve().parents[1] / 'DevContainer.sh'
FAKE_CLI = '''#!/usr/bin/env python3
import json
import os
import sys
import time
import subprocess

args = sys.argv[1:]
with open(os.environ['FAKE_CALLS'], 'a') as log:
    log.write(json.dumps(args) + '\\n')
if args[0] == 'up':
    assert sys.stdin.read() == ''
    time.sleep(float(os.environ.get('FAKE_UP_DELAY', '0')))
    print('{"outcome":"success"}')
    sys.exit(int(os.environ.get('FAKE_UP_STATUS', '0')))
if args[0] == 'exec':
    command = args[args.index('--') + 1:]
    env = os.environ.copy()
    env['PATH'] = env['FAKE_REMOTE_BIN'] + os.pathsep + env['PATH']
    sys.exit(subprocess.run(command, cwd=env['FAKE_REMOTE_WORKSPACE'], env=env).returncode)
raise AssertionError(args)
'''


FAKE_COMMAND = '''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

print(json.dumps({'command': [Path(sys.argv[0]).name, *sys.argv[1:]],
                  'stdin': sys.stdin.read(), 'cwd': os.getcwd()}))
sys.exit(int(os.environ.get('FAKE_EXEC_STATUS', '0')))
'''


class DevContainerLauncherTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='rsd launcher ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.implementation = self.root / 'Processor/Tools/DevContainer/DevContainer.sh'
        self.implementation.parent.mkdir(parents=True)
        shutil.copy2(LAUNCHER, self.implementation)
        self.launcher = self.root / 'DevContainer.sh'
        self.launcher.symlink_to(self.implementation.relative_to(self.root))
        self.src = self.root / 'Processor/Src'
        self.src.mkdir()
        self.remote = self.root / 'container workspace'
        (self.remote / 'Processor/Src').mkdir(parents=True)
        self.remote_bin = self.root / 'remote bin'
        self.remote_bin.mkdir()
        for name in ('bash', 'true', 'printf'):
            path = self.remote_bin / name
            path.write_text(FAKE_COMMAND)
            path.chmod(0o755)
        self.config = self.root / '.devcontainer'
        self.config.mkdir()
        for name, contents in (
            ('Dockerfile', 'FROM example\n'),
            ('requirements.txt', 'example==1\n'),
            ('devcontainer.json', '{"build":{"dockerfile":"Dockerfile","context":"."}}\n'),
        ):
            (self.config / name).write_text(contents)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        (self.bin / 'devcontainer').write_text(FAKE_CLI)
        (self.bin / 'devcontainer').chmod(0o755)
        (self.bin / 'docker').write_text('#!/bin/sh\nexit 0\n')
        (self.bin / 'docker').chmod(0o755)
        self.calls_path = self.root / 'calls.jsonl'
        self.env = os.environ.copy()
        self.env.update(PATH=str(self.bin) + os.pathsep + self.env['PATH'],
                        FAKE_CALLS=str(self.calls_path),
                        FAKE_REMOTE_WORKSPACE=str(self.remote),
                        FAKE_REMOTE_BIN=str(self.remote_bin))
        self.state = self.root / 'Work/DevContainer/fingerprint'

    def run_launcher(self, *args, input='', cwd='/tmp', launcher=None):
        return subprocess.run([str(launcher or self.launcher), *args], cwd=cwd, env=self.env,
                              input=input, capture_output=True, text=True, timeout=10)

    def calls(self):
        if not self.calls_path.exists():
            return []
        return [json.loads(line) for line in self.calls_path.read_text().splitlines()]

    def test_shell_default_and_container_reuse(self):
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['command'], ['bash', '-l'])
        first_up, first_exec = self.calls()
        self.assertIn('--remove-existing-container', first_up)
        for call in (first_up, first_exec):
            self.assertEqual(call[call.index('--workspace-folder') + 1], str(self.root))
            self.assertEqual(call[call.index('--id-label') + 1],
                             'rsd.devcontainer.workspace=' + str(self.root))
        result = self.run_launcher('true')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('--remove-existing-container', self.calls()[-2])

    def test_direct_execution_reuses_the_symlink_workspace(self):
        self.assertEqual(self.run_launcher('true').returncode, 0)
        result = subprocess.run([str(self.implementation), 'true'], cwd='/tmp',
                                env=self.env, input='', capture_output=True,
                                text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        up, execute = self.calls()[-2:]
        self.assertNotIn('--remove-existing-container', up)
        for call in (up, execute):
            self.assertEqual(call[call.index('--workspace-folder') + 1], str(self.root))
            self.assertEqual(call[call.index('--id-label') + 1],
                             'rsd.devcontainer.workspace=' + str(self.root))

    def test_current_directory_is_preserved_for_commands_and_shells(self):
        entries = (
            (self.root, self.launcher, self.remote),
            (self.src, '../../DevContainer.sh', self.remote / 'Processor/Src'),
        )
        for cwd, launcher, expected in entries:
            for command in ((), ('true',)):
                with self.subTest(cwd=cwd, command=command):
                    result = self.run_launcher(*command, cwd=cwd, launcher=launcher)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(json.loads(result.stdout)['cwd'], str(expected))

    def test_current_directory_with_spaces_is_preserved(self):
        relative = 'Processor/Src/directory with spaces'
        local = self.root / relative
        remote = self.remote / relative
        local.mkdir()
        remote.mkdir()
        result = self.run_launcher('true', cwd=local)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['cwd'], str(remote))

    def test_outside_checkout_uses_repository_root(self):
        result = self.run_launcher('true', cwd='/tmp')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['cwd'], str(self.remote))

    def test_content_changes_recreate_container(self):
        self.assertEqual(self.run_launcher('true').returncode, 0)
        for name in ('Dockerfile', 'requirements.txt', 'devcontainer.json'):
            with self.subTest(name=name):
                path = self.config / name
                before = self.state.read_text()
                path.write_text(path.read_text() + '\n')
                result = self.run_launcher('true')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('--remove-existing-container', self.calls()[-2])
                self.assertNotEqual(before, self.state.read_text())
                path.touch()
                self.assertEqual(self.run_launcher('true').returncode, 0)
                self.assertNotIn('--remove-existing-container', self.calls()[-2])

    def test_added_and_removed_build_input_recreates_container(self):
        self.assertEqual(self.run_launcher('true').returncode, 0)
        extra = self.config / 'additional-input'
        extra.write_text('input')
        self.assertEqual(self.run_launcher('true').returncode, 0)
        self.assertIn('--remove-existing-container', self.calls()[-2])
        extra.unlink()
        self.assertEqual(self.run_launcher('true').returncode, 0)
        self.assertIn('--remove-existing-container', self.calls()[-2])

    def test_forced_rebuild(self):
        self.assertEqual(self.run_launcher('true').returncode, 0)
        result = self.run_launcher('--rebuild', 'true')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--remove-existing-container', self.calls()[-2])

    def test_arguments_stdin_and_exit_status_are_preserved(self):
        self.env['FAKE_EXEC_STATUS'] = '7'
        args = ['printf', '%s\n', 'two words', 'literal; $(echo text)', '--help', '']
        result = self.run_launcher('--', *args, input='command input\n')
        self.assertEqual(result.returncode, 7)
        self.assertEqual(json.loads(result.stdout), {'command': args, 'stdin': 'command input\n',
                                                      'cwd': str(self.remote)})
        self.assertIn('{"outcome":"success"}', result.stderr)

    def test_failed_startup_does_not_execute_or_record_new_inputs(self):
        self.assertEqual(self.run_launcher('true').returncode, 0)
        previous = self.state.read_bytes()
        (self.config / 'requirements.txt').write_text('example==2\n')
        self.env['FAKE_UP_STATUS'] = '8'
        before = len(self.calls())
        result = self.run_launcher('true')
        self.assertEqual(result.returncode, 8)
        self.assertEqual(len(self.calls()), before + 1)
        self.assertEqual(self.calls()[-1][0], 'up')
        self.assertEqual(self.state.read_bytes(), previous)
        self.env.pop('FAKE_UP_STATUS')
        self.assertEqual(self.run_launcher('true').returncode, 0)
        self.assertIn('--remove-existing-container', self.calls()[-2])

    def test_concurrent_startups_recreate_once(self):
        self.env['FAKE_UP_DELAY'] = '0.2'
        processes = [subprocess.Popen([str(self.launcher), 'true'], env=self.env,
                                      stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, text=True) for _ in range(2)]
        for process in processes:
            stdout, stderr = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, stdout + stderr)
        ups = [call for call in self.calls() if call[0] == 'up']
        self.assertEqual(len(ups), 2)
        self.assertEqual(sum('--remove-existing-container' in call for call in ups), 1)

    def test_help_and_invalid_options_do_not_start_container(self):
        self.assertEqual(self.run_launcher('--help').returncode, 0)
        self.assertEqual(self.run_launcher('--invalid').returncode, 2)
        self.assertEqual(self.calls(), [])


if __name__ == '__main__':
    unittest.main()
