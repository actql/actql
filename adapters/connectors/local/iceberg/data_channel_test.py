"""Real Arrow/Parquet/Iceberg data boundaries, not replacement execution rules."""
from collections import Counter
import gc
import json
import math
from pathlib import Path
import tempfile
import unittest

import pyarrow as pa
import pyarrow.parquet as pq
from pyiceberg.catalog.sql import SqlCatalog

from physical import PhysicalRefusal, arrow_schema, decode_physical, encode_rows, iceberg_schema


def mapping():
    # The independently sealed fixture is shared with the original physical
    # acceptance; expectations below are not calculated by the encoder.
    return json.loads((Path(__file__).parent / "fixtures/presence-mapping.json").read_text())


class DataChannelTests(unittest.TestCase):
    def test_original_flat_arrow_rows_are_observed_before_native_list_constructor(self):
        contract = mapping()
        original = encode_rows(contract, [{"id": 1, "p": "e\u0301\r\n"}, {"id": 2}])
        entered = []
        class OriginalRowCall:
            # Explicit call-count port around the SAME real Arrow Table. No
            # replacement rows, schema inference or resource proof is supplied.
            schema = original.schema
            nbytes = original.nbytes
            num_rows = original.num_rows
            num_columns = original.num_columns
            def to_pylist(self):
                entered.append(True)
                return original.to_pylist()
        primary = RuntimeError("OriginalRowMaterialRefusal")
        observed = []
        def refuse(geometry):
            observed.append(dict(geometry))
            raise primary
        with self.assertRaises(RuntimeError) as failed:
            decode_physical(contract, OriginalRowCall(), before_materialization=refuse)
        self.assertIs(failed.exception, primary)
        self.assertEqual(entered, [])
        self.assertEqual(observed, [{"phase": "arrow-rows", "bytes": original.nbytes,
                                    "rows": 2, "columns": 3}])

    def test_original_typed_empty_arrow_has_zero_geometry_without_fake_eos(self):
        original = encode_rows(mapping(), [])
        seen = []
        self.assertEqual(decode_physical(mapping(), original,
                                        before_materialization=lambda value: seen.append(dict(value))), [])
        self.assertEqual(seen, [{"phase": "arrow-rows", "bytes": 0, "rows": 0, "columns": 3}])
        self.assertEqual(original.schema, arrow_schema(mapping()))

    def test_binary64_negative_zero_and_exact_integer_boundary(self):
        contract = mapping()
        rows = [{"id": -0.0}, {"id": 9007199254740992}, {"id": -2.5}]
        with tempfile.TemporaryDirectory(prefix="actql-data-numeric-") as root:
            path = Path(root) / "data.parquet"
            pq.write_table(encode_rows(contract, rows), path)
            actual = decode_physical(contract, pq.read_table(path))
            self.assertEqual(actual, rows)
            self.assertEqual(math.copysign(1, actual[0]["id"]), -1)
        for value in (9007199254740993, True, math.inf, -math.inf, math.nan):
            with self.subTest(value=value), self.assertRaises(PhysicalRefusal):
                encode_rows(contract, [{"id": value}])

    def test_chunk_boundaries_and_empty_chunks_do_not_create_eos_or_rows(self):
        contract = mapping()
        schema = arrow_schema(contract)
        # Empty physical chunks are not a semantic end-of-stream marker.
        table = pa.Table.from_arrays([
            pa.chunked_array([[], [1.0, 2.0], [], [3.0, 3.0], []], type=pa.float64()),
            pa.chunked_array([[], ["e\u0301\r\n", None], [], [None, None], []], type=pa.string()),
            pa.chunked_array([[], [True, True], [], [False, False], []], type=pa.bool_()),
        ], schema=schema)
        self.assertEqual(table.column(0).num_chunks, 5)
        expected = [{"id": 1, "p": "e\u0301\r\n"}, {"id": 2, "p": None},
                    {"id": 3}, {"id": 3}]
        self.assertEqual(decode_physical(contract, table), expected)
        self.assertEqual(decode_physical(contract, table.combine_chunks()), expected)
        self.assertEqual(decode_physical(contract, table.slice(0, 0)), [])
        self.assertEqual(table.slice(0, 0).schema, schema)

    def test_arrow_borrow_keeps_original_backing_without_claiming_release(self):
        contract = mapping()
        producer = encode_rows(contract, [{"id": 1, "p": "first"}, {"id": 2}])
        original_buffer = producer.column("id").chunk(0).buffers()[1]
        address, size = original_buffer.address, original_buffer.size
        borrowed = producer.slice(1, 1)
        self.assertEqual(borrowed.column("id").chunk(0).buffers()[1].address,
                         address)
        del original_buffer, producer
        gc.collect()
        # A live borrower remains valid; GC opportunity is not physical cleanup
        # acknowledgement or proof that an admitted reservation can be returned.
        self.assertEqual(decode_physical(contract, borrowed), [{"id": 2}])
        self.assertEqual(borrowed.column("id").chunk(0).buffers()[1].address, address)
        self.assertGreaterEqual(size, 16)

    def test_parquet_field_ids_types_and_presence_are_not_defaulted(self):
        contract = mapping()
        table = encode_rows(contract, [{"id": 1}, {"id": 2, "p": None}])
        wrong_type = pa.Table.from_arrays([
            pa.array([1, 2], type=pa.int64()), table.column("p"),
            table.column("__actql_presence_3")], schema=pa.schema([
                pa.field("id", pa.int64(), metadata={b"PARQUET:field_id": b"1"}),
                table.schema.field("p"), table.schema.field("__actql_presence_3")]))
        with self.assertRaisesRegex(PhysicalRefusal, "PhysicalFieldType"):
            decode_physical(contract, wrong_type)
        for missing in ("p", "__actql_presence_3"):
            with self.subTest(missing=missing), self.assertRaisesRegex(
                    PhysicalRefusal, "PhysicalFieldMissing"):
                decode_physical(contract, table.drop([missing]))
        for presence, value in ((None, None), (False, "not-absent")):
            invalid = pa.Table.from_pylist([{"id": 1, "p": value,
                "__actql_presence_3": presence}], schema=arrow_schema(contract))
            with self.assertRaises(PhysicalRefusal):
                decode_physical(contract, invalid)

    def test_real_iceberg_multiple_files_preserve_bag_not_file_order(self):
        contract = mapping()
        rows = [{"id": 1, "p": "e\u0301\r\n"}, {"id": 2, "p": None},
                {"id": 3}, {"id": 3}]
        # The declared physical column is binary64, not a Python int column.
        # These independent physical expectations are not product projections.
        expected = [{"id": 1.0, "p": "e\u0301\r\n"}, {"id": 2.0, "p": None},
                    {"id": 3.0}, {"id": 3.0}]
        with tempfile.TemporaryDirectory(prefix="actql-data-iceberg-") as root:
            catalog = SqlCatalog("data", uri=f"sqlite:///{root}/catalog.db",
                                 warehouse=f"file://{root}/warehouse")
            try:
                catalog.create_namespace("data")
                table = catalog.create_table(("data", "rows"), iceberg_schema(contract))
                table.append(encode_rows(contract, rows[:2]))
                table.append(encode_rows(contract, rows[2:]))
                files = list(table.scan().plan_files())
                self.assertEqual(len(files), 2)
                actual = [row for task in files for row in
                          decode_physical(contract, pq.read_table(task.file.file_path))]
                bag = lambda values: Counter(json.dumps(value, ensure_ascii=False,
                    sort_keys=True) for value in values)
                self.assertTrue(all(type(row["id"]) is float for row in actual))
                self.assertEqual(bag(actual), bag(expected))
                self.assertEqual(table.schema(), iceberg_schema(contract))
            finally:
                catalog.close()


if __name__ == "__main__":
    unittest.main()
