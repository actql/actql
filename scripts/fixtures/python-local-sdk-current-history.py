"""Finite actual Core/SQLite managed-continuation read counters.

Raw mode uses explicit fixture authority. Isolated installed-image mode uses
the real owning factory and operation allowance; it is not equivalent raw fuel.
Neither is normal Host, latency or physical-stop acceptance. Only the existing
task selection/drive and physical Journal import are measured.

The optional prepare-pending:100 and target-pending:100 phases separate genuine
setup from a fresh owning target. The external guard must finish preparation,
first close and both byte/input audits before passing its final JSON report to
target mode. That report routes a namespace; it never replaces current/full
admission. No budget or automatic phase launch is implemented by this fixture.
"""
import asyncio
from collections import Counter
from contextlib import contextmanager, nullcontext
from ctypes import byref
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import stat
import sys
from tempfile import mkdtemp
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
INSTALLED_IMAGE = len(sys.argv) > 1 and sys.argv[1] == '--installed'
if not INSTALLED_IMAGE:
    sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk import AsyncClient
from actql_sdk._local_core import LocalCore, LocalCoreError, LocalCoreInitializationError, _NORMAL_HOST_OPERATION_FUEL
from actql_sdk._local_product import InstalledLocalHost, LocalProductCleanupPending, _OriginalExecution, _ordinary_core_limits
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


def history_phase(selection):
    phases = {'prepare-pending:100': 'prepare', 'target-pending:100': 'target'}
    if selection in phases:
        return phases[selection]
    if selection is not None and selection.startswith(('prepare-', 'target-')):
        raise ValueError('Unsupported history phase selection')
    return None


def history_state_identity(state):
    observed = state.lstat()
    if not stat.S_ISDIR(observed.st_mode):
        raise ValueError('Expected original case directory, never a link')
    return {'path': str(state.resolve()), 'dev': observed.st_dev, 'inode': observed.st_ino}


def ready_history_state(document, scratch, source, fixture_sha):
    """Route successful setup DATA; actual Host/Core still validate the Store.

    The external guard must also complete its input proofs and byte audits
    before selecting this target. This report cannot grant current authority.
    """
    if (type(document) is not dict or document.get('phase') != 'prepare'
            or document.get('fixtureSha256') != fixture_sha
            or type(document.get('installedCohort')) is not dict
            or document['installedCohort'].get('sourceSha') != source):
        raise ValueError('Foreign preparation source or fixture')
    histories = document.get('histories')
    if type(histories) is not list or len(histories) != 1:
        raise ValueError('Expected one completed preparation phase')
    prepared = histories[0]
    if (type(prepared) is not dict or any(type(prepared.get(field)) is not int for field in (
            'history', 'acceptedPendingHistory', 'retiredPendingParentLoans',
            'closedPendingHistory', 'completedHistory'))
            or prepared.get('history') != 100 or prepared.get('acceptedPendingHistory') != 100
            or prepared.get('retiredPendingParentLoans') != 100
            or prepared.get('closedPendingHistory') != 0
            or prepared.get('completedHistory') != 0 or prepared.get('steps') != []
            or prepared.get('coreMode') != 'installed-image/ordinary-operation-owner'
            or prepared.get('fault') is not None
            or prepared.get('firstCloseReturned') is not True
            or prepared.get('cleanupFailures') != [] or prepared.get('refusal') is not None):
        raise ValueError('Preparation counts or original close incomplete')
    identity = prepared.get('stateIdentity')
    if (type(identity) is not dict or set(identity) != {'path', 'dev', 'inode'}
            or type(identity['path']) is not str
            or type(identity['dev']) is not int or type(identity['inode']) is not int):
        raise ValueError('Missing original successful namespace locator')
    state = Path(identity['path'])
    if state.parent != scratch.resolve() or history_state_identity(state) != identity:
        raise ValueError('Changed preparation directory or foreign namespace')
    return state, document['installedCohort']


