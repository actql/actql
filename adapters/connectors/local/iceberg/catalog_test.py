import tempfile
import unittest
import sqlite3
import hashlib
import gzip
import json
import math
import re
import pyarrow as pa
from contextlib import closing
from unittest.mock import patch
import pyarrow.parquet as pq
from pyiceberg.serializers import FromByteStream
from pyiceberg import manifest as manifest_module
from pyiceberg.avro import file as avro_file_module
from pyiceberg.avro.codecs.deflate import DeflateCodec
from pathlib import Path

from catalog import CatalogRefusal, TableCatalog, _parquet_thrift_limits
import catalog as catalog_module
from physical import seal, PhysicalRefusal, canonical_envelope
from physical_test import mapping, schema_wire


def request(action, name, suffix, expected=None):
    return seal({"version": "actql-table-operation/0.1",
                 "logical_request_scope_cid": "sha256:" + suffix * 64,
                 "effect_identity_cid": "sha256:" + "2" * 64,
                 "action": action, "catalog_identity_cid": "sha256:" + "3" * 64,
                 "namespace": ["test"], "table_name": name,
                 "expected_table": expected,
                 "input_artifact_cid": "sha256:" + "4" * 64,
                 "input_carrier": {"kind": "relation", "cid": "sha256:" + "5" * 64},
                 "schema_cid": mapping()["schema_cid"],
                 "storage_mapping_cid": mapping()["mapping_cid"],
                 "data_policy_cid": "sha256:" + "6" * 64}, "request_cid")


def expected(receipt):
    return {"table_uuid": receipt["table_uuid"], "generation_cid": receipt["generation_cid"]}


class LostReplyCatalog(TableCatalog):
    def after_publication(self):
        raise ConnectionError("CommitReplyLost")


