"""Private physical assembly; capacity is not Source or Run authorization."""
from __future__ import annotations

from threading import RLock

from ._local_core import LocalCore, _Workspace
from ._local_duckdb import DuckDBConnection, DuckDBLibrary


class DuckDBWorkspace:
    """Keep one connection and its exact existing Core workspace loan.

    The trusted Host must obtain existing Source/Run authorization before using
    this physical assembly. workspace_bytes reserves the configured envelope;
    DuckDB's buffer-manager memory limit alone is not a total native-memory bound.
    """

    def __init__(self, core: LocalCore, library: DuckDBLibrary, path: str, *,
                 workspace_bytes: int, memory_bytes: int, readonly: bool = True) -> None:
        if (type(workspace_bytes) is not int or not 0 < workspace_bytes <= 2**63 - 1
                or type(memory_bytes) is not int or not 0 < memory_bytes <= workspace_bytes):
            raise ValueError('Invalid DuckDB workspace envelope')
        self._identity = self
        self._core = core
        self._lock = RLock()
        self._connection: DuckDBConnection | None = None
        self._initializing = True
        self._cleanup_unknown: object | None = None
        self._closing = False
        self._retiring = False
        self._closed = False
        # Capacity refusal cannot enter DuckDB configuration/open/connect.
        self._loan: _Workspace = core.reserve_workspace(workspace_bytes,
            stopped=self._stopped, cleanup=self._cleanup)
        try:
            self._connection = self._open_connection(library, path,
                memory_bytes=memory_bytes, readonly=readonly)
        except BaseException as error:
            pending = getattr(error, 'physical_cleanup', None)
            if pending is not None:
                # The existing connection constructor retains its exact failed
                # native handle; do not construct a replacement connection.
                if isinstance(pending, DuckDBConnection):
                    self._connection = pending
                else:
                    self._cleanup_unknown = pending
            self._initializing = False
            try:
                self.close()
            except BaseException:
                pass
            if not self._closed:
                setattr(error, 'physical_cleanup', self)
            raise
        finally:
            self._initializing = False

    @staticmethod
    def _open_connection(library: DuckDBLibrary, path: str, *,
                         memory_bytes: int, readonly: bool) -> DuckDBConnection:
        return DuckDBConnection(library, path, memory_bytes=memory_bytes, readonly=readonly)

    def _owned(self) -> None:
        if self._identity is not self:
            raise ValueError('Foreign DuckDB workspace handle')

    def connection(self) -> DuckDBConnection:
        self._owned()
        with self._lock:
            if self._closing or self._initializing or self._connection is None:
                raise RuntimeError('DuckDB workspace is unavailable')
            return self._connection

    def _stopped(self) -> bool:
        with self._lock:
            if self._initializing or self._cleanup_unknown is not None:
                return False
            return self._connection is None or self._connection.stop_new_io()

    def _cleanup(self) -> bool:
        with self._lock:
            if self._initializing or self._cleanup_unknown is not None:
                return False
            return self._connection is None or self._connection.close()

    def close(self) -> bool:
        """Retire the original physical loan, never cancel/replay a Run."""
        self._owned()
        with self._lock:
            if self._closed:
                return True
            self._closing = True
            if self._initializing or self._retiring:
                return False
            self._retiring = True
        # Core invokes callbacks while holding its instance lock. Never wait
        # for that lock while holding the callback's metadata lock.
        try:
            completed = self._core.close_workspace(self._loan)
            if completed:
                with self._lock:
                    self._closed = True
            return completed
        finally:
            with self._lock:
                self._retiring = False
