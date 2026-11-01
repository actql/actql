"""Actual SQLite/File seal transport with original scalar Core EOF custody."""
import hashlib
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_files import LocalFileError
from actql_sdk._local_storage import LocalStorageCommitUnknown
import test_local_product_payload_copy as copy_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


SEALED = b'{"original":"Core Sealed e\xcc\x81/~","null":null}'


class ProductPayloadSealingTests(unittest.TestCase):
    def host(self, path, *, complete=True):
        fixture = copy_fixture.ProductPayloadCopyTests()
        self.addCleanup(fixture.doCleanups)
        host, core, held, calls, _ = fixture.host(path,
            [copy_fixture.PAYLOAD] if complete else [copy_fixture.PAYLOAD, b''])
        self.assertEqual(host._advance_original_payload_copy(held), complete)
        previous = core._call
        children, begun, confirmed = {}, set(), set()
        def input_bytes(handle):
            for value in core._loans.values():
                if value.handle == handle and value.ticket in core._inputs:
                    return json.loads(core._inputs[value.ticket].payload)
            self.fail('Missing original Sealed observation')
        def call(family, name, *args):
            if family == 'buffer' and name == 'byte' and args[0] in children:
                return SEALED[args[1]]
            ours = family == 'payload_writing' and (
                name == 'reserve' and args[1] == 3 or args[0] in children)
            if not ours: return previous(family, name, *args)
            calls.append((family, name, args))
            if name == 'reserve':
                self.assertEqual(args[0], held.record.handle)
                self.assertIsNotNone(held.chunk)
                self.assertEqual(held.row.generation, 3)
                handle = 100 + args[2]
                children[handle] = args[2]
                return handle
            if name == 'produce':
                actual = input_bytes(args[1])
                identity = held.finalization.result.observation.identity
                self.assertEqual(actual, {'store_authority_cid': held.store_authority,
                    'material_generation_cid': held.generation,
                    'device': str(identity.device), 'inode': str(identity.inode),
                    'size': str(len(copy_fixture.PAYLOAD)),
                    'physical_digest': 'sha256:' + hashlib.sha256(copy_fixture.PAYLOAD).hexdigest()})
                self.assertIsNone(held.physical.descriptor)
                self.assertEqual(held.finalization.result.observation.size, len(copy_fixture.PAYLOAD))
            if name == 'length': return len(SEALED)
            if name == 'begin':
                self.assertNotIn(args[0], begun)
                self.assertIsNone(held.names, 'Old revision name loan survived Sealed admission')
                begun.add(args[0])
            if name == 'confirm':
                self.assertIn(args[0], begun)
                actual = input_bytes(args[1])
                self.assertEqual(actual, {'store_authority_cid': held.store_authority,
                    'material_generation_cid': held.generation,
                    'physical_revision': 4, 'record_json': SEALED.decode()})
                confirmed.add(args[0])
            if name == 'close':
                if args[0] in begun and args[0] not in confirmed: return -9
                return core._cleanup(children.pop(args[0]))
            return 0
        core._call = original_byte_fixture_port(call)
        return host, core, held, calls

    def test_original_eof_snapshot_final_name_and_actual_sealed_row_share_custody(self):
        with TemporaryDirectory(prefix='actql-payload-sealed-') as directory:
            host, core, held, calls = self.host(Path(directory))
            before, chunk, physical, capacity = len(calls), held.chunk, held.physical, held.capacity
            self.assertTrue(host._advance_original_payload_sealing(held))
            self.assertEqual((held.row.generation, held.row.payload), (4, SEALED))
            self.assertIs(held.chunk, chunk)
            self.assertIs(core._loans[chunk.ticket], chunk)
            self.assertIs(held.physical, physical)
            self.assertIs(held.capacity, capacity)
            self.assertEqual(physical.name, 'payload-' + held.generation[7:])
            self.assertEqual((Path(directory) / 'source' / 'results' / physical.name).read_bytes(), copy_fixture.PAYLOAD)
            self.assertFalse(any(f in ('source', 'task', 'publication') for f, _, _ in calls[before:]))
            self.assertTrue(host.close())

    def test_lost_writer_stop_reply_retains_same_eof_and_final_cursor_without_second_close(self):
        with TemporaryDirectory(prefix='actql-payload-sealed-') as directory:
            host, _, held, calls = self.host(Path(directory))
            chunk, physical, capacity = held.chunk, held.physical, held.capacity
            descriptor, close = physical.descriptor, os.close
            def lose(stopped):
                self.assertEqual(stopped, descriptor)
                close(stopped)
                raise OSError('original stop acknowledgement lost')
            with patch('actql_sdk._local_files.os.close', side_effect=lose):
                with self.assertRaisesRegex(LocalFileError, 'stop remains unknown'):
                    host._advance_original_payload_sealing(held)
            cursor = held.finalization
            self.assertIs(held.chunk, chunk)
            self.assertIs(held.capacity, capacity)
            self.assertIsNone(held.writing)
            self.assertFalse(cursor.linked)
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('Original descriptor close repeated')):
                self.assertTrue(host._advance_original_payload_sealing(held))
            self.assertIs(held.finalization, cursor)
            self.assertIs(held.physical, physical)
            self.assertEqual(sum(f == 'payload_writing' and n == 'reserve' and a[1] == 3 for f, n, a in calls), 1)
            self.assertTrue(host.close())

    def test_lost_sealed_cas_reply_uses_actual_same_row_after_pending_close_without_reissue(self):
        with TemporaryDirectory(prefix='actql-payload-sealed-') as directory:
            host, core, held, calls = self.host(Path(directory))
            store = host._installation._store
            write = store.compare_exchange_reserved_inspected
            attempts = []
            def lose(*args, **kwargs):
                attempts.append(write(*args, **kwargs))
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'compare_exchange_reserved_inspected', side_effect=lose):
                with self.assertRaises(LocalStorageCommitUnknown): host._advance_original_payload_sealing(held)
                child, cursor, capacity = held.writing, held.finalization, held.capacity
                with self.assertRaises(ValueError): host._advance_original_payload_sealing(held)
            self.assertFalse(host.close())
            self.assertIs(core._loans[child.ticket], child)
            self.assertIs(held.finalization, cursor)
            self.assertIs(held.capacity, capacity)
            host._observe_original_payload_writing(held)
            self.assertEqual(attempts, [4])
            self.assertEqual(held.row.payload, SEALED)
            self.assertEqual(sum(f == 'payload_writing' and n == 'begin' and a[0] == child.handle for f, n, a in calls), 1)
            self.assertTrue(host.close())

    def test_complete_physical_bytes_without_original_core_eof_cannot_begin_snapshot(self):
        with TemporaryDirectory(prefix='actql-payload-sealed-') as directory:
            host, _, held, _ = self.host(Path(directory), complete=False)
            physical = held.physical
            self.assertEqual(physical.written, len(copy_fixture.PAYLOAD))
            with patch.object(physical.root, 'begin_snapshot', side_effect=AssertionError('Missing Core EOF reached snapshot')):
                with self.assertRaises(ValueError): host._advance_original_payload_sealing(held)
            self.assertIsNone(held.finalization)
            self.assertIsNone(held.writing)
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
