"""Persistent transport for the same Native Read/component/Library originals.

The selected installed caller supplies the already funded Host pair. This
module neither loads a provider nor issues a Read frame, grant or capacity.
"""
from __future__ import annotations

from ctypes import byref, c_int64, c_ubyte, c_uint16, c_void_p
from dataclasses import dataclass
from typing import Any, NoReturn

from ._local_native_host_resources import _OriginalHostResourcesCustody
from ._local_native_shim_abi import bind

_RETIRED_READ_CRYPTO_DATA = object()


@dataclass(frozen=True, slots=True)
class _OriginalReadCryptoFact:
    operation: int
    issue_origin: int
    issue_family: int


class _OriginalReadCryptoError(RuntimeError):
    def __init__(self, original: _OriginalReadCryptoSlots, *, unknown: bool,
                 fact: _OriginalReadCryptoFact | None = None) -> None:
        self.cleanup_crypto, self.unknown, self.fact = original, unknown, fact
        super().__init__('Original Read Crypto outcome is unconfirmed' if unknown
                         else 'Original Read Crypto operation was refused')


class _OriginalReadCryptoFunctions:
    def __init__(self, library: Any) -> None:
        self.library = library
        self.prepare = bind(library, 'actql_read_crypto_prepare_into')
        self.load = bind(library, 'actql_read_crypto_load_utf16_into')
        self.operate = bind(library, 'actql_read_crypto_operate_into')
        self.hmac = bind(library, 'actql_read_crypto_hmac_into')
        self.verify = bind(library, 'actql_read_crypto_verify_into')
        self.originals = bind(library, 'actql_read_crypto_originals_into')
        self.operation = bind(library, 'actql_read_crypto_operation')
        self.origin = bind(library, 'actql_read_crypto_issue_origin')
        self.family = bind(library, 'actql_read_crypto_issue_family')
        self.closed = bind(library, 'actql_read_crypto_close_confirmed')
        self.verification = bind(library, 'actql_read_crypto_verification')
        self.output = bind(library, 'actql_read_crypto_copy_output')
        self.drop = bind(library, 'actql_read_crypto_drop_reply')
        self.finish = bind(library, 'actql_read_crypto_finish_closed_data')
        self.refused = bind(library, 'actql_read_crypto_finish_refused_prepare')
        self.refused_library = bind(library, 'actql_read_crypto_finish_refused_library')


