"""Retain the explicitly provisioned Host attestation file's physical generation."""

import os
import stat
from collections.abc import Callable
from hashlib import sha256
from struct import Struct
import sys
from typing import TypeVar

from ._local_files import LocalFileRoot, LocalOriginalAcquisitionError, _OriginalFileReader

_T = TypeVar('_T')
_LIMIT = 8192
_GENERATION = Struct('>12Q')
_KEY = 'effect-host.key'


def _private_key_projection(root: LocalFileRoot, info: os.stat_result) -> bytes:
    platform = 1 if sys.platform == 'darwin' else 2 if sys.platform == 'linux' else 0
    identity = root._identity
    if (platform == 0 or identity is None or not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.geteuid() or info.st_mode & 0o077 or info.st_nlink != 1
            or not 0 < info.st_size <= _LIMIT):
        raise ValueError('Original Host attestation file is unprotected')
    mtime, mtime_ns = divmod(info.st_mtime_ns, 1_000_000_000)
    ctime, ctime_ns = divmod(info.st_ctime_ns, 1_000_000_000)
    name = _KEY.encode('ascii')
    return b'AQLPFP01' + bytes((platform, len(name))) + _GENERATION.pack(
        identity.device, identity.inode, info.st_dev, info.st_ino, info.st_mode,
        info.st_uid, info.st_gid, info.st_size,
        mtime % (1 << 64), mtime_ns, ctime % (1 << 64), ctime_ns) + name


def _observe_host_attestation_generation(root: LocalFileRoot) -> bytes:
    """Use metadata only. First installation preserves this actual generation."""
    with root._lock:
        directory = root._validate_original_directory()
        info = os.stat(_KEY, dir_fd=directory, follow_symlinks=False)
        return _private_key_projection(root, info)


def _host_key_original_body(journal: bytes, role: bytes, generation: bytes) -> bytes:
    return sha256(journal).digest() + sha256(role).digest() + generation


def _bound_host_key_generation(body: bytes, journal: bytes, role: bytes) -> bytes:
    prefix = _host_key_original_body(journal, role, b'')
    if (not body.startswith(prefix) or len(body) != len(prefix) + 106 + len(_KEY)
            or not body[len(prefix):].startswith(b'AQLPFP01') or not body.endswith(_KEY.encode('ascii'))):
        raise ValueError('Original Local Host attestation is foreign')
    return body[len(prefix):]


class _OriginalEffectHostKey:
    """One key read, after confirmation of the finite original signing use."""

    def __init__(self, root: LocalFileRoot, expected: bytes,
                 require_claimed_use: Callable[[], None]) -> None:
        self._original = self
        self._root = root
        self._expected = expected
        self._require_claimed_use = require_claimed_use
        self._reader: _OriginalFileReader | None = None
        self._attempted = False
        self._closing = False

    def _current(self) -> None:
        if self._original is not self or self._closing:
            raise ValueError('Foreign or retired Original Host attestation key')
        self._require_claimed_use()
        if _observe_host_attestation_generation(self._root) != self._expected:
            raise ValueError('Original Host attestation file generation changed')
        if self._reader is not None:
            with self._root._lock:
                self._root._validate_original(self._reader)
                descriptor = self._reader.descriptor
                if (descriptor is None
                        or _private_key_projection(self._root, os.fstat(descriptor)) != self._expected):
                    raise ValueError('Original Host attestation descriptor generation changed')

    def with_private_key(self, consume: Callable[[bytes], _T]) -> _T:
        if self._attempted:
            raise ValueError('Original Host attestation key read was already attempted')
        self._attempted = True
        self._current()
        try:
            reader = self._root.open_original(_KEY, max_bytes=_LIMIT)
        except LocalOriginalAcquisitionError as failure:
            self._reader = failure.original_reader
            raise
        self._reader = reader
        self._current()
        body = bytearray()
        while True:
            chunk = self._root.read_original(reader)
            body.extend(chunk.data)
            self._root.release_original_chunk(reader, chunk)
            if chunk.eof:
                break
        self._root.observe_original(reader)
        self._current()
        value = consume(bytes(body))
        self._current()
        return value

    def close(self) -> bool:
        if self._original is not self:
            raise ValueError('Foreign original Host attestation cleanup')
        self._closing = True
        if self._reader is not None:
            if not self._root.close_original(self._reader):
                return False
            self._reader = None
        return True
