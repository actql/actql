"""Original routing over real selected Store/current and scalar Core ports.

Unrelated records use the existing nominal Run issuer with explicit admission
DATA. They are routing fixtures, not N actual accepted/physically executed Runs.
"""
import copy
from dataclasses import replace
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import actql_sdk._local_product as product
from actql_sdk._local_core import LocalCoreError
from actql_sdk._values import wire_bytes
import test_local_finite_run as run_fixture
import test_local_submission_append as append_fixture


class OriginalReferenceIndexTests(unittest.TestCase):
    def fixture(self, directory, count):
        fixture = run_fixture.FiniteRunAssemblyTests()
        self.addCleanup(fixture.doCleanups)
        host, core, events, _ = fixture.assembly(Path(directory))
        self.addCleanup(host.close)
        execution, saved = host._accept_original(
            {'epoch': host.profile()['submissionEpoch'], 'nonce': 'original'},
            append_fixture.INTENT, run_id='original-run')
        self.assertIsNotNone(execution)
        run = execution.run
        original = json.loads(saved)
        # Register unrelated keys backwards so the index must preserve order;
        # the selected real saved admission still comes last in both fixtures.
        for index in reversed(range(count - 1)):
            source = host._copy(wire_bytes({'run_id': f'index-only-{index}', 'now': host._now()}))
            other = host._runs.reserve(run.configuration, run.preparation, source)
            host._run_loans.append(other)
            metadata = copy.deepcopy(original)
            metadata['ref']['runDefinitionCid'] = 'sha256:' + format(index, '064x')
            host._register_original_run_reference(other, wire_bytes(metadata))
        host._register_original_run_reference(run, saved)
        return host, core, run, original, saved, events

    def test_original_selector_probes_and_parses_are_bounded_for_1_10_100_references(self):
        observations = []
        for count, bound in [(1, 1), (10, 4), (100, 7)]:
            with self.subTest(references=count), TemporaryDirectory(prefix='actql-reference-index-') as directory:
                host, core, run, admission, saved, _ = self.fixture(directory, count)
                references = host._public_run_references
                sources = {entry.source for entry in references}
                payloads = [core._inputs[source.ticket].payload for source in sources]
                owned, decode, read = core._owned_input, product._object, host._read_original_saved_admission
                counts = {'probes': 0, 'held_parses': 0, 'saved_reads': 0}
                routing = True

                def original_input(value):
                    if routing and value in sources:
                        counts['probes'] += 1  # One original record comparison/probe.
                    return owned(value)

                def original_json(raw, *args):
                    if routing and any(raw is value for value in payloads):
                        counts['held_parses'] += 1
                    return decode(raw, *args)

                def original_saved(selected):
                    nonlocal routing
                    counts['saved_reads'] += 1
                    self.assertIs(selected, run)
                    routing = False
                    try:
                        return read(selected)
                    finally:
                        routing = True

                with patch.object(core, '_owned_input', side_effect=original_input), \
                        patch.object(product, '_object', side_effect=original_json), \
                        patch.object(host, '_read_original_saved_admission', side_effect=original_saved), \
                        patch.object(host, '_restore_original_run', side_effect=AssertionError('Known ref restored')):
                    selected, observed = host._select_original_run(admission['ref'])
                self.assertIs(selected, run)
                self.assertEqual(observed, saved)
                self.assertEqual(counts['saved_reads'], 1)
                self.assertLessEqual(counts['probes'], bound)
                self.assertEqual(counts['held_parses'], 1)
                self.assertIs(host._public_run_references, references)
                keys = [core._inputs[entry.source.ticket].payload for entry in references]
                self.assertEqual(keys, sorted(keys))
                observations.append((count, counts.copy()))
                self.assertTrue(host.close())
        print('original_reference_index=' + json.dumps(observations, sort_keys=True))


    def test_missing_reference_preserves_existing_restore_refusal_without_preparation(self):
        with TemporaryDirectory(prefix='actql-reference-missing-') as directory:
            host, _, _, admission, _, _ = self.fixture(directory, 10)
            reference = {**admission['ref'], 'runDefinitionCid': 'sha256:' + 'f' * 64}
            refusal = ValueError('Original saved reference unavailable')
            with patch.object(host, '_restore_original_run', side_effect=refusal) as restore, \
                    patch.object(host, '_prepare_original', side_effect=AssertionError('Lookup prepared')):
                with self.assertRaises(ValueError) as failed:
                    host._select_original_run(reference)
                self.assertIs(failed.exception, refusal)
                restore.assert_called_once_with(reference)
            self.assertFalse(host._has_live_original_run_reference(reference))
            self.assertTrue(host.close())

    def test_foreign_released_run_and_released_input_never_become_authority_from_index(self):
        for state in ['foreign-run', 'released-run', 'released-input']:
            with self.subTest(state=state), TemporaryDirectory(prefix='actql-reference-original-') as directory:
                host, core, run, admission, _, _ = self.fixture(directory, 10)
                references = host._public_run_references
                index = next(i for i, entry in enumerate(references) if entry.run is run)
                entry = references[index]
                if state == 'foreign-run':
                    references[index] = replace(entry, run=copy.copy(run))
                elif state == 'released-run':
                    self.assertTrue(host._runs.close_run(run))
                else:
                    self.assertTrue(core.close_input(entry.source))
                    host._inputs.remove(entry.source)
                try:
                    with patch.object(host, '_restore_original_run', side_effect=AssertionError('Index hit restored')), \
                            patch.object(host, '_prepare_original', side_effect=AssertionError('Index hit prepared')):
                        with self.assertRaises(ValueError):
                            host._select_original_run(admission['ref'])
                finally:
                    if state == 'foreign-run':
                        references[index] = entry
                    elif state == 'released-run':
                        host._run_loans.remove(run)
                        references.pop(index)
                    else:
                        references.pop(index)
                self.assertTrue(host.close())

    def test_actual_account_current_and_typed_saved_refusal_still_follow_index_hit(self):
        for state in ['changed-account', 'typed-stale-verifier']:
            with self.subTest(state=state), TemporaryDirectory(prefix='actql-reference-current-') as directory:
                host, core, _, admission, _, _ = self.fixture(directory, 10)
                previous = core._call
                inspected = []

                def original_call(family, name, *args):
                    value = previous(family, name, *args)
                    if (family, name) == ('journal', 'inspect'):
                        inspected.append(args[0])
                        return -42 if state == 'typed-stale-verifier' else value
                    return value

                if state == 'changed-account':
                    binding = host._installation.binding
                    os.chmod(binding._account.name, 0o644, dir_fd=binding._source._root._open())
                with patch.object(core, '_call', side_effect=original_call), \
                        patch.object(host, '_restore_original_run', side_effect=AssertionError('Refusal restored')), \
                        patch.object(host, '_prepare_original', side_effect=AssertionError('Refusal prepared')):
                    if state == 'changed-account':
                        with self.assertRaisesRegex(Exception, 'original generation'):
                            host._select_original_run(admission['ref'])
                        self.assertFalse(inspected)
                    else:
                        # The scalar port forwards the actual original Store
                        # read, then supplies the original typed verifier error.
                        with self.assertRaises(LocalCoreError) as failed:
                            host._select_original_run(admission['ref'])
                        self.assertEqual(failed.exception.code, -42)
                        self.assertEqual(len(inspected), 1)
                self.assertTrue(host.close())

    def test_registration_refusals_and_original_cleanup_chronology_are_unchanged(self):
        with TemporaryDirectory(prefix='actql-reference-register-') as directory:
            host, core, run, admission, saved, _ = self.fixture(directory, 10)
            references = host._public_run_references
            inputs = list(host._inputs)
            loans = list(host._run_loans)
            host._register_original_run_reference(run, saved)
            changed = {**admission, 'ref': {**admission['ref'], 'runDefinitionCid': 'sha256:' + 'e' * 64}}
            with self.assertRaisesRegex(ValueError, 'reference changed'):
                host._register_original_run_reference(run, wire_bytes(changed))
            self.assertEqual(host._inputs, inputs)
            self.assertEqual(host._run_loans, loans)
            source = host._copy(wire_bytes({'run_id': 'ambiguous-metadata', 'now': host._now()}))
            other = host._runs.reserve(run.configuration, run.preparation, source)
            host._run_loans.append(other)
            before = list(host._inputs)
            with self.assertRaisesRegex(ValueError, 'Ambiguous'):
                host._register_original_run_reference(other, saved)
            self.assertEqual(host._inputs, before)
            self.assertIs(host._public_run_references, references)
            closed, close = [], host._runs.close_run

            def original_close(selected):
                closed.append(selected)
                return close(selected)

            with patch.object(host._runs, 'close_run', side_effect=original_close):
                self.assertTrue(host.close())
            self.assertEqual(closed, list(reversed([*loans, other])))
            self.assertFalse(references)

    def test_reference_input_is_not_a_mutable_output_and_field_order_does_not_change_key(self):
        with TemporaryDirectory(prefix='actql-reference-bytes-') as directory:
            host, core, run, admission, saved, _ = self.fixture(directory, 10)
            entry = next(entry for entry in host._public_run_references if entry.run is run)
            raw = core._inputs[entry.source.ticket].payload
            self.assertIs(type(raw), bytes)
            with self.assertRaises(ValueError):
                core.read_material(entry.source)
            self.assertIs(core._inputs[entry.source.ticket].payload, raw)
            reordered = dict(reversed(list(admission['ref'].items())))
            selected, observed = host._select_original_run(reordered)
            self.assertIs(selected, run)
            self.assertEqual(observed, saved)
            self.assertTrue(host._has_live_original_run_reference(reordered))
            self.assertIs(core._inputs[entry.source.ticket].payload, raw)
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
