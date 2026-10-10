"""Consume the packaged actual Wasm; no Node or CLI execution."""
import asyncio
import json
from actql_local_probe import Probe

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
    print(json.dumps({'success': True, 'transfers': 20, 'pages': pages, 'artifact': probe.identity}))

asyncio.run(main())
