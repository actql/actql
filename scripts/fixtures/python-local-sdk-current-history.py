"""Finite actual Core/SQLite managed-continuation read counters.

Raw same-source Wasm and explicit fixture authority; not an installed package,
latency benchmark, normal Host qualification or physical-stop proof. Only the
existing task selection/drive and physical Journal import are observed.
"""
import asyncio
from collections import Counter
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import sys
from tempfile import mkdtemp
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk import AsyncClient
from actql_sdk._local_core import LocalCore, LocalCoreError, _NORMAL_HOST_OPERATION_FUEL
from actql_sdk._local_product import InstalledLocalHost, _ordinary_core_limits
from actql_sdk._local_journal_port import _JournalCallbacks
from actql_sdk._local_storage import StoredBytes
from actql_sdk._values import thaw, wire_bytes
from actql_sdk import _wire

# Missing a Run referenced by an existing submitted row is the saved reader's
# custody refusal; it is not the separate missing-submission (-35) branch.
FAULTS = {'missing': -31, 'revision': -35, 'cancel': -35,
          'foreign': -31, 'intent': -31, 'current': -41, 'reentry': -41}


@dataclass(frozen=True)
class Row:
    n: int

    @classmethod
    def model_validate(cls, value, *, strict):
        if strict is not True or type(value) is not dict or set(value) != {'n'} or type(value['n']) is not int:
            raise ValueError('Expected the independently authored integer row')
        return cls(value['n'])


class Trace:
    def __init__(self):
        self.enabled = False
        self.active = None
        self.target = None
        self.target_body = None
        self.target_revision = None
        self.steps = []
        self.refusal = None

    def call(self, phase, invoke):
        if not self.enabled:
            return invoke()
        assert self.active is None and self.target is not None
        counts = Counter()
        self.active = counts
        try:
            result = invoke()
        except LocalCoreError as error:
            self.refusal = error
            raise
        finally:
            self.active = None
            observed = {'phase': phase, 'counts': dict(sorted(counts.items()))}
            self.steps.append(observed)
            print(json.dumps({'continuationObservation': observed}), flush=True)
        assert counts.get('historyScans', 0) == 0, observed
        assert counts.get('unrelatedRunRows', 0) == 0, observed
        assert counts.get('unrelatedTaskRows', 0) == 0, observed
        assert counts.get('unrelatedEffectRows', 0) == 0, observed
        assert counts.get('changedTargetRows', 0) == 0, observed
        return result


