"""Independent two-import row oracles; no Run, admission or latency acceptance."""
from ctypes import POINTER, c_uint8, cast
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import RLock
from types import SimpleNamespace
import sqlite3
import sys
import unittest

import wasmtime

from actql_sdk._local_core import LocalCore, _Output, _PhysicalInput
from actql_sdk._local_journal_port import _JournalCallbacks, _JournalRowTransfer
from actql_sdk._local_storage import ByteFence, LocalByteStore, StoredBytes, _NamespaceReader


class _Memory:
    def __init__(self):
        self.data = (c_uint8 * 327680)()
        self.data[64:69] = b'nskey'
        self.reads, self.writes = [], []

    def data_ptr(self, _):
        return cast(self.data, POINTER(c_uint8))

    def data_len(self, _):
        return len(self.data)

    def read(self, _, start, end):
        self.reads.append((start, end))
        return bytearray(self.data[start:end])

    def write(self, _, payload, offset):
        self.writes.append((offset, len(payload)))
        self.data[offset:offset + len(payload)] = payload
        return len(payload)


class JournalRowTransportTests(unittest.TestCase):
    def fixture(self, row=...):
        if row is ...:
            row = ('key', StoredBytes(9007199254740993, b'payload'))
        core = LocalCore.__new__(LocalCore)
        core._identity, core._store = object(), object()
        core._lock = RLock()
        core._closing = core._closed = core._retired = False
        core._physical_vm_observation = core._platform_vm_original = None
        core._invocation_observation = None
        core._released = set()
        memory, store, queries = _Memory(), object(), []
        callbacks = _JournalCallbacks(lambda: None, store)
        def query(reader, mode, namespace, key, current):
            queries.append((mode, namespace, key))
            current()
            return row
        reader = _NamespaceReader(lambda *a: self.fail('Unexpected scalar scan'),
            lambda *a: self.fail('Unexpected scalar read'), store, lambda: None,
            lambda *a: None, lambda reader, required, current: current(),
            check_frame=lambda reader: None, query_current=query)
        callbacks.reader = reader
        ready = [False]
        def cleanup():
            if not ready[0]:
                return False
            callbacks.release()
            callbacks.reader = None
            return True
        physical = _PhysicalInput(b'', cleanup, lambda _: True, journal=callbacks)
        core._inputs = {7: physical}
        core._loans = {3: object(), 7: _Output(core._identity, 7, 17, 1048576, 'journal')}
        core._exports = {'memory': memory}
        caller = SimpleNamespace(get=lambda name: memory if name == 'memory' else None)
        return core, callbacks, memory, caller, queries, physical, ready

    def header(self, core, caller, **changes):
        args = dict(ticket=7, mode=1, namespace_offset=64, namespace_bytes=2,
                    key_offset=66, key_bytes=3, header_offset=128)
        args.update(changes)
        return core._journal_query_header(caller, **args)

    def copy(self, core, caller, **changes):
        args = dict(ticket=7, key_offset=256, key_bytes=3, body_offset=8192, body_bytes=7)
        args.update(changes)
        return core._journal_copy_row(caller, **args)

    def test_literal_header_preserves_revision_above_double_precision(self):
        core, callbacks, memory, caller, queries, physical, _ = self.fixture()
        self.assertEqual(self.header(core, caller), 0)
        self.assertEqual(bytes(memory.data[128:144]),
                         b'\x03\x00\x00\x00\x07\x00\x00\x00\x01\x00\x00\x00\x00\x00\x20\x00')
        transfer = callbacks.transfer
        self.assertIs(transfer.physical, physical)
        self.assertIs(transfer.memory, memory)
        self.assertIs(transfer.reader, callbacks.reader)
        self.assertIs(transfer.row, callbacks.row)
        self.assertTrue(callbacks.transfer_ready)
        self.assertEqual(self.copy(core, caller), 0)
        self.assertEqual(bytes(memory.data[256:259]), b'key')
        self.assertEqual(bytes(memory.data[8192:8199]), b'payload')
        self.assertEqual(memory.reads, [(64, 66), (66, 69)])
        self.assertEqual(memory.writes, [(128, 16), (256, 3), (8192, 7)])
        self.assertEqual(queries, [(1, 'ns', 'key')])
        self.assertIsNone(callbacks.transfer)
        self.assertIsNone(callbacks.row)
        self.assertFalse(callbacks.queried)
        self.assertIs(core._inputs[7], physical)

    def test_maximum_revision_empty_body_is_a_row_and_performs_no_empty_write(self):
        core, callbacks, memory, caller, queries, _, _ = self.fixture(('key', StoredBytes(9223372036854775807, b'')))
        self.assertEqual(self.header(core, caller), 0)
        self.assertEqual(bytes(memory.data[128:144]),
                         b'\x03\x00\x00\x00\x00\x00\x00\x00\xff\xff\xff\xff\xff\xff\xff\x7f')
        self.assertEqual(self.copy(core, caller, body_bytes=0, body_offset=len(memory.data)), 0)
        self.assertEqual(memory.writes, [(128, 16), (256, 3)])
        self.assertEqual(len(queries), 1)
        self.assertIsNone(callbacks.transfer)

    def test_confirmed_miss_releases_query_but_malformed_row_latches_failure(self):
        core, callbacks, memory, caller, queries, _, _ = self.fixture(None)
        self.assertEqual(self.header(core, caller), 1)
        self.assertFalse(callbacks.queried)
        self.assertIsNone(callbacks.request)
        self.assertEqual(memory.writes, [])
        self.assertEqual(len(queries), 1)
        for row in ([], ('key', StoredBytes(-1, b'')), ('key', StoredBytes(2**63, b'')),
                    ('', StoredBytes(0, b'')), ('key', StoredBytes(0, bytearray()))):
            with self.subTest(row=row):
                core, callbacks, memory, caller, queries, _, _ = self.fixture(row)
                self.assertEqual(self.header(core, caller), -41)
                first = callbacks.failure
                self.assertIsInstance(first, ValueError)
                self.assertEqual(self.header(core, caller), -41)
                self.assertIs(callbacks.failure, first)
                self.assertEqual(len(queries), 1)
                self.assertEqual(memory.writes, [])

    def test_scan_empty_cursor_and_full_bounded_row_have_only_two_imports(self):
        payload = bytes(range(256)) * 1024
        core, callbacks, memory, caller, queries, _, _ = self.fixture(('k' * 4096, StoredBytes(4, payload)))
        self.assertEqual(self.header(core, caller, mode=0, key_bytes=0), 0)
        self.assertEqual(bytes(memory.data[128:136]), b'\x00\x10\x00\x00\x00\x00\x04\x00')
        self.assertEqual(self.copy(core, caller, key_bytes=4096, body_bytes=262144), 0)
        self.assertEqual(bytes(memory.data[256:4352]), b'k' * 4096)
        self.assertEqual(bytes(memory.data[8192:8192 + 262144]), payload)
        self.assertEqual(queries, [(0, 'ns', '')])
        self.assertEqual(memory.reads, [(64, 66)])
        self.assertEqual(memory.writes[2:], [(8192 + index, 16384) for index in range(0, 262144, 16384)])
        self.assertIsNone(callbacks.transfer)

    def test_invalid_query_ranges_and_foreign_or_retired_tickets_never_query(self):
        cases = ({'ticket': 8}, {'ticket': True}, {'mode': 2}, {'namespace_bytes': 0},
                 {'namespace_bytes': 4097}, {'key_bytes': 4097}, {'key_bytes': 0},
                 {'namespace_offset': -1}, {'key_offset': 327679},
                 {'header_offset': 327665}, {'header_offset': 64})
        for changes in cases:
            with self.subTest(changes=changes):
                core, callbacks, memory, caller, queries, _, _ = self.fixture()
                self.assertEqual(self.header(core, caller, **changes), -41)
                self.assertEqual(queries, [])
                self.assertEqual(memory.writes, [])
        core, _, memory, caller, queries, _, _ = self.fixture()
        core._retired = True
        self.assertEqual(self.header(core, caller), -41)
        self.assertEqual(queries, [])
        self.assertEqual(memory.writes, [])

    def test_request_read_failure_cannot_query_or_hide_its_first_cause(self):
        for change in ('short', 'request', 'reader', 'memory', 'trap'):
            with self.subTest(change=change):
                core, callbacks, memory, caller, queries, physical, _ = self.fixture()
                read = memory.read
                original = OSError('request read failed')
                def fail(actual, start, end):
                    raw = read(actual, start, end)
                    if change == 'short':
                        return raw[:-1]
                    if change == 'request':
                        callbacks.request = bytearray(5)
                    elif change == 'reader':
                        callbacks.reader = None
                    elif change == 'memory':
                        core._exports['memory'] = _Memory()
                    else:
                        raise original
                    return raw
                memory.read = fail
                self.assertEqual(self.header(core, caller), -41)
                first = callbacks.failure
                if change == 'trap':
                    self.assertIs(first, original)
                self.assertEqual(self.header(core, caller), -41)
                self.assertIs(callbacks.failure, first)
                self.assertEqual(queries, [])
                self.assertEqual(memory.writes, [])
                self.assertIs(core._inputs[7], physical)

    def test_copy_refuses_changed_identity_without_requery_or_release(self):
        for change in ('memory', 'caller', 'input', 'row', 'reader', 'retired', 'foreign_ticket'):
            with self.subTest(change=change):
                core, callbacks, memory, caller, queries, physical, _ = self.fixture()
                self.assertEqual(self.header(core, caller), 0)
                transfer = callbacks.transfer
                if change == 'memory':
                    core._exports['memory'] = _Memory()
                elif change == 'caller':
                    other = _Memory()
                    caller = SimpleNamespace(get=lambda _: other)
                elif change == 'input':
                    core._inputs[7] = _PhysicalInput(b'', lambda: True, lambda _: True, journal=callbacks)
                elif change == 'row':
                    callbacks.row = (b'key', StoredBytes(9007199254740993, b'changed'))
                elif change == 'reader':
                    callbacks.reader = None
                elif change == 'retired':
                    core._retired = True
                self.assertEqual(self.copy(core, caller, ticket=8 if change == 'foreign_ticket' else 7), -41)
                self.assertIs(callbacks.transfer, transfer)
                self.assertIs(transfer.physical, physical)
                self.assertEqual(transfer.row[1].payload, b'payload')
                self.assertEqual(len(queries), 1)
                self.assertEqual(memory.writes, [(128, 16)])

    def test_copy_rejects_wrong_lengths_and_overlapping_or_out_of_bounds_fields(self):
        for changes in ({'key_bytes': 2}, {'body_bytes': 6}, {'key_bytes': True},
                        {'body_offset': 257}, {'body_offset': 327675}, {'key_offset': -1}):
            with self.subTest(changes=changes):
                core, callbacks, memory, caller, queries, _, _ = self.fixture()
                self.assertEqual(self.header(core, caller), 0)
                transfer = callbacks.transfer
                self.assertEqual(self.copy(core, caller, **changes), -41)
                self.assertIs(callbacks.transfer, transfer)
                self.assertEqual(memory.writes, [(128, 16)])
                self.assertEqual(len(queries), 1)

    def test_header_short_write_or_trap_retains_exact_row_and_first_cause(self):
        for trap in (False, True):
            with self.subTest(trap=trap):
                core, callbacks, memory, caller, queries, physical, _ = self.fixture()
                original = OSError('header transfer failed')
                write = memory.write
                def fail(caller, payload, offset):
                    write(caller, payload[:8], offset)
                    if trap:
                        raise original
                    return 8
                memory.write = fail
                self.assertEqual(self.header(core, caller), -41)
                transfer, first = callbacks.transfer, callbacks.failure
                self.assertIs(transfer.row, callbacks.row)
                self.assertIs(transfer.physical, physical)
                self.assertFalse(callbacks.transfer_ready)
                if trap:
                    self.assertIs(first, original)
                self.assertEqual(self.copy(core, caller), -41)
                self.assertEqual(self.header(core, caller), -41)
                self.assertIs(callbacks.transfer, transfer)
                self.assertIs(callbacks.failure, first)
                self.assertEqual(len(queries), 1)

    def test_header_reentry_and_short_row_write_keep_same_transfer(self):
        for phase in ('header', 'row'):
            with self.subTest(phase=phase):
                core, callbacks, memory, caller, queries, _, _ = self.fixture()
                write = memory.write
                if phase == 'row':
                    self.assertEqual(self.header(core, caller), 0)
                def fail(actual, raw, offset):
                    if phase == 'header':
                        self.assertEqual(self.copy(core, actual), -41)
                        return write(actual, raw, offset)
                    return write(actual, raw[:-1], offset)
                memory.write = fail
                action = self.header if phase == 'header' else self.copy
                self.assertEqual(action(core, caller), -41)
                transfer, first = callbacks.transfer, callbacks.failure
                self.assertIsNotNone(transfer)
                self.assertIs(transfer.row, callbacks.row)
                self.assertEqual(self.copy(core, caller), -41)
                self.assertIs(callbacks.transfer, transfer)
                self.assertIs(callbacks.failure, first)
                self.assertEqual(len(queries), 1)

    def test_partial_second_chunk_failure_and_cleanup_refusal_keep_original_custody(self):
        payload = b'a' * 32769
        core, callbacks, memory, caller, queries, physical, ready = self.fixture(('key', StoredBytes(7, payload)))
        parent, loan = core._loans[3], core._loans[7]
        self.assertEqual(self.header(core, caller), 0)
        transfer = callbacks.transfer
        original = OSError('second chunk failed after partial write')
        write = memory.write
        def fail(caller, raw, offset):
            if offset == 8192 + 16384:
                write(caller, raw[:7], offset)
                raise original
            return write(caller, raw, offset)
        memory.write = fail
        self.assertEqual(self.copy(core, caller, body_bytes=len(payload)), -41)
        self.assertIs(callbacks.failure, original)
        self.assertTrue(callbacks.transfer_started)
        self.assertIs(callbacks.transfer, transfer)
        self.assertEqual(self.copy(core, caller, body_bytes=len(payload)), -41)
        self.assertEqual(self.header(core, caller), -41)
        self.assertEqual(len(queries), 1)
        self.assertEqual(memory.writes, [(128, 16), (256, 3), (8192, 16384), (24576, 7)])
        self.assertEqual(core._cleanup(7), 1)
        self.assertIs(core._inputs[7], physical)
        self.assertIs(callbacks.transfer, transfer)
        self.assertIs(core._loans[3], parent)
        self.assertIs(core._loans[7], loan)
        ready[0] = True
        self.assertEqual(core._cleanup(7), 0)
        self.assertNotIn(7, core._inputs)
        self.assertIsNone(callbacks.transfer)
        self.assertIs(callbacks.failure, original)
        self.assertIs(core._loans[3], parent)
        self.assertIs(core._loans[7], loan)

    def test_replaced_row_after_write_and_reentrant_copy_cannot_release_original(self):
        for reenter in (False, True):
            with self.subTest(reenter=reenter):
                core, callbacks, memory, caller, queries, _, _ = self.fixture()
                self.assertEqual(self.header(core, caller), 0)
                transfer = callbacks.transfer
                write = memory.write
                def change(actual, raw, offset):
                    count = write(actual, raw, offset)
                    if reenter:
                        self.assertEqual(self.copy(core, actual), -41)
                    else:
                        callbacks.row = (b'key', StoredBytes(1, b'changed'))
                    return count
                memory.write = change
                self.assertEqual(self.copy(core, caller), -41)
                self.assertIs(callbacks.transfer, transfer)
                self.assertEqual(transfer.row[1].payload, b'payload')
                self.assertEqual(len(queries), 1)
                self.assertEqual(memory.writes, [(128, 16), (256, 3)])

    def test_coordinated_receipt_mutations_cannot_change_header_or_copied_row(self):
        for phase in ('header', 'copy'):
            for field in ('row', 'reader', 'memory', 'physical', 'ticket'):
                for setter in (setattr, object.__setattr__):
                    with self.subTest(phase=phase, field=field, setter=setter):
                        core, callbacks, memory, caller, queries, physical, _ = self.fixture()
                        captured = []
                        if phase == 'copy':
                            self.assertEqual(self.header(core, caller), 0)
                        write = memory.write
                        def replace(actual, raw, offset):
                            count = write(actual, raw, offset)
                            original = callbacks.transfer
                            captured.append(original)
                            if field == 'row':
                                replacement = (b'key', StoredBytes(original.generation, b'changed'))
                                callbacks.row = replacement
                            elif field == 'reader':
                                replacement = SimpleNamespace(owner=callbacks.store)
                                callbacks.reader = replacement
                            elif field == 'memory':
                                replacement = _Memory()
                                core._exports['memory'] = replacement
                            elif field == 'physical':
                                replacement = _PhysicalInput(b'', lambda: True, lambda _: True, journal=callbacks)
                                core._inputs[7] = replacement
                            else:
                                replacement = 8
                                core._inputs[8] = physical
                            # Both ordinary and reflection assignment must fail
                            # on the true immutable tuple, after the paired edit.
                            setter(original, field, replacement)
                            return count
                        memory.write = replace
                        action = self.header if phase == 'header' else self.copy
                        self.assertEqual(action(core, caller), -41)
                        original, first = captured[0], callbacks.failure
                        self.assertIs(callbacks.transfer, original)
                        self.assertIs(original.physical, physical)
                        self.assertIs(original.memory, memory)
                        self.assertEqual(original.body, b'payload')
                        self.assertEqual(original.generation, 9007199254740993)
                        self.assertEqual(sys.getsizeof(original), sys.getsizeof((None,) * 10))
                        self.assertEqual(self.copy(core, caller), -41)
                        self.assertEqual(self.header(core, caller), -41)
                        self.assertIs(callbacks.failure, first)
                        self.assertIs(callbacks.transfer, original)
                        self.assertEqual(len(queries), 1)
                        self.assertEqual(memory.writes, [(128, 16)] if phase == 'header'
                                         else [(128, 16), (256, 3)])

    def test_replaced_receipt_progress_or_frozen_payload_fails_against_captured_originals(self):
        for phase in ('header', 'copy'):
            for field in ('receipt', 'ready', 'started', 'payload', 'generation', 'current', 'store'):
                with self.subTest(phase=phase, field=field):
                    core, callbacks, memory, caller, queries, physical, _ = self.fixture()
                    captured = []
                    if phase == 'copy':
                        self.assertEqual(self.header(core, caller), 0)
                    write = memory.write
                    def replace(actual, raw, offset):
                        count = write(actual, raw, offset)
                        original = callbacks.transfer
                        captured.append(original)
                        if field == 'receipt':
                            replacement = (b'key', StoredBytes(original.generation, b'changed'))
                            callbacks.row = replacement
                            callbacks.transfer = original._replace(row=replacement, body=replacement[1].payload)
                        elif field == 'ready':
                            callbacks.transfer_ready = phase == 'header'
                        elif field == 'started':
                            callbacks.transfer_started = phase == 'header'
                        elif field == 'payload':
                            object.__setattr__(original.row[1], 'payload', b'changed')
                        elif field == 'generation':
                            object.__setattr__(original.row[1], 'generation', original.generation + 1)
                        elif field == 'current':
                            callbacks.current = lambda: None
                        else:
                            replacement = object()
                            callbacks.store = replacement
                            object.__setattr__(original.reader, 'owner', replacement)
                        return count
                    memory.write = replace
                    action = self.header if phase == 'header' else self.copy
                    self.assertEqual(action(core, caller), -41)
                    original, first = captured[0], callbacks.failure
                    self.assertIs(callbacks.transfer, original)
                    self.assertIs(original.physical, physical)
                    self.assertEqual(original.body, b'payload')
                    self.assertEqual(original.generation, 9007199254740993)
                    self.assertEqual(self.copy(core, caller), -41)
                    self.assertEqual(self.header(core, caller), -41)
                    self.assertIs(callbacks.failure, first)
                    self.assertIs(callbacks.transfer, original)
                    self.assertEqual(len(queries), 1)
                    self.assertEqual(memory.writes, [(128, 16)] if phase == 'header'
                                     else [(128, 16), (256, 3)])

    def test_new_imports_use_closed_memory_method_guard(self):
        core, callbacks, memory, caller, _, _, _ = self.fixture()
        guards = []
        span = SimpleNamespace(failure=None, suspended=False, reader=callbacks.reader,
            binding=SimpleNamespace(_current_observer=callbacks.current), admitted=True,
            closed_import=False, _guard_sql=lambda: guards.append('sql'),
            _guard_wasm_methods=lambda: guards.append('memory'))
        core._invocation_observation = span
        header = core._observation_import('journal_query_header', core._journal_query_header)
        copy = core._observation_import('journal_copy_row', core._journal_copy_row)
        self.assertEqual(header(caller, 7, 1, 64, 2, 66, 3, 128), 0)
        self.assertEqual(copy(caller, 7, 256, 3, 8192, 7), 0)
        self.assertEqual(guards.count('memory'), 2)
        self.assertFalse(span.closed_import)

    def test_both_original_reservations_charge_header_and_bounded_transfer_before_query(self):
        from actql_sdk._local_host_binding import _InvocationObservation
        from actql_sdk._local_storage_physical import _CLOSED_SQL_BYTES
        from test_local_host_current import LocalHostCurrentTests
        from test_local_journal_port import LocalJournalBridgeCustodyTests
        transfer_bytes = (sys.getsizeof((None,) * 10) + 64 + 16
            + 2 * sys.getsizeof(bytearray()) + sys.getsizeof(b'') + 2 * 16384
            + sys.getsizeof((None, None)) + 2 * sys.getsizeof((None, None, None)))
        self.assertEqual(LocalCore._journal_transfer_bytes(), transfer_bytes)
        fixture = LocalHostCurrentTests()
        self.addCleanup(fixture.doCleanups)
        core, source, loan, _, calls, _, _ = fixture.bridge()
        callbacks = core._journal_callbacks(loan.ticket)
        self.assertIsNone(callbacks.transfer)
        self.assertIsNone(callbacks.row)
        original = (2 * (source.length + 256) + 2 * 262144 + 4096
            + sys.getsizeof(callbacks) + sys.getsizeof(core._inputs[loan.ticket])
            + sys.getsizeof(object.__new__(_InvocationObservation))
            + sys.getsizeof((None,) * 4) + 4096 + 3 * _CLOSED_SQL_BYTES)
        self.assertEqual(calls[0], ('current', 'reserve', (source.handle, loan.ticket, original + transfer_bytes)))
        fixture = LocalJournalBridgeCustodyTests()
        self.addCleanup(fixture.doCleanups)
        core, material, calls, _ = fixture.bridge()
        loan = core.reserve_journal_observation(material, 8, store=fixture.store,
            current=lambda: None, cleanup=lambda: True)
        callbacks = core._journal_callbacks(loan.ticket)
        self.assertIsNone(callbacks.transfer)
        self.assertIsNone(callbacks.row)
        original = (2 * 1048576 + 4096 + sys.getsizeof(callbacks)
                    + sys.getsizeof(core._inputs[loan.ticket]))
        self.assertEqual(calls[0], ('journal', 'reserve',
            (material.handle, 8, loan.ticket, original + transfer_bytes)))

    def test_real_wasmtime_and_sqlite_copy_exact_large_revision_and_bytes(self):
        with TemporaryDirectory() as directory, LocalByteStore(Path(directory) / 'physical.sqlite',
                max_records=4, max_record_bytes=65536, max_payload_bytes=262144) as store:
            payload = bytes(range(256)) * 128 + b'\x00/\xf0\x9f\x98\x80/e\xcc\x81'
            key = store.namespaced_key('ns', 'key')
            self.assertEqual(store.compare_exchange('epoch', None, b'original'), 0)
            self.assertEqual(store.compare_exchange(key, None, payload), 0)
            with sqlite3.connect(Path(directory) / 'physical.sqlite') as physical:
                physical.execute('UPDATE core_bytes SET generation=? WHERE key=?', (9007199254740993, key))
            core, callbacks, _, _, _, _, _ = self.fixture()
            callbacks.store = store
            callbacks.reader = None
            engine = wasmtime.Engine()
            core._store = wasmtime.Store(engine)
            module = wasmtime.Module(engine, '''(module
                (import "actql_host" "journal_query_header" (func $query (param i32 i32 i32 i32 i32 i32 i32) (result i32)))
                (import "actql_host" "journal_copy_row" (func $copy (param i32 i32 i32 i32 i32) (result i32)))
                (import "actql_host" "journal_current" (func $current (param i32) (result i32)))
                (memory (export "memory") 5 512)
                (data (i32.const 64) "nskey")
                (func (export "read") (result i64)
                    i32.const 7 call $current i32.eqz if else unreachable end
                    i32.const 7 i32.const 1 i32.const 64 i32.const 2 i32.const 66 i32.const 3 i32.const 128
                    call $query i32.eqz if else unreachable end
                    i32.const 7 i32.const 256 i32.const 128 i32.load i32.const 8192 i32.const 132 i32.load
                    call $copy i32.eqz if else unreachable end
                    i32.const 7 call $current i32.eqz if else unreachable end
                    i32.const 136 i64.load))''')
            i32 = wasmtime.ValType.i32()
            imports = [wasmtime.Func(core._store, wasmtime.FuncType([i32] * count, [i32]),
                callback, access_caller=caller) for callback, count, caller in (
                    (core._journal_query_header, 7, True), (core._journal_copy_row, 5, True),
                    (core._journal_current, 1, False))]
            instance = wasmtime.Instance(core._store, module, imports)
            core._exports = instance.exports(core._store)
            def inspect(reader):
                callbacks.reader = reader
                try:
                    self.assertEqual(core._exports['read'](core._store), 9007199254740993)
                    memory = core._exports['memory']
                    self.assertEqual(bytes(memory.read(core._store, 256, 259)), b'key')
                    self.assertEqual(bytes(memory.read(core._store, 8192, 8192 + len(payload))), payload)
                    self.assertIsNone(callbacks.transfer)
                    self.assertIsNone(callbacks.row)
                finally:
                    callbacks.reader = None
            store.inspect_namespaces((ByteFence('epoch', 0, b'original'),), inspect=inspect, current=lambda: None)
            self.assertEqual(store.read(key), StoredBytes(9007199254740993, payload))
