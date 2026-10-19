"""Custody of one existing Native adoption and its retained Journal child.

The trusted Native assembly prepares the original binding into a persistent
slot. This transport does not load Crypto, adopt a path, issue funding or
replace a missing installed supplier. Native retains every partial open.
"""
from __future__ import annotations

from collections.abc import Callable
from ctypes import byref, c_int32, c_uint16, c_void_p
from math import isfinite
from typing import TYPE_CHECKING, Any, NoReturn

from ._local_native_control_custody import _OriginalArenaFact
from ._local_native_host_resources import _OriginalHostResourcesCustody
from ._local_native_shim_abi import bind

if TYPE_CHECKING:
    from ._local_native_read_crypto import _OriginalReadCryptoLibrary

_RETIRED_ADOPTION_DATA = object()


class _OriginalAdoptionError(RuntimeError):
    def __init__(self, original: _OriginalAdoptionCustody, *, unknown: bool,
                 fact: _OriginalArenaFact | None = None) -> None:
        self.cleanup_adoption, self.unknown, self.fact = original, unknown, fact
        super().__init__('Original adoption outcome is unconfirmed' if unknown
                         else 'Original adoption operation was refused')


class _OriginalAdoptionFunctions:
    def __init__(self, library: Any) -> None:
        self.library = library
        self.operate = bind(library, 'actql_local_adoption_operate_into')
        self.journal = bind(library, 'actql_local_adoption_capture_journal_into')
        self.originals = bind(library, 'actql_local_adoption_originals_into')
        self.drop_originals = bind(library, 'actql_local_adoption_drop_originals')
        self.operation = bind(library, 'actql_local_adoption_operation')
        self.issue = bind(library, 'actql_local_adoption_issue_family')
        self.drop = bind(library, 'actql_local_adoption_drop_reply')
        self.finish = bind(library, 'actql_local_adoption_finish_closed_data')