async def population(raw, digest, scratch, history, fault=None, persisted=False, pending=False):
    assert not (persisted and pending)
    trace = Trace()
    original_header = LocalCore._journal_query_header
    original_current = LocalCore._journal_current
    original_operation = LocalCore._journal_current_operation
    original_query = _JournalCallbacks.query
    fault_used = False
    injected_primary = RuntimeError('Original component current/reentry failure')
    failed_callbacks = None

    def queried(callbacks):
        nonlocal fault_used, failed_callbacks
        namespace = bytes(callbacks.request[:callbacks.namespace_length]).decode('utf-8')
        code = original_query(callbacks)
        selected = 'client_submitted_intents' if fault == 'intent' else 'client_runs'
        if (trace.active is None or fault is None or fault_used or namespace != selected
                or code != 0):
            return code
        fault_used = True
        key, row = callbacks.row
        # Corrupt only the complete DATA returned by this real SQLite query,
        # before the unchanged original physical transfer/current checks.
        # This does not write a durable row or supply acceptance authority.
        if fault == 'missing':
            callbacks.row = None
            return 1
        if fault == 'revision':
            callbacks.row = (key, StoredBytes(row.generation + 1, row.payload))
        elif fault == 'cancel':
            before = b'"cancellation_requested":false'
            assert row.payload.count(before) == 1
            callbacks.row = (key, StoredBytes(row.generation,
                row.payload.replace(before, b'"cancellation_requested":true')))
        elif fault == 'foreign':
            callbacks.row = (b'foreign-original-run', row)
        elif fault == 'intent':
            before = b'SELECT 1 AS n'
            assert row.payload.count(before) == 1
            callbacks.row = (key, StoredBytes(row.generation,
                row.payload.replace(before, b'SELECT 2 AS n')))
        elif fault == 'reentry':
            try:
                core._call('workspace', 'root_reserved')
            except RuntimeError as error:
                failed_callbacks = callbacks
                assert callbacks._fail(error) == -41
                assert callbacks.failure is error
                return -41
            raise AssertionError('The original Core allowed reentry')
        return code

    def query(core, caller, ticket, mode, namespace_offset, namespace_bytes,
              key_offset, key_bytes, header_offset):
        counts = trace.active
        namespace = None
        if counts is not None:
            memory = core._bulk_memory(caller, namespace_offset, namespace_bytes)
            namespace = bytes(memory.read(caller, namespace_offset, namespace_offset + namespace_bytes)).decode('utf-8')
        code = original_header(core, caller, ticket, mode, namespace_offset, namespace_bytes,
                               key_offset, key_bytes, header_offset)
        if counts is not None:
            counts['queries'] += 1
            counts['scanQueries' if mode == 0 else 'pointQueries'] += 1
            if mode == 0:
                counts['scan:' + namespace] += 1
                # Host/Account/settings current inventories stay mandatory.
                # Only the unrelated Run/task/Effect/cancellation census is
                # outside this already admitted live continuation's scope.
                if namespace.startswith(('client_run', 'client_task', 'client_effect',
                                         'client_cancel', 'client_submitted')):
                    counts['historyScans'] += 1
            if code == 0:
                counts['returnedRows'] += 1
                row = core._journal_callbacks(ticket).row
                if namespace == 'client_runs':
                    counts['returnedRunRows'] += 1
                    if row[0] != trace.target.encode('utf-8'):
                        counts['unrelatedRunRows'] += 1
                    elif row[1].payload != trace.target_body or row[1].generation != trace.target_revision:
                        counts['changedTargetRows'] += 1
                elif namespace.startswith('client_task'):
                    counts['returnedTaskRows'] += 1
                    # The existing material writer keys chunks by this exact
                    # original Run scope. No other task namespace is inferred.
                    prefix = trace.target.encode('utf-8') + b':'
                    if namespace != 'client_task_run_materials' or not row[0].startswith(prefix):
                        counts['unrelatedTaskRows'] += 1
                elif namespace.startswith('client_effect'):
                    # This authored Values/JOIN target has no Effect members.
                    counts['returnedEffectRows'] += 1
                    counts['unrelatedEffectRows'] += 1
            elif code == 1:
                counts['misses'] += 1
        return code

    def current(core, ticket):
        if trace.active is not None:
            trace.active['physicalCurrentCalls'] += 1
        return original_current(core, ticket)

    def operation(core, ticket):
        nonlocal fault_used, failed_callbacks
        if trace.active is not None:
            trace.active['physicalOperationCalls'] += 1
            if fault == 'current' and not fault_used:
                fault_used = True
                failed_callbacks = core._journal_callbacks(ticket)
                return failed_callbacks._fail(injected_primary)
        return original_operation(core, ticket)

    state = Path(mkdtemp(prefix=f'history-{history}-', dir=scratch))
    client = host = core = None
    primary = None
    completed_history = 0
    accepted_pending_history = 0
    closed_pending_history = 0
    pending_references = set()
    cleanup = []
    try:
        with patch.object(LocalCore, '_journal_query_header', query), \
                patch.object(LocalCore, '_journal_current', current), \
                patch.object(LocalCore, '_journal_current_operation', operation), \
                patch.object(_JournalCallbacks, 'query', queried):
            core = LocalCore(raw, digest=digest, transfer_capacity=12 * 1024 * 1024,
                slots=128, resources=_ordinary_core_limits(), fuel=_NORMAL_HOST_OPERATION_FUEL)
            host = InstalledLocalHost(core, state, now=lambda: 1_800_000_000_000,
                observed_at='2026-11-18T00:00:00.000Z', sdk_finite=True)
            client = await AsyncClient._connect_local(host)
            for index in range(history):
                if pending:
                    # Stop at the original accepting owner, before its outer
                    # submit consumer constructs or starts physical work.
                    name = f'history-{history}-{index}'
                    reference = thaw(client.new_submission(nonce=name))
                    intent = wire_bytes({'kind': 'aql', 'input': {
                        'text': 'WITH seed AS (SELECT 41 AS n) FROM seed |> SELECT n |> RESULT answer',
                        'format': 'aql'}, 'parameters': None})
                    run, admission = host._accept_original(reference, intent, run_id=name)
                    saved = json.loads(admission)
                    assert run is not None and _wire.negotiated(saved, 'admission', thaw(client._selected))
                    assert saved['ref']['authorityScopeCid'] == reference['epoch']['authorityScopeCid']
                    key = wire_bytes(saved['ref'])
                    assert key not in pending_references
                    pending_references.add(key)
                    assert not host._physical_work and not host._physical_starts
                    assert not host._source_free_computes and not host._tasks
                    accepted_pending_history += 1
                    print(json.dumps({'acceptedPendingHistory': accepted_pending_history}), flush=True)
                else:
                    original = await client.start_source(
                        'WITH seed AS (SELECT 41 AS n) FROM seed |> SELECT n |> RESULT answer', format='aql')
                    assert (await original.wait(until='terminal')).to_dict()['status'] == 'succeeded'
                    assert await original.result('answer').all(schema=Row, max_rows=2) == [Row(41)]
                    completed_history += 1
                    print(json.dumps({'completedHistory': completed_history}), flush=True)
                if persisted or pending:
                    # Original child-first close only. Pending mode has an
                    # acknowledged admission, not a successfully executed Run.
                    # Keep this fresh case's durable originals in place.
                    await client.aclose()
                    await host.aclose()
                    assert core.close() is True
                    if pending:
                        closed_pending_history += 1
                        print(json.dumps({'closedPendingHistory': closed_pending_history}), flush=True)
                    core = LocalCore(raw, digest=digest, transfer_capacity=12 * 1024 * 1024,
                        slots=128, resources=_ordinary_core_limits(), fuel=_NORMAL_HOST_OPERATION_FUEL)
                    host = InstalledLocalHost(core, state, now=lambda: 1_800_000_000_000,
                        observed_at='2026-11-18T00:00:00.000Z', sdk_finite=True)
                    client = await AsyncClient._connect_local(host)

            if pending:
                assert accepted_pending_history == closed_pending_history == len(pending_references) == history

            read_start = core.read_sdk_start_step
            select_task = core.reserve_next_sdk_task
            drive_task = core.drive_task

            def original_claim(*args, **kwargs):
                wire = read_start(*args, **kwargs)
                record = json.loads(wire)
                if record['kind'] == 'claim':
                    assert trace.target is None or trace.target == record['key']
                    trace.target = record['key']  # Labelling only, never claim acceptance.
                    # Correlate returned bytes with this original claim DATA;
                    # unchanged Core validators still decide current/authority.
                    trace.target_body = record['body'].encode('utf-8')
                    trace.target_revision = int(record['revision']) + 1
                return wire

            def select(*args, **kwargs):
                return trace.call('select', lambda: select_task(*args, **kwargs))

            def drive(task, quantum):
                assert quantum > 0
                # A fixed test input exercises multiple real bounded quanta.
                # It does not change a result, retry a failure or classify state.
                return trace.call('drive', lambda: drive_task(task, 1))

            with patch.object(core, 'read_sdk_start_step', original_claim), \
                    patch.object(core, 'reserve_next_sdk_task', select), \
                    patch.object(core, 'drive_task', drive):
                trace.enabled = True
                execution = await client.start_source(
                    'WITH seed AS (SELECT 1 AS n) FROM seed AS l |> JOIN seed AS r ON l.n = r.n '
                    'MAX_OUTPUT_ROWS 1 |> SELECT l.n + r.n AS n |> RESULT answer', format='aql')
                final = (await execution.wait(until='terminal')).to_dict()
                assert final['status'] == 'succeeded' and final['result_available']
                assert await execution.result('answer').all(schema=Row, max_rows=2) == [Row(2)]
                assert (await execution.status()).to_dict() == final
            assert fault is None, 'A changed original reached successful execution'
            assert sum(step['phase'] == 'drive' for step in trace.steps) > 1
            assert trace.steps
            for step in trace.steps:
                assert step['counts'].get('historyScans', 0) == 0, step
                assert step['counts'].get('unrelatedRunRows', 0) == 0, step
                assert step['counts'].get('unrelatedTaskRows', 0) == 0, step
                assert step['counts'].get('unrelatedEffectRows', 0) == 0, step
                assert step['counts'].get('changedTargetRows', 0) == 0, step
                assert step['counts'].get('returnedRunRows', 0) > 0, step
    except BaseException as error:
        primary = error
        failures = []
        if host is not None:
            for work in host._physical_work:
                if work._future.done() and not work._future.cancelled():
                    cause = work._future.exception()
                    if cause is not None:
                        detail = {'type': type(cause).__name__}
                        if type(cause) is LocalCoreError:
                            detail.update(operation=cause.operation, code=cause.code)
                        failures.append(detail)
        print(json.dumps({'completedHistory': completed_history,
                          'acceptedPendingHistory': accepted_pending_history,
                          'closedPendingHistory': closed_pending_history,
                          'originalWorkFailures': failures}), flush=True)
        if fault is None:
            raise
        assert fault_used and type(trace.refusal) is LocalCoreError, failures
        assert trace.refusal.operation == 'reserve_next_sdk_task', trace.refusal.operation
        assert trace.refusal.code == FAULTS[fault], trace.refusal.code
        assert [step['phase'] for step in trace.steps] == ['select'], trace.steps
        if fault == 'current':
            assert failed_callbacks.failure is injected_primary
        if fault == 'reentry':
            assert type(failed_callbacks.failure) is RuntimeError
    finally:
        for original in (client, host):
            if original is not None:
                try:
                    await original.aclose()
                except BaseException as error:
                    cleanup.append(error)
        if core is not None:
            try:
                if not core.close():
                    raise RuntimeError('Original component Core cleanup remains pending')
            except BaseException as error:
                cleanup.append(error)
        if cleanup:
            if primary is None:
                raise cleanup[0]
            # Keep the same initiating error; disclose rather than promote a
            # failed/pending cleanup to first-close success.
            print(json.dumps({'cleanupFailures': [type(error).__name__ for error in cleanup]}), file=sys.stderr)
    return {'history': history, 'fault': fault, 'steps': trace.steps,
            'populationMode': 'accepted-pending-durable-history/live-target' if pending else
                'persisted-history-fresh-live-target' if persisted else 'same-live-host',
            'completedHistory': completed_history, 'acceptedPendingHistory': accepted_pending_history,
            'closedPendingHistory': closed_pending_history,
            'refusal': None if trace.refusal is None else trace.refusal.code,
            'firstCloseReturned': not cleanup,
            'cleanupFailures': [type(error).__name__ for error in cleanup]}


