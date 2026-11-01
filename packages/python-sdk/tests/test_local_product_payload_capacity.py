"""Actual SQLite capacity/transition caller with scalar Core; not actual Wasm."""
import json
import copy
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_storage import LocalStorageCommitUnknown, LocalStorageError
import test_local_product_payload_intent as intent_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


RESERVED = b'{"original":"Core Reserved e\xcc\x81/~","null":null}'
WRITING = b'{"original":"Core Writing e\xcc\x81/~","null":null}'


class ProductPayloadCapacityTests(unittest.TestCase):
    def host(self, path):
        fixture = intent_fixture.ProductPayloadIntentTests()
        self.addCleanup(fixture.doCleanups)
        host, core, publication, calls, _ = fixture.host(path)
        held = host._prepare_original_payload(publication, 0)
        host._save_original_payload_intent(held)
        previous = core._call
        children, begun, confirmed = {}, set(), set()
        faults = {}
        def source(handle):
            for value in core._loans.values():
                if value.handle == handle and value.ticket in core._inputs:
                    return json.loads(core._inputs[value.ticket].payload)
            self.fail('Missing original physical observation')
        def call(family, name, *args):
            if family == 'payload_record' and name == 'close' and children:
                return -9
            if family not in ('payload_reservation', 'payload_writing'):
                if family == 'buffer' and name == 'byte' and args[0] in children:
                    return children[args[0]][2][args[1]]
                return previous(family, name, *args)
            calls.append((family, name, args))
            if (family, name) in faults: return faults[family, name]
            if name == 'reserve':
                self.assertEqual(args[0], held.record.handle)
                ticket = args[1] if family == 'payload_reservation' else args[2]
                if family == 'payload_writing': self.assertEqual(args[1], 1)
                handle = 100 + ticket
                children[handle] = (family, ticket, RESERVED if family == 'payload_reservation' else WRITING)
                return handle
            if name == 'length': return len(children[args[0]][2])
            if name == 'produce' and family == 'payload_reservation':
                actual = source(args[1])
                if (actual['reserved_bytes'] != held.maximum or actual['reserved_objects'] != 1
                        or actual['capacity_namespace'] != 'publication_payload'):
                    return -32
            if name == 'begin':
                if args[0] in begun: return -33
                begun.add(args[0])
            if name == 'confirm':
                self.assertIn(args[0], begun)
                actual = source(args[1])
                expected_revision = 1 if family == 'payload_reservation' else 2
                self.assertEqual(actual['store_authority_cid'], held.store_authority)
                self.assertEqual(actual['material_generation_cid'], held.generation)
                if (actual['physical_revision'] != expected_revision
                        or actual['record_json'].encode() != children[args[0]][2]): return -32
                confirmed.add(args[0])
            if name == 'close':
                if args[0] in begun and args[0] not in confirmed: return -9
                _, ticket, _ = children.pop(args[0])
                return core._cleanup(ticket)
            return 0
        core._call = original_byte_fixture_port(call)
        return host, core, held, calls, faults

    def row(self, host, held):
        return host._installation._store.read(held.row.key)

    def test_reserved_and_writing_are_confirmed_from_saved_rows_with_original_capacity(self):
        with TemporaryDirectory(prefix='actql-payload-capacity-') as directory:
            host, core, held, calls, _ = self.host(Path(directory))
            before = len(calls)
            host._reserve_original_payload_capacity(held)
            with self.assertRaises(ValueError):
                host._save_original_payload_transition(held, copy.copy(held.reservation),
                    lambda: self.fail('Copied child reached transport'),
                    lambda: self.fail('Copied child reached Core begin'))
            host._save_original_payload_reserved(held)
            self.assertEqual((self.row(host, held).generation, self.row(host, held).payload), (1, RESERVED))
            host._prepare_original_payload_writing(held)
            self.assertEqual((self.row(host, held).generation, self.row(host, held).payload), (2, WRITING))
            self.assertEqual((held.capacity.reserved_bytes, held.capacity.reserved_objects), (held.maximum, 1))
            self.assertIs(core._loans[held.record.ticket], held.record)
            self.assertFalse(any(f in ('source', 'task', 'publication') for f, _, _ in calls[before:]))
            capacity = held.capacity
            self.assertTrue(host.close())
            # Connection cleanup never infers payload reclamation or releases
            # durable reservation on behalf of the original payload Owner.
            from actql_sdk._local_storage import LocalByteStore
            with LocalByteStore(Path(directory) / 'state' / 'client.sqlite3', max_records=1024,
                                max_record_bytes=1048576, max_payload_bytes=8388608) as store:
                self.assertEqual(store.read_capacity(capacity.namespace, capacity.key), capacity)

    def test_capacity_reply_loss_is_observed_once_after_pending_close_without_rereserving(self):
        with TemporaryDirectory(prefix='actql-payload-capacity-') as directory:
            host, _, held, calls, _ = self.host(Path(directory))
            store = host._installation._store
            reserve = store.reserve_capacity_inspected
            attempts = []
            def lose(*args, **kwargs):
                attempts.append(reserve(*args, **kwargs))
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'reserve_capacity_inspected', side_effect=lose):
                with self.assertRaises(LocalStorageCommitUnknown): host._reserve_original_payload_capacity(held)
                with self.assertRaisesRegex(LocalStorageError, 'lookup'): host._reserve_original_payload_capacity(held)
            self.assertFalse(host.close())
            host._observe_original_payload_capacity(held)
            self.assertEqual(len(attempts), 1)
            self.assertEqual(self.row(host, held).payload, intent_fixture.RAW)
            self.assertFalse(any(f == 'payload_reservation' and n == 'begin' for f, n, _ in calls))
            self.assertTrue(host.close())

    def test_reserved_commit_reply_loss_keeps_same_child_then_observes_actual_successor(self):
        with TemporaryDirectory(prefix='actql-payload-capacity-') as directory:
            host, core, held, calls, _ = self.host(Path(directory))
            host._reserve_original_payload_capacity(held)
            child = held.reservation
            store = host._installation._store
            write = store.compare_exchange_reserved_inspected
            attempts = []
            def lose(*args, **kwargs):
                attempts.append(write(*args, **kwargs))
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'compare_exchange_reserved_inspected', side_effect=lose):
                with self.assertRaises(LocalStorageCommitUnknown): host._save_original_payload_reserved(held)
                with self.assertRaisesRegex(LocalStorageError, 'lookup'): host._save_original_payload_reserved(held)
            self.assertFalse(host.close())
            host._observe_original_payload_reserved(held)
            self.assertEqual(len(attempts), 1)
            self.assertIs(core._loans[child.ticket], child)
            self.assertEqual(sum(f == 'payload_reservation' and n == 'begin' for f, n, _ in calls), 1)
            self.assertEqual(held.row.payload, RESERVED)
            self.assertTrue(host.close())

    def test_writing_reply_loss_does_not_allocate_file_or_repeat_original_transition(self):
        with TemporaryDirectory(prefix='actql-payload-capacity-') as directory:
            host, _, held, calls, _ = self.host(Path(directory))
            host._reserve_original_payload_capacity(held)
            host._save_original_payload_reserved(held)
            store = host._installation._store
            write = store.compare_exchange_reserved_inspected
            attempts = []
            def lose(*args, **kwargs):
                attempts.append(write(*args, **kwargs))
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'compare_exchange_reserved_inspected', side_effect=lose):
                with self.assertRaises(LocalStorageCommitUnknown): host._prepare_original_payload_writing(held)
            self.assertFalse(host.close())
            host._observe_original_payload_writing(held)
            self.assertEqual(len(attempts), 1)
            self.assertEqual(sum(f == 'payload_writing' and n == 'begin' for f, n, _ in calls), 1)
            self.assertEqual(held.row.payload, WRITING)
            self.assertTrue(host.close())

    def test_foreign_actual_capacity_is_rejected_by_core_without_record_cas(self):
        with TemporaryDirectory(prefix='actql-payload-capacity-') as directory:
            host, core, held, calls, _ = self.host(Path(directory))
            store = host._installation._store
            store.reserve_capacity('publication_payload', held.row.key, held.maximum - 1, 1,
                                   store._max_payload_bytes, 32)
            host._payload_capacity_attempts.add(held.record.ticket)
            with self.assertRaises(LocalCoreError): host._observe_original_payload_capacity(held)
            self.assertIsNone(held.capacity)
            self.assertIs(core._loans[held.record.ticket], held.record)
            self.assertEqual(self.row(host, held).payload, intent_fixture.RAW)
            self.assertFalse(any(f == 'payload_reservation' and n == 'begin' for f, n, _ in calls))
            self.assertFalse(host.close())


if __name__ == '__main__':
    unittest.main()
