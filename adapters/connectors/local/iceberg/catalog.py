"""Atomic local Catalog publication, not a second Effect state machine.

Only the bulk Effect adapter may call write_claimed after the common Ledger's
durable send claim and current-authority check. This module does physical I/O;
it does not issue approval, decide retries, or infer success from the head.
"""
import hashlib
import json
import os
import sqlite3
import re
import uuid
from pathlib import Path
from io import BytesIO as _BytesIO
from urllib.parse import unquote, urlparse

import pyarrow.parquet as pq
from pyiceberg.catalog.sql import SqlCatalog
from pyiceberg.exceptions import NoSuchTableError, TableAlreadyExistsError
from pyiceberg.table import CommitTableResponse, Table
from pyiceberg.serializers import FromInputFile, FromByteStream as _FromByteStream, Compressor as _Compressor

from physical import (PhysicalRefusal, canonical_envelope, check_mapping, decode_physical,
                      encode_rows, envelope_cid, iceberg_schema, seal)
from custody import CustodyIO, install_custody, reserve, claim_file, charge_file, cleanup_after_stop


# Original pinned PyArrow21 ReaderProperties defaults, not Run capacities.
# The focused test binds these two dependency facts to its installed upstream
# parquet/properties.h. Never widen either existing parser bound for a footer.
_PARQUET_THRIFT_STRING_DEFAULT = 100_000_000
_PARQUET_THRIFT_CONTAINER_DEFAULT = 1_000_000
# Fixed streaming work window, not a file-size, expansion or acceptance limit.
_METADATA_READ_QUANTUM = 65536


def _parquet_thrift_limits(footer_bytes):
    return (min(footer_bytes, _PARQUET_THRIFT_STRING_DEFAULT),
            min(footer_bytes, _PARQUET_THRIFT_CONTAINER_DEFAULT))


class CatalogRefusal(PhysicalRefusal):
    pass


def check_logical_schema(mapping, wire):
    """Check correspondence of common-issued bytes, never infer value contracts.

    The common owner admits and canonicalizes the original logical schema. This
    physical boundary preserves its exact preimage and only verifies that its
    columns correspond to the sealed physical mapping. It does not interpret
    extents, normalize text or replace common value admission.
    """
    if not isinstance(wire, str):
        raise CatalogRefusal("MissingTableLogicalSchema")
    try:
        raw = wire.encode("utf-8", errors="strict")
    except UnicodeError:
        raise CatalogRefusal("TableLogicalSchemaEncoding") from None
    if not 1 <= len(raw) <= 65536 or \
            "sha256:" + hashlib.sha256(raw).hexdigest() != mapping["schema_cid"]:
        raise CatalogRefusal("TableLogicalSchemaIdentity")
    from process_worker import check_shape, precheck_depth, unique_object, reject_constant
    try:
        precheck_depth(wire)
        fields = json.loads(wire, object_pairs_hook=unique_object, parse_constant=reject_constant)
        check_shape(fields)
    except (ValueError, UnicodeError, RecursionError):
        raise CatalogRefusal("TableLogicalSchemaShape") from None
    if not isinstance(fields, dict) or set(fields) != {c["name"] for c in mapping["columns"]}:
        raise CatalogRefusal("TableLogicalSchemaColumns")
    types = {"boolean": "boolean", "double": "number", "string": "string"}
    for column in mapping["columns"]:
        contract = fields[column["name"]]
        if column["presence"] == "conditional":
            if not isinstance(contract, dict) or set(contract) != {"contract", "presence"} or \
                    contract["presence"] != "conditional":
                raise CatalogRefusal("TableLogicalSchemaPresence")
            contract = contract["contract"]
        if not isinstance(contract, dict) or contract.get("type") != types[column["physical_type"]] or \
                type(contract.get("nullable")) is not bool or contract["nullable"] != column["nullable"]:
            raise CatalogRefusal("TableLogicalSchemaContract")
    return wire


