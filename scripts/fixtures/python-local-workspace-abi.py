"""Actual shared Host root accounting; no Source/Run dispatch is asserted."""
import copy
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'packages/python-sdk/src'))
from actql_sdk._local_core import LocalCore, LocalCoreError, LocalCoreResources

module = Path(sys.argv[1]).read_bytes()
digest = hashlib.sha256(module).hexdigest()
fixed_memory = 16 * 1024 * 1024
resources = LocalCoreResources(0, 8, 0, 0, 0, fixed_memory + 1024 + 128)
core = LocalCore(module, digest=digest, transfer_capacity=1024, resources=resources)
stopped = False
cleaned = False
workspace = None
cleanup_calls = 0
stop_calls = 0

def stop():
    global stop_calls
    stop_calls += 1
    return stopped


def cleanup():
    global cleanup_calls
    cleanup_calls += 1
    return cleaned


try:
    assert core._call('workspace', 'root_reserved') == fixed_memory + 1024
    workspace = core.reserve_workspace(128, stopped=stop, cleanup=cleanup)
    assert core._call('workspace', 'root_reserved') == fixed_memory + 1024 + 128
    assert core._call('buffer', 'reserved') == 1024
    try:
        core.reserve_workspace(1, stopped=lambda: True, cleanup=lambda: True)
    except LocalCoreError as error:
        assert error.code == -4
    else:
        raise AssertionError('Root capacity was spent twice')
    try:
        core.close_workspace(copy.copy(workspace))
    except ValueError:
        pass
    else:
        raise AssertionError('Copied workspace acquired custody')
    assert core.close_workspace(workspace) is False
    assert stop_calls == 1 and cleanup_calls == 0
    stopped = True
    assert core.close_workspace(workspace) is False
    assert stop_calls == 2 and cleanup_calls == 1
    store = core._store
    assert core.close() is False
    assert core._store is store and not core._retired
    assert core._call('buffer', 'reserved') == 0
    assert core._call('workspace', 'root_reserved') == fixed_memory + 128
    cleaned = True
    assert core.close_workspace(workspace) is True
    assert stop_calls == 2 and cleanup_calls == 2
    assert core._call('workspace', 'root_reserved') == fixed_memory
    assert core.close() is True
    assert core._closed and core._store is None
    assert core.close() is True
finally:
    if not core._closed:
        stopped = cleaned = True
        if workspace is not None and core._loans.get(workspace.ticket) is workspace:
            core.close_workspace(workspace)
        assert core.close() is True

print(json.dumps({'success': True, 'module_sha256': digest,
    'cases': ['fixed_memory_reservation', 'overlapping_workspace_and_transfer',
              'aggregate_refusal', 'copied_workspace_refusal',
              'stop_and_cleanup_separation', 'host_close_retains_pending_store',
              'fixed_memory_lives_until_store_disposal']}))
