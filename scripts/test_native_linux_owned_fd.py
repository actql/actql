"""Actual selected Linux arm64 FD/extent cases, not process-domain admission."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROVIDER = ROOT / 'packages/python-local-runtime/native/pre-root'
SELECTED = platform.system() == 'Linux' and platform.machine() in {'aarch64', 'arm64'}


@unittest.skipUnless(SELECTED, 'Requires the actual selected Linux arm64 target')
class LinuxOwnedFD(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = Path(tempfile.mkdtemp(prefix='actql-linux-owned-fd-'))
        cls.compiler = shutil.which(os.environ.get('CC', 'cc'))
        if cls.compiler is None:
            raise RuntimeError('The selected Linux C compiler is required')
        cls.identities = {}
        cls.results = {}

    @classmethod
    def tearDownClass(cls):
        # Fixture FD/view cleanup is asserted by each actual C executable.
        # Removing this harness directory is never a physical retirement ACK.
        print('Retained Linux owned-FD diagnostic: ' + str(cls.directory))
        print(json.dumps({'target': 'linux-arm64',
                          'native_cases': sum(cls.results.values()),
                          'native_executions_succeeded': len(cls.results),
                          'executables': cls.identities,
                          'process_domain_admission': False,
                          'normal_profile': None, 'image_rust_engine': False}))

    def compile(self, name, *, selected=True):
        source = PROVIDER / 'fixtures' / (name + '.c')
        executable = self.directory / (name if selected else name + '-unselected')
        command = [self.compiler, '-std=c11', '-O0', '-Wall', '-Wextra',
                   '-D_GNU_SOURCE', '-pthread']
        if selected:
            command.append('-DACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN=1')
        command += [str(source), '-o', str(executable)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        (self.directory / (name + ('-selected' if selected else '-unselected') + '.stderr')).write_text(result.stderr)
        if selected:
            self.assertEqual(result.returncode, 0, result.stderr)
            self.identities[name] = hashlib.sha256(executable.read_bytes()).hexdigest()
            symbols = subprocess.run(['nm', '--defined-only', str(executable)],
                                     capture_output=True, text=True, timeout=10)
            self.assertEqual(symbols.returncode, 0, symbols.stderr)
            self.assertNotIn('actql_native_owned_capture_image_fd', symbols.stdout)
            self.assertNotIn('actql_native_owned_rust_', symbols.stdout)
        return result, executable

    def execute(self, name, field, expected):
        _, executable = self.compile(name)
        result = subprocess.run([str(executable)], capture_output=True,
                                text=True, timeout=30)
        (self.directory / (name + '.stdout')).write_text(result.stdout)
        (self.directory / (name + '.stderr')).write_text(result.stderr)
        self.assertEqual(result.returncode, 0, result.stderr)
        body = json.loads(result.stdout.strip().splitlines()[-1])
        self.assertEqual(body[field], expected)
        self.assertEqual(body['passed'], expected)
        self.assertEqual(body['worker'], 0)
        self.assertEqual(body['vm'], 0)
        self.assertEqual(body['public_e2e'], 0)
        self.results[name] = expected

    def test_01_requires_explicit_selected_backend(self):
        result, executable = self.compile('region', selected=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('explicitly selected Linux arm64', result.stderr)
        self.assertFalse(executable.exists())

    def test_02_same_fd_extent_and_failed_unmap(self):
        self.execute('region', 'region_cases', 38)

    def test_03_same_original_domain_and_failed_retirement(self):
        self.execute('extent_domain', 'extent_domain_cases', 15)



if __name__ == '__main__':
    unittest.main()
