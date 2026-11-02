"""New actual VM/Root/input-pool binding; no installed image or Request/Run.

The existing raw-Wasm physical fixture owns Engine/Store retirement. Its fixed
platform callback consumes a LocalCore original view of those SAME objects;
this view owns no second runtime, native holding, Root or cleanup operation.
"""
import hashlib
import json
from pathlib import Path
import sys
import wasmtime
from python_local_physical import PhysicalFixture
from actql_sdk._local_core import LocalCore


class PlatformFixture(PhysicalFixture):
    def __init__(self, module, nonce, *, delegate=None):
        self.original = None
        self.delegate = delegate
        self.platform_calls = []
        super().__init__(module, nonce, capacity=4096, slots=8,
            execution_bytes=16777216 + 4096)

    def call(self, name, *arguments):
        if name == 'open':
            # Explicit original-view assembly for this diagnostic fixture;
            # ordinary LocalCore constructs these same originals itself.
            core = LocalCore.__new__(LocalCore)
            core._identity, core._nonce = object(), self.nonce
            core._store, core._instance, core._exports = self.store, self.instance, self.exports
            core._closed = core._retired = core._closing = False
            core._platform_vm_original = None
            core._platform_vm_type = None
            core._physical_holding = None
            self.original = core
            core._observe_platform_vm(wasmtime)
            name = 'open_platform'
        return super().call(name, *arguments)

    def platform_vm_observation(self, caller, nonce, ordinal):
        self.platform_calls.append(ordinal)
        selected = self.original if self.delegate is None else self.delegate
        if selected is None:
            return -42
        return selected._platform_vm_observation(caller, nonce, ordinal)


module = Path(sys.argv[1]).read_bytes()
cases = []
left = PlatformFixture(module, 101)
try:
    # A scalar pool would need a separate4096B lease above the already held
    #16MiB VM. The original platform pool claims only actual wire allocations.
    assert left.call('reserved') == 0
    payload = b'{"n":41}'
    physical = sys.getsizeof(payload)
    handle = left.copy(1, payload, physical)
    assert left.call('allocated') == physical + 2 * len(payload)
    assert left.call('reserved') == physical
    assert 1 in left.platform_calls and left.platform_calls.count(0) >= 2
    reader = left.call('borrow', handle)
    assert reader > 0
    held = left.call('allocated')
    assert left.call('close', handle) == -9
    assert left.call('return', reader) == -9
    assert left.call('allocated') == held
    left.stop_ready = True
    assert left.call('return', reader) == 0
    left.cleanup_ready = True
    assert left.call('close', handle) == 0
    assert left.call('allocated') == 0 and left.call('reserved') == 0
    cases.append('same VM original and actual byte/copy claims survive borrower retirement')
    # Use the SAME nonce to prove that DATA equality cannot substitute for the
    # actual Caller Store/Instance/Memory at binding.
    try:
        foreign = PlatformFixture(module, 101, delegate=left.original)
    except ValueError:
        pass
    else:
        foreign.close()
        raise AssertionError('Foreign real VM binding was admitted')
    assert not left.original._closed
    cases.append('foreign actual Caller with equal nonce is refused without replacing original')
    payload = b'null'
    handle = left.copy(2, payload, sys.getsizeof(payload))
    left.original._closing = True
    assert left.call('reserve', 3, 1, 0) == -10
    held = left.call('allocated')
    assert held > 0 and not left.original._closed
    # A later successful observation cannot reopen this same closed view.
    left.original._closing = False
    assert left.call('reserve', 3, 1, 0) == -10
    assert left.call('allocated') == held
    assert left.call('close', handle) == 0
    assert left.call('close_pool') == 0
    assert left.store is not None
    cases.append('closing fences new claims while same original cleanup remains possible')
finally:
    left.close()
print(json.dumps({'success': True, 'module_sha256': hashlib.sha256(module).hexdigest(),
    'cases': cases, 'scope': 'actual platform VM Root input-pool and borrower component',
    'normal_image': False, 'request_or_run_admission': False, 'physical_store_ack': False}))
