"""Selected Darwin loader-condition checks, not startup or capacity admission."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LoaderEnvironment(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if sys.platform != 'darwin':
            raise RuntimeError('Select the actual Darwin loader diagnostic')
        evidence = os.environ.get('ACTQL_NATIVE_LOADER_ENVIRONMENT_EVIDENCE')
        if evidence:
            directory = Path(evidence)
            if not directory.is_absolute():
                raise ValueError('Evidence directory must be absolute')
            directory.mkdir(exist_ok=False)
        else:
            cls.temporary = tempfile.TemporaryDirectory(prefix='actql-loader-environment-')
            cls.addClassCleanup(cls.temporary.cleanup)
            directory = Path(cls.temporary.name)
        cls.exe = directory / 'environment'
        command = ['/Library/Developer/CommandLineTools/usr/bin/clang', '-std=c11',
                   '-O0', '-Wall', '-Wextra', '-Werror',
                   '-MD', '-MF', str(directory / 'environment.d'),
                   '-isysroot', '/Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk',
                   str(ROOT / 'src/platform_native/host_bootstrap/fixtures/initial_loader_environment.c'),
                   '-o', str(cls.exe)]
        subprocess.run(command, check=True, capture_output=True, text=True, timeout=60)
        if evidence:
            (directory / 'compile.json').write_text(json.dumps({
                'command': command, 'source': subprocess.check_output(
                    ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'workingDiff': subprocess.check_output(['git', 'diff', '--stat'], cwd=ROOT, text=True),
                'executableSha256': hashlib.sha256(cls.exe.read_bytes()).hexdigest(),
                'qualification': 'private loader environment C/O0 condition only; not OS facility admission',
            }, indent=2) + '\n')
        print('actual C/O0 executable sha256=' + hashlib.sha256(cls.exe.read_bytes()).hexdigest(), flush=True)

    def run_case(self, name, expected):
        # The fixture changes only its own process after exec. No inherited
        # injection attempt is launched just to test the private scanner.
        environment = {k: v for k, v in os.environ.items() if not k.startswith('DYLD_')}
        result = subprocess.run([str(self.exe), name], check=True, env=environment,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.stdout.strip(), expected)

    def test_vectors(self):
        self.run_case('vectors', 'bounded environment vectors passed')

    def test_terminated_vector_work_boundary(self):
        self.run_case('boundary', 'bounded environment termination passed')

    def test_actual_changed_environment_refusal_is_sticky(self):
        self.run_case('actual-change', 'actual environment change remains refused')

    def test_actual_initial_refusal_cannot_be_recaptured(self):
        self.run_case('actual-refusal', 'actual initial refusal remains refused')


class OsFacilityProtocol(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if sys.platform != 'darwin':
            raise RuntimeError('Select the actual Darwin process/thread diagnostic')
        evidence = os.environ.get('ACTQL_NATIVE_LOADER_ENVIRONMENT_EVIDENCE')
        if evidence:
            directory = Path(evidence)
            if not directory.is_absolute():
                raise ValueError('Evidence directory must be absolute')
            directory.mkdir(exist_ok=False)
        else:
            cls.temporary = tempfile.TemporaryDirectory(prefix='actql-os-facility-')
            cls.addClassCleanup(cls.temporary.cleanup)
            directory = Path(cls.temporary.name)
        cls.executables = {}
        for selection in ['selected', 'unselected']:
            exe = directory / selection
            command = ['/Library/Developer/CommandLineTools/usr/bin/clang', '-std=c11',
                       '-O0', '-Wall', '-Wextra', '-Werror',
                       '-MD', '-MF', str(directory / (selection + '.d')),
                       '-isysroot', '/Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk']
            if selection == 'selected':
                command += ['-DACTQL_NATIVE_COMMAND_OPERATIONAL_ENTRY',
                            '-DACTQL_NATIVE_CLIENT_SOURCE_SHA="1234567890abcdef1234567890abcdef12345678"']
            command += [str(ROOT / 'src/platform_native/host_bootstrap/fixtures/initial_os_facility.c'),
                        '-o', str(exe)]
            compiled = subprocess.run(command, capture_output=True, text=True, timeout=60)
            if evidence:
                (directory / (selection + '.compile.stdout')).write_text(compiled.stdout)
                (directory / (selection + '.compile.stderr')).write_text(compiled.stderr)
            if compiled.returncode:
                raise RuntimeError(compiled.stderr)
            cls.executables[selection] = exe
            identity = {'command': command, 'executableSha256': hashlib.sha256(exe.read_bytes()).hexdigest(),
                        'qualification': 'controlled parent port; not production startup or OS facility admission'}
            if evidence:
                (directory / (selection + '.json')).write_text(json.dumps(identity, indent=2) + '\n')
            print(selection + ' C/O0 executable sha256=' + identity['executableSha256'], flush=True)

    def run_case(self, name):
        environment = {k: v for k, v in os.environ.items() if not k.startswith('DYLD_')}
        exe = self.executables['unselected' if name == 'unselected' else 'selected']
        result = subprocess.run([str(exe), name], check=True, env=environment,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.stdout.strip(),
                         'initial OS facility protocol passed; production entry admission unexecuted')

    def test_unselected_has_no_facility(self):
        self.run_case('unselected')

    def test_one_capture_nominal_original_and_sticky_parent_refusal(self):
        self.run_case('one-shot')

    def test_real_foreign_thread_and_fork_cannot_use_original(self):
        self.run_case('foreign')

    def test_missing_original_cannot_be_reissued(self):
        self.run_case('missing')

    def test_partial_environment_refusal_keeps_same_observation(self):
        self.run_case('partial')


if __name__ == '__main__':
    unittest.main()