class _OriginalReadCryptoSlots:
    __slots__ = ('_resources', '_functions', '_host', '_pair', '_read', '_component',
                 '_library', '_reply', '_unknown', '_unknown_carrier', '_closed')

    def _initialize(self, resources: _OriginalHostResourcesCustody,
                    functions: _OriginalReadCryptoFunctions) -> None:
        self._resources, self._functions = resources, functions
        self._host, self._pair, self._read = c_void_p(), c_void_p(), c_void_p()
        self._component, self._library, self._reply = c_void_p(), c_void_p(), c_void_p()
        self._unknown: _OriginalReadCryptoError | None = None
        self._unknown_carrier = _OriginalReadCryptoError(self, unknown=True)
        self._closed = False

    def _slots(self) -> tuple[c_void_p, ...]:
        return self._host, self._pair, self._read, self._component, self._library, self._reply

    def __copy__(self) -> NoReturn:
        raise TypeError('Original Read Crypto custody cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original Read Crypto custody cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original Read Crypto custody cannot be serialized')

    def _mark_unknown(self) -> _OriginalReadCryptoError:
        if self._unknown is None:
            self._unknown = self._unknown_carrier
        return self._unknown

    def _status(self, code: Any) -> None:
        if type(code) is not int or code != 0:
            raise self._mark_unknown()

    def _check_original(self, *, entered: bool) -> None:
        if self._unknown is not None:
            raise self._unknown
        pair = self._resources
        for original in (pair, pair._read, pair._sqlite, pair._read._domain, pair._sqlite._domain):
            if original._unknown is not None:
                raise original._unknown
            if original._closed:
                raise ValueError('Original Read Crypto parent is retired')
        if (self._closed or pair._owner._host_resources_original is not pair
                or (pair._phase != 'read' if entered else pair._phase is not None)
                or pair._read._scope_open != entered):
            raise ValueError('Original Read Crypto frame is unavailable')

    def _extract(self, expected_component: c_void_p | None = None) -> None:
        self._status(self._functions.originals(self._reply,
            *(byref(value) for value in self._slots()[:-1])))
        pair = self._resources
        if (self._host.value != pair._host.value or self._pair.value != pair._original.value
                or self._read.value != pair._native_read.value
                or (expected_component is not None
                    and self._component.value != expected_component.value)):
            raise self._mark_unknown()

    def _fact(self, expected: int) -> _OriginalReadCryptoFact:
        if self._reply.value is None:
            raise self._mark_unknown()
        values = (self._functions.operation(self._reply), self._functions.origin(self._reply),
                  self._functions.family(self._reply), self._functions.closed(self._reply))
        op, origin, family, closed = values
        if (any(type(v) is not int for v in values) or op != expected
                or not 0 <= origin <= 5 or not 0 <= family <= 20
                or (origin == 0) != (family == 0)
                or closed != int(expected in (4, 5) and origin == 0)):
            raise self._mark_unknown()
        return _OriginalReadCryptoFact(op, origin, family)

    def _issue(self, fact: _OriginalReadCryptoFact) -> _OriginalReadCryptoError:
        if ((fact.issue_origin == 2 and fact.issue_family == 9)
                or (fact.issue_origin == 5 and fact.issue_family == 10)):
            self._unknown_carrier.fact = fact
            return self._mark_unknown()
        return _OriginalReadCryptoError(self, unknown=False, fact=fact)

    def _drop(self) -> None:
        self._status(self._functions.drop(byref(self._reply), *self._slots()[:-1]))
        if self._reply.value is not None:
            raise self._mark_unknown()

    def _finish(self) -> None:
        self._status(self._functions.finish(*(byref(slot) for slot in self._slots())))
        self._ack_data()

    def _ack_data(self) -> None:
        if any(slot.value is not None for slot in self._slots()):
            raise self._mark_unknown()
        self._closed = True


