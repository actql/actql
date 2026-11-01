"""Actual raw Wasmtime block ABI with same private input callback; no normal Run."""
import hashlib
import json
from pathlib import Path
import sys

from python_local_physical import PhysicalFixture
from actql_sdk._local_core import LocalCore, _PhysicalInput


class OriginalBulkFixture(PhysicalFixture):
    def input_copy(self, caller, ticket, start, offset, length):
        self.block_calls.append((start, length))
        return self.bridge._input_copy(caller, ticket, start, offset, length)


module = Path(sys.argv[1]).read_bytes()
fixture = OriginalBulkFixture(module, 8101, capacity=262144, slots=16)
try:
    bridge = LocalCore.__new__(LocalCore)
    bridge._closed = bridge._retired = bridge._closing = False
    bridge._store, bridge._exports = fixture.store, fixture.exports
    bridge._physical_vm_observation = None
    bridge._inputs = {}
    fixture.bridge, fixture.block_calls = bridge, []
    # Independent JSON byte oracle spans three blocks, including NUL-escaped
    # content, non-BMP Unicode, a decomposed code point and CRLF.
    payload = b'"' + b'x' * 32768 + b'\\u0000/\xf0\x9f\x98\x80/e\xcc\x81"\r\n'
    original = _PhysicalInput(payload, lambda: True, lambda _: True)
    bridge._inputs[41] = original
    fixture.inputs[41] = payload
    handle = fixture.call('reserve', 41, len(payload), sys.getsizeof(payload))
    assert handle > 0
    assert fixture.call('read_block', handle, 0, 1) == -5
    for start in range(0, len(payload), 16384):
        count = min(16384, len(payload) - start)
        assert fixture.call('fill_block', handle, start, count) == 0
    assert fixture.call('seal', handle) == 0
    assert fixture.block_calls == [(0, 16384), (16384, 16384), (32768, 21)]
    assert fixture.reads == 0
    assert bridge._inputs[41] is original
    actual = []
    for start, count in fixture.block_calls:
        offset = fixture.call('read_block', handle, start, count)
        assert offset >= 0
        memory = fixture.exports['memory']
        assert count <= memory.data_len(fixture.store) - offset
        actual.append(bytes(memory.read(fixture.store, offset, offset + count)))
    assert b''.join(actual) == payload
    assert fixture.call('close', handle) == -9
    assert fixture.call('read_block', handle, 0, 1) == -5
    fixture.cleanup_ready = True
    assert fixture.call('close', handle) == 0
    assert 41 not in fixture.inputs
    assert fixture.call('read_block', handle, 0, 1) == -2
    assert fixture.call('close_pool') == 0
finally:
    fixture.close()

print(json.dumps({'success': True, 'module_sha256': hashlib.sha256(module).hexdigest(),
    'cases': ['original_wasmtime_bounded_block_transport'],
    'scope': 'raw_external_ABI_only_not_funded_Host_Run_or_physical_ACK'}))