class TableCatalog(SqlCatalog):
    """Pinned PyIceberg staging plus one SQLite head/receipt transaction.

    Committed generations retain their reservation. Unpublished staging is removable only after the
    existing Host process owner confirms stop and a durable publication fence.
    """

    def __init__(self, database, warehouse, catalog_cid, limits, before_materialization=None):
        # Resolve the operator-configured root once (macOS /var is an alias).
        # Data-file paths must thereafter stay within this canonical root.
        if before_materialization is not None and not callable(before_materialization):
            raise ValueError("InvalidTableConstructorObserver")
        self.before_materialization = before_materialization
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
        # Both original generation observations remain real file reads. Keep
        # one fixed scratch buffer instead of materializing the whole metadata
        # file merely to hash it. The caller backs this window before entry.
        with self.local_path(location).open("rb", buffering=0) as original:
            self._observe_material("metadata-hash", _METADATA_READ_QUANTUM)
            scratch = bytearray(_METADATA_READ_QUANTUM)
            view = memoryview(scratch)
            digest = hashlib.sha256()
            while count := original.readinto(scratch):
                digest.update(view[:count])
            return "sha256:" + digest.hexdigest()

    def _read_generation_metadata(self, io, location):
        input_file = io.new_input(location)
        if self.before_materialization is None:
            return FromInputFile.table_metadata(input_file)
        with input_file.open() as original:
            original.seek(0, os.SEEK_END)
            size = original.tell()
            original.seek(0)
            self._observe_material("metadata-input", size)
            # Observe before the bounded read and use this SAME byte snapshot
            # for codec preflight and the original upstream constructor. A
            # callback or later file growth cannot enlarge an admitted read.
            raw = original.read(size)
            if len(raw) != size or original.read(1):
                raise ValueError("TableMetadataFileChanged")
            with _BytesIO(raw) as snapshot:
                compression = _Compressor.get_compressor(input_file.location)
                decoded_size = size
                if input_file.location.endswith(".gz.metadata.json"):
                    self._observe_material("metadata-codec", _METADATA_READ_QUANTUM)
                    decoded_size = 0
                    # The SAME existing gzip codec owns validation, including
                    # concatenated members and CRC/truncation errors. Count in
                    # a fixed work window; never trust compressed size or ISIZE
                    # as a bound on the complete decoded metadata constructor.
                    with compression.stream_decompressor(snapshot) as decoded:
                        while block := decoded.read(_METADATA_READ_QUANTUM):
                            decoded_size += len(block)
                    snapshot.seek(0)
                self._observe_material("metadata-json", decoded_size)
                return _FromByteStream.table_metadata(byte_stream=snapshot, compression=compression)

    def reconcile(self, request):
        # Missing receipt is not proof of noncommit and never authorizes resend.
        db = self.connection()
        try:
            row = db.execute("SELECT request_wire,receipt_wire FROM actql_table_commits WHERE request_cid=?",
                             (request["request_cid"],)).fetchone()
            if row is None:
                row = db.execute("SELECT n.request_wire,n.receipt_wire FROM actql_table_noncommits n "
                                 "JOIN actql_table_publication_fences f USING(request_cid) "
                                 "WHERE n.request_cid=? AND f.request_wire=n.request_wire",
                                 (request["request_cid"],)).fetchone()
        finally:
            db.close()
        if row is None:
            return None
        if row[0] != canonical_envelope(request):
            raise CatalogRefusal("ForeignOriginalOperation")
        return json.loads(row[1])

    def confirm_noncommit(self, request, reason):
        """Persist original-operation nonpublication and its fence atomically.

        Called only for the writer's validated create/expected-version conflict,
        never for an HTTP status or an arbitrary exception. A committed original
        wins even if an error was raised on its return path. No staging files or
        reservations are reclaimed here; cleanup still requires physical stop.
        """
        if reason not in ("CreateNameConflict", "ExpectedGenerationConflict") or \
                (request["action"] == "create") != (reason == "CreateNameConflict"):
            raise CatalogRefusal("InvalidNoncommitReason")
        wire = canonical_envelope(request)
        db = self.connection()
        try:
            db.execute("BEGIN IMMEDIATE")
            committed = db.execute("SELECT request_wire,receipt_wire FROM actql_table_commits WHERE request_cid=?",
                                   (request["request_cid"],)).fetchone()
            if committed:
                if committed[0] != wire:
                    raise CatalogRefusal("ForeignOriginalOperation")
                db.commit()
                return json.loads(committed[1])
            allocation = db.execute("SELECT request_wire FROM actql_table_allocations WHERE request_cid=?",
                                    (request["request_cid"],)).fetchone()
            if allocation is None or allocation[0] != wire:
                raise CatalogRefusal("NoncommitAllocationBinding")
            existing = db.execute("SELECT request_wire,receipt_wire FROM actql_table_noncommits WHERE request_cid=?",
                                  (request["request_cid"],)).fetchone()
            if existing:
                if existing[0] != wire:
                    raise CatalogRefusal("ForeignOriginalOperation")
                db.commit()
                return json.loads(existing[1])
            fence = db.execute("SELECT request_wire FROM actql_table_publication_fences WHERE request_cid=?",
                               (request["request_cid"],)).fetchone()
            if fence and fence[0] != wire:
                raise CatalogRefusal("ForeignOriginalOperation")
            receipt = seal({"version": "actql-table-noncommit-receipt/0.1",
                            "request_cid": request["request_cid"],
                            "effect_identity_cid": request["effect_identity_cid"],
                            "catalog_identity_cid": request["catalog_identity_cid"],
                            "schema_cid": request["schema_cid"],
                            "storage_mapping_cid": request["storage_mapping_cid"],
                            "reason": reason}, "receipt_cid")
            db.execute("INSERT OR IGNORE INTO actql_table_publication_fences(request_cid,request_wire) VALUES (?,?)",
                       (request["request_cid"], wire))
            db.execute("INSERT INTO actql_table_noncommits VALUES (?,?,?)",
                       (request["request_cid"], wire, canonical_envelope(receipt)))
            db.commit()
            return receipt
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()

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

    def resolve_generation(self, selector):
        """Bind a new read to one published generation, not an Effect outcome.

        Read head and its original publication record in one SQLite snapshot.
        Later replacement may change the head, but cannot change this binding.
        Current read authority belongs to the Host, before and after this I/O.
        """
        if not isinstance(selector, dict) or set(selector) != {
                "catalog_identity_cid", "namespace", "table_name", "table_uuid", "schema_cid"}:
            raise CatalogRefusal("TableReadSelectorShape")
        if selector["catalog_identity_cid"] != self.catalog_cid:
            raise CatalogRefusal("ForeignReadCatalog")
        namespace, name = selector["namespace"], selector["table_name"]
        if not isinstance(namespace, list) or not 1 <= len(namespace) <= 32 or \
                any(not isinstance(part, str) or not 1 <= len(part) <= 256 or
                    any(char in part for char in ".\0\r\n") for part in namespace) or \
                not isinstance(name, str) or not 1 <= len(name) <= 256 or \
                any(char in name for char in "\0\r\n"):
            raise CatalogRefusal("TableReadSelectorName")
        try:
            if str(uuid.UUID(selector["table_uuid"])) != selector["table_uuid"]:
                raise ValueError()
        except (ValueError, TypeError, AttributeError):
            raise CatalogRefusal("TableReadSelectorIdentity") from None
        if not isinstance(selector["schema_cid"], str) or \
                not re.fullmatch(r"sha256:[0-9a-f]{64}", selector["schema_cid"]):
            raise CatalogRefusal("TableReadSelectorIdentity")
        db = self.connection()
        try:
            source = """FROM iceberg_tables t LEFT JOIN actql_table_commits c
                ON c.metadata_location=t.metadata_location
                WHERE t.catalog_name=? AND t.table_namespace=? AND t.table_name=?"""
            parameters = (self.name, ".".join(namespace), name)
            if self.before_materialization is not None:
                # The geometry and original material belong to ONE SQLite
                # read snapshot. The original Host callback may reenter or
                # commit a later head; it cannot retarget this transaction.
                db.execute("BEGIN")
                lengths = db.execute("""SELECT length(CAST(t.metadata_location AS BLOB)),
                    length(CAST(c.receipt_wire AS BLOB)),length(CAST(c.request_wire AS BLOB)) """ +
                    source, parameters).fetchmany(2)
                self._observe_material("catalog-record",
                                       sum(size or 0 for row in lengths for size in row),
                                       len(lengths), 3)
            # At most two fixed three-scalar rows precede the callback; the
            # installing caller backs those controls before entry. Payload text
            # and receipt/request JSON trees are constructed below. Binding and
            # value validation still run once on these same original bytes.
            records = db.execute("SELECT t.metadata_location,c.receipt_wire,c.request_wire " +
                                 source, parameters).fetchmany(2)
        finally:
            db.close()
        if not records:
            raise CatalogRefusal("TableReadNotFound")
        if len(records) != 1 or records[0][1] is None:
            raise CatalogRefusal("TableReadPublicationRecord")
        location, receipt_wire, request_wire = records[0]
        receipt, request = json.loads(receipt_wire), json.loads(request_wire)
        if not isinstance(receipt, dict) or set(receipt) != {
                "version", "request_cid", "effect_identity_cid", "catalog_identity_cid", "table_uuid",
                "generation_cid", "metadata_location", "snapshot_id", "schema_cid",
                "storage_mapping_cid", "row_count", "receipt_cid"} or \
                receipt.get("receipt_cid") != envelope_cid(
                {k: v for k, v in receipt.items() if k != "receipt_cid"}) or \
                receipt.get("version") != "actql-table-receipt/0.1" or \
                receipt.get("metadata_location") != location or \
                receipt.get("catalog_identity_cid") != self.catalog_cid or \
                receipt.get("table_uuid") != selector["table_uuid"] or \
                receipt.get("schema_cid") != selector["schema_cid"]:
            raise CatalogRefusal("TableReadPublicationBinding")
        if not isinstance(request, dict) or request.get("request_cid") != envelope_cid(
                {k: v for k, v in request.items() if k != "request_cid"}) or \
                request.get("request_cid") != receipt.get("request_cid") or \
                request.get("catalog_identity_cid") != self.catalog_cid or \
                request.get("namespace") != namespace or request.get("table_name") != name or \
                request.get("schema_cid") != selector["schema_cid"] or \
                request.get("effect_identity_cid") != receipt.get("effect_identity_cid") or \
                request.get("storage_mapping_cid") != receipt.get("storage_mapping_cid"):
            raise CatalogRefusal("TableReadPublicationBinding")
        if self.generation(location) != receipt.get("generation_cid"):
            raise CatalogRefusal("ReadGenerationBinding")
        io = self._load_file_io({}, location)
        metadata = self._read_generation_metadata(io, location)
        mapping = json.loads(metadata.properties.get("actql.storage-mapping", "null"))
        if not isinstance(mapping, dict):
            raise CatalogRefusal("ForeignTableStorageMapping")
        _, _, schema_wire = self._generation_read_material(receipt, mapping, metadata=metadata, io=io)
        return {"receipt": receipt, "mapping": mapping, "schema_wire": schema_wire}

    def write_claimed(self, request, mapping, rows, reservation, schema_wire):
        """Internal physical boundary, called only after the original send claim."""
        if self.context is not None:
            raise CatalogRefusal("ConcurrentAdapterUse")
        carrier = request.get("input_carrier")
        if not isinstance(carrier, dict) or set(carrier) != {"kind", "cid"} or \
                not isinstance(carrier["cid"], str) or \
                not re.fullmatch(r"sha256:[0-9a-f]{64}", carrier["cid"]):
            raise CatalogRefusal("InvalidTableCarrierReference")
        if carrier["kind"] != "relation" or request.get("action") not in {"create", "replace"}:
            raise CatalogRefusal("UnsupportedTableCarrierOperation")
        if len(canonical_envelope(request).encode("utf-8")) > 65536:
            raise CatalogRefusal("OperationByteLimit")
        if request["catalog_identity_cid"] != self.catalog_cid or \
                request["storage_mapping_cid"] != mapping["mapping_cid"] or \
                request["schema_cid"] != mapping["schema_cid"]:
            raise CatalogRefusal("InputMappingBinding")
        if envelope_cid({k: v for k, v in request.items() if k != "request_cid"}) != request["request_cid"]:
            raise CatalogRefusal("OperationIdentity")
        check_mapping(mapping)
        check_logical_schema(mapping, schema_wire)
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
                if table.metadata.properties.get("actql.logical-schema") != schema_wire:
                    raise CatalogRefusal("SchemaReplacementUnsupported")
                transaction = table.transaction()
                transaction.overwrite(physical)
            else:
                raise CatalogRefusal("UnsupportedTableAction")
            transaction.set_properties({"actql.last-operation": request["request_cid"],
                                        "actql.data-policy-cid": request["data_policy_cid"],
                                        "actql.logical-schema": schema_wire})
            transaction.commit_transaction()
            return self.reconcile(request)
        except (TableAlreadyExistsError, NoSuchTableError) as error:
            # Translate only action-specific upstream target conflicts. Other
            # upstream exceptions remain uncertain, not fabricated noncommit.
            if isinstance(error, TableAlreadyExistsError) and request["action"] == "create":
                return self.confirm_noncommit(request, "CreateNameConflict")
            if isinstance(error, NoSuchTableError) and request["action"] == "replace":
                return self.confirm_noncommit(request, "ExpectedGenerationConflict")
            raise
        except CatalogRefusal as error:
            if str(error) in ("CreateNameConflict", "ExpectedGenerationConflict"):
                return self.confirm_noncommit(request, str(error))
            raise
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

    def generation_table(self, receipt, mapping, metadata=None):
        metadata, io, _ = self._generation_read_material(receipt, mapping, metadata=metadata)
        return Table(("immutable", "read"), metadata, receipt["metadata_location"], io, self)

    def _generation_read_material(self, receipt, mapping, metadata=None, io=None):
        # One original Mapping/schema validation and selected FileIO. The two
        # physical generation observations remain around actual metadata I/O;
        # a retained check result does not replace current external bytes.
        check_mapping(mapping)
        if receipt["catalog_identity_cid"] != self.catalog_cid or \
                receipt["storage_mapping_cid"] != mapping["mapping_cid"] or \
                receipt["schema_cid"] != mapping["schema_cid"] or \
                self.generation(receipt["metadata_location"]) != receipt["generation_cid"]:
            raise CatalogRefusal("ReadGenerationBinding")
        if io is None:
            io = self._load_file_io({}, receipt["metadata_location"])
        if metadata is None:
            metadata = self._read_generation_metadata(io, receipt["metadata_location"])
        if str(metadata.table_uuid) != receipt["table_uuid"] or \
                metadata.properties.get("actql.schema-cid") != mapping["schema_cid"] or \
                metadata.properties.get("actql.storage-mapping") != canonical_envelope(mapping) or \
                receipt["snapshot_id"] != (str(metadata.current_snapshot_id)
                                           if metadata.current_snapshot_id is not None else None) or \
                type(receipt["row_count"]) is not int or not 0 <= receipt["row_count"] <= 9007199254740991:
            raise CatalogRefusal("ReadTableIdentity")
        schema_wire = check_logical_schema(mapping, metadata.properties.get("actql.logical-schema"))
        return metadata, io, schema_wire

    def _observe_material(self, phase, size, rows=0, columns=0):
        if self.before_materialization is None:
            return
        # Exact primitive geometry only, never an amount, permission, source
        # identity or physical return. Keep JSON's exact integer domain.
        if any(type(value) is not int or not 0 <= value <= 9007199254740991
               for value in (size, rows, columns)):
            raise ValueError("InvalidTableConstructorGeometry")
        result = self.before_materialization(
            {"phase": phase, "bytes": size, "rows": rows, "columns": columns})
        if result is not None:
            raise ValueError("InvalidTableConstructorContinuation")

    def _read_generation_file(self, task):
        path = self.local_path(task.file.file_path)
        # Keep the SAME open descriptor for footer, native metadata and data.
        # Footer parsing is funded before ParquetFile's native constructor;
        # its declared container/string bounds cannot exceed that actual wire.
        with path.open("rb") as original:
            length = os.fstat(original.fileno()).st_size
            if length < 8:
                raise ValueError("InvalidTableParquetFooter")
            original.seek(-8, os.SEEK_END)
            tail = original.read(8)
            footer = int.from_bytes(tail[:4], "little")
            if tail[4:] != b"PAR1" or not 1 <= footer <= length - 8:
                raise ValueError("InvalidTableParquetFooter")
            self._observe_material("parquet-footer", footer + 8)
            original.seek(0)
            string_limit, container_limit = _parquet_thrift_limits(footer)
            parquet = pq.ParquetFile(original, thrift_string_size_limit=string_limit,
                                     thrift_container_size_limit=container_limit)
            try:
                metadata = parquet.metadata
                if metadata.num_rows != task.file.record_count:
                    raise ValueError("TableParquetRowCount")
                size = sum(metadata.row_group(group).column(column).total_uncompressed_size
                           for group in range(metadata.num_row_groups)
                           for column in range(metadata.num_columns))
                # Encoded file size cannot bound dictionary-expanded Arrow
                # material. The original footer supplies uncompressed sizes,
                # actual rows and physical columns BEFORE the data constructor.
                self._observe_material("parquet-read", size, metadata.num_rows, metadata.num_columns)
                return parquet.read()
            finally:
                parquet.close()

    def read_generation(self, receipt, mapping):
        table = self.generation_table(receipt, mapping)
        output = []
        for task in table.scan().plan_files():
            if task.delete_files:
                raise CatalogRefusal("ExternalDeleteFilesUnsupported")
            if self.before_materialization is None:
                raw = pq.read_table(self.local_path(task.file.file_path))
            else:
                raw = self._read_generation_file(task)
            output.extend(decode_physical(
                mapping, raw, before_materialization=self.before_materialization))
        if len(output) != receipt["row_count"]:
            raise CatalogRefusal("ReadRowCount")
        return output