class _OriginalReadCryptoCustody(_OriginalReadCryptoSlots):
    """One outer-control registration consumed once in the same entered Read."""
    __slots__ = ('_attempted', '_loaded', '_libraries')
    _attempted: bool
    _loaded: bool
    _libraries: list[_OriginalReadCryptoLibrary]

    @classmethod
    def _prepare_original(cls, resources: _OriginalHostResourcesCustody,
                          functions: _OriginalReadCryptoFunctions) -> _OriginalReadCryptoCustody:
        if (cls is not _OriginalReadCryptoCustody
                or type(resources) is not _OriginalHostResourcesCustody
                or type(functions) is not _OriginalReadCryptoFunctions
                or functions.library is not resources._functions.library):
            raise ValueError('Original Read Crypto assembly is unavailable')
        value = cls.__new__(cls)
        value._initialize(resources, functions)
        value._attempted, value._loaded = False, False
        value._libraries = []
        output = byref(value._reply)
        known: _OriginalReadCryptoError | None = None
        resources._owner._enter()
        try:
            value._check_original(entered=False)
            if resources._read._crypto_original is not None:
                raise ValueError('Original Read Crypto registration was already selected')
            resources._read._crypto_original = value
            try:
                value._status(functions.prepare(resources._host, resources._original,
                    resources._native_read, output))
                value._extract()
                fact = value._fact(1)
                if fact.issue_origin:
                    known = value._issue(fact)
                    if known.unknown or value._component.value is not None:
                        raise value._mark_unknown()
                    value._status(functions.refused(byref(value._host), byref(value._pair),
                        byref(value._read), byref(value._reply)))
                    value._ack_data()
                    resources._read._crypto_original = _RETIRED_READ_CRYPTO_DATA
                    raise known
                if value._component.value is None or value._library.value is not None:
                    raise value._mark_unknown()
                value._drop()
            except BaseException as error:
                if error is known or error is value._unknown:
                    raise
                raise value._mark_unknown() from error
        finally:
            resources._owner._busy = False
        return value

    def load(self, *, path: str, heap_bytes: int, diagnostic_ceiling: int) -> None:
        if (type(path) is not str or not path.startswith('/') or '\0' in path
                or not 0 < len(path) <= 4096 or type(heap_bytes) is not int
                or not -(1 << 63) <= heap_bytes < (1 << 63)
                or type(diagnostic_ceiling) is not int
                or not -(1 << 31) <= diagnostic_ceiling < (1 << 31)):
            raise ValueError('Original Read Crypto load inputs are unavailable')
        raw = path.encode('utf-16-le')
        units = len(raw) // 2
        if units > 4096:
            raise ValueError('Original Read Crypto path exceeds its ABI bound')
        text = (c_uint16 * units).from_buffer_copy(raw)
        output = byref(self._reply)
        known: _OriginalReadCryptoError | None = None
        self._resources._owner._enter()
        try:
            self._check_original(entered=True)
            if (self._resources._read._crypto_original is not self or self._attempted):
                raise ValueError('Original Read Crypto load was already attempted')
            self._attempted = True
            try:
                self._drop()
                self._status(self._functions.load(self._host, self._pair, self._read,
                    self._component, text, units, heap_bytes, diagnostic_ceiling, output))
                fact = self._fact(2)
                if fact.issue_origin:
                    known = self._issue(fact)
                    if known.unknown:
                        raise known
                else:
                    self._loaded = True
                self._drop()
                if known is not None:
                    raise known
            except BaseException as error:
                if error is known or error is self._unknown:
                    raise
                raise self._mark_unknown() from error
        finally:
            self._resources._owner._busy = False

    def open_library(self) -> _OriginalReadCryptoLibrary:
        return _OriginalReadCryptoLibrary._open_original(self)

    def close(self) -> None:
        if self._unknown is not None:
            raise self._unknown
        if self._closed:
            self._resources._owner._enter()
            self._resources._owner._busy = False
            return
        for child in self._libraries:
            if child._unknown is not None:
                raise child._unknown
            if not child._closed:
                raise ValueError('Original Crypto Library cleanup remains pending')
        output = byref(self._reply)
        known: _OriginalReadCryptoError | None = None
        self._resources._owner._enter()
        try:
            self._check_original(entered=True)
            if self._resources._read._crypto_original is not self:
                raise ValueError('Foreign original Read Crypto registration')
            try:
                self._drop()
                self._status(self._functions.operate(self._host, self._pair, self._read,
                    self._component, self._library, 5, output))
                fact = self._fact(5)
                if fact.issue_origin:
                    known = self._issue(fact)
                    if known.unknown:
                        raise known
                    self._drop()
                    raise known
                self._finish()
                self._resources._read._crypto_original = _RETIRED_READ_CRYPTO_DATA
                self._libraries.clear()
            except BaseException as error:
                if error is known or error is self._unknown:
                    raise
                raise self._mark_unknown() from error
        finally:
            self._resources._owner._busy = False


