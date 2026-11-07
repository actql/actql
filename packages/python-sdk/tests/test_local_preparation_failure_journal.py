"""Real File/SQLite terminal CAS with explicit scalar Core preparation ports.

The separate Wasm parser test establishes the typed issuer. These tests exercise
its Python original-handle, current, transaction, lookup and cleanup connection;
they do not load a Wasm artifact or claim installed ordinary acceptance.
"""
import asyncio
from dataclasses import replace
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_preparation import LocalPreparationFailure
from actql_sdk._local_storage import LocalStorageCommitUnknown
from actql_sdk._values import content_cid, wire_bytes
import test_local_submission_append as original_append
from local_abi_declaration_fixture import original_byte_fixture_port

FAILED = b'{"preparation_problem_classification":"invalid_input","preparation_problem_code":"ClientProgramInvalidInput"}'


class PreparationFailureJournalTests(unittest.TestCase):
    def fixture(self, directory):
        original = original_append.LocalSubmissionAppendTests()
        host, core, calls, _ = original.host(Path(directory))
        self.addCleanup(host.close)
        host._configuration = replace(host._configuration, sdk=True)
        host._runs._configurations[host._configuration.handle] = host._configuration
        reference = original.reference(host)
        base = core._call
        selected, outputs, plans = {}, {}, {}
        counts = {'prepare': 0, 'failure': 0, 'lookup': 0, 'validate': 0}
        intent_cid = content_cid({'version': 'actql-submitted-intent/0.1',
            'intent': json.loads(original_append.INTENT)}, data_keys=True)

        def row():
            callback = core._journal_callbacks(host._installation.binding._current.ticket)
            self.assertIsNotNone(callback.reader)
            self.assertEqual(callback.check_current(), 0)
            rows = []
            callback.reader.read('client_submitted_intents', original_append.REQUEST,
                                 lambda value: rows.append(value))
            return rows[0][1] if rows[0] is not None else None

        def call(family, name, *args):
            if family == 'program':
                calls.append((family, name, args))
                if name in ('install_environment', 'reserve_preparation'):
                    return 9000 + len(calls)
                if name == 'prepare':
                    counts['prepare'] += 1
                    return 0
                if name == 'prepared_outcome':
                    return 2
                if name in ('close_preparation', 'close_environment'):
                    return 0
                raise AssertionError('Known failure must never read plan counts')
            if family == 'submission' and name == 'reserve' and args[2] == 4:
                handle = 100 + args[3]
                selected[handle] = 'lookup'
                return handle
            if family == 'submission' and name == 'reserve_failure':
                self.assertEqual(args[0], host._configuration.handle)
                prepared = host._preparation._preparations[args[1]]
                self.assertIs(host._preparation._failures[args[1]].preparation, prepared)
                self.assertEqual(core._inputs[prepared.input.ticket].payload, original_append.INTENT)
                self.assertEqual(json.loads(core._inputs[args[2] - 100].payload),
                                 {'reference': wire_bytes(reference).decode()})
                handle = 100 + args[3]
                selected[handle] = 'failure'
                return handle
            if family == 'submission' and name == 'produce' and args[0] in selected:
                original_row = row()
                if selected[args[0]] == 'lookup':
                    counts['lookup'] += 1
                    observed = ({'kind': 'missing'} if original_row is None else
                        {'kind': 'preparation_failed', 'intentCid': intent_cid,
                         'problemCode': 'ClientProgramInvalidInput', 'problemClassification': 'invalid_input'}
                        if original_row.payload == FAILED else {'kind': 'preparing', 'intentCid': intent_cid})
                else:
                    counts['failure'] += 1
                    self.assertEqual(original_row.payload, original_append.PREPARING)
                    plans[args[0]] = original_row
                    observed = {'key': original_append.REQUEST, 'revision': str(original_row.generation),
                                'before': original_row.payload.decode(), 'body': FAILED.decode()}
                outputs[args[0]] = wire_bytes(observed)
                return 0
            if family == 'submission' and name == 'validate_append' and args[0] in selected:
                actual = row()
                if selected[args[0]] == 'failure':
                    counts['validate'] += 1
                    expected = plans[args[0]]
                    return 0 if (actual.generation, actual.payload) == (expected.generation, expected.payload) else -32
                return 0
            if name == 'length' and args[0] in outputs:
                return len(outputs[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][args[1]]
            return base(family, name, *args)

        core._call = original_byte_fixture_port(call)
        return host, core, calls, counts, reference, intent_cid

    def test_accepted_typed_failure_commits_then_independent_lookup_without_run(self):
        with TemporaryDirectory(prefix='actql-failure-terminal-') as directory:
            host, _, calls, counts, reference, identity = self.fixture(directory)
            run, saved = host._accept_original(reference, original_append.INTENT, run_id='must-not-issue')
            self.assertIsNone(run)
            self.assertEqual(json.loads(saved), {'kind': 'preparation_failed', 'submissionRef': reference,
                'intentCid': identity, 'problem': {'code': 'ClientProgramInvalidInput',
                                                 'classification': 'invalid_input'}})
            self.assertEqual(counts['prepare'], 1)
            self.assertEqual(counts['failure'], 1)
            self.assertEqual(counts['lookup'], 1)
            self.assertGreaterEqual(counts['validate'], 3)
            self.assertFalse(host._prepared_inputs)
            self.assertFalse(host._run_loans)
            self.assertFalse(host._physical_work)
            self.assertFalse(any(family in ('compute', 'publication') or
                                 family == 'run' and name in ('reserve', 'prepare')
                                 for family, name, _ in calls))
            self.assertTrue(host.close())

    def test_public_first_attempt_reports_recorded_terminal_without_scheduling_work(self):
        with TemporaryDirectory(prefix='actql-failure-public-') as directory:
            host, _, _, counts, reference, identity = self.fixture(directory)
            body = {'connection': {'mode': 'local', 'owner': 'local', 'durability': 'durable',
                'consentRefs': [], 'runners': []}, **json.loads(original_append.INTENT),
                'submissionRef': reference, 'intentCid': identity,
                'attemptRef': {'operation': 'submit', 'attemptId': 'first-original'}}
            async def submit():
                response = await host.open('submit-intent', wire_bytes(body))
                try:
                    return json.loads(await response.aread())
                finally:
                    await response.aclose()
            response = asyncio.run(submit())
            self.assertEqual(response['kind'], 'recorded')
            self.assertEqual(response['attemptRef'], body['attemptRef'])
            self.assertEqual(response['outcome']['kind'], 'preparation_failed')
            self.assertEqual(counts['prepare'], 1)
            self.assertFalse(host._physical_work)
            self.assertFalse(host._public_run_references)
            self.assertTrue(host.close())

    def test_current_failure_after_typed_parser_result_prevents_terminal_write(self):
        with TemporaryDirectory(prefix='actql-failure-post-current-') as directory:
            host, _, _, counts, reference, _ = self.fixture(directory)
            binding = host._installation.binding
            original = binding.inspect
            def refuse_after(action):
                result = original(action)
                if host._preparation._failures:
                    raise LocalCoreError('original_post_prepare_current', -32)
                return result
            with patch.object(binding, 'inspect', side_effect=refuse_after):
                with self.assertRaises(LocalCoreError):
                    host._accept_original(reference, original_append.INTENT, run_id='must-not-issue')
            self.assertEqual(counts['prepare'], 1)
            self.assertEqual(counts['failure'], 0)
            self.assertEqual(counts['lookup'], 0)
            self.assertTrue(host._prepared_inputs)
            self.assertTrue(host.close())

    def test_lost_commit_reply_keeps_same_failed_preparation_and_never_looks_up_or_retries(self):
        with TemporaryDirectory(prefix='actql-failure-lost-') as directory:
            host, core, _, counts, reference, _ = self.fixture(directory)
            store = host._installation._store
            original = store.compare_exchange_many_inspected
            writes = []
            def lose(batch, *args, **kwargs):
                result = original(batch, *args, **kwargs)
                if any(write.payload == FAILED for write in batch):
                    writes.append(result)
                    raise LocalStorageCommitUnknown(store)
                return result
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=lose):
                with self.assertRaises(LocalStorageCommitUnknown):
                    host._accept_original(reference, original_append.INTENT, run_id='must-not-issue')
            self.assertEqual(len(writes), 1)
            self.assertEqual(counts['lookup'], 0)
            self.assertEqual(counts['prepare'], 1)
            self.assertEqual(counts['failure'], 1)
            prepared = host._prepared_inputs[0]
            self.assertIs(host._preparation._failures[prepared.handle].preparation, prepared)
            output = host._projections[-1]
            self.assertIs(core._loans[output.ticket], output)
            self.assertFalse(host._run_loans)
            self.assertTrue(host.close())

    def test_same_saved_failure_or_preparing_does_not_reprepare_and_changed_intent_conflicts(self):
        with TemporaryDirectory(prefix='actql-failure-same-') as directory:
            host, _, _, counts, reference, identity = self.fixture(directory)
            host._retain_intent(reference, original_append.INTENT)
            body = {'connection': {'mode': 'local', 'owner': 'local', 'durability': 'durable',
                'consentRefs': [], 'runners': []}, **json.loads(original_append.INTENT),
                'submissionRef': reference, 'intentCid': identity,
                'attemptRef': {'operation': 'submit', 'attemptId': 'same-original'}}
            async def submit():
                response = await host.open('submit-intent', wire_bytes(body))
                try:
                    return json.loads(await response.aread())
                finally:
                    await response.aclose()
            with patch.object(host, '_accept_original', side_effect=AssertionError('Repeated accepted preparation')):
                preparing = asyncio.run(submit())
            self.assertEqual(preparing['kind'], 'recorded')
            self.assertEqual(preparing['outcome']['kind'], 'preparing')
            host._accept_original(reference, original_append.INTENT, run_id='must-not-issue')
            with patch.object(host, '_accept_original', side_effect=AssertionError('Repeated terminal preparation')):
                terminal = asyncio.run(submit())
                self.assertEqual(terminal['kind'], 'already_satisfied')
                self.assertEqual(terminal['outcome']['kind'], 'preparation_failed')
                body['parameters'] = {'different': True}
                body['intentCid'] = content_cid({'version': 'actql-submitted-intent/0.1',
                    'intent': {key: body[key] for key in ('kind', 'input', 'parameters')}}, data_keys=True)
                conflict = asyncio.run(submit())
                self.assertEqual(conflict['kind'], 'conflict')
            self.assertEqual(counts['prepare'], 1)
            self.assertTrue(host.close())

    def test_refused_terminal_revalidation_rolls_back_and_keeps_original_failure(self):
        with TemporaryDirectory(prefix='actql-failure-current-') as directory:
            host, core, _, counts, reference, _ = self.fixture(directory)
            original = core.validate_submission_append
            def refuse(output, current):
                if counts['failure']:
                    raise LocalCoreError('validate_submission_append', -32)
                return original(output, current)
            with patch.object(core, 'validate_submission_append', side_effect=refuse):
                with self.assertRaises(LocalCoreError):
                    host._accept_original(reference, original_append.INTENT, run_id='must-not-issue')
            store = host._installation._store
            self.assertEqual(store.read(store.namespaced_key('client_submitted_intents', original_append.REQUEST)).payload,
                             original_append.PREPARING)
            self.assertEqual(counts['lookup'], 0)
            self.assertEqual(counts['prepare'], 1)
            self.assertIsInstance(next(iter(host._preparation._failures.values())), LocalPreparationFailure)
            self.assertFalse(host._run_loans)
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
