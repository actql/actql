"""Actual same-VM staged input backing, not a normal image or Request Run."""
import hashlib
import json
from pathlib import Path
import sys
import wasmtime
from python_local_physical import PhysicalFixture
from actql_sdk._local_core import LocalCore


class PlatformInputFixture(PhysicalFixture):
    def __init__(self, module, nonce):
        self.original = None
        self.platform_calls = []
        super().__init__(module, nonce, capacity=12 * 1024 * 1024, slots=64,
                         execution_bytes=16 * 1024 * 1024 + 12 * 1024 * 1024)

    def call(self, name, *arguments):
        if name == 'open':
            # Same original-view assembly as the existing fixed-port fixture.
            # PhysicalFixture owns the one Engine/Store/Instance and cleanup.
            core = LocalCore.__new__(LocalCore)
            core._identity, core._nonce = object(), self.nonce
            core._store, core._instance, core._exports = self.store, self.instance, self.exports
            core._closed = core._retired = core._closing = False
            core._platform_vm_original = core._platform_vm_type = None
            core._physical_holding = None
            core._observe_platform_vm(wasmtime)
            self.original = core
            name = 'open_platform'
        return super().call(name, *arguments)

    def platform_vm_observation(self, caller, nonce, ordinal):
        self.platform_calls.append(ordinal)
        if self.original is None:
            return -42
        return self.original._platform_vm_observation(caller, nonce, ordinal)

    def stage(self, ticket, payload):
        self.inputs[ticket] = payload
        handle = self.call('reserve', ticket, len(payload), sys.getsizeof(payload))
        assert handle > 0
        for start in range(0, len(payload), 16_384):
            assert self.call('fill', handle, start, min(16_384, len(payload) - start)) == 0
        return handle


module = Path(sys.argv[1]).read_bytes()
cases = []
fixture = PlatformInputFixture(module, 301)
try:
    # A long scalar is one node. Geometry observes its actual spelling instead
    # of reserving one node per character or the unused configured16384 nodes.
    payload = json.dumps('e\u0301/~😀' * 2000, ensure_ascii=False).encode()
    handle = fixture.stage(1, payload)
    assert fixture.call('seal', handle) == 0
    assert bytes(fixture.call('byte', handle, i) for i in range(len(payload))) == payload
    reader = fixture.call('borrow', handle)
    assert reader > 0
    assert fixture.call('close', handle) == -9
    assert fixture.call('return', reader) == -9
    fixture.stop_ready = fixture.cleanup_ready = True
    assert fixture.call('return', reader) == 0
    assert fixture.call('close', handle) == 0
    cases.append('same real VM preserves Unicode scalar wire and original borrower cleanup')
finally:
    fixture.close()

fixture = PlatformInputFixture(module, 302)
try:
    payload = b'[' + b','.join([b'0'] * 2048) + b']'
    retained = []
    failed = None
    # Bounded by the original64 slots and100000 work policy of PhysicalFixture;
    # no fuel, memory, policy or target geometry is raised by this component.
    for ticket in range(1, 17):
        handle = fixture.stage(ticket, payload)
        result = fixture.call('seal', handle)
        if result != 0:
            assert result == -4, result
            failed = handle
            break
        retained.append(handle)
    assert retained and failed is not None
    # Failed preflight/grow remains the same owned handle. It cannot silently
    # start a second parser, and logical cleanup still needs the physical port.
    assert fixture.call('seal', failed) == -9
    assert fixture.call('close', failed) == -9
    fixture.cleanup_ready = True
    assert fixture.call('close', failed) == 0
    for handle in retained:
        assert fixture.call('close', handle) == 0
    assert fixture.call('allocated') == 0 and fixture.call('reserved') == 0
    handle = fixture.stage(40, payload)
    assert fixture.call('seal', handle) == 0
    assert fixture.call('close', handle) == 0
    cases.append('actual input/parser coexistence refuses before allocation and original cleanup restores capacity')
finally:
    fixture.close()

fixture = PlatformInputFixture(module, 303)
try:
    handle = fixture.stage(1, b'{"x":[')
    assert fixture.call('seal', handle) == -7
    assert fixture.call('seal', handle) == -9
    assert fixture.call('close', handle) == -9
    fixture.cleanup_ready = True
    assert fixture.call('close', handle) == 0
    assert fixture.call('allocated') == 0 and fixture.call('reserved') == 0
    cases.append('original parser refusal keeps failed claim and cannot replace same parser before cleanup')
finally:
    fixture.close()

print(json.dumps({'success': True,
    'module_sha256': hashlib.sha256(module).hexdigest(), 'cases': cases,
    'scope': 'actual fixed platform VM input/preflight/parser/capacity component',
    'normal_image': False, 'request_run_admission': False,
    'external_cleanup_ports': 'explicit nominal fixture stop/cleanup, not physical ACK',
    'fuel': 'existing unmetered raw-Wasm fixture, no normal fuel qualification'}))
