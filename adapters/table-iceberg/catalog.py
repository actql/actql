"""Atomic local Catalog publication, not a second Effect state machine.

Only the bulk Effect adapter may call write_claimed after the common Ledger's
durable send claim and current-authority check. This module does physical I/O;
it does not issue approval, decide retries, or infer success from the head.
"""
import hashlib
import json
import os
import sqlite3
from pathlib import Path
from urllib.parse import unquote, urlparse

import pyarrow.parquet as pq
from pyiceberg.catalog.sql import SqlCatalog
from pyiceberg.exceptions import NoSuchTableError
from pyiceberg.table import CommitTableResponse, Table
from pyiceberg.serializers import FromInputFile

from physical import (PhysicalRefusal, canonical_envelope, decode_physical,
                      encode_rows, envelope_cid, iceberg_schema, seal)
from custody import CustodyIO, install_custody, reserve, claim_file, charge_file, cleanup_after_stop


class CatalogRefusal(PhysicalRefusal):
    pass


class TableCatalog(SqlCatalog):
    """Pinned PyIceberg staging plus one SQLite head/receipt transaction.

    No public Program installer calls this boundary yet. Committed generations
    retain their reservation. Unpublished staging is removable only after the
    existing Host process owner confirms stop and a durable publication fence.
    """

    def __init__(self, database, warehouse, catalog_cid, limits):
        # Resolve the operator-configured root once (macOS /var is an alias).
        # Data-file paths must thereafter stay within this canonical root.
        self.database = str(Path(database).resolve())
        self.warehouse = Path(warehouse).resolve()
        self.catalog_cid = catalog_cid
        self.limits = limits
        self.context = None
        super().__init__("actql-table", uri=f"sqlite:///{self.database}",
                         warehouse=self.warehouse.as_uri())
        db = self.connection()
        try:
            db.execute("""CREATE TABLE IF NOT EXISTS actql_table_commits (
                request_cid TEXT PRIMARY KEY, request_wire TEXT NOT NULL,
                receipt_wire TEXT NOT NULL, metadata_location TEXT NOT NULL)""")
            db.commit()
        finally:
            db.close()
        install_custody(self, limits)

    def _load_file_io(self, properties, location=None):
        delegate = super()._load_file_io(properties, location)
        return CustodyIO(self, self.context[0]["request_cid"], delegate) if self.context else delegate

    def claim_file(self, request_cid, path):
        claim_file(self, request_cid, path)

    def charge_file(self, request_cid, path, amount):
        charge_file(self, request_cid, path, amount)

    def cleanup_after_stop(self, request, **kwargs):
        # This is a trusted physical boundary, not a public request accepting
        # a caller's claimed "stopped" boolean. The Host owner supplies the fact.
        if self.context is not None:
            raise CatalogRefusal("WriterNotStopped")
        return cleanup_after_stop(self, request, **kwargs)

    def connection(self):
        db = sqlite3.connect(self.database, timeout=10)
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("PRAGMA synchronous=FULL")
        return db

    def local_path(self, location):
        uri = urlparse(location)
        if uri.scheme != "file" or uri.netloc:
            raise CatalogRefusal("UnsupportedFileLocation")
        path = Path(unquote(uri.path))
        if not path.is_absolute() or not path.is_relative_to(self.warehouse):
            raise CatalogRefusal("ForeignWarehousePath")
        if path.resolve() != path:
            raise CatalogRefusal("IndirectWarehousePath")
        return path

    def generation(self, location):
        return "sha256:" + hashlib.sha256(self.local_path(location).read_bytes()).hexdigest()

    def reconcile(self, request):
        # Missing receipt is not proof of noncommit and never authorizes resend.
        db = self.connection()
        try:
            row = db.execute("SELECT request_wire,receipt_wire FROM actql_table_commits WHERE request_cid=?",
                             (request["request_cid"],)).fetchone()
        finally:
            db.close()
        if row is None:
            return None
        if row[0] != canonical_envelope(request):
            raise CatalogRefusal("ForeignOriginalOperation")
        return json.loads(row[1])

    def inspect_target(self, request):
        """Current-use observation, never proof about an original commit."""
        if request["catalog_identity_cid"] != self.catalog_cid or \
                envelope_cid({k: v for k, v in request.items() if k != "request_cid"}) != request["request_cid"]:
            raise CatalogRefusal("ForeignTableTarget")
        if not request["namespace"] or any("." in part for part in request["namespace"]):
            raise CatalogRefusal("UnsupportedNamespaceSpelling")
        try:
            table = self.load_table((*request["namespace"], request["table_name"]))
        except NoSuchTableError:
            return None
        mapping = json.loads(table.metadata.properties.get("actql.storage-mapping", "null"))
        if not isinstance(mapping, dict):
            raise CatalogRefusal("ForeignTableStorageMapping")
        return {"table_uuid": str(table.metadata.table_uuid),
                "generation_cid": self.generation(table.metadata_location),
                "schema_cid": table.metadata.properties.get("actql.schema-cid"),
                "storage_mapping_cid": mapping.get("mapping_cid")}

    def write_claimed(self, request, mapping, rows, reservation):
        """Internal physical boundary; no public installer calls this yet."""
        if self.context is not None:
            raise CatalogRefusal("ConcurrentAdapterUse")
        if len(canonical_envelope(request).encode("utf-8")) > 65536:
            raise CatalogRefusal("OperationByteLimit")
        if request["catalog_identity_cid"] != self.catalog_cid or \
                request["storage_mapping_cid"] != mapping["mapping_cid"] or \
                request["schema_cid"] != mapping["schema_cid"]:
            raise CatalogRefusal("InputMappingBinding")
        if envelope_cid({k: v for k, v in request.items() if k != "request_cid"}) != request["request_cid"]:
            raise CatalogRefusal("OperationIdentity")
        if self.reconcile(request) is not None:
            raise CatalogRefusal("AlreadyCommittedReconcileOnly")
        # SqlCatalog flattens namespace components with dots. Do not alias
        # different component tuples or derive a filesystem path from names.
        if not request["namespace"] or any("." in part for part in request["namespace"]):
            raise CatalogRefusal("UnsupportedNamespaceSpelling")
        identifier = (*request["namespace"], request["table_name"])
        physical = encode_rows(mapping, rows)  # Refuse types before staging.
        reserve(self, request, self.limits, reservation)
        self.context = (request, mapping, physical.num_rows)
        try:
            if request["action"] == "create":
                if request["expected_table"] is not None:
                    raise CatalogRefusal("CreatePrecondition")
                transaction = self.create_table_transaction(
                    identifier, iceberg_schema(mapping),
                    location=(self.warehouse / "tables" / request["request_cid"][7:]).as_uri(),
                    properties={"format-version": "2", "actql.schema-cid": mapping["schema_cid"],
                                "actql.storage-mapping": canonical_envelope(mapping)})
                if physical.num_rows:
                    transaction.append(physical)
            elif request["action"] == "replace":
                table = self.load_table(identifier)
                self.check_expected(request, table)
                transaction = table.transaction()
                transaction.overwrite(physical)
            else:
                raise CatalogRefusal("UnsupportedTableAction")
            transaction.set_properties({"actql.last-operation": request["request_cid"],
                                        "actql.data-policy-cid": request["data_policy_cid"]})
            transaction.commit_transaction()
            return self.reconcile(request)
        finally:
            self.context = None

    def check_expected(self, request, table):
        expected = request["expected_table"]
        if expected is None or str(table.metadata.table_uuid) != expected["table_uuid"] or \
                self.generation(table.metadata_location) != expected["generation_cid"]:
            raise CatalogRefusal("ExpectedGenerationConflict")
        mapping = json.loads(table.metadata.properties.get("actql.storage-mapping", "null"))
        if table.metadata.properties.get("actql.schema-cid") != request["schema_cid"] or \
                not isinstance(mapping, dict) or mapping.get("mapping_cid") != request["storage_mapping_cid"]:
            raise CatalogRefusal("SchemaReplacementUnsupported")

    def commit_table(self, table, requirements, updates):
        if self.context is None:
            raise CatalogRefusal("MissingClaimedOperation")
        request, mapping, row_count = self.context
        identifier = table.name()
        try:
            current = self.load_table(identifier)
        except NoSuchTableError:
            current = None
        if request["action"] == "create":
            if current is not None:
                raise CatalogRefusal("CreateNameConflict")
        else:
            if current is None:
                raise CatalogRefusal("ExpectedGenerationConflict")
            self.check_expected(request, current)
        staged = self._update_and_stage_table(current, identifier, requirements, updates)
        self._write_metadata(staged.metadata, staged.io, staged.metadata_location)
        path = self.local_path(staged.metadata_location)
        # Data, manifests, metadata and directory entries precede publication.
        durable_files = {path}
        for snapshot in staged.metadata.snapshots:
            durable_files.add(self.local_path(snapshot.manifest_list))
            for manifest in snapshot.manifests(staged.io):
                durable_files.add(self.local_path(manifest.manifest_path))
                for entry in manifest.fetch_manifest_entry(staged.io, discard_deleted=False):
                    durable_files.add(self.local_path(entry.data_file.file_path))
        for durable in durable_files:
            with durable.open("rb") as file:
                os.fsync(file.fileno())
        directories = {self.warehouse.parent}
        for durable in durable_files:
            parent = durable.parent
            while parent.is_relative_to(self.warehouse):
                directories.add(parent)
                parent = parent.parent
        for parent in directories:
            directory = os.open(parent, os.O_RDONLY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        receipt = seal({"version": "actql-table-receipt/0.1",
                        "request_cid": request["request_cid"],
                        "effect_identity_cid": request["effect_identity_cid"],
                        "catalog_identity_cid": request["catalog_identity_cid"],
                        "table_uuid": str(staged.metadata.table_uuid),
                        "generation_cid": self.generation(staged.metadata_location),
                        "metadata_location": staged.metadata_location,
                        "snapshot_id": str(staged.metadata.current_snapshot_id)
                        if staged.metadata.current_snapshot_id is not None else None,
                        "schema_cid": mapping["schema_cid"], "storage_mapping_cid": mapping["mapping_cid"],
                        "row_count": row_count}, "receipt_cid")
        namespace = ".".join(identifier[:-1])
        self.before_publication()
        db = self.connection()
        try:
            db.execute("BEGIN IMMEDIATE")
            if db.execute("SELECT 1 FROM actql_table_publication_fences WHERE request_cid=?", (request["request_cid"],)).fetchone():
                raise CatalogRefusal("PublicationFenced")
            if current is None:
                try:
                    db.execute("""INSERT INTO iceberg_tables
                        (catalog_name,table_namespace,table_name,metadata_location,previous_metadata_location)
                        VALUES (?,?,?,?,?)""",
                               (self.name, namespace, identifier[-1], staged.metadata_location, None))
                except sqlite3.IntegrityError as e:
                    raise CatalogRefusal("CreateNameConflict") from e
            else:
                result = db.execute("""UPDATE iceberg_tables SET metadata_location=?,previous_metadata_location=?
                    WHERE catalog_name=? AND table_namespace=? AND table_name=? AND metadata_location=?""",
                                    (staged.metadata_location, current.metadata_location, self.name,
                                     namespace, identifier[-1], current.metadata_location))
                if result.rowcount != 1:
                    raise CatalogRefusal("ExpectedGenerationConflict")
            db.execute("INSERT INTO actql_table_commits VALUES (?,?,?,?)",
                       (request["request_cid"], canonical_envelope(request), canonical_envelope(receipt), staged.metadata_location))
            db.commit()
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()
        self.after_publication()
        return CommitTableResponse(metadata=staged.metadata, metadata_location=staged.metadata_location)

    def after_publication(self):
        """Return path only; subclasses may model a lost reply in tests."""

    def before_publication(self):
        """Physical staging boundary for stop/concurrent-commit diagnostics."""

    def read_generation(self, receipt, mapping):
        if receipt["catalog_identity_cid"] != self.catalog_cid or \
                receipt["storage_mapping_cid"] != mapping["mapping_cid"] or \
                receipt["schema_cid"] != mapping["schema_cid"] or \
                self.generation(receipt["metadata_location"]) != receipt["generation_cid"]:
            raise CatalogRefusal("ReadGenerationBinding")
        io = self._load_file_io({}, receipt["metadata_location"])
        metadata = FromInputFile.table_metadata(io.new_input(receipt["metadata_location"]))
        if str(metadata.table_uuid) != receipt["table_uuid"] or \
                metadata.properties.get("actql.schema-cid") != mapping["schema_cid"] or \
                metadata.properties.get("actql.storage-mapping") != canonical_envelope(mapping):
            raise CatalogRefusal("ReadTableIdentity")
        table = Table(("immutable", "read"), metadata, receipt["metadata_location"], io, self)
        output = []
        for task in table.scan().plan_files():
            if task.delete_files:
                raise CatalogRefusal("ExternalDeleteFilesUnsupported")
            raw = pq.read_table(self.local_path(task.file.file_path))
            output.extend(decode_physical(mapping, raw))
        if len(output) != receipt["row_count"]:
            raise CatalogRefusal("ReadRowCount")
        return output
