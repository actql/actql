"""Actual File copy from original scalar Core chunks; not actual Wasm/ACK."""
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_files import LocalFileError
from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_product import LocalProductCleanupPending
import test_local_product_payload_file as file_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


PAYLOAD = b'[{"n":1,"text":"e\xcc\x81/~\\r\\n","null":null}]'


class ProductPayloadCopyTests(unittest.TestCase):
    def host(self, path, parts):
        fixture = file_fixture.ProductPayloadFileTests()
        self.addCleanup(fixture.doCleanups)
        host, core, held, calls = fixture.host(path)
        host._acquire_original_payload_file(held)
        host._stage_original_payload_file(held)
        previous = core._call
        chunks, produced, faults = {}, set(), {}
        remaining = list(parts)
        def call(family, name, *args):
            if family == 'payload_request' and name == 'start_replay':
                self.assertEqual(args[0], held.request.handle)
                return 0
            if family == 'buffer' and name == 'byte' and args[0] in chunks:
                return chunks[args[0]][1][args[1]]
            if family != 'payload_chunk': return previous(family, name, *args)
            calls.append((family, name, args))
            if name in faults: return faults[name]
            if name == 'reserve':
                self.assertEqual(args[0], held.request.handle)
                self.assertFalse(chunks, 'A second chunk replaced original custody')
                self.assertTrue(remaining, 'EOF was replayed')
                handle = 100 + args[1]
                chunks[handle] = (args[1], remaining.pop(0))
                return handle
            if name == 'produce':
                produced.add(args[0])
                return 0
            ticket, data = chunks[args[0]]
            self.assertIn(args[0], produced)
            if name == 'length': return len(data)
            if name == 'final': return int(not remaining)
            if name == 'close':
                del chunks[args[0]]
                return core._cleanup(ticket)
            return 0
        core._call = original_byte_fixture_port(call)
        return host, core, held, calls, faults

    def test_short_write_keeps_original_chunk_and_offset_without_replaying_source(self):
        with TemporaryDirectory(prefix='actql-payload-copy-') as directory:
            host, core, held, calls, _ = self.host(Path(directory), [PAYLOAD[:10], PAYLOAD[10:]])
            before = len(calls)
            write = os.write
            def short(descriptor, data): return write(descriptor, data[:2])
            with patch('actql_sdk._local_files.os.write', side_effect=short):
                self.assertFalse(host._advance_original_payload_copy(held))
                chunk = held.chunk
                self.assertEqual(held.chunk_offset, 2)
                self.assertIs(core._loans[chunk.ticket], chunk)
                for _ in range(len(PAYLOAD)):
                    if host._advance_original_payload_copy(held): break
                else: self.fail('Original bounded copy did not reach Core EOF')
            physical = held.physical
            self.assertEqual(physical.written, len(PAYLOAD))
            self.assertEqual((Path(directory) / 'source' / 'results' / physical.name).read_bytes(), PAYLOAD)
            # The typed final chunk remains the original EOF evidence until
            # sealing/cleanup; a Python completion flag cannot replace it.
            self.assertIs(core._loans[held.chunk.ticket], held.chunk)
            self.assertEqual(sum(f == 'payload_chunk' and n == 'reserve' for f, n, _ in calls[before:]), 2)
            self.assertFalse(any(f in ('source', 'task', 'publication') for f, _, _ in calls[before:]))
            capacity = held.capacity
            self.assertTrue(host.close())
            self.assertEqual(capacity.reserved_bytes, held.maximum)

    def test_lost_write_reply_keeps_same_chunk_and_unknown_file_without_second_write(self):
        with TemporaryDirectory(prefix='actql-payload-copy-') as directory:
            host, _, held, _, _ = self.host(Path(directory), [PAYLOAD])
            write = os.write
            def lose(descriptor, data):
                write(descriptor, data)
                raise OSError('original payload append reply lost')
            with patch('actql_sdk._local_files.os.write', side_effect=lose) as writes:
                with self.assertRaisesRegex(OSError, 'reply lost'):
                    host._advance_original_payload_copy(held)
                chunk, physical, capacity = held.chunk, held.physical, held.capacity
                with self.assertRaises(LocalFileError): host._advance_original_payload_copy(held)
                self.assertEqual(writes.call_count, 1)
            self.assertIs(held.chunk, chunk)
            self.assertIs(held.capacity, capacity)
            self.assertTrue(physical.write_unknown)
            self.assertEqual((Path(directory) / 'source' / 'results' / physical.name).read_bytes(), PAYLOAD)
            self.assertTrue(host.close())

    def test_chunk_cleanup_failure_keeps_same_loan_and_never_repeats_completed_append(self):
        with TemporaryDirectory(prefix='actql-payload-copy-') as directory:
            host, core, held, calls, faults = self.host(Path(directory), [PAYLOAD, b''])
            faults['close'] = -9
            with self.assertRaises(LocalProductCleanupPending): host._advance_original_payload_copy(held)
            chunk, physical, capacity = held.chunk, held.physical, held.capacity
            self.assertFalse(host.close())
            self.assertIs(core._loans[chunk.ticket], chunk)
            self.assertIs(held.physical, physical)
            self.assertIs(held.capacity, capacity)
            # Closing forbids new copy work. Original cleanup retries the same
            # output loan and never infers Store ACK or payload reclamation.
            faults.clear()
            with patch('actql_sdk._local_files.os.write', side_effect=AssertionError('Completed append repeated')):
                self.assertTrue(host.close())
            self.assertEqual(sum(f == 'payload_chunk' and n == 'reserve' for f, n, _ in calls), 1)
            self.assertEqual((Path(directory) / 'source' / 'results' / physical.name).read_bytes(), PAYLOAD)

    def test_current_chunk_refusal_precedes_another_append_and_keeps_original_custody(self):
        with TemporaryDirectory(prefix='actql-payload-copy-') as directory:
            host, _, held, calls, faults = self.host(Path(directory), [PAYLOAD])
            write = os.write
            with patch('actql_sdk._local_files.os.write', side_effect=lambda fd, data: write(fd, data[:2])):
                self.assertFalse(host._advance_original_payload_copy(held))
            chunk, physical, capacity = held.chunk, held.physical, held.capacity
            faults['validate'] = -32
            with patch('actql_sdk._local_files.os.write', side_effect=AssertionError('Current refusal reached append')):
                with self.assertRaises(LocalCoreError) as failure:
                    host._advance_original_payload_copy(held)
            self.assertEqual(failure.exception.code, -32)
            self.assertIs(held.chunk, chunk)
            self.assertIs(held.capacity, capacity)
            self.assertEqual(physical.written, 2)
            self.assertEqual(sum(f == 'payload_chunk' and n == 'reserve' for f, n, _ in calls), 1)
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