def correlate_history_cohort(observed, expected):
    if expected is not None and (type(expected) is not dict or observed.keys() != expected.keys()
            or any(type(expected[key]) is not type(value) or expected[key] != value
                   for key, value in observed.items())):
        raise ValueError('Prepared namespace belongs to a different installed cohort')


class PrefixObservation:
    """Bounded first normal retain observation; no validation or permission."""
    def __init__(self):
        self.active = self.entered = self.complete = self.eof = self.invalid = False
        self.keys = set()
        self.core = self.store = None

    def observe(self, core, ticket, mode, namespace, code):
        if not self.active or core is not self.core or mode != 0 or namespace != 'client_runs':
            return
        try:
            callbacks = core._journal_callbacks(ticket)
            if callbacks is None or callbacks.store is not self.store:
                self.invalid = True
            elif code == 1 and callbacks.row is None:
                self.eof = True
            elif code == 0 and callbacks.row is not None and type(callbacks.row[0]) is bytes:
                key = callbacks.row[0]
                if key not in self.keys:
                    if len(self.keys) == 100:
                        self.invalid = True
                    else:
                        self.keys.add(key)
            else:
                self.invalid = True
        except Exception:
            self.invalid = True

    @contextmanager
    def bind(self, host, core):
        if self.core is not None:
            raise ValueError('Prefix observation is one-use, not a retained permission')
        original = InstalledLocalHost._retain_intent
        self.core, self.store = core, host._installation._store

        def retain(receiver, *args, **kwargs):
            if receiver is not host or self.entered:
                return original(receiver, *args, **kwargs)
            self.entered = self.active = True
            try:
                result = original(receiver, *args, **kwargs)
            finally:
                self.active = False
            # An original failure bypasses this diagnostic assertion, retaining
            # its exact primary. No return/output or callback is substituted.
            assert not self.invalid and self.eof and len(self.keys) == 100, 'Incomplete actual prefix observation'
            self.complete = True
            return result

        with patch.object(InstalledLocalHost, '_retain_intent', retain):
            yield

    def report(self):
        return {'complete': self.complete, 'observedRunRows': len(self.keys), 'scanEnded': self.eof}


async def close_history_owners(client, host, core, primary):
    cleanup = []
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
        print(json.dumps({'cleanupFailures': [type(error).__name__ for error in cleanup]}), file=sys.stderr)
    return cleanup


def retire_pending_original_parents(host, original):
    """Return one fresh admission's private loans, never close or stop its Run.

    The caller passes the unchanged descriptor returned by _accept_original,
    after leaving that admission's operation frame. Core still owns each ACK.
    """
    core = host._core
    with core._lock:
        if (type(original) is not _OriginalExecution or original.host is not host
                or any(getattr(original, field) is not None for field in (
                    'reference', 'compute', 'preflight', 'publisher', 'tasks',
                    'results', 'publication', 'state', 'physical_start',
                    'start_step', 'stop_interest'))
                or original.submission is None or original.rows_input is None):
            raise ValueError('Expected the same fresh unstarted admission descriptor')
        run, prepared = original.run, original.run.preparation
        if (not any(value is run for value in host._run_loans)
                or not any(value is prepared for value in host._prepared_inputs)
                or run.handle in host._runs._run_restorations
                or any(value is not run and value.preparation is prepared
                       for value in host._runs._runs.values())
                or any((host._physical_work, host._physical_starts,
                        host._source_free_computes, host._tasks, host._public_run_references))
                or any(getattr(host, field) is not None for field in (
                    '_uncertain_ticket', '_pending_run_write',
                    '_pending_start_write', '_pending_binding_write'))
                or core._host_fuel_phase is not None or core._host_retained_work is not None):
            raise ValueError('Original admission has shared, restored or active custody')
        with core._host_cleanup():
            if host._retire_original_execution_parents(original) is not True:
                raise LocalProductCleanupPending(host)


