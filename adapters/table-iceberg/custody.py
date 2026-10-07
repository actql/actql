"""Bounded physical file custody in the Catalog database.

These are file allocations, not Effect states or approval/retry decisions.
Reservations remain charged while publication/cleanup is uncertain. The initial
provider deliberately has no GC; even unused committed reservation is retained.
"""
import io
import os

from pyiceberg.io import FileIO, OutputFile

from physical import PhysicalRefusal, canonical_envelope


class CustodyStream(io.RawIOBase):
    def __init__(self, catalog, request_cid, path, stream):
        super().__init__()
        self.catalog, self.request_cid, self.path, self.stream = catalog, request_cid, path, stream

    def writable(self):
        return True

    def tell(self):
        return self.stream.tell()

    def write(self, data):
        self.catalog.charge_file(self.request_cid, str(self.path), len(data))
        return self.stream.write(data)

    def flush(self):
        if not self.stream.closed:
            self.stream.flush()

    def close(self):
        if self.closed:
            return
        # Completion follows flush/fsync/close, never precedes them.
        self.stream.flush()
        os.fsync(self.stream.fileno())
        self.stream.close()
        super().close()


class CustodyOutput(OutputFile):
    def __init__(self, catalog, request_cid, delegate):
        super().__init__(delegate.location)
        self.catalog, self.request_cid, self.delegate = catalog, request_cid, delegate

    def __len__(self):
        return len(self.delegate)

    def exists(self):
        return self.delegate.exists()

    def to_input_file(self):
        return self.delegate.to_input_file()

    def create(self, overwrite=False):
        path = self.catalog.local_path(self.location)
        self.catalog.claim_file(self.request_cid, str(path))
        path.parent.mkdir(parents=True, exist_ok=True)
        # Never truncate a retained/published file, even if the upstream writer
        # requests overwrite=True for a newly generated UUID path.
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
        descriptor = os.open(path, flags, 0o600)
        return CustodyStream(self.catalog, self.request_cid, path, os.fdopen(descriptor, "wb"))


class CustodyIO(FileIO):
    def __init__(self, catalog, request_cid, delegate):
        super().__init__(delegate.properties)
        self.catalog, self.request_cid, self.delegate = catalog, request_cid, delegate

    def new_input(self, location):
        self.catalog.local_path(location)
        return self.delegate.new_input(location)

    def new_output(self, location):
        return CustodyOutput(self.catalog, self.request_cid, self.delegate.new_output(location))

    def delete(self, location):
        raise PhysicalRefusal("CatalogFileCleanupNotAuthorized")


def install_custody(catalog, limits):
    if set(limits) != {"bytes", "files", "operations"} or any(
            type(value) is not int or not 1 <= value <= 9007199254740991 for value in limits.values()):
        raise PhysicalRefusal("InvalidPersistentLimits")
    db = catalog.connection()
    try:
        db.execute("BEGIN IMMEDIATE")
        db.execute("""CREATE TABLE IF NOT EXISTS actql_table_limits (
            singleton INTEGER PRIMARY KEY CHECK(singleton=1), catalog_cid TEXT NOT NULL,
            limits_wire TEXT NOT NULL)""")
        current = db.execute("SELECT catalog_cid,limits_wire FROM actql_table_limits WHERE singleton=1").fetchone()
        binding = (catalog.catalog_cid, canonical_envelope(limits))
        if current is None:
            db.execute("INSERT INTO actql_table_limits VALUES (1,?,?)", binding)
        elif current != binding:
            raise PhysicalRefusal("PersistentLimitBinding")
        db.execute("""CREATE TABLE IF NOT EXISTS actql_table_allocations (
            request_cid TEXT PRIMARY KEY, request_wire TEXT NOT NULL,
            reserved_bytes INTEGER NOT NULL, reserved_files INTEGER NOT NULL,
            charged_bytes INTEGER NOT NULL DEFAULT 0)""")
        db.execute("""CREATE TABLE IF NOT EXISTS actql_table_files (
            path TEXT PRIMARY KEY, request_cid TEXT NOT NULL, charged_bytes INTEGER NOT NULL DEFAULT 0)""")
        db.commit()
    except BaseException:
        db.rollback()
        raise
    finally:
        db.close()


def reserve(catalog, request, limits, reservation):
    if set(reservation) != {"bytes", "files"} or any(type(v) is not int or v < 1 for v in reservation.values()):
        raise PhysicalRefusal("InvalidFileReservation")
    db = catalog.connection()
    try:
        db.execute("BEGIN IMMEDIATE")
        if db.execute("SELECT 1 FROM actql_table_allocations WHERE request_cid=?", (request["request_cid"],)).fetchone():
            raise PhysicalRefusal("ExistingAllocationReconcileOnly")
        size, files, count = db.execute("SELECT COALESCE(SUM(reserved_bytes),0),COALESCE(SUM(reserved_files),0),COUNT(*) FROM actql_table_allocations").fetchone()
        if size + reservation["bytes"] > limits["bytes"] or files + reservation["files"] > limits["files"] or count >= limits["operations"]:
            raise PhysicalRefusal("PersistentCapacityExceeded")
        db.execute("INSERT INTO actql_table_allocations VALUES (?,?,?,?,0)",
                   (request["request_cid"], canonical_envelope(request), reservation["bytes"], reservation["files"]))
        db.commit()
    except BaseException:
        db.rollback()
        raise
    finally:
        db.close()


def claim_file(catalog, request_cid, path):
    db = catalog.connection()
    try:
        db.execute("BEGIN IMMEDIATE")
        allocation = db.execute("SELECT reserved_files FROM actql_table_allocations WHERE request_cid=?", (request_cid,)).fetchone()
        count = db.execute("SELECT COUNT(*) FROM actql_table_files WHERE request_cid=?", (request_cid,)).fetchone()[0]
        if allocation is None or count >= allocation[0]:
            raise PhysicalRefusal("FileCapacityExceeded")
        db.execute("INSERT INTO actql_table_files VALUES (?,?,0)", (path, request_cid))
        db.commit()
    except BaseException:
        db.rollback()
        raise
    finally:
        db.close()


def charge_file(catalog, request_cid, path, amount):
    db = catalog.connection()
    try:
        db.execute("BEGIN IMMEDIATE")
        result = db.execute("""UPDATE actql_table_allocations SET charged_bytes=charged_bytes+?
            WHERE request_cid=? AND charged_bytes+?<=reserved_bytes""", (amount, request_cid, amount))
        if result.rowcount != 1:
            raise PhysicalRefusal("ByteCapacityExceeded")
        if db.execute("UPDATE actql_table_files SET charged_bytes=charged_bytes+? WHERE path=? AND request_cid=?",
                      (amount, path, request_cid)).rowcount != 1:
            raise PhysicalRefusal("FileCustodyMissing")
        db.commit()
    except BaseException:
        db.rollback()
        raise
    finally:
        db.close()
