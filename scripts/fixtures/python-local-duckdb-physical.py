"""Explicit standalone C API consumer; not public Local or wheel acceptance."""
import argparse
import ctypes as C
import hashlib
import io
import json
import platform
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk._local_duckdb import (  # noqa: E402
    DuckDBConnection, DuckDBLibrary, DuckDBPhysicalError, DuckDBTransferLimits,
)

parser = argparse.ArgumentParser()
parser.add_argument('library', type=Path)
parser.add_argument('--digest', required=True)
parser.add_argument('--version', required=True)
args = parser.parse_args()
assert subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT,
                               text=True) == '', 'Use committed physical adapter source'
library = DuckDBLibrary(args.library, digest=args.digest, version=args.version)


class StandaloneDuckDBTests(unittest.TestCase):
    def setUp(self):
        self.connection = DuckDBConnection(library, '', memory_bytes=67_108_864,
                                           readonly=False)
        self.stream = None

    def tearDown(self):
        if self.stream is not None:
            self.assertTrue(self.stream.close())
        self.assertTrue(self.connection.close())

    def query(self, sql, **limits):
        self.stream = self.connection.prepare(sql, DuckDBTransferLimits(**limits))
        self.stream.execute()
        return self.stream

    def rows(self, sql, **limits):
        stream = self.query(sql, **limits)
        destination = bytearray(limits.get('max_row_bytes', 4096))
        result = []
        while (count := stream.read_row(destination)) is not None:
            result.append(bytes(destination[:count]))
        return result

    def test_fixed_native_codec_values_and_fields(self):
        # Unicode spelling, raw line endings, embedded NULL, integer boundaries
        # and IEEE bits are independently fixed, not copied from this producer.
        rows = self.rows("SELECT '-9223372036854775808'::BIGINT AS n, "
            "18446744073709551615::UBIGINT AS u, TRUE AS flag, "
            "NULL::VARCHAR AS missing, 'é' || chr(13) || chr(10) || chr(0) || '😀' AS \"名/称~\", "
            "1.5::DOUBLE AS d, 1.5::FLOAT AS f, 12.30::DECIMAL(5,2) AS dec, "
            "'-170141183460469231731687303715884105728'::HUGEINT AS huge, "
            "340282366920938463463374607431768211455::UHUGEINT AS uhuge")
        self.assertEqual(rows, [
            b'["-9223372036854775808","18446744073709551615",true,null,'
            b'"e\xcc\x81\\u000d\\u000a\\u0000\xf0\x9f\x98\x80",'
            b'"3ff8000000000000","3fc00000","1230",'
            b'"-170141183460469231731687303715884105728",'
            b'"340282366920938463463374607431768211455"]',
        ])
        destination = bytearray(4096)
        count = self.stream.write_fields(destination)
        self.assertEqual(json.loads(bytes(destination[:count])), [
            ['n', 'BIGINT', None, None], ['u', 'UBIGINT', None, None],
            ['flag', 'BOOLEAN', None, None], ['missing', 'VARCHAR', None, None],
            ['名/称~', 'VARCHAR', None, None], ['d', 'DOUBLE', None, None],
            ['f', 'FLOAT', None, None], ['dec', 'DECIMAL', '5', '2'],
            ['huge', 'HUGEINT', None, None], ['uhuge', 'UHUGEINT', None, None],
        ])

    def test_empty_is_end_without_a_fabricated_row(self):
        self.assertEqual(self.rows('SELECT 1 AS n WHERE FALSE', max_rows=0), [])

    def test_multiple_chunks_preserve_explicit_order(self):
        rows = self.rows('SELECT i FROM range(2051) t(i) ORDER BY i DESC', max_rows=2051)
        self.assertEqual(rows, [f'["{i}"]'.encode('ascii') for i in range(2050, -1, -1)])

    def test_long_varchar_refused_before_python_cell_copy(self):
        stream = self.query("SELECT repeat('z', 65537)", max_cell_bytes=65536)
        with patch.object(C.c_ubyte, 'from_address', side_effect=AssertionError('Copied oversized cell')):
            with self.assertRaisesRegex(DuckDBPhysicalError, 'cell capacity'):
                stream.read_row(bytearray(128))
        self.assertFalse(self.connection.close())
        with self.assertRaisesRegex(DuckDBPhysicalError, 'cannot read'):
            stream.read_row(bytearray(128))

    def test_capacity_refusal_does_not_turn_partial_row_into_success(self):
        stream = self.query("SELECT 'abcdef'", max_row_bytes=4)
        destination = bytearray(4)
        with self.assertRaisesRegex(DuckDBPhysicalError, 'row capacity'):
            stream.read_row(destination)
        self.assertEqual(len(destination), 4)
        with self.assertRaisesRegex(DuckDBPhysicalError, 'cannot read'):
            stream.read_row(destination)

    def test_row_limit_does_not_report_end(self):
        stream = self.query('SELECT i FROM range(2) t(i) ORDER BY i', max_rows=1)
        destination = bytearray(32)
        count = stream.read_row(destination)
        self.assertEqual(bytes(destination[:count]), b'["0"]')
        with self.assertRaisesRegex(DuckDBPhysicalError, 'row count capacity'):
            stream.read_row(destination)

    def test_unsupported_physical_type_refused_before_fetch(self):
        self.stream = self.connection.prepare('SELECT [1,2]', DuckDBTransferLimits())
        with self.assertRaisesRegex(DuckDBPhysicalError, 'Unsupported'):
            self.stream.execute()

    def test_connection_cleanup_keeps_live_result_and_retries_same_handle(self):
        stream = self.query('SELECT 7 AS n')
        retained = stream._result.internal
        self.assertFalse(self.connection.close())
        actual = library.api.duckdb_destroy_result
        with patch.object(library.api, 'duckdb_destroy_result', side_effect=OSError('cleanup failure')):
            with self.assertRaises(OSError):
                stream.close()
        self.assertEqual(stream._result.internal, retained)
        self.assertIn(stream, self.connection._streams)
        with patch.object(library.api, 'duckdb_destroy_result', wraps=actual) as destroy:
            self.assertTrue(stream.close())
            self.assertTrue(stream.close())
            destroy.assert_called_once()
        self.assertTrue(self.connection.close())

    def test_canonical_settings_are_observed(self):
        rows = self.rows("SELECT current_setting('enable_external_access'), "
            "current_setting('autoinstall_known_extensions'), "
            "current_setting('autoload_known_extensions'), "
            "current_setting('allow_unsigned_extensions'), "
            "current_setting('preserve_insertion_order'), "
            "current_setting('threads'), current_setting('max_temp_directory_size'), "
            "current_setting('default_collation')")
        self.assertEqual(rows, [b'[false,false,false,false,true,"1","0 bytes","binary"]'])

    def test_readonly_source_blocks_write_physically(self):
        self.assertTrue(self.connection.close())
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / 'source.duckdb')
            self.connection = DuckDBConnection(library, path, memory_bytes=67_108_864,
                                               readonly=False)
            self.rows('CREATE TABLE source AS SELECT 2::BIGINT AS n')
            self.assertTrue(self.stream.close())
            self.assertTrue(self.connection.close())
            self.connection = DuckDBConnection(library, path, memory_bytes=67_108_864)
            self.stream = None
            self.assertEqual(self.rows('SELECT n FROM source'), [b'["2"]'])
            self.assertTrue(self.stream.close())
            self.stream = self.connection.prepare('INSERT INTO source VALUES (3)',
                                                  DuckDBTransferLimits())
            with self.assertRaisesRegex(DuckDBPhysicalError, 'physical execution'):
                self.stream.execute()
            self.assertTrue(self.stream.close())
            self.assertEqual(self.rows('SELECT n FROM source'), [b'["2"]'])
            self.assertTrue(self.stream.close())
            self.assertTrue(self.connection.close())


output = io.StringIO()
result = unittest.TextTestRunner(stream=output, verbosity=2).run(
    unittest.defaultTestLoader.loadTestsFromTestCase(StandaloneDuckDBTests))
sys.stderr.write(output.getvalue())
source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
print(json.dumps({'source_sha': source, 'library': str(args.library),
    'library_sha256': args.digest, 'library_version': args.version,
    'python': sys.version, 'platform': platform.platform(),
    'machine': platform.machine(), 'tests': result.testsRun, 'success': result.wasSuccessful(),
    'public_local_acceptance': False, 'wheel_acceptance': False}))
sys.exit(0 if result.wasSuccessful() and result.testsRun == 10 else 1)
