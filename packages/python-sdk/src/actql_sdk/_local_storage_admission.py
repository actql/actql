"""Read the selected SQLite catalog without recovering an unadmitted Store."""
from collections.abc import Callable, Iterator
from contextlib import contextmanager
import fcntl
import os
from pathlib import Path
import sqlite3
import stat
from tempfile import TemporaryDirectory

from ._local_storage_physical import _SQLITE_STATEMENT_CACHE, _SQLiteByteDatabase, _TrackedSQLiteConnection

# A shared lock over SQLite's rollback locking bytes excludes its RESERVED,
# PENDING and EXCLUSIVE writes while the original files are copied.
_LOCK_BYTE = 0x40000000
_LOCK_BYTES = 512
_COPY_CHUNK = 65536
_JOURNAL_MAGIC = bytes.fromhex('d9d505f920a163d7')

_Stamp = tuple[int, int, int, int, int, int, int]
_Snapshot = tuple[_Stamp, _Stamp, _Stamp | None, _Stamp | None, _Stamp | None]


class _CatalogInspection:
    def __init__(self) -> None:
        self._children: list[Callable[[], None]] = []
        self.failure: BaseException | None = None

    @contextmanager
    def hold(self, close: Callable[[], None]) -> Iterator[None]:
        depth = len(self._children)
        self._children.append(close)
        try:
            yield
        except BaseException:
            if self.failure is None:
                try:
                    self._close_to(depth)
                except BaseException:
                    # The original failure remains primary. The same Store
                    # owns this child until an actual close acknowledges it.
                    pass
            raise
        else:
            self._close_to(depth)

    def _close_to(self, depth: int) -> None:
        while len(self._children) > depth:
            try:
                self._children[-1]()
            except BaseException as failure:
                if self.failure is None:
                    self.failure = failure
                raise
            self._children.pop()

    def close(self) -> None:
        self._close_to(0)


def _stamp(info: os.stat_result) -> _Stamp:
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def _sidecar(path: Path) -> _Stamp | None:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
            or info.st_mode & 0o077):
        raise ValueError('Original Local rollback sidecar is unavailable')
    return _stamp(info)


def _copy_exact(source: int, expected: _Stamp, destination: Path,
                inspection: _CatalogInspection) -> None:
    if _stamp(os.fstat(source)) != expected:
        raise ValueError('Original Local inspection file changed')
    remaining = expected[4]
    offset = 0
    target = destination.open('xb')
    with inspection.hold(target.close):
        while remaining:
            span = min(remaining, _COPY_CHUNK)
            data = os.pread(source, span, offset)
            if len(data) != span or target.write(data) != span:
                raise ValueError('Incomplete original Local inspection file')
            remaining -= span
            offset += span
    if _stamp(os.fstat(source)) != expected:
        raise ValueError('Original Local inspection file changed')


def _initial_sdk_counter(database: _SQLiteByteDatabase, key: str, bound: int) -> tuple[int, bytes]:
    row = database.read_row(key, bound)
    if row is None:
        raise ValueError('Original SDK Submission usage custody is missing')
    generation, body, kind, extent = row
    if (type(generation) is not int or generation < 0 or type(body) is not bytes
            or kind != 'blob' or type(extent) is not int or not 0 < extent == len(body) <= bound):
        raise ValueError('Original SDK Submission usage custody is invalid')
    return generation, body


def _canonical_nonnegative_counter(value: bytes) -> bool:
    return (bool(value) and len(value) <= 19 and value.isdigit()
            and (len(value) == 1 or not value.startswith(b'0')) and int(value) < 2**63)


