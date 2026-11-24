"""One installed Saved Result with separate Core and File suspension controls."""
from __future__ import annotations

import asyncio
from collections.abc import Mapping
from hashlib import sha256
import json
import os
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
        self.scans = self.points = self.cancel_scans = self.cancel_rows = 0
        self.cancel_scan_body_bytes = 0

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
                if status == 0 and arguments['namespace'] == 'client_cancellations':
                    self.cancel_rows += 1
                    # One candidate for the census decoder and witness hash.
                    # Count its actual body length without retaining row data.
                    self.cancel_scan_body_bytes += len(self.original.row[1].payload)

    def __enter__(self):
        assert self.previous is None
        sys.setprofile(self.profile)
        return self

    def __exit__(self, _type, _value, _traceback):
        sys.setprofile(self.previous)


async def observe_read(host, result, stop_phase=None, *, totals=None):
    reader = result.rows()

    async def consume():
        async with reader:
            return [row async for row in reader]

    core, store = host._core, host._core._store
    scope = carrier = source = None
    stopped_advance = None
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
                if totals is not None:
                    beat['cancel_rows'] = queries.cancel_rows
                    beat['cancel_scan_body_bytes'] = queries.cancel_scan_body_bytes
                if physical is not None and physical.eof:
                    beat['physical_sha256'] = physical.hash.hexdigest()
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
                    stopped_advance = reader._advance
                    assert stopped_advance is not None and not stopped_advance.done()
                    assert stopped_advance.cancelling() == 0
                    await reader.aclose()
                    assert reader._advance is stopped_advance and stopped_advance.done()
                    assert stopped_advance.cancelling() == 1
                    assert type(stopped_advance.exception()) is StopAsyncIteration
                    break
            if totals is not None:
                totals.update(scan_calls=queries.scans, point_calls=queries.points,
                              cancel_scan_calls=queries.cancel_scans, cancel_rows=queries.cancel_rows,
                              cancel_scan_body_bytes=queries.cancel_scan_body_bytes)
    assert sys.getprofile() is None
    assert carrier is not None and scope is not None and beats[0]['phase'] == 'core'
    assert core._host_operation_scope is None
    assert carrier not in host._saved_result_reads
    receipt = plain(await reader.delivery_attempt())
    if stop_phase is not None:
        assert stopped_advance is not None
        assert reading.result() == [] and reader.rows_yielded == 0
        assert receipt == {'kind': 'not_found'}
        return None, receipt, beats, core_turns, reader.attempt_id
    assert receipt['attempt']['attempt_id'] == reader.attempt_id
    return reading.result(), receipt, beats, core_turns, reader.attempt_id


def original_terminal_revision(creator):
    # Successful public RunState need not project control. This dedicated
    # fresh Store contains only the seed Run at this point. Borrow only its
    # storage revision through the current reader, never the row's contents.
    host = creator._local_host
    assert type(host) is InstalledLocalHost
    installation = host._active()
    binding, store = installation.binding, installation._store
    assert store is not None
    revisions = []

    def inspect(reader):
        rows = []

        def observe(row):
            assert row is not None
            key, original = row
            assert type(original.generation) is int and 0 <= original.generation < 2**31
            rows.append((key, original.generation))

        def end(row):
            assert row is None

        reader.scan_after('client_runs', '', observe)
        (key, revision), = rows
        reader.scan_after('client_runs', key, end)
        revisions.append(revision)

    # The scalar comes from the physical Store, outside any guest operation.
    # The subsequent public cancel still checks its own current and authority.
    with binding.fenced() as fences:
        store.inspect_namespaces(fences, inspect=inspect, current=binding._current_observer)
    revision, = revisions
    return revision


