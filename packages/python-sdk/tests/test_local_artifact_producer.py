"""Receipt/copy assembly tests, never actual Wasm, DuckDB or wheel evidence."""
from __future__ import annotations

from contextlib import ExitStack
from image_fixture import IMAGE, ORIGINAL, RUNTIME_HASH, descriptor
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import shlex
import struct
import subprocess
import tempfile
import unittest
import zipfile
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
        paths = ['toolchain.json', 'moon.mod', 'vendor/duckdb/1.4.3/manifest.json',
                 'scripts/generate-local-wasm-abi.py',
                 'packages/python-sdk/src/actql_sdk/_local_wasm_abi.py',
                 'src/physical_resources/imported_child_ledger_wasm.mbt',
                 'src/physical_resources/platform_vm_capacity_wasm.mbt',
                 'src/client_host_wasm/moon.pkg',
                 'packages/python-product/pyproject.toml',
                 'packages/python-sdk/pyproject.toml', 'packages/python-local-runtime/pyproject.toml',
                 'packages/python-local-runtime/setup.py',
                 'packages/python-local-runtime/src/actql_local_runtime/__init__.py']
        paths += [str(path.relative_to(ROOT)) for path in producer.recipe.notice_originals().values()]
        paths += [str(path.relative_to(ROOT)) for path in (ROOT / 'src/client_host_wasm').glob('*.mbt')]
        for filename in paths:
            target = self.source / filename
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / filename, target)
        selected = self.source / 'packages/python-local-runtime/selected-image-recipe.json'
        selected.write_bytes(ORIGINAL)
        self.git('init', '-q')
        self.commit()
        self.module = self.root / 'original.wasm'
        self.library = self.root / 'original.dylib'
        # Synthetic format headers and declared receipt records exercise only
        # finite producer assembly. Neither component has been executed.
        self.module.write_bytes(b'\0asm\x01\0\0\0fixture-not-an-executed-module')
        self.core_input = self.root / 'original.core'
        self.core_input.write_bytes(b'Independent non-executable link input fixture')
        self.link_response = self.root / 'original.wasm.rsp'
        self.link_response.write_text(shlex.join(['link-core', str(self.core_input),
            '-o', str(self.module), '-target', 'wasm', '-memory-limits-max', '256']))
        self.moon_home = self.root / 'fixture-toolchain'
        (self.moon_home / 'bin').mkdir(parents=True)
        pin = json.loads((self.source / 'toolchain.json').read_bytes())
        (self.moon_home / 'installed.json').write_text(json.dumps({'pin': pin, 'platform': 'darwin-arm64'}))
        # These executable version-response fixtures are not compilers. Their
        # file/version fences exercise only the maintainer input verifier.
        for name, value in [('moon', 'moon ' + pin['moon']), ('moonc', pin['moonc'])]:
            path = self.moon_home / 'bin' / name
            path.write_text('#!/bin/sh\nprintf \'%s\\n\' ' + shlex.quote(value) + '\n')
            path.chmod(0o755)
        command = struct.pack('<6I', 0x32, 24, 1, 11 << 16, 11 << 16, 0)
        self.library.write_bytes(struct.pack('<8I', 0xfeedfacf, 0x0100000c, 0, 6, 1, len(command), 0, 0) + command)
        digest = hash_bytes(self.module.read_bytes())
        self.core = {'source_sha': self.head, 'module': str(self.module), 'module_sha256': digest,
                     'scope': 'physical_buffer_bridge_workspace_only',
                     'moonc': json.loads((self.source / 'toolchain.json').read_bytes())['moonc'],
                     'python': 'synthetic fixture', 'positive_native_result_acceptance': False,
                     'public_local_acceptance': False,
                     'contract': {'success': True, 'module_sha256': digest},
                     **{name: {'success': True, 'module_sha256': digest, 'cases': ['synthetic fixture']}
                        for name in ('result', 'physical', 'workspace')}}
        self.duckdb = {'source_sha': self.head, 'library': str(self.library),
                       'library_sha256': hash_bytes(self.library.read_bytes()), 'library_version': 'v1.4.3',
                       'python': 'synthetic fixture', 'platform': 'macOS-synthetic-fixture', 'machine': 'arm64',
                       'tests': 20, 'success': True, 'module_source': None, 'workspace_selection': False,
                       'public_local_acceptance': False, 'wheel_acceptance': False}
        self.image_path = self.root / 'original.cwasm'
        self.image_path.write_bytes(IMAGE)
        self.image = {'source_sha': self.head, 'module_sha256': digest, 'core_abi': 74,
            'wasmtime_version': '38.0.0', 'runtime_library_sha256': RUNTIME_HASH,
            'provider_library_sha256': json.loads(ORIGINAL)['provider_library_sha256'],
            'engine_sha256': descriptor(self.head, '0.0.0.dev0', digest)['engine_sha256'],
            'image': str(self.image_path), 'image_sha256': hash_bytes(IMAGE),
            'compiled': True, 'runtime_executed': False, 'public_local_acceptance': False}
        # Synthetic metadata below tests only the closed receipt law. No phase
        # or image has executed; these objects are never runtime evidence.
        fixture_cohort = {'execution_kind': 'selected_precompiled_image',
            'module_sha256': digest, 'image_sha256': hash_bytes(IMAGE),
            'engine_sha256': descriptor(self.head, '0.0.0.dev0', digest)['engine_sha256'],
            'runtime_library_sha256': RUNTIME_HASH,
            'provider_library_sha256': json.loads(ORIGINAL)['provider_library_sha256']}
        self.core['contract']['cases'] = ['synthetic non-executable format fixture']
        for name in ('contract', 'result', 'physical', 'workspace'):
            self.core[name]['cohort'] = dict(fixture_cohort)
        self.image_file = self.root / 'image.json'
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
        self.module_original = producer.record_original_module(self.source, self.head, self.head,
            self.module, self.link_response, self.moon_home)
        self.core['module_original'] = self.module_original
        self.module_file = self.root / 'module-original.json'
        self.module_file.write_text(json.dumps(self.module_original))
        self.core_file.write_text(json.dumps(self.core))
        self.duckdb_file.write_text(json.dumps(self.duckdb))
        self.image_file.write_text(json.dumps(self.image))

    def run_producer(self):
        return producer.produce(self.core_file, self.duckdb_file, self.image_file, self.output)

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
        self.assertEqual((self.output / 'client_host_wasm.cwasm').read_bytes(), IMAGE)
        self.assertEqual((self.output / 'engine-recipe.json').read_bytes(), ORIGINAL)
        self.assertEqual(result['image_receipt_sha256'], hash_bytes(self.image_file.read_bytes()))
        self.assertFalse(result['runtime_executed'])
        self.assertFalse(result['wheel_built'])
        self.assertFalse(result['public_local_accepted'])
        stage = self.root / 'stage'
        def private_stage(components, archive, native, target):
            self.assertEqual(archive, self.root / 'fixed-binding-source')
            self.assertEqual(native, self.root / 'fixed-native-libraries')
            (target / 'WASMTIME-LICENSE').write_bytes(b'independent private notice fixture')
            return {'native_loaded': False}
        # Native staging and Mach-O refusals have independent tests. This
        # synthetic receipt case retains its original component-copy scope.
        with patch.object(producer.recipe, 'stage_private_runtime', side_effect=private_stage):
            prepared = producer.recipe.prepare(self.output, stage,
                bindings_source=self.root / 'fixed-binding-source',
                native_libraries=self.root / 'fixed-native-libraries')
        self.assertEqual(prepared['source_sha'], self.head)
        self.assertFalse(prepared['runtime_executed'])

    def test_foreign_or_incomplete_image_provenance_is_not_copied(self):
        for key, value in [('source_sha', '0' * 40), ('module_sha256', '0' * 64),
                ('runtime_library_sha256', '0' * 64), ('provider_library_sha256', '0' * 64),
                ('engine_sha256', '0' * 64),
                ('compiled', 1), ('runtime_executed', True)]:
            original = self.image.copy(); self.image[key] = value; self.write_receipts()
            with self.assertRaisesRegex(ValueError, 'selected original recipe'): self.run_producer()
            self.assertFalse(self.output.exists()); self.image = original

    def test_synthetic_wheel_component_inventory_includes_image_and_recipe(self):
        self.run_producer()
        spec = importlib.util.spec_from_file_location('image_wheel_inspector',
            ROOT / 'scripts/build-python-product-wheels.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        wheel = self.root / 'synthetic.whl'
        stage = self.root / 'private-stage'
        private = stage / 'src/actql_local_runtime/_wasmtime'
        private.mkdir(parents=True)
        (private / '__init__.py').write_bytes(b'# Independent non-executable binding fixture\n')
        (private.parent / 'WASMTIME-LICENSE').write_bytes(b'independent private notice fixture')
        names = ('artifact.json', 'engine-recipe.json', 'client_host_wasm.cwasm',
                 'client_host_wasm.wasm', 'libduckdb.dylib', 'LICENSE',
                 'DUCKDB-LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE')
        for missing, changed in ((None, None), ('client_host_wasm.cwasm', None),
                                 (None, 'engine-recipe.json'), (None, 'client_host_wasm.cwasm')):
            with self.subTest(missing=missing, changed=changed):
                with zipfile.ZipFile(wheel, 'w') as archive:
                    for name in names:
                        if name == missing: continue
                        value = (self.output / name).read_bytes()
                        if name == changed: value = b'x' * len(value)
                        archive.writestr('actql_local_runtime/' + name, value)
                    for path in (private / '__init__.py', private.parent / 'WASMTIME-LICENSE'):
                        archive.writestr('actql_local_runtime/' + path.relative_to(private.parent).as_posix(), path.read_bytes())
                if missing or changed:
                    with self.assertRaises((ValueError, KeyError)):
                        module.runtime_wheel_components(wheel, self.output, stage)
                else:
                    module.runtime_wheel_components(wheel, self.output, stage)

    def test_synthetic_sdk_wheel_binding_is_exact_and_contains_no_runtime(self):
        spec = importlib.util.spec_from_file_location('sdk_image_binding_inspector',
            ROOT / 'scripts/build-python-product-wheels.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        original = b'{"source_sha":"independent fixture only"}'
        wheel = self.root / 'synthetic-sdk.whl'
        for value in (original, original + b' ', b'foreign'):
            with zipfile.ZipFile(wheel, 'w') as archive:
                archive.writestr('actql_sdk/_local_release_binding.json', value)
            if value == original: module.sdk_runtime_binding(wheel, original)
            else:
                with self.assertRaisesRegex(ValueError, 'binding mismatch'):
                    module.sdk_runtime_binding(wheel, original)

    def test_light_sdk_wheel_refuses_a_precompiled_native_image(self):
        spec = importlib.util.spec_from_file_location('sdk_binary_image_inspector',
            ROOT / 'scripts/build-python-product-wheels.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        wheel = self.root / 'actql_sdk-0.0.0.dev0-py3-none-any.whl'
        for binary in (False, True):
            with zipfile.ZipFile(wheel, 'w') as archive:
                archive.writestr('sdk.dist-info/METADATA',
                    'Name: actql-sdk\nVersion: 0.0.0.dev0\nRequires-Dist: httpx==0.28.1\nRequires-Dist: rfc8785==0.1.4\n')
                archive.writestr('sdk.dist-info/WHEEL', 'Tag: py3-none-any\n')
                if binary: archive.writestr('actql_sdk/foreign.cwasm', IMAGE)
            if binary:
                with self.assertRaisesRegex(ValueError, 'contains a native engine'):
                    module.wheel_metadata(wheel, 'actql-sdk', '0.0.0.dev0')
            else:
                module.wheel_metadata(wheel, 'actql-sdk', '0.0.0.dev0')

    def test_unadopted_missing_source_recipe_refuses_without_a_default(self):
        self.git('rm', 'packages/python-local-runtime/selected-image-recipe.json')
        self.commit()
        for receipt in (self.core, self.duckdb, self.image): receipt['source_sha'] = self.head
        self.write_receipts()
        with self.assertRaisesRegex(ValueError, 'source-original image recipe is unavailable'):
            self.run_producer()
        self.assertFalse(self.output.exists())

    def test_modified_selected_source_recipe_is_not_an_installer_original(self):
        selected = self.source / 'packages/python-local-runtime/selected-image-recipe.json'
        selected.write_bytes(ORIGINAL + b' ')
        with self.assertRaisesRegex(ValueError, 'committed clean'): self.run_producer()
        self.assertFalse(self.output.exists())

    def test_foreign_image_header_cannot_be_relabelled_with_a_new_digest(self):
        wrong = IMAGE[:18] + b'\x3e\0' + IMAGE[20:]
        self.image_path.write_bytes(wrong)
        self.image['image_sha256'] = hash_bytes(wrong); self.write_receipts()
        with self.assertRaisesRegex(ValueError, 'binary target'): self.run_producer()
        self.assertFalse(self.output.exists())

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