class CatalogTests(unittest.TestCase):
    def open(self, root, cls=TableCatalog):
        return cls(Path(root) / "catalog.db", Path(root) / "warehouse", "sha256:" + "3" * 64,
                   {"bytes": 16777216, "files": 256, "operations": 32})

    def write(self, catalog, operation, rows, reservation=None):
        return catalog.write_claimed(operation, mapping(), rows,
                                     reservation or {"bytes": 1048576, "files": 16}, schema_wire())

    def test_same_read_observes_parquet_and_row_material_before_original_constructors(self):
        # Fresh authored physical fixture, retained even on an assertion failure.
        # This supplies no Program, authorization, Run or parent reservation.
        root = tempfile.mkdtemp(prefix="actql-table-construction-")
        print("Retained physical constructor fixture:", root)
        catalog = self.open(root)
        observed = []
        before = lambda geometry: observed.append(dict(geometry))
        catalog.before_materialization = before
        rows = [{"id": 1, "p": "e\u0301\r\n"}, {"id": 2}, {"id": 3, "p": None}]
        try:
            catalog.create_namespace("test")
            receipt = self.write(catalog, request("create", "constructor_rows", "c"), rows)
            # Select only the read's original material, separately from setup.
            observed.clear()
            read_table = pq.read_table
            read_file = pq.ParquetFile.read
            entries = []
            def check_before_data():
                self.assertIn("parquet-read", [value["phase"] for value in observed],
                              "the original Arrow constructor ran without its before-call geometry")
                entries.append(True)
            def original_table(*args, **kwargs):
                check_before_data()
                return read_table(*args, **kwargs)
            def original_file(owner, *args, **kwargs):
                check_before_data()
                return read_file(owner, *args, **kwargs)
            with patch.object(pq, "read_table", original_table), patch.object(pq.ParquetFile, "read", original_file):
                actual = catalog.read_generation(receipt, mapping())
            self.assertEqual(actual, rows)
            self.assertTrue(entries)
            phases = [value["phase"] for value in observed]
            self.assertLess(phases.index("parquet-footer"), phases.index("parquet-read"))
            self.assertLess(phases.index("parquet-read"), phases.index("arrow-rows"))
            material = next(value for value in observed if value["phase"] == "arrow-rows")
            self.assertEqual((material["rows"], material["columns"]), (3, 3))
            self.assertGreater(material["bytes"], 0)
        finally:
            catalog.engine.dispose()

    def test_original_constructor_refusal_precedes_data_read_and_preserves_cause(self):
        for phase in ("parquet-footer", "parquet-read"):
            with self.subTest(phase=phase):
                root = tempfile.mkdtemp(prefix="actql-table-constructor-refusal-")
                print("Retained physical refusal fixture:", root)
                writer = self.open(root)
                try:
                    writer.create_namespace("test")
                    receipt = self.write(writer, request("create", "rows", "d"), [{"id": 1}])
                finally:
                    writer.engine.dispose()
                primary = RuntimeError("OriginalConstructorRefusal")
                observed = []
                def before(geometry):
                    observed.append(dict(geometry))
                    if geometry["phase"] == phase:
                        raise primary
                reader = TableCatalog(Path(root) / "catalog.db", Path(root) / "warehouse",
                                      "sha256:" + "3" * 64,
                                      {"bytes": 16777216, "files": 256, "operations": 32},
                                      before_materialization=before)
                try:
                    with patch.object(pq.ParquetFile, "read", side_effect=AssertionError("unfunded data read")):
                        with self.assertRaises(RuntimeError) as failed:
                            reader.read_generation(receipt, mapping())
                    self.assertIs(failed.exception, primary)
                    self.assertEqual(observed[-1]["phase"], phase)
                finally:
                    reader.engine.dispose()

    def test_observed_original_parquet_read_preserves_binary64_bits_and_omission(self):
        root = tempfile.mkdtemp(prefix="actql-table-observed-bits-")
        print("Retained observed numeric fixture:", root)
        seen = []
        catalog = TableCatalog(Path(root) / "catalog.db", Path(root) / "warehouse",
                               "sha256:" + "3" * 64,
                               {"bytes": 16777216, "files": 256, "operations": 32})
        rows = [{"id": -0.0, "p": "e\u0301\r\n"}, {"id": 9007199254740992}, {"id": -2.5, "p": None}]
        try:
            catalog.create_namespace("test")
            receipt = self.write(catalog, request("create", "rows", "e"), rows)
            self.assertEqual(seen, [], "test publication supplies no observed read or backing evidence")
            catalog.before_materialization = lambda value: seen.append(dict(value))
            actual = catalog.read_generation(receipt, mapping())
            self.assertEqual(actual, rows)
            self.assertEqual(math.copysign(1, actual[0]["id"]), -1)
            self.assertEqual(actual[1]["id"], 9007199254740992)
            self.assertNotIn("p", actual[1])
            self.assertIsNone(actual[2]["p"])
            # This existing fixture reuses setup's immutable manifest-list
            # cache; only the data manifest is constructed in this scope.
            # The distinct cold-cache constructor case observes both files.
            self.assertEqual([value["phase"] for value in seen],
                             ["metadata-hash", "metadata-input", "metadata-json",
                              "manifest-file", "manifest-deflate", "manifest-block",
                              "parquet-footer", "parquet-read", "arrow-rows"])
        finally:
            catalog.engine.dispose()

    def test_observed_footer_keeps_original_pinned_native_parser_defaults(self):
        source = (Path(pa.get_include()) / "parquet/properties.h").read_text()
        original = []
        for name in ("String", "Container"):
            expression = re.search(r"kDefaultThrift" + name + r"SizeLimit = ([0-9 *]+);", source)
            self.assertIsNotNone(expression)
            original.append(math.prod(int(part.strip()) for part in expression.group(1).split("*")))
        self.assertEqual(_parquet_thrift_limits(2147483647), tuple(original))
        for footer in (1, 512, 2_000_000):
            self.assertEqual(_parquet_thrift_limits(footer), tuple(min(footer, value) for value in original))

    def test_published_record_geometry_precedes_material_and_keeps_same_read_snapshot(self):
        root = tempfile.mkdtemp(prefix="actql-table-record-construction-")
        print("Retained original record fixture:", root)
        writer = self.open(root)
        reader = None
        try:
            writer.create_namespace("test")
            operation = request("create", "rôws", "7")
            receipt = self.write(writer, operation, [{"id": 1}])
            selector = {"catalog_identity_cid": writer.catalog_cid, "namespace": ["test"],
                        "table_name": "rôws", "table_uuid": receipt["table_uuid"],
                        "schema_cid": mapping()["schema_cid"]}
            expected_bytes = sum(len(value.encode("utf-8")) for value in
                                 (receipt["metadata_location"], canonical_envelope(receipt), canonical_envelope(operation)))
            seen = []
            replacements = []
            def before(geometry):
                if geometry["phase"] != "catalog-record":
                    return
                seen.append(dict(geometry))
                # This original callback can reenter the same Catalog before
                # row materialization. A new committed head cannot retarget
                # the original length observation/read transaction.
                replacement = request("replace", "rôws", "8", expected(receipt))
                replacements.append(self.write(writer, replacement, [{"id": 2}]))
            reader = TableCatalog(Path(root) / "catalog.db", Path(root) / "warehouse",
                                  "sha256:" + "3" * 64,
                                  {"bytes": 16777216, "files": 256, "operations": 32},
                                  before_materialization=before)
            frozen = reader.resolve_generation(selector)
            self.assertEqual(seen, [{"phase": "catalog-record", "bytes": expected_bytes,
                                     "rows": 1, "columns": 3}])
            self.assertEqual(len(replacements), 1)
            self.assertNotEqual(replacements[0]["generation_cid"], receipt["generation_cid"])
            self.assertEqual(frozen, {"receipt": receipt, "mapping": mapping(), "schema_wire": schema_wire()})
        finally:
            if reader is not None:
                reader.engine.dispose()
            writer.engine.dispose()

    def test_original_record_refusal_closes_snapshot_before_payload_or_json_materialization(self):
        root = tempfile.mkdtemp(prefix="actql-table-record-refusal-")
        print("Retained original record refusal fixture:", root)
        writer = self.open(root)
        reader = None
        try:
            writer.create_namespace("test")
            receipt = self.write(writer, request("create", "rows", "9"), [{"id": 1}])
            selector = {"catalog_identity_cid": writer.catalog_cid, "namespace": ["test"],
                        "table_name": "rows", "table_uuid": receipt["table_uuid"],
                        "schema_cid": mapping()["schema_cid"]}
            primary = RuntimeError("OriginalRecordBackingRefusal")
            def before(geometry):
                self.assertEqual(geometry["phase"], "catalog-record")
                raise primary
            reader = TableCatalog(Path(root) / "catalog.db", Path(root) / "warehouse",
                                  "sha256:" + "3" * 64,
                                  {"bytes": 16777216, "files": 256, "operations": 32},
                                  before_materialization=before)
            connection = reader.connection
            connections, statements = [], []
            def original_connection():
                db = connection()
                connections.append(db)
                db.set_trace_callback(statements.append)
                return db
            reader.connection = original_connection
            with patch("catalog.json.loads", side_effect=AssertionError("unfunded JSON material")):
                with self.assertRaises(RuntimeError) as failed:
                    reader.resolve_generation(selector)
            self.assertIs(failed.exception, primary)
            self.assertEqual(len(connections), 1)
            self.assertTrue(any("length(CAST(t.metadata_location AS BLOB))" in query for query in statements))
            self.assertFalse(any(query.startswith("SELECT t.metadata_location,c.receipt_wire,c.request_wire ")
                                 for query in statements))
            # Exact local SQLite handle closure, not a Resource/Run/child ACK.
            with self.assertRaises(sqlite3.ProgrammingError):
                connections[0].execute("SELECT 1")
        finally:
            if reader is not None:
                reader.engine.dispose()
            writer.engine.dispose()

    def test_resolved_original_reuses_checked_mapping_schema_and_selected_io_once(self):
        root = tempfile.mkdtemp(prefix="actql-table-original-checks-")
        print("Retained original checked material fixture:", root)
        catalog = self.open(root)
        try:
            catalog.create_namespace("test")
            receipt = self.write(catalog, request("create", "rows", "a"), [{"id": 1}])
            selector = {"catalog_identity_cid": catalog.catalog_cid, "namespace": ["test"],
                        "table_name": "rows", "table_uuid": receipt["table_uuid"],
                        "schema_cid": mapping()["schema_cid"]}
            original_mapping = catalog_module.check_mapping
            original_schema = catalog_module.check_logical_schema
            original_io = catalog._load_file_io
            original_generation = catalog.generation
            counts = {"mapping": 0, "schema": 0, "io": 0, "generation": 0}
            checked_wires = []
            def check_mapping(*args, **kwargs):
                counts["mapping"] += 1
                return original_mapping(*args, **kwargs)
            def check_schema(*args, **kwargs):
                counts["schema"] += 1
                result = original_schema(*args, **kwargs)
                checked_wires.append(result)
                return result
            def load_io(*args, **kwargs):
                counts["io"] += 1
                return original_io(*args, **kwargs)
            def generation(*args, **kwargs):
                counts["generation"] += 1
                return original_generation(*args, **kwargs)
            with patch.object(catalog_module, "check_mapping", check_mapping), \
                    patch.object(catalog_module, "check_logical_schema", check_schema), \
                    patch.object(catalog, "_load_file_io", load_io), \
                    patch.object(catalog, "generation", generation):
                frozen = catalog.resolve_generation(selector)
            self.assertEqual(counts, {"mapping": 1, "schema": 1, "io": 1, "generation": 2})
            self.assertIs(frozen["schema_wire"], checked_wires[0])
            self.assertEqual(frozen, {"receipt": receipt, "mapping": mapping(), "schema_wire": schema_wire()})
        finally:
            catalog.engine.dispose()

    def test_existing_generation_table_preserves_original_materials_and_refusal_after_shared_check(self):
        root = tempfile.mkdtemp(prefix="actql-table-original-materials-")
        print("Retained original material wrapper fixture:", root)
        catalog = self.open(root)
        try:
            catalog.create_namespace("test")
            receipt = self.write(catalog, request("create", "rows", "b"), [{"id": 1, "p": None}])
            material = catalog._generation_read_material
            originals = []
            def selected(*args, **kwargs):
                result = material(*args, **kwargs)
                originals.append(result)
                return result
            with patch.object(catalog, "_generation_read_material", selected):
                table = catalog.generation_table(receipt, mapping())
                self.assertIs(table.metadata, originals[0][0])
                self.assertIs(table.io, originals[0][1])
                self.assertIs(table.catalog, catalog)
                self.assertEqual(table.metadata_location, receipt["metadata_location"])
                self.assertEqual(catalog.read_generation(receipt, mapping()), [{"id": 1, "p": None}])
            bad = dict(mapping())
            bad["schema_cid"] = "sha256:" + "9" * 64
            with self.assertRaisesRegex(PhysicalRefusal, "StorageMappingIdentity"):
                catalog.generation_table(receipt, bad)
        finally:
            catalog.engine.dispose()

    def test_original_metadata_parser_is_preceded_by_same_file_geometry(self):
        root = tempfile.mkdtemp(prefix="actql-table-metadata-construction-")
        print("Retained original metadata fixture:", root)
        catalog = self.open(root)
        try:
            catalog.create_namespace("test")
            receipt = self.write(catalog, request("create", "rows", "c"), [{"id": 1, "p": "e\u0301"}])
            size = catalog.local_path(receipt["metadata_location"]).stat().st_size
            observed = []
            catalog.before_materialization = lambda value: observed.append(dict(value))
            original = FromByteStream.table_metadata
            def parse(byte_stream, *args, **kwargs):
                self.assertIn({"phase": "metadata-json", "bytes": size, "rows": 0, "columns": 0}, observed,
                              "original metadata decoder entered before its actual byte geometry")
                return original(byte_stream, *args, **kwargs)
            with patch.object(FromByteStream, "table_metadata", parse):
                table = catalog.generation_table(receipt, mapping())
            self.assertEqual(str(table.metadata.table_uuid), receipt["table_uuid"])
            self.assertEqual([item["phase"] for item in observed],
                             ["metadata-hash", "metadata-input", "metadata-json"])
            self.assertEqual(observed[0]["bytes"], 65536)
            self.assertEqual(observed[1]["bytes"], size)
        finally:
            catalog.engine.dispose()

    def test_original_metadata_refusal_closes_same_stream_before_decoder(self):
        root = tempfile.mkdtemp(prefix="actql-table-metadata-refusal-")
        print("Retained original metadata refusal fixture:", root)
        catalog = self.open(root)
        try:
            catalog.create_namespace("test")
            receipt = self.write(catalog, request("create", "rows", "d"), [{"id": 1}])
            original_io = catalog._load_file_io({}, receipt["metadata_location"])
            original_input = original_io.new_input(receipt["metadata_location"])
            streams = []
            class OriginalInput:
                location = original_input.location
                def open(self):
                    stream = original_input.open()
                    streams.append(stream)
                    return stream
            primary = RuntimeError("OriginalMetadataConstructorRefusal")
            def before(value):
                if value["phase"] == "metadata-json":
                    raise primary
            catalog.before_materialization = before
            with patch.object(catalog, "_load_file_io", return_value=original_io), \
                    patch.object(original_io, "new_input", return_value=OriginalInput()), \
                    patch.object(FromByteStream, "table_metadata", side_effect=AssertionError("unfunded metadata decoder")):
                with self.assertRaises(RuntimeError) as failed:
                    catalog.generation_table(receipt, mapping())
            self.assertIs(failed.exception, primary)
            self.assertEqual(len(streams), 1)
            self.assertTrue(streams[0].closed)
        finally:
            catalog.engine.dispose()

    def test_gzip_metadata_observes_full_concatenated_expansion_before_original_parser(self):
        root = tempfile.mkdtemp(prefix="actql-table-gzip-metadata-")
        print("Retained gzip metadata fixture:", root)
        catalog = self.open(root)
        try:
            catalog.create_namespace("test")
            receipt = self.write(catalog, request("create", "rows", "e"), [{"id": 1}])
            location = catalog.local_path(receipt["metadata_location"])
            metadata = json.loads(location.read_bytes())
            metadata["properties"]["codec-fixture"] = "x" * 180000
            logical = json.dumps(metadata).encode("utf-8")
            split = 65539
            encoded = gzip.compress(logical[:split]) + gzip.compress(logical[split:])
            compressed = location.with_name("observed.gz.metadata.json")
            compressed.write_bytes(encoded)
            self.assertLess(len(encoded), len(logical))
            self.assertNotEqual(int.from_bytes(encoded[-4:], "little"), len(logical))
            seen = []
            catalog.before_materialization = lambda value: seen.append(dict(value))
            original = FromByteStream.table_metadata
            def parse(byte_stream, *args, **kwargs):
                self.assertEqual(seen, [
                    {"phase": "metadata-input", "bytes": len(encoded), "rows": 0, "columns": 0},
                    {"phase": "metadata-codec", "bytes": 65536, "rows": 0, "columns": 0},
                    {"phase": "metadata-json", "bytes": len(logical), "rows": 0, "columns": 0}])
                return original(byte_stream, *args, **kwargs)
            with patch.object(FromByteStream, "table_metadata", parse):
                result = catalog._read_generation_metadata(
                    catalog._load_file_io({}, compressed.as_uri()), compressed.as_uri())
            self.assertEqual(str(result.table_uuid), receipt["table_uuid"])
            self.assertEqual(result.properties["codec-fixture"], "x" * 180000)
        finally:
            catalog.engine.dispose()

    def test_metadata_input_growth_refuses_before_unbounded_original_decoder_read(self):
        root = tempfile.mkdtemp(prefix="actql-table-metadata-growth-")
        print("Retained metadata growth fixture:", root)
        catalog = self.open(root)
        try:
            catalog.create_namespace("test")
            receipt = self.write(catalog, request("create", "rows", "f"), [{"id": 1}])
            location = catalog.local_path(receipt["metadata_location"])
            def before(value):
                if value["phase"] == "metadata-input":
                    with location.open("ab") as changed:
                        changed.write(b" ")
            catalog.before_materialization = before
            with patch.object(FromByteStream, "table_metadata", side_effect=AssertionError("unbounded decoder read")):
                with self.assertRaisesRegex(ValueError, "TableMetadataFileChanged"):
                    catalog.generation_table(receipt, mapping())
        finally:
            catalog.engine.dispose()

    def test_gzip_preflight_retains_original_crc_refusal_without_json_admission(self):
        root = tempfile.mkdtemp(prefix="actql-table-metadata-codec-refusal-")
        print("Retained metadata codec refusal fixture:", root)
        catalog = self.open(root)
        try:
            location = catalog.warehouse / "corrupt.gz.metadata.json"
            location.parent.mkdir(parents=True, exist_ok=True)
            original = gzip.compress(b"{}")
            corrupt = original[:-8] + bytes([original[-8] ^ 1]) + original[-7:]
            location.write_bytes(corrupt)
            seen = []
            catalog.before_materialization = lambda value: seen.append(dict(value))
            with patch.object(FromByteStream, "table_metadata", side_effect=AssertionError("unadmitted metadata decoder")):
                with self.assertRaises(gzip.BadGzipFile):
                    catalog._read_generation_metadata(
                        catalog._load_file_io({}, location.as_uri()), location.as_uri())
            self.assertEqual([value["phase"] for value in seen], ["metadata-input", "metadata-codec"])
        finally:
            catalog.engine.dispose()

    def test_original_generation_hash_streams_fixed_scratch_without_whole_file_copy(self):
        root = tempfile.mkdtemp(prefix="actql-table-metadata-hash-")
        print("Retained original metadata hash fixture:", root)
        catalog = self.open(root)
        try:
            location = catalog.warehouse / "original.metadata.json"
            location.parent.mkdir(parents=True, exist_ok=True)
            for raw in (b"", b"original\x00\xff" * 20000):
                location.write_bytes(raw)
                expected = "sha256:" + hashlib.sha256(raw).hexdigest()
                seen = []
                catalog.before_materialization = lambda value: seen.append(dict(value))
                with patch.object(Path, "read_bytes", side_effect=AssertionError("whole hash file copy")):
                    self.assertEqual(catalog.generation(location.as_uri()), expected)
                self.assertEqual(seen, [{"phase": "metadata-hash", "bytes": 65536, "rows": 0, "columns": 0}])
        finally:
            catalog.engine.dispose()

    def test_rejected_original_parquet_schema_refuses_before_native_data_read(self):
        for shape, code in (("nested", "PhysicalFieldType"), ("dictionary", "PhysicalFieldType"),
                            ("extra", "PhysicalFieldId"), ("missing", "PhysicalFieldMissing")):
            with self.subTest(shape=shape):
                root = tempfile.mkdtemp(prefix="actql-table-rejected-parquet-" + shape + "-")
                print("Retained rejected Parquet fixture:", root)
                catalog = self.open(root)
                try:
                    catalog.create_namespace("test")
                    receipt = self.write(catalog, request("create", "rows", "1"), [{"id": 1, "p": "one"}])
                    task = next(iter(catalog.generation_table(receipt, mapping()).scan().plan_files()))
                    original = pa.Table.from_pylist([{"id": 1.0, "p": "one", "__actql_presence_3": True}],
                                                   schema=catalog_module.encode_rows(mapping(), []).schema)
                    fields, arrays = list(original.schema), [original.column(index) for index in range(3)]
                    if shape == "nested":
                        fields[0] = pa.field("id", pa.list_(pa.float64()), metadata=fields[0].metadata)
                        arrays[0] = pa.array([[1.0]], type=fields[0].type)
                    elif shape == "dictionary":
                        fields[1] = pa.field("p", pa.dictionary(pa.int8(), pa.string()), metadata=fields[1].metadata)
                        arrays[1] = pa.array(["one"], type=fields[1].type)
                    elif shape == "extra":
                        fields.append(pa.field("unselected", pa.list_(pa.float64()),
                                               metadata={b"PARQUET:field_id": b"99"}))
                        arrays.append(pa.array([[1.0]], type=fields[-1].type))
                    else:
                        fields.pop()
                        arrays.pop()
                    # Authored corrupt physical material in this NEW fixture,
                    # not a replay or mutation of any original failed Run.
                    pq.write_table(pa.Table.from_arrays(arrays, schema=pa.schema(fields)),
                                   catalog.local_path(task.file.file_path))
                    observed = []
                    catalog.before_materialization = lambda value: observed.append(dict(value))
                    with patch.object(pq.ParquetFile, "read", side_effect=AssertionError("unfunded rejected carrier data")):
                        with self.assertRaisesRegex(PhysicalRefusal, code):
                            catalog.read_generation(receipt, mapping())
                    self.assertIn("parquet-footer", [value["phase"] for value in observed])
                    self.assertNotIn("parquet-read", [value["phase"] for value in observed])
                finally:
                    catalog.engine.dispose()

    def test_original_manifest_file_codec_and_block_construct_only_after_geometry(self):
        root = tempfile.mkdtemp(prefix="actql-table-manifest-construction-")
        print("Retained original manifest constructor fixture:", root)
        catalog = self.open(root)
        rows = [{"id": 1, "p": "e\u0301\r\n"}, {"id": 2}, {"id": 3, "p": None}]
        try:
            catalog.create_namespace("test")
            receipt = self.write(catalog, request("create", "rows", "2"), rows)
            # Fixture setup runs outside this observed read. A fresh physical
            # worker has no prior manifest cache; reproduce only that original
            # cold-input condition in this private, serial component process.
            manifest_module._manifests.cache_clear()
            seen, entries = [], []
            catalog.before_materialization = lambda value: seen.append(dict(value))
            original_decoder = avro_file_module.new_decoder
            original_decompress = DeflateCodec.decompress
            def decoder(data):
                phase = "manifest-file" if data.startswith(avro_file_module.MAGIC) else "manifest-block"
                self.assertTrue(any(value["phase"] == phase for value in seen),
                                "original Avro decoder entered before " + phase + " geometry")
                entries.append(phase)
                return original_decoder(data)
            def decompress(data):
                self.assertEqual(seen[-1]["phase"], "manifest-block",
                                 "original codec entered without decoded-block constructor geometry")
                self.assertGreaterEqual(seen[-1]["bytes"], 0)
                entries.append("original-deflate")
                return original_decompress(data)
            with patch.object(avro_file_module, "new_decoder", decoder), \
                    patch.object(DeflateCodec, "decompress", decompress):
                actual = catalog.read_generation(receipt, mapping())
            self.assertEqual(actual, rows)
            self.assertIn("manifest-file", entries)
            self.assertIn("manifest-block", entries)
            self.assertIn("original-deflate", entries)
        finally:
            catalog.engine.dispose()

    def test_unsupported_carrier_refuses_before_any_staging_or_reservation(self):
        with tempfile.TemporaryDirectory(prefix="actql-table-kind-") as root:
            catalog = self.open(root)
            try:
                for kind in ["graph", "vectors", "events"]:
                    operation = request("create", "rows", "7")
                    operation["input_carrier"]["kind"] = kind
                    operation = seal({k: v for k, v in operation.items() if k != "request_cid"}, "request_cid")
                    with self.assertRaisesRegex(CatalogRefusal, "UnsupportedTableCarrierOperation"):
                        self.write(catalog, operation, [{"id": 1}])
                    self.assertIsNone(catalog.reconcile(operation))
                self.assertFalse(catalog.warehouse.exists())
                with closing(catalog.connection()) as db:
                    self.assertEqual(db.execute("SELECT COUNT(*) FROM actql_table_allocations").fetchone()[0], 0)
            finally:
                catalog.engine.dispose()

    def test_create_replace_and_original_operation_after_later_commit(self):
        rows = [{"id": 1, "p": "e\u0301\r\n"}, {"id": 2, "p": None}, {"id": 3}, {"id": 3}]
        with tempfile.TemporaryDirectory(prefix="actql-table-catalog-") as root:
            catalog = self.open(root)
            catalog.create_namespace("test")
            first = request("create", "rows", "7")
            receipt = self.write(catalog, first, rows)
            second = request("replace", "rows", "8", expected(receipt))
            next_receipt = self.write(catalog, second, [{"id": 9}])
            self.assertEqual(receipt["table_uuid"], next_receipt["table_uuid"])
            self.assertNotEqual(receipt["generation_cid"], next_receipt["generation_cid"])
            self.assertEqual(catalog.read_generation(receipt, mapping()), rows)
            self.assertEqual(catalog.read_generation(next_receipt, mapping()), [{"id": 9}])
            catalog.engine.dispose()
            reopened = self.open(root)
            self.assertEqual(reopened.reconcile(first), receipt)
            self.assertEqual(reopened.read_generation(receipt, mapping()), rows)
            with self.assertRaisesRegex(CatalogRefusal, "AlreadyCommittedReconcileOnly"):
                self.write(reopened, first, rows)
            conflict = request("replace", "rows", "9", expected(receipt))
            refused = self.write(reopened, conflict, [])
            self.assertEqual(refused["version"], "actql-table-noncommit-receipt/0.1")
            self.assertEqual(refused["reason"], "ExpectedGenerationConflict")
            self.assertEqual(reopened.reconcile(conflict), refused)
            reopened.engine.dispose()

    def test_commit_response_loss_reconciles_after_restart(self):
        with tempfile.TemporaryDirectory(prefix="actql-table-reply-") as root:
            catalog = self.open(root, LostReplyCatalog)
            catalog.create_namespace("test")
            operation = request("create", "rows", "a")
            with self.assertRaisesRegex(ConnectionError, "CommitReplyLost"):
                self.write(catalog, operation, [{"id": 1}])
            catalog.engine.dispose()
            reopened = self.open(root)
            receipt = reopened.reconcile(operation)
            self.assertIsNotNone(receipt)
            self.assertEqual(reopened.read_generation(receipt, mapping()), [{"id": 1}])
            reopened.engine.dispose()

    def test_new_read_resolves_one_generation_and_preserves_presence_after_replace(self):
        rows = [{"id": 1, "p": "e\u0301\r\n"}, {"id": 2, "p": None}, {"id": 3}, {"id": 3}]
        with tempfile.TemporaryDirectory(prefix="actql-table-reader-") as root:
            writer = self.open(root)
            writer.create_namespace("test")
            receipt = self.write(writer, request("create", "rows", "a"), rows)
            selector = {"catalog_identity_cid": writer.catalog_cid, "namespace": ["test"],
                        "table_name": "rows", "table_uuid": receipt["table_uuid"],
                        "schema_cid": mapping()["schema_cid"]}
            writer.engine.dispose()
            reader = self.open(root)
            frozen = reader.resolve_generation(selector)
            self.assertEqual(frozen, {"receipt": receipt, "mapping": mapping(), "schema_wire": schema_wire()})
            reader.engine.dispose()
            writer = self.open(root)
            replacement = self.write(writer, request("replace", "rows", "b", expected(receipt)), [{"id": 9}])
            writer.engine.dispose()
            reopened = self.open(root)
            self.assertEqual(reopened.read_generation(frozen["receipt"], frozen["mapping"]), rows)
            self.assertEqual(reopened.resolve_generation(selector)["receipt"], replacement)
            for field, value, reason in (
                    ("table_uuid", "00000000-0000-0000-0000-000000000000", "TableReadPublicationBinding"),
                    ("schema_cid", "sha256:" + "9" * 64, "TableReadPublicationBinding"),
                    ("catalog_identity_cid", "sha256:" + "9" * 64, "ForeignReadCatalog"),
                    ("table_name", "missing", "TableReadNotFound")):
                with self.subTest(field=field), self.assertRaisesRegex(CatalogRefusal, reason):
                    reopened.resolve_generation({**selector, field: value})
            reopened.engine.dispose()

    def test_empty_generation_and_missing_original_publication_record_are_not_inferred(self):
        with tempfile.TemporaryDirectory(prefix="actql-table-reader-empty-") as root:
            catalog = self.open(root)
            catalog.create_namespace("test")
            receipt = self.write(catalog, request("create", "rows", "c"), [])
            selector = {"catalog_identity_cid": catalog.catalog_cid, "namespace": ["test"],
                        "table_name": "rows", "table_uuid": receipt["table_uuid"],
                        "schema_cid": mapping()["schema_cid"]}
            frozen = catalog.resolve_generation(selector)
            self.assertEqual(frozen["mapping"], mapping())
            self.assertEqual(catalog.read_generation(frozen["receipt"], frozen["mapping"]), [])
            # A head is not a substitute for the original atomic publication
            # record. Model record corruption without modifying physical files.
            with closing(catalog.connection()) as db:
                db.execute("DELETE FROM actql_table_commits WHERE request_cid=?", (receipt["request_cid"],))
                db.commit()
            with self.assertRaisesRegex(CatalogRefusal, "TableReadPublicationRecord"):
                catalog.resolve_generation(selector)
            catalog.engine.dispose()

    def test_record_failure_rolls_back_catalog_head_not_only_receipt(self):
        with tempfile.TemporaryDirectory(prefix="actql-table-atomic-") as root:
            catalog = self.open(root)
            catalog.create_namespace("test")
            with closing(catalog.connection()) as db:
                db.execute("""CREATE TRIGGER fail_receipt BEFORE INSERT ON actql_table_commits
                    BEGIN SELECT RAISE(ABORT, 'ReceiptSaveRefused'); END""")
                db.commit()
            operation = request("create", "rows", "b")
            with self.assertRaisesRegex(sqlite3.IntegrityError, "ReceiptSaveRefused"):
                self.write(catalog, operation, [{"id": 1}])
            self.assertFalse(catalog.table_exists(("test", "rows")))
            self.assertIsNone(catalog.reconcile(operation))  # Still not permission to resend.
            self.assertTrue(list((Path(root) / "warehouse").rglob("*.parquet")))
            with self.assertRaisesRegex(PhysicalRefusal, "ExistingAllocationReconcileOnly"):
                self.write(catalog, operation, [{"id": 1}])
            catalog.engine.dispose()

    def test_typed_empty_and_create_conflict(self):
        with tempfile.TemporaryDirectory(prefix="actql-table-empty-") as root:
            catalog = self.open(root)
            catalog.create_namespace("test")
            operation = request("create", "rows", "c")
            receipt = self.write(catalog, operation, [])
            self.assertEqual(receipt["row_count"], 0)
            self.assertIsNone(receipt["snapshot_id"])
            self.assertEqual(catalog.read_generation(receipt, mapping()), [])
            conflict = request("create", "rows", "d")
            refused = self.write(catalog, conflict, [])
            self.assertEqual(refused["reason"], "CreateNameConflict")
            self.assertEqual(catalog.reconcile(conflict), refused)
            catalog.engine.dispose()

    def test_noncommit_record_and_fence_are_atomic_and_survive_restart_cleanup(self):
        with tempfile.TemporaryDirectory(prefix="actql-table-noncommit-") as root:
            catalog = self.open(root)
            catalog.create_namespace("test")
            committed = self.write(catalog, request("create", "rows", "7"), [{"id": 1}])
            operation = request("replace", "rows", "8", expected(committed))
            self.write(catalog, request("replace", "rows", "9", expected(committed)), [{"id": 2}])
            # Failed record persistence must roll back the fence too, and must
            # never manufacture a confirmed failure from the resulting absence.
            with closing(catalog.connection()) as db:
                db.execute("""CREATE TRIGGER fail_noncommit BEFORE INSERT ON actql_table_noncommits
                    BEGIN SELECT RAISE(ABORT, 'NoncommitSaveRefused'); END""")
                db.commit()
            with self.assertRaisesRegex(sqlite3.IntegrityError, "NoncommitSaveRefused"):
                self.write(catalog, operation, [{"id": 3}])
            self.assertIsNone(catalog.reconcile(operation))
            with closing(catalog.connection()) as db:
                self.assertIsNone(db.execute("SELECT 1 FROM actql_table_publication_fences WHERE request_cid=?",
                                            (operation["request_cid"],)).fetchone())
                db.execute("DROP TRIGGER fail_noncommit")
                db.commit()
            # The trusted writer has observed its conflict; recording that
            # fact is not permission to rerun write_claimed or inspect a head.
            receipt = catalog.confirm_noncommit(operation, "ExpectedGenerationConflict")
            self.assertEqual(receipt, seal({"version": "actql-table-noncommit-receipt/0.1",
                "request_cid": operation["request_cid"], "effect_identity_cid": operation["effect_identity_cid"],
                "catalog_identity_cid": operation["catalog_identity_cid"], "schema_cid": operation["schema_cid"],
                "storage_mapping_cid": operation["storage_mapping_cid"], "reason": "ExpectedGenerationConflict"},
                "receipt_cid"))
            catalog.engine.dispose()
            reopened = self.open(root)
            self.assertEqual(reopened.reconcile(operation), receipt)
            self.assertEqual(reopened.cleanup_after_stop(operation)["pending"], False)
            self.assertEqual(reopened.reconcile(operation), receipt)
            with self.assertRaisesRegex(CatalogRefusal, "AlreadyCommittedReconcileOnly"):
                self.write(reopened, operation, [{"id": 3}])
            self.assertEqual(reopened.read_generation(committed, mapping()), [{"id": 1}])
            reopened.engine.dispose()

    def test_noncommit_never_overrides_a_committed_original_or_unallocated_absence(self):
        with tempfile.TemporaryDirectory(prefix="actql-table-noncommit-binding-") as root:
            class MisleadingReturn(TableCatalog):
                def after_publication(self):
                    raise CatalogRefusal("CreateNameConflict")
            catalog = self.open(root, MisleadingReturn)
            catalog.create_namespace("test")
            operation = request("create", "rows", "7")
            committed = self.write(catalog, operation, [{"id": 1}])
            self.assertEqual(committed["version"], "actql-table-receipt/0.1")
            self.assertEqual(catalog.reconcile(operation), committed)
            absent = request("create", "missing", "8")
            with self.assertRaisesRegex(CatalogRefusal, "NoncommitAllocationBinding"):
                catalog.confirm_noncommit(absent, "CreateNameConflict")
            self.assertIsNone(catalog.reconcile(absent))
            with closing(catalog.connection()) as db:
                self.assertEqual(db.execute("SELECT COUNT(*) FROM actql_table_noncommits").fetchone(), (0,))
            catalog.engine.dispose()

    def test_capacity_refuses_before_publication_and_keeps_failed_reservation(self):
        with tempfile.TemporaryDirectory(prefix="actql-table-capacity-") as root:
            catalog = self.open(root)
            catalog.create_namespace("test")
            operation = request("create", "rows", "e")
            with self.assertRaisesRegex(PhysicalRefusal, "PersistentCapacityExceeded"):
                self.write(catalog, operation, [], {"bytes": 16777217, "files": 16})
            self.assertFalse((Path(root) / "warehouse").exists())
            with self.assertRaisesRegex(PhysicalRefusal, "ByteCapacityExceeded"):
                self.write(catalog, operation, [{"id": 1}], {"bytes": 1, "files": 16})
            self.assertFalse(catalog.table_exists(("test", "rows")))
            with closing(catalog.connection()) as db:
                allocated = db.execute("SELECT reserved_bytes FROM actql_table_allocations WHERE request_cid=?",
                                       (operation["request_cid"],)).fetchone()
                self.assertEqual(allocated, (1,))
            with self.assertRaisesRegex(PhysicalRefusal, "ExistingAllocationReconcileOnly"):
                self.write(catalog, operation, [])
            catalog.engine.dispose()

    def test_logical_schema_is_saved_with_extents_through_replace_and_restart(self):
        # Independently authored complete logical contract, not derived from
        # the physical string discriminator or a schema inferred from rows.
        wire = schema_wire().replace('"nullable":true,"type":"string"',
                                     '"max_utf8_bytes":32,"nullable":true,"type":"string"')
        schema = hashlib.sha256(wire.encode('utf-8')).hexdigest()
        physical = seal({**{k: v for k, v in mapping().items() if k != 'mapping_cid'},
                         'schema_cid': 'sha256:' + schema}, 'mapping_cid')
        def operation(action, suffix, old=None):
            base = request(action, 'rows', suffix, old)
            return seal({**{k: v for k, v in base.items() if k != 'request_cid'},
                         'schema_cid': physical['schema_cid'],
                         'storage_mapping_cid': physical['mapping_cid']}, 'request_cid')
        with tempfile.TemporaryDirectory(prefix='actql-table-schema-') as root:
            catalog = self.open(root)
            catalog.create_namespace('test')
            first = operation('create', '1')
            receipt = catalog.write_claimed(first, physical, [], {'bytes':1048576, 'files':16}, wire)
            selector = {'catalog_identity_cid': first['catalog_identity_cid'], 'namespace':['test'],
                        'table_name':'rows', 'table_uuid':receipt['table_uuid'],
                        'schema_cid':physical['schema_cid']}
            frozen = catalog.resolve_generation(selector)
            self.assertEqual(frozen['schema_wire'], wire)
            self.assertEqual(catalog.read_generation(receipt, physical), [])
            second = operation('replace', '2', expected(receipt))
            catalog.write_claimed(second, physical, [{'id':1}, {'id':2, 'p':None}],
                                  {'bytes':1048576, 'files':16}, wire)
            catalog.engine.dispose()
            reopened = self.open(root)
            self.assertEqual(reopened.resolve_generation(selector)['schema_wire'], wire)
            self.assertEqual(reopened.read_generation(frozen['receipt'], frozen['mapping']), [])
            self.assertEqual(reopened.reconcile(first), receipt)
            reopened.engine.dispose()

    def test_missing_or_foreign_logical_schema_refuses_before_staging(self):
        with tempfile.TemporaryDirectory(prefix='actql-table-schema-refusal-') as root:
            catalog = self.open(root)
            catalog.create_namespace('test')
            operation = request('create', 'rows', '1')
            for wire, reason in [(None, 'MissingTableLogicalSchema'),
                                 ('{}', 'TableLogicalSchemaIdentity'),
                                 (schema_wire() + ' ', 'TableLogicalSchemaIdentity')]:
                with self.assertRaisesRegex(CatalogRefusal, reason):
                    catalog.write_claimed(operation, mapping(), [], {'bytes':1048576, 'files':16}, wire)
                self.assertFalse(catalog.table_exists(('test', 'rows')))
                self.assertIsNone(catalog.reconcile(operation))
                self.assertFalse((Path(root) / 'warehouse').exists())
            catalog.engine.dispose()


if __name__ == "__main__":
    unittest.main()
