"""Scalar Core and real SQLite transport boundaries, not Wasm/public admission."""
import copy
from dataclasses import replace
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError, _Output
from actql_sdk._local_storage import LocalStorageCommitUnknown, LocalStorageError
import test_local_run as run_fixture
import test_local_submission_append as append_fixture
from local_abi_declaration_fixture import original_byte_fixture_port

RUN_KEY = 'sha256:' + 'a' * 64
RUN_BODY = b'{"opaque":"original Core Run and packet e\xcc\x81/~","null":null}'
READY = b'{"opaque":"original Core ready e\xcc\x81/~","null":null}'


class FiniteRunFacadeTests(unittest.TestCase):
    def bridge(self):
        core, _, custody, _, _, configuration, run, calls, codes = run_fixture.RunCustodyTests().bridge()
        current = _Output(core._identity, 99, 999, 65536, 'current')
        core._loans[99] = current
        configuration = replace(configuration, current=current, sdk=True)
        custody._configurations[configuration.handle] = configuration
        run = replace(run, configuration=configuration)
        custody._runs[run.handle] = run
        observed = _Output(core._identity, 98, 998, 1048576, 'submission_append')
        core._loans[98] = observed
        core._host_current_ready = lambda _: None
        core._journal_callbacks = lambda _: None
        return core, custody, run, observed, calls, codes

    def test_ready_original_requires_restore_without_prepared_or_start(self):
        core, custody, run, observed, calls, codes = self.bridge()
        codes['run', 'prepare_sdk'] = 2
        before = len(calls)
        self.assertEqual(custody.prepare_sdk(run, observed), 'restore_required')
        self.assertEqual(calls[before:], [('run', 'prepare_sdk', (run.handle, observed.handle))])
        self.assertIs(custody._runs[run.handle], run)
        self.assertIs(core._loans[observed.ticket], observed)

    def test_finite_configuration_refuses_absolute_deadline_entry_before_io(self):
        _, custody, run, _, calls, _ = self.bridge()
        before = len(calls)
        with self.assertRaisesRegex(ValueError, 'original submission lookup'):
            custody.prepare(run)
        self.assertEqual(len(calls), before)

    def test_refusal_and_trap_keep_original_run_and_observation_without_retry(self):
        for refusal in (-35, -41, RuntimeError('Original invocation trap')):
            core, custody, run, observed, calls, codes = self.bridge()
            codes['run', 'prepare_sdk'] = refusal
            before = len(calls)
            with self.assertRaises((LocalCoreError, RuntimeError)):
                custody.prepare_sdk(run, observed)
            self.assertEqual(calls[before:], [('run', 'prepare_sdk', (run.handle, observed.handle))])
            self.assertIs(custody._runs[run.handle], run)
            self.assertIs(core._loans[observed.ticket], observed)

    def test_foreign_observation_and_run_copy_cannot_reach_core(self):
        _, custody, run, observed, calls, _ = self.bridge()
        before = len(calls)
        for action in (
            lambda: custody.prepare_sdk(copy.copy(run), observed),
            lambda: custody.prepare_sdk(run, copy.copy(observed)),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)


