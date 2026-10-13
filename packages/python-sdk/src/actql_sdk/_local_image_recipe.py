"""Private precompiled-image preparation; no engine or authority creation.

The selected installer supplies the expected immutable recipe. This module
checks artifact correspondence only. It does not adopt a capacity profile,
deserialize an image, infer CPU compatibility, or authorize execution.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
from typing import Any

from ._local_core import LOCAL_CORE_ABI
from ._local_distribution import LocalInstallationError, WASMTIME_VERSION, _closed, _hex, _pairs, _read_file


@dataclass(frozen=True, slots=True)
class _SelectedImageRecipe:
    source_sha: str
    package_version: str
    module_sha256: str
    runtime_library_sha256: str
    engine_body: bytes
    image_bytes_limit: int

    def validate(self) -> None:
        if (not _hex(self.source_sha, 40) or type(self.package_version) is not str
                or not self.package_version or not _hex(self.module_sha256, 64)
                or not _hex(self.runtime_library_sha256, 64)
                or type(self.engine_body) is not bytes
                or not 0 < len(self.engine_body) <= 65536
                or type(self.image_bytes_limit) is not int or self.image_bytes_limit <= 0):
            raise LocalInstallationError('Unavailable selected Local image recipe')
        try:
            body = _closed(json.loads(self.engine_body, object_pairs_hook=_pairs), (
                'target', 'cpu_features', 'consume_fuel', 'strategy',
                'parallel_compilation', 'allocation', 'pooling'))
            # An explicit baseline target avoids compilation for the producer's
            # detected CPU. Actual pinned compiler/config validation is separate.
            if (body['target'] != 'aarch64-apple-darwin'
                    or body['cpu_features'] != ['aarch64-baseline']
                    or body['consume_fuel'] is not True
                    or body['strategy'] != 'cranelift'
                    or body['parallel_compilation'] is not False
                    or body['allocation'] != 'pooling'):
                raise LocalInstallationError('Unsupported selected Local engine recipe')
            pool = _closed(body['pooling'], (
                'total_core_instances', 'total_memories', 'max_memories_per_module',
                'max_memory_size', 'max_core_instance_size', 'total_tables',
                'max_tables_per_module', 'table_elements', 'total_gc_heaps'))
            if (any(type(value) is not int or not 0 < value <= (2**64 - 1 if name in (
                    'max_memory_size', 'max_core_instance_size', 'table_elements') else 2**32 - 1)
                    for name, value in pool.items())
                    or pool['total_core_instances'] != 1 or pool['total_memories'] != 1
                    or pool['max_memories_per_module'] != 1
                    or pool['max_memory_size'] != 16 * 1024 * 1024):
                raise LocalInstallationError('Unavailable selected Local pooling recipe')
        except (ValueError, UnicodeError, RecursionError) as original:
            raise LocalInstallationError('Invalid selected Local image recipe') from original


def _image_descriptor(body: Any, recipe: _SelectedImageRecipe) -> dict[str, Any]:
    if type(recipe) is not _SelectedImageRecipe:
        raise LocalInstallationError('Unavailable selected Local image recipe')
    recipe.validate()
    item = _closed(body, ('source_sha', 'package_version', 'module_sha256',
        'core_abi', 'wasmtime_version', 'runtime_library_sha256', 'platform',
        'engine_body', 'engine_sha256', 'file', 'bytes', 'sha256'))
    expected = json.loads(recipe.engine_body, object_pairs_hook=_pairs)
    # Compare exact canonical bytes too: JSON equality alone identifies True
    # and 1 in Python, which is not this closed engine-setting contract.
    encoded = json.dumps(item['engine_body'], sort_keys=True, separators=(',', ':'),
                         ensure_ascii=True, allow_nan=False).encode('ascii')
    original = json.dumps(expected, sort_keys=True, separators=(',', ':'),
                          ensure_ascii=True, allow_nan=False).encode('ascii')
    if (item['source_sha'] != recipe.source_sha
            or item['package_version'] != recipe.package_version
            or item['module_sha256'] != recipe.module_sha256
            or type(item['core_abi']) is not int or item['core_abi'] != LOCAL_CORE_ABI
            or item['wasmtime_version'] != WASMTIME_VERSION
            or item['runtime_library_sha256'] != recipe.runtime_library_sha256
            or item['platform'] != 'darwin-arm64' or encoded != original
            or item['engine_sha256'] != hashlib.sha256(original).hexdigest()
            or item['file'] != 'client_host_wasm.cwasm'
            or type(item['bytes']) is not int
            or not 0 < item['bytes'] <= recipe.image_bytes_limit
            or not _hex(item['sha256'], 64)):
        raise LocalInstallationError('Installed Local image does not match the selected recipe')
    return item


def _load_selected_image(root: Path, body: Any, recipe: _SelectedImageRecipe) -> bytes:
    """Read exact installed image bytes; never deserialize or fall back to JIT.

    The future installed resolver must supply this directory and original
    recipe. There is no user image/path option. Native/runtime-library identity
    and the bootstrap capacity supplier must still be checked before loading.
    """
    try:
        item = _image_descriptor(body, recipe)
        return _read_file(root / item['file'], maximum=recipe.image_bytes_limit,
                          expected=item['bytes'], digest=item['sha256'], capture=True)
    except (OSError, TypeError, ValueError, UnicodeError, RecursionError) as original:
        raise LocalInstallationError('Installed Local image is unavailable or invalid') from original