async def prepare_original(state_dir, report_wait_failure=None, *,
                           value_size=16512, cancellation_records=None):
    assert not state_dir.exists()
    values = ['x' * value_size]
    expected = [{'s': value} for value in values]
    delivered_wire = b''.join(json.dumps(row, separators=(',', ':')).encode() + b'\n' for row in expected)
    query = "SELECT '" + values[0] + "' AS s"
    async with await AsyncClient.open(state_dir=state_dir) as creator:
        if cancellation_records is not None:
            # History levels have the same number of Runs. Additional records
            # come from public AlreadyTerminal cancellations.
            assert cancellation_records in (0, 1, 10)
            control = await creator.start_source('SELECT 1 AS n', format='sql',
                                                 submission_ref=creator.new_submission())
            state = plain(await control.wait())
            assert state['status'] == 'succeeded'
            cancellations = []
            for _ in range(cancellation_records):
                revision = original_terminal_revision(creator)
                observed = plain(await control.cancel(expected_revision=revision))
                original = observed['cancellation']
                assert observed['kind'] == 'already_satisfied' and original['kind'] == 'already_terminal'
                assert original['ref'] == plain(control.ref)
                assert plain(await control.lookup_cancellation(original['cancelRef'])) == {
                    'kind': 'found', 'cancellation': original}
                assert plain(await control.status()) == state
                assert original['cancelRef'] not in cancellations
                cancellations.append(original['cancelRef'])
        submission = creator.new_submission()
        execution = await creator.start_source(query, format='sql', submission_ref=submission)
        try:
            assert (await execution.wait())['status'] == 'succeeded'
        except Exception as failure:
            if report_wait_failure is not None:
                try:
                    report_wait_failure(failure)
                except BaseException:
                    pass  # Optional evidence cannot replace the original failure.
            raise
        reference = plain(execution.ref)
    return reference, expected, delivered_wire


async def exercise(state_dir, **identity):
    reference, expected, delivered_wire = await prepare_original(state_dir)
    physical_wire = json.dumps(expected, separators=(',', ':')).encode()
    physical_digest = sha256(physical_wire).hexdigest()
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
        delivered_digest = sha256(delivered_wire).hexdigest()
        successful = []
        for _ in range(2):
            observed, receipt, beats, core_turns, attempt = await observe_read(host, result)
            attempts.add(attempt)
            assert observed == expected
            hash_beats = [beat for beat in beats if beat['phase'] == 'hash']
            assert [beat['offset'] for beat in hash_beats] == [16384, len(physical_wire)]
            assert hash_beats[-1]['physical_sha256'] == physical_digest
            assert core_turns >= 2
            assert beats[-1]['scan_calls'] > beats[0]['scan_calls']
            assert beats[-1]['point_calls'] > beats[0]['point_calls']
            assert beats[-1]['cancel_scan_calls'] > beats[0]['cancel_scan_calls'] > 0
            proof = receipt['hostReleaseReceipt']
            assert receipt['kind'] == 'found' and receipt['record']['state'] == 'succeeded'
            assert proof['run_definition_cid'] == reference['runDefinitionCid']
            assert proof['delivered_byte_count'] == len(delivered_wire)
            assert proof['delivered_sha256'] == delivered_digest
            assert plain(await original.status()) == state
            successful.append({'turns': beats, 'core_turns': core_turns})
        assert len(attempts) == 4
    print(json.dumps({**identity, 'core_cancellation': controls['core'],
                      'hash_cancellation': controls['hash'],
                      'successful_reads': successful, 'rows': len(expected), 'bytes': len(delivered_wire),
                      'sha256': delivered_digest, 'physical_bytes': len(physical_wire),
                      'physical_sha256': physical_digest, 'first_close': True}))


async def measure_history(destination, levels, *, chunk_counts=(1, 2)):
    destination.mkdir(mode=0o700)
    for cancellation_records in levels:
        for chunk_count in chunk_counts:
            # The one-row canonical array has ten framing bytes. A single
            # extra byte changes the physical read from one chunk to two.
            state_dir = destination / f'c{cancellation_records}-k{chunk_count}'
            reference, expected, delivered = await prepare_original(
                state_dir, value_size=16373 + chunk_count, cancellation_records=cancellation_records)
            physical = json.dumps(expected, separators=(',', ':')).encode()
            assert len(physical) == 16383 + chunk_count
            async with await AsyncClient.open(state_dir=state_dir) as client:
                execution = await client.attach(reference)
                assert plain(execution.ref) == reference
                host = client._local_host
                assert type(host) is InstalledLocalHost and type(host._core) is LocalCore
                assert host._core._ordinary_host and 'advance_and_read_saved_result' not in vars(host._core)
                totals = {}
                rows, receipt, beats, core_turns, attempt = await observe_read(
                    host, execution.result('answer'), totals=totals)
                assert rows == expected and core_turns >= 2
                assert (totals['cancel_rows'] > 0) == bool(cancellation_records)
                hash_beats = [beat for beat in beats if beat['phase'] == 'hash']
                assert [beat['offset'] for beat in hash_beats] == (
                    [16384] if chunk_count == 1 else [16384, 16385])
                assert hash_beats[-1]['physical_sha256'] == sha256(physical).hexdigest()
                assert receipt['kind'] == 'found' and receipt['record']['state'] == 'succeeded'
                assert receipt['attempt']['attempt_id'] == attempt
                proof = receipt['hostReleaseReceipt']
                assert proof['run_definition_cid'] == reference['runDefinitionCid']
                assert proof['delivered_byte_count'] == len(delivered)
                assert proof['delivered_sha256'] == sha256(delivered).hexdigest()
            print(json.dumps({'cancellation_records': cancellation_records, 'physical_chunks': chunk_count,
                              'core_turns': core_turns, 'beats': beats, 'read_totals': totals,
                              'delivered_bytes': len(delivered), 'physical_bytes': len(physical),
                              'first_close': True}), flush=True)


