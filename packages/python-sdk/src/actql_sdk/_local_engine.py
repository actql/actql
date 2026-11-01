"""Pinned physical Engine configuration shared by image producer and runtime.

No module compilation, Run admission, allocator adoption or authority is
performed by this adapter. Callers retain the original native handles until
cleanup succeeds, and fund the selected bootstrap before constructing them.
"""
from __future__ import annotations

from contextlib import ExitStack as _ExitStack
from ctypes import ArgumentError, CDLL, c_char_p, c_void_p, cast
from dataclasses import dataclass
import hashlib
from importlib import metadata
from pathlib import Path
import json
from typing import Any

from ._local_image_recipe import _SelectedImageRecipe, _load_selected_image
from ._local_distribution import LocalComponents, LocalInstallationError, WASMTIME_VERSION, _OriginalComponentFile, _read_file, _pairs


def _selected_engine_settings(recipe: _SelectedImageRecipe) -> tuple[tuple[str, str, bool | int | str], ...]:
    """The same validated settings for Python and private compiler C callers.

    This immutable projection is DATA, not a Config, allocator or admission.
    The original recipe remains the only validator of accepted values.
    """
    recipe.validate()
    body = json.loads(recipe.engine_body)
    settings: list[tuple[str, str, bool | int | str]] = [
        ('config', 'consume_fuel', body['consume_fuel']),
        ('config', 'strategy', body['strategy']),
        ('config', 'target', body['target']),
    ]
    # Explicit target suppresses host-inferred ISA features in pinned Wasmtime
    # 38. The baseline recipe never calls flag_enable or enables host tuning.
    for name in ('parallel_compilation', 'wasm_gc', 'wasm_component_model', 'async_support',
                 'memory_reservation', 'memory_guard_size',
                 'memory_reservation_for_growth', 'max_wasm_stack'):
        settings.append(('config', name, body[name]))
    settings.extend(('pool', name, value) for name, value in body['pooling'].items())
    return tuple(settings)


def _configure_selected_engine(config: Any, pool: Any, ffi: Any,
                               wasmtime: Any, recipe: _SelectedImageRecipe) -> None:
    settings = _selected_engine_settings(recipe)
    for _, name, value in settings[:2]:
        setattr(config, name, value)
    pointer = config.ptr()
    for domain, name, value in settings[2:]:
        if domain == 'config' and name == 'target':
            assert isinstance(value, str)
            error = ffi.wasmtime_config_target_set(pointer, c_char_p(value.encode('ascii')))
            if error:
                raise wasmtime.WasmtimeError._from_ptr(error)
        else:
            prefix = 'wasmtime_config_' if domain == 'config' else 'wasmtime_pooling_allocation_config_'
            getattr(ffi, prefix + name + '_set')(pointer if domain == 'config' else pool, value)
    ffi.wasmtime_pooling_allocation_strategy_set(pointer, pool)


@dataclass(frozen=True, slots=True)
class _InstalledImageInput:
    encoded: bytes
    sha256: str
    recipe: _SelectedImageRecipe
    runtime_library: Path


@dataclass(frozen=True, slots=True)
class _InstalledImageFileInput:
    """Installed descriptor only; capture requires the original native holding."""

    path: Path
    length: int
    sha256: str
    recipe: _SelectedImageRecipe
    runtime_library: Path


def _checked_installed_image_file(components: LocalComponents) -> _InstalledImageFileInput:
    """Reuse original component/recipe checks without capturing whole image bytes.

    This supplies no allocator, capacity, library adoption or execution authority.
    The genuine original holding must already exist before native FD capture.
    """
    library = _installed_runtime_library(components, native=True)
    recipe = components.image_recipe
    body = json.loads(_read_file(components.image.parent / 'artifact.json', maximum=65536),
                      object_pairs_hook=_pairs)
    from ._local_image_recipe import _image_descriptor
    item = _image_descriptor(body['compiled_image'], recipe)
    if (components.image.name != item['file'] or components.image_bytes != item['bytes']
            or components.image_sha256 != item['sha256']):
        raise LocalInstallationError('Installed image original descriptor mismatch')
    return _InstalledImageFileInput(components.image, item['bytes'], item['sha256'], recipe, library)


def _verify_original_provider(library: Path, recipe: _SelectedImageRecipe) -> None:
    digest, size = recipe.owned_provider()
    provider = library.parent / 'libactql_native_control.dylib'
    for directory in (library.parent.parent, library.parent):
        if directory.is_symlink() or not directory.is_dir():
            raise LocalInstallationError('Installed original native provider directory is invalid')
    _read_file(provider, maximum=size, expected=size, digest=digest)


