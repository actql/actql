"""Actual Python callbacks into the portable Core buffer owner, not a Run test."""
import hashlib
import json
from pathlib import Path
import sys
import wasmtime


class PhysicalFixture:
    def __init__(self, module, nonce, capacity=256, slots=8):
        self.inputs = {}
        self.cleanups = {}
        self.reads = 0
        self.stops = 0
        self.cleanup_ready = False
        self.stop_ready = False
        self.invalid_byte = False
        self.nonce = nonce
        self.engine = wasmtime.Engine()
        self.store = wasmtime.Store(self.engine)
        self.store.set_limits(memory_size=16 * 1024 * 1024, memories=1)
        self.module = wasmtime.Module(self.engine, module)
        self.linker = wasmtime.Linker(self.engine)
        i32 = wasmtime.ValType.i32()
        for name, params, callback in (
            ('input_byte', [i32, i32], self.read),
            ('input_cleanup', [i32], self.cleanup),
            ('reader_stop', [i32, i32], self.stop)):
            self.linker.define_func('actql_host', name,
                wasmtime.FuncType(params, [i32]), callback)
        assert {(item.module, item.name) for item in self.module.imports} == {
            ('actql_host', 'input_byte'), ('actql_host', 'input_cleanup'), ('actql_host', 'reader_stop')}
        self.instance = self.linker.instantiate(self.store, self.module)
        self.exports = self.instance.exports(self.store)
        assert self.call('open', capacity, slots, 1048576) == 0

    def call(self, name, *args):
        return self.exports['actql_buffer_' + name](self.store, self.nonce, *args)

    def read(self, ticket, index):
        self.reads += 1
        return 256 if self.invalid_byte else self.inputs[ticket][index]

    def cleanup(self, ticket):
        self.cleanups[ticket] = self.cleanups.get(ticket, 0) + 1
        if not self.cleanup_ready:
            return 1
        del self.inputs[ticket]
        return 0

    def stop(self, ticket, reader):
        self.stops += 1
        assert ticket in self.inputs and reader > 0
        return 0 if self.stop_ready else 1

    def copy(self, ticket, payload, retained_bytes):
        # The caller supplies its independently measured physical allowance.
        handle = self.call('reserve', ticket, len(payload), retained_bytes)
        assert handle > 0
        self.inputs[ticket] = payload
        assert self.call('fill', handle, 0, len(payload)) == 0
        assert self.call('seal', handle) == 0
        output = bytes(self.call('byte', handle, index) for index in range(len(payload)))
        assert output == payload
        return handle

    def close(self):
        self.store.close()
        self.linker.close()
        self.module.close()
        self.engine.close()


module = Path(sys.argv[1]).read_bytes()
left, right = PhysicalFixture(module, 101), PhysicalFixture(module, 202)
try:
    # Independently authored exact bytes: a decomposed key, escaped pointer
    # characters, a non-BMP value, CRLF, NULL and an absent field.
    payload = '{"e\u0301/~😀":"e\u0301\\r\\n😀","nullable":null,"n":1}'.encode('utf-8')
    physical_bytes = sys.getsizeof(payload)
    handle = left.copy(1, payload, physical_bytes)
    assert json.loads(payload) == {'e\u0301/~😀': 'e\u0301\r\n😀', 'nullable': None, 'n': 1}
    assert left.call('allocated') == 2 * len(payload) + physical_bytes
    assert left.call('reserved') == 256
    assert right.exports['actql_buffer_byte'](right.store, left.nonce, handle, 0) == -1
    assert right.reads == 0
    # Individually valid reservations still exceed one aggregate allowance.
    assert left.call('reserve', 2, len(payload), 128) == -4
    assert left.call('fill', handle, 0, 1) == -5
    reader = left.call('borrow', handle)
    assert reader > handle
    assert left.call('close', reader) == -2, 'Reader handles cannot alias input handles'
    assert left.call('close', handle) == -9
    assert not left.cleanups
    assert left.call('return', reader) == -9
    assert left.call('allocated') == 2 * len(payload) + physical_bytes
    left.stop_ready = True
    assert left.call('return', reader) == 0
    assert left.call('close', handle) == -9
    assert left.call('allocated') == 2 * len(payload) + physical_bytes
    left.cleanup_ready = True
    assert left.call('close', handle) == 0
    assert left.cleanups[1] == 2
    assert left.call('byte', handle, 0) == -2
    assert left.call('allocated') == 0
    next_handle = left.copy(2, b'null', 4)
    assert next_handle > reader
    assert left.call('close_pool') == 0
    assert left.call('close_pool') == 0
    assert left.call('reserved') == 0
    assert left.call('reserve', 3, 4, 4) == -5
    right.inputs[1] = b'null'
    bad = right.call('reserve', 1, 4, 4)
    right.invalid_byte = True
    assert right.call('fill', bad, 0, 4) == -12
    assert right.call('seal', bad) == -7
    assert right.call('byte', bad, 0) == -5
    right.invalid_byte = False
    assert right.call('fill', bad, 0, 4) == 0
    assert right.call('seal', bad) == 0
    right.cleanup_ready = True
    assert right.call('close_pool') == 0
    assert right.call('reserved') == 0
finally:
    left.close()
    right.close()

print(json.dumps({'success': True, 'module_sha256': hashlib.sha256(module).hexdigest(),
    'cases': ['exact_values', 'instance_identity', 'aggregate_capacity',
              'borrow_retirement', 'cleanup_retry', 'stale_handles', 'invalid_byte', 'pool_close']}))
