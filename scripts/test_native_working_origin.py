"""Selected Native working-origin custody; no Common or installed qualification."""
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

from python_host_bootstrap_source import INPUTS

ROOT = Path(__file__).resolve().parents[1]
PROVIDER = ROOT / 'packages/python-local-runtime/native/pre-root'


class WorkingOriginCustody(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if platform.system() != 'Linux' or platform.machine() not in {'x86_64', 'amd64'}:
            raise RuntimeError('This diagnostic requires the actual Linux x64 target')
        home = Path(os.environ['MOON_HOME']).resolve()
        pin = json.loads((ROOT / 'toolchain.json').read_bytes())
        installed = json.loads((home / 'installed.json').read_bytes())
        if installed != {'pin': pin, 'platform': 'linux-x64'}:
            raise RuntimeError('The original pinned Linux x64 MoonBit installation is required')
        compiler = shutil.which(os.environ.get('CC', 'cc'))
        if compiler is None:
            raise RuntimeError('The selected original compiler is required')
        parent = ROOT / '_build/native-working-origin'
        parent.mkdir(parents=True, exist_ok=True)
        cls.directory = Path(tempfile.mkdtemp(prefix='attempt-', dir=parent))
        target = cls.invoke('compiler-target', [compiler, '-dumpmachine']).stdout.strip()
        if not re.fullmatch(r'x86_64(?:-[^-]+)?-linux-gnu[^\s]*', target):
            raise RuntimeError('The selected C compiler must target Linux x64 GNU')
        stage = cls.directory / 'derived'
        prepared = cls.invoke('prepare', ['python3', str(PROVIDER / 'prepare_scoped_read.py'),
            '--moonbit', str(home), '--destination', str(stage),
            '--target', 'x86_64-unknown-linux-gnu'])
        record = json.loads(prepared.stdout)
        if record['status'] != 'review-source-only' or record['installed_supplier']:
            raise RuntimeError('Preparation is not an installed supplier')
        cls.executable = cls.directory / 'working-origin'
        fixture = ROOT / 'src/platform_native/host_bootstrap/working_origin_fixture.c'
        # Exact finite stock-File metadata belongs only to this diagnostic.
        # It does not admit any Request/control/managed constructor capacity.
        definitions = ['_GNU_SOURCE', 'MOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC',
            'ACTQL_SCOPED_READ_ALLOCATOR',
            'ACTQL_SCOPED_READ_PROVIDER=' + json.dumps(str(stage / 'owned_capacity.c')),
            'ACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN',
            'ACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY', 'ACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS=64',
            'ACTQL_BUNDLE_STOCK_FILE_CONTROL_BYTES=1544']
        command = [compiler, '-std=c11', '-O0', '-fwrapv', '-fno-strict-aliasing',
            '-ffunction-sections', '-fdata-sections', '-pthread', '-I' + str(stage),
            *['-D' + value for value in definitions], str(fixture),
            *[str(stage / (name + '.c')) for name in ('backtrace', 'env', 'runtime', 'sync_io', 'utf')],
            str(stage / 'libmoonbitrun.o'), str(stage / 'libbacktrace.a'),
            '-Wl,--gc-sections', '-lm', '-ldl', '-o', str(cls.executable)]
        cls.invoke('compile', command)
        (cls.directory / 'inputs.json').write_text(json.dumps({
            'profile': 'scoped-review-values', 'target': 'x86_64-unknown-linux-gnu',
            'source': cls.invoke('head', ['git', 'rev-parse', 'HEAD']).stdout.strip(),
            'dirty': bool(cls.invoke('status', ['git', 'status', '--porcelain']).stdout),
            'compiler': {'path': str(Path(compiler).resolve()), 'target': target,
                'version': cls.invoke('compiler', [compiler, '--version']).stdout,
                'sha256': hashlib.sha256(Path(compiler).read_bytes()).hexdigest()},
            'toolchain': installed,
            'command': command, 'source_recipe': record,
            'fixture_sha256': hashlib.sha256(fixture.read_bytes()).hexdigest(),
            'bootstrap_inputs': {name: {
                'bytes': (ROOT / name).stat().st_size,
                'sha256': hashlib.sha256((ROOT / name).read_bytes()).hexdigest(),
            } for name in INPUTS},
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

    def test_selected_unbound_bound_refused_and_pending_retirement(self):
        result = self.invoke('lifecycle', [str(self.executable)])
        record = json.loads(result.stdout.strip().splitlines()[-1])
        self.assertEqual(record, {'passed': 5, 'failed': 0})

    @classmethod
    def tearDownClass(cls):
        print('Retained working-origin Native diagnostic: ' + str(cls.directory))


if __name__ == '__main__':
    unittest.main()
