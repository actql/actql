"""Actual retained final reader with scalar Core Sealed binding/current."""
import hashlib
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_files import LocalFileError, LocalReaderAcquisitionError
import test_local_product_payload_sealing as sealing_fixture
import test_local_product_payload_copy as copy_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


BINDING = b'{"original":"Core Sealed binding e\xcc\x81/~","null":null}'


class ProductPayloadReaderTests(unittest.TestCase):
    def host(self, path):
        fixture = sealing_fixture.ProductPayloadSealingTests()
        self.addCleanup(fixture.doCleanups)
        host, core, held, calls = fixture.host(path)
        self.assertTrue(host._advance_original_payload_sealing(held))
        previous = core._call
        children, wires, faults = {}, {}, {}
        def call(family, name, *args):
            if family == 'buffer' and name == 'byte' and args[0] in wires:
                return wires[args[0]][args[1]]
            if family not in ('payload_binding', 'payload_names'): return previous(family, name, *args)
            calls.append((family, name, args))
            if name in faults: return faults[name]
            if name == 'reserve':
                self.assertEqual(args[0], held.record.handle)
                handle = 100 + args[1]
                children[handle] = args[1]
                return handle
            if name == 'produce':
                self.assertEqual((held.row.generation, held.row.payload), (4, sealing_fixture.SEALED))
                wires[args[0]] = BINDING if family == 'payload_binding' else json.dumps({
                    'store_authority_cid': held.store_authority,
                    'material_generation_cid': held.generation, 'request_cid': 'original',
                    'record_revision': '4', 'staging_name': 'stage-' + held.generation[7:],
                    'object_name': 'payload-' + held.generation[7:]}).encode()
            if name == 'length': return len(wires[args[0]])
            if name == 'close': return core._cleanup(children.pop(args[0]))
            return 0
        core._call = original_byte_fixture_port(call)
        return host, core, held, calls, faults

    def test_fresh_sealed_names_and_binding_open_same_file_and_retain_eof_descriptor(self):
        with TemporaryDirectory(prefix='actql-payload-reader-') as directory:
            host, core, held, calls, _ = self.host(Path(directory))
            finalization, physical, capacity = held.finalization, held.physical, held.capacity
            before = len(calls)
            host._open_original_payload_reader(held)
            reader = held.reader
            self.assertIs(reader.finalization, finalization)
            self.assertIsNone(held.chunk)
            self.assertIsNone(held.writing)
            self.assertIs(core._loans[held.binding.ticket], held.binding)
            self.assertTrue(host._advance_original_payload_reader(held))
            observed = reader.root.observe_completed_reader(reader)
            self.assertEqual(observed.physical_digest, 'sha256:' + hashlib.sha256(copy_fixture.PAYLOAD).hexdigest())
            self.assertEqual(observed.observation.size, len(copy_fixture.PAYLOAD))
            self.assertIsNotNone(reader.descriptor)
            with patch('actql_sdk._local_files.os.pread', side_effect=AssertionError('Completed original reread')):
                self.assertTrue(host._advance_original_payload_reader(held))
            self.assertIs(held.capacity, capacity)
            self.assertIs(held.physical, physical)
            self.assertFalse(any(f in ('source', 'task', 'publication') for f, _, _ in calls[before:]))
            self.assertTrue(host.close())

    def test_current_binding_refusal_precedes_physical_read_and_keeps_same_descriptor(self):
        with TemporaryDirectory(prefix='actql-payload-reader-') as directory:
            host, _, held, _, faults = self.host(Path(directory))
            host._open_original_payload_reader(held)
            reader, capacity = held.reader, held.capacity
            faults['validate'] = -32
            with patch('actql_sdk._local_files.os.pread', side_effect=AssertionError('Current refusal reached physical read')):
                with self.assertRaises(LocalCoreError) as failure:
                    host._advance_original_payload_reader(held)
            self.assertEqual(failure.exception.code, -32)
            self.assertIs(held.reader, reader)
            self.assertIs(held.capacity, capacity)
            self.assertEqual(reader.offset, 0)
            self.assertTrue(host.close())

    def test_failed_reader_acquisition_retains_original_descriptor_without_reopening(self):
        with TemporaryDirectory(prefix='actql-payload-reader-') as directory:
            host, _, held, _, _ = self.host(Path(directory))
            root = held.physical.root
            with patch.object(root, '_validate_reader', side_effect=LocalFileError('original reader validation failed')):
                with self.assertRaises(LocalReaderAcquisitionError) as failure:
                    host._open_original_payload_reader(held)
            reader = held.reader
            self.assertIs(failure.exception.original_reader, reader)
            descriptor, capacity, finalization = reader.descriptor, held.capacity, held.finalization
            self.assertIsNotNone(descriptor)
            with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('Original reader reopened')):
                with self.assertRaises(ValueError): host._open_original_payload_reader(held)
            close = os.close
            def fail(stopped):
                if stopped == descriptor: raise OSError('original reader stop failed')
                return close(stopped)
            with patch('actql_sdk._local_files.os.close', side_effect=fail):
                self.assertFalse(host.close())
            self.assertIs(held.reader, reader)
            self.assertIs(held.capacity, capacity)
            self.assertIs(held.finalization, finalization)
            self.assertFalse(host.close())
            close(descriptor)
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