class FiniteRunSQLiteTests(unittest.TestCase):
    def test_retained_task_chunks_commit_in_same_original_ready_transaction(self):
        with TemporaryDirectory(prefix='actql-retained-task-') as directory:
            host, _, output, validations, _, candidate = self.host(Path(directory))
            chunks = [{'key': RUN_KEY + ':0', 'body': 'é' * 65536},
                      {'key': RUN_KEY + ':1', 'body': 'original-tail'}]
            candidate['task_materials'] = chunks
            host._commit_original_run_rows(output)
            store = host._installation._store
            self.assertEqual(store.read(store.namespaced_key('client_run_custody', 'issued')).payload, b'1')
            self.assertEqual(store.read(store.namespaced_key('client_runs', RUN_KEY)).payload, RUN_BODY)
            self.assertEqual(store.read(store.namespaced_key('client_submitted_intents', append_fixture.REQUEST)).payload, READY)
            for chunk in chunks:
                saved = store.read(store.namespaced_key('client_task_run_materials', chunk['key']))
                self.assertEqual(saved.payload, chunk['body'].encode())
                self.assertEqual(saved.generation, 0)
            self.assertEqual(len(validations), 2)
            self.assertIs(host._pending_run_write, output)
            self.assertIn(output.ticket, host._row_write_attempts)
            self.assertTrue(host.close())

    def test_retained_task_chunk_refusal_rolls_back_ready_and_preserves_original_output(self):
        with TemporaryDirectory(prefix='actql-retained-task-refusal-') as directory:
            host, core, output, _, statuses, candidate = self.host(Path(directory))
            key = RUN_KEY + ':0'
            candidate['task_materials'] = [{'key': key, 'body': 'original task material'}]
            statuses[2] = -32
            with self.assertRaises(LocalCoreError):
                host._commit_original_run_rows(output)
            store = host._installation._store
            count, run, submitted = self.rows(host)
            self.assertEqual((count.payload, count.generation), (b'0', 0))
            self.assertIsNone(run)
            self.assertEqual(submitted.payload, append_fixture.PREPARING)
            self.assertIsNone(store.read(store.namespaced_key('client_task_run_materials', key)))
            self.assertIs(core._loans[output.ticket], output)
            self.assertTrue(host.close())

    def test_retained_task_lost_reply_keeps_all_original_rows_without_repeating_transaction(self):
        with TemporaryDirectory(prefix='actql-retained-task-loss-') as directory:
            host, core, output, _, _, candidate = self.host(Path(directory))
            key = RUN_KEY + ':0'
            candidate['task_materials'] = [{'key': key, 'body': 'original task material'}]
            store = host._installation._store
            original = store.compare_exchange_many_inspected
            def lose(*args, **kwargs):
                original(*args, **kwargs)
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=lose) as write:
                with self.assertRaises(LocalStorageCommitUnknown):
                    host._commit_original_run_rows(output)
                with self.assertRaisesRegex(LocalStorageError, 'transport replay'):
                    host._commit_original_run_rows(output)
                self.assertEqual(write.call_count, 1)
            self.assertEqual(store.read(store.namespaced_key('client_task_run_materials', key)).payload,
                             b'original task material')
            self.assertIs(core._loans[output.ticket], output)
            self.assertIs(host._pending_run_write, output)
            self.assertTrue(host.close())

    def test_retained_task_chunk_shape_and_original_order_refuse_before_write(self):
        for chunks in ([], [{'key': RUN_KEY + ':1', 'body': 'wrong ordinal'}],
                       [{'key': RUN_KEY + ':0', 'body': 'x', 'extra': None}],
                       [{'key': RUN_KEY + ':0', 'body': ''}],
                       [{'key': RUN_KEY + ':' + str(i), 'body': 'x'} for i in range(4)]):
            with self.subTest(chunks=chunks), TemporaryDirectory(prefix='actql-task-shape-') as directory:
                host, _, output, _, _, candidate = self.host(Path(directory))
                candidate['task_materials'] = chunks
                with self.assertRaises(ValueError):
                    host._commit_original_run_rows(output)
                self.assertIsNone(self.rows(host)[1])
                self.assertTrue(host.close())

    def test_original_reference_locator_commits_with_same_ready_rows(self):
        with TemporaryDirectory(prefix='actql-original-locator-') as directory:
            host, _, output, validations, _, candidate = self.host(Path(directory))
            # This is original Core DATA supplied by an explicit scalar port.
            # Python does not derive a locator or authenticate this fixture.
            key = '7' * 64
            body = '{"original":"reference é/~"}'
            candidate['reference_locator'] = {'key': key, 'body': body}
            host._commit_original_run_rows(output)
            store = host._installation._store
            saved = store.read(store.namespaced_key('client_run_reference_index', key))
            self.assertEqual((saved.payload, saved.generation), (body.encode(), 0))
            count, run, submitted = self.rows(host)
            self.assertEqual((count.payload, count.generation), (b'1', 1))
            self.assertEqual(run.payload, RUN_BODY)
            self.assertEqual(submitted.payload, READY)
            self.assertEqual(len(validations), 2)
            self.assertTrue(host.close())

    def test_original_reference_locator_refusal_rolls_back_and_unknown_never_replays(self):
        for lost_reply in (False, True):
            with self.subTest(lost_reply=lost_reply), TemporaryDirectory(prefix='actql-locator-stop-') as directory:
                host, core, output, _, statuses, candidate = self.host(Path(directory))
                key = '8' * 64
                body = '{"original":"retained reference"}'
                candidate['reference_locator'] = {'key': key, 'body': body}
                store = host._installation._store
                original = store.compare_exchange_many_inspected
                if lost_reply:
                    def lose(*args, **kwargs):
                        original(*args, **kwargs)
                        raise LocalStorageCommitUnknown(store)
                    with patch.object(store, 'compare_exchange_many_inspected', side_effect=lose) as write:
                        with self.assertRaises(LocalStorageCommitUnknown):
                            host._commit_original_run_rows(output)
                        with self.assertRaisesRegex(LocalStorageError, 'transport replay'):
                            host._commit_original_run_rows(output)
                        self.assertEqual(write.call_count, 1)
                    self.assertEqual(self.rows(host)[1].payload, RUN_BODY)
                    self.assertEqual(store.read(store.namespaced_key('client_run_reference_index', key)).payload,
                                     body.encode())
                else:
                    statuses[2] = -32
                    with self.assertRaises(LocalCoreError):
                        host._commit_original_run_rows(output)
                    self.assertIsNone(self.rows(host)[1])
                    self.assertIsNone(store.read(store.namespaced_key('client_run_reference_index', key)))
                self.assertIs(core._loans[output.ticket], output)
                self.assertIs(host._pending_run_write, output)
                self.assertTrue(host.close())

    def test_original_reference_locator_shape_refuses_before_write(self):
        for locator in ({}, {'key': 'a' * 64, 'body': 'x', 'extra': None},
                        {'key': 'a' * 63, 'body': 'x'}, {'key': 'A' * 64, 'body': 'x'},
                        {'key': 'a' * 64, 'body': ''}, {'key': 'a' * 64, 'body': 'é' * 32769}):
            with self.subTest(locator=locator), TemporaryDirectory(prefix='actql-locator-shape-') as directory:
                host, _, output, _, _, candidate = self.host(Path(directory))
                candidate['reference_locator'] = locator
                with self.assertRaises(ValueError):
                    host._commit_original_run_rows(output)
                self.assertIsNone(self.rows(host)[1])
                self.assertTrue(host.close())

    def host(self, path):
        host, core, calls, _ = append_fixture.LocalSubmissionAppendTests().host(path)
        reference = {'epoch': host.profile()['submissionEpoch'], 'nonce': 'original'}
        preparing = host._retain_intent(reference, append_fixture.INTENT)
        self.assertTrue(host._close_projection(preparing))
        # This tests physical forwarding only. The independent scalar metadata
        # tag is not evidence of real Account/profile/Run admission.
        host._configuration = replace(host._configuration, sdk=True)
        host._runs._configurations[host._configuration.handle] = host._configuration
        source = host._copy(b'{"opaque":"same original row-input loan"}')
        original = core._call
        candidate = {'run_key': RUN_KEY, 'submission_key': append_fixture.REQUEST,
            'preparing': append_fixture.PREPARING.decode(), 'run': RUN_BODY.decode(),
            'submitted': READY.decode(), 'issued_revision': '0', 'issued_body': '1',
            'reference_locator': {'key': '6' * 64, 'body': '{"opaque":"same original locator DATA"}'}}
        validations = []
        statuses = {}
        output_handle = []

        def call(family, name, *args):
            if family == 'material':
                calls.append((family, name, args))
                if name == 'reserve_submitted_rows':
                    handle = 100 + args[3]
                    output_handle.append(handle)
                    return handle
                if name == 'validate_submitted_rows':
                    callbacks = core._journal_callbacks(host._configuration.current.ticket)
                    self.assertIsNotNone(callbacks.reader)
                    self.assertEqual(callbacks.check_current(), 0)
                    seen = []
                    callbacks.reader.read('client_run_custody', 'issued', lambda row: seen.append(row))
                    callbacks.reader.read('client_submitted_intents', append_fixture.REQUEST, lambda row: seen.append(row))
                    self.assertEqual(seen[0][1].payload, b'0')
                    self.assertEqual(seen[1][1].payload, append_fixture.PREPARING)
                    validations.append(args[0])
                    failure = statuses.get(len(validations))
                    if isinstance(failure, BaseException):
                        raise failure
                    return failure if failure is not None else 0
                if name == 'length':
                    return len(json.dumps(candidate, ensure_ascii=False).encode())
                if name == 'produce':
                    self.assertIsNotNone(core._journal_callbacks(host._configuration.current.ticket).reader)
                    return 0
                if name in ('close', 'retire_output'):
                    return core._cleanup(args[0] - 100)
            if family == 'buffer' and name == 'byte' and args[0] in output_handle:
                return json.dumps(candidate, ensure_ascii=False).encode()[args[1]]
            return original(family, name, *args)
        core._call = original_byte_fixture_port(call)
        output = core.reserve_submitted_run_rows(7, host._configuration.handle, source, cleanup=lambda: True)
        host._row_outputs.append(output)
        self.addCleanup(host.close)
        return host, core, output, validations, statuses, candidate

    def rows(self, host):
        store = host._installation._store
        return tuple(store.read(store.namespaced_key(namespace, key)) for namespace, key in (
            ('client_run_custody', 'issued'), ('client_runs', RUN_KEY),
            ('client_submitted_intents', append_fixture.REQUEST)))

    def test_core_candidate_ready_writes_commit_in_one_original_transaction(self):
        with TemporaryDirectory(prefix='actql-finite-run-') as directory:
            host, core, output, validations, _, _ = self.host(Path(directory))
            host._commit_original_run_rows(output)
            count, run, submitted = self.rows(host)
            self.assertEqual((count.payload, count.generation), (b'1', 1))
            self.assertEqual((run.payload, run.generation), (RUN_BODY, 0))
            self.assertEqual((submitted.payload, submitted.generation), (READY, 1))
            self.assertGreaterEqual(len(validations), 2)
            self.assertIs(core._loans[output.ticket], output)
            self.assertFalse(host._journal_outputs)  # no saved admission inferred here
            self.assertTrue(host.close())

    def test_commit_reply_loss_retains_same_loans_and_does_not_retry(self):
        with TemporaryDirectory(prefix='actql-finite-run-') as directory:
            host, core, output, _, _, _ = self.host(Path(directory))
            store = host._installation._store
            write = store.compare_exchange_many_inspected
            attempts = []
            def lose(*args, **kwargs):
                attempts.append(write(*args, **kwargs))
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=lose):
                with self.assertRaises(LocalStorageCommitUnknown):
                    host._commit_original_run_rows(output)
            self.assertEqual(len(attempts), 1)
            self.assertEqual(self.rows(host)[1].payload, RUN_BODY)
            self.assertIs(core._loans[output.ticket], output)
            self.assertIn(output, host._row_outputs)
            self.assertFalse(host._journal_outputs)

    def test_same_transaction_core_refusal_rolls_back_all_ready_writes(self):
        with TemporaryDirectory(prefix='actql-finite-run-') as directory:
            host, core, output, validations, statuses, _ = self.host(Path(directory))
            statuses[2] = -32
            with self.assertRaises(LocalCoreError) as failure:
                host._commit_original_run_rows(output)
            self.assertEqual(failure.exception.code, -32)
            count, run, submitted = self.rows(host)
            self.assertEqual((count.payload, count.generation), (b'0', 0))
            self.assertIsNone(run)
            self.assertEqual((submitted.payload, submitted.generation), (append_fixture.PREPARING, 0))
            self.assertEqual(len(validations), 2)
            self.assertIs(core._loans[output.ticket], output)

    def test_query_failure_is_not_missing_or_permission_to_insert(self):
        with TemporaryDirectory(prefix='actql-finite-run-') as directory:
            host, core, output, _, statuses, _ = self.host(Path(directory))
            statuses[1] = LocalStorageError('Original SQLite query failed')
            with self.assertRaisesRegex(LocalStorageError, 'query failed'):
                host._commit_original_run_rows(output)
            self.assertIsNone(self.rows(host)[1])
            self.assertIs(core._loans[output.ticket], output)

    def test_cached_transport_still_requires_current_and_core_validation(self):
        with TemporaryDirectory(prefix='actql-finite-run-') as directory:
            host, core, output, validations, statuses, _ = self.host(Path(directory))
            binding = host._installation.binding
            binding.inspect(lambda current: core.read_submitted_run_rows(output, current))
            self.assertTrue(core._inputs[output.ticket].payload)
            statuses[2] = -41
            with self.assertRaises(LocalCoreError) as failure:
                binding.inspect(lambda current: core.read_submitted_run_rows(output, current))
            self.assertEqual(failure.exception.code, -41)
            self.assertEqual(len(validations), 2)
            self.assertIsNone(self.rows(host)[1])
            with self.assertRaises(ValueError):
                core.read_submitted_run_rows(output, binding._current)

    def test_extra_field_and_invalid_generation_refuse_without_a_write(self):
        for change in ({'extra': 'not accepted'}, {'issued_revision': '01'}, {'issued_revision': '-1'},
                       {'issued_revision': '9223372036854775808'}):
            with TemporaryDirectory(prefix='actql-finite-run-') as directory:
                host, _, output, _, _, candidate = self.host(Path(directory))
                candidate.update(change)
                with self.assertRaises(ValueError):
                    host._commit_original_run_rows(output)
                self.assertIsNone(self.rows(host)[1])
                self.assertTrue(host.close())

    def test_same_write_invocation_cannot_replay_after_lost_ack(self):
        with TemporaryDirectory(prefix='actql-finite-run-') as directory:
            host, core, output, _, _, _ = self.host(Path(directory))
            store = host._installation._store
            with patch.object(store, 'compare_exchange_many_inspected',
                              side_effect=LocalStorageCommitUnknown(store)) as write:
                with self.assertRaises(LocalStorageCommitUnknown):
                    host._commit_original_run_rows(output)
                with self.assertRaisesRegex(LocalStorageError, 'transport replay'):
                    host._commit_original_run_rows(output)
                self.assertEqual(write.call_count, 1)
            self.assertIs(host._pending_run_write, output)
            self.assertIs(core._loans[output.ticket], output)
            with self.assertRaisesRegex(LocalStorageError, 'new acceptance'):
                host._accept_original({}, append_fixture.INTENT, run_id='must-not-start')
            self.assertIsNone(self.rows(host)[1])
            self.assertTrue(host.close())


