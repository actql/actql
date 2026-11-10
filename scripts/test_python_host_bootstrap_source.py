"""Source-closure negatives only; no Native/compiler/installed acceptance."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from python_host_bootstrap_source import INPUTS, MANIFEST, verify_source


class SourceClosureTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.head = '0' * 40
        self.status = b''
        self.calls = []
        # Fixed SHA256("abc"), independently known. These are source-file
        # fixtures, not Native outputs or Resource accounting expectations.
        self.manifest = {
            'status': 'source-preparation-only', 'target': 'aarch64-apple-darwin',
            'inputs': [{'path': name, 'bytes': 3,
                        'sha256': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'}
                       for name in INPUTS],
        }
        for name in INPUTS:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'abc')
        self.write_manifest()

    def write_manifest(self):
        self.raw = json.dumps(self.manifest).encode()
        (self.root / MANIFEST).write_bytes(self.raw)

    def git_blob(self, args, *, cwd):
        self.assertEqual(cwd, self.root)
        self.calls.append(args)
        if args == ['git', 'rev-parse', 'HEAD']:
            return self.head.encode() + b'\n'
        if args == ['git', 'status', '--porcelain', '--untracked-files=normal']:
            return self.status
        self.assertEqual(args[:2], ['git', 'show'])
        return self.raw if args[2].endswith(':' + MANIFEST) else b'abc'

    def check(self):
        with patch('python_host_bootstrap_source.subprocess.check_output', self.git_blob):
            return verify_source(self.root, '0' * 40)

    def test_required_allocator_include_cannot_be_omitted(self):
        required = 'packages/python-local-runtime/native/pre-root/owned_rust_heap.inc'
        self.assertIn(required, INPUTS)
        self.manifest['inputs'] = [entry for entry in self.manifest['inputs']
                                   if entry['path'] != required]
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'source manifest'):
            self.check()

    def test_original_process_header_cannot_be_omitted(self):
        required = 'src/platform_native/host_bootstrap/process_region.h'
        self.assertIn(required, INPUTS)
        self.manifest['inputs'] = [entry for entry in self.manifest['inputs']
                                   if entry['path'] != required]
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'source manifest'):
            self.check()

    def test_source_closure_does_not_claim_physical_or_installed_success(self):
        result = self.check()
        self.assertEqual(result['verified_inputs'], 41)
        self.assertEqual(result['native_execution'], 0)
        self.assertIs(result['installed_capability'], False)

    def test_root_control_sources_cannot_be_omitted(self):
        for required in (
            'src/platform_native/host_bootstrap/root_control.inc',
            'src/platform_native/host_bootstrap/root_control_native.mbt',
            'src/platform_native/host_bootstrap/root_control_physical_scoped_wbtest.mbt',
            'src/platform_native/host_bootstrap/root_control_unavailable_wbtest.mbt',
            'packages/python-local-runtime/native/pre-root/fixtures/scoped_read.c',
            'scripts/test_native_prepared_controls.py',
            'src/platform_native/host_bootstrap/working_origin.inc',
            'src/platform_native/host_bootstrap/working_origin_fixture.c',
            'scripts/test_native_working_origin.py',

        ):
            with self.subTest(path=required):
                self.assertIn(required, INPUTS)
                original = self.manifest['inputs']
                self.manifest['inputs'] = [entry for entry in original
                                           if entry['path'] != required]
                self.write_manifest()
                with self.assertRaisesRegex(ValueError, 'source manifest'):
                    self.check()
                self.manifest['inputs'] = original
                self.write_manifest()

    def test_request_original_carriers_cannot_be_omitted(self):
        for required in (
            'src/platform_native/host_bootstrap/backed_live_child_native.mbt',
            'src/platform_native/host_bootstrap/backed_request_preparation_native.mbt',
            'src/platform_native/host_bootstrap/request_preparation_physical_scoped_wbtest.mbt',
        ):
            with self.subTest(path=required):
                self.assertIn(required, INPUTS)
                original = self.manifest['inputs']
                self.manifest['inputs'] = [entry for entry in original
                                           if entry['path'] != required]
                self.write_manifest()
                with self.assertRaisesRegex(ValueError, 'source manifest'):
                    self.check()
                self.manifest['inputs'] = original
                self.write_manifest()

    def test_extent_work_observer_cannot_be_omitted(self):
        required = 'src/platform_native/host_bootstrap/extent_work_native.mbt'
        self.assertIn(required, INPUTS)
        self.manifest['inputs'] = [entry for entry in self.manifest['inputs']
                                   if entry['path'] != required]
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'source manifest'):
            self.check()

    def test_domain_inventory_observer_cannot_be_omitted(self):
        required = 'src/platform_native/host_bootstrap/domain_inventory_native.mbt'
        self.assertIn(required, INPUTS)
        self.manifest['inputs'] = [entry for entry in self.manifest['inputs']
                                   if entry['path'] != required]
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'source manifest'):
            self.check()

    def test_original_cleanup_observer_cannot_be_omitted(self):
        required = 'src/platform_native/host_bootstrap/read_cleanup_observation_native.mbt'
        self.assertIn(required, INPUTS)
        self.manifest['inputs'] = [entry for entry in self.manifest['inputs']
                                   if entry['path'] != required]
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'source manifest'):
            self.check()

    def test_growth_source_and_consuming_fixture_are_required(self):
        for required in (
                'src/platform_native/host_bootstrap/backing_growth_native.mbt',
                'src/platform_native/host_bootstrap/backing_growth_wbtest.mbt',
                'packages/python-local-runtime/native/pre-root/owned_domain_growth.inc'):
            with self.subTest(required=required):
                self.assertIn(required, INPUTS)
                original = self.manifest['inputs']
                self.manifest['inputs'] = [entry for entry in original
                                           if entry['path'] != required]
                self.write_manifest()
                with self.assertRaisesRegex(ValueError, 'source manifest'):
                    self.check()
                self.manifest['inputs'] = original
                self.write_manifest()

    def test_modified_source_blob_is_rejected(self):
        (self.root / INPUTS[-1]).write_bytes(b'abd')
        with self.assertRaisesRegex(ValueError, 'source mismatch'):
            self.check()

    def test_unknown_field_and_foreign_target_are_rejected(self):
        self.manifest['allow'] = True
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'source manifest'):
            self.check()
        del self.manifest['allow']
        self.manifest['target'] = 'x86_64-unknown-linux-gnu'
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'source manifest'):
            self.check()

    def test_foreign_path_and_symlink_are_rejected(self):
        self.manifest['inputs'][0]['path'] = '../foreign.c'
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'bootstrap input'):
            self.check()
        self.manifest['inputs'][0]['path'] = INPUTS[0]
        self.write_manifest()
        path = self.root / INPUTS[0]
        path.unlink()
        target = self.root / 'foreign.c'
        target.write_bytes(b'abc')
        path.symlink_to(target)
        with self.assertRaisesRegex(ValueError, 'Symlink'):
            self.check()

    def test_duplicate_and_changed_manifest_are_rejected(self):
        self.raw = self.raw.replace(b'{', b'{"status":"forged",', 1)
        (self.root / MANIFEST).write_bytes(self.raw)
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            self.check()
        self.write_manifest()
        (self.root / MANIFEST).write_bytes(self.raw + b' ')
        with self.assertRaisesRegex(ValueError, 'manifest mismatch'):
            self.check()

    def test_same_selected_inputs_under_a_foreign_head_are_rejected_before_read(self):
        self.head = '1' * 40
        with self.assertRaisesRegex(ValueError, 'exact clean source'):
            self.check()
        self.assertFalse(any(args[1] == 'show' for args in self.calls))

    def test_imported_owner_change_before_and_during_inspection_is_rejected(self):
        self.status = b' M src/physical_resources/delegation.mbt\n'
        with self.assertRaisesRegex(ValueError, 'exact clean source'):
            self.check()
        self.assertFalse(any(args[1] == 'show' for args in self.calls))
        self.status = b''
        original_blob = self.git_blob

        def changed_after_read(args, *, cwd):
            data = original_blob(args, cwd=cwd)
            if args[1] == 'show':
                self.status = b' M src/physical_resources/delegation.mbt\n'
            return data

        with patch('python_host_bootstrap_source.subprocess.check_output', changed_after_read):
            with self.assertRaisesRegex(ValueError, 'exact clean source'):
                verify_source(self.root, '0' * 40)


if __name__ == '__main__':
    unittest.main()
