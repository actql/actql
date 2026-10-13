"""Receipt/copy assembly tests, never actual Wasm, DuckDB or wheel evidence."""
from __future__ import annotations

from contextlib import ExitStack
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('local_artifact_producer', ROOT / 'scripts/produce-python-local-runtime.py')
assert spec is not None and spec.loader is not None
producer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(producer)
from actql_sdk._local_distribution import LocalInstallationError  # noqa: E402
hash_bytes = lambda value: hashlib.sha256(value).hexdigest()


class LocalArtifactProducerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='actql-python-artifact-unit-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        paths = ['toolchain.json', 'vendor/duckdb/1.4.3/manifest.json',
                 'packages/python-product/pyproject.toml',
                 'packages/python-sdk/pyproject.toml', 'packages/python-local-runtime/pyproject.toml',
                 'packages/python-local-runtime/setup.py',
                 'packages/python-local-runtime/src/actql_local_runtime/__init__.py']
        paths += [str(path.relative_to(ROOT)) for path in producer.recipe.notice_originals().values()]
        for filename in paths:
            target = self.source / filename
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / filename, target)
        self.git('init', '-q')
        self.commit()
        self.module = self.root / 'original.wasm'
        self.library = self.root / 'original.dylib'
        # Synthetic format headers and declared receipt records exercise only
        # finite producer assembly. Neither component has been executed.
        self.module.write_bytes(b'\0asm\x01\0\0\0fixture-not-an-executed-module')
        command = struct.pack('<6I', 0x32, 24, 1, 11 << 16, 11 << 16, 0)
        self.library.write_bytes(struct.pack('<8I', 0xfeedfacf, 0x0100000c, 0, 6, 1, len(command), 0, 0) + command)
        digest = hash_bytes(self.module.read_bytes())
        self.core = {'source_sha': self.head, 'module': str(self.module), 'module_sha256': digest,
                     'scope': 'physical_buffer_bridge_workspace_only',
                     'moonc': json.loads((self.source / 'toolchain.json').read_bytes())['moonc'],
                     'python': 'synthetic fixture', 'positive_native_result_acceptance': False,
                     'public_local_acceptance': False,
                     **{name: {'success': True, 'module_sha256': digest, 'cases': ['synthetic fixture']}
                        for name in ('result', 'physical', 'workspace')}}
        self.duckdb = {'source_sha': self.head, 'library': str(self.library),
                       'library_sha256': hash_bytes(self.library.read_bytes()), 'library_version': 'v1.4.3',
                       'python': 'synthetic fixture', 'platform': 'macOS-synthetic-fixture', 'machine': 'arm64',
                       'tests': 20, 'success': True, 'module_source': None, 'workspace_selection': False,
                       'public_local_acceptance': False, 'wheel_acceptance': False}
        self.core_file = self.root / 'core.json'
        self.duckdb_file = self.root / 'duckdb.json'
        self.write_receipts()
        self.output = self.root / 'artifact'
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(producer, 'ROOT', self.source))
        self.stack.enter_context(patch.object(producer.recipe, 'ROOT', self.source))
        self.stack.enter_context(patch.object(producer.sys, 'platform', 'darwin'))
        self.stack.enter_context(patch.object(producer.platform, 'machine', return_value='arm64'))
        self.stack.enter_context(patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Engine import')))

    def git(self, *args):
        return subprocess.check_output(['git', '-c', 'user.name=Fixture', '-c',
                                        'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false',
                                        *args], cwd=self.source, text=True).strip()

    def commit(self):
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        self.head = self.git('rev-parse', 'HEAD')

    def write_receipts(self):
        self.core_file.write_text(json.dumps(self.core))
        self.duckdb_file.write_text(json.dumps(self.duckdb))

    def run_producer(self):
        return producer.produce(self.core_file, self.duckdb_file, self.output)

    def test_fixed_originals_copy_and_stage_through_existing_recipe_without_engine_loading(self):
        result = self.run_producer()
        self.assertEqual(result['source_sha'], self.head)
        self.assertEqual(result['core_abi'], producer.LOCAL_CORE_ABI)
        self.assertEqual(result['artifact_sha256'], hash_bytes((self.output / 'artifact.json').read_bytes()))
        self.assertEqual(result['core_receipt_sha256'], hash_bytes(self.core_file.read_bytes()))
        self.assertEqual((self.output / 'client_host_wasm.wasm').read_bytes(), self.module.read_bytes())
        self.assertEqual((self.output / 'libduckdb.dylib').read_bytes(), self.library.read_bytes())
        for name, path in producer.recipe.notice_originals().items():
            self.assertEqual((self.output / name).read_bytes(), path.read_bytes())
        self.assertFalse(result['runtime_executed'])
        self.assertFalse(result['wheel_built'])
        self.assertFalse(result['public_local_accepted'])
        stage = self.root / 'stage'
        prepared = producer.recipe.prepare(self.output, stage)
        self.assertEqual(prepared['source_sha'], self.head)
        self.assertFalse(prepared['runtime_executed'])

    def test_foreign_core_or_duckdb_source_rejected_before_destination_creation(self):
        for receipt in (self.core, self.duckdb):
            with self.subTest(receipt='core' if receipt is self.core else 'duckdb'):
                receipt['source_sha'] = '0' * 40
                self.write_receipts()
                with self.assertRaisesRegex(ValueError, 'exact producer source'):
                    self.run_producer()
                self.assertFalse(self.output.exists())
                receipt['source_sha'] = self.head

    def test_failed_or_foreign_module_physical_evidence_does_not_form_an_artifact(self):
        for change in ({'success': False}, {'module_sha256': '0' * 64}, {'cases': []}):
            with self.subTest(change=change):
                original = self.core['physical'].copy()
                self.core['physical'].update(change)
                self.write_receipts()
                with self.assertRaisesRegex(ValueError, 'same module'):
                    self.run_producer()
                self.assertFalse(self.output.exists())
                self.core['physical'] = original

    def test_changed_component_digest_and_symlink_are_rejected_before_copy(self):
        original = self.module.read_bytes()
        self.module.write_bytes(original + b'changed')
        with self.assertRaises(LocalInstallationError):
            self.run_producer()
        self.assertFalse(self.output.exists())
        self.module.unlink()
        self.module.symlink_to(self.library)
        with self.assertRaisesRegex(ValueError, 'regular file'):
            self.run_producer()
        self.assertFalse(self.output.exists())

    def test_unconfirmed_standalone_version_or_profile_is_refused(self):
        for key, value in [('library_version', 'v1.5.5'), ('tests', 0), ('tests', True),
                           ('machine', 'x86_64'), ('platform', 'Linux-fixture'),
                           ('success', False), ('workspace_selection', True)]:
            with self.subTest(key=key):
                original = self.duckdb[key]
                self.duckdb[key] = value
                self.write_receipts()
                with self.assertRaisesRegex(ValueError, 'selected physical profile'):
                    self.run_producer()
                self.assertFalse(self.output.exists())
                self.duckdb[key] = original

    def test_compiler_closed_receipt_and_duplicate_fields_are_refused(self):
        self.core['moonc'] = 'foreign compiler'
        self.write_receipts()
        with self.assertRaisesRegex(ValueError, 'pinned compiler'):
            self.run_producer()
        self.core['moonc'] = json.loads((self.source / 'toolchain.json').read_bytes())['moonc']
        self.core['extra'] = True
        self.write_receipts()
        with self.assertRaisesRegex(ValueError, 'original physical-boundary'):
            self.run_producer()
        del self.core['extra']
        self.core_file.write_text(json.dumps(self.core)[:-1] + ', "source_sha": "duplicate"}')
        with self.assertRaisesRegex(LocalInstallationError, 'Duplicate'):
            self.run_producer()
        self.assertFalse(self.output.exists())

    def test_original_library_target_is_reused_without_abi_header_acceptance_claim(self):
        value = bytearray(self.library.read_bytes())
        struct.pack_into('<I', value, 4, 0x01000007)
        self.library.write_bytes(value)
        self.duckdb['library_sha256'] = hash_bytes(value)
        self.write_receipts()
        with self.assertRaisesRegex(ValueError, 'arm64'):
            self.run_producer()
        self.assertFalse(self.output.exists())

    def test_postcopy_corruption_and_notice_substitution_keep_failed_output_unaccepted(self):
        copy = producer.copy_original
        for filename in ('client_host_wasm.wasm', 'MOONBIT-CORE-NOTICE'):
            with self.subTest(filename=filename):
                def corrupt(source, destination, maximum, digest):
                    value = copy(source, destination, maximum, digest)
                    if Path(destination).name == filename:
                        Path(destination).write_bytes(b'altered original')
                    return value
                with patch.object(producer, 'copy_original', side_effect=corrupt):
                    with self.assertRaises(LocalInstallationError):
                        self.run_producer()
                self.assertFalse((self.output / 'producer.json').exists())
                shutil.rmtree(self.output)

    def test_original_receipt_change_during_copy_is_not_certified(self):
        copy = producer.copy_original
        def change(source, destination, maximum, digest):
            result = copy(source, destination, maximum, digest)
            self.core_file.write_bytes(self.core_file.read_bytes() + b'\n')
            return result
        with patch.object(producer, 'copy_original', side_effect=change):
            with self.assertRaisesRegex(ValueError, 'receipt changed'):
                self.run_producer()
        self.assertFalse((self.output / 'producer.json').exists())

    def test_component_growth_or_symlink_after_precheck_is_refused_before_copy(self):
        original = self.module.read_bytes()
        check = producer.recipe.library_target
        for replacement in ('grow', 'symlink'):
            with self.subTest(replacement=replacement):
                def replace(library):
                    check(library)
                    if replacement == 'grow':
                        with self.module.open('ab') as stream:
                            stream.truncate(32 * 1024 * 1024 + 1)
                    else:
                        self.module.unlink()
                        self.module.symlink_to(self.library)
                with patch.object(producer.recipe, 'library_target', side_effect=replace):
                    error = LocalInstallationError if replacement == 'grow' else OSError
                    with self.assertRaises(error):
                        self.run_producer()
                self.assertFalse((self.output / 'client_host_wasm.wasm').exists())
                self.assertFalse((self.output / 'producer.json').exists())
                self.module.unlink()
                self.module.write_bytes(original)
                shutil.rmtree(self.output)

    def test_dirty_source_and_existing_destination_cannot_be_overwritten(self):
        (self.source / 'uncommitted').write_text('dirty')
        with self.assertRaisesRegex(ValueError, 'clean'):
            self.run_producer()
        (self.source / 'uncommitted').unlink()
        self.output.mkdir()
        (self.output / 'marker').write_text('original')
        with self.assertRaises(FileExistsError):
            self.run_producer()
        self.assertEqual((self.output / 'marker').read_text(), 'original')