def _check_snapshot_catalog(path: Path, inspection: _CatalogInspection, *,
                            writable: bool, retained: bool, ordinary: bool) -> None:
    mode = 'rw' if writable else 'ro'
    connection = sqlite3.connect(path.as_uri() + '?mode=' + mode, uri=True,
                                 isolation_level=None, timeout=0.0,
                                 factory=_TrackedSQLiteConnection, cached_statements=_SQLITE_STATEMENT_CACHE)
    with inspection.hold(connection.close):
        database = _SQLiteByteDatabase(connection)
        database.begin_read()
        if connection.execute('PRAGMA main.user_version').fetchone() != (0,):
            raise ValueError('Unsupported Local rollback Store generation')
        database._journal_schema()
        database.require_usage_mode(retained)
        if ordinary:
            issued_generation, issued = _initial_sdk_counter(
                database, 'namespace:31:client_submitted_intent_custody:issued', 19)
            usage_generation, usage = _initial_sdk_counter(
                database, 'namespace:29:client_submitted_intent_usage:retained', 39)
            fields = usage.split(b':')
            if (issued_generation != usage_generation or not _canonical_nonnegative_counter(issued)
                    or len(fields) != 2 or fields[0] != issued
                    or not _canonical_nonnegative_counter(fields[1])
                    or (issued == b'0' and fields[1] != b'0')):
                raise ValueError('Original SDK Submission usage custody is invalid')


def inspect_retained_catalog(path: Path, parent: tuple[int, int],
                             generation: tuple[int, int], limit: int,
                             inspection: _CatalogInspection, *, retained: bool, ordinary: bool) -> Callable[[], None]:
    journal = path.with_name(path.name + '-journal')
    wal = path.with_name(path.name + '-wal')
    shared_memory = path.with_name(path.name + '-shm')

    def observe() -> _Snapshot:
        directory = _stamp(path.parent.lstat())
        database = _sidecar(path)
        if (directory[:2] != parent or not stat.S_ISDIR(directory[2])
                or directory[2] & 0o077 or directory[3] != os.getuid()
                or database is None or database[:2] != generation):
            raise ValueError('Original Local Store generation changed during inspection')
        return (directory, database, _sidecar(journal), _sidecar(wal), _sidecar(shared_memory))

    acquired = observe()
    if acquired[3] is not None or acquired[4] is not None:
        raise ValueError('Unsupported WAL sidecars for original Local rollback Store')

    def same_original() -> None:
        if observe() != acquired:
            raise ValueError('Original Local Store changed during retained inspection')

    try:
        _check_snapshot_catalog(path, inspection, writable=False, retained=retained, ordinary=ordinary)
    except sqlite3.OperationalError as error:
        # Do not turn an active writer, malformed catalog, or other native
        # refusal into an alternative inspection route.
        hot = acquired[2]
        if (inspection.failure is not None
                or getattr(error, 'sqlite_errorcode', None) != sqlite3.SQLITE_READONLY_ROLLBACK
                or hot is None):
            raise
        if acquired[1][4] + hot[4] > limit:
            raise ValueError('Original Local rollback inspection extent exceeded') from error
        database_fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK)
        with inspection.hold(lambda: os.close(database_fd)):
            fcntl.lockf(database_fd, fcntl.LOCK_SH | fcntl.LOCK_NB, _LOCK_BYTES, _LOCK_BYTE)
            same_original()
            journal_fd = os.open(journal, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK)
            with inspection.hold(lambda: os.close(journal_fd)):
                # This Store has never used attached databases. A named
                # super-journal can reference files outside either owner.
                tail = os.pread(journal_fd, 16, max(0, hot[4] - 16))
                if len(tail) == 16 and tail[8:] == _JOURNAL_MAGIC and any(tail[:4]):
                    raise ValueError('Unsupported multi-database Local rollback journal')
                temporary = TemporaryDirectory(prefix='actql-local-catalog-')
                with inspection.hold(temporary.cleanup):
                    copy = Path(temporary.name) / 'original.sqlite3'
                    _copy_exact(database_fd, acquired[1], copy, inspection)
                    _copy_exact(journal_fd, hot, copy.with_name(copy.name + '-journal'), inspection)
                    same_original()
                    _check_snapshot_catalog(copy, inspection, writable=True, retained=retained, ordinary=ordinary)
                same_original()
    same_original()
    return same_original
