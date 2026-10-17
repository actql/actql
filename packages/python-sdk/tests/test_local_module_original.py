"""Independent module input/copy refusals; no actual compiler, image or VM."""
from copy import deepcopy
import json
from pathlib import Path
import unittest

import test_local_artifact_producer as fixture


class ModuleOriginalTests(unittest.TestCase):
    def setUp(self):
        self.case = fixture.LocalArtifactProducerTests()
        self.case.setUp(); self.addCleanup(self.case.doCleanups)
        self.producer = fixture.producer

    def record(self, compiled_source=None):
        c = self.case
        return self.producer.record_original_module(c.source, c.head,
            c.head if compiled_source is None else compiled_source,
            c.module, c.link_response, c.moon_home)

    def verify(self, original=None):
        return self.producer.verify_original_module(self.case.source,
            self.case.module_original if original is None else original, self.case.head)

    def test_closed_compile_only_material_has_no_physical_success_or_grant(self):
        c = self.case
        self.assertEqual(self.verify(), c.core['module_sha256'])
        self.assertEqual(c.module_original['scope'], 'compile_only_module_inputs')
        self.assertEqual(c.module_original['source_sha'], c.head)
        self.assertEqual(c.module_original['compiled_source_sha'], c.head)
        self.assertEqual(len(c.module_original['link_inputs']), 1)
        self.assertFalse({'result', 'physical', 'workspace', 'success', 'normal_funding'}
                         & c.module_original.keys())

    def test_final_producer_rejects_compile_only_receipt_even_with_valid_image_inputs(self):
        c = self.case
        c.core_file.write_text(json.dumps(c.module_original))
        with self.assertRaisesRegex(ValueError, 'original physical-boundary'):
            c.run_producer()
        self.assertFalse(c.output.exists())

    def test_every_physical_case_family_remains_mandatory(self):
        c = self.case
        for name in ('result', 'physical', 'workspace'):
            for bad in (None, {'success': False}, {'success': True, 'module_sha256': c.core['module_sha256'], 'cases': []}):
                value = deepcopy(c.core)
                if bad is None:
                    del value[name]
                else:
                    value[name] = bad
                c.core_file.write_text(json.dumps(value))
                with self.subTest(name=name, bad=bad), self.assertRaises(ValueError):
                    c.run_producer()
                self.assertFalse(c.output.exists())

    def test_relabelling_compile_scope_with_physical_fields_is_not_admission(self):
        c = self.case
        value = deepcopy(c.module_original)
        value['scope'] = 'physical_buffer_bridge_workspace_only'
        value.update({name: c.core[name] for name in ('result', 'physical', 'workspace')})
        c.core_file.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, 'original physical-boundary'):
            c.run_producer()

    def test_source_only_documentation_child_preserves_actual_compiled_source(self):
        c = self.case
        compiled = c.head
        (c.source / 'README.md').write_text('Independent source-only fixture change\n')
        c.commit()
        original = self.record(compiled)
        self.assertEqual(original['source_sha'], c.head)
        self.assertEqual(original['compiled_source_sha'], compiled)
        self.assertNotEqual(c.head, compiled)
        self.assertEqual(self.verify(original), c.core['module_sha256'])
        with self.assertRaisesRegex(ValueError, 'exact producer source'):
            self.producer.verify_original_core(c.source, c.core, c.head)

    def test_added_source_member_refuses_old_compiled_source(self):
        c = self.case
        compiled = c.head
        (c.source / 'src/new_member.mbt').write_text('let original_member = 1\n')
        c.commit()
        with self.assertRaisesRegex(ValueError, 'source member|source inputs differ'):
            self.record(compiled)

    def test_empty_source_member_is_counted_without_becoming_an_empty_artifact(self):
        c = self.case
        compiled = c.head
        (c.source / 'src/empty_member.mbt').write_bytes(b'')
        c.commit()
        original = self.record()
        self.assertNotEqual(original['source_inputs_sha256'], c.module_original['source_inputs_sha256'])
        with self.assertRaisesRegex(ValueError, 'source inputs differ'):
            self.record(compiled)
        c.module.write_bytes(b'')
        with self.assertRaises(fixture.LocalInstallationError):
            self.record()

    def test_changed_source_and_dirty_working_copy_cannot_reuse_original(self):
        c = self.case
        (c.source / 'src/client_host_wasm/version.mbt').write_text('not the admitted source\n')
        with self.assertRaisesRegex(ValueError, 'committed clean'):
            self.verify()

    def test_stale_generated_abi_refuses_at_its_original_generator(self):
        c = self.case
        p = c.source / 'packages/python-sdk/src/actql_sdk/_local_wasm_abi.py'
        p.write_bytes(p.read_bytes() + b'\n# independent stale projection\n')
        c.commit()
        with self.assertRaisesRegex(ValueError, 'ABI is stale'):
            self.record()

    def test_unknown_top_level_or_nested_input_fields_refuse(self):
        for change in ('top', 'compiler', 'link'):
            original = deepcopy(self.case.module_original)
            if change == 'top':
                original['extra'] = True
            elif change == 'compiler':
                original['compiler']['moon']['extra'] = True
            else:
                original['link_inputs'][0]['extra'] = True
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.verify(original)

    def test_pin_marker_and_actual_version_refuse_independently(self):
        c = self.case
        marker = c.moon_home / 'installed.json'
        raw = marker.read_bytes()
        marker.write_text(json.dumps({'pin': {}, 'platform': 'darwin-arm64'}))
        with self.assertRaisesRegex(ValueError, 'compiler pin mismatch'):
            self.verify()
        marker.write_bytes(raw)
        (c.moon_home / 'bin/moonc').write_text('#!/bin/sh\nprintf \'foreign compiler\\n\'\n')
        with self.assertRaisesRegex(ValueError, 'compiler version mismatch'):
            self.verify()

    def test_actual_link_input_substitution_and_membership_addition_refuse(self):
        c = self.case
        raw = c.core_input.read_bytes()
        c.core_input.write_bytes(b'independent other compiled input')
        with self.assertRaisesRegex(ValueError, 'link inputs changed'):
            self.verify()
        c.core_input.write_bytes(raw)
        another = c.root / 'another.core'; another.write_bytes(raw)
        c.link_response.write_text(c.link_response.read_text().replace(' -o ', ' ' + str(another) + ' -o '))
        with self.assertRaisesRegex(ValueError, 'link inputs changed'):
            self.verify()

    def test_link_target_limit_output_and_duplicate_inputs_are_not_inferred(self):
        c = self.case
        raw = c.link_response.read_text()
        changes = [raw.replace('-target wasm', '-target js'), raw.replace('256', '512'),
                   raw.replace(' -o ', ' ' + str(c.core_input) + ' -o ')]
        for changed in changes:
            c.link_response.write_text(changed)
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                self.verify()
        c.link_response.write_text(raw)
        other = c.root / 'different.wasm'; other.write_bytes(b'\0asm\x01\0\0\0different')
        c.link_response.write_text(raw.replace(str(c.module), str(other)))
        with self.assertRaisesRegex(ValueError, 'actual link output'):
            self.verify()

    def test_changed_regular_module_and_symlink_inputs_refuse(self):
        c = self.case
        raw = c.module.read_bytes()
        c.module.write_bytes(raw + b'changed')
        with self.assertRaises(fixture.LocalInstallationError):
            self.verify()
        c.module.write_bytes(raw)
        c.core_input.unlink(); c.core_input.symlink_to(c.module)
        with self.assertRaisesRegex(ValueError, 'original regular file'):
            self.verify()

    def test_missing_module_original_and_foreign_contract_do_not_form_final_artifacts(self):
        c = self.case
        for change in ('missing', 'contract'):
            value = deepcopy(c.core)
            if change == 'missing':
                del value['module_original']
            else:
                value['contract']['module_sha256'] = '0' * 64
            c.core_file.write_text(json.dumps(value))
            with self.subTest(change=change), self.assertRaises(ValueError):
                c.run_producer()
            self.assertFalse(c.output.exists())

