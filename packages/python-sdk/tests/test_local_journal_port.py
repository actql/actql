"""Independent physical transport oracles, not public Run/COMMIT acceptance."""
import copy
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import RLock
import sqlite3
import unittest
from unittest.mock import patch

from actql_sdk._local_core import (
    LocalCore, LocalCoreError, LOCAL_CORE_ABI, _IMPORT_SIGNATURES,
    _JOURNAL_SIGNATURES, _Output, _PhysicalInput,
)
from actql_sdk._local_journal_port import _JournalCallbacks
from actql_sdk._local_storage import LocalByteStore, ByteWrite, ByteFence, StoredBytes, _NamespaceReader
from actql_sdk import _wire as wire
from actql_sdk._values import decode_json
from local_abi_declaration_fixture import assert_current_local_abi, original_byte_fixture_port


def scalar_reader_check(view, required, current):
    """Required checker for neutral scalar readers, never a production factory.

    Synthetic wrappers retain their original delegated physical fence and
    separately owned callback failure; actual Store readers use their own port.
    """
    view.check_fences(view, required)
    if current() is not None:
        raise ValueError('Scalar reader current cannot return permission')


def query(callbacks, mode, namespace, key):
    left, right = namespace.encode(), key.encode()
    status = callbacks.begin(mode, len(left), len(right))
    if status != 0:
        return status
    for ordinal, byte in enumerate(left + right):
        if callbacks.byte(ordinal, byte) != 0:
            return -41
    return callbacks.query()


