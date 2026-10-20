"""Same-Store/current transport checks with scalar Core, not installed evidence."""
import asyncio
import copy
from dataclasses import replace
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_product import LocalProductCleanupPending
from actql_sdk._local_submission import LocalSubmissionIdentityError
import test_local_submission_append as append_fixture


class LocalSubmissionLookupTests(unittest.TestCase):
    def fixture(self, directory, observed, *, run_reference=None, result_name=None):
        fixture = append_fixture.LocalSubmissionAppendTests()
        host, core, calls, _ = fixture.host(Path(directory))
        if result_name is not None:
            # Scalar metadata selects this transport branch only. It does not
            # prove actual SDK Account/profile/Run admission or Core execution.
            host._configuration = replace(host._configuration, sdk=True)
            host._runs._configurations[host._configuration.handle] = host._configuration
        self.addCleanup(host.close)
        reference = fixture.reference(host)
        base = core._call
        outputs, sources = {}, {}
        counters = {'produce': 0, 'validate': 0}

        def current():
            callbacks = core._journal_callbacks(host._installation.binding._current.ticket)
            self.assertIsNotNone(callbacks.reader)
            self.assertEqual(callbacks.check_current(), 0)
            return callbacks

        def call(family, name, *args):
            if family == 'submission' and name == 'reserve' and args[2] in (4, 5, 6):
                # Reserve output custody before entering its physical Read.
                callbacks = core._journal_callbacks(host._installation.binding._current.ticket)
                self.assertIsNone(callbacks.reader)
                handle = 100 + args[3]
                self.assertEqual(args[2], 6 if result_name is not None else 4 if run_reference is None else 5)
                sources[handle] = args[1]
                return handle
            if family == 'submission' and name == 'produce' and args[0] in sources:
                counters['produce'] += 1
                current()
                source = core._inputs[sources[args[0]] - 100].payload
                expected = ({'reference': json.dumps(reference, ensure_ascii=False, separators=(',', ':'))}
                            if run_reference is None else run_reference if result_name is None else
                            {**run_reference, "resultName": result_name})
                self.assertEqual(json.loads(source), expected)
                outputs[args[0]] = json.dumps(observed, separators=(',', ':')).encode()
                return 0
            if family == 'submission' and name == 'validate_append' and args[0] in sources:
                counters['validate'] += 1
                current()
                return 0
            if name == 'length' and args[0] in outputs:
                return len(outputs[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][args[1]]
            return base(family, name, *args)

        core._call = call
        return host, core, calls, counters, reference

    def test_ready_lookup_uses_original_admission_without_preparation_or_resend(self):
        admission = {'ref': {'namespaceId': 'local',
            'authorityScopeCid': 'sha256:' + 'a' * 64,
            'runDefinitionCid': 'sha256:' + 'd' * 64},
            'durability': 'durable', 'revision': 7}
        with TemporaryDirectory(prefix='actql-lookup-') as directory:
            host, _, calls, counters, reference = self.fixture(directory, {
                'kind': 'ready', 'intentCid': 'sha256:' + 'e' * 64,
                'admission': json.dumps(admission, separators=(',', ':'))})
            store = host._installation._store
            with patch.object(store, 'compare_exchange_many_inspected',
                              side_effect=AssertionError('Lookup must not submit a write')):
                async def observe():
                    response = await host.open('lookup-submission', json.dumps({
                        'connection': {'mode': 'local', 'owner': 'local', 'durability': 'durable',
                            'consentRefs': [], 'runners': []}, 'submissionRef': reference}).encode())
                    try:
                        return json.loads(await response.aread())
                    finally:
                        await response.aclose()
                result = asyncio.run(observe())
            self.assertEqual(result, {'kind': 'ready', 'submissionRef': reference,
                'intentCid': 'sha256:' + 'e' * 64, 'admission': admission})
            self.assertEqual(counters['produce'], 1)
            self.assertEqual(counters['validate'], 3)
            self.assertFalse(host._projections)
            self.assertFalse(host._append_sources)
            self.assertFalse(any(family in ('program', 'compute', 'publication')
                                 or family == 'run' and name in ('reserve', 'prepare')
                                 for family, name, _ in calls))
            self.assertTrue(host.close())

    def test_missing_is_unresolvable_and_preparing_never_acquires_a_run(self):
        for original in ({'kind': 'missing'},
                         {'kind': 'preparing', 'intentCid': 'sha256:' + 'e' * 64}):
            with self.subTest(original=original), TemporaryDirectory(prefix='actql-lookup-') as directory:
                host, _, _, _, reference = self.fixture(directory, original)
                result = json.loads(host._lookup_original_submission(reference))
                self.assertEqual(result['submissionRef'], reference)
                self.assertNotIn('admission', result)
                if original['kind'] == 'missing':
                    self.assertEqual(result['kind'], 'unresolvable')
                    self.assertEqual(result['problem'], {'code': 'submission_history_unresolvable'})
                else:
                    self.assertEqual(result['kind'], 'preparing')
                self.assertFalse(host._run_loans)
                self.assertTrue(host.close())

    def test_foreign_authenticator_refuses_before_lookup_acquisition(self):
        with TemporaryDirectory(prefix='actql-lookup-') as directory:
            host, _, _, counters, reference = self.fixture(directory, {'kind': 'missing'})
            foreign = copy.deepcopy(reference)
            foreign['epoch']['authenticator'] = '0' * 64
            with self.assertRaises(LocalSubmissionIdentityError):
                host._lookup_original_submission(foreign)
            self.assertEqual(counters['produce'], 0)
            self.assertFalse(host._projections)
            self.assertTrue(host.close())

    def test_failed_snapshot_validation_retains_original_output_until_cleanup(self):
        with TemporaryDirectory(prefix='actql-lookup-') as directory:
            host, core, _, counters, reference = self.fixture(directory, {'kind': 'missing'})
            with patch.object(core, 'validate_submission_lookup',
                              side_effect=LocalCoreError('validate_submission_lookup', -32)):
                with self.assertRaises(LocalCoreError):
                    host._lookup_original_submission(reference)
            self.assertEqual(counters['produce'], 1)
            output = host._projections[-1]
            self.assertIs(core._loans[output.ticket], output)
            with self.assertRaises(ValueError):
                core.close_submission_lookup(copy.copy(output))
            self.assertTrue(host.close())

    def test_pending_close_keeps_same_output_and_input_for_same_handle_cleanup(self):
        with TemporaryDirectory(prefix='actql-lookup-') as directory:
            host, core, _, _, reference = self.fixture(directory, {'kind': 'missing'})
            original = core.close_submission_lookup
            with patch.object(core, 'close_submission_lookup', return_value=False):
                with self.assertRaises(LocalProductCleanupPending):
                    host._lookup_original_submission(reference)
            output = host._projections[-1]
            source = host._append_sources[output.ticket]
            self.assertIs(core._loans[output.ticket], output)
            self.assertIs(core._loans[source.ticket], source)
            with patch.object(core, 'close_submission_lookup', wraps=original) as close:
                self.assertTrue(host.close())
                close.assert_called_once_with(output)

    def test_public_attach_returns_exact_original_admission_without_executable_run(self):
        reference = {'namespaceId': 'local', 'authorityScopeCid': 'sha256:' + 'a' * 64,
                     'runDefinitionCid': 'sha256:' + 'd' * 64}
        admission = {'ref': reference, 'durability': 'durable', 'revision': 7}
        with TemporaryDirectory(prefix='actql-attach-') as directory:
            host, _, calls, counts, _ = self.fixture(directory, {
                'kind': 'ready', 'intentCid': 'sha256:' + 'e' * 64,
                'admission': json.dumps(admission)}, run_reference=reference)
            async def attach():
                response = await host.open('attach', json.dumps({
                    'connection': {'mode': 'local', 'owner': 'local', 'durability': 'durable',
                        'consentRefs': [], 'runners': []}, 'ref': reference}).encode())
                try:
                    return json.loads(await response.aread())
                finally:
                    await response.aclose()
            self.assertEqual(asyncio.run(attach()), admission)
            self.assertEqual(counts['produce'], 1)
            self.assertFalse(host._run_loans)
            self.assertFalse(host._prepared_inputs)
            self.assertFalse(host._public_run_references)
            self.assertFalse(any(family in ('program', 'compute', 'publication')
                                 for family, _, _ in calls))
            self.assertTrue(host.close())

    def test_attach_missing_original_is_unavailable_without_admission_or_repair(self):
        reference = {'namespaceId': 'local', 'authorityScopeCid': 'sha256:' + 'a' * 64,
                     'runDefinitionCid': 'sha256:' + 'd' * 64}
        with TemporaryDirectory(prefix='actql-attach-') as directory:
            host, core, _, _, _ = self.fixture(directory, {'kind': 'missing'},
                                               run_reference=reference)
            with self.assertRaisesRegex(ValueError, 'Run is unavailable'):
                host._attach_original_run(reference)
            self.assertFalse(host._run_loans)
            output = host._projections[-1]
            self.assertIs(core._loans[output.ticket], output)
            self.assertTrue(host.close())

    def test_attach_rejects_another_original_reference_without_changing_it(self):
        requested = {'namespaceId': 'local', 'authorityScopeCid': 'sha256:' + 'a' * 64,
                     'runDefinitionCid': 'sha256:' + 'd' * 64}
        foreign = {**requested, 'runDefinitionCid': 'sha256:' + 'f' * 64}
        with TemporaryDirectory(prefix='actql-attach-') as directory:
            host, _, _, _, _ = self.fixture(directory, {
                'kind': 'ready', 'intentCid': 'sha256:' + 'e' * 64,
                'admission': json.dumps({'ref': foreign, 'durability': 'durable', 'revision': 7})},
                run_reference=requested)
            with self.assertRaisesRegex(ValueError, 'Foreign original Local Run admission'):
                host._attach_original_run(requested)
            self.assertFalse(host._run_loans)
            self.assertTrue(host.close())

    def test_saved_result_reader_keeps_nominal_owner_without_compiling_or_delivering(self):
        reference = {'namespaceId': 'local', 'authorityScopeCid': 'sha256:' + 'a' * 64,
                     'runDefinitionCid': 'sha256:' + 'd' * 64}
        packet = {'resultOrdinal': '0', 'bindingOrdinal': '0', 'kind': 'result-originals', 'resultName': 'answer',
                  'runDefinitionCid': reference['runDefinitionCid'],
                  **{name: '{"fixture":"transport"}' for name in
                     ('index', 'manifest', 'definition', 'artifact', 'retention', 'binding')}}
        with TemporaryDirectory(prefix='actql-cold-read-') as directory:
            host, core, calls, counts, _ = self.fixture(directory, packet,
                run_reference=reference, result_name='answer')
            store = host._installation._store
            with patch.object(store, 'compare_exchange_many_inspected',
                              side_effect=AssertionError('Metadata read must not write or deliver')):
                output = host._retain_original_result_read(reference, 'answer')
            self.assertIs(core._loans[output.ticket], output)
            self.assertIs(host._projections[-1], output)
            self.assertFalse(host._run_loans)
            self.assertFalse(host._prepared_inputs)
            self.assertEqual(counts, {'produce': 1, 'validate': 3})
            self.assertFalse(any(family in ('program', 'compute', 'publication')
                                 for family, _, _ in calls))
            with patch.object(core, 'close_submission_lookup', return_value=False):
                self.assertFalse(host._close_projection(output))
                self.assertIs(core._loans[output.ticket], output)
            self.assertTrue(host._close_projection(output))
            self.assertTrue(host.close())

    def test_saved_result_reader_rejects_changed_selection_with_same_cleanup_carrier(self):
        reference = {'namespaceId': 'local', 'authorityScopeCid': 'sha256:' + 'a' * 64,
                     'runDefinitionCid': 'sha256:' + 'd' * 64}
        packet = {'resultOrdinal': '0', 'bindingOrdinal': '0', 'kind': 'result-originals', 'resultName': 'foreign',
                  'runDefinitionCid': reference['runDefinitionCid'],
                  **{name: '{}' for name in
                     ('index', 'manifest', 'definition', 'artifact', 'retention', 'binding')}}
        with TemporaryDirectory(prefix='actql-cold-foreign-') as directory:
            host, core, _, _, _ = self.fixture(directory, packet,
                run_reference=reference, result_name='answer')
            with self.assertRaisesRegex(ValueError, 'Foreign original saved Local Result'):
                host._retain_original_result_read(reference, 'answer')
            original = host._projections[-1]
            self.assertIs(core._loans[original.ticket], original)
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
