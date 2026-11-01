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
from typing import TYPE_CHECKING, Any, cast

if TYPE_CHECKING:
    from ._local_image_recipe import _SelectedImageRecipe
    from ._local_worker_slot import _OriginalDescriptor

from ._local_wasm_abi import LOCAL_CORE_ABI

WASMTIME_VERSION = '38.0.0'
# Selected standalone profile, shared with the pinned vendor/artifact producer.
# This is not the older private Node/DuckDB physical diagnostic profile.
DUCKDB_VERSION = 'v1.4.3'
_LOCAL_COMPONENT_PLATFORM = 'darwin-arm64'
_NOTICES = ('LICENSE', 'DUCKDB-LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE')


class LocalInstallationError(RuntimeError):
    """Refuse an unavailable or inconsistent installed Local release cohort."""


class LocalComponentReadCleanupPending(LocalInstallationError):
    """Keep the original input FD after an unconfirmed one-shot close."""

    def __init__(self, descriptor: _OriginalDescriptor) -> None:
        self.cleanup_descriptor = descriptor
        self.original_error: BaseException | None = None
        self.cleanup_error: BaseException | None = None
        super().__init__('Installed Local component reader cleanup is unconfirmed')


@dataclass(frozen=True, slots=True)
class LocalComponents:
    source_sha: str
    package_version: str
    module: Path
    module_sha256: str
    duckdb: Path
    duckdb_sha256: str
    duckdb_version: str
    image: Path
    image_sha256: str
    image_bytes: int
    image_recipe: _SelectedImageRecipe
    engine_recipe: Path
    engine_recipe_sha256: str


def _closed(value: Any, fields: tuple[str, ...]) -> dict[str, Any]:
    if type(value) is not dict or set(value) != set(fields):
        raise LocalInstallationError('Invalid installed Local component manifest')
    return cast(dict[str, Any], value)


def _hex(value: object, length: int) -> bool:
    return type(value) is str and re.fullmatch('[0-9a-f]{' + str(length) + '}', value) is not None


class _OriginalComponentFile:
    """One initialization's exact hashed file and existing descriptor carrier.

    This is neither a path cache nor a loaded-code/ABI/funding observation.
    Only read-only linkage checks reuse it; the native-load boundary still
    obtains its own complete byte observation. No descriptor is reopened.
    """
    def __init__(self, path: Path, *, expected: int, digest: str) -> None:
        self._original = self
        self.path, self.expected, self.digest = path, expected, digest
        self._source: _OriginalDescriptor | None = None
        self._stamp: tuple[int, ...] | None = None
        self._closing = False

    @staticmethod
    def _snapshot(value: os.stat_result) -> tuple[int, ...]:
        return (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns,
                value.st_ctime_ns, value.st_mode, value.st_uid)

    def _retain(self, source: _OriginalDescriptor, before: os.stat_result,
                digest: str) -> None:
        if (self._original is not self or self._closing or self._source is not None
                or before.st_size != self.expected or digest != self.digest):
            raise LocalInstallationError('Foreign or changed original component read')
        self._source, self._stamp = source, self._snapshot(before)

    def read(self) -> None:
        if self._original is not self or self._closing or self._source is not None:
            raise LocalInstallationError('Original component read is unavailable')
        _read_file(self.path, maximum=self.expected, expected=self.expected,
                   digest=self.digest, _original=self)

    def observe(self) -> None:
        if (self._original is not self or self._closing or self._source is None
                or self._stamp is None):
            raise LocalInstallationError('Original component descriptor is unavailable')
        descriptor = os.fstat(self._source.value)
        named = self.path.stat(follow_symlinks=False)
        if (not stat.S_ISREG(named.st_mode) or self._snapshot(descriptor) != self._stamp
                or self._snapshot(named) != self._stamp):
            raise LocalInstallationError('Original component changed during initialization')

    def __exit__(self, kind: Any, primary: BaseException | None, trace: Any) -> None:
        try:
            self.close()
        except LocalComponentReadCleanupPending as pending:
            pending.original_error = primary
            raise

    def close(self) -> None:
        if self._original is not self:
            raise LocalInstallationError('Copied original component descriptor')
        self._closing = True
        if self._source is not None:
            source = self._source
            try:
                source.close()
            except BaseException as error:
                pending = LocalComponentReadCleanupPending(source)
                pending.cleanup_error = error
                raise pending from error
            self._source = None


