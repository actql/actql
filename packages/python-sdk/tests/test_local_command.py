"""Independent physical codec cases, not Run or Source admission."""
from dataclasses import FrozenInstanceError
import unittest

from actql_sdk._errors import ClientError
from actql_sdk._local_command import native_command
from actql_sdk._local_duckdb import DuckDBParameter


class NativeCommandTests(unittest.TestCase):
    def test_fixed_native_projection_preserves_sql_bits_unicode_and_null(self):
        raw = (b'{"sql":"SELECT ?, ?, ?, ? /*e\xcc\x81\\r\\n\xf0\x9f\x98\x80*/",'
               b'"parameters":[{"type":{"id":"DOUBLE"},"value":"8000000000000000"},'
               b'{"type":{"id":"VARCHAR"},"value":"e\xcc\x81\\r\\n\\u0000\xf0\x9f\x98\x80"},'
               b'{"type":{"id":"BOOLEAN"},"value":false},'
               b'{"type":{"id":"VARCHAR"},"value":null}]}')
        command = native_command(raw)
        self.assertEqual(command.sql, 'SELECT ?, ?, ?, ? /*é\r\n😀*/')
        self.assertEqual(command.parameters, (
            DuckDBParameter('DOUBLE', '8000000000000000'),
            DuckDBParameter('VARCHAR', 'é\r\n\0😀'),
            DuckDBParameter('BOOLEAN', False), DuckDBParameter('VARCHAR', None)))
        with self.assertRaises(FrozenInstanceError):
            command.sql = 'changed'

    def test_closed_shapes_absent_null_and_unsupported_bindings_are_not_repaired(self):
        cases = [b'{}', b'{"sql":"SELECT 1","parameters":null}',
                 b'{"sql":"SELECT 1","parameters":[],"unknown":true}',
                 b'{"sql":"SELECT ?","parameters":[{"type":{"id":"VARCHAR"}}]}',
                 b'{"sql":"SELECT ?","parameters":[{"type":{"id":"BOOLEAN"},"value":1}]}',
                 b'{"sql":"SELECT ?","parameters":[{"type":{"id":"DOUBLE"},"value":1.5}]}',
                 b'{"sql":"SELECT ?","parameters":[{"type":{"id":"DECIMAL"},"value":null}]}',
                 b'{"sql":"SELECT ?","parameters":[{"type":{"id":"VARCHAR","unknown":1},"value":null}]}']
        for payload in cases:
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                native_command(payload)

    def test_shared_json_admission_rejects_duplicates_invalid_utf8_and_nan(self):
        for raw in (b'{"sql":"SELECT 1","sql":"SELECT 2","parameters":[]}',
                    b'{"sql":"\xff","parameters":[]}',
                    b'{"sql":"SELECT 1","parameters":[NaN]}'):
            with self.subTest(raw=raw), self.assertRaises(ClientError):
                native_command(raw)

    def test_transfer_limit_precedes_json_admission(self):
        for payload in (b' ' * 100001, bytearray(b'{}')):
            with self.subTest(kind=type(payload)), self.assertRaises(ValueError):
                native_command(payload)


if __name__ == '__main__':
    unittest.main()