class _OriginalAdoptionCustody:
    """Persistent out-slots, never Python Session or cleanup authority.

    ``prepare`` is a private trusted-assembly port, not an application callback
    or a funding supplier. It must retain the actual Crypto/provider custody
    and write the same Native binding before its first physical operation.
    The wrapper registers on the original Read before invoking it once.
    """
    __slots__ = ('_resources', '_functions', '_preparation', '_original', '_reply',
                 '_host', '_pair', '_read', '_crypto', '_session', '_journal',
                 '_unknown', '_unknown_carrier', '_closed', '_journal_attempted',
                 '_observed_originals', '_crypto_library')
    _resources: _OriginalHostResourcesCustody
    _crypto_library: _OriginalReadCryptoLibrary | None
    _functions: _OriginalAdoptionFunctions
    _preparation: Callable[[Any], int] | None
    _original: c_void_p
    _reply: c_void_p
    _host: c_void_p
    _pair: c_void_p
    _read: c_void_p
    _crypto: c_void_p
    _session: c_void_p
    _journal: c_void_p
    _unknown: _OriginalAdoptionError | None
    _unknown_carrier: _OriginalAdoptionError
    _closed: bool
    _journal_attempted: bool
    _observed_originals: tuple[int | None, int | None, int | None]

    @classmethod
    def _open_from_original_library(
        cls, resources: _OriginalHostResourcesCustody,
        functions: _OriginalAdoptionFunctions, crypto: _OriginalReadCryptoLibrary, *,
        parent_path: str, state_name: str, source_path: str, source_name: str,
        account_id: str, configuration_files: tuple[str, ...],
        managed_root_path: str | None, diagnostic_ceiling: int,
    ) -> _OriginalAdoptionCustody:
        """Transport the existing Native adoption input and actual Library.

        This selects neither a Host nor a key, and does not initialize an
        absent installation. The existing Native binding owns every open and
        partial result. Its borrowed Library stays registered through DATA ACK.
        """
        from ._local_native_read_crypto import _OriginalReadCryptoLibrary
        from ._local_native_runtime import _exact_utf16
        if (cls is not _OriginalAdoptionCustody
                or type(resources) is not _OriginalHostResourcesCustody
                or type(functions) is not _OriginalAdoptionFunctions
                or functions.library is not resources._functions.library
                or type(crypto) is not _OriginalReadCryptoLibrary
                or crypto._resources is not resources
                or type(configuration_files) is not tuple or len(configuration_files) > 8
                or type(diagnostic_ceiling) is not int
                or not 0 < diagnostic_ceiling < 2**31
                or managed_root_path is not None and type(managed_root_path) is not str):
            raise ValueError('Original adoption Library or input is unavailable')
        # Exact UTF-16 transport uses the existing closed Native input bounds.
        # No path resolution, key creation, normalization or source substitution.
        paths = tuple(_exact_utf16(value, 4096) for value in
            (parent_path, state_name, source_path, source_name, account_id))
        files = tuple(_exact_utf16(value, 4096) for value in configuration_files)
        lengths = (c_int32 * len(files))(*(len(value) for value in files))
        joined = (c_uint16 * sum(map(len, files)))(*(unit for value in files for unit in value))
        managed = ((c_uint16 * 0)() if managed_root_path is None
                   else _exact_utf16(managed_root_path, 4096))
        prepare_utf16 = bind(functions.library, 'actql_local_adoption_prepare_utf16_into')

        def prepare(out: Any) -> int:
            args = tuple(item for value in paths for item in (value, len(value)))
            return int(prepare_utf16(resources._host, resources._original,
                resources._read._original, crypto._library, *args,
                joined, len(joined), lengths, len(files), managed, len(managed),
                int(managed_root_path is not None), diagnostic_ceiling, out))

        return cls._open_original(resources, functions, prepare=prepare,
                                  _crypto_library=crypto)

    @classmethod
    def _open_original(cls, resources: _OriginalHostResourcesCustody,
                       functions: _OriginalAdoptionFunctions, *,
                       prepare: Callable[[Any], int],
                       _crypto_library: _OriginalReadCryptoLibrary | None = None
                       ) -> _OriginalAdoptionCustody:
        if (cls is not _OriginalAdoptionCustody
                or type(resources) is not _OriginalHostResourcesCustody
                or type(functions) is not _OriginalAdoptionFunctions
                or functions.library is not resources._functions.library
                or not callable(prepare)):
            raise ValueError('Original adoption assembly is unavailable')
        original = cls.__new__(cls)
        original._resources, original._functions = resources, functions
        original._crypto_library = _crypto_library
        original._preparation = prepare
        original._original, original._reply = c_void_p(), c_void_p()
        original._host, original._pair, original._read = c_void_p(), c_void_p(), c_void_p()
        original._crypto, original._session, original._journal = c_void_p(), c_void_p(), c_void_p()
        original._unknown, original._closed, original._journal_attempted = None, False, False
        original._observed_originals = None, None, None
        original._unknown_carrier = _OriginalAdoptionError(original, unknown=True)
        out = byref(original._original)
        outputs = tuple(byref(slot) for slot in original._original_slots())
        owner = resources._owner
        # Local busy/thread/process refusal creates no foreign responsibility.
        owner._enter()
        try:
            original._parents_current()
            if getattr(resources._read, '_adoption_original', None) is not None:
                raise ValueError('Original adoption has already been selected')
            if _crypto_library is not None:
                original._require_crypto_library(unbound=True)
            resources._read._adoption_original = original
            if _crypto_library is not None:
                _crypto_library._adoption_original = original
            try:
                original._status(prepare(out))
                if original._original.value is None:
                    raise original._mark_unknown()
                original._status(functions.originals(original._original, *outputs))
                original._check_originals()
                if original._session.value is not None or original._journal.value is not None:
                    raise original._mark_unknown()
                original._run(1)
            except BaseException as error:
                if isinstance(error, _OriginalAdoptionError) and error.cleanup_adoption is original:
                    raise
                raise original._mark_unknown() from error
        finally:
            owner._busy = False
        return original

    def __copy__(self) -> NoReturn:
        raise TypeError('Original adoption custody cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original adoption custody cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original adoption custody cannot be serialized')

    def _original_slots(self) -> tuple[c_void_p, ...]:
        return self._host, self._pair, self._read, self._crypto, self._session, self._journal

    def _mark_unknown(self) -> _OriginalAdoptionError:
        if self._unknown is None:
            self._unknown = self._unknown_carrier
        return self._unknown

    def _status(self, code: Any) -> None:
        if type(code) is not int or code != 0:
            raise self._mark_unknown()

    def _check_originals(self) -> None:
        p = self._resources
        if (self._host.value != p._host.value or self._pair.value != p._original.value
                or self._read.value != p._read._original.value or self._crypto.value is None
                or self._crypto_library is not None
                   and self._crypto.value != self._crypto_library._library.value):
            raise self._mark_unknown()
        observed = self._crypto.value, self._session.value, self._journal.value
        if any(old is not None and old != current
               for old, current in zip(self._observed_originals, observed)):
            raise self._mark_unknown()
        # Correlate immutable aliases only. These addresses grant no use and
        # remain separate from the owned managed references in the out-slots.
        self._observed_originals = observed

    def _require_crypto_library(self, *, unbound: bool = False) -> None:
        from ._local_native_read_crypto import _OriginalReadCryptoLibrary
        library = self._crypto_library
        if library is None:
            return
        if type(library) is not _OriginalReadCryptoLibrary:
            raise ValueError('Original adoption Library is unavailable')
        library._check_original(entered=False)
        parent = library._parent
        if parent._unknown is not None:
            raise parent._unknown
        if (parent._closed or not parent._loaded
                or library not in parent._libraries or library._library.value is None
                or library._resources is not self._resources
                or self._resources._read._crypto_original is not parent
                or (library._adoption_original is not None if unbound
                    else library._adoption_original is not self)):
            raise ValueError('Original adoption Library is unavailable')

    def _parents_current(self) -> None:
        p = self._resources
        for parent in (p, p._read, p._sqlite, p._read._domain, p._sqlite._domain):
            if parent._unknown is not None:
                raise parent._unknown
            if parent._closed:
                raise ValueError('Original adoption parent is retired')
        if (p._owner._host_resources_original is not p or p._phase is not None
                or p._read._scope_open or p._owner._original.value != p._host.value
                or p._read._domain._parent_read_original is not p._read
                or p._sqlite._domain._sqlite_library_original is not p._sqlite):
            raise ValueError('Original adoption parents are unavailable')

    def _available(self) -> None:
        if self._unknown is not None:
            raise self._unknown
        self._parents_current()
        self._require_crypto_library()
        if (self._closed or self._original.value is None
                or self._resources._read._adoption_original is not self):
            raise ValueError('Original adoption is retired or unavailable')

    def _drop_reply(self) -> None:
        if self._reply.value is not None:
            self._status(self._functions.drop(byref(self._reply), self._original))
            if self._reply.value is not None:
                raise self._mark_unknown()

    def _drop_originals(self) -> None:
        outputs = tuple(byref(slot) for slot in self._original_slots())
        self._status(self._functions.drop_originals(self._original, *outputs))
        if any(slot.value is not None for slot in self._original_slots()):
            raise self._mark_unknown()

    def _run(self, operation: int, journal: tuple[float, int, int] | None = None
             ) -> _OriginalArenaFact:
        # Called only under the original Host's entry. Do not reacquire it or
        # wrap the Native Journal's own Read/SQLite scopes in another Read.
        known: _OriginalAdoptionError | None = None
        try:
            self._drop_reply()
            self._drop_originals()
            out = byref(self._reply)
            if journal is None:
                self._status(self._functions.operate(self._original, operation, out))
            else:
                self._journal_attempted = True
                self._status(self._functions.journal(self._original, *journal, out))
            if self._reply.value is None:
                raise self._mark_unknown()
            op, family = self._functions.operation(self._reply), self._functions.issue(self._reply)
            if (type(op) is not int or op != operation
                    or type(family) is not int or not 0 <= family <= 7):
                raise self._mark_unknown()
            fact = _OriginalArenaFact(op, family)
            self._status(self._functions.originals(self._original,
                *(byref(slot) for slot in self._original_slots())))
            self._check_originals()
            if family:
                if family in (3, 7):
                    self._unknown_carrier.fact = fact
                    raise self._mark_unknown()
                known = _OriginalAdoptionError(self, unknown=False, fact=fact)
                self._drop_reply()
                raise known
            if operation == 3:
                self._drop_originals()
                self._status(self._functions.finish(byref(self._original), byref(self._reply)))
                if (self._original.value is not None or self._reply.value is not None
                        or self._resources._read._adoption_original is not self):
                    raise self._mark_unknown()
                self._closed = True
                self._resources._read._adoption_original = _RETIRED_ADOPTION_DATA
                self._preparation = None
                if self._crypto_library is not None:
                    self._crypto_library._adoption_original = _RETIRED_ADOPTION_DATA
            else:
                self._drop_reply()
            return fact
        except BaseException as error:
            if error is known or error is self._unknown:
                raise
            raise self._mark_unknown() from error

    def _call(self, operation: int) -> _OriginalArenaFact:
        if operation not in (2, 3):
            raise ValueError('Original adoption observation is unavailable')
        self._available()
        self._resources._owner._enter()
        try:
            self._available()
            return self._run(operation)
        finally:
            self._resources._owner._busy = False

    def current(self) -> _OriginalArenaFact:
        return self._call(2)

    def open_journal(self, *, ttl_ms: float, max_records: int,
                     max_snapshot_bytes: int) -> _OriginalArenaFact:
        if (type(ttl_ms) is not float or not isfinite(ttl_ms) or ttl_ms <= 0
                or type(max_records) is not int or not 0 < max_records < 2**31
                or type(max_snapshot_bytes) is not int or not 0 < max_snapshot_bytes < 2**63):
            raise ValueError('Original Journal options are unavailable')
        self._available()
        self._resources._owner._enter()
        try:
            self._available()
            if self._journal_attempted:
                raise ValueError('Original Journal has already been selected')
            self._run(4, (ttl_ms, max_records, max_snapshot_bytes))
            if self._journal.value is None:
                raise self._mark_unknown()
            return self._run(5)
        finally:
            self._resources._owner._busy = False

    def close(self) -> None:
        if self._unknown is not None:
            raise self._unknown
        if not self._closed:
            self._call(3)
        else:
            # Repeated acknowledged cleanup checks the same process/thread,
            # without another physical close or parent retirement.
            self._resources._owner._enter()
            self._resources._owner._busy = False


def _require_adoption_retired(read: Any) -> None:
    child = getattr(read, '_adoption_original', None)
    if child is not None and child is not _RETIRED_ADOPTION_DATA:
        error = getattr(child, '_unknown', None)
        if error is not None:
            raise error
        raise ValueError('Original adoption cleanup or data remains pending')