async def population(raw, digest, scratch, history, fault=None, persisted=False, pending=False, installed=False,
                     phase=None, existing_state=None):
    assert not (persisted and pending)
    trace = Trace()
    prefix = PrefixObservation() if phase == 'target' else None
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
        if prefix is not None and prefix.active:
            try:
                memory = core._bulk_memory(caller, namespace_offset, namespace_bytes)
                selected_namespace = bytes(memory.read(
                    caller, namespace_offset, namespace_offset + namespace_bytes)).decode('utf-8')
                prefix.observe(core, ticket, mode, selected_namespace, code)
            except Exception:
                prefix.invalid = True  # Never mask the original query/primary.
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

    if phase not in (None, 'prepare', 'target') or phase is not None and (not installed or not pending or history != 100):
        raise ValueError('Split phases require the selected installed pending100 case')
    if phase == 'target' and existing_state is None:
        raise ValueError('Target requires its completed original preparation namespace')
    state = existing_state if phase == 'target' else Path(mkdtemp(prefix=f'history-{history}-', dir=scratch))
    if phase == 'prepare':
        state = state.resolve()  # The first owning factory and later route use the same path.
    client = host = core = None
    primary = None
    completed_history = 0
    accepted_pending_history = 0
    closed_pending_history = 0
    retired_pending_parent_loans = 0
    pending_references = set()
    cleanup = []

    async def open_original():
        nonlocal host, core, client
        try:
            if installed:
                # The existing owning factory resolves and acquires the real
                # image. Never mark a raw Core ordinary or build a profile here.
                host = InstalledLocalHost.installed(state_dir=state)
                core = host._core
                assert core._ordinary_host
            else:
                core = LocalCore(raw, digest=digest, transfer_capacity=12 * 1024 * 1024,
                    slots=128, resources=_ordinary_core_limits(), fuel=_NORMAL_HOST_OPERATION_FUEL)
                host = InstalledLocalHost(core, state, now=lambda: 1_800_000_000_000,
                    observed_at='2026-11-18T00:00:00.000Z', sdk_finite=True)
        except LocalProductCleanupPending as failure:
            host = failure.cleanup_host
            core = host._core
            raise
        except LocalCoreInitializationError as failure:
            core = failure.cleanup_core
            raise
        client = await AsyncClient._connect_local(host)

    try:
        with patch.object(LocalCore, '_journal_query_header', query), \
                patch.object(LocalCore, '_journal_current', current), \
                patch.object(LocalCore, '_journal_current_operation', operation), \
                patch.object(_JournalCallbacks, 'query', queried):
            await open_original()
            for index in range(0 if phase == 'target' else history):
                if pending:
                    # Stop at the original accepting owner, before its outer
                    # submit consumer constructs or starts physical work.
                    name = f'history-{history}-{index}'
                    reference = thaw(client.new_submission(nonce=name))
                    intent = wire_bytes({'kind': 'aql', 'input': {
                        'text': 'WITH seed AS (SELECT 41 AS n) FROM seed |> SELECT n |> RESULT answer',
                        'format': 'aql'}, 'parameters': None})
                    # Exit this SAME original operation before client/Host
                    # close. No refill, nested initial frame or Work is issued.
                    with core._host_operation():
                        if installed:
                            assert core._host_fuel_phase == 'operation'
                        run, admission = host._accept_original(reference, intent, run_id=name)
                    if installed:
                        assert core._host_fuel_phase is None and core._host_retained_work is None
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
                    # Keep the same Host/Core and durable rows. A private loan
                    # ACK is neither a whole-Host close nor a Run stop/result.
                    retire_pending_original_parents(host, run)
                    run = None  # Only after the complete original ACK chain.
                    retired_pending_parent_loans += 1
                    print(json.dumps({'retiredPendingParentLoans': retired_pending_parent_loans}), flush=True)
                else:
                    original = await client.start_source(
                        'WITH seed AS (SELECT 41 AS n) FROM seed |> SELECT n |> RESULT answer', format='aql')
                    assert (await original.wait(until='terminal')).to_dict()['status'] == 'succeeded'
                    assert await original.result('answer').all(schema=Row, max_rows=2) == [Row(41)]
                    completed_history += 1
                    print(json.dumps({'completedHistory': completed_history}), flush=True)
                if persisted:
                    # Persisted mode retains its original child-first whole
                    # close/reopen route and this case's durable originals.
                    await client.aclose()
                    await host.aclose()
                    assert core.close() is True
                    await open_original()

            if pending and phase != 'target':
                assert accepted_pending_history == retired_pending_parent_loans == len(pending_references) == history
                assert closed_pending_history == 0

            if phase != 'prepare':
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
                        patch.object(core, 'drive_task', drive), \
                        prefix.bind(host, core) if prefix is not None else nullcontext():
                    trace.enabled = True
                    execution = await client.start_source(
                        'WITH seed AS (SELECT 1 AS n) FROM seed AS l |> JOIN seed AS r ON l.n = r.n '
                        'MAX_OUTPUT_ROWS 1 |> SELECT l.n + r.n AS n |> RESULT answer', format='aql')
                    if prefix is not None:
                        assert prefix.complete, 'Normal target did not complete its full prefix scope'
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
                        try:
                            frame = cause.__traceback__
                            for _ in range(32):
                                if frame is None:
                                    break
                                if (frame.tb_frame.f_code is LocalCore._call.__code__
                                        and frame.tb_frame.f_locals.get('self') is core):
                                    detail['sdkFrame'] = 'LocalCore._call'
                                    operation = frame.tb_frame.f_locals.get('export_name')
                                    if type(operation) is str and operation in core._exports:
                                        detail['abiOperation'] = operation
                                    break
                                frame = frame.tb_next
                            for runtime_name in ('wasmtime', 'actql_local_runtime._wasmtime'):
                                runtime = sys.modules.get(runtime_name)
                                ffi = sys.modules.get(runtime_name + '._ffi')
                                if runtime is None or ffi is None or type(cause) is not runtime.Trap:
                                    continue
                                # Read the closed C code: the public TrapCode
                                # enum may omit a code from the same runtime.
                                code = ffi.wasmtime_trap_code_t()
                                detail['trapCode'] = (code.value if ffi.wasmtime_trap_code(
                                    cause.ptr(), byref(code)) else None)
                                break
                        except BaseException:
                            # Diagnostic failure cannot replace the original.
                            detail['diagnosticUnavailable'] = True
                        failures.append(detail)
        print(json.dumps({'completedHistory': completed_history,
                          'acceptedPendingHistory': accepted_pending_history,
                          'closedPendingHistory': closed_pending_history,
                          'retiredPendingParentLoans': retired_pending_parent_loans,
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
        cleanup = await close_history_owners(client, host, core, primary)
    result = {'history': history, 'fault': fault, 'steps': trace.steps,
            'coreMode': 'installed-image/ordinary-operation-owner' if installed else 'raw-component/initial-fuel',
            'populationMode': 'accepted-pending-durable-history/private-parent-retirement/live-target' if pending else
                'persisted-history-fresh-live-target' if persisted else 'same-live-host',
            'completedHistory': completed_history, 'acceptedPendingHistory': accepted_pending_history,
            'closedPendingHistory': closed_pending_history,
            'retiredPendingParentLoans': retired_pending_parent_loans,
            'refusal': None if trace.refusal is None else trace.refusal.code,
            'firstCloseReturned': not cleanup,
            'cleanupFailures': [type(error).__name__ for error in cleanup]}
    if phase is not None:
        result.update(stateIdentity=history_state_identity(state), phase=phase,
                      prefixObservation=None if prefix is None else prefix.report())
        result['populationMode'] = ('accepted-pending-preparation-only' if phase == 'prepare' else
                                    'same-completed-namespace/full-normal-target')
    return result


async def main():
    image_identity = None
    expected_cohort = None
    existing_state = None
    phase = None
    fixture_sha = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    resolver = nullcontext()
    if INSTALLED_IMAGE:
        if len(sys.argv) not in (5, 6) or not sys.flags.isolated:
            raise ValueError('Expected isolated installed Python, --installed source SHA, fresh scratch and selection')
        expected_source, scratch, selection = sys.argv[2:5]
        phase = history_phase(selection)
        if len(sys.argv) != (6 if phase == 'target' else 5):
            raise ValueError('Only target phase takes its completed preparation report')
        if len(expected_source) != 40 or any(c not in '0123456789abcdef' for c in expected_source):
            raise ValueError('Expected exact installed cohort source SHA')
        if phase is None and not (selection == 'pending' or selection.startswith(('pending:', 'fault:'))):
            raise ValueError('Installed image selection is pending history or its original current/refusal control')
        from actql_sdk import _local_product
        original_resolver = _local_product.installed_local_components

        def checked_components():
            nonlocal image_identity
            # Observe the actual existing resolver result before its factory
            # constructs Core. Return that original, never cached/forged parts.
            components = original_resolver()
            assert components.source_sha == expected_source, 'Installed SDK/image source differs'
            observed = {'sourceSha': components.source_sha, 'packageVersion': components.package_version,
                'moduleSha256': components.module_sha256, 'imageSha256': components.image_sha256,
                'imageBytes': components.image_bytes, 'engineRecipeSha256': components.engine_recipe_sha256,
                'duckdbSha256': components.duckdb_sha256, 'duckdbVersion': components.duckdb_version}
            correlate_history_cohort(observed, expected_cohort)
            if image_identity is None:
                image_identity = observed
            else:
                assert observed == image_identity, 'Installed original cohort changed between owners'
            return components

        resolver = patch.object(_local_product, 'installed_local_components', checked_components)
        raw = digest = None
    else:
        if len(sys.argv) not in (3, 4):
            raise ValueError('Expected same-source Wasm, fresh scratch and optional selected history')
        raw = Path(sys.argv[1]).read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        scratch = sys.argv[2]
        selection = sys.argv[3] if len(sys.argv) == 4 else None
    scratch = Path(scratch); scratch.mkdir(parents=True, exist_ok=True)
    if phase == 'target':
        report_path = Path(sys.argv[5])
        metadata = report_path.lstat()
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 65536:
            raise ValueError('Expected bounded regular preparation control report')
        existing_state, expected_cohort = ready_history_state(
            json.loads(report_path.read_bytes()), scratch, expected_source, fixture_sha)
    fault = selection[6:] if selection is not None and selection.startswith('fault:') else None
    assert fault is None or fault in FAULTS
    persisted = selection is not None and selection.startswith('persisted:')
    pending = phase is not None or selection is not None and (selection == 'pending' or selection.startswith('pending:'))
    sizes = [100] if phase is not None else [0] if fault is not None else [1, 10, 100] if selection in (None, 'pending') else [
        int(selection[10:] if persisted else selection[8:] if pending else selection)]
    assert fault is not None or all(size in (1, 10, 100) for size in sizes)
    observations = []
    with resolver:
        for size in sizes:
            observed = await population(raw, digest, scratch, size, fault, persisted, pending, INSTALLED_IMAGE,
                                        phase, existing_state)
            if observations:
                assert observed['steps'] == observations[0]['steps'], 'Target counters changed with unrelated history'
            observations.append(observed)
    result = {'qualification': 'installed image/real ordinary operation component; not raw fuel equivalence or normal/stop/latency acceptance'
        if INSTALLED_IMAGE else 'raw same-source component, no latency/normal/stop claim',
        'fuelMode': {'owner': 'ordinary Host operation' if INSTALLED_IMAGE else 'raw initial allowance',
            'sourceDeclaredLimit': _NORMAL_HOST_OPERATION_FUEL, 'consumedFuel': 'unmeasured'},
        'wasmSha256': image_identity['moduleSha256'] if INSTALLED_IMAGE else digest,
        'installedCohort': image_identity, 'histories': observations,
        'unmeasured': ['Core internal parse/hash counts', 'latency', 'physical ACK/FD']}
    if phase is not None:
        result.update(phase=phase, fixtureSha256=fixture_sha)
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    asyncio.run(main())
