"""Real same-Store CAS with scalar Core, not physical Wasm/start admission."""
import copy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_storage import LocalStorageCommitUnknown, LocalStorageError
import test_local_finite_run as fixture
import test_local_submission_append as append_fixture

BINDING = b'{"opaque":"original Core publication binding e\xcc\x81/~","null":null}'
DISPATCH = b'{"opaque":"original Core dispatch e\xcc\x81/~","null":null}'
CLAIM = b'{"opaque":"original Core physical claim e\xcc\x81/~","null":null}'


class SDKStartAssemblyTests(unittest.TestCase):
    def host(self, path):
        host, core, _, _ = fixture.FiniteRunAssemblyTests().assembly(path)
        reference = {'epoch': host.profile()['submissionEpoch'], 'nonce': 'original'}
        run, _ = host._accept_original(reference, append_fixture.INTENT, run_id='original-run')
        self.addCleanup(host.close)
        previous = core._call
        kinds, candidates = {}, {}
        events = []
        failures = {}
        def actual():
            reader = core._journal_callbacks(host._configuration.current.ticket).reader
            self.assertIsNotNone(reader)
            values = []
            reader.read('client_runs', fixture.RUN_KEY, lambda row: values.append(row))
            self.assertEqual(len(values), 1)
            return values[0][1]
        def call(family, name, *args):
            if family == 'material' and name == 'reserve':
                self.assertEqual(args[0], run.handle)
                self.assertIn(args[1], (9, 5, 7, 8))
                handle = 100 + args[2]
                kinds[handle] = args[1]
                return handle
            if family == 'material' and args[0] in kinds:
                handle = args[0]
                kind = kinds[handle]
                before, after, revision = ((fixture.RUN_BODY, BINDING, 0) if kind == 9 else
                    (BINDING, DISPATCH, 1) if kind == 7 else (DISPATCH, CLAIM, 2))
                events.append((kind, name))
                code = failures.get((kind, name))
                if isinstance(code, BaseException): raise code
                if code is not None: return code
                if kind == 5:
                    if name == 'produce':
                        self.assertEqual((actual().payload, actual().generation), (BINDING, 1))
                        return 0
                    if name == 'close': return core._cleanup(handle - 100)
                    raise AssertionError((kind, name))
                if name == 'produce':
                    row = actual()
                    self.assertEqual((row.payload, row.generation), (before, revision))
                    candidates[handle] = json.dumps({'kind': 'publication' if kind == 9 else 'dispatch' if kind == 7 else 'claim',
                        'key': fixture.RUN_KEY, 'revision': str(revision), 'body': after.decode()},
                        ensure_ascii=False).encode()
                    return 0
                if name in ('validate_sdk_start', 'validate_sdk_publication'):
                    row = actual()
                    return 0 if (row.payload, row.generation) == (before, revision) else -35
                if name in ('confirm_sdk_start', 'confirm_sdk_publication'):
                    row = actual()
                    return 0 if (row.payload, row.generation) == (after, revision + 1) else -35
                if name == 'length': return len(candidates[handle])
                if name in ('retire_output', 'close'): return core._cleanup(handle - 100)
            if family == 'buffer' and name == 'byte' and args[0] in candidates:
                return candidates[args[0]][args[1]]
            if family == 'run' and name in ('reserve_sdk_physical_start', 'confirm_physical_start',
                                            'physical_start_ready', 'close_physical_start'):
                events.append(('run', name))
                if name != 'close_physical_start':
                    self.assertEqual((actual().payload, actual().generation), (CLAIM, 3))
                if name == 'reserve_sdk_physical_start': return 1500000
                return 0
            if family == 'compute' and name in ('reserve_source_free', 'configure_source_free', 'configured', 'close'):
                events.append(('compute', name))
                if name == 'reserve_source_free': return 1600000
                return 0
            return previous(family, name, *args)
        core._call = call
        return host, core, run, events, failures

    def row(self, host):
        store = host._installation._store
        return store.read(store.namespaced_key('client_runs', fixture.RUN_KEY))

    def test_original_dispatch_and_claim_are_saved_before_compute_configuration(self):
        with TemporaryDirectory(prefix='actql-sdk-start-') as directory:
            host, core, run, events, _ = self.host(Path(directory))
            compute = host._configure_original_compute(run)
            self.assertEqual((self.row(host).payload, self.row(host).generation), (CLAIM, 3))
            self.assertEqual(events.count((7, 'confirm_sdk_start')), 1)
            self.assertEqual(events.count((8, 'confirm_sdk_start')), 1)
            self.assertIs(compute.start.run, run)
            self.assertIs(compute.start.input, run.input)
            self.assertIs(host._source_free_computes[0], compute)
            self.assertLess(events.index((8, 'confirm_sdk_start')), events.index(('run', 'reserve_sdk_physical_start')))
            self.assertLess(events.index(('run', 'physical_start_ready')), events.index(('compute', 'configure_source_free')))
            self.assertFalse(any(name in ('advance', 'prepare_invocation', 'start_task') for _, name in events))
            # Both consumed outputs are gone physically; original Core loans
            # stay reachable until the same Compute/start/material cleanup.
            self.assertNotIn(host._step_outputs[0].ticket, core._inputs)
            self.assertIs(core._loans[host._step_outputs[0].ticket], host._step_outputs[0])
            self.assertTrue(host.close())

    def test_original_normalization_is_produced_and_retired_before_dispatch(self):
        with TemporaryDirectory(prefix='actql-sdk-normalization-') as directory:
            host, _, run, events, _ = self.host(Path(directory))
            host._configure_original_compute(run)
            self.assertEqual(events.count((5, 'produce')), 1)
            self.assertEqual(events.count((5, 'close')), 1)
            self.assertLess(events.index((9, 'confirm_sdk_publication')), events.index((5, 'produce')))
            self.assertLess(events.index((5, 'close')), events.index((7, 'produce')))
            self.assertFalse(any(name in ('validate_sdk_start', 'confirm_sdk_start')
                                 for kind, name in events if kind == 5))
            self.assertTrue(host.close())

    def test_original_normalization_failure_keeps_same_loan_without_dispatch(self):
        with TemporaryDirectory(prefix='actql-sdk-normalization-') as directory:
            host, core, run, events, failures = self.host(Path(directory))
            failures[5, 'produce'] = -34
            with self.assertRaises(LocalCoreError): host._configure_original_compute(run)
            output = host._step_outputs[0]
            self.assertIs(core._loans[output.ticket], output)
            self.assertEqual(events.count((5, 'produce')), 1)
            self.assertFalse(any(kind in (7, 8, 'run', 'compute') for kind, _ in events))
            self.assertEqual((self.row(host).payload, self.row(host).generation), (BINDING, 1))
            self.assertTrue(host.close())

    def test_normalization_transport_pending_keeps_same_cleanup_before_dispatch(self):
        with TemporaryDirectory(prefix='actql-sdk-normalization-') as directory:
            host, core, run, events, failures = self.host(Path(directory))
            failures[5, 'close'] = -9
            from actql_sdk._local_product import LocalProductCleanupPending
            with self.assertRaises(LocalProductCleanupPending): host._configure_original_compute(run)
            output = host._step_outputs[0]
            self.assertIs(core._loans[output.ticket], output)
            self.assertFalse(host.close())
            self.assertIs(host._step_outputs[0], output)
            self.assertFalse(any(kind in (7, 8, 'run', 'compute') for kind, _ in events))
            del failures[5, 'close']
            self.assertTrue(host.close())
            self.assertEqual(events.count((5, 'produce')), 1)

    def test_dispatch_commit_reply_loss_keeps_original_step_and_prevents_claim(self):
        with TemporaryDirectory(prefix='actql-sdk-start-') as directory:
            host, core, run, events, _ = self.host(Path(directory))
            store = host._installation._store
            write = store.compare_exchange_many_inspected
            attempts = []
            def lose(*args, **kwargs):
                result = write(*args, **kwargs)
                if self.row(host).payload == BINDING: return result
                attempts.append(result)
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=lose):
                with self.assertRaises(LocalStorageCommitUnknown): host._configure_original_compute(run)
                with self.assertRaisesRegex(LocalStorageError, 'new Compute'):
                    host._configure_original_compute(run)
            self.assertEqual(len(attempts), 1)
            self.assertEqual(self.row(host).payload, DISPATCH)
            self.assertEqual(len(host._step_outputs), 1)
            self.assertIs(core._loans[host._pending_start_write.ticket], host._pending_start_write)
            self.assertFalse(any(kind in (8, 'run', 'compute') for kind, _ in events))

    def test_saved_claim_must_be_confirmed_before_start_or_compute(self):
        with TemporaryDirectory(prefix='actql-sdk-start-') as directory:
            host, core, run, events, failures = self.host(Path(directory))
            failures[8, 'confirm_sdk_start'] = -41
            with self.assertRaises(LocalCoreError) as failure: host._configure_original_compute(run)
            self.assertEqual(failure.exception.code, -41)
            self.assertEqual(self.row(host).payload, CLAIM)
            self.assertIs(core._loans[host._pending_start_write.ticket], host._pending_start_write)
            self.assertFalse(any(kind in ('run', 'compute') for kind, _ in events))

    def test_changed_current_rejects_before_dispatch_write(self):
        with TemporaryDirectory(prefix='actql-sdk-start-') as directory:
            host, _, run, events, failures = self.host(Path(directory))
            failures[7, 'validate_sdk_start'] = -32
            with self.assertRaises(LocalCoreError): host._configure_original_compute(run)
            self.assertEqual(self.row(host).payload, BINDING)
            self.assertFalse(any(name == 'confirm_sdk_start' for _, name in events))

    def test_foreign_run_copy_refuses_before_any_new_projection(self):
        with TemporaryDirectory(prefix='actql-sdk-start-') as directory:
            host, _, run, events, _ = self.host(Path(directory))
            before = len(events)
            with self.assertRaises(ValueError): host._configure_original_compute(copy.copy(run))
            self.assertEqual(len(events), before)

    def test_retirement_failure_retains_same_claim_and_blocks_parent_cleanup(self):
        with TemporaryDirectory(prefix='actql-sdk-start-') as directory:
            host, core, run, _, failures = self.host(Path(directory))
            failures[8, 'retire_output'] = -9
            from actql_sdk._local_product import LocalProductCleanupPending
            with self.assertRaises(LocalProductCleanupPending): host._configure_original_compute(run)
            claim = host._step_outputs[0]
            self.assertIn(claim.ticket, core._inputs)
            self.assertIs(core._loans[claim.ticket], claim)
            self.assertEqual(len(host._physical_starts), 1)
            self.assertFalse(host._source_free_computes)
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