class LocalJournalPhysicalPortTests(unittest.TestCase):
    def setUp(self):
        self.directory = TemporaryDirectory(prefix='actql-python-journal-port-')
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'original.sqlite'
        self.store = LocalByteStore(self.path, max_records=12,
                                   max_record_bytes=512, max_payload_bytes=4096)
        self.addCleanup(self.store.close)
        self.namespace = 'e\u0301:/~'
        self.key = 'k\x00/~😀'
        self.raw = b'{"e\xcc\x81":"line\\r\\n","nullable":null,"n":1.25}'
        self.record_key = self.store.namespaced_key(self.namespace, self.key)
        self.assertEqual(self.store.compare_exchange('epoch', None, b'original'), 0)
        self.assertEqual(self.store.compare_exchange(self.record_key, None, self.raw), 0)
        self.fences = (ByteFence('epoch', 0, b'original'),)
        self.writes = (ByteWrite('outcome', None, b'original-Core-write'),)
        self.callbacks = _JournalCallbacks(lambda: None, self.store)

    def inside(self, fn):
        def inspect(reader):
            self.callbacks.reader = reader
            try:
                fn()
            finally:
                self.callbacks.reader = None
        return self.store.compare_exchange_many_inspected(
            self.writes, self.fences, inspect=inspect, current=lambda: None)

    def raw_row(self):
        callbacks = self.callbacks
        self.assertEqual(callbacks.length(0), len(self.key.encode()))
        self.assertEqual(callbacks.length(1), len(self.raw))
        return (bytes(callbacks.row_byte(0, i) for i in range(callbacks.length(0))),
                bytes(callbacks.row_byte(1, i) for i in range(callbacks.length(1))),
                callbacks.revision())

    def test_same_store_scan_and_exact_read_preserve_raw_key_body_and_int64(self):
        with sqlite3.connect(self.path) as physical:
            physical.execute('UPDATE core_bytes SET generation=? WHERE key=?',
                             (9007199254740993, self.record_key))
        def consume():
            self.assertEqual(query(self.callbacks, 0, self.namespace, ''), 0)
            self.assertEqual(self.raw_row(), (self.key.encode(), self.raw, 9007199254740993))
            self.assertEqual(self.callbacks.release(), 0)
            self.assertEqual(query(self.callbacks, 1, self.namespace, self.key), 0)
            self.assertEqual(self.raw_row(), (self.key.encode(), self.raw, 9007199254740993))
            self.assertEqual(self.callbacks.release(), 0)
        self.assertEqual(self.inside(consume), (0,))
        self.assertEqual(self.store.read(self.record_key), StoredBytes(9007199254740993, self.raw))

    def test_physical_miss_and_scan_end_do_not_substitute_neighbor_or_composed_namespace(self):
        def consume():
            for mode, namespace, key in [(1, self.namespace, 'missing'),
                                          (0, self.namespace, self.key),
                                          (1, 'é:/~', self.key)]:
                self.assertEqual(query(self.callbacks, mode, namespace, key), 1)
                self.assertEqual(self.callbacks.revision(), -1)
                self.assertEqual(self.callbacks.length(1), -41)
                self.assertEqual(self.callbacks.release(), 0)
        self.assertEqual(self.inside(consume), (0,))

    def test_query_failure_retains_original_exception_never_a_notfound_observation(self):
        class QueryFailure(sqlite3.Connection):
            fail = False
            def execute(self, sql, *args, **kwargs):
                if self.fail and 'ORDER BY key COLLATE BINARY LIMIT 1' in sql:
                    raise sqlite3.OperationalError('original query failure')
                return super().execute(sql, *args, **kwargs)
        self.store.close()
        connect = sqlite3.connect
        with patch('actql_sdk._local_storage.sqlite3.connect',
                   side_effect=lambda *a, **k: connect(*a, **(k | {'factory': QueryFailure}))):
            self.store = LocalByteStore(self.path, max_records=12, max_record_bytes=512, max_payload_bytes=4096)
        self.addCleanup(self.store.close)
        self.store._connection.fail = True
        self.callbacks.store = self.store
        def consume():
            self.assertEqual(query(self.callbacks, 1, self.namespace, self.key), -41)
            self.assertIsInstance(self.callbacks.failure, sqlite3.OperationalError)
            self.assertEqual(self.callbacks.release(), -41)
        with self.assertRaisesRegex(sqlite3.OperationalError, 'original query failure'):
            self.inside(consume)
        self.assertIsNone(self.store.read('outcome'))

    def test_old_reader_and_permission_boolean_are_unavailable_not_current(self):
        saved = []
        def consume():
            saved.append(self.callbacks.reader)
            self.assertEqual(query(self.callbacks, 1, self.namespace, self.key), 0)
            self.assertEqual(self.callbacks.release(), 0)
        self.assertEqual(self.inside(consume), (0,))
        self.callbacks.reader = saved[0]
        self.assertEqual(query(self.callbacks, 1, self.namespace, self.key), -41)
        self.assertIsInstance(self.callbacks.failure, ValueError)
        wrong = _JournalCallbacks(lambda: True, self.store, reader=saved[0])
        self.assertEqual(wrong.check_current(), -41)
        self.assertIsInstance(wrong.failure, ValueError)

    def test_current_failure_keeps_original_cause_before_query_and_after_bad_retry(self):
        original = PermissionError('original epoch or authority unavailable')
        def refuse():
            raise original
        reader = _NamespaceReader(lambda *args: self.fail('Unexpected query'),
                                  lambda *args: self.fail('Unexpected query'), self.store, lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check)
        callbacks = _JournalCallbacks(refuse, self.store, reader=reader)
        self.assertEqual(query(callbacks, 1, self.namespace, self.key), -41)
        self.assertIs(callbacks.failure, original)
        self.assertEqual(callbacks.byte(0, 97), -41)
        self.assertIs(callbacks.failure, original)
        self.assertEqual(callbacks.query(), -41)
        self.assertIs(callbacks.failure, original)

    def test_query_transfer_limits_and_order_refuse_without_io(self):
        reader = _NamespaceReader(lambda *args: self.fail('Unexpected query'),
                                  lambda *args: self.fail('Unexpected query'), self.store, lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check)
        for mode, left, right in [(2, 1, 1), (1, 1, 0), (0, 4097, 1), (0, 1, 4097), (True, 1, 1)]:
            callbacks = _JournalCallbacks(lambda: None, self.store, reader=reader)
            self.assertEqual(callbacks.begin(mode, left, right), -41)
        callbacks = _JournalCallbacks(lambda: None, self.store, reader=reader)
        self.assertEqual(callbacks.begin(1, 1, 1), 0)
        self.assertEqual(callbacks.byte(1, 97), -41)
        self.assertEqual(callbacks.query(), -41)
        incomplete = _JournalCallbacks(lambda: None, self.store, reader=reader)
        self.assertEqual(incomplete.begin(1, 1, 1), 0)
        self.assertEqual(incomplete.query(), -41)

    def test_unreleased_query_copy_cannot_be_overwritten_by_another_query(self):
        def consume():
            self.assertEqual(query(self.callbacks, 1, self.namespace, self.key), 0)
            original = self.callbacks.row
            self.assertEqual(query(self.callbacks, 1, self.namespace, self.key), -41)
            self.assertIs(self.callbacks.row, original)
            self.assertEqual(self.callbacks.release(), -41)
        self.assertEqual(self.inside(consume), (0,))
        self.assertIsNone(self.callbacks.row)

    def test_current_revocation_after_read_keeps_same_row_loan_until_cleanup(self):
        active = [True]
        self.callbacks.current = lambda: None if active[0] else (_ for _ in ()).throw(
            PermissionError('original authority revoked'))
        def consume():
            reader = self.callbacks.reader
            def read(namespace, key, callback):
                reader.read(namespace, key, callback)
                active[0] = False
            self.callbacks.reader = _NamespaceReader(reader.scan_after, read, self.store, reader.current, check_fences=lambda _, required: reader.check_fences(reader, required),
                check_fences_and_current=scalar_reader_check)
            self.assertEqual(query(self.callbacks, 1, self.namespace, self.key), -41)
            self.assertIsInstance(self.callbacks.failure, PermissionError)
            self.assertEqual(self.callbacks.row[1].payload, self.raw)
            self.assertEqual(self.callbacks.length(1), -41)
        self.assertEqual(self.inside(consume), (0,))
        self.assertIsNotNone(self.callbacks.row)
        self.callbacks.release()
        self.assertIsNone(self.callbacks.row)


