"""One installed Saved Result with separate Core and File suspension controls."""
from __future__ import annotations

import asyncio
from collections.abc import Mapping
from hashlib import sha256
import json
import sys
from pathlib import Path

from actql import AsyncClient
from actql_sdk._local_core import LocalCore
from actql_sdk._local_journal_port import _JournalCallbacks
from actql_sdk._local_product import InstalledLocalHost


def plain(value):
    if isinstance(value, Mapping):
        return {key: plain(child) for key, child in value.items()}
    if isinstance(value, (tuple, list)):
        return [plain(child) for child in value]
    return value


class PhysicalQueries:
    """Count calls to the installed Core's actual journal scan and point ports."""

    def __init__(self, host):
        binding = host._installation.binding
        self.original = host._core._journal_callbacks(binding._current.ticket)
        assert type(self.original) is _JournalCallbacks
        self.previous = sys.getprofile()
        self.query = _JournalCallbacks.query.__code__
        self.scans = self.points = self.cancel_scans = 0

    def profile(self, frame, event, status):
        if event != 'return' or frame.f_code is not self.query or status not in (0, 1):
            return
        arguments = frame.f_locals
        if arguments.get('self') is self.original:
            mode = self.original.mode
            self.scans += mode == 0
            self.points += mode == 1
            if mode == 0 and arguments.get('namespace') in (
                    'client_cancel_custody', 'client_cancellations', 'client_cancel_originals'):
                self.cancel_scans += 1

    def __enter__(self):
        assert self.previous is None
        sys.setprofile(self.profile)
        return self

    def __exit__(self, _type, _value, _traceback):
        sys.setprofile(self.previous)


async def observe_read(host, result, stop_phase=None):
    reader = result.rows()

    async def consume():
        async with reader:
            return [row async for row in reader]

    core, store = host._core, host._core._store
    scope = carrier = source = None
    beats = []
    core_turns = 0
    async with asyncio.TaskGroup() as tasks:
        reading = tasks.create_task(consume())
        with PhysicalQueries(host) as queries:
            while not reading.done():
                await asyncio.sleep(0)
                preparing = [value for value in host._saved_result_reads if value._preparing]
                assert len(preparing) <= 1
                if not preparing or preparing[0]._source is None:
                    continue
                current, = preparing
                assert core._host_fuel_phase == 'operation' and core._host_operation_scope is not None
                assert core._store is store and not core._invoking and not core._lock._is_owned()
                installation = host._installation
                assert not installation._store._connection.in_transaction
                assert installation.binding._observed_reader is None
                if scope is None:
                    scope, carrier, source = core._host_operation_scope, current, current._source
                assert current is carrier and core._host_operation_scope is scope
                assert current._source is source and reader.rows_yielded == 0
                physical = current._reader
                phase = 'core' if physical is None else 'hash'
                if physical is not None:
                    assert physical.chunk is None and physical.offset > 0
                beat = {'phase': phase, 'offset': 0 if physical is None else physical.offset,
                        'fuel_remaining': store.get_fuel(), 'scan_calls': queries.scans,
                        'point_calls': queries.points, 'cancel_scan_calls': queries.cancel_scans}
                if not beats or beats[-1] != beat:
                    if beats:
                        assert beat['fuel_remaining'] <= beats[-1]['fuel_remaining']
                    if phase == 'core':
                        core_turns += 1
                    if len(beats) < 32 or phase == 'hash':
                        beats.append(beat)
                    else:
                        beats[-1] = beat
                if phase == stop_phase:
                    if physical is not None:
                        assert not physical.eof
                    await reader.aclose()
                    break
    assert sys.getprofile() is None
    assert carrier is not None and scope is not None and beats[0]['phase'] == 'core'
    assert core._host_operation_scope is None
    assert carrier not in host._saved_result_reads
    receipt = plain(await reader.delivery_attempt())
    if stop_phase is not None:
        assert reading.cancelled() and reader.rows_yielded == 0
        assert receipt == {'kind': 'not_found'}
        return None, receipt, beats, core_turns, reader.attempt_id
    assert receipt['attempt']['attempt_id'] == reader.attempt_id
    return reading.result(), receipt, beats, core_turns, reader.attempt_id


async def exercise(state_dir):
    assert not state_dir.exists()
    values = [f'{ordinal:03}-' + 'x' * 236 for ordinal in range(96)]
    expected = [{'s': value} for value in values]
    wire = b''.join(json.dumps(row, separators=(',', ':')).encode() + b'\n' for row in expected)
    query = "SELECT s FROM UNNEST([" + ','.join("'" + value + "'" for value in values) + "]) AS s ORDER BY s"
    async with await AsyncClient.open(state_dir=state_dir) as creator:
        submission = creator.new_submission()
        execution = await creator.start_source(query, format='sql', submission_ref=submission)
        assert (await execution.wait())['status'] == 'succeeded'
        reference = plain(execution.ref)
    async with await AsyncClient.open(state_dir=state_dir) as client:
        original = await client.attach(reference)
        assert plain(original.ref) == reference
        state = plain(await original.status())
        result = original.result('answer')
        host = client._local_host
        assert type(host) is InstalledLocalHost and type(host._core) is LocalCore
        assert host._core._ordinary_host and 'advance_and_read_saved_result' not in vars(host._core)
        controls, attempts = {}, set()
        for phase in ('core', 'hash'):
            _, _, controls[phase], _, attempt = await observe_read(host, result, phase)
            attempts.add(attempt)
            assert plain(await original.status()) == state
        digest = sha256(wire).hexdigest()
        successful = []
        for _ in range(2):
            observed, receipt, beats, core_turns, attempt = await observe_read(host, result)
            attempts.add(attempt)
            assert observed == expected
            assert [beat['offset'] for beat in beats if beat['phase'] == 'hash'] == [16384, len(wire)]
            assert core_turns >= 2
            assert beats[-1]['scan_calls'] > beats[0]['scan_calls']
            assert beats[-1]['point_calls'] > beats[0]['point_calls']
            assert beats[-1]['cancel_scan_calls'] > beats[0]['cancel_scan_calls'] > 0
            proof = receipt['hostReleaseReceipt']
            assert receipt['kind'] == 'found' and receipt['record']['state'] == 'succeeded'
            assert proof['run_definition_cid'] == reference['runDefinitionCid']
            assert proof['delivered_byte_count'] == len(wire) and proof['delivered_sha256'] == digest
            assert plain(await original.status()) == state
            successful.append({'turns': beats, 'core_turns': core_turns})
        assert len(attempts) == 4
    print(json.dumps({'core_cancellation': controls['core'], 'hash_cancellation': controls['hash'],
                      'successful_reads': successful, 'rows': len(expected), 'bytes': len(wire),
                      'sha256': digest, 'first_close': True}))


if __name__ == '__main__':
    asyncio.run(exercise(Path(sys.argv[1])))
