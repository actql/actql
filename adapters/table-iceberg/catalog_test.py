import tempfile
import unittest
import sqlite3
import hashlib
from contextlib import closing
from pathlib import Path

from catalog import CatalogRefusal, TableCatalog
from physical import seal, PhysicalRefusal
from physical_test import mapping, schema_wire


def request(action, name, suffix, expected=None):
    return seal({"version": "actql-table-operation/0.1",
                 "logical_request_scope_cid": "sha256:" + suffix * 64,
                 "effect_identity_cid": "sha256:" + "2" * 64,
                 "action": action, "catalog_identity_cid": "sha256:" + "3" * 64,
                 "namespace": ["test"], "table_name": name,
                 "expected_table": expected,
                 "input_artifact_cid": "sha256:" + "4" * 64,
                 "input_relation_cid": "sha256:" + "5" * 64,
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
            with self.assertRaisesRegex(CatalogRefusal, "ExpectedGenerationConflict"):
                self.write(reopened, request("replace", "rows", "9", expected(receipt)), [])
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
            with self.assertRaisesRegex(CatalogRefusal, "CreateNameConflict"):
                self.write(catalog, request("create", "rows", "d"), [])
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