class _OriginalReadCryptoLibrary(_OriginalReadCryptoSlots):
    """One Library or partial Library; its data aliases retire in original Read."""
    __slots__ = ('_parent', '_adoption_original')
    _adoption_original: Any
    _parent: _OriginalReadCryptoCustody

    @classmethod
    def _open_original(cls, parent: _OriginalReadCryptoCustody) -> _OriginalReadCryptoLibrary:
        if cls is not _OriginalReadCryptoLibrary or type(parent) is not _OriginalReadCryptoCustody:
            raise ValueError('Original Read Crypto Library parent is unavailable')
        value = cls.__new__(cls)
        value._initialize(parent._resources, parent._functions)
        value._parent = parent
        value._adoption_original = None
        output = byref(value._reply)
        known: _OriginalReadCryptoError | None = None
        parent._resources._owner._enter()
        try:
            parent._check_original(entered=True)
            if not parent._loaded or parent._resources._read._crypto_original is not parent:
                raise ValueError('Original Read Crypto component is not loaded')
            parent._libraries.append(value)
            try:
                value._status(value._functions.operate(parent._host, parent._pair, parent._read,
                    parent._component, c_void_p(), 3, output))
                value._extract(parent._component)
                fact = value._fact(3)
                if fact.issue_origin:
                    known = value._issue(fact)
                    if known.unknown:
                        raise known
                    if value._library.value is None:
                        value._status(value._functions.refused_library(
                            *(byref(slot) for slot in value._slots())))
                        value._ack_data()
                    else:
                        value._drop()
                    raise known
                if value._library.value is None:
                    raise value._mark_unknown()
                value._drop()
            except BaseException as error:
                if error is known or error is value._unknown:
                    raise
                raise value._mark_unknown() from error
        finally:
            parent._resources._owner._busy = False
        return value

    def _call(self, operation: int, inputs: tuple[bytes, ...] = ()) -> bytes | bool | None:
        if self._unknown is not None:
            raise self._unknown
        if self._parent._unknown is not None:
            raise self._parent._unknown
        buffers = tuple((c_ubyte * len(value)).from_buffer_copy(value) for value in inputs)
        output, length = (c_ubyte * 32)(), c_int64(-1)
        out = byref(self._reply)
        known: _OriginalReadCryptoError | None = None
        self._resources._owner._enter()
        try:
            self._check_original(entered=True)
            if (self not in self._parent._libraries or self._parent._closed
                    or self._library.value is None
                    or self._resources._read._crypto_original is not self._parent):
                raise ValueError('Original Read Crypto Library is retired')
            if operation == 4 and self._adoption_original is not None:
                from ._local_native_adoption import _RETIRED_ADOPTION_DATA
                if self._adoption_original is not _RETIRED_ADOPTION_DATA:
                    pending = self._adoption_original
                    if pending._unknown is not None:
                        raise pending._unknown
                    raise ValueError('Original adoption still borrows this Library')
            try:
                self._drop()
                originals = self._slots()[:-1]
                if operation == 4:
                    self._status(self._functions.operate(*originals, operation, out))
                else:
                    arguments = tuple(item for pair in zip(buffers, map(len, inputs)) for item in pair)
                    call = self._functions.hmac if operation == 6 else self._functions.verify
                    self._status(call(*originals, *arguments, out))
                fact = self._fact(operation)
                if fact.issue_origin:
                    known = self._issue(fact)
                    if known.unknown:
                        raise known
                    self._drop()
                    raise known
                result: bytes | bool | None = None
                if operation == 4:
                    self._finish()
                elif operation == 6:
                    self._status(self._functions.output(self._reply, *originals, output, 32, byref(length)))
                    if length.value != 32:
                        raise self._mark_unknown()
                    result = bytes(output)
                    self._drop()
                else:
                    verified = self._functions.verification(self._reply)
                    if type(verified) is not int or verified not in (0, 1):
                        raise self._mark_unknown()
                    result = bool(verified)
                    self._drop()
                return result
            except BaseException as error:
                if error is known or error is self._unknown:
                    raise
                raise self._mark_unknown() from error
        finally:
            self._resources._owner._busy = False

    @staticmethod
    def _bytes(*values: bytes) -> None:
        if any(type(v) is not bytes or len(v) > (1 << 31) - 1 for v in values):
            raise ValueError('Original Read Crypto byte inputs exceed the ABI bound')

    def hmac_sha256(self, key: bytes, data: bytes) -> bytes:
        self._bytes(key, data)
        result = self._call(6, (key, data))
        if type(result) is not bytes:
            raise self._mark_unknown()
        return result

    def verify_hmac_sha256(self, key: bytes, data: bytes, signature: bytes) -> bool:
        self._bytes(key, data, signature)
        result = self._call(7, (key, data, signature))
        if type(result) is not bool:
            raise self._mark_unknown()
        return result

    def close(self) -> None:
        if self._unknown is not None:
            raise self._unknown
        if self._closed:
            self._resources._owner._enter()
            self._resources._owner._busy = False
            return
        self._call(4)


def _require_read_crypto_retired(read: Any) -> None:
    original = getattr(read, '_crypto_original', None)
    if original is not None and original is not _RETIRED_READ_CRYPTO_DATA:
        if original._unknown is not None:
            raise original._unknown
        for child in original._libraries:
            if child._unknown is not None:
                raise child._unknown
        raise ValueError('Original Read Crypto cleanup or data remains pending')