def _platform_runtime_library(recipe: _SelectedImageRecipe) -> Path:
    """Resolve the existing pinned dependency, without loading native code."""
    recipe.validate()
    distribution = metadata.distribution('wasmtime')
    if distribution.version != WASMTIME_VERSION:
        raise LocalInstallationError('Installed image runtime version mismatch')
    # resources.files imports a named package; Wasmtime's initializer loads its
    # DLL. Distribution metadata locates wheel files without that side effect.
    root = distribution.locate_file('wasmtime')
    if not isinstance(root, Path):
        raise LocalInstallationError('Installed image runtime requires ordinary wheel files')
    library = root / 'darwin-aarch64/_libwasmtime.dylib'
    _read_file(library, maximum=recipe.runtime_library_bytes,
               expected=recipe.runtime_library_bytes, digest=recipe.runtime_library_sha256)
    return library


def _installed_runtime_library(components: LocalComponents, *, native: bool = False) -> Path:
    if type(components) is not LocalComponents:
        raise LocalInstallationError('Unavailable installed Local image components')
    recipe = components.image_recipe
    recipe.validate()
    if (recipe.source_sha != components.source_sha
            or recipe.package_version != components.package_version
            or recipe.module_sha256 != components.module_sha256):
        raise LocalInstallationError('Installed image original component binding mismatch')
    _read_file(components.module, maximum=32 * 1024 * 1024, digest=components.module_sha256)
    if native:
        recipe.owned_provider()
        # Do not import the private bindings to discover their directory. Their
        # generated functions capture DLL addresses at import, after the trusted
        # supplier has acquired and transferred the original native holding.
        if metadata.version('actql-local-runtime') != components.package_version:
            raise LocalInstallationError('Installed native runtime cohort mismatch')
        root = components.image.parent / '_wasmtime'
        # Bind the exact dependency before the private binding's native loader
        # can resolve it. These bytes confer no physical funding or authority.
        _verify_original_provider(root / 'darwin-aarch64/_libwasmtime.dylib', recipe)
    else:
        return _platform_runtime_library(recipe)
    library = root / 'darwin-aarch64/_libwasmtime.dylib'
    _read_file(library, maximum=recipe.runtime_library_bytes,
               expected=recipe.runtime_library_bytes, digest=recipe.runtime_library_sha256)
    return library


def _checked_installed_image(components: LocalComponents) -> _InstalledImageInput:
    """Resolve only the installed original. No arbitrary image or path argument."""
    if type(components) is not LocalComponents:
        raise LocalInstallationError('Unavailable installed Local image components')
    recipe = components.image_recipe
    recipe.validate()
    if (recipe.source_sha != components.source_sha
            or recipe.package_version != components.package_version
            or recipe.module_sha256 != components.module_sha256):
        raise LocalInstallationError('Installed image original component binding mismatch')
    try:
        _read_file(components.module, maximum=32 * 1024 * 1024, digest=components.module_sha256)
        library = _platform_runtime_library(recipe)
        # The recipe belongs to the same SDK-bound artifact manifest. Recheck
        # its fields and exact image bytes before the unsafe native loader.
        body = json.loads(_read_file(components.image.parent / 'artifact.json', maximum=65536),
                          object_pairs_hook=_pairs)
        from ._local_image_recipe import _image_descriptor
        descriptor = _image_descriptor(body['compiled_image'], recipe)
        if (descriptor['sha256'] != components.image_sha256
                or descriptor['bytes'] != components.image_bytes
                or descriptor['file'] != components.image.name):
            raise LocalInstallationError('Installed image changed after component inspection')
        # The same local descriptor is checked by the bounded file reader and
        # its complete digest before it returns immutable bytes. Do not hash
        # those same bytes again merely to compare the already-bound digest.
        image = _load_selected_image(components.image.parent, body['compiled_image'], recipe)
        return _InstalledImageInput(image, components.image_sha256, recipe, library)
    except (OSError, KeyError, TypeError, ValueError, UnicodeError, RecursionError,
            metadata.PackageNotFoundError) as original:
        raise LocalInstallationError('Installed image runtime is unavailable or inconsistent') from original


