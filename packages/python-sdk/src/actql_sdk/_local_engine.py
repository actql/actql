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


def _verify_loaded_runtime(image: _InstalledImageInput, ffi: Any) -> None:
    """Fence the dependency native loader before any Config/Engine construction."""
    actual = Path(ffi.filename)
    if actual != image.runtime_library or Path(ffi.dll._name) != image.runtime_library:
        raise LocalInstallationError('Loaded image runtime differs from the original selected wheel')
    _read_file(actual, maximum=image.recipe.runtime_library_bytes,
               expected=image.recipe.runtime_library_bytes, digest=image.recipe.runtime_library_sha256)
