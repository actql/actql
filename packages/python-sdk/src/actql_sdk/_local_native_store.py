"""Trusted Host assembly of the existing Store on one original Native DB.

The caller retains the original durable initialization intent, selected Library
and funding. This physical connection creates none of those capabilities.
"""
from pathlib import Path
import os
from typing import NoReturn

from ._local_core import LocalCore
from ._local_files import LocalFileRoot, _PayloadFile
from ._local_native_domain_custody import _OriginalDomainReadFunctions
from ._local_native_sqlite import _OriginalSqliteCustody
from ._local_native_sqlite_database import (
    _OriginalDatabaseCustody, _OriginalDatabaseError, _OriginalDatabaseFunctions)
from ._local_native_storage import _NativeByteDatabase
from ._local_storage import LocalByteStore, LocalStorageError, LocalStorageInitializationError


class _OriginalNativeStoreSelection:
    """Private linkage, not a Library acquisition, grant or new Store Owner.

    The trusted installed caller already owns this Core and separately funded
    selected Library. Native still enforces its one-Database lifetime; this
    linkage cannot reset it or create a replacement after response loss.
    """
    __slots__ = ('_original', '_core', '_identity', '_library', '_functions', '_read')

    def __init__(self, core: LocalCore, library: _OriginalSqliteCustody,
                 functions: _OriginalDatabaseFunctions,
                 read: _OriginalDomainReadFunctions) -> None:
        if (type(core) is not LocalCore or type(library) is not _OriginalSqliteCustody
                or type(functions) is not _OriginalDatabaseFunctions
                or type(read) is not _OriginalDomainReadFunctions
                or functions.library is not library._functions.library
                or read.library is not functions.library):
            raise ValueError('Original Native installation Store selection is unavailable')
        self._original = self
        self._core, self._identity = core, core._identity
        self._library, self._functions, self._read = library, functions, read
        self.require_core(core)

    def __copy__(self) -> NoReturn:
        raise TypeError('Original Native Store selection cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original Native Store selection cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original Native Store selection cannot be serialized')

    def require_core(self, core: LocalCore) -> None:
        if (self._original is not self or self._core is not core
                or core._identity is not self._identity
                or core._closed or core._closing or core._retired):
            raise ValueError('Foreign or retired original Native Store Core')

    def open(self, core: LocalCore, path: Path, root: LocalFileRoot, *,
             max_records: int, max_record_bytes: int, max_payload_bytes: int,
             max_inspection_queries: int | None = None,
             new_file: _PayloadFile | None = None) -> LocalByteStore:
        # Core serializes its original installation. This is lifecycle identity
        # only, not a current Account/publisher/Run permission decision.
        with core._lock:
            self.require_core(core)
            store = _open_original_native_store(path, root, library=self._library,
                functions=self._functions, read=self._read, max_records=max_records,
                max_record_bytes=max_record_bytes, max_payload_bytes=max_payload_bytes,
                max_inspection_queries=max_inspection_queries,
                new_file=new_file)
            try:
                self.require_core(core)
            except BaseException as error:
                raise LocalStorageInitializationError(store) from error
            return store


def _open_original_native_store(path: Path, root: LocalFileRoot, *,
                                library: _OriginalSqliteCustody,
                                functions: _OriginalDatabaseFunctions,
                                read: _OriginalDomainReadFunctions,
                                max_records: int, max_record_bytes: int,
                                max_payload_bytes: int,
                                max_inspection_queries: int | None = None,
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
                                max_payload_bytes=max_payload_bytes,
                                max_inspection_queries=max_inspection_queries)
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
