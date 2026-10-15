"""Trusted Host assembly of the existing Store on one original Native DB.

The caller retains the original durable initialization intent, selected Library
and funding. This physical connection creates none of those capabilities.
"""
from pathlib import Path
import os

from ._local_files import LocalFileRoot, _PayloadFile
from ._local_native_domain_custody import _OriginalDomainReadFunctions
from ._local_native_sqlite import _OriginalSqliteCustody
from ._local_native_sqlite_database import (
    _OriginalDatabaseCustody, _OriginalDatabaseError, _OriginalDatabaseFunctions)
from ._local_native_storage import _NativeByteDatabase
from ._local_storage import LocalByteStore, LocalStorageError, LocalStorageInitializationError


def _open_original_native_store(path: Path, root: LocalFileRoot, *,
                                library: _OriginalSqliteCustody,
                                functions: _OriginalDatabaseFunctions,
                                read: _OriginalDomainReadFunctions,
                                max_records: int, max_record_bytes: int,
                                max_payload_bytes: int,
                                new_file: _PayloadFile | None = None) -> LocalByteStore:
    """Same original File root/Database; restore is existing-only, never repair.

    Fresh callers must have persisted the existing initialization marker before
    passing its exclusive empty-file acquisition. An uncertain Native open is
    returned in the same Store cleanup carrier; it cannot create another claim,
    connection, schema or grant. The parent Library/Root remains caller-owned.
    """
    if (type(root) is not LocalFileRoot
            or type(library) is not _OriginalSqliteCustody
            or type(functions) is not _OriginalDatabaseFunctions
            or type(read) is not _OriginalDomainReadFunctions
            or functions.library is not library._functions.library
            or read.library is not functions.library
            or new_file is not None and type(new_file) is not _PayloadFile):
        raise ValueError('Original Native Store selection is unavailable')
    store = LocalByteStore.__new__(LocalByteStore)
    store._prepare_physical_path(path, max_records=max_records,
                                max_record_bytes=max_record_bytes,
                                max_payload_bytes=max_payload_bytes)
    path = store._physical_path
    with root._lock:
        directory = os.fstat(root._open())
        if (directory.st_dev, directory.st_ino) != store._physical_parent:
            raise LocalStorageError('Foreign original Native Store directory')
        store._native_file_root = root
        ownership = None
        if new_file is not None:
            observed = root.claim_empty_store_file(new_file, path)
            ownership = (observed.device, observed.inode)
            store._physical_original = ownership
            store._created = True
        else:
            # No O_CREAT or empty-file inference on restoration. Schema3 is
            # checked by the existing Native Database's existing-only entry.
            store._physical_original = store._file_generation(path.lstat())
        store._observe_generation()
        try:
            original = _OriginalDatabaseCustody._open_original(
                library, functions, read, path=str(path),
                max_body_bytes=max_record_bytes, ownership=ownership)
        except _OriginalDatabaseError as error:
            # Registration precedes cleanup or propagation. Unknown partial
            # custody may refuse _local(), so retain it without another call.
            port = _NativeByteDatabase.__new__(_NativeByteDatabase)
            port._original = error.cleanup_database
            store._physical = port
            raise LocalStorageInitializationError(store) from error
        except BaseException as error:
            # A known entry refusal can happen after the one-time file claim.
            # It is not a foreign-operation Unknown, but the same claimed file
            # and pending Store still belong to the original caller.
            raise LocalStorageInitializationError(store) from error
        port = _NativeByteDatabase.__new__(_NativeByteDatabase)
        port._original = original
        store._physical = port
        try:
            original._local()
            store._observe_generation()
        except BaseException as error:
            raise LocalStorageInitializationError(store) from error
        store._ready = True
        return store
