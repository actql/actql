"""Actual Linux x64 process-provider cases; no image/Engine/normal admission."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import shlex
import subprocess
import sys
import tempfile
import time
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
    ('process_inventory', 'process_inventory_cases', 19),
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
        cls.context = {}
        cls.source = cls.invoke('source', ['git', 'rev-parse', 'HEAD']).stdout.strip()
        status = cls.invoke('source-clean', ['git', 'status', '--porcelain'])
        if status.returncode or status.stdout:
            raise RuntimeError('Requires the same clean committed source')
        recipe = json.loads((PROVIDER / 'linux-x64-process-source.json').read_bytes())
        for item in recipe['inputs']:
            data = (ROOT / item['path']).read_bytes()
            if len(data) != item['bytes'] or hashlib.sha256(data).hexdigest() != item['sha256']:
                raise RuntimeError('Changed process-provider source: ' + item['path'])
        cls.context['source'] = cls.source
        cls.context['recipe'] = hashlib.sha256(
            (PROVIDER / 'linux-x64-process-source.json').read_bytes()).hexdigest()
        cls.pin = json.loads((ROOT / 'toolchain.json').read_bytes())
        cls.moon_home = Path(os.environ['MOON_HOME'])
        installed = json.loads((cls.moon_home / 'installed.json').read_bytes())
        if installed != {'pin': cls.pin, 'platform': 'linux-x64'}:
            raise RuntimeError('Requires the original pinned Linux x64 MoonBit installation')
        cls.context['toolchain'] = installed
        cls.context['tools'] = {}
        for name in ('moon', 'moonc'):
            binary = cls.moon_home / 'bin' / name
            cls.context['tools'][name] = {'path': str(binary),
                'sha256': hashlib.sha256(binary.read_bytes()).hexdigest()}
        moon = cls.invoke('moon-version', [str(cls.moon_home / 'bin/moon'), 'version'])
        moonc = cls.invoke('moonc-version', [str(cls.moon_home / 'bin/moonc'), '-v'])
        if (moon.returncode or not moon.stdout.splitlines()
                or moon.stdout.splitlines()[0] != 'moon ' + cls.pin['moon']
                or moonc.returncode or moonc.stdout.strip() != cls.pin['moonc']):
            raise RuntimeError('Actual MoonBit compiler versions differ from toolchain.json')
        target = cls.invoke('cc-target', [cls.compiler, '-dumpmachine'])
        version = cls.invoke('cc-version', [cls.compiler, '--version'])
        if (target.returncode or version.returncode
                or not re.fullmatch(r'x86_64(?:-[^-]+)?-linux-gnu[^\s]*', target.stdout.strip())):
            raise RuntimeError('Requires the actual Linux x64 GNU compiler target')
        cls.context['c_compiler'] = {'path': str(Path(cls.compiler).resolve()),
            'sha256': hashlib.sha256(Path(cls.compiler).read_bytes()).hexdigest(),
            'target': target.stdout.strip(), 'version': version.stdout}
        cls.persist()

    @classmethod
    def persist(cls, **extra):
        manifest = {'profile': 'linux-x64-posix-process', 'context': cls.context,
                    'records': cls.records, 'normal_profile': None,
                    'image_rust_engine': False, **extra}
        (cls.directory / 'original-controls.json').write_text(
            json.dumps(manifest, indent=2) + '\n')

    @classmethod
    def invoke(cls, label, command, *, timeout=60, stdin=None):
        cls.sequence += 1
        stem = cls.directory / f'{cls.sequence:02d}-{label}'
        started = time.monotonic()
        try:
            result = subprocess.run(command, capture_output=True, text=True,
                                    timeout=timeout, cwd=ROOT, stdin=stdin,
                                    env={**os.environ, 'CC': cls.compiler})
        except subprocess.TimeoutExpired as error:
            def output(value):
                return value.decode(errors='replace') if isinstance(value, bytes) else value or ''
            stem.with_suffix('.stdout').write_text(output(error.stdout))
            stem.with_suffix('.stderr').write_text(output(error.stderr))
            cls.records.append({'command': command, 'returncode': None,
                'timed_out': True, 'timeout_seconds': timeout,
                'seconds': time.monotonic() - started, 'stdout': str(stem.with_suffix('.stdout')),
                'stderr': str(stem.with_suffix('.stderr'))})
            cls.persist()
            raise
        stem.with_suffix('.stdout').write_text(result.stdout)
        stem.with_suffix('.stderr').write_text(result.stderr)
        cls.records.append({'command': command, 'returncode': result.returncode,
            'timed_out': False, 'timeout_seconds': timeout,
            'seconds': time.monotonic() - started, 'stdout': str(stem.with_suffix('.stdout')),
            'stderr': str(stem.with_suffix('.stderr'))})
        cls.persist()
        return result

    def compile(self, name, *, selected=True, extra=()):
        executable = self.directory / (name + ('-selected' if selected else '-unselected'))
        dependencies = executable.with_suffix('.d')
        command = [self.compiler,
            '-std=c11', '-O0', '-Wall', '-Wextra', '-D_GNU_SOURCE', '-pthread',
            '-I', str(PROVIDER),
            '-MD', '-MF', str(dependencies),
            *(['-DACTQL_NATIVE_OWNED_LINUX_X64_PROCESS_DOMAIN=1'] if selected else []),
            *extra, str(PROVIDER / 'fixtures' / (name + '.c')), '-o', str(executable)]
        result = self.invoke(name + '-compile', command)
        if result.returncode == 0:
            members = shlex.split(dependencies.read_text().replace('\\\n', ' ').split(':', 1)[1])
            inputs = []
            for member in members:
                path = Path(member)
                if not path.is_absolute():
                    path = ROOT / path
                data = path.read_bytes()
                inputs.append({'path': str(path), 'bytes': len(data),
                               'sha256': hashlib.sha256(data).hexdigest()})
            self.records.append({'compile': name, 'actual_source_and_headers': inputs})
            self.persist()
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
                if name == 'domain_span':
                    # This ORIGINAL fixture consumes an already-open private
                    # 64-page regular FD at stdin, not a terminal or a pipe.
                    # The harness retains its own descriptor until child exit;
                    # its close is separate from all fixture domain/loan ACKs.
                    with tempfile.TemporaryFile(dir=self.directory) as backing:
                        os.fchmod(backing.fileno(), 0o600)
                        os.ftruncate(backing.fileno(), 64 * os.sysconf('SC_PAGE_SIZE'))
                        before = os.fstat(backing.fileno())
                        result = self.invoke(name + '-execute', [str(executable)],
                                             timeout=30, stdin=backing)
                        after = os.fstat(backing.fileno())
                        self.assertEqual((before.st_dev, before.st_ino, before.st_size),
                                         (after.st_dev, after.st_ino, after.st_size))
                        self.records.append({'fixture_stdin': name,
                            'device': before.st_dev, 'inode': before.st_ino,
                            'bytes': before.st_size, 'mode': before.st_mode,
                            'original_open_after_child': not backing.closed})
                    self.records.append({'fixture_stdin': name,
                                         'caller_descriptor_closed': backing.closed})
                    self.persist()
                else:
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
        head = cls.invoke('source-after', ['git', 'rev-parse', 'HEAD'])
        status = cls.invoke('source-clean-after', ['git', 'status', '--porcelain'])
        if head.returncode or head.stdout.strip() != cls.source or status.returncode or status.stdout:
            raise RuntimeError('Selected source changed during actual qualification')
        for tool in (*cls.context['tools'].values(), cls.context['c_compiler']):
            if hashlib.sha256(Path(tool['path']).read_bytes()).hexdigest() != tool['sha256']:
                raise RuntimeError('An original compiler changed during qualification')
        if json.loads((cls.moon_home / 'installed.json').read_bytes()) != cls.context['toolchain']:
            raise RuntimeError('Original toolchain installation changed during qualification')
        cls.persist()
        print('Retained Linux x64 process-provider controls: ' + str(cls.directory))


if __name__ == '__main__':
    program = unittest.main(exit=False, verbosity=2)
    result = program.result
    complete = result.wasSuccessful() and result.testsRun == 3 and not result.skipped
    summary = {'tests_run': result.testsRun, 'skipped': len(result.skipped),
               'failures': len(result.failures), 'errors': len(result.errors),
               'complete': complete, 'expected_physical_fixtures': len(CASES)}
    if hasattr(LinuxX64OwnedProcess, 'directory'):
        LinuxX64OwnedProcess.persist(test_result=summary)
    print(json.dumps(summary))
    sys.exit(0 if complete else 1)
