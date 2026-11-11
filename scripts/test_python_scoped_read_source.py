"""Source-stage mutations, not runtime, allocator, or funding acceptance."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


CANDIDATE = Path(__file__).resolve().parents[1] / 'packages/python-local-runtime/native/pre-root'
SPEC = importlib.util.spec_from_file_location('prepare_scoped_read', CANDIDATE / 'prepare_scoped_read.py')
assert SPEC is not None and SPEC.loader is not None
PREPARE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREPARE)


def entry(data):
    return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


class ScopedReadCommandTests(unittest.TestCase):
    def test_explicit_x64_cli_target_reaches_the_existing_verified_preparer(self):
        # This checks routing only. Source pins and actual copied output remain
        # covered by the existing preparation tests; no compilation is implied.
        for target in ('aarch64-apple-darwin', 'aarch64-unknown-linux-gnu',
                       'x86_64-unknown-linux-gnu'):
            with self.subTest(target=target), \
                    patch.object(PREPARE, 'prepare', return_value={'target': target}) as selected, \
                    patch('builtins.print') as output:
                PREPARE.main(['--moonbit', '/pinned/moon', '--destination', '/fresh/stage',
                              '--target', target])
                selected.assert_called_once_with(Path('/pinned/moon'), Path('/fresh/stage'),
                                                 target=target)
                output.assert_called_once_with(json.dumps({'target': target}))


class CurrentProviderClosureTests(unittest.TestCase):
    def test_default_darwin_binaries_are_not_replaced_by_local_linux_inputs(self):
        manifest = json.loads((CANDIDATE / 'scoped-read-source.json').read_bytes())
        self.assertEqual(manifest['target'], 'aarch64-apple-darwin')
        # Independent pins for the existing selected compiler, not this host's
        # toolchain. Linux overrides must remain confined to source_targets.
        expected = {
            'lib/libmoonbitrun.o': {'bytes': 188920, 'sha256':
                'd9db2413e755c00ab374901211a03a9551222fe779022bc3648235747ed2bd96'},
            'lib/libbacktrace.a': {'bytes': 281872, 'sha256':
                'a0ed98ead4be023f2840063c0e1c016fe581895c936759e68fd6e0e23dfaf9b7'},
        }
        selected = PREPARE._select_target(manifest, 'aarch64-apple-darwin')
        for path, pin in expected.items():
            with self.subTest(path=path):
                item = next(item for item in selected['inputs']
                            if item['root'] == 'moonbit' and item['path'] == path)
                self.assertEqual({key: item[key] for key in ('bytes', 'sha256')}, pin)
                self.assertEqual(selected['outputs'][item['output']], pin)
        for target in ('aarch64-unknown-linux-gnu', 'x86_64-unknown-linux-gnu'):
            selected = PREPARE._select_target(manifest, target)
            for path, pin in manifest['source_targets'][target]['binary_inputs'].items():
                with self.subTest(target=target, path=path):
                    item = next(item for item in selected['inputs']
                                if item['root'] == 'moonbit' and item['path'] == path)
                    self.assertEqual({key: item[key] for key in ('bytes', 'sha256')}, pin)
                    self.assertEqual(selected['outputs'][item['output']], pin)
                    self.assertNotEqual(pin, expected[path])

    def test_existing_linux_process_recipe_keeps_current_source_identities(self):
        root = CANDIDATE.parents[3]
        manifest = json.loads((CANDIDATE / 'linux-x64-process-source.json').read_bytes())
        for item in manifest['inputs']:
            with self.subTest(path=item['path']):
                self.assertEqual(entry((root / item['path']).read_bytes()),
                                 {key: item[key] for key in ('bytes', 'sha256')})

    def test_real_provider_patch_and_derived_outputs_match(self):
        manifest = json.loads((CANDIDATE / 'scoped-read-source.json').read_bytes())
        source_patch = PREPARE._read(CANDIDATE, manifest['patch']['path'], manifest['patch'])
        with tempfile.TemporaryDirectory() as temporary:
            stage = Path(temporary)
            for item in manifest['inputs']:
                if item['root'] == 'provider':
                    (stage / item['output']).write_bytes(
                        PREPARE._read(CANDIDATE, item['path'], item))
            # Exercise the real provider hunks, including the two newly added
            # Read files, without needing a compiler or a MoonBit installation.
            result = subprocess.run(
                ['git', 'apply', '--no-index', '--exclude=moonbit_runtime.h', '-'],
                input=source_patch, cwd=stage, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            for path in stage.iterdir():
                with self.subTest(path=path.name):
                    self.assertEqual(entry(path.read_bytes()), manifest['outputs'][path.name])

    def test_real_provider_inputs_and_unpatched_borrow_outputs_are_pinned(self):
        manifest = json.loads((CANDIDATE / 'scoped-read-source.json').read_bytes())
        for item in manifest['inputs']:
            if item['root'] != 'provider':
                continue
            with self.subTest(path=item['path']):
                data = PREPARE._read(CANDIDATE, item['path'], item)
                if item['path'] in {'owned_domain_borrow.h', 'owned_domain_borrow.inc'}:
                    # These original provider files are copied without patching.
                    self.assertEqual(manifest['outputs'][item['output']], entry(data))


class ScopedReadSourceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.provider = self.root / 'provider'
        self.moonbit = self.root / 'moonbit'
        self.destination = self.root / 'stage'
        self.provider.mkdir()
        (self.moonbit / 'include').mkdir(parents=True)
        (self.provider / 'owned.c').write_bytes(b'abc\n')
        (self.moonbit / 'include/runtime.h').write_bytes(b'abc\n')
        self.patch = b'--- a/runtime.h\n+++ b/runtime.h\n@@ -1 +1 @@\n-abc\n+abcd\n'
        (self.provider / 'read.patch').write_bytes(self.patch)
        self.manifest = {
            'status': 'review-source-only', 'normal_profile': None,
            'installed_supplier': False, 'target': 'aarch64-apple-darwin',
            'deployment_target': '11.0', 'required_defines': ['DERIVED_READ'],
            'patch': {'path': 'read.patch', **entry(self.patch)},
            'inputs': [
                {'root': 'provider', 'path': 'owned.c', 'output': 'owned.c', **entry(b'abc\n')},
                {'root': 'moonbit', 'path': 'include/runtime.h', 'output': 'runtime.h', **entry(b'abc\n')},
            ],
            'outputs': {'owned.c': entry(b'abc\n'), 'runtime.h': entry(b'abcd\n')},
        }

    def prepare(self, target=None):
        (self.provider / 'scoped-read-source.json').write_text(json.dumps(self.manifest))
        return PREPARE.prepare(self.moonbit, self.destination, provider=self.provider, target=target)

    def add_linux_binaries(self):
        (self.moonbit / 'lib').mkdir()
        binaries = {'lib/libmoonbitrun.o': b'linux-object',
                    'lib/libbacktrace.a': b'linux-archive'}
        for path, data in binaries.items():
            (self.moonbit / path).write_bytes(data)
            output = Path(path).name
            self.manifest['inputs'].append({'root': 'moonbit', 'path': path,
                                           'output': output, **entry(b'darwin-input')})
            self.manifest['outputs'][output] = entry(b'darwin-input')
        self.manifest['source_targets'] = {'aarch64-unknown-linux-gnu': {
            'deployment_target': None,
            'required_source_parameters': ['ACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS'],
            'required_defines': ['DERIVED_READ', '_GNU_SOURCE',
                                 'ACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN'],
            'binary_inputs': {path: entry(data) for path, data in binaries.items()},
        }}

    def test_linux_selection_requires_its_exact_binaries_and_explicit_defines(self):
        self.add_linux_binaries()
        result = self.prepare('aarch64-unknown-linux-gnu')
        self.assertEqual(result['target'], 'aarch64-unknown-linux-gnu')
        self.assertIsNone(result['deployment_target'])
        self.assertEqual(result['required_source_parameters'], ['ACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS'])
        self.assertIn('ACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN', result['required_defines'])
        self.assertEqual((self.destination / 'libmoonbitrun.o').read_bytes(), b'linux-object')
        self.assertEqual(result['compiled'], 0)
        self.assertIs(result['installed_supplier'], False)

    def test_x64_bundle_variant_keeps_its_explicit_profile_and_exact_binary_inputs(self):
        self.add_linux_binaries()
        import copy
        original = self.manifest['source_targets']['aarch64-unknown-linux-gnu']
        variant = copy.deepcopy(original)
        variant['required_defines'].append('ACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY')
        self.manifest['source_targets']['x86_64-unknown-linux-gnu'] = variant
        result = self.prepare('x86_64-unknown-linux-gnu')
        self.assertEqual(result['target'], 'x86_64-unknown-linux-gnu')
        self.assertIn('ACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY', result['required_defines'])
        self.assertNotIn('ACTQL_NATIVE_OWNED_LINUX_X64_PROCESS_DOMAIN', result['required_defines'])
        self.assertEqual(result['compiled'], 0)
        self.assertIs(result['installed_supplier'], False)

    def test_x64_bundle_cannot_substitute_the_default_process_profile(self):
        self.add_linux_binaries()
        import copy
        variant = copy.deepcopy(self.manifest['source_targets']['aarch64-unknown-linux-gnu'])
        variant['required_defines'].append('ACTQL_NATIVE_OWNED_LINUX_X64_PROCESS_DOMAIN')
        self.manifest['source_targets']['x86_64-unknown-linux-gnu'] = variant
        with self.assertRaisesRegex(ValueError, 'Invalid selected source target recipe'):
            self.prepare('x86_64-unknown-linux-gnu')
        self.assertFalse(self.destination.exists())

    def test_linux_objects_do_not_satisfy_default_darwin_selection(self):
        self.add_linux_binaries()
        with self.assertRaisesRegex(ValueError, 'mismatch'):
            self.prepare()
        self.assertFalse(self.destination.exists())

    def test_linux_wrong_binary_cannot_fall_back_to_darwin(self):
        self.add_linux_binaries()
        (self.moonbit / 'lib/libmoonbitrun.o').write_bytes(b'darwin-input')
        with self.assertRaisesRegex(ValueError, 'mismatch'):
            self.prepare('aarch64-unknown-linux-gnu')
        self.assertFalse(self.destination.exists())

    def test_unknown_target_and_incomplete_linux_recipe_refuse(self):
        with self.assertRaisesRegex(ValueError, 'Unknown source closure target'):
            self.prepare('unknown')
        self.add_linux_binaries()
        del self.manifest['source_targets']['aarch64-unknown-linux-gnu']['binary_inputs']['lib/libbacktrace.a']
        with self.assertRaisesRegex(ValueError, 'Invalid selected source target recipe'):
            self.prepare('aarch64-unknown-linux-gnu')
        self.assertFalse(self.destination.exists())

    def test_exact_patch_copy_preserves_originals_and_is_not_an_installed_supplier(self):
        result = self.prepare()
        self.assertEqual((self.destination / 'runtime.h').read_bytes(), b'abcd\n')
        self.assertEqual((self.moonbit / 'include/runtime.h').read_bytes(), b'abc\n')
        self.assertEqual((self.provider / 'owned.c').read_bytes(), b'abc\n')
        self.assertIs(result['installed_supplier'], False)
        self.assertIsNone(result['normal_profile'])
        self.assertEqual(result['compiled'], 0)

    def test_modified_original_input_is_refused_before_publication(self):
        (self.provider / 'owned.c').write_bytes(b'abd\n')
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.prepare()
        self.assertFalse(self.destination.exists())

    def test_wrong_runtime_header_is_refused_without_system_fallback(self):
        (self.moonbit / 'include/runtime.h').write_bytes(b'xyz\n')
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.prepare()
        self.assertFalse(self.destination.exists())

    def test_changed_patch_and_independently_wrong_output_are_refused(self):
        changed = self.patch.replace(b'+abcd', b'+abce')
        (self.provider / 'read.patch').write_bytes(changed)
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.prepare()
        # Even a newly pinned patch cannot pass the independent derived digest.
        self.manifest['patch'].update(entry(changed))
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.prepare()
        self.assertFalse(self.destination.exists())

    def test_symlink_input_and_symlink_output_are_refused(self):
        source = self.provider / 'owned.c'
        source.unlink()
        source.symlink_to(self.moonbit / 'include/runtime.h')
        with self.assertRaisesRegex(ValueError, 'Symlink'):
            self.prepare()
        source.unlink()
        source.write_bytes(b'abc\n')
        self.destination.symlink_to(self.root / 'missing')
        with self.assertRaisesRegex(ValueError, 'already exists'):
            self.prepare()

    def test_existing_output_and_selected_input_tree_are_never_overwritten(self):
        self.destination.mkdir()
        (self.destination / 'original').write_bytes(b'keep')
        with self.assertRaisesRegex(ValueError, 'already exists'):
            self.prepare()
        self.assertEqual((self.destination / 'original').read_bytes(), b'keep')
        self.destination = self.moonbit / 'derived'
        with self.assertRaisesRegex(ValueError, 'cannot overwrite selected'):
            self.prepare()

    def test_duplicate_output_and_path_escape_are_refused(self):
        self.manifest['inputs'][1]['output'] = 'owned.c'
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            self.prepare()
        self.manifest['inputs'][1]['output'] = '../escape'
        with self.assertRaisesRegex(ValueError, 'Invalid source closure path'):
            self.prepare()
        self.assertFalse((self.root / 'escape').exists())

    def test_nonregular_or_oversized_source_is_refused(self):
        source = self.provider / 'owned.c'
        source.unlink()
        source.mkdir()
        with self.assertRaisesRegex(ValueError, 'size mismatch'):
            self.prepare()
        source.rmdir()
        source.write_bytes(b'abc\n')
        self.manifest['inputs'][0]['bytes'] = 2 * 1024 * 1024 + 1
        with self.assertRaisesRegex(ValueError, 'size mismatch'):
            self.prepare()

    def test_copy_changed_before_final_verification_has_no_completion_metadata(self):
        original_read = PREPARE._read

        def swap(root, name, expected):
            if root == self.destination and name == 'runtime.h':
                (root / name).write_bytes(b'abce\n')
            return original_read(root, name, expected)

        with patch.object(PREPARE, '_read', swap):
            with self.assertRaisesRegex(ValueError, 'digest mismatch'):
                self.prepare()
        self.assertFalse((self.destination / 'scoped-read-stage.json').exists())
        self.assertEqual((self.moonbit / 'include/runtime.h').read_bytes(), b'abc\n')


if __name__ == '__main__':
    unittest.main()
