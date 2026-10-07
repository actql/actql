import tempfile
import unittest
import json
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq
from pyiceberg.catalog.sql import SqlCatalog

from physical import (PhysicalRefusal, arrow_schema, check_mapping,
                      decode_physical, encode_rows, iceberg_schema, seal)


def mapping():
    # Authored independently; its seal was calculated by a standalone Node
    # SHA-256 encoder, not by the Python implementation under test.
    return json.loads((Path(__file__).parent / "fixtures/presence-mapping.json").read_text())


class PhysicalTests(unittest.TestCase):
    def test_three_states_duplicates_and_original_unicode(self):
        contract = mapping()
        rows = [{"id": 1, "p": "e\u0301\r\n"}, {"id": 2, "p": None},
                {"id": 3}, {"id": 3}]
        with tempfile.TemporaryDirectory(prefix="actql-table-physical-") as root:
            path = Path(root) / "rows.parquet"
            pq.write_table(encode_rows(contract, rows), path)
            self.assertEqual(decode_physical(contract, pq.read_table(path)), rows)

    def test_real_iceberg_files_have_bound_ids_and_zero_rows_keep_schema(self):
        contract = mapping()
        rows = [{"id": 1, "p": "value"}, {"id": 2, "p": None}, {"id": 3}]
        with tempfile.TemporaryDirectory(prefix="actql-table-iceberg-") as root:
            catalog = SqlCatalog("physical", uri=f"sqlite:///{root}/catalog.db", warehouse=f"file://{root}/warehouse")
            catalog.create_namespace("test")
            table = catalog.create_table(("test", "rows"), iceberg_schema(contract))
            table.append(encode_rows(contract, rows))
            tasks = list(table.scan().plan_files())
            self.assertEqual(len(tasks), 1)
            raw = pq.read_table(tasks[0].file.file_path)
            self.assertEqual(decode_physical(contract, raw), rows)
            empty = catalog.create_table(("test", "empty"), iceberg_schema(contract))
            self.assertEqual(list(empty.scan().plan_files()), [])
            self.assertEqual(empty.schema(), iceberg_schema(contract))
            self.assertIsNone(empty.current_snapshot())
            catalog.close()

    def test_corrupt_presence_cannot_be_repaired_by_defaults(self):
        contract = mapping()
        schema = arrow_schema(contract)
        for row in [{"id": 1, "p": None, "__actql_presence_3": None},
                    {"id": 1, "p": "value", "__actql_presence_3": False}]:
            with self.assertRaises(PhysicalRefusal):
                decode_physical(contract, pa.Table.from_pylist([row], schema=schema))
        raw = encode_rows(contract, [{"id": 1}])
        for omitted in ["p", "__actql_presence_3"]:
            with self.assertRaisesRegex(PhysicalRefusal, "PhysicalFieldMissing"):
                decode_physical(contract, raw.drop([omitted]))
        with self.assertRaisesRegex(PhysicalRefusal, "PhysicalFieldId"):
            decode_physical(contract, raw.cast(pa.schema([pa.field(f.name, f.type) for f in schema])))

    def test_prewrite_refusal(self):
        contract = mapping()
        for row in [{"p": None}, {"id": None}, {"id": True}, {"id": 1, "p": ["nested"]},
                    {"id": 1, "p": "\ud800"}, {"id": float("inf")}, {"id": 10**400}]:
            with self.assertRaises(PhysicalRefusal):
                encode_rows(contract, [row])
        for field, value in [("name", "__actql_presence_3"), ("physical_type", "struct"),
                             ("presence_field_id", 1), ("presence_field_id", None)]:
            body = {k: v for k, v in mapping().items() if k != "mapping_cid"}
            body["columns"][1][field] = value
            with self.assertRaises(PhysicalRefusal):
                check_mapping(seal(body, "mapping_cid"))
        body = {k: v for k, v in mapping().items() if k != "mapping_cid"}
        body["columns"][1]["presence_field_id"] = 9
        with self.assertRaisesRegex(PhysicalRefusal, "UnsupportedFieldIdLayout"):
            check_mapping(seal(body, "mapping_cid"))

    def test_conditional_nonnullable_is_not_required(self):
        body = {k: v for k, v in mapping().items() if k != "mapping_cid"}
        body["columns"][1]["nullable"] = False
        contract = seal(body, "mapping_cid")
        raw = encode_rows(contract, [{"id": 1}])
        self.assertEqual(decode_physical(contract, raw), [{"id": 1}])
        with self.assertRaisesRegex(PhysicalRefusal, "NonnullableValue"):
            encode_rows(contract, [{"id": 1, "p": None}])


if __name__ == "__main__":
    unittest.main()
