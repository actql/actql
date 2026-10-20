"""Real packaging with inert resources; no Core or native runtime execution."""
from email.parser import BytesParser
from pathlib import Path
import json
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class RuntimeWheelLayoutTests(unittest.TestCase):
    def test_platform_package_uses_the_same_root_as_its_resource_inspector(self):
        with TemporaryDirectory(prefix='actql-runtime-wheel-layout-') as directory:
            stage = Path(directory)
            original = ROOT / 'packages/python-local-runtime'
            for name in ('pyproject.toml', 'setup.py', 'WASMTIME-LICENSE'):
                shutil.copyfile(original / name, stage / name)
            shutil.copyfile(ROOT / 'LICENSE', stage / 'LICENSE')
            for name in ('DUCKDB-LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE'):
                (stage / name).write_bytes(b'Independent packaging notice fixture\n')
            package = stage / 'src/actql_local_runtime'
            package.mkdir(parents=True)
            (package / '__init__.py').write_bytes(b'"""Inert packaging fixture."""\n')
            payloads = {'artifact.json': json.dumps({'platform': 'darwin-arm64'}).encode(),
                        'engine-recipe.json': b'{}', 'client_host_wasm.wasm': b'raw fixture',
                        'client_host_wasm.cwasm': b'image fixture', 'libduckdb.dylib': b'library fixture'}
            for name, value in payloads.items():
                (package / name).write_bytes(value)
            subprocess.run([sys.executable, '-m', 'build', '--wheel', '--no-isolation',
                            '--outdir', str(stage / 'dist'), str(stage)],
                           check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            wheels = list((stage / 'dist').glob('*.whl'))
            self.assertEqual(len(wheels), 1)
            with zipfile.ZipFile(wheels[0]) as wheel:
                for name, value in payloads.items():
                    self.assertEqual(wheel.read('actql_local_runtime/' + name), value)
                self.assertIn('actql_local_runtime/__init__.py', wheel.namelist())
                self.assertFalse(any('.data/purelib/' in name for name in wheel.namelist()))
                metadata = [name for name in wheel.namelist() if name.endswith('.dist-info/WHEEL')]
                self.assertEqual(len(metadata), 1)
                body = BytesParser().parsebytes(wheel.read(metadata[0]))
                self.assertEqual(body['Root-Is-Purelib'], 'false')
                self.assertEqual(body.get_all('Tag'), ['py3-none-macosx_11_0_arm64'])


if __name__ == '__main__':
    unittest.main()
