"""Closed physical receipt correspondence only; no module/image execution."""
from copy import deepcopy
import unittest

import test_local_artifact_producer as fixture


class PhysicalCoreCohortTests(unittest.TestCase):
    def setUp(self):
        self.case = fixture.LocalArtifactProducerTests()
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.producer = fixture.producer

    def test_selected_image_descriptor_is_shared_by_every_nonzero_phase(self):
        c = self.case
        self.assertEqual(self.producer.verify_original_core(c.source, c.core, c.head),
                         c.core['module_sha256'])
        before = deepcopy(c.core)
        self.assertEqual(self.producer.verify_original_core(c.source, c.core, c.head),
                         c.core['module_sha256'])
        self.assertEqual(c.core, before)
        self.assertFalse(c.output.exists())

    def test_old_module_only_report_cannot_be_relabelled_as_selected_image_execution(self):
        c = self.case
        for name in ('contract', 'result', 'physical', 'workspace'):
            c.core[name].pop('cohort')
        with self.assertRaisesRegex(ValueError, 'selected-image physical cohort'):
            self.producer.verify_original_core(c.source, c.core, c.head)
        c.write_receipts()
        with self.assertRaisesRegex(ValueError, 'selected-image physical cohort'):
            c.run_producer()
        self.assertFalse(c.output.exists())

    def test_every_phase_refuses_raw_jit_foreign_or_missing_execution_kind(self):
        c = self.case
        for name in ('contract', 'result', 'physical', 'workspace'):
            original = deepcopy(c.core[name])
            for mode in ('raw_wasm_jit', 'system_wasmtime', None, True):
                with self.subTest(phase=name, mode=mode):
                    c.core[name] = deepcopy(original)
                    c.core[name]['cohort']['execution_kind'] = mode
                    with self.assertRaisesRegex(ValueError, 'selected image cohort'):
                        self.producer.verify_original_core(c.source, c.core, c.head)
            c.core[name] = original

    def test_module_image_engine_and_both_libraries_are_bound_in_every_phase(self):
        c = self.case
        for name in ('contract', 'result', 'physical', 'workspace'):
            original = deepcopy(c.core[name])
            for field in ('module_sha256', 'image_sha256', 'engine_sha256',
                          'runtime_library_sha256', 'provider_library_sha256'):
                with self.subTest(phase=name, field=field):
                    c.core[name] = deepcopy(original)
                    c.core[name]['cohort'][field] = 'f' * 64
                    with self.assertRaisesRegex(ValueError, 'selected image cohort'):
                        self.producer.verify_original_core(c.source, c.core, c.head)
            c.core[name] = original

    def test_closed_cohort_rejects_unknown_fields_and_unrepresentable_hashes(self):
        c = self.case
        original = deepcopy(c.core)
        for change in ({'extra': True}, {'image_sha256': False},
                       {'image_sha256': 'f' * 63}, {'image_sha256': 'F' * 64}):
            with self.subTest(change=change):
                c.core = deepcopy(original)
                for name in ('contract', 'result', 'physical', 'workspace'):
                    c.core[name]['cohort'].update(change)
                with self.assertRaisesRegex(ValueError, 'cohort'):
                    self.producer.verify_original_core(c.source, c.core, c.head)

    def test_same_wrong_image_in_all_reports_cannot_qualify_a_different_real_component(self):
        c = self.case
        for name in ('contract', 'result', 'physical', 'workspace'):
            c.core[name]['cohort']['image_sha256'] = 'f' * 64
        # The original Core verifier checks mutual correspondence. The final
        # producer additionally binds those observations to actual image bytes.
        self.producer.verify_original_core(c.source, c.core, c.head)
        c.write_receipts()
        with self.assertRaisesRegex(ValueError, 'original compiled image'):
            c.run_producer()
        self.assertFalse(c.output.exists())

    def test_contract_success_without_nonzero_cases_cannot_fill_the_fourth_phase(self):
        c = self.case
        for cases in ([], None, True, 1):
            with self.subTest(cases=cases):
                c.core['contract']['cases'] = cases
                with self.assertRaisesRegex(ValueError, 'nonzero cases'):
                    self.producer.verify_original_core(c.source, c.core, c.head)


if __name__ == '__main__':
    unittest.main()