async def main():
    if len(sys.argv) not in (3, 4):
        raise ValueError('Expected same-source Wasm, fresh scratch and optional selected history')
    raw = Path(sys.argv[1]).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    scratch = Path(sys.argv[2]); scratch.mkdir(parents=True, exist_ok=True)
    fault = sys.argv[3][6:] if len(sys.argv) == 4 and sys.argv[3].startswith('fault:') else None
    assert fault is None or fault in FAULTS
    persisted = len(sys.argv) == 4 and sys.argv[3].startswith('persisted:')
    pending = len(sys.argv) == 4 and (sys.argv[3] == 'pending' or sys.argv[3].startswith('pending:'))
    sizes = [0] if fault is not None else [1, 10, 100] if len(sys.argv) == 3 or sys.argv[3] == 'pending' else [
        int(sys.argv[3][10:] if persisted else sys.argv[3][8:] if pending else sys.argv[3])]
    assert fault is not None or all(size in (1, 10, 100) for size in sizes)
    observations = []
    for size in sizes:
        observed = await population(raw, digest, scratch, size, fault, persisted, pending)
        if observations:
            assert observed['steps'] == observations[0]['steps'], 'Target counters changed with unrelated history'
        observations.append(observed)
    print(json.dumps({'qualification': 'raw same-source component, no latency/normal/stop claim',
        'wasmSha256': digest, 'histories': observations,
        'unmeasured': ['Core internal parse/hash counts', 'latency', 'physical ACK/FD']}, sort_keys=True))


if __name__ == '__main__':
    asyncio.run(main())
