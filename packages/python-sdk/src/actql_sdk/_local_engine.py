"""Pinned physical Engine configuration shared by image producer and runtime.

No module compilation, Run admission, allocator adoption or authority is
performed by this adapter. Callers retain the original native handles until
cleanup succeeds, and fund the selected bootstrap before constructing them.
"""
from __future__ import annotations

from ctypes import c_char_p
from dataclasses import dataclass
import hashlib
from importlib import metadata, resources
from pathlib import Path
import json
from typing import Any

from ._local_image_recipe import _SelectedImageRecipe, _load_selected_image
from ._local_distribution import LocalComponents, LocalInstallationError, WASMTIME_VERSION, _read_file, _pairs


def _configure_selected_engine(config: Any, pool: Any, ffi: Any,
                               wasmtime: Any, recipe: _SelectedImageRecipe) -> None:
    recipe.validate()
    body = json.loads(recipe.engine_body)
    config.consume_fuel = body['consume_fuel']
    config.strategy = body['strategy']
    pointer = config.ptr()
    error = ffi.wasmtime_config_target_set(pointer, c_char_p(body['target'].encode('ascii')))
    if error:
        raise wasmtime.WasmtimeError._from_ptr(error)
    # Explicit target suppresses host-inferred ISA features in pinned Wasmtime
    # 38. The baseline recipe never calls flag_enable or enables host tuning.
    for name in ('parallel_compilation', 'wasm_gc', 'wasm_component_model', 'async_support',
                 'memory_reservation', 'memory_guard_size',
                 'memory_reservation_for_growth', 'max_wasm_stack'):
        getattr(ffi, 'wasmtime_config_' + name + '_set')(pointer, body[name])
    for name, value in body['pooling'].items():
        getattr(ffi, 'wasmtime_pooling_allocation_config_' + name + '_set')(pool, value)
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
    provider = library.parent / 'libactql_native_control.dylib'
    for directory in (library.parent.parent, library.parent):
        if directory.is_symlink() or not directory.is_dir():
            raise LocalInstallationError('Installed original native provider directory is invalid')
    _read_file(provider, maximum=recipe.provider_library_bytes,
               expected=recipe.provider_library_bytes, digest=recipe.provider_library_sha256)


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
        if metadata.version('wasmtime') != WASMTIME_VERSION:
            raise LocalInstallationError('Installed image runtime version mismatch')
        selected_root = resources.files('wasmtime')
        if not isinstance(selected_root, Path):
            raise LocalInstallationError('Installed image runtime requires ordinary wheel files')
        root = selected_root
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
        if metadata.version('wasmtime') != WASMTIME_VERSION:
            raise LocalInstallationError('Installed image runtime version mismatch')
        root = resources.files('wasmtime')
        if not isinstance(root, Path):
            raise LocalInstallationError('Installed image runtime requires ordinary wheel files')
        library = root / 'darwin-aarch64/_libwasmtime.dylib'
        _read_file(library, maximum=recipe.runtime_library_bytes,
                   expected=recipe.runtime_library_bytes, digest=recipe.runtime_library_sha256)
        # The recipe belongs to the same SDK-bound artifact manifest. Recheck
        # its fields and exact image bytes before the unsafe native loader.
        body = json.loads(_read_file(components.image.parent / 'artifact.json', maximum=65536),
                          object_pairs_hook=_pairs)
        image = _load_selected_image(components.image.parent, body['compiled_image'], recipe)
        if hashlib.sha256(image).hexdigest() != components.image_sha256:
            raise LocalInstallationError('Installed image changed after component inspection')
        return _InstalledImageInput(image, components.image_sha256, recipe, library)
    except (OSError, KeyError, TypeError, ValueError, UnicodeError, RecursionError,
            metadata.PackageNotFoundError) as original:
        raise LocalInstallationError('Installed image runtime is unavailable or inconsistent') from original


def _verify_loaded_runtime(image: _InstalledImageInput | _InstalledImageFileInput, ffi: Any) -> None:
    """Fence the dependency native loader before any Config/Engine construction."""
    actual = Path(ffi.filename)
    if actual != image.runtime_library or Path(ffi.dll._name) != image.runtime_library:
        raise LocalInstallationError('Loaded image runtime differs from the original selected wheel')
    _read_file(actual, maximum=image.recipe.runtime_library_bytes,
               expected=image.recipe.runtime_library_bytes, digest=image.recipe.runtime_library_sha256)
    if type(image) is _InstalledImageFileInput:
        _verify_original_provider(actual, image.recipe)
