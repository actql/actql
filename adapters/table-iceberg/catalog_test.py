import tempfile
import unittest
import sqlite3
from contextlib import closing
from pathlib import Path

from catalog import CatalogRefusal, TableCatalog
from physical import seal, PhysicalRefusal
from physical_test import mapping


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
                                     reservation or {"bytes": 1048576, "files": 16})

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


if __name__ == "__main__":
    unittest.main()
