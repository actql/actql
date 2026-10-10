"""Physical callbacks shared by the focused real-Wasm acceptance cases."""
import wasmtime


class PhysicalFixture:
    def __init__(self, module, nonce, capacity=256, slots=8, fuel=None):
        self.inputs = {}
        self.cleanups = {}
        self.reads = 0
        self.stops = 0
        self.cleanup_ready = False
        self.stop_ready = False
        self.invalid_byte = False
        self.nonce = nonce
        config = wasmtime.Config()
        if fuel is not None:
            config.consume_fuel = True
        self.engine = wasmtime.Engine(config)
        self.store = wasmtime.Store(self.engine)
        if fuel is not None:
            self.store.set_fuel(fuel)
        self.store.set_limits(memory_size=16 * 1024 * 1024, memories=1)
        self.module = wasmtime.Module(self.engine, module)
        self.linker = wasmtime.Linker(self.engine)
        i32 = wasmtime.ValType.i32()
        for name, params, callback in (
            ('input_byte', [i32, i32], self.read),
            ('input_cleanup', [i32], self.cleanup),
            ('reader_stop', [i32, i32], self.stop),
            ('native_settled', [i32], self.unexpected_native),
            ('native_stopped', [i32], self.unexpected_native),
            ('native_cleaned', [i32], self.unexpected_native)):
            self.linker.define_func('actql_host', name,
                wasmtime.FuncType(params, [i32]), callback)
        assert {(item.module, item.name) for item in self.module.imports} == {
            ('actql_host', 'input_byte'), ('actql_host', 'input_cleanup'), ('actql_host', 'reader_stop'),
            ('actql_host', 'native_settled'), ('actql_host', 'native_stopped'), ('actql_host', 'native_cleaned')}
        self.instance = self.linker.instantiate(self.store, self.module)
        self.exports = self.instance.exports(self.store)
        assert self.call('open', capacity, slots, 1048576, 100000, slots + 2, slots,
                              32000000, 200000000, 16 * 1024 * 1024 + capacity) == 0

    def call(self, name, *args):
        return self.exports['actql_buffer_' + name](self.store, self.nonce, *args)

    def read(self, ticket, index):
        self.reads += 1
        return 256 if self.invalid_byte else self.inputs[ticket][index]

    def unexpected_native(self, handle):
        raise AssertionError('This non-Native fixture cannot acknowledge Source physical facts')

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

