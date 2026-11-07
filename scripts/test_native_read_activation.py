"""Selected ordinary Native Read activation diagnostics; no installed CLI qualification."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROVIDER = ROOT / 'packages/python-local-runtime/native/pre-root'


class ReadActivationCustody(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        host = (platform.system(), platform.machine())
        targets = {('Linux', 'x86_64'): ('linux-x64', 'x86_64-unknown-linux-gnu'),
                   ('Linux', 'amd64'): ('linux-x64', 'x86_64-unknown-linux-gnu'),
                   ('Darwin', 'arm64'): ('darwin-arm64', 'aarch64-apple-darwin')}
        if host not in targets:
            raise RuntimeError('This diagnostic requires an existing pinned Native target')
        selected_platform, selected_target = targets[host]
        linux = selected_platform == 'linux-x64'
        home = Path(os.environ['MOON_HOME']).resolve()
        pin = json.loads((ROOT / 'toolchain.json').read_bytes())
        installed = json.loads((home / 'installed.json').read_bytes())
        if installed != {'pin': pin, 'platform': selected_platform}:
            raise RuntimeError('The original pinned Native MoonBit installation is required')
        compiler = shutil.which(os.environ.get('CC', 'cc'))
        if compiler is None:
            raise RuntimeError('The selected original compiler is required')
        parent = ROOT / '_build/native-read-activation'
        parent.mkdir(parents=True, exist_ok=True)
        cls.directory = Path(tempfile.mkdtemp(prefix='attempt-', dir=parent))
        target = cls.invoke('compiler-target', [compiler, '-dumpmachine']).stdout.strip()
        expected_target = (r'x86_64(?:-[^-]+)?-linux-gnu[^\s]*' if linux
                           else r'arm64-apple-darwin[^\s]*')
        if not re.fullmatch(expected_target, target):
            raise RuntimeError('The selected C compiler must match the actual pinned target')
        stage = cls.directory / 'derived'
        prepared = cls.invoke('prepare', ['python3', str(PROVIDER / 'prepare_scoped_read.py'),
            '--moonbit', str(home), '--destination', str(stage),
            '--target', selected_target])
        record = json.loads(prepared.stdout)
        if record['status'] != 'review-source-only' or record['installed_supplier']:
            raise RuntimeError('Preparation is not an installed supplier')
        cls.executable = cls.directory / 'read-activation'
        fixture = PROVIDER / 'fixtures/scoped_read.c'
        # Exact finite stock-File metadata belongs only to this diagnostic.
        # It does not admit any Request/control/managed constructor capacity.
        definitions = ['MOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC',
            'ACTQL_SCOPED_READ_ALLOCATOR', 'ACTQL_SCOPED_READ_PROVIDER',
            'ACTQL_READ_SEARCH_WORK',
            'OWNED_SOURCE=' + json.dumps(str(stage / 'owned_capacity.c'))]
        if linux:
            definitions += ['_GNU_SOURCE', 'ACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN',
                'ACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY', 'ACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS=64',
                'ACTQL_BUNDLE_STOCK_FILE_CONTROL_BYTES=1544']
        link = ['-Wl,--gc-sections', '-lm', '-ldl'] if linux else ['-Wl,-dead_strip']
        command = [compiler, '-finstrument-functions', '-std=c11', '-O0', '-fwrapv', '-fno-strict-aliasing',
            '-ffunction-sections', '-fdata-sections', '-pthread', '-I' + str(stage),
            *['-D' + value for value in definitions], str(fixture),
            *[str(stage / (name + '.c')) for name in ('backtrace', 'env', 'runtime', 'sync_io', 'utf')],
            str(stage / 'libmoonbitrun.o'), str(stage / 'libbacktrace.a'),
            *link, '-o', str(cls.executable)]
        cls.invoke('compile', command)
        (cls.directory / 'inputs.json').write_text(json.dumps({
            'profile': 'scoped-review-values', 'target': selected_target,
            'source': cls.invoke('head', ['git', 'rev-parse', 'HEAD']).stdout.strip(),
            'dirty': bool(cls.invoke('status', ['git', 'status', '--porcelain']).stdout),
            'compiler': {'path': str(Path(compiler).resolve()), 'target': target,
                'version': cls.invoke('compiler', [compiler, '--version']).stdout,
                'sha256': hashlib.sha256(Path(compiler).read_bytes()).hexdigest()},
            'toolchain': installed,
            'command': command, 'source_recipe': record,
            'fixture_sha256': hashlib.sha256(fixture.read_bytes()).hexdigest(),
            'executable_sha256': hashlib.sha256(cls.executable.read_bytes()).hexdigest(),
            'installed_capability': False,
        }, indent=2) + '\n')

    @classmethod
    def invoke(cls, name, command):
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=90)
        (cls.directory / (name + '.stdout')).write_text(result.stdout)
        (cls.directory / (name + '.stderr')).write_text(result.stderr)
        if result.returncode:
            raise RuntimeError(f'{name} failed ({result.returncode}): {result.stderr}')
        return result

    def execute(self, selection, expected):
        result = self.invoke(selection, [str(self.executable), '--' + selection + '-only'])
        record = json.loads(result.stdout.strip().splitlines()[-1])
        self.assertEqual(record['passed'], expected)
        self.assertEqual(record['failed'], 0)

    def test_ordinary_activation_failure_lost_ack_and_partial_cleanup(self):
        self.execute('read-activation', 3)

    def test_large_managed_and_file_activation_failure_custody(self):
        self.execute('read-raw-activation', 6)

    def test_existing_subpage_provenance_and_failed_retirement(self):
        self.execute('managed-subpage', 4)

    def test_managed_successor_search_does_not_rescan_live_prefix(self):
        self.execute('managed-successor-search', 1)

    def test_coalesced_block_fallback_preserves_original_live_slots(self):
        self.execute('managed-block-fallback', 1)

    def test_existing_managed_search_fallback(self):
        self.execute('managed-search-fallback', 1)

    def test_existing_managed_search_and_cleanup(self):
        self.execute('managed-search', 1)

    def test_existing_cleanup_snapshot(self):
        self.execute('cleanup-snapshot', 1)

    def test_existing_managed_alias_constructor_and_retirement(self):
        self.execute('scoped-managed-alias', 1)

    @classmethod
    def tearDownClass(cls):
        print('Retained ordinary Read activation diagnostic: ' + str(cls.directory))


if __name__ == '__main__':
    unittest.main()