def _read_file(path: Path, *, maximum: int, expected: int | None = None,
               digest: str | None = None, capture: bool = False, prefix: int = 0,
               _original: _OriginalComponentFile | None = None) -> bytes:
    if type(prefix) is not int or prefix < 0 or prefix > maximum or capture and prefix:
        raise LocalInstallationError('Invalid installed Local prefix read')
    if _original is not None and (type(_original) is not _OriginalComponentFile
            or _original.path != path or _original.expected != expected or _original.digest != digest):
        raise LocalInstallationError('Foreign original component reader')
    from ._local_worker_slot import _OriginalDescriptor
    # Prepare the same existing physical FD carrier before acquisition. Avoid a
    # second buffered-reader constructor that could fail after open but before
    # accepting ownership. These records supply no capacity or installation.
    source = _OriginalDescriptor(-1)
    pending = LocalComponentReadCleanupPending(source)
    primary: BaseException | None = None
    retained = False
    # Installed wheels are ordinary nofollow files, never extracted archives.
    source.value = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        before = os.fstat(source.value)
        if (not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= maximum
                or expected is not None and before.st_size != expected):
            raise LocalInstallationError('Invalid installed Local component size')
        checksum = hashlib.sha256()
        captured = bytearray() if digest is None or capture or prefix else None
        remaining = before.st_size
        while remaining:
            block = os.read(source.value, min(65536, remaining))
            if not block:
                raise LocalInstallationError('Incomplete installed Local component')
            checksum.update(block)
            remaining -= len(block)
            if captured is not None:
                captured.extend(block[:max(0, prefix - len(captured))] if prefix else block)
        after = os.fstat(source.value)
        if (os.read(source.value, 1) or (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns,
                              before.st_ctime_ns) != (after.st_dev, after.st_ino, after.st_size,
                                                      after.st_mtime_ns, after.st_ctime_ns)
                or digest is not None and checksum.hexdigest() != digest):
            raise LocalInstallationError('Installed Local component changed or digest mismatched')
        result = bytes(captured) if captured is not None else b''
        if _original is not None:
            _original._retain(source, before, checksum.hexdigest())
            retained = True
        return result
    except BaseException as failure:
        primary = failure
        raise
    finally:
        try:
            if not retained:
                source.close()
        except BaseException as cleanup:
            # Failure does not establish whether close consumed the OS FD.
            # Keep both causes and the original one-shot carrier; no retry on
            # the same integer after possible descriptor-number reuse.
            pending.original_error = primary
            pending.cleanup_error = cleanup
            raise pending from cleanup


def _component(root: Path, value: Any, filename: str, maximum: int) -> tuple[Path, str]:
    item = _closed(value, ('file', 'bytes', 'sha256'))
    if (item['file'] != filename or type(item['bytes']) is not int
            or not 0 < item['bytes'] <= maximum or not _hex(item['sha256'], 64)):
        raise LocalInstallationError('Invalid installed Local component descriptor')
    path = root / filename
    _read_file(path, maximum=maximum, expected=item['bytes'], digest=item['sha256'])
    return path, item['sha256']


def _valid_image_header(header: bytes, size: int) -> bool:
    # Wasmtime serializes code as an ELF object even on the selected macOS
    # host. This checks the binary architecture, not Engine compatibility.
    return (size >= 64 and len(header) == 20
            and header[:7] == b'\x7fELF\x02\x01\x01'
            and header[18:20] == b'\xb7\x00')


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise LocalInstallationError('Duplicate installed Local manifest field')
        value[key] = item
    return value


