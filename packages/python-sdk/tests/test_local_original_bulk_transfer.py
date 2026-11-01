"""Bounded original-memory counters and SQLite controls, not normal acceptance."""
from ctypes import POINTER, c_uint8, cast
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import RLock
from types import SimpleNamespace
import json
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Output, _PhysicalInput, _PublisherCallbacks
from actql_sdk._local_journal_port import _JournalCallbacks
from actql_sdk._local_storage import ByteFence, LocalByteStore


class Memory:
    def __init__(self, payload=b''):
        self.data = (c_uint8 * 131072)()
        self.data[64:64 + len(payload)] = payload
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


class OriginalBulkTransferTests(unittest.TestCase):
    def bridge(self, payload=b''):
        core = LocalCore.__new__(LocalCore)
        core._identity, core._store = object(), object()
        core._lock = RLock()
        core._ordinary_host = True
        core._closing = core._closed = core._retired = False
        core._inputs, core._loans, core._released = {}, {}, set()
        core._physical_holding = None
        current = []
        core._physical_vm_observation = SimpleNamespace(
            _require_core_current=lambda: current.append('current'))
        memory = Memory(payload)
        core._exports = {'memory': memory}
        return core, memory, current

    def output(self, payload):
        core, memory, current = self.bridge(payload)
        output = _Output(core._identity, 7, 23, 65536, 'material')
        physical = _PhysicalInput(b'', lambda: True, lambda _: True)
        core._inputs[7], core._loans[7] = physical, output
        calls = []
        def call(family, operation, *args):
            calls.append((family, operation, args))
            if operation == 'length':
                return len(payload)
            self.assertEqual((family, operation), ('buffer', 'read_block'))
            self.assertEqual(args[0], 23)
            self.assertTrue(0 < args[2] <= 16384)
            return 64 + args[1]
        core._call = call
        return core, memory, current, output, physical, calls

    def test_ordinary_output_copies_complete_original_in_two_blocks_without_scalar_fallback(self):
        payload = bytes(range(256)) * 64 + b'\x00e\xcc\x81/\xf0\x9f\x98\x80\r\n'
        core, memory, current, output, physical, calls = self.output(payload)
        self.assertEqual(core.read_material(output), payload)
        self.assertEqual([args[2] for _, op, args in calls if op == 'read_block'], [16384, 11])
        self.assertEqual(memory.reads, [(64, 16448), (16448, 16459)])
        self.assertEqual(len(current), 4)
        self.assertIs(core._loans[7], output)
        self.assertIs(core._inputs[7], physical)
        count = len(calls)
        self.assertIs(core.read_material(output), physical.payload)
        self.assertEqual(len(calls), count)

    def test_current_or_original_output_change_during_copy_keeps_no_partial_payload(self):
        for mode in ('current', 'loan', 'input', 'memory', 'short'):
            with self.subTest(mode=mode):
                core, memory, _, output, physical, _ = self.output(b'original')
                read = memory.read
                def changed(*args):
                    raw = read(*args)
                    if mode == 'current':
                        def refused():
                            raise ValueError('original current changed')
                        core._physical_vm_observation._require_core_current = refused
                    elif mode == 'loan':
                        core._loans[7] = _Output(core._identity, 7, 23, 65536, 'material')
                    elif mode == 'input':
                        core._inputs[7] = _PhysicalInput(b'', lambda: True, lambda _: True)
                    elif mode == 'memory':
                        core._exports['memory'] = Memory()
                    else:
                        return raw[:-1]
                    return raw
                memory.read = changed
                with self.assertRaises((ValueError, LocalCoreError)):
                    core.read_material(output)
                self.assertEqual(physical.payload, b'')
                self.assertIn(7, core._loans)

    def test_input_copy_requires_same_memory_original_ticket_and_complete_bounded_write(self):
        core, memory, _ = self.bridge()
        source = _PhysicalInput(b'\x00e\xcc\x81/\xff\r\n', lambda: True, lambda _: True)
        core._inputs[9] = source
        caller = SimpleNamespace(get=lambda _: memory)
        self.assertEqual(core._input_copy(caller, 9, 0, 64, 8), 8)
        self.assertEqual(bytes(memory.data[64:72]), source.payload)
        writes = len(memory.writes)
        for actual, ticket, start, offset, length in (
                (SimpleNamespace(get=lambda _: Memory()), 9, 0, 64, 1),
                (caller, 10, 0, 64, 1), (caller, 9, -1, 64, 1),
                (caller, 9, 0, 64, 16385), (caller, 9, 8, 64, 1)):
            self.assertEqual(core._input_copy(actual, ticket, start, offset, length), -5)
        self.assertEqual(len(memory.writes), writes)
        write = memory.write
        def replace(*args):
            count = write(*args)
            core._inputs[9] = _PhysicalInput(source.payload, lambda: True, lambda _: True)
            return count
        memory.write = replace
        self.assertEqual(core._input_copy(caller, 9, 0, 64, 8), -5)
        self.assertIsNot(core._inputs[9], source)

    def test_sqlite_journal_exact_full_row_and_revision_survive_bounded_transfers(self):
        with TemporaryDirectory() as directory, LocalByteStore(Path(directory) / 'fresh.sqlite',
                max_records=4, max_record_bytes=65536, max_payload_bytes=262144) as store:
            namespace, key = 'e\u0301:/~', 'k\x00/~😀'
            payload = bytes(range(256)) * 128 + b'\x00e\xcc\x81'
            physical_key = store.namespaced_key(namespace, key)
            self.assertEqual(store.compare_exchange('epoch', None, b'original'), 0)
            self.assertEqual(store.compare_exchange(physical_key, None, payload), 0)
            callbacks = _JournalCallbacks(lambda: None, store)
            def inspect(reader):
                callbacks.reader = reader
                try:
                    left, right = namespace.encode(), key.encode()
                    self.assertEqual(callbacks.begin(1, len(left), len(right)), 0)
                    self.assertEqual(callbacks.query_copy(0, left), len(left))
                    self.assertEqual(callbacks.query_copy(len(left), right), len(right))
                    self.assertEqual(callbacks.query(), 0)
                    original = callbacks.row
                    pieces = [callbacks.row_copy(1, i, min(16384, len(payload) - i))
                              for i in range(0, len(payload), 16384)]
                    self.assertEqual(list(map(len, pieces)), [16384, 16384, 4])
                    self.assertEqual(b''.join(pieces), payload)
                    self.assertEqual(callbacks.row_copy(0, 0, len(right)), right)
                    self.assertEqual(callbacks.revision(), 0)
                    self.assertIs(callbacks.row, original)
                    self.assertEqual(callbacks.release(), 0)
                finally:
                    callbacks.reader = None
            store.inspect_namespaces((ByteFence('epoch', 0, b'original'),),
                                     inspect=inspect, current=lambda: None)
            self.assertEqual(store.read(physical_key).payload, payload)

    def test_publisher_block_keeps_original_six_facts_and_authorizes_only_complete_once(self):
        fact = {'stage': 'request', 'namespace_id': 'ns', 'authority_scope_cid': 'scope',
                'run_definition_cid': 'definition', 'publication_request_cid': 'request',
                'public_index_entry_cid': None}
        payload = json.dumps(fact, separators=(',', ':')).encode()
        core, memory, _ = self.bridge(payload)
        authorized = []
        callbacks = _PublisherCallbacks(lambda: True, lambda value: authorized.append(value) or True)
        core._inputs[9] = _PhysicalInput(b'', lambda: True, lambda _: True, publisher=callbacks)
        caller = SimpleNamespace(get=lambda _: memory)
        self.assertEqual(core._publisher_begin(9, len(payload)), 0)
        self.assertEqual(core._publisher_copy(caller, 9, 0, 64, len(payload)), len(payload))
        self.assertEqual(authorized, [])
        self.assertEqual(core._publisher_finish(9), 0)
        self.assertEqual(len(authorized), 1)
        self.assertEqual({k: getattr(authorized[0], k) for k in fact}, fact)
        self.assertIsNone(callbacks.buffer)
        self.assertEqual(core._publisher_finish(9), -2)
