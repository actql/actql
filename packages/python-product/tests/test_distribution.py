"""Independent product/cohort metadata fixtures; no runtime or product E2E."""
from email.message import Message
import importlib.abc
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
import tomllib
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
from python_release_cohort import read_cohort

spec = importlib.util.spec_from_file_location('wheel_cohort', ROOT / 'scripts/build-python-product-wheels.py')
cohort = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cohort)


class ProductDistributionTests(unittest.TestCase):
    def projects(self, root):
        for name in ('python-product', 'python-sdk', 'python-local-runtime'):
            path = root / 'packages' / name
            path.mkdir(parents=True)
            shutil.copyfile(ROOT / 'packages' / name / 'pyproject.toml', path / 'pyproject.toml')

    def test_three_metadata_packages_share_one_cohort_and_sdk_stays_light(self):
        self.assertEqual(read_cohort(ROOT), '0.0.0.dev0')
        product = tomllib.loads((ROOT / 'packages/python-product/pyproject.toml').read_text())['project']
        self.assertEqual(product['name'], 'actql')
        self.assertEqual(product['dependencies'], ['actql-sdk==0.0.0.dev0', 'actql-local-runtime==0.0.0.dev0'])

    def test_missing_old_or_wrong_cohort_and_local_sdk_extra_reject(self):
        changes = [('python-product', 'version = "0.0.0.dev0"', 'version = "0.0.1"'),
                   ('python-product', 'actql-sdk==0.0.0.dev0', 'actql-sdk>=0.0.0.dev0'),
                   ('python-local-runtime', 'wasmtime==38.0.0', 'wasmtime==39.0.0'),
                   ('python-sdk', '[project.optional-dependencies]',
                    '[project.optional-dependencies]\nlocal = ["actql-local-runtime==0.0.0.dev0"]')]
        for package, old, new in changes:
            with self.subTest(package=package), TemporaryDirectory() as directory:
                root = Path(directory)
                self.projects(root)
                file = root / 'packages' / package / 'pyproject.toml'
                file.write_text(file.read_text().replace(old, new))
                with self.assertRaises(ValueError): read_cohort(root)

    def test_facade_aliases_same_sdk_and_never_imports_runtime_at_import(self):
        product = ROOT / 'packages/python-product/src'
        sdk = ROOT / 'packages/python-sdk/src'
        code = '''
import importlib.abc, sys
class RefuseRuntime(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path=None, target=None):
        if fullname.split('.')[0] in ('wasmtime','duckdb','actql_local_runtime'):
            raise AssertionError('Facade imported a Local engine')
sys.meta_path.insert(0, RefuseRuntime())
import actql, actql_sdk
assert set(actql.__all__) == set(actql_sdk.__all__) | {'open'}
for name in actql_sdk.__all__:
    assert getattr(actql, name) is getattr(actql_sdk, name), name
assert callable(actql.open) and actql.open is not actql.Client.open
assert 'wasmtime' not in sys.modules and 'duckdb' not in sys.modules
'''
        result = subprocess.run([sys.executable, '-I', '-c',
            f'import sys;sys.path[:0]=[{str(product)!r},{str(sdk)!r}];\n'+code],
            capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def wheel(self, directory, name, *, requirements, tag='py3-none-any', extra=None):
        path = directory / f"{name.replace('-', '_')}-0.0.0.dev0-{tag}.whl"
        metadata = Message()
        metadata['Metadata-Version'], metadata['Name'], metadata['Version'] = '2.4', name, '0.0.0.dev0'
        for requirement in requirements: metadata['Requires-Dist'] = requirement
        if extra is not None: metadata['Provides-Extra'] = extra
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('fixture.dist-info/METADATA', metadata.as_bytes())
            archive.writestr('fixture.dist-info/WHEEL', 'Wheel-Version: 1.0\nTag: '+tag+'\n')
            if name == 'actql':
                for member in ('actql/__init__.py', 'actql/__init__.pyi', 'actql/py.typed'):
                    archive.writestr(member, b'')
        return path

    def test_wheel_consumer_requires_exact_default_dependencies_tags_and_facade(self):
        for name, dependencies, tag in [
                ('actql', ['actql-sdk==0.0.0.dev0','actql-local-runtime==0.0.0.dev0'], 'py3-none-any'),
                ('actql-sdk', ['httpx==0.28.1','rfc8785==0.1.4'], 'py3-none-any'),
                ('actql-local-runtime', ['wasmtime==38.0.0'], 'py3-none-macosx_11_0_arm64')]:
            with self.subTest(name=name), TemporaryDirectory() as directory:
                path = self.wheel(Path(directory), name, requirements=dependencies, tag=tag)
                cohort.wheel_metadata(path, name, '0.0.0.dev0')
                with self.assertRaises(ValueError): cohort.wheel_metadata(path, name, '0.0.1')
                path = self.wheel(Path(directory), name, requirements=dependencies+['wasmtime==38.0.0'], tag=tag)
                with self.assertRaises(ValueError): cohort.wheel_metadata(path, name, '0.0.0.dev0')

    def test_sdk_local_extra_and_native_bytes_are_rejected_in_wheel(self):
        with TemporaryDirectory() as directory:
            path = self.wheel(Path(directory), 'actql-sdk',
                requirements=['httpx==0.28.1','rfc8785==0.1.4'], extra='local')
            with self.assertRaises(ValueError): cohort.wheel_metadata(path, 'actql-sdk', '0.0.0.dev0')
            path = self.wheel(Path(directory), 'actql-sdk', requirements=['httpx==0.28.1','rfc8785==0.1.4'])
            with zipfile.ZipFile(path, 'a') as archive: archive.writestr('hidden/engine.wasm', b'fixture')
            with self.assertRaises(ValueError): cohort.wheel_metadata(path, 'actql-sdk', '0.0.0.dev0')

    def test_runtime_wheel_must_copy_exact_original_component_and_notice_bytes(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / 'original'
            artifact.mkdir()
            stage = root / 'stage'
            package = stage / 'src/actql_local_runtime'
            private = package / '_wasmtime'
            (private / 'darwin-aarch64').mkdir(parents=True)
            names = ('artifact.json', 'engine-recipe.json', 'client_host_wasm.cwasm',
                     'client_host_wasm.wasm', 'libduckdb.dylib',
                     'LICENSE', 'DUCKDB-LICENSE','MOONBIT-CORE-LICENSE','MOONBIT-CORE-NOTICE')
            originals = []
            wheel = root / 'runtime.whl'
            with zipfile.ZipFile(wheel, 'w') as archive:
                for name in names:
                    raw = b'independent fixture '+name.encode()
                    (artifact / name).write_bytes(raw)
                    archive.writestr('actql_local_runtime/'+name, raw)
                    originals.append(artifact / name)
                for relative in ('WASMTIME-LICENSE', '_wasmtime/bindings.py',
                                 '_wasmtime/darwin-aarch64/_libwasmtime.dylib'):
                    original = package / relative
                    original.write_bytes(b'independent private fixture '+relative.encode())
                    archive.writestr('actql_local_runtime/'+relative, original.read_bytes())
                    originals.append(original)
            self.assertEqual(set(cohort.runtime_wheel_components(wheel, artifact, stage)),
                             {'actql_local_runtime/_wasmtime/bindings.py'})
            # Same length is insufficient for either artifact or private stage bytes.
            for original in originals:
                with self.subTest(member=original.name):
                    before = original.read_bytes()
                    original.write_bytes(b'X'+before[1:])
                    with self.assertRaisesRegex(ValueError, 'digest'):
                        cohort.runtime_wheel_components(wheel, artifact, stage)
                    original.write_bytes(before)


if __name__ == '__main__':
    unittest.main()