def _inspect_local_components_for_packaging(root: Path, *, target_platform: str,
                                           package_version: str,
                                           artifact_sha256: str | None = None) -> LocalComponents:
    """Read the selected target's original bytes without adopting or loading it.

    A release preparation host need not execute its artifact target. This is
    the same full component/recipe predicate, not a Linux runtime grant. The
    producer still owns actual library format/ABI inspection and source gates.
    """
    if type(target_platform) is not str or target_platform != _LOCAL_COMPONENT_PLATFORM:
        raise LocalInstallationError('No selected component verifier for this packaging target')
    try:
        if artifact_sha256 is not None and not _hex(artifact_sha256, 64):
            raise LocalInstallationError('Invalid SDK-bound Local artifact digest')
        raw = _read_file(root / 'artifact.json', maximum=65536, digest=artifact_sha256, capture=True)
        body = _closed(json.loads(raw, object_pairs_hook=_pairs), (
            'source_sha', 'package_version', 'platform', 'core_abi', 'wasmtime_version',
            'module', 'duckdb', 'duckdb_version', 'notices', 'compiled_image', 'engine_recipe'))
        if (not _hex(body['source_sha'], 40) or type(package_version) is not str
                or not package_version or body['package_version'] != package_version
                or body['platform'] != _LOCAL_COMPONENT_PLATFORM
                or type(body['core_abi']) is not int or body['core_abi'] != LOCAL_CORE_ABI
                or body['wasmtime_version'] != WASMTIME_VERSION
                or body['duckdb_version'] != DUCKDB_VERSION):
            raise LocalInstallationError('Installed Local release cohort is incompatible')
        module, module_hash = _component(root, body['module'], 'client_host_wasm.wasm', 32 * 1024 * 1024)
        library, library_hash = _component(root, body['duckdb'], 'libduckdb.dylib', 128 * 1024 * 1024)
        # These component checks establish correspondence only. The original
        # Host capacity supplier still precedes VM construction and image capture.
        from ._local_image_recipe import _image_descriptor, _recipe_from_original
        recipe_path, recipe_hash = _component(root, body['engine_recipe'],
                                               'engine-recipe.json', 65536)
        original_recipe = _read_file(recipe_path, maximum=65536, digest=recipe_hash, capture=True)
        recipe = _recipe_from_original(original_recipe, source_sha=body['source_sha'],
            package_version=package_version, module_sha256=module_hash)
        image = _image_descriptor(body['compiled_image'], recipe)
        image_path = root / image['file']
        header = _read_file(image_path, maximum=recipe.image_bytes_limit,
                   expected=image['bytes'], digest=image['sha256'], prefix=20)
        if not _valid_image_header(header, image['bytes']):
            raise LocalInstallationError('Installed Local image has an incompatible binary target')
        notices = _closed(body['notices'], _NOTICES)
        for filename in _NOTICES:
            if not _hex(notices[filename], 64):
                raise LocalInstallationError('Invalid installed Local license descriptor')
            _read_file(root / filename, maximum=1024 * 1024, digest=notices[filename])
        return LocalComponents(body['source_sha'], package_version, module, module_hash,
                               library, library_hash, body['duckdb_version'], image_path,
                               image['sha256'], image['bytes'], recipe, recipe_path, recipe_hash)
    except (OSError, ValueError, UnicodeError, RecursionError) as original:
        raise LocalInstallationError('Installed Local components are unavailable or invalid') from original