class LocalJournalBridgeCustodyTests(unittest.TestCase):
    def bridge(self):
        directory = TemporaryDirectory(prefix='actql-python-journal-scalar-')
        self.addCleanup(directory.cleanup)
        self.store = LocalByteStore(Path(directory.name) / 'original.sqlite', max_records=8,
                                    max_record_bytes=512, max_payload_bytes=4096)
        self.addCleanup(self.store.close)
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._inputs = {1: _PhysicalInput(b'', lambda: True, lambda _: True)}
        core._loans = {}
        core._released = set()
        core._next_ticket = 2
        core._closing = False
        material = _Output(core._identity, 1, 7, 1048576, 'material')
        core._loans[1] = material
        calls = []
        code = [0]
        def invoke(family, name, *args):
            calls.append((family, name, args))
            self.assertEqual(family, 'journal')
            if name == 'reserve':
                self.assertEqual(args[:2], (7, 8))
                self.assertGreaterEqual(args[3], 2 * 1048576)
                return 20
            if name == 'inspect':
                callbacks = core._journal_callbacks(2)
                self.assertIsNotNone(callbacks.reader)
                return code[0]
            if name == 'revision':
                return (0, 9, 2)[args[1]]
            if name == 'close':
                return 0 if core._cleanup(2) == 0 else -9
            raise AssertionError('Unexpected call')
        core._call = original_byte_fixture_port(invoke)
        return core, material, calls, code

    def test_same_ticket_retains_callback_input_and_cleanup_failure_for_retry(self):
        core, material, calls, code = self.bridge()
        ready = [False]
        cleaned = []
        loan = core.reserve_journal_observation(material, 8, store=self.store, current=lambda: None,
                                               cleanup=lambda: cleaned.append('close') or ready[0])
        reader = _NamespaceReader(lambda *a: None, lambda *a: None, self.store, lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check)
        core.inspect_journal_observation(loan, reader)
        self.assertIsNone(core._journal_callbacks(2).reader)
        self.assertEqual(core.journal_observation_revisions(loan, reader), (0, 9, 2))
        self.assertFalse(core.close_journal_observation(loan))
        self.assertIs(core._loans[2], loan)
        self.assertIs(core._loans[1], material)
        ready[0] = True
        self.assertTrue(core.close_journal_observation(loan))
        self.assertEqual(cleaned, ['close', 'close'])
        self.assertEqual(core._journal_current(2), -41)
        with self.assertRaises(ValueError):
            core.close_journal_observation(loan)
        self.assertTrue(all(family == 'journal' for family, _, _ in calls))

    def test_foreign_copied_parent_boolean_and_closing_refuse_before_io(self):
        core, material, calls, _ = self.bridge()
        original_store = self.store
        foreign, other, _, _ = self.bridge()
        self.store = original_store
        for action in [lambda: core.reserve_journal_observation(copy.copy(material), 8, store=self.store, current=lambda: None, cleanup=lambda: True),
                       lambda: core.reserve_journal_observation(other, 8, store=self.store, current=lambda: None, cleanup=lambda: True),
                       lambda: core.reserve_journal_observation(material, True, store=self.store, current=lambda: None, cleanup=lambda: True)]:
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(calls, [])
        core._closing = True
        with self.assertRaises(ValueError):
            core.reserve_journal_observation(material, 8, store=self.store, current=lambda: None, cleanup=lambda: True)
        self.assertEqual(calls, [])

    def test_core_refusal_releases_reader_only_not_original_parent_or_ticket(self):
        core, material, calls, code = self.bridge()
        loan = core.reserve_journal_observation(material, 8, store=self.store, current=lambda: None, cleanup=lambda: True)
        code[0] = -42
        reader = _NamespaceReader(lambda *a: None, lambda *a: None, self.store, lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check)
        with self.assertRaises(LocalCoreError) as failed:
            core.inspect_journal_observation(loan, reader)
        self.assertEqual(failed.exception.code, -42)
        self.assertIsNone(core._journal_callbacks(2).reader)
        self.assertIs(core._loans[2], loan)
        self.assertIs(core._loans[1], material)

    def test_original_query_exception_is_returned_without_notfound_or_resend(self):
        core, material, calls, code = self.bridge()
        loan = core.reserve_journal_observation(material, 8, store=self.store, current=lambda: None, cleanup=lambda: True)
        original = OSError('original physical query')
        def invoke(family, name, *args):
            core._journal_callbacks(2).failure = original
            return -41
        core._call = original_byte_fixture_port(invoke)
        with self.assertRaises(OSError) as failed:
            core.inspect_journal_observation(loan, _NamespaceReader(lambda *a: None, lambda *a: None, self.store, lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check))
        self.assertIs(failed.exception, original)
        self.assertIs(core._loans[2], loan)
        self.assertIsNone(core._journal_callbacks(2).reader)

    def test_foreign_store_reader_and_expired_snapshot_refuse_without_core_adoption(self):
        core, material, calls, code = self.bridge()
        original_store = self.store
        loan = core.reserve_journal_observation(material, 8, store=original_store,
                                                current=lambda: None, cleanup=lambda: True)
        temporary = TemporaryDirectory(prefix='actql-python-foreign-journal-')
        self.addCleanup(temporary.cleanup)
        foreign = LocalByteStore(Path(temporary.name) / 'foreign.sqlite', max_records=8,
                                 max_record_bytes=512, max_payload_bytes=4096)
        self.addCleanup(foreign.close)
        reader = _NamespaceReader(lambda *a: None, lambda *a: None, foreign, lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check)
        baseline = len(calls)
        with self.assertRaises(ValueError):
            core.inspect_journal_observation(loan, reader)
        self.assertEqual(len(calls), baseline)
        self.assertIs(core._loans[2], loan)
        captured = []
        def inspect(original):
            captured.append(original)
            original.scan_after('empty', '', lambda row: self.assertIsNone(row))
        self.assertEqual(original_store.compare_exchange_many_inspected(
            (ByteWrite('fixed', None, b'original'),),
            (ByteFence('missing-original', 0, b'none'),),
            inspect=inspect, current=lambda: None), None)
        # Establish an independent actual metadata fence for the empty snapshot.
        self.assertEqual(original_store.compare_exchange('meta', None, b'original'), 0)
        self.assertEqual(original_store.compare_exchange_many_inspected(
            (ByteWrite('fixed', None, b'original'),),
            (ByteFence('meta', 0, b'original'),),
            inspect=inspect, current=lambda: None), (0,))
        callbacks = core._journal_callbacks(2)
        callbacks.reader = captured[0]
        self.assertEqual(callbacks.check_current(), -41)
        self.assertIsInstance(callbacks.failure, ValueError)
        callbacks.reader = None

    def test_private_loader_matches_changed_abi_imports_and_revision_width(self):
        assert_current_local_abi(self, LOCAL_CORE_ABI)
        self.assertEqual(_JOURNAL_SIGNATURES, {
            'reserve': ('i64 i32 i32 i32 i64', 'i32'), 'inspect': ('i64 i32', 'i32'),
            'revision': ('i64 i32 i32', 'i64'), 'admission_length': ('i64 i32', 'i32'), 'close': ('i64 i32', 'i32')})
        self.assertEqual(_IMPORT_SIGNATURES['journal_query_header'],
                         ('i32 i32 i32 i32 i32 i32 i32', 'i32'))
        self.assertEqual(_IMPORT_SIGNATURES['journal_copy_row'], ('i32 i32 i32 i32 i32', 'i32'))
        self.assertNotIn('journal_revision', _IMPORT_SIGNATURES)
        self.assertNotIn('journal_begin', _IMPORT_SIGNATURES)

    def admission_bridge(self):
        core, material, calls, code = self.bridge()
        loan = core.reserve_journal_observation(material, 8, store=self.store,
            current=lambda: None, cleanup=lambda: True)
        # Independent closed public admission, not an actual Core decision.
        raw = (b'{"ref":{"namespaceId":"scope","authorityScopeCid":"sha256:' + b'b' * 64
               + b'","runDefinitionCid":"sha256:' + b'a' * 64
               + b'"},"durability":"durable","revision":0}')
        copied = []
        def invoke(family, name, *args):
            calls.append((family, name, args))
            if family == 'journal' and name == 'admission_length':
                self.assertIsNotNone(core._journal_callbacks(loan.ticket).reader)
                status = core._journal_current(loan.ticket)
                return status if status != 0 else len(raw) if code[0] == 0 else code[0]
            if family == 'buffer' and name == 'byte':
                copied.append(args[1])
                return raw[args[1]]
            raise AssertionError('Unexpected physical/semantic primitive')
        core._call = original_byte_fixture_port(invoke)
        reader = _NamespaceReader(lambda *a: None, lambda *a: None, self.store,
                                  lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check)
        return core, loan, reader, raw, copied, calls, code

    def test_admission_transfer_and_cached_read_both_check_current_snapshot(self):
        core, loan, reader, raw, copied, calls, code = self.admission_bridge()
        self.assertTrue(wire.valid(decode_json(raw), 'admission'))
        self.assertEqual(core.read_journal_admission(loan, reader), raw)
        self.assertEqual(copied, list(range(len(raw))))
        self.assertIsNone(core._journal_callbacks(loan.ticket).reader)
        baseline = len(calls)
        self.assertEqual(core.read_journal_admission(loan, reader), raw)
        self.assertEqual([name for _, name, _ in calls[baseline:]],
                         ['admission_length', 'admission_length'])
        self.assertIs(core._loans[loan.ticket], loan)

    def test_cached_admission_cannot_bypass_core_current_refusal(self):
        core, loan, reader, raw, copied, calls, code = self.admission_bridge()
        self.assertEqual(core.read_journal_admission(loan, reader), raw)
        code[0] = -32
        baseline = len(calls)
        with self.assertRaises(LocalCoreError) as refused:
            core.read_journal_admission(loan, reader)
        self.assertEqual(refused.exception.code, -32)
        self.assertEqual([name for _, name, _ in calls[baseline:]], ['admission_length'])
        self.assertIsNone(core._journal_callbacks(loan.ticket).reader)
        self.assertEqual(core._inputs[loan.ticket].payload, raw)
        self.assertIs(core._loans[loan.ticket], loan)

    def test_admission_physical_failure_preserves_original_exception_and_loans(self):
        core, loan, reader, raw, copied, calls, code = self.admission_bridge()
        original = OSError('Original current snapshot unavailable')
        core._journal_callbacks(loan.ticket).current = lambda: (_ for _ in ()).throw(original)
        with self.assertRaises(OSError) as refused:
            core.read_journal_admission(loan, reader)
        self.assertIs(refused.exception, original)
        self.assertEqual(copied, [])
        self.assertIsNone(core._journal_callbacks(loan.ticket).reader)
        self.assertIs(core._loans[loan.ticket], loan)
        self.assertIn(1, core._loans)

    def test_admission_foreign_loan_reader_and_closing_reject_before_io(self):
        core, loan, reader, raw, copied, calls, code = self.admission_bridge()
        baseline = len(calls)
        other = _NamespaceReader(lambda *a: None, lambda *a: None, object(),
                                 lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check)
        for action in [lambda: core.read_journal_admission(copy.copy(loan), reader),
                       lambda: core.read_journal_admission(loan, other)]:
            with self.assertRaises(ValueError):
                action()
        core._closing = True
        with self.assertRaises(ValueError):
            core.read_journal_admission(loan, reader)
        self.assertEqual(len(calls), baseline)
        self.assertEqual(copied, [])

    def test_current_failure_after_copy_never_returns_admission_or_releases_loan(self):
        core, loan, reader, raw, copied, calls, code = self.admission_bridge()
        original = PermissionError('Original authority changed during transfer')
        invoke = core._call
        lengths = [0]
        def change(family, name, *args):
            if family == 'journal' and name == 'admission_length':
                lengths[0] += 1
                if lengths[0] == 3:
                    core._journal_callbacks(loan.ticket).failure = original
                    return -41
            return invoke(family, name, *args)
        core._call = original_byte_fixture_port(change)
        with self.assertRaises(PermissionError) as refused:
            core.read_journal_admission(loan, reader)
        self.assertIs(refused.exception, original)
        self.assertEqual(copied, list(range(len(raw))))
        self.assertEqual(core._inputs[loan.ticket].payload, raw)
        self.assertIs(core._loans[loan.ticket], loan)
        self.assertIn(1, core._loans)
        self.assertIsNone(core._journal_callbacks(loan.ticket).reader)
