"""Real SQLite append faults with scalar Core; not Wasm or public Run evidence."""
import copy
import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_product import InstalledLocalHost
from actql_sdk._local_storage import LocalStorageCommitUnknown, LocalStorageError
from actql_sdk._local_submission import LocalSubmissionIdentityError
import test_local_product as product_fixture

REQUEST = 'sha256:' + 'c' * 64
INTENT = b'{"kind":"aql","input":{"format":"sql","text":"/*\xf0\x9f\x98\x80*/\\r\\nSELECT 1 AS n"},"parameters":{"e\xcc\x81/~":null}}'
PREPARING = b'{"opaque":"original preparing transport e\xcc\x81/~","null":null}'


class LocalSubmissionAppendTests(unittest.TestCase):
    def host(self, path):
        core, calls, statuses, _ = product_fixture.LocalProductAssemblyTests().core()
        base = core._call
        projections, outputs, plans = {}, {}, {}
        counters = {'append_produce': 0, 'append_validate': 0}

        def current():
            output = host._installation.binding._current
            callbacks = core._journal_callbacks(output.ticket)
            self.assertIsNotNone(callbacks.reader)
            self.assertEqual(callbacks.check_current(), 0)
            return callbacks.reader

        def read_count():
            values = []
            current().read('client_submitted_intent_custody', 'issued',
                           lambda row: values.append(row))
            self.assertEqual(len(values), 1)
            return values[0]

        def call(family, name, *args):
            if family == 'submission' and name == 'reserve':
                projections[100 + args[3]] = (args[1], args[2])
                if args[2] in (3, 4):
                    calls.append((family, name, args))
                    return 100 + args[3]
            if family == 'submission' and name == 'produce' and projections[args[0]][1] in (2, 3, 4):
                calls.append((family, name, args))
                source, kind = projections[args[0]]
                fields = json.loads(core._inputs[source - 100].payload)
                if kind == 2:
                    body = json.dumps({'version': 'actql-submission-epoch/0.1',
                        **{key: fields[key] for key in ('authority_scope_cid', 'epoch_nonce', 'not_before', 'expires_at')}},
                        separators=(',', ':')).encode()
                    outputs[args[0]] = json.dumps({'epoch_wire': body.decode(),
                        'epoch_cid': 'sha256:' + hashlib.sha256(body).hexdigest(),
                        'request_id': REQUEST, 'validity': 'admissible'}).encode()
                elif kind == 4:
                    # Explicit scalar lookup port for the public first-admission
                    # caller. No Core execution or original readiness is claimed.
                    read_count()
                    rows = []
                    current().read('client_submitted_intents', REQUEST, lambda row: rows.append(row))
                    if rows[0] is None:
                        outputs[args[0]] = b'{"kind":"missing"}'
                    else:
                        self.assertEqual(rows[0][1].payload, PREPARING)
                        original = json.loads(INTENT)
                        preimage = json.dumps({'intent': original, 'version': 'actql-submitted-intent/0.1'},
                            ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
                        outputs[args[0]] = json.dumps({'kind': 'preparing',
                            'intentCid': 'sha256:' + hashlib.sha256(preimage).hexdigest()}).encode()
                else:
                    counters['append_produce'] += 1
                    self.assertEqual(fields['intent'].encode(), INTENT)
                    count = read_count()
                    rows = []
                    current().read('client_submitted_intents', REQUEST, lambda row: rows.append(row))
                    if rows[0] is None:
                        self.assertEqual(count[1].payload, b'0')
                        plans[args[0]] = 'append'
                        outputs[args[0]] = json.dumps({'kind': 'append', 'key': REQUEST,
                            'body': PREPARING.decode(), 'issued_revision': str(count[1].generation),
                            'issued_body': '1'}, ensure_ascii=False).encode()
                    else:
                        self.assertEqual(count[1].payload, b'1')
                        plans[args[0]] = 'retained'
                        outputs[args[0]] = json.dumps({'kind': 'retained', 'key': REQUEST,
                            'body': rows[0][1].payload.decode(), 'revision': str(rows[0][1].generation)},
                            ensure_ascii=False).encode()
                return 0
            if family == 'submission' and name == 'validate_append':
                if projections[args[0]][1] == 4:
                    current()
                    return 0
                calls.append((family, name, args))
                counters['append_validate'] += 1
                self.assertEqual(args[1], host._installation.binding._current.handle)
                count = read_count()
                expected = b'0' if plans[args[0]] == 'append' else b'1'
                generation = 0 if plans[args[0]] == 'append' else 1
                return 0 if count[1].payload == expected and count[1].generation == generation else -32
            if name == 'length' and args[0] in outputs:
                return len(outputs[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][args[1]]
            return base(family, name, *args)

        core._call = call
        host = InstalledLocalHost(core, path, now=lambda: 0, observed_at='2026-10-12T00:00:00.000Z')
        self.addCleanup(host.close)
        return host, core, calls, counters

    def reference(self, host):
        return {'epoch': host.profile()['submissionEpoch'], 'nonce': 'original'}

    def assert_rows(self, host, count=b'1', preparing=PREPARING):
        store = host._installation._store
        self.assertEqual(store.read(store.namespaced_key('client_submitted_intent_custody', 'issued')).payload, count)
        row = store.read(store.namespaced_key('client_submitted_intents', REQUEST))
        self.assertEqual(row.payload if row is not None else None, preparing)

    def test_counter_and_original_intent_commit_together_after_same_snapshot_core_reinspection(self):
        with TemporaryDirectory(prefix='actql-append-') as directory:
            host, core, calls, counts = self.host(Path(directory))
            output = host._retain_intent(self.reference(host), INTENT)
            self.assert_rows(host)
            self.assertEqual(output.family, 'submission_append')
            self.assertIs(core._loans[output.ticket], output)
            self.assertEqual(counts['append_produce'], 1)
            self.assertGreaterEqual(counts['append_validate'], 4)
            self.assertFalse(any(family in ('program', 'compute', 'publication') for family, _, _ in calls))
            self.assertTrue(host.close())

    def test_commit_after_reply_loss_keeps_original_rows_and_loans_without_repeating_write(self):
        with TemporaryDirectory(prefix='actql-append-') as directory:
            host, core, _, counts = self.host(Path(directory))
            ref = self.reference(host)
            store = host._installation._store
            original = store.compare_exchange_many_inspected
            commits = []
            def lose(*args, **kwargs):
                result = original(*args, **kwargs)
                commits.append(result)
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=lose):
                with self.assertRaises(LocalStorageCommitUnknown) as raised:
                    host._retain_intent(ref, INTENT)
            self.assertIs(raised.exception.cleanup_store, store)
            self.assertEqual(len(commits), 1)
            self.assert_rows(host)
            output = host._projections[-1]
            self.assertEqual(output.family, 'submission_append')
            self.assertIs(core._loans[output.ticket], output)
            self.assertEqual(counts['append_produce'], 1)
            self.assertTrue(host.close())

    def test_core_candidate_change_inside_write_transaction_rolls_back_without_run(self):
        with TemporaryDirectory(prefix='actql-append-') as directory:
            host, core, _, _ = self.host(Path(directory))
            ref = self.reference(host)
            original = core.validate_submission_append
            attempts = []
            def refuse(output, current):
                attempts.append(output)
                # The fourth inspection is the fresh physical write frame.
                if len(attempts) == 4:
                    raise LocalCoreError('validate_submission_append', -32)
                return original(output, current)
            with patch.object(core, 'validate_submission_append', side_effect=refuse):
                with self.assertRaises(LocalCoreError):
                    host._retain_intent(ref, INTENT)
            self.assert_rows(host, count=b'0', preparing=None)
            self.assertEqual(len(attempts), 4)
            self.assertTrue(host.close())

    def test_physical_write_conflict_is_not_acceptance_and_does_not_retry(self):
        with TemporaryDirectory(prefix='actql-append-') as directory:
            host, _, _, _ = self.host(Path(directory))
            store = host._installation._store
            with patch.object(store, 'compare_exchange_many_inspected', return_value=None) as write:
                with self.assertRaisesRegex(LocalStorageError, 'lookup is required'):
                    host._retain_intent(self.reference(host), INTENT)
                self.assertEqual(write.call_count, 1)
            self.assert_rows(host, count=b'0', preparing=None)
            self.assertTrue(host.close())

    def test_wrong_epoch_authenticator_is_rejected_before_candidate_or_write(self):
        with TemporaryDirectory(prefix='actql-append-') as directory:
            host, _, _, counts = self.host(Path(directory))
            reference = self.reference(host)
            reference['epoch']['authenticator'] = '0' * 64
            with self.assertRaisesRegex(LocalSubmissionIdentityError, 'authentication failed'):
                host._retain_intent(reference, INTENT)
            self.assertEqual(counts['append_produce'], 0)
            self.assert_rows(host, count=b'0', preparing=None)
            self.assertTrue(host.close())

    def test_cached_candidate_requires_current_transaction_and_cannot_be_reused_after_commit(self):
        with TemporaryDirectory(prefix='actql-append-') as directory:
            host, core, _, _ = self.host(Path(directory))
            output = host._retain_intent(self.reference(host), INTENT)
            current = host._installation.binding._current
            before = output
            with self.assertRaises(ValueError):
                core.read_submission_append(output, current)
            with self.assertRaises(LocalCoreError):
                host._installation.binding.inspect(lambda active: core.read_submission_append(output, active))
            with self.assertRaises(ValueError):
                core.close_submission_append(copy.copy(output))
            self.assertIs(core._loans[before.ticket], before)
            self.assertTrue(host.close())

    def test_explicit_lookup_of_retained_original_does_not_write_or_reissue(self):
        with TemporaryDirectory(prefix='actql-append-') as directory:
            host, _, _, counts = self.host(Path(directory))
            reference = self.reference(host)
            first = host._retain_intent(reference, INTENT)
            store = host._installation._store
            with patch.object(store, 'compare_exchange_many_inspected',
                              side_effect=AssertionError('Original intent was resent')):
                second = host._retain_intent(reference, INTENT)
            self.assertIsNot(first, second)
            self.assert_rows(host)
            self.assertEqual(counts['append_produce'], 2)
            self.assertTrue(host.close())

    def test_append_cleanup_failure_keeps_original_output_and_source_for_same_handle_retry(self):
        with TemporaryDirectory(prefix='actql-append-') as directory:
            host, core, calls, _ = self.host(Path(directory))
            output = host._retain_intent(self.reference(host), INTENT)
            original = core.close_submission_append
            with patch.object(core, 'close_submission_append', return_value=False) as close:
                self.assertFalse(host.close())
                close.assert_called_once_with(output)
            self.assertIs(core._loans[output.ticket], output)
            self.assertIs(host._projections[-1], output)
            self.assertIsNotNone(host._installation)
            with patch.object(core, 'close_submission_append', wraps=original) as close:
                self.assertTrue(host.close())
                close.assert_called_once_with(output)
            self.assertFalse(any(family == 'run' and name in ('cancel', 'prepare') for family, name, _ in calls))


if __name__ == '__main__':
    unittest.main()