class FiniteRunAssemblyTests(unittest.TestCase):
    host = FiniteRunSQLiteTests.host
    rows = FiniteRunSQLiteTests.rows
    # Inherited physical cases are selected separately; this class adds only
    # the complete assembly caller over the same scalar Core and actual Store.
    def assembly(self, path, *, restored=False):
        host, core, output, validations, statuses, candidate = self.host(path)
        previous = core._call
        journal_tickets = {}
        events = []
        admission = b'{"ref":{"namespaceId":"local","authorityScopeCid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","runDefinitionCid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"durability":"durable","revision":0}'
        def call(family, name, *args):
            if family == 'program':
                events.append((family, name))
                if name == 'install_environment': return 600000
                if name == 'reserve_preparation': return 700000 + args[1]
                if name in ('prepare', 'close_environment', 'close_preparation'): return 0
                if name in ('prepared_tasks', 'prepared_results'): return 1
            if family == 'run' and name in ('reserve', 'prepare_sdk', 'prepared', 'close'):
                events.append((family, name))
                if name == 'reserve': return 800000 + args[2]
                if name == 'prepare_sdk': return 2 if restored else 0
                return 0
            if family == 'journal':
                events.append((family, name))
                if name == 'reserve':
                    handle = 900000 + args[2]
                    journal_tickets[handle] = args[2]
                    return handle
                if name in ('inspect', 'admission_length'):
                    callbacks = core._journal_callbacks(journal_tickets[args[0]])
                    self.assertIsNotNone(callbacks.reader)
                    seen = []
                    callbacks.reader.read('client_runs', RUN_KEY, lambda row: seen.append(row))
                    callbacks.reader.read('client_submitted_intents', append_fixture.REQUEST,
                                          lambda row: seen.append(row))
                    self.assertEqual(seen[0][1].payload, RUN_BODY)
                    self.assertEqual(seen[1][1].payload, READY)
                    return len(admission) if name == 'admission_length' else 0
                if name == 'close': return core._cleanup(journal_tickets[args[0]])
            if family == 'submission' and name == 'retire_output':
                return core._cleanup(args[0] - 100)
            if family == 'buffer' and name == 'byte' and args[0] in journal_tickets:
                return admission[args[1]]
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        return host, core, events, admission

    def test_preparation_write_and_saved_admission_use_same_original_assembly(self):
        with TemporaryDirectory(prefix='actql-finite-assembly-') as directory:
            host, core, events, admission = self.assembly(Path(directory))
            reference = {'epoch': host.profile()['submissionEpoch'], 'nonce': 'original'}
            run, saved = host._accept_original(reference, append_fixture.INTENT, run_id='original-run')
            self.assertEqual(saved, admission)
            self.assertIs(host._run_loans[0], run)
            self.assertIs(host._runs._runs[run.handle], run)
            self.assertEqual(events.count(('run', 'prepare_sdk')), 1)
            self.assertEqual(events.count(('journal', 'inspect')), 1)
            self.assertEqual(self.rows(host)[1].payload, RUN_BODY)
            self.assertFalse(any(family in ('source', 'compute', 'publication') for family, _ in events))
            self.assertTrue(host.close())
            self.assertTrue(core._closed)

    def test_existing_ready_decision_never_reaches_fresh_write_or_admission(self):
        with TemporaryDirectory(prefix='actql-finite-assembly-') as directory:
            host, _, events, _ = self.assembly(Path(directory), restored=True)
            reference = {'epoch': host.profile()['submissionEpoch'], 'nonce': 'original'}
            with self.assertRaises(LocalCoreError) as failure:
                host._accept_original(reference, append_fixture.INTENT, run_id='must-not-replace')
            self.assertEqual(failure.exception.operation, 'original_run_restore_required')
            self.assertIsNone(self.rows(host)[1])
            self.assertEqual(len(host._run_loans), 1)
            self.assertFalse(any(family == 'journal' for family, _ in events))
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
