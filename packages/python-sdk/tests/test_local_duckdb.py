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
    DuckDBTransferLimits, DuckDBParameter, _RowWriter, _bounded_utf8,
)


class PhysicalDuckDBTests(unittest.TestCase):
    def test_utf8_copy_is_bounded_without_normalization_or_replacement(self):
        self.assertEqual(_bounded_utf8('e\u0301\r\n😀', 9), b'e\xcc\x81\r\n\xf0\x9f\x98\x80')
        for value in ('😀😀', '\ud800', '\udfff'):
            with self.subTest(value=repr(value)), self.assertRaises(ValueError):
                _bounded_utf8(value, 4)

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
        owner._read_view = None
        owner._connection = C.c_void_p()
        owner._database = C.c_void_p()
        owner._config = C.c_void_p()
        owner._open_error = C.c_void_p()
        owner._closing = False
        owner._closed = False
        return owner

    def test_stop_observation_seals_admission_without_interrupting_live_io(self):
        owner = self.connection()
        owner._api.duckdb_interrupt = Mock()
        owner._api.duckdb_prepare = Mock()
        owner._io.acquire()
        try:
            self.assertFalse(owner.stop_new_io())
            self.assertTrue(owner._closing)
            owner._api.duckdb_interrupt.assert_not_called()
        finally:
            owner._io.release()
        self.assertTrue(owner.stop_new_io())
        with self.assertRaises(DuckDBPhysicalError):
            owner.prepare('SELECT 1', DuckDBTransferLimits())
        owner._api.duckdb_prepare.assert_not_called()
        self.assertTrue(owner.close())

    def read_view(self):
        owner = self.connection()
        owner._connection.value = 41
        owner._api.duckdb_query = Mock(return_value=0)
        return owner, owner.begin_read_view()

    def test_read_view_settlement_requires_successful_commit_and_closed_streams(self):
        owner, view = self.read_view()
        self.assertFalse(view.committed)
        stream = DuckDBStream(owner, DuckDBTransferLimits())
        owner._streams.add(stream)
        with self.assertRaises(DuckDBPhysicalError):
            view.commit()
        self.assertFalse(view.close())
        self.assertEqual(owner._api.duckdb_query.call_count, 1)
        self.assertTrue(stream.close())
        view.commit()
        self.assertTrue(view.committed)
        with self.assertRaises(DuckDBPhysicalError):
            view.commit()
        self.assertTrue(view.close())
        self.assertTrue(view.close())
        self.assertEqual([call.args[1] for call in owner._api.duckdb_query.call_args_list],
                         [b'BEGIN TRANSACTION', b'COMMIT'])

    def test_abandoned_read_view_rolls_back_without_settlement(self):
        owner, view = self.read_view()
        self.assertTrue(view.close())
        self.assertFalse(view.committed)
        self.assertEqual([call.args[1] for call in owner._api.duckdb_query.call_args_list],
                         [b'BEGIN TRANSACTION', b'ROLLBACK'])
        self.assertTrue(owner.close())

    def test_unknown_commit_is_not_replayed_or_settlement(self):
        owner, view = self.read_view()
        owner._api.duckdb_query.side_effect = OSError('reply lost')
        with self.assertRaises(OSError) as failure:
            view.commit()
        self.assertIs(failure.exception.physical_cleanup, view)
        self.assertFalse(view.committed)
        self.assertFalse(owner.close())
        with self.assertRaises(DuckDBPhysicalError):
            view.commit()
        owner._api.duckdb_disconnect.side_effect = [OSError('stop pending'), None]
        with self.assertRaises(OSError):
            view.close()
        self.assertIs(owner._read_view, view)
        self.assertTrue(view.close())
        self.assertEqual(owner._api.duckdb_query.call_count, 2)
        self.assertFalse(view.committed)

    def test_observed_commit_cleanup_failure_retains_result_without_recommit(self):
        owner, view = self.read_view()
        owner._api.duckdb_destroy_result.side_effect = [OSError('cleanup pending'), None]
        with self.assertRaises(OSError) as failure:
            view.commit()
        self.assertIs(failure.exception.physical_cleanup, view)
        self.assertTrue(view.committed)
        self.assertTrue(view._result_created)
        self.assertFalse(owner.close())
        self.assertIs(owner._read_view, view)
        self.assertTrue(view.close())
        self.assertFalse(view._result_created)
        self.assertEqual(owner._api.duckdb_query.call_count, 2)

    def test_read_view_copy_and_callback_overlap_cannot_close_original(self):
        owner, view = self.read_view()
        with self.assertRaisesRegex(ValueError, 'Foreign'):
            copy.copy(view).close()
        owner._io.acquire()
        try:
            self.assertFalse(view.close())
            self.assertIs(owner._read_view, view)
            self.assertEqual(owner._api.duckdb_query.call_count, 1)
        finally:
            owner._io.release()
        self.assertTrue(view.close())

    def test_failed_begin_retains_original_cleanup_and_never_retries_begin(self):
        owner = self.connection()
        owner._connection.value = 41
        owner._api.duckdb_query = Mock(return_value=1)
        with self.assertRaises(DuckDBPhysicalError) as failure:
            owner.begin_read_view()
        view = failure.exception.physical_cleanup
        self.assertIs(owner._read_view, view)
        self.assertFalse(view.committed)
        self.assertFalse(owner.close())
        with self.assertRaises(DuckDBPhysicalError):
            owner.begin_read_view()
        self.assertTrue(view.close())
        self.assertEqual(owner._api.duckdb_query.call_count, 1)

    def test_failed_rollback_teardown_does_not_repeat_control_io(self):
        owner, view = self.read_view()
        owner._api.duckdb_query.return_value = 1
        with self.assertRaises(DuckDBPhysicalError):
            view.close()
        self.assertFalse(view.committed)
        self.assertIs(owner._read_view, view)
        self.assertTrue(view.close())
        self.assertEqual(owner._api.duckdb_query.call_count, 2)

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

    def test_column_framing_uses_same_native_row_and_no_transposed_copy(self):
        stream = self.stream()
        stream._executed = True
        stream._chunk.value = 1
        stream._chunk_rows = 2
        stream._types = (5, 17)
        def cell(writer, column, kind):
            writer.put(b'"7"' if column == 0 else b'null')
        stream._cell = cell
        destination = bytearray(32)
        count = stream.read_column_row(destination)
        self.assertEqual(bytes(destination[:count]), b'[["7"],[null]]')
        self.assertEqual(stream._read_rows, 1)
        count = stream.read_row(destination)
        self.assertEqual(bytes(destination[:count]), b'["7",null]')
        self.assertEqual(stream._read_rows, 2)
        self.assertEqual(stream._row, 2)

    def test_column_capacity_failure_retains_stream_without_row_retry(self):
        stream = self.stream()
        stream._executed = True
        stream._chunk.value = 17
        stream._chunk_rows = 1
        stream._types = (5,)
        stream._cell = lambda writer, column, kind: writer.put(b'"7"')
        with self.assertRaisesRegex(DuckDBPhysicalError, 'row capacity'):
            stream.read_column_row(bytearray(6))
        self.assertTrue(stream._failed)
        self.assertEqual(stream._read_rows, 0)
        self.assertEqual(stream._chunk.value, 17)
        with self.assertRaisesRegex(DuckDBPhysicalError, 'cannot read'):
            stream.read_row(bytearray(32))
        self.assertFalse(stream._owner.close())
        self.assertTrue(stream.close())
        self.assertTrue(stream._owner.close())

    def parameter_connection(self, count=1):
        owner = self.connection()
        def prepare(connection, text, statement):
            statement._obj.value = 19
            return 0
        owner._api.duckdb_prepare = Mock(side_effect=prepare)
        owner._api.duckdb_nparams = Mock(return_value=count)
        owner._api.duckdb_bind_null = Mock(return_value=0)
        owner._api.duckdb_bind_boolean = Mock(return_value=0)
        owner._api.duckdb_bind_double = Mock(return_value=0)
        owner._api.duckdb_bind_varchar_length = Mock(return_value=0)
        owner._api.duckdb_execute_prepared_streaming = Mock()
        return owner

    def test_parameter_payload_refusal_precedes_native_prepare_and_execute(self):
        bad = [DuckDBParameter('DOUBLE', True), DuckDBParameter('DOUBLE', 'NaN'),
               DuckDBParameter('DOUBLE', '7ff0000000000000'),
               DuckDBParameter('DOUBLE', '7ff8000000000000'),
               DuckDBParameter('BOOLEAN', 'true'), DuckDBParameter('VARCHAR', False),
               DuckDBParameter('VARCHAR', '\ud800'), DuckDBParameter('DATE', '1')]
        for parameter in bad:
            owner = self.parameter_connection()
            with self.subTest(parameter=parameter), self.assertRaises(ValueError):
                owner.prepare('SELECT ?', DuckDBTransferLimits(), parameters=(parameter,))
            owner._api.duckdb_prepare.assert_not_called()
            owner._api.duckdb_execute_prepared_streaming.assert_not_called()
            self.assertEqual(owner._streams, set())

    def test_parameter_count_mismatch_does_not_execute_or_leave_success(self):
        owner = self.parameter_connection(count=2)
        with self.assertRaisesRegex(DuckDBPhysicalError, 'count mismatch'):
            owner.prepare('SELECT ?, ?', DuckDBTransferLimits(),
                          parameters=(DuckDBParameter('VARCHAR', None),))
        owner._api.duckdb_execute_prepared_streaming.assert_not_called()
        owner._api.duckdb_bind_null.assert_not_called()
        self.assertEqual(owner._streams, set())
        owner._api.duckdb_destroy_prepare.assert_called_once()

    def test_parameter_utf8_total_refusal_precedes_excess_copy(self):
        owner = self.parameter_connection(count=2)
        with patch('actql_sdk._local_duckdb._bounded_utf8', wraps=_bounded_utf8) as bounded:
            with self.assertRaises(ValueError):
                owner.prepare('SELECT ?, ?', DuckDBTransferLimits(max_cell_bytes=8, max_row_bytes=4),
                    parameters=(DuckDBParameter('VARCHAR', 'e\u0301'), DuckDBParameter('VARCHAR', '😀')))
            self.assertEqual(bounded.call_args.args, ('😀', 1))
        owner._api.duckdb_prepare.assert_not_called()

    def test_failed_binding_cleanup_retains_same_statement_for_retry(self):
        owner = self.parameter_connection()
        owner._api.duckdb_bind_double.return_value = 1
        owner._api.duckdb_destroy_prepare.side_effect = [RuntimeError('cleanup failed'), None]
        with self.assertRaisesRegex(DuckDBPhysicalError, 'binding failed') as caught:
            owner.prepare('SELECT ?', DuckDBTransferLimits(),
                          parameters=(DuckDBParameter('DOUBLE', '8000000000000000'),))
        stream = caught.exception.physical_cleanup
        self.assertIn(stream, owner._streams)
        self.assertEqual(stream._statement.value, 19)
        owner._api.duckdb_execute_prepared_streaming.assert_not_called()
        self.assertFalse(owner.close())
        self.assertTrue(stream.close())
        self.assertTrue(owner.close())


if __name__ == '__main__':
    unittest.main()
