"""Actual Linux x64 process-provider cases; no image/Engine/normal admission."""
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
SELECTED = platform.system() == 'Linux' and platform.machine() in {'x86_64', 'amd64'}

# Original fixture assertions/counts, not expectations derived from the new
# provider. Each executable retains its own physical failure injections.
CASES = (
    ('region', 'region_cases', 38),
    ('region_range', 'region_range_cases', 23),
    ('extent_domain', 'extent_domain_cases', 15),
    ('domain_borrow', 'domain_borrow_cases', 19),
    ('domain_record', 'domain_record_cases', 10),
    ('domain_span', 'cases', 16),
    ('stopped_region', 'executed', 14),
    ('in_process_domain', 'in_process_domain_assertions', 23),
    ('domain_storage', 'discovered', 33),
    ('first_fit', 'native_first_fit_cases', 23),
    ('extent_work', 'discovered', 14),
    ('cleanup', 'native_cleanup_cases', 16),
    ('thread', 'executed', 12),
)


class LinuxX64OwnedProcess(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not SELECTED:
            raise RuntimeError('Requires actual Linux x64; no skipped qualification')
        cls.compiler = shutil.which(os.environ.get('CC', 'cc'))
        if cls.compiler is None:
            raise RuntimeError('The actual selected C compiler is required')
        parent = ROOT / '_build/linux-x64-owned-process'
        parent.mkdir(parents=True, exist_ok=True)
        cls.directory = Path(tempfile.mkdtemp(prefix='original-', dir=parent))
        cls.records = []
        cls.sequence = 0

    def invoke(self, label, command, *, timeout=60):
        type(self).sequence += 1
        stem = self.directory / f'{self.sequence:02d}-{label}'
        result = subprocess.run(command, capture_output=True, text=True,
                                timeout=timeout, env={**os.environ, 'CC': self.compiler})
        stem.with_suffix('.stdout').write_text(result.stdout)
        stem.with_suffix('.stderr').write_text(result.stderr)
        self.records.append({'command': command, 'returncode': result.returncode,
                             'stdout': str(stem.with_suffix('.stdout')),
                             'stderr': str(stem.with_suffix('.stderr'))})
        return result

    def compile(self, name, *, selected=True, extra=()):
        executable = self.directory / (name + ('-selected' if selected else '-unselected'))
        command = [self.compiler,
            '-std=c11', '-O0', '-Wall', '-Wextra', '-D_GNU_SOURCE', '-pthread',
            *(['-DACTQL_NATIVE_OWNED_LINUX_X64_PROCESS_DOMAIN=1'] if selected else []),
            *extra, str(PROVIDER / 'fixtures' / (name + '.c')), '-o', str(executable)]
        result = self.invoke(name + '-compile', command)
        return result, executable

    def test_01_unselected_and_conflicting_profiles_refuse_before_execution(self):
        result, executable = self.compile('region', selected=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Owned backing requires', result.stderr)
        self.assertFalse(executable.exists())
        result, _ = self.compile('region', extra=(
            '-DACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN=1',))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('cannot substitute another provider', result.stderr)
        result, _ = self.compile('region', extra=('-U_GNU_SOURCE',))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Select _GNU_SOURCE before', result.stderr)

    def test_02_actual_selected_layout_and_shared_atomics(self):
        result, executable = self.compile('linux_x64_process_abi')
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.invoke('abi-execute', [str(executable)], timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        facts = json.loads(result.stdout.strip().splitlines()[-1])
        self.assertEqual(facts['profile'], 'linux-x64-posix-process')
        self.assertEqual(facts['passed'], 1)
        self.assertTrue(facts['shared_pid_lock_free'])
        self.assertEqual((facts['int_bytes'], facts['pid_bytes'],
                          facts['pointer_bytes'], facts['off_bytes']), (4, 4, 8, 8))
        self.assertGreater(facts['page_bytes'], 0)
        self.assertGreater(facts['capacity_control_bytes'], 0)

    def test_03_original_physical_custody_and_retirement_cases(self):
        for name, field, expected in CASES:
            with self.subTest(fixture=name):
                result, executable = self.compile(name)
                self.assertEqual(result.returncode, 0, result.stderr)
                digest = hashlib.sha256(executable.read_bytes()).hexdigest()
                symbols = self.invoke(name + '-symbols',
                                      ['nm', '--defined-only', str(executable)])
                self.assertEqual(symbols.returncode, 0, symbols.stderr)
                self.assertNotIn('actql_native_owned_capture_image_fd', symbols.stdout)
                self.assertNotIn('actql_native_owned_rust_', symbols.stdout)
                result = self.invoke(name + '-execute', [str(executable)], timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)
                facts = json.loads(result.stdout.strip().splitlines()[-1])
                self.assertEqual(facts[field], expected)
                if 'passed' in facts:
                    self.assertEqual(facts['passed'], expected)
                if 'failed' in facts:
                    self.assertEqual(facts['failed'], 0)
                self.records.append({'fixture': name, 'sha256': digest,
                                     'actual': facts})

    @classmethod
    def tearDownClass(cls):
        # Retain original binaries/control/stdout/stderr even after a failure.
        # Removing a directory would never acknowledge a physical borrow.
        manifest = {'profile': 'linux-x64-posix-process',
                    'compiler': cls.compiler, 'records': cls.records,
                    'normal_profile': None, 'image_rust_engine': False}
        (cls.directory / 'original-controls.json').write_text(
            json.dumps(manifest, indent=2) + '\n')
        print('Retained Linux x64 process-provider controls: ' + str(cls.directory))


if __name__ == '__main__':
    unittest.main()