def inspect_local_components(root: Path, *, package_version: str,
                             artifact_sha256: str | None = None) -> LocalComponents:
    """Inspect an installed supplier, before optional engines or foreign loading.

    These hashes are release integrity, not current Host publisher authority.
    The existing Wasm/DuckDB loaders still validate the exact bytes they load.
    The producer owns binary target and ABI evidence; this inspection is not
    execution or a claim that an artifact passed product acceptance.
    """
    if sys.platform != 'darwin' or platform.machine() != 'arm64':
        raise LocalInstallationError('Python Local is not available for this platform')
    return _inspect_local_components_for_packaging(root, target_platform=_LOCAL_COMPONENT_PLATFORM,
        package_version=package_version, artifact_sha256=artifact_sha256)


def installed_local_components() -> LocalComponents:
    """Only a selected Local connection calls this installed-package resolver."""
    if sys.platform != 'darwin' or platform.machine() != 'arm64':
        raise LocalInstallationError('Python Local is not available for this platform')
    try:
        version = metadata.version('actql-sdk')
        if (metadata.version('actql') != version
                or metadata.version('actql-local-runtime') != version):
            raise LocalInstallationError('Installed Local release cohort is incompatible')
        if metadata.version('wasmtime') != WASMTIME_VERSION:
            raise LocalInstallationError('Installed Local Wasmtime dependency is incompatible')
        root = resources.files('actql_local_runtime')
        if not isinstance(root, Path):
            raise LocalInstallationError('Python Local requires an installed runtime wheel')
        sdk_root = resources.files('actql_sdk')
        if not isinstance(sdk_root, Path):
            raise LocalInstallationError('Python Local requires an installed SDK wheel')
        # The cohort builder writes this source-qualified binding into the SDK
        # wheel. An independently changed runtime manifest cannot self-authorize
        # its image by changing both the declared recipe and file checksums.
        decoded = json.loads(_read_file(sdk_root / '_local_release_binding.json',
            maximum=65536), object_pairs_hook=_pairs)
        platform_runtime = type(decoded) is dict and 'runtime_allocation' in decoded
        binding = _closed(decoded,
            ('source_sha', 'package_version', 'core_abi', 'artifact_sha256',
             'runtime_allocation' if platform_runtime else 'host_capacity_sha256'))
        if (not _hex(binding['source_sha'], 40) or binding['package_version'] != version
                or type(binding['core_abi']) is not int or binding['core_abi'] != LOCAL_CORE_ABI
                or not _hex(binding['artifact_sha256'], 64)
                or (binding['runtime_allocation'] != 'platform' if platform_runtime
                    else not _hex(binding['host_capacity_sha256'], 64))):
            raise LocalInstallationError('Installed SDK Local cohort binding is incompatible')
        components = inspect_local_components(root, package_version=version,
            artifact_sha256=binding['artifact_sha256'])
        if components.source_sha != binding['source_sha']:
            raise LocalInstallationError('Installed SDK and Local source do not match')
        if platform_runtime != (components.image_recipe.runtime_allocation == 'platform'):
            raise LocalInstallationError('Installed SDK and runtime allocation differ')
        return components
    except (OSError, ValueError, UnicodeError, RecursionError) as original:
        raise LocalInstallationError('Installed SDK Local cohort binding is unavailable or invalid') from original
    except (metadata.PackageNotFoundError, ModuleNotFoundError) as original:
        raise LocalInstallationError('Python Local requires the standard actql installation') from original


def load_local_module(components: LocalComponents) -> bytes:
    """Acquire bounded bytes and validate their digest on the same descriptor.

    Prior component inspection does not authorize an unchecked later reread.
    The trusted Host must account for the load/compile phase before calling
    this function; a file-size cap is not a total Wasmtime memory guarantee.
    """
    if type(components) is not LocalComponents or not _hex(components.module_sha256, 64):
        raise LocalInstallationError('Invalid installed Local module descriptor')
    try:
        return _read_file(components.module, maximum=32 * 1024 * 1024,
                          digest=components.module_sha256, capture=True)
    except OSError as original:
        raise LocalInstallationError('Installed Local module is unavailable') from original
