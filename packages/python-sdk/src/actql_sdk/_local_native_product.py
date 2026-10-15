"""Bounded metadata transport on the same existing Native Runtime custody.

The Native Owner issues and validates the metadata. This driver neither adopts
an installed product nor turns copied identity into authority or capacity.
"""
from __future__ import annotations

from ctypes import POINTER, byref, c_int, c_int32, c_uint16, c_void_p
from typing import Any

from ._local_native_control_custody import _OriginalArenaFact
from ._local_native_runtime import (
    _OriginalPackagedRuntimeCustody, _OriginalPackagedRuntimeError, _exact_utf16,
)


class _OriginalPackagedProductFunctions:
    def __init__(self, library: Any) -> None:
        self.library = library
        self.observe = library.actql_packaged_product_observe_utf16_into
        self.observe.argtypes = ([c_void_p] + [POINTER(c_uint16), c_int32] * 3
                                + [c_int32, POINTER(c_void_p)])
        self.identity = library.actql_packaged_product_identity_into
        self.identity.argtypes = [c_void_p, POINTER(c_void_p)]
        self.drop = library.actql_packaged_product_drop_reply
        self.drop.argtypes = [POINTER(c_void_p), c_void_p, c_void_p, c_void_p]
        self.validate = library.actql_packaged_product_validate_originals
        self.validate.argtypes = [c_void_p, c_void_p, c_void_p, c_void_p]
        for call in (self.observe, self.identity, self.drop, self.validate):
            call.restype = c_int
        self.operation = library.actql_packaged_product_operation
        self.issue = library.actql_packaged_product_issue_family
        self.length = library.actql_packaged_product_metadata_units
        for call in (self.operation, self.issue, self.length):
            call.argtypes = [c_void_p]
            call.restype = c_int32
        self.unit = library.actql_packaged_product_metadata_unit_at
        self.unit.argtypes = [c_void_p, c_int32]
        self.unit.restype = c_int32

    def _call(self, original: _OriginalPackagedRuntimeCustody, operation: int,
              buffers: tuple[Any, ...] = (), ceiling: int = 0) -> tuple[_OriginalArenaFact, str | None]:
        if (type(self) is not _OriginalPackagedProductFunctions
                or type(original) is not _OriginalPackagedRuntimeCustody
                or self.library is not original._functions.library
                or type(operation) is not int or operation not in (4, 5)):
            raise ValueError('Original product Runtime selection is unavailable')
        original._available()
        # Persistent out-slot belongs to the existing Runtime before FFI. An
        # exception keeps it, the original loan and the same Unknown carrier.
        out = byref(original._product_reply)
        owner = original._read._domain._owner
        known: _OriginalPackagedRuntimeError | None = None
        owner._enter()
        try:
            original._available()
            try:
                if operation == 4:
                    a, b, c = buffers
                    code = self.observe(original._runtime, a, len(a), b, len(b),
                                        c, len(c), ceiling, out)
                else:
                    code = self.identity(original._runtime, out)
                original._status(code)
                reply = original._product_reply
                if reply.value is None:
                    raise original._mark_unknown()
                # Same nominal originals must be checked by the C/Native
                # projection before reading even local metadata or issue tags.
                original._status(self.validate(reply, original._host,
                    original._original_read, original._runtime))
                op, issue = self.operation(reply), self.issue(reply)
                if (type(op) is not int or op != operation
                        or type(issue) is not int or not 0 <= issue <= 9):
                    raise original._mark_unknown()
                fact = _OriginalArenaFact(op, issue)
                wire: str | None = None
                if operation == 5 and issue == 0:
                    length = self.length(reply)
                    if type(length) is not int or not 0 < length <= 4096:
                        raise original._mark_unknown()
                    raw = bytearray(length * 2)
                    for index in range(length):
                        unit = self.unit(reply, index)
                        if type(unit) is not int or not 0 <= unit <= 65535:
                            raise original._mark_unknown()
                        raw[2 * index] = unit & 255
                        raw[2 * index + 1] = unit >> 8
                    wire = raw.decode('utf-16-le', errors='strict')
                original._status(self.drop(out, original._host,
                    original._original_read, original._runtime))
                if original._product_reply.value is not None:
                    raise original._mark_unknown()
                if fact.issue_family:
                    known = original._owner_issue(fact)
                    raise known
            except BaseException as error:
                if error is known or error is original._unknown:
                    raise
                raise original._mark_unknown() from error
        finally:
            owner._busy = False
        return fact, wire

    def observe_members(self, original: _OriginalPackagedRuntimeCustody, *,
                        launcher_root: str, launcher_descriptor_sha256: str,
                        platform_descriptor_sha256: str,
                        diagnostic_ceiling: int) -> _OriginalArenaFact:
        if type(diagnostic_ceiling) is not int or not 0 < diagnostic_ceiling < 2**31:
            raise ValueError('Original product diagnostic bound is unavailable')
        buffers = (_exact_utf16(launcher_root, 4096),
                   _exact_utf16(launcher_descriptor_sha256, 64, exact=64),
                   _exact_utf16(platform_descriptor_sha256, 64, exact=64))
        return self._call(original, 4, buffers, diagnostic_ceiling)[0]

    def identity_wire(self, original: _OriginalPackagedRuntimeCustody) -> str:
        _, wire = self._call(original, 5)
        if wire is None:
            raise original._mark_unknown()
        return wire
