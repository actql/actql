"""Actual transaction loans and scalar bridge custody; not actual Wasm admission."""
from local_abi_declaration_fixture import assert_current_local_abi
import copy
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import RLock
import unittest

from actql_sdk._local_core import (
    LocalCore, LocalCoreError, _Input, _PhysicalInput, _CURRENT_SIGNATURES, LOCAL_CORE_ABI,
)
from actql_sdk._local_storage import LocalByteStore, ByteFence, _NamespaceReader


class LocalHostCurrentTests(unittest.TestCase):
    def bridge(self, *, current=lambda: None, cleanup=lambda: True):
        directory = TemporaryDirectory(prefix='actql-current-frame-')
        self.addCleanup(directory.cleanup)
        store = LocalByteStore(Path(directory.name) / 'original.sqlite', max_records=16,
                               max_record_bytes=1024, max_payload_bytes=8192)
        self.addCleanup(store.close)
        store.compare_exchange('epoch', None, b'original-epoch')
        store.compare_exchange(store.namespaced_key('client_local_adoption', 'adoption'), None, b'original-body')
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._inputs = {1: _PhysicalInput(b'original', lambda: True, lambda _: True)}
        core._loans = {}
        core._released = set()
        core._next_ticket = 2
        core._closing = False
        source = _Input(core._identity, 1, 10, 8)
        core._loans[1] = source
        calls, statuses = [], {}
        payload = b'{"authority_scope_cid":"original","account":"e\xcc\x81\\r\\n"}'

        def call(family, name, *args):
            calls.append((family, name, args))
            if name in statuses:
                result = statuses[name]
                if isinstance(result, BaseException):
                    raise result
                return result
            if (family, name) == ('current', 'reserve'):
                self.assertEqual(args[:2], (10, 2))
                self.assertGreaterEqual(args[2], 2 * 262144 + 4096)
                return 20
            if (family, name) == ('current', 'close'):
                return 0 if core._cleanup(2) == 0 else -9
            if family == 'current':
                self.assertIsNotNone(core._journal_callbacks(2).reader)
                return len(payload) if name == 'length' else 0
            if (family, name) == ('buffer', 'byte'):
                return payload[args[1]]
            raise AssertionError('Unexpected execution/adoption/COMMIT call')

        core._call = call
        loan = core.reserve_host_current(source, store=store, current=current, cleanup=cleanup)
        return core, source, loan, store, calls, statuses, payload

    def inside(self, store, action):
        def inspect(reader):
            # Scalar custody tests also exercise the real physical snapshot.
            # This read is not a substitute for the Core singleton validator.
            def check(row):
                self.assertIsNotNone(row)
                self.assertEqual(row[0], 'adoption')
                self.assertEqual(row[1].payload, b'original-body')
            reader.read('client_local_adoption', 'adoption', check)
            action(reader)
        changes = store._connection.total_changes
        store.inspect_namespaces(
            (ByteFence('epoch', 0, b'original-epoch'),),
            inspect=inspect, current=lambda: None)
        self.assertEqual(store._connection.total_changes, changes)

    def test_actual_same_store_reader_bound_only_inside_original_transaction(self):
        core, source, loan, store, calls, _, payload = self.bridge()
        captured = []

        def action(reader):
            captured.append(reader)
            with core.host_current_frame(loan, reader):
                core.bind_host_current(loan)
                core.produce_host_current(loan)
                self.assertEqual(core.read_host_current(loan), payload)
                self.assertEqual(core.read_host_current(loan), payload)
                self.assertIs(core._journal_callbacks(2).reader, reader)
            self.assertIsNone(core._journal_callbacks(2).reader)

        self.assertIsNone(self.inside(store, action))
        self.assertIs(core._loans[1], source)
        self.assertEqual(sum(name == 'length' for _, name, _ in calls), 1)
        with self.assertRaises(ValueError):
            core.validate_host_current(loan)
        with self.assertRaises(ValueError):
            with core.host_current_frame(loan, captured[0]):
                pass
        self.assertIs(core._loans[2], loan)
        self.assertTrue(core.close_host_current(loan))

    def test_copied_foreign_and_nested_frame_refuse_without_core_calls(self):
        core, _, loan, store, calls, _, _ = self.bridge()
        original_count = len(calls)
        with self.assertRaises(ValueError):
            core.bind_host_current(copy.copy(loan))
        foreign = _NamespaceReader(lambda *a: None, lambda *a: None, object(), lambda: None, check_fences=lambda *_: None)
        with self.assertRaises(ValueError):
            with core.host_current_frame(loan, foreign):
                pass
        self.assertEqual(len(calls), original_count)

        def action(reader):
            with core.host_current_frame(loan, reader):
                with self.assertRaises(ValueError):
                    with core.host_current_frame(loan, reader):
                        pass
                self.assertIs(core._journal_callbacks(2).reader, reader)
        self.inside(store, action)
        self.assertTrue(core.close_host_current(loan))

    def test_permission_boolean_is_not_current_and_original_exception_survives(self):
        failure = OSError('original filesystem fence unavailable')
        for supplier, kind in [(lambda: True, ValueError), (lambda: (_ for _ in ()).throw(failure), OSError)]:
            core, _, loan, store, calls, _, _ = self.bridge(current=supplier)
            with self.assertRaises(kind) as caught:
                self.inside(store, lambda reader: self.enter(core, loan, reader))
            if kind is OSError:
                self.assertIs(caught.exception, failure)
            self.assertFalse(any(name == 'bind' for _, name, _ in calls))
            self.assertIsNone(core._journal_callbacks(2).reader)
            self.assertTrue(core.close_host_current(loan))

    @staticmethod
    def enter(core, loan, reader):
        with core.host_current_frame(loan, reader):
            core.bind_host_current(loan)

    def test_core_notadopted_and_queryfailure_do_not_become_scope_or_retry(self):
        for status in (-35, -41, -32):
            core, source, loan, store, calls, statuses, _ = self.bridge()
            statuses['bind'] = status
            with self.assertRaises(LocalCoreError) as failure:
                self.inside(store, lambda reader: self.enter(core, loan, reader))
            self.assertEqual(failure.exception.code, status)
            self.assertIs(core._loans[1], source)
            self.assertIs(core._loans[2], loan)
            self.assertFalse(any(name == 'produce' for _, name, _ in calls))
            self.assertTrue(core.close_host_current(loan))

    def test_cleanup_failure_and_active_frame_retain_same_ticket_and_parent(self):
        ready = [False]
        cleaned = []
        core, source, loan, store, _, _, _ = self.bridge(cleanup=lambda: cleaned.append('same') or ready[0])

        def action(reader):
            with core.host_current_frame(loan, reader):
                self.assertFalse(core.close_host_current(loan))
                self.assertEqual(cleaned, [])
        self.inside(store, action)
        self.assertFalse(core.close_host_current(loan))
        self.assertIs(core._loans[2], loan)
        self.assertIs(core._loans[1], source)
        ready[0] = True
        self.assertTrue(core.close_host_current(loan))
        self.assertEqual(cleaned, ['same', 'same'])
        with self.assertRaises(ValueError):
            core.close_host_current(loan)

    def test_cached_metadata_rechecks_current_before_and_after_return(self):
        core, _, loan, store, calls, statuses, payload = self.bridge()
        def action(reader):
            with core.host_current_frame(loan, reader):
                core.produce_host_current(loan)
                self.assertEqual(core.read_host_current(loan), payload)
                statuses['validate'] = -32
                with self.assertRaises(LocalCoreError):
                    core.read_host_current(loan)
        self.inside(store, action)
        self.assertEqual(sum(name == 'length' for _, name, _ in calls), 1)
        self.assertTrue(core.close_host_current(loan))

    def test_callback_query_cause_is_latched_even_when_caller_catches_it(self):
        core, _, loan, store, _, _, _ = self.bridge()
        failure = OSError('actual query unavailable')
        def action(reader):
            with core.host_current_frame(loan, reader):
                callbacks = core._journal_callbacks(2)
                callbacks._fail(failure)
        with self.assertRaises(OSError) as caught:
            self.inside(store, action)
        self.assertIs(caught.exception, failure)
        self.assertIsNone(core._journal_callbacks(2).reader)
        self.assertTrue(core.close_host_current(loan))

    def test_callback_primary_survives_a_derived_core_failure_from_the_same_frame(self):
        core, source, loan, store, _, _, _ = self.bridge()
        failure = OSError('original physical query refused')
        derived = LocalCoreError('produce_publication_sdk_run_state', -41)
        def action(reader):
            with core.host_current_frame(loan, reader):
                callbacks = core._journal_callbacks(2)
                callbacks._fail(failure)
                raise derived
        with self.assertRaises(OSError) as caught:
            self.inside(store, action)
        self.assertIs(caught.exception, failure)
        self.assertIs(caught.exception.__cause__, derived)
        self.assertIs(core._journal_callbacks(2).failure, failure)
        self.assertIsNone(core._journal_callbacks(2).reader)
        self.assertIs(core._loans[source.ticket], source)
        self.assertIs(core._loans[loan.ticket], loan)
        self.assertTrue(core.close_host_current(loan))

    def test_closed_scalar_loader_and_namespace_revision_width_remain_exact(self):
        assert_current_local_abi(self, LOCAL_CORE_ABI)
        self.assertEqual(_CURRENT_SIGNATURES, {
            'reserve': ('i64 i32 i32 i64', 'i32'), 'bind': ('i64 i32', 'i32'),
            'validate': ('i64 i32', 'i32'), 'produce': ('i64 i32', 'i32'),
            'length': ('i64 i32', 'i32'), 'close': ('i64 i32', 'i32')})


if __name__ == '__main__':
    unittest.main()
