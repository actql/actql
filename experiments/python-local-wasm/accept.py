"""Consume the packaged actual Wasm; no Node or CLI execution."""
import asyncio
import json
import threading
import duckdb
from actql_local_probe import Probe

async def interrupt_native():
    connection = duckdb.connect(':memory:', config={'threads': 1, 'memory_limit': '16MB'})
    entered = threading.Event()
    def query():
        entered.set()
        return connection.execute('SELECT sum(i * j) FROM range(10000000) a(i), range(1000) b(j)').fetchone()
    worker = asyncio.create_task(asyncio.to_thread(query))
    try:
        assert await asyncio.to_thread(entered.wait, 2), 'Native worker did not enter'
        await asyncio.sleep(.05)
        assert not worker.done(), 'Native operation completed before interruption'
        connection.interrupt()
        try:
            await asyncio.wait_for(asyncio.shield(worker), 5)
        except duckdb.InterruptException:
            pass
        else:
            raise AssertionError('Native interrupt was not observed')
        assert worker.done(), 'A cancelled Python waiter is not physical thread stop'
    finally:
        if not worker.done():
            connection.interrupt()
            try:
                await asyncio.wait_for(asyncio.shield(worker), 5)
            except duckdb.InterruptException:
                pass
        if worker.done():
            connection.close()
    return {'interrupted': True, 'physical_thread_stopped': True, 'connection_closed': True}

async def main():
    probe = Probe()
    pages = []
    try:
        expected = {'e\u0301/~😀': 'e\u0301\r\n😀', 'nullable': None, 'n': 1}
        for ticket in range(20):
            assert probe.request(ticket) == 1
            await asyncio.sleep(0)
            assert ticket not in probe.inputs, 'Callback must remain asynchronously pending'
            assert await probe.transfer(ticket) == expected
            assert not probe.inputs and not probe.outputs and not probe.tasks
            pages.append(probe.pages())
        assert probe.request(100) == 1
        await asyncio.sleep(0)
        assert not probe.tasks[100].done()
        # Request + physical stop alone never establishes terminal eligibility.
        assert probe.eligible(1 | 128 | 512) == 0
        await probe.release(100)
        assert not probe.tasks and not probe.inputs and not probe.outputs
        native = await interrupt_native()
        complete = 1 | 2 | 4 | 128 | 256 | 512
        assert probe.eligible(complete) == 1
        for missing in (1, 4, 128, 256, 512):
            assert probe.eligible(complete & ~missing) == 0
        for unresolved in (8, 16, 32, 64):
            assert probe.eligible(complete | unresolved) == 0
        assert pages[-1] == pages[0], 'Repeated copied transfers must not grow memory pages'
    finally:
        await probe.aclose()
        await probe.aclose()
    try:
        probe.request(101)
    except ValueError as error:
        assert str(error) == 'ProbeClosed'
    else:
        raise AssertionError('Closed probe accepted a callback')
    print(json.dumps({'success': True, 'transfers': 20, 'native_stop': native, 'pages': pages, 'artifact': probe.identity}))

asyncio.run(main())
