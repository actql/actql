"""Source-stage mutations, not runtime, allocator, or funding acceptance."""
import hashlib
import importlib.util
import json
from pathlib import Path
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

    def prepare(self):
        (self.provider / 'scoped-read-source.json').write_text(json.dumps(self.manifest))
        return PREPARE.prepare(self.moonbit, self.destination, provider=self.provider)

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
