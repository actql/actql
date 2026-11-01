"""Real SQLite/File acquisition and staging with scalar Core; not actual Wasm."""
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_files import LocalAreaAcquisitionError
from actql_sdk._local_storage import LocalStorageCommitUnknown
import test_local_product_payload_capacity as capacity_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


OWNED = b'{"original":"Core Owned e\xcc\x81/~","null":null}'


class ProductPayloadFileTests(unittest.TestCase):
    def host(self, path):
        fixture = capacity_fixture.ProductPayloadCapacityTests()
        self.addCleanup(fixture.doCleanups)
        host, core, held, calls, _ = fixture.host(path)
        host._reserve_original_payload_capacity(held)
        host._save_original_payload_reserved(held)
        host._prepare_original_payload_writing(held)
        previous = core._call
        children, wires, begun, confirmed = {}, {}, set(), set()
        def input_bytes(handle):
            for value in core._loans.values():
                if value.handle == handle and value.ticket in core._inputs:
                    return json.loads(core._inputs[value.ticket].payload)
            self.fail('Missing original physical input')
        def call(family, name, *args):
            ours = family in ('payload_allocation', 'payload_names') or (
                family == 'payload_writing' and (name == 'reserve' and args[1] == 2 or args[0] in children))
            if family == 'buffer' and name == 'byte' and args[0] in wires:
                return wires[args[0]][args[1]]
            if not ours: return previous(family, name, *args)
            calls.append((family, name, args))
            if name == 'reserve':
                self.assertEqual(args[0], held.record.handle)
                kind = args[1] if family != 'payload_names' else 0
                ticket = args[2] if family != 'payload_names' else args[1]
                handle = 100 + ticket
                children[handle] = (family, kind, ticket)
                return handle
            if name == 'produce':
                if family == 'payload_allocation':
                    packet = input_bytes(args[1])
                    name_value = 'alloc-' + held.generation[7:] + '-1'
                    kind = children[args[0]][1]
                    self.assertEqual(packet['namespace'], 'publication_payload_allocation')
                    if kind == 1:
                        self.assertIsNone(packet['physical_revision'])
                        self.assertIsNone(packet['allocation_body'])
                        body = name_value
                    else:
                        self.assertEqual(packet['physical_revision'], '0')
                        self.assertEqual(packet['allocation_body'], name_value)
                        self.assertIsNone(held.area.directory)
                        identity = host._installation._results.observe_area(held.area)
                        self.assertEqual((packet['device'], packet['inode']), (str(identity.device), str(identity.inode)))
                        body = name_value + '|' + packet['device'] + '|' + packet['inode']
                    wires[args[0]] = json.dumps({'store_authority_cid': held.store_authority,
                        'namespace': packet['namespace'], 'material_generation_cid': held.generation,
                        'expected_revision': None if kind == 1 else '0',
                        'previous_body': None if kind == 1 else name_value,
                        'allocation_body': body}).encode()
                elif family == 'payload_writing':
                    actual = input_bytes(args[1])
                    identity = held.origin.observe(held.physical).identity
                    self.assertEqual((actual['device'], actual['inode']), (str(identity.device), str(identity.inode)))
                    wires[args[0]] = OWNED
                else:
                    wires[args[0]] = json.dumps({'store_authority_cid': held.store_authority,
                        'material_generation_cid': held.generation, 'request_cid': 'original',
                        'record_revision': '3', 'staging_name': 'stage-' + held.generation[7:],
                        'object_name': 'payload-' + held.generation[7:]}).encode()
            if name == 'length': return len(wires[args[0]])
            if name == 'begin':
                if args[0] in begun: return -33
                begun.add(args[0])
            if name == 'confirm':
                self.assertIn(args[0], begun)
                actual = input_bytes(args[1])
                if family == 'payload_allocation':
                    original = json.loads(wires[args[0]])
                    expected = '0' if children[args[0]][1] == 1 else '1'
                    if actual['physical_revision'] != expected or actual['allocation_body'] != original['allocation_body']: return -32
                elif actual['physical_revision'] != 3 or actual['record_json'].encode() != OWNED:
                    return -32
                confirmed.add(args[0])
            if name == 'close':
                if args[0] in begun and args[0] not in confirmed: return -9
                _, _, ticket = children.pop(args[0])
                return core._cleanup(ticket)
            return 0
        core._call = original_byte_fixture_port(call)
        return host, core, held, calls

    def test_saved_allocation_identity_precedes_open_and_owned_file_uses_core_stage_name(self):
        with TemporaryDirectory(prefix='actql-payload-file-') as directory:
            host, core, held, _ = self.host(Path(directory))
            host._acquire_original_payload_file(held)
            self.assertEqual(held.row.generation, 3)
            self.assertEqual(held.row.payload, OWNED)
            self.assertEqual(held.allocation_row.generation, 1)
            identity = host._installation._results.observe_area(held.area)
            self.assertEqual(held.origin._identity, identity)
            physical = held.physical
            host._stage_original_payload_file(held)
            self.assertIs(held.physical, physical)
            self.assertIs(physical.root, host._installation._results)
            self.assertEqual(physical.name, 'stage-' + held.generation[7:])
            self.assertEqual(physical.written, 0)
            self.assertIs(core._loans[held.record.ticket], held.record)
            self.assertTrue(host.close())

    def test_ownership_commit_reply_loss_retains_same_area_and_never_opens_or_recreates(self):
        with TemporaryDirectory(prefix='actql-payload-file-') as directory:
            host, _, held, calls = self.host(Path(directory))
            store = host._installation._store
            write = store.compare_exchange_attached_inspected
            attempts = []
            def lose(candidate, *args, **kwargs):
                result = write(candidate, *args, **kwargs)
                attempts.append(candidate)
                if candidate.expected_generation == 0: raise LocalStorageCommitUnknown(store)
                return result
            with patch.object(store, 'compare_exchange_attached_inspected', side_effect=lose):
                with self.assertRaises(LocalStorageCommitUnknown): host._acquire_original_payload_file(held)
            area = held.area
            self.assertIsNone(area.directory)
            self.assertIsNone(held.origin)
            self.assertIsNone(held.physical)
            self.assertFalse(host.close())
            self.assertIs(held.area, area)
            host._observe_original_allocation(held)
            self.assertEqual(len(attempts), 2)
            self.assertEqual(sum(f == 'payload_allocation' and n == 'begin' for f, n, _ in calls), 2)
            self.assertTrue(host.close())

    def test_failed_area_sync_keeps_original_handle_for_same_sync_retry_without_mkdir(self):
        with TemporaryDirectory(prefix='actql-payload-file-') as directory:
            host, _, held, _ = self.host(Path(directory))
            with patch('actql_sdk._local_files.os.fsync', side_effect=OSError('original area sync failure')):
                with self.assertRaises(LocalAreaAcquisitionError): host._acquire_original_payload_file(held)
            area = held.area
            self.assertIsNotNone(area)
            self.assertFalse(area.creation_synced)
            with patch('actql_sdk._local_files.os.mkdir', side_effect=AssertionError('Area recreated')):
                host._retry_original_area_sync(held)
            self.assertIs(held.area, area)
            self.assertTrue(area.creation_synced)
            self.assertIsNone(held.physical)
            self.assertTrue(host.close())

    def test_failed_staging_sync_retains_same_cursor_for_exact_retry_without_link(self):
        with TemporaryDirectory(prefix='actql-payload-file-') as directory:
            host, _, held, _ = self.host(Path(directory))
            host._acquire_original_payload_file(held)
            physical = held.physical
            with patch('actql_sdk._local_files.os.fsync', side_effect=OSError('original stage sync failure')):
                with self.assertRaisesRegex(OSError, 'stage sync failure'): host._stage_original_payload_file(held)
            cursor = held.adoption
            self.assertIsNotNone(cursor)
            self.assertTrue(cursor.linked)
            with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('Original link repeated')):
                host._advance_original_payload_staging(held)
            self.assertIs(held.physical, physical)
            self.assertIsNone(held.adoption)
            self.assertEqual(physical.name, 'stage-' + held.generation[7:])
            self.assertTrue(host.close())

    def test_descriptor_cleanup_failure_keeps_file_area_and_capacity_for_same_retry(self):
        with TemporaryDirectory(prefix='actql-payload-file-') as directory:
            host, _, held, _ = self.host(Path(directory))
            host._acquire_original_payload_file(held)
            physical, area, capacity = held.physical, held.area, held.capacity
            actual_close = os.close
            def fail(descriptor):
                if descriptor == physical.descriptor: raise OSError('original descriptor close failure')
                return actual_close(descriptor)
            with patch('actql_sdk._local_files.os.close', side_effect=fail):
                self.assertFalse(host.close())
            self.assertIs(held.physical, physical)
            self.assertIs(held.area, area)
            self.assertIs(held.capacity, capacity)
            self.assertIsNotNone(physical.descriptor)
            # An uncertain close cannot retry a possibly recycled descriptor.
            # Supply the actual physical stop, then let the same Owner observe it.
            self.assertFalse(host.close())
            actual_close(physical.descriptor)
            self.assertTrue(host.close())

    def test_pending_staging_cleanup_stops_descriptor_before_retiring_same_cursor(self):
        with TemporaryDirectory(prefix='actql-payload-file-') as directory:
            host, _, held, _ = self.host(Path(directory))
            host._acquire_original_payload_file(held)
            physical, area, capacity = held.physical, held.area, held.capacity
            with patch('actql_sdk._local_files.os.fsync', side_effect=OSError('original stage sync failure')):
                with self.assertRaisesRegex(OSError, 'stage sync failure'):
                    host._stage_original_payload_file(held)
            cursor = held.adoption
            self.assertTrue(cursor.linked)
            original_descriptor = physical.descriptor
            actual_close = os.close
            def fail(descriptor):
                if descriptor == original_descriptor:
                    raise OSError('original descriptor stop failure')
                return actual_close(descriptor)
            with patch('actql_sdk._local_files.os.close', side_effect=fail):
                self.assertFalse(host.close())
            self.assertIs(held.adoption, cursor)
            self.assertIs(held.physical, physical)
            self.assertIs(held.area, area)
            self.assertIs(held.capacity, capacity)
            self.assertFalse(host.close())
            actual_close(original_descriptor)
            with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('Cleanup repeated link')):
                self.assertTrue(host.close())
            self.assertIsNone(held.adoption)
            self.assertIsNone(held.physical)


if __name__ == '__main__':
    unittest.main()