def installed_identity(source):
    import actql
    from actql_sdk._local_distribution import installed_local_components
    if not Path(actql.__file__).is_relative_to(Path(sys.prefix)):
        raise ValueError('Installed public facade required')
    original = installed_local_components()
    if original.source_sha != source:
        raise ValueError('Foreign installed Saved fixture source')
    return {'source': original.source_sha, 'module': original.module_sha256,
            'image': original.image_sha256, 'pid': os.getpid()}


async def warm_interruption(directory, identity):
    state_dir = directory / 'fresh-public-state' / '.actql'
    state_dir.parent.mkdir()
    reference, _, _ = await prepare_original(state_dir, value_size=1)
    with (directory / 'fresh-original-reference.json').open('x') as receipt:
        json.dump({'stateDir': str(state_dir), 'warmPID': identity['pid'],
                   'reference': reference, 'resultName': 'answer'}, receipt)
    print(json.dumps({**identity, 'phase': 'warm', 'first_close': True}))


async def recover_interrupted(directory, identity):
    original = json.loads((directory / 'fresh-original-reference.json').read_text())
    state_dir = directory / 'fresh-public-state' / '.actql'
    assert original['stateDir'] == str(state_dir) and original['warmPID'] != identity['pid']
    assert state_dir.is_dir() and original['resultName'] == 'answer'
    async with await AsyncClient.open(state_dir=state_dir) as client:
        run = await client.attach(original['reference'])
        assert plain(run.ref) == original['reference']
        assert (await run.status())['status'] == 'succeeded'
        result = run.result('answer')
        async with result.rows() as reader:
            assert [row async for row in reader] == [{'s': 'x'}]
        receipt = plain(await reader.delivery_attempt())
        proof = receipt['hostReleaseReceipt']
        assert receipt['kind'] == 'found' and receipt['record']['state'] == 'succeeded'
        assert receipt['attempt']['attempt_id'] == reader.attempt_id
        assert proof['run_definition_cid'] == original['reference']['runDefinitionCid']
        expected = b'{"s":"x"}\n'
        assert proof['delivered_byte_count'] == len(expected)
        assert proof['delivered_sha256'] == sha256(expected).hexdigest()
    print(json.dumps({**identity, 'phase': 'recover', 'same_saved': True,
                      'replayed': False, 'first_close': True,
                      'bytes': len(expected), 'sha256': sha256(expected).hexdigest()}))


if __name__ == '__main__':
    state_dir = Path(sys.argv[1]).resolve()
    if len(sys.argv) == 3 and sys.argv[2] in ('--measure-history', '--measure-nonempty-history'):
        levels = (1,) if sys.argv[2] == '--measure-nonempty-history' else (0, 1)
        asyncio.run(measure_history(state_dir, levels))
    elif len(sys.argv) == 4 and sys.argv[2] in (
            '--installed-continuation', '--warm-interruption', '--recover-interruption'):
        identity = installed_identity(sys.argv[3])
        if sys.argv[2] == '--installed-continuation':
            asyncio.run(exercise(state_dir, **identity))
        elif sys.argv[2] == '--warm-interruption':
            asyncio.run(warm_interruption(state_dir, identity))
        else:
            asyncio.run(recover_interrupted(state_dir, identity))
    elif len(sys.argv) == 2:
        asyncio.run(exercise(state_dir))
    else:
        raise ValueError('Select one Saved fixture mode and its state')
