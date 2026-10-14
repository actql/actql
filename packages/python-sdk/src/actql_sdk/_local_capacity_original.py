"""Source-bound installed Host configuration, not admission or an allocator.

Only the release producer supplies this private original. Its numerical values
and physical bootstrap envelope require integrator adoption; decoding them does
not prove a physical allocation, create authorization or account universal RSS.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
from importlib import resources
import json
from pathlib import Path
from typing import Any

from ._local_core import LOCAL_CORE_ABI, LocalCoreResources
from ._local_distribution import LocalComponents, LocalInstallationError, _closed, _hex, _pairs, _read_file

_ROOT_FIELDS = ('planning_work', 'attempts', 'holdings', 'transfer_bytes',
                'retained_bytes', 'execution_bytes')
_PROFILE_FIELDS = ('platform', 'backend', 'allocation_domain', 'engine_recipe_sha256',
                   'host_capacity_bytes', 'bootstrap_execution_bytes', 'root')


@dataclass(frozen=True, slots=True)
class _HostCapacityOriginal:
    resources: LocalCoreResources
    host_capacity_bytes: int
    bootstrap_execution_bytes: int


def _capacity_from_source(original: bytes, components: LocalComponents) -> _HostCapacityOriginal:
    """Validate an integrator-selected original before release staging or VM I/O."""
    if type(components) is not LocalComponents or type(original) is not bytes or not 0 < len(original) <= 65536:
        raise LocalInstallationError('Unavailable original Local Host capacity')
    try:
        body = _closed(json.loads(original, object_pairs_hook=_pairs), _PROFILE_FIELDS)
        limits = _closed(body['root'], _ROOT_FIELDS)
        selected = LocalCoreResources(**limits)
        baseline, bootstrap = body['host_capacity_bytes'], body['bootstrap_execution_bytes']
        if (body['platform'] != 'darwin-arm64' or body['backend'] != 'wasmtime-precompiled-pooling'
                or body['allocation_domain'] != 'host-owned-reserved-capacity'
                or not _hex(body['engine_recipe_sha256'], 64)
                or body['engine_recipe_sha256'] != components.engine_recipe_sha256
                or not selected.valid() or selected.attempts < 3
                or type(baseline) is not int or not 0 < baseline <= 2**63 - 1
                or type(bootstrap) is not int or not 16777216 < bootstrap <= 2**63 - 1
                # This is the known current installation overlap only. It is
                # not a complete numerical proof of later Run/read holdings.
                # Bootstrap includes temporary image/FFI/native load copies;
                # the later lifetime baseline does not retain those copies.
                # Select the maximum of these disjoint phases, not their sum.
                or selected.execution_bytes < max(44441600 + baseline, bootstrap)):
            raise LocalInstallationError('Inconsistent selected Local Host capacity original')
        return _HostCapacityOriginal(selected, baseline, bootstrap)
    except (ValueError, TypeError, UnicodeError, RecursionError) as failure:
        raise LocalInstallationError('Invalid selected Local Host capacity original') from failure


def _encode_installed_capacity(original: bytes, components: LocalComponents) -> bytes:
    """Attach the release context to the exact original, without changing it."""
    _capacity_from_source(original, components)
    encoded = (json.dumps({'source_sha': components.source_sha,
        'package_version': components.package_version, 'core_abi': LOCAL_CORE_ABI,
        'module_sha256': components.module_sha256,
        'engine_recipe_sha256': components.engine_recipe_sha256,
        'original': original.decode('utf-8')}, sort_keys=True, ensure_ascii=True,
        separators=(',', ':')) + '\n').encode('ascii')
    if len(encoded) > 131072:
        raise LocalInstallationError('Installed capacity original exceeds its representation bound')
    return encoded


def _decode_installed_capacity(encoded: bytes, components: LocalComponents) -> _HostCapacityOriginal:
    if (type(components) is not LocalComponents or type(encoded) is not bytes
            or not 0 < len(encoded) <= 131072):
        raise LocalInstallationError('Unavailable installed Local Host capacity original')
    try:
        body = _closed(json.loads(encoded, object_pairs_hook=_pairs), (
            'source_sha', 'package_version', 'core_abi', 'module_sha256', 'engine_recipe_sha256', 'original'))
        if (body['source_sha'] != components.source_sha
                or body['package_version'] != components.package_version
                or type(body['core_abi']) is not int or body['core_abi'] != LOCAL_CORE_ABI
                or body['module_sha256'] != components.module_sha256
                or body['engine_recipe_sha256'] != components.engine_recipe_sha256
                or type(body['original']) is not str):
            raise LocalInstallationError('Installed Local Host capacity context mismatch')
        return _capacity_from_source(body['original'].encode('utf-8'), components)
    except (ValueError, UnicodeError, RecursionError) as failure:
        raise LocalInstallationError('Invalid installed Local Host capacity original') from failure


def _selected_capacity_original(components: LocalComponents) -> _HostCapacityOriginal:
    """No user profile/path, fixture fallback, optional engine import or VM I/O."""
    if type(components) is not LocalComponents:
        raise LocalInstallationError('Invalid installed Local capacity context')
    try:
        root = resources.files('actql_sdk')
        if not isinstance(root, Path):
            raise LocalInstallationError('Installed capacity requires ordinary wheel files')
        binding: dict[str, Any] = _closed(json.loads(_read_file(root / '_local_release_binding.json',
            maximum=65536), object_pairs_hook=_pairs),
            ('source_sha', 'package_version', 'core_abi', 'artifact_sha256', 'host_capacity_sha256'))
        artifact = _read_file(components.image.parent / 'artifact.json', maximum=65536)
        if (binding['source_sha'] != components.source_sha
                or binding['package_version'] != components.package_version
                or type(binding['core_abi']) is not int or binding['core_abi'] != LOCAL_CORE_ABI
                or binding['artifact_sha256'] != hashlib.sha256(artifact).hexdigest()
                or not _hex(binding['host_capacity_sha256'], 64)):
            raise LocalInstallationError('Installed capacity release binding mismatch')
        encoded = _read_file(root / '_local_host_capacity.json', maximum=131072,
                            digest=binding['host_capacity_sha256'], capture=True)
        return _decode_installed_capacity(encoded, components)
    except (OSError, ValueError, UnicodeError, RecursionError) as failure:
        raise LocalInstallationError('Installed Local Host capacity original is unavailable') from failure
