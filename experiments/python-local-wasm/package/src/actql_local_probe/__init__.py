"""Experimental callback bridge; not an embedded ActQL Client or Run service."""
import asyncio
import hashlib
from importlib.resources import files
import json
import wasmtime
import duckdb


class Probe:
    def __init__(self):
        source = files(__package__)
        wasm = source.joinpath('core.wasm').read_bytes()
        identity = json.loads(source.joinpath('artifact.json').read_text())
        if hashlib.sha256(wasm).hexdigest() != identity['wasm_sha256']:
            raise ValueError('ProbeArtifactDigestMismatch')
        self.identity = identity
        self.inputs, self.outputs, self.tasks = {}, {}, {}
        self.gates = {}
        self.engine = wasmtime.Engine()
        self.store = wasmtime.Store(self.engine)
        self.store.set_limits(memory_size=16 * 1024 * 1024, memories=1)
        self.linker = wasmtime.Linker(self.engine)
        i32 = wasmtime.ValType.i32()
        for name, params, results, callback in (
            ('request_input', [i32], [i32], self._request),
            ('input_byte', [i32, i32], [i32], self._byte),
            ('output_byte', [i32, i32], [], self._output)):
            self.linker.define_func('python_probe', name, wasmtime.FuncType(params, results), callback)
        self.module = wasmtime.Module(self.engine, wasm)
        actual = {(value.module, value.name) for value in self.module.imports}
        expected = {('python_probe', name) for name in ('request_input', 'input_byte', 'output_byte')}
        if actual != expected:
            raise ValueError('UnexpectedProbeImports')
        self.instance = self.linker.instantiate(self.store, self.module)
        self.exports = self.instance.exports(self.store)
        self.closed = False

    def _request(self, ticket):
        if ticket in self.tasks or ticket in self.inputs:
            raise ValueError('DuplicateProbeTicket')
        self.gates[ticket] = asyncio.Event()
        self.tasks[ticket] = asyncio.create_task(self._produce(ticket))
        return 1

    async def _produce(self, ticket):
        await self.gates[ticket].wait()
        # This native binding owns its connection; only exact JSON bytes cross
        # into Wasm. It is a transfer experiment, not a replacement Scheduler.
        with duckdb.connect(':memory:') as connection:
            result = connection.execute('SELECT ? AS value, NULL AS nullable, 1 AS n', ['e\u0301\r\n😀']).fetchone()
        wire = json.dumps({'e\u0301/~😀': result[0], 'nullable': result[1], 'n': result[2]}, ensure_ascii=False).encode()
        if len(wire) > 16384:
            raise ValueError('ProbeInputLimit')
        self.inputs[ticket] = wire

    def _byte(self, ticket, index):
        return self.inputs[ticket][index]

    def _output(self, ticket, value):
        output = self.outputs.setdefault(ticket, bytearray())
        if len(output) >= 16384 or not 0 <= value <= 255:
            raise ValueError('ProbeOutputLimit')
        output.append(value)

    def request(self, ticket):
        if self.closed:
            raise ValueError('ProbeClosed')
        return self.exports['probe_request'](self.store, ticket)

    async def transfer(self, ticket):
        self.gates[ticket].set()
        await self.tasks[ticket]
        length = len(self.inputs[ticket])
        output_length = self.exports['probe_transfer'](self.store, ticket, length)
        output = bytes(self.outputs.get(ticket, b''))
        if output_length != len(output) or output_length < 0:
            raise ValueError('ProbeTransferRejected')
        # No Wasm view or pointer escapes; the Python result owns a copy.
        await self.release(ticket)
        return json.loads(output)

    async def release(self, ticket):
        task = self.tasks.get(ticket)
        if task is not None:
            if not task.done():
                task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
            del self.tasks[ticket]
        self.gates.pop(ticket, None)
        self.inputs.pop(ticket, None)
        self.outputs.pop(ticket, None)

    def eligible(self, facts):
        return self.exports['probe_cancel_eligible'](self.store, facts)

    def pages(self):
        return self.exports['memory'].size(self.store)

    async def aclose(self):
        if self.closed:
            return
        for ticket in list(self.tasks):
            await self.release(ticket)
        self.closed = True
        self.store.close()
        self.linker.close()
        self.module.close()
        self.engine.close()
