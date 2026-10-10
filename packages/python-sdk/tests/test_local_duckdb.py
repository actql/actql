"""Fixed boundary counterexamples; these do not establish public Local runs."""
import copy
import ctypes as C
from pathlib import Path
from threading import Lock
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from actql_sdk._local_duckdb import (
    DuckDBConnection, DuckDBLibrary, DuckDBPhysicalError, DuckDBStream,
    DuckDBTransferLimits, _RowWriter,
)


class PhysicalDuckDBTests(unittest.TestCase):
    def connection(self):
        api = SimpleNamespace(duckdb_destroy_prepare=Mock(),
            duckdb_destroy_data_chunk=Mock(), duckdb_destroy_result=Mock(),
            duckdb_disconnect=Mock(), duckdb_close=Mock())
        owner = DuckDBConnection.__new__(DuckDBConnection)
        owner._identity = owner
        owner._api = api
        owner._io = Lock()
        owner._lifetime = Lock()
        owner._streams = set()
        owner._connection = C.c_void_p()
        owner._database = C.c_void_p()
        owner._config = C.c_void_p()
        owner._open_error = C.c_void_p()
        owner._closing = False
        owner._closed = False
        return owner

    def stream(self):
        owner = self.connection()
        stream = DuckDBStream(owner, DuckDBTransferLimits())
        owner._streams.add(stream)
        return stream

    def test_scalar_limits_reject_boolean_negative_and_overflow(self):
        for settings in ({'max_rows': True}, {'max_rows': -1},
                         {'max_rows': 2**63}, {'max_columns': 1025},
                         {'max_cell_bytes': 1048577}, {'max_row_bytes': 1}):
            with self.subTest(settings=settings), self.assertRaises(ValueError):
                DuckDBTransferLimits(**settings)

    def test_digest_refused_before_native_loader(self):
        with patch.object(Path, 'open') as opened, patch('ctypes.CDLL') as load:
            opened.return_value.__enter__.return_value.read.side_effect = [b'bad', b'']
            with self.assertRaisesRegex(ValueError, 'digest'):
                DuckDBLibrary(Path('component'), digest='0' * 64, version='v1.5.5')
            load.assert_not_called()

    def test_native_cell_limit_precedes_pointer_read(self):
        destination = bytearray(32)
        writer = _RowWriter(destination, 32)
        with patch.object(C.c_ubyte, 'from_address', side_effect=AssertionError('Copied oversized cell')):
            with self.assertRaisesRegex(DuckDBPhysicalError, 'cell capacity'):
                writer.string(1, 65, 64)
        self.assertEqual(destination, bytearray(32))

    def test_raw_unicode_null_and_control_bytes_have_fixed_json(self):
        raw = 'e\u0301\r\n\0"\\😀'.encode('utf8')
        native = C.create_string_buffer(raw)
        destination = bytearray(128)
        writer = _RowWriter(destination, 128)
        writer.string(C.addressof(native), len(raw), 128)
        self.assertEqual(bytes(destination[:writer.position]),
            b'"e\xcc\x81\\u000d\\u000a\\u0000\\"\\\\\xf0\x9f\x98\x80"')

    def test_escaped_expansion_cannot_grow_destination(self):
        native = C.create_string_buffer(b'\0\0\0')
        destination = bytearray(8)
        with self.assertRaisesRegex(DuckDBPhysicalError, 'row capacity'):
            _RowWriter(destination, 8).string(C.addressof(native), 3, 8)
        self.assertEqual(len(destination), 8)

    def test_only_owned_mutable_bounded_destination_is_accepted(self):
        for value in (b'[]', memoryview(bytearray(8)), bytearray(1), bytearray(17)):
            with self.subTest(kind=type(value)), self.assertRaises(ValueError):
                _RowWriter(value, 16)

    def test_callback_operation_keeps_same_handles_until_close_can_enter(self):
        stream = self.stream()
        stream._statement.value = 17
        stream._owner._io.acquire()
        try:
            self.assertFalse(stream.close())
            self.assertFalse(stream._owner.close())
            self.assertEqual(stream._statement.value, 17)
            stream._api.duckdb_destroy_prepare.assert_not_called()
        finally:
            stream._owner._io.release()
        self.assertTrue(stream.close())
        self.assertTrue(stream._owner.close())

    def test_cleanup_failure_retains_exact_stream_and_parent(self):
        stream = self.stream()
        stream._result_created = True
        stream._api.duckdb_destroy_result.side_effect = [OSError('close failed'), None]
        with self.assertRaises(OSError):
            stream.close()
        self.assertIn(stream, stream._owner._streams)
        self.assertTrue(stream._result_created)
        self.assertFalse(stream._owner.close())
        self.assertTrue(stream.close())
        self.assertEqual(stream._api.duckdb_destroy_result.call_count, 2)
        self.assertTrue(stream._owner.close())
        self.assertTrue(stream.close())
        self.assertEqual(stream._api.duckdb_destroy_result.call_count, 2)

    def test_copied_handles_cannot_execute_interrupt_or_close(self):
        stream = self.stream()
        other = copy.copy(stream)
        for action in (other.execute, other.close, copy.copy(stream._owner).interrupt,
                       copy.copy(stream._owner).close):
            with self.assertRaisesRegex(ValueError, 'Foreign'):
                action()
        self.assertIn(stream, stream._owner._streams)

    def test_failed_execution_cannot_be_repeated(self):
        stream = self.stream()
        stream._api.duckdb_execute_prepared_streaming = Mock(return_value=1)
        with self.assertRaisesRegex(DuckDBPhysicalError, 'physical execution'):
            stream.execute()
        with self.assertRaisesRegex(DuckDBPhysicalError, 'cannot execute'):
            stream.execute()
        stream._api.duckdb_execute_prepared_streaming.assert_called_once()
        self.assertTrue(stream._result_created)
        self.assertTrue(stream.close())


if __name__ == '__main__':
    unittest.main()
