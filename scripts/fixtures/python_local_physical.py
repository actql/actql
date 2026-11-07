"""Physical callbacks shared by the focused real-Wasm acceptance cases."""
from pathlib import Path
import sys
import wasmtime

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'packages/python-sdk/src'))
from actql_sdk._local_core import LOCAL_CORE_ABI, _validate_core_module
from actql_sdk._local_wasm_abi import _IMPORT_SIGNATURES


class PhysicalFixture:
    def __init__(self, module, nonce, capacity=256, slots=8, fuel=None,
                 execution_bytes=None, retained_bytes=200_000_000):
        self.inputs = {}
        self.cleanups = {}
        self.reads = 0
        self.stops = 0
        self.cleanup_ready = False
        self.stop_ready = False
        self.invalid_byte = False
        self.nonce = nonce
        self.store = self.linker = self.module = self.engine = None
        try:
            config = wasmtime.Config()
            if fuel is not None:
                config.consume_fuel = True
            self.engine = wasmtime.Engine(config)
            self.store = wasmtime.Store(self.engine)
            if fuel is not None:
                self.store.set_fuel(fuel)
            self.store.set_limits(memory_size=16 * 1024 * 1024, memories=1)
            self.module = wasmtime.Module(self.engine, module)
            # These are current-source probes. Historical artifacts must never
            # reach physical callbacks under the current wrapper declaration.
            _validate_core_module(wasmtime, self.module)
            self.linker = wasmtime.Linker(self.engine)
            i32 = wasmtime.ValType.i32()
            for name, params, callback in (
                ('input_byte', [i32, i32], self.read),
                ('input_cleanup', [i32], self.cleanup),
                ('reader_stop', [i32, i32], self.stop),
                ('native_settled', [i32], self.native_settled),
                ('native_stopped', [i32], self.native_stopped),
                ('native_cleaned', [i32], self.native_cleaned),
                ('publisher_current', [i32], self.publisher_current),
                ('publisher_begin', [i32, i32], self.publisher_begin),
                ('publisher_byte', [i32, i32, i32], self.publisher_byte),
                ('publisher_finish', [i32], self.publisher_finish),
                ('journal_current', [i32], self.journal_refuse),
                ('journal_current_operation', [i32], self.journal_refuse),
                ('journal_schema', [i32], self.journal_refuse)):

                self.linker.define_func('actql_host', name,
                    wasmtime.FuncType(params, [wasmtime.ValType.i64() if _IMPORT_SIGNATURES.get(name, ('', 'i32'))[1] == 'i64' else i32]), callback)
            for name in ('input_copy', 'publisher_copy', 'journal_query_header', 'journal_copy_row'):
                params, result = _IMPORT_SIGNATURES[name]
                self.linker.define_func('actql_host', name, wasmtime.FuncType(
                    [i32 for _ in params.split()], [i32]),
                    getattr(self, name), access_caller=True)
            for name, (params, result) in _IMPORT_SIGNATURES.items():
                if not name.startswith('execution_child_'):
                    continue
                scalar = {'i32': wasmtime.ValType.i32, 'i64': wasmtime.ValType.i64}
                # Raw diagnostic pools do not own an installed execution child.
                # Linking a declared import is not permission to acquire one.
                self.linker.define_func('actql_host', name, wasmtime.FuncType(
                    [scalar[p]() for p in params.split()], [scalar[result]()]),
                    self.execution_child_unavailable)
            self.linker.define_func('actql_host', 'platform_vm_observation',
                wasmtime.FuncType([wasmtime.ValType.i64(), i32], [wasmtime.ValType.i64()]),
                self.platform_vm_observation, access_caller=True)
            self.instance = self.linker.instantiate(self.store, self.module)
            self.exports = self.instance.exports(self.store)
            if self.exports['actql_host_abi_version'](self.store) != LOCAL_CORE_ABI:
                raise ValueError('Unsupported Local Core fixture ABI version')
            envelope = 16 * 1024 * 1024 + capacity if execution_bytes is None else execution_bytes
            assert self.call('open', capacity, slots, 1048576, 100000, slots + 2, slots,
                                  32000000, retained_bytes, envelope, 0) == 0
        except BaseException:
            self.close()
            raise

    def call(self, name, *args):
        return self.exports['actql_buffer_' + name](self.store, self.nonce, *args)

    def execution_child_unavailable(self, *args):
        return -42

    def platform_vm_observation(self, caller, nonce, ordinal):
        # Raw diagnostic fixtures never promote scalar limits to this original.
        return -42

    def read(self, ticket, index):
        self.reads += 1
        return 256 if self.invalid_byte else self.inputs[ticket][index]

    def unexpected_native(self, handle):
        raise AssertionError('This non-Native fixture cannot acknowledge Source physical facts')

    def native_settled(self, handle):
        return self.unexpected_native(handle)

    def native_stopped(self, handle):
        return self.unexpected_native(handle)

    def native_cleaned(self, handle):
        return self.unexpected_native(handle)

    # Old non-publication fixtures have no trusted publisher Owner. These
    # callbacks refuse explicitly; Source/Run permissions are never reused.
    def publisher_current(self, ticket):
        return -2

    def publisher_begin(self, ticket, length):
        return -2

    def publisher_byte(self, ticket, index, byte):
        return -2

    def publisher_finish(self, ticket):
        return -2

    def input_copy(self, *args):
        # The separately selected scalar fixture does not acquire a bulk port.
        return -5

    def publisher_copy(self, *args):
        return -2

    def journal_query_header(self, *args):
        return -41

    def journal_copy_row(self, *args):
        return -41

    def journal_refuse(self, *args):
        # Existing unrelated physical fixtures have no original journal port.
        return -41

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
        for start in range(0, len(payload), 16_384):
            assert self.call('fill', handle, start, min(16_384, len(payload) - start)) == 0
        assert self.call('seal', handle) == 0
        output = bytes(self.call('byte', handle, index) for index in range(len(payload)))
        assert output == payload
        return handle

    def close(self):
        for name in ('store', 'linker', 'module', 'engine'):
            value = getattr(self, name, None)
            if value is not None:
                value.close()
                setattr(self, name, None)