class _InitializationLibraryFiles:
    """Original hashed FDs retained only across one read-only loader fence.

    No path cache survives initialization, and no capacity, DLL or authority
    is obtained from these records. The post-load read still checks all bytes.
    """
    def __init__(self, recipe: _SelectedImageRecipe, runtime_library: Path) -> None:
        self._original = self
        self._recipe, self._runtime_library = recipe, runtime_library
        self._stack = _ExitStack()
        self._files: dict[Path, _OriginalComponentFile] = {}
        self._active = False
        self._closed = False

    def __enter__(self) -> _InitializationLibraryFiles:
        if self._original is not self or self._active or self._closed:
            raise LocalInstallationError('Original initialization file scope is unavailable')
        self._active = True
        return self

    def __exit__(self, *failure: Any) -> bool | None:
        self._active, self._closed = False, True
        return self._stack.__exit__(*failure)

    def _require(self, recipe: _SelectedImageRecipe, runtime_library: Path) -> None:
        if (self._original is not self or not self._active or self._closed
                or recipe is not self._recipe or runtime_library != self._runtime_library):
            raise LocalInstallationError('Foreign or retired initialization file scope')

    def _read(self, path: Path, size: int, digest: str) -> None:
        original = self._files.get(path)
        if original is None:
            original = _OriginalComponentFile(path, expected=size, digest=digest)
            # Register before acquisition; failed reads retain the same existing
            # one-shot FD carrier and do not acquire a replacement descriptor.
            self._stack.push(original.__exit__)
            original.read()
            self._files[path] = original
        original.observe()

    def observe(self, recipe: _SelectedImageRecipe, runtime_library: Path, *,
                provider: bool) -> None:
        self._require(recipe, runtime_library)
        self._read(runtime_library, recipe.runtime_library_bytes, recipe.runtime_library_sha256)
        if provider:
            for directory in (runtime_library.parent.parent, runtime_library.parent):
                if directory.is_symlink() or not directory.is_dir():
                    raise LocalInstallationError('Installed original native provider directory is invalid')
            digest, size = recipe.owned_provider()
            self._read(runtime_library.parent / 'libactql_native_control.dylib', size, digest)


def _verify_loaded_runtime(image: _InstalledImageInput | _InstalledImageFileInput, ffi: Any, *,
                           _initialization_files: _InitializationLibraryFiles | None = None) -> None:
    """Fence the dependency native loader before any Config/Engine construction."""
    actual = Path(ffi.filename)
    if actual != image.runtime_library or Path(ffi.dll._name) != image.runtime_library:
        raise LocalInstallationError('Loaded image runtime differs from the original selected wheel')
    if _initialization_files is not None:
        _initialization_files.observe(image.recipe, actual, provider=type(image) is _InstalledImageFileInput)
    else:
        _read_file(actual, maximum=image.recipe.runtime_library_bytes,
                   expected=image.recipe.runtime_library_bytes, digest=image.recipe.runtime_library_sha256)
        if type(image) is _InstalledImageFileInput:
            _verify_original_provider(actual, image.recipe)


# Exact external symbols used by the selected Rust forwarding module. Compare
# the imported C functions, not the Rust wrapper addresses (which differ).
_ORIGINAL_PROVIDER_SYMBOLS = (
    'acquire', 'transfer', 'enter', 'leave', 'current', 'capacity_bytes',
    'contains_live_span', 'allocate', 'protect', 'retire', 'try_close',
    'seal_readonly', 'capture_image_fd',
)


def _verify_original_provider_link(image: _InstalledImageFileInput,
                                   runtime: Any, provider: Any, *,
                                   _initialization_files: _InitializationLibraryFiles | None = None) -> None:
    if type(image) is not _InstalledImageFileInput:
        raise LocalInstallationError('Original installed image input is unavailable')
    _verify_selected_provider_link(image.recipe, image.runtime_library, runtime, provider,
                                   _initialization_files=_initialization_files)


def _verify_selected_provider_link(recipe: _SelectedImageRecipe, runtime_library: Path,
                                   runtime: Any, provider: Any, *,
                                   _initialization_files: _InitializationLibraryFiles | None = None) -> None:
    """Check already loaded matching components, without loading/calling them.

    This proves code/provider identity only, never a holding, capacity, funding,
    current authority, Engine initialization or physical retirement. A distinct
    library that embeds its own provider/TLS cannot pass the imported addresses.
    """
    if (not isinstance(runtime, CDLL) or not isinstance(provider, CDLL)
            or type(runtime._name) is not str or type(provider._name) is not str
            or Path(runtime._name) != runtime_library
            or Path(provider._name) != runtime_library.parent / 'libactql_native_control.dylib'):
        raise LocalInstallationError('Loaded Local runtime and original provider paths differ')
    recipe.validate()
    if _initialization_files is None:
        with _InitializationLibraryFiles(recipe, runtime_library) as originals:
            _verify_selected_provider_link(recipe, runtime_library, runtime, provider,
                                           _initialization_files=originals)
        return
    _initialization_files.observe(recipe, runtime_library, provider=True)
    for suffix in _ORIGINAL_PROVIDER_SYMBOLS:
        name = 'actql_native_owned_' + suffix
        try:
            actual = cast(getattr(runtime, name), c_void_p).value
            original = cast(getattr(provider, name), c_void_p).value
        except (AttributeError, TypeError, ValueError, ArgumentError) as error:
            raise LocalInstallationError('Original Local provider linkage is unavailable') from error
        if actual is None or original is None or actual != original:
            raise LocalInstallationError('Local runtime uses a different original capacity or TLS provider')
    # The same exact descriptors and named files must remain unchanged through
    # all read-only address casts; no load, provider call or await occurs here.
    _initialization_files.observe(recipe, runtime_library, provider=True)
