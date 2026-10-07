import os
import select
import sqlite3
import subprocess
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path

from catalog import CatalogRefusal, TableCatalog
import catalog_test
from catalog_test import expected, request
from custody import reserve
from physical import PhysicalRefusal, canonical_envelope
from physical_test import mapping


class ConcurrentCatalog(TableCatalog):
    barrier = None

    def before_publication(self):
        if self.barrier:
            self.barrier.wait(timeout=10)


class CustodyTests(unittest.TestCase):
    open = catalog_test.CatalogTests.open
    write = catalog_test.CatalogTests.write

    def failed_stage(self, root):
        catalog = self.open(root)
        catalog.create_namespace("test")
        with closing(catalog.connection()) as db:
            db.execute("""CREATE TRIGGER fail_receipt BEFORE INSERT ON actql_table_commits
                BEGIN SELECT RAISE(ABORT, 'ReceiptSaveRefused'); END""")
            db.commit()
        operation = request("create", "rows", "b")
        with self.assertRaisesRegex(sqlite3.IntegrityError, "ReceiptSaveRefused"):
            self.write(catalog, operation, [{"id": 1}])
        return catalog, operation

    def allocation(self, catalog, operation):
        with closing(catalog.connection()) as db:
            return db.execute("SELECT reserved_bytes,reserved_files FROM actql_table_allocations WHERE request_cid=?",
                              (operation["request_cid"],)).fetchone()

    def test_manifest_before_directory_creation_does_not_leave_false_pending(self):
        with tempfile.TemporaryDirectory(prefix="actql-table-preallocation-") as root:
            catalog = self.open(root)
            operation = request("create", "rows", "d")
            reserve(catalog, operation, catalog.limits, {"bytes": 1048576, "files": 16})
            path = catalog.warehouse / "not-created" / "data" / "never-created.parquet"
            catalog.claim_file(operation["request_cid"], str(path))
            self.assertFalse(path.parent.exists())
            self.assertEqual(catalog.cleanup_after_stop(operation),
                             {"retained": False, "pending": False, "removed": 1})
            self.assertFalse(path.parent.exists())
            self.assertEqual(self.allocation(catalog, operation), (0, 0))
            self.assertEqual(catalog.cleanup_after_stop(operation)["removed"], 0)
            catalog.engine.dispose()

    def test_foreign_symlink_is_refused_without_returning_capacity(self):
        with tempfile.TemporaryDirectory(prefix="actql-table-link-") as root:
            catalog = self.open(root)
            operation = request("create", "rows", "e")
            reserve(catalog, operation, catalog.limits, {"bytes": 1048576, "files": 16})
            path = catalog.warehouse / "data" / "claimed.parquet"
            catalog.claim_file(operation["request_cid"], str(path))
            path.parent.mkdir(parents=True)
            sentinel = Path(root) / "external-sentinel"
            sentinel.write_bytes(b"must remain")
            path.symlink_to(sentinel)
            with self.assertRaisesRegex(CatalogRefusal, "IndirectWarehousePath"):
                catalog.cleanup_after_stop(operation)
            self.assertEqual(sentinel.read_bytes(), b"must remain")
            self.assertTrue(path.is_symlink())
            self.assertEqual(self.allocation(catalog, operation), (1048576, 16))
            catalog.engine.dispose()

    def test_cleanup_failure_keeps_capacity_and_restart_retry_finishes_once(self):
        with tempfile.TemporaryDirectory(prefix="actql-table-cleanup-") as root:
            catalog, operation = self.failed_stage(root)
            files = list((Path(root) / "warehouse").rglob("*.parquet"))
            self.assertTrue(files)
            def refuse(path):
                raise PermissionError("RemovalRefused")
            with self.assertRaisesRegex(PermissionError, "RemovalRefused"):
                catalog.cleanup_after_stop(operation, unlink=refuse)
            self.assertEqual(self.allocation(catalog, operation), (1048576, 16))
            self.assertTrue(all(path.exists() for path in files))
            catalog.engine.dispose()
            reopened = self.open(root)
            result = reopened.cleanup_after_stop(operation)
            self.assertFalse(result["pending"])
            self.assertFalse(result["retained"])
            self.assertEqual(self.allocation(reopened, operation), (0, 0))
            self.assertFalse(any(path.exists() for path in files))
            self.assertEqual(reopened.cleanup_after_stop(operation)["removed"], 0)
            with self.assertRaisesRegex(PhysicalRefusal, "PublicationFenced"):
                self.write(reopened, operation, [])
            reopened.engine.dispose()

    def test_lost_removal_record_never_restores_payload_or_releases_early(self):
        with tempfile.TemporaryDirectory(prefix="actql-table-removal-loss-") as root:
            catalog, operation = self.failed_stage(root)
            removed = []
            def remove_then_lose_response(path):
                os.unlink(path)
                removed.append(path)
                raise ConnectionError("RemovalResponseLost")
            with self.assertRaisesRegex(ConnectionError, "RemovalResponseLost"):
                catalog.cleanup_after_stop(operation, unlink=remove_then_lose_response)
            self.assertEqual(len(removed), 1)
            self.assertFalse(removed[0].exists())
            self.assertEqual(self.allocation(catalog, operation), (1048576, 16))
            catalog.engine.dispose()
            reopened = self.open(root)
            self.assertFalse(reopened.cleanup_after_stop(operation)["pending"])
            self.assertEqual(self.allocation(reopened, operation), (0, 0))
            reopened.engine.dispose()

    def test_commit_response_loss_and_later_head_do_not_allow_file_deletion(self):
        with tempfile.TemporaryDirectory(prefix="actql-table-retained-") as root:
            catalog = self.open(root)
            catalog.create_namespace("test")
            operation = request("create", "rows", "7")
            receipt = self.write(catalog, operation, [{"id": 1}])
            self.write(catalog, request("replace", "rows", "8", expected(receipt)), [{"id": 2}])
            catalog.engine.dispose()
            reopened = self.open(root)
            def forbidden(path):
                self.fail("A committed operation must not invoke removal")
            result = reopened.cleanup_after_stop(operation, unlink=forbidden)
            self.assertEqual(result, {"retained": True, "pending": False, "removed": 0})
            self.assertEqual(reopened.read_generation(receipt, mapping()), [{"id": 1}])
            self.assertEqual(self.allocation(reopened, operation), (1048576, 16))
            reopened.engine.dispose()

    def test_concurrent_replace_one_commit_and_one_typed_conflict(self):
        with tempfile.TemporaryDirectory(prefix="actql-table-concurrent-") as root:
            initial = self.open(root)
            initial.create_namespace("test")
            receipt = self.write(initial, request("create", "rows", "7"), [{"id": 0}])
            left, right = self.open(root, ConcurrentCatalog), self.open(root, ConcurrentCatalog)
            left.barrier = right.barrier = threading.Barrier(2)
            operations = [request("replace", "rows", "8", expected(receipt)),
                          request("replace", "rows", "9", expected(receipt))]
            with ThreadPoolExecutor(max_workers=2) as executor:
                futures = [executor.submit(self.write, catalog, operation, [{"id": number}])
                           for catalog, operation, number in zip([left, right], operations, [1, 2])]
                outcomes = []
                for future in futures:
                    try:
                        outcomes.append(future.result(timeout=15))
                    except CatalogRefusal as error:
                        self.assertEqual(str(error), "ExpectedGenerationConflict")
                        outcomes.append(None)
            self.assertEqual(sum(result is not None for result in outcomes), 1)
            for operation, result in zip(operations, outcomes):
                cleanup = initial.cleanup_after_stop(operation)
                self.assertEqual(cleanup["retained"], result is not None)
                self.assertFalse(cleanup["pending"])
            self.assertEqual(initial.read_generation(receipt, mapping()), [{"id": 0}])
            for catalog in [initial, left, right]:
                catalog.engine.dispose()

    def test_actual_process_exit_precedes_unpublished_file_cleanup(self):
        with tempfile.TemporaryDirectory(prefix="actql-table-stopped-writer-") as root:
            catalog = self.open(root)
            catalog.create_namespace("test")
            operation = request("create", "rows", "c")
            script = """
import json, select, sys
from catalog import TableCatalog
from physical_test import mapping
class Staged(TableCatalog):
    def before_publication(self):
        print('staged', flush=True)
        select.select([sys.stdin], [], [], 10)
        raise RuntimeError('DiagnosticStageEndedWithoutPublication')
root, wire = sys.argv[1:]
c = Staged(root + '/catalog.db', root + '/warehouse', 'sha256:' + '3'*64,
           {'bytes':16777216, 'files':256, 'operations':32})
c.write_claimed(json.loads(wire), mapping(), [{'id':1}], {'bytes':1048576, 'files':16})
"""
            child = subprocess.Popen([sys.executable, "-c", script, root, canonical_envelope(operation)],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                readable, _, _ = select.select([child.stdout], [], [], 15)
                self.assertTrue(readable, "No physical staging observation")
                self.assertEqual(child.stdout.readline().strip(), "staged")
                self.assertIsNone(catalog.reconcile(operation))
                self.assertEqual(self.allocation(catalog, operation), (1048576, 16))
                child.kill()
                self.assertLess(child.wait(timeout=5), 0)
                self.assertFalse(catalog.cleanup_after_stop(operation)["pending"])
                self.assertEqual(self.allocation(catalog, operation), (0, 0))
                self.assertFalse(catalog.table_exists(("test", "rows")))
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait(timeout=5)
                for stream in [child.stdin, child.stdout, child.stderr]:
                    stream.close()
                catalog.engine.dispose()


if __name__ == "__main__":
    unittest.main()
