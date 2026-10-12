"""Installed component integrity; no admission, policy or execution permission."""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
from importlib import metadata, resources
import json
import os
from pathlib import Path
import platform
import re
import stat
import sys
from typing import Any, cast

from ._local_core import LOCAL_CORE_ABI

WASMTIME_VERSION = '38.0.0'
_NOTICES = ('LICENSE', 'DUCKDB-LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE')


class LocalInstallationError(RuntimeError):
    """Refuse an unavailable or inconsistent installed Local release cohort."""


@dataclass(frozen=True, slots=True)
class LocalComponents:
    source_sha: str
    package_version: str
    module: Path
    module_sha256: str
    duckdb: Path
    duckdb_sha256: str
    duckdb_version: str


def _closed(value: Any, fields: tuple[str, ...]) -> dict[str, Any]:
    if type(value) is not dict or set(value) != set(fields):
        raise LocalInstallationError('Invalid installed Local component manifest')
    return cast(dict[str, Any], value)


def _hex(value: object, length: int) -> bool:
    return type(value) is str and re.fullmatch('[0-9a-f]{' + str(length) + '}', value) is not None


def _read_file(path: Path, *, maximum: int, expected: int | None = None,
               digest: str | None = None) -> bytes:
    # Installed wheels are ordinary files. Never extract a zip, follow a
    # component symlink, or search a development/Node installation.
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), 'rb') as source:
        before = os.fstat(source.fileno())
        if (not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= maximum
                or expected is not None and before.st_size != expected):
            raise LocalInstallationError('Invalid installed Local component size')
        checksum = hashlib.sha256()
        header = b''
        remaining = before.st_size
        while remaining:
            block = source.read(min(65536, remaining))
            if not block:
                raise LocalInstallationError('Incomplete installed Local component')
            checksum.update(block)
            remaining -= len(block)
            if digest is None:
                header += block
        after = os.fstat(source.fileno())
        if (source.read(1) or (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns,
                              before.st_ctime_ns) != (after.st_dev, after.st_ino, after.st_size,
                                                      after.st_mtime_ns, after.st_ctime_ns)
                or digest is not None and checksum.hexdigest() != digest):
            raise LocalInstallationError('Installed Local component changed or digest mismatched')
        return header


def _component(root: Path, value: Any, filename: str, maximum: int) -> tuple[Path, str]:
    item = _closed(value, ('file', 'bytes', 'sha256'))
    if (item['file'] != filename or type(item['bytes']) is not int
            or not 0 < item['bytes'] <= maximum or not _hex(item['sha256'], 64)):
        raise LocalInstallationError('Invalid installed Local component descriptor')
    path = root / filename
    _read_file(path, maximum=maximum, expected=item['bytes'], digest=item['sha256'])
    return path, item['sha256']


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise LocalInstallationError('Duplicate installed Local manifest field')
        value[key] = item
    return value


def inspect_local_components(root: Path, *, package_version: str) -> LocalComponents:
    """Inspect an installed supplier, before optional engines or foreign loading.

    These hashes are release integrity, not current Host publisher authority.
    The existing Wasm/DuckDB loaders still validate the exact bytes they load.
    The producer owns binary target and ABI evidence; this inspection is not
    execution or a claim that an artifact passed product acceptance.
    """
    if sys.platform != 'darwin' or platform.machine() != 'arm64':
        raise LocalInstallationError('Python Local is not available for this platform')
    try:
        raw = _read_file(root / 'artifact.json', maximum=65536)
        body = _closed(json.loads(raw, object_pairs_hook=_pairs), (
            'source_sha', 'package_version', 'platform', 'core_abi', 'wasmtime_version',
            'module', 'duckdb', 'duckdb_version', 'notices'))
        if (not _hex(body['source_sha'], 40) or type(package_version) is not str
                or not package_version or body['package_version'] != package_version
                or body['platform'] != 'darwin-arm64'
                or type(body['core_abi']) is not int or body['core_abi'] != LOCAL_CORE_ABI
                or body['wasmtime_version'] != WASMTIME_VERSION
                or type(body['duckdb_version']) is not str
                or re.fullmatch(r'v\d+\.\d+\.\d+', body['duckdb_version']) is None):
            raise LocalInstallationError('Installed Local release cohort is incompatible')
        module, module_hash = _component(root, body['module'], 'client_host_wasm.wasm', 32 * 1024 * 1024)
        library, library_hash = _component(root, body['duckdb'], 'libduckdb.dylib', 128 * 1024 * 1024)
        notices = _closed(body['notices'], _NOTICES)
        for filename in _NOTICES:
            if not _hex(notices[filename], 64):
                raise LocalInstallationError('Invalid installed Local license descriptor')
            _read_file(root / filename, maximum=1024 * 1024, digest=notices[filename])
        return LocalComponents(body['source_sha'], package_version, module, module_hash,
                               library, library_hash, body['duckdb_version'])
    except (OSError, ValueError, UnicodeError, RecursionError) as original:
        raise LocalInstallationError('Installed Local components are unavailable or invalid') from original


def installed_local_components() -> LocalComponents:
    """Only a selected Local connection calls this installed-package resolver."""
    if sys.platform != 'darwin' or platform.machine() != 'arm64':
        raise LocalInstallationError('Python Local is not available for this platform')
    try:
        version = metadata.version('actql-sdk')
        if metadata.version('actql-local-runtime') != version:
            raise LocalInstallationError('Installed Local release cohort is incompatible')
        if metadata.version('wasmtime') != WASMTIME_VERSION:
            raise LocalInstallationError('Installed Local Wasmtime dependency is incompatible')
        root = resources.files('actql_local_runtime')
        if not isinstance(root, Path):
            raise LocalInstallationError('Python Local requires an installed runtime wheel')
        return inspect_local_components(root, package_version=version)
    except (metadata.PackageNotFoundError, ModuleNotFoundError) as original:
        raise LocalInstallationError('Python Local requires the actql-sdk[local] installation') from original
