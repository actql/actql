"""Ordinary same-live-Host Runs, original Result rereads and cold Saved.

All lifecycle actions use the installed public Client. The optional inventory
record is a read-only, non-atomic diagnostic; it is never a cleanup action or
physical acknowledgement. No garbage collection or private retirement is used.
"""
from __future__ import annotations

from collections.abc import Mapping
from contextlib import _GeneratorContextManager
from types import BuiltinMethodType, FunctionType, GeneratorType
import _thread
import builtins
import json
import os
from pathlib import Path
import sys
import threading
import time


ROOT = Path(__file__).resolve().parent


class _OrdinaryFuelObservation:
    """Optional finite read-only evidence; the ordinary caller stays unchanged.

    Start is the original operation's setup-lock exit. End is sampled in its
    original locked epilogue before identity reset, and confirmed at that lock's
    actual exit. A retained unit ends only in its original worker callback.
    Scope return is neither a Run outcome nor a physical cleanup acknowledgement.
    Only scalar identities/values are retained, never a Store, Host or frame.
    """
    MAX_OPERATIONS = 512
    MAX_STAGES = 1024

    def __init__(self, core_type, host_type, work_type):
        self.core_type, self.host_type, self.work_type = core_type, host_type, work_type
        self.methods = (core_type._host_operation, core_type._finish_work_operation,
                        host_type._accept_original, host_type._read_original_saved_admission,
                        core_type.inspect_journal_observation, work_type._run)
        self.operation_code = self.methods[0].__wrapped__.__code__
        self.finish_code, self.work_code = self.methods[1].__code__, self.methods[5].__code__
        self.exit_code = _GeneratorContextManager.__exit__.__code__
        # These three code objects stay alive through the original methods.
        # Never hash arbitrary unrelated f_code objects on the global profile path.
        self.stage_codes = dict(zip((id(method.__code__) for method in self.methods[2:5]),
                                    ('accept', 'saved-admission', 'journal-inspect')))
        self.marker_code = write_event.__code__
        self.records, self.stages = [None] * self.MAX_OPERATIONS, [None] * self.MAX_STAGES
        self.used = self.stage_used = 0
        self.ordinal = None
        self.getter = self.setter = self.store_type = None
        self.failed = self.missing = self.overflow = self.active = self.restored = False
        self.previous = (None, None)
        self.callback = self._profile

    def __enter__(self):
        self.previous = (sys.getprofile(), threading.getprofile())
        if self.active or any(value is not None for value in self.previous):
            raise AssertionError('Ordinary fuel observation requires no other profiler')
        self.active = True
        try:
            threading.setprofile(self.callback)
            sys.setprofile(self.callback)
        except BaseException:
            self._finish()
            raise
        return self

    def _finish(self):
        self.active = False
        for restore, previous in ((sys.setprofile, self.previous[0]),
                                  (threading.setprofile, self.previous[1])):
            try:
                restore(previous)
            except BaseException:
                self.failed = True
        self.restored = (sys.getprofile() is self.previous[0]
                         and threading.getprofile() is self.previous[1])

    def __exit__(self, kind, primary, trace):
        self._finish()
        return False

    def _base(self, core, *, active=False):
        if type(core) is not self.core_type:
            return None
        data = vars(core)
        exports = data.get('_exports')
        # Wasmtime's original InstanceExports has an already-materialized dict;
        # inspect that DATA without another runtime/export lookup.
        memory_map = exports if type(exports) is dict else vars(exports).get('_extern_map')
        original, store, lock = (data.get('_platform_vm_original'), data.get('_store'),
                                  data.get('_lock'))
        if (type(original) is not tuple or len(original) < 8
                or original[0] is not core or original[1] is not data.get('_identity')
                or original[2] != data.get('_nonce') or original[3] is not store
                or original[4] is not data.get('_instance') or original[5] is not data.get('_exports')
                or type(memory_map) is not dict or original[6] is not memory_map.get('memory')
                or original[7] != os.getpid() or store is None
                or data.get('_ordinary_host') is not True or data.get('_closed') is not False
                or data.get('_retired') is not False or data.get('_invoking') is not False
                or type(lock) is not _thread.RLock or not lock._is_owned()):
            return None
        if active and (data.get('_host_fuel_phase') != 'operation'
                or type(data.get('_host_operation_id')) is not int
                or data['_host_operation_id'] <= 0 or data.get('_host_operation_scope') is None):
            return None
        return data, store

    def _find(self, core, scope):
        if type(core) is not self.core_type or scope is None:
            return None
        return next((record for record in reversed(self.records[:self.used])
                     if record['core'] == id(core) and record['scope'] == id(scope)
                     and record['nonce'] == vars(core).get('_nonce')), None)

    def _remaining(self, core, record):
        selected = self._base(core, active=True)
        if selected is None:
            record['reason'] = 'foreign-or-unavailable'
            return None
        data, store = selected
        if (data.get('_closing') is not False or id(store) != record['store']
                or data['_nonce'] != record['nonce']
                or data['_host_operation_id'] != record['operation']
                or id(data['_host_operation_scope']) != record['scope']):
            record['reason'] = 'foreign-or-unavailable'
            return None
        getter, setter = vars(type(store)).get('get_fuel'), vars(type(store)).get('set_fuel')
        if type(getter) is not FunctionType or type(setter) is not FunctionType:
            record['reason'] = 'unavailable-store-methods'
            return None
        if self.getter is None:
            self.store_type, self.getter, self.setter = type(store), getter, setter
        if type(store) is not self.store_type or getter is not self.getter or setter is not self.setter:
            record['reason'] = 'changed-store-methods'
            return None
        try:
            remaining = getter(store)  # No guest entry, setter, new operation or scope refresh.
        except BaseException:
            self.failed = True
            record['reason'] = 'getter-unavailable'
            return None
        if type(remaining) is not int or not 0 <= remaining < 1 << 64:
            record['reason'] = 'invalid-remaining-fuel'
            return None
        after = self._base(core, active=True)
        if (after is None or after[1] is not store
                or after[0]['_host_operation_id'] != record['operation']
                or id(after[0]['_host_operation_scope']) != record['scope']):
            record['reason'] = 'changed-original-operation'
            return None
        return remaining

    def _lock_exit(self, frame, core):
        selected = self._base(core)
        if selected is None:
            return
        data, store = selected
        if frame.f_code is self.operation_code:
            scope = frame.f_locals.get('scope')
            if scope is None or frame.f_locals.get('initial') is not False:
                return  # Bootstrap has a separate allowance.
            record = self._find(core, scope)
            if data.get('_host_operation_scope') is scope and data.get('_host_fuel_phase') == 'operation':
                operation = data.get('_host_operation_id')
                if record is not None and record['operation'] == operation:
                    return  # The originating context may exit while its worker retains this SAME unit.
                if self.used == self.MAX_OPERATIONS:
                    self.overflow = True
                    return  # Admit the observation slot BEFORE calling the getter.
                record = {'core': id(core), 'store': id(store), 'nonce': data['_nonce'],
                          'operation': operation, 'scope': id(scope), 'ordinal': self.ordinal,
                          'startRemaining': None, 'endRemaining': None, 'ending': None,
                          'context_success': None, 'ended': False, 'reason': None}
                self.records[self.used] = record
                self.used += 1
                record['startRemaining'] = self._remaining(core, record)
                return
        else:
            retained = frame.f_locals.get('retained')
            if type(retained) is not tuple or len(retained) != 3:
                return
            record = self._find(core, retained[1])
        if record is None:
            self.missing = True
            return
        if frame.f_code is self.operation_code:
            if record['operation'] != frame.f_locals.get('sequence', -2) + 1:
                self.missing = True
                return
        elif record['operation'] != retained[2]:
            self.missing = True
            return
        if (data.get('_host_operation_scope') is None and data.get('_host_operation_id') == 0
                and data.get('_host_fuel_phase') is None and data.get('_host_retained_work') is None):
            expected = 'normal-context' if frame.f_code is self.operation_code else 'retained-worker'
            if record['ending'] == expected:
                record['ended'] = True  # Actual owner reset observed before releasing its lock.

    def _before_reset(self, frame, core):
        selected = self._base(core, active=True)
        if selected is None:
            return
        data, _ = selected
        if frame.f_code is self.operation_code:
            scope = frame.f_locals.get('scope')
            if scope is None or frame.f_locals.get('initial') is not False:
                return
            if data['_host_operation_scope'] is not scope:
                return
            retained = data.get('_host_retained_work')
            if type(retained) is tuple and len(retained) == 3 and retained[1] is scope:
                return  # Not the retained operation's end.
            record = self._find(core, scope)
            if record is None or record['operation'] != data['_host_operation_id']:
                self.missing = True
                return
            record['ending'] = 'normal-context'
            if record['context_success'] is not True:
                record['reason'] = 'normal-body-failed-or-unavailable'
                return
        else:
            if frame.f_locals.get('ordinary') is not True:
                return
            work, retained, parent = (frame.f_locals.get('work'),
                                      data.get('_host_retained_work'), frame.f_back)
            if (type(work) is not self.work_type or type(retained) is not tuple or len(retained) != 3
                    or retained[0] is not work or retained[1] is not data['_host_operation_scope']
                    or retained[2] != data['_host_operation_id']):
                return
            record = self._find(core, retained[1])
            if record is None or record['operation'] != retained[2]:
                self.missing = True
                return
            record['ending'] = 'retained-worker'
            if (parent is None or parent.f_code is not self.work_code
                    or parent.f_locals.get('self') is not work or 'failure' not in parent.f_locals
                    or parent.f_locals['failure'] is not None):
                record['reason'] = 'worker-failed-or-unavailable'
                return
        record['endRemaining'] = self._remaining(core, record)

    def _profile(self, frame, event, arg):
        if not self.active:
            return
        try:
            code = frame.f_code
            if code is self.marker_code and event == 'call':
                details = frame.f_locals.get('details')
                if frame.f_locals.get('phase') == 'submission-created' and type(details) is dict:
                    ordinal = details.get('ordinal')
                    if type(ordinal) is int and 1 <= ordinal <= 10:
                        self.ordinal = ordinal
            elif code is self.exit_code and event == 'call':
                manager = frame.f_locals.get('self')
                generator = vars(manager).get('gen') if type(manager) is _GeneratorContextManager else None
                if type(generator) is GeneratorType and generator.gi_code is self.operation_code:
                    owner = generator.gi_frame
                    if owner is not None and 'typ' in frame.f_locals:
                        record = self._find(owner.f_locals.get('self'), owner.f_locals.get('scope'))
                        if (record is not None and record['operation'] ==
                                owner.f_locals.get('sequence', -2) + 1):
                            record['context_success'] = frame.f_locals['typ'] is None
            elif code is self.operation_code or code is self.finish_code:
                core = frame.f_locals.get('self')
                if event == 'c_return' and arg is builtins.getattr:
                    self._before_reset(frame, core)
                elif (event == 'c_call' and type(arg) is BuiltinMethodType
                        and arg.__name__ == '__exit__' and type(core) is self.core_type
                        and arg.__self__ is vars(core).get('_lock')):
                    self._lock_exit(frame, core)
            elif id(code) in self.stage_codes and event in ('call', 'return'):
                receiver = frame.f_locals.get('self')
                core = receiver if type(receiver) is self.core_type else (
                    vars(receiver).get('_core') if type(receiver) is self.host_type else None)
                selected = self._base(core, active=True)
                if selected is not None:
                    if self.stage_used == self.MAX_STAGES:
                        self.overflow = True
                        return
                    data, _ = selected
                    record = self._find(core, data['_host_operation_scope'])
                    if record is not None:
                        index = self.stage_used
                        self.stage_used += 1
                        self.stages[index] = {'stage': self.stage_codes[id(code)], 'event': event,
                            'core': record['core'], 'operation': record['operation'],
                            'scope': record['scope'], 'ordinal': self.ordinal,
                            'remaining': self._remaining(core, record)}
        except BaseException:
            self.failed = True  # Optional evidence never formats, retains or replaces primary errors.

    def summary(self):
        methods = (self.core_type._host_operation, self.core_type._finish_work_operation,
                   self.host_type._accept_original, self.host_type._read_original_saved_admission,
                   self.core_type.inspect_journal_observation, self.work_type._run)
        unchanged = (all(before is after for before, after in zip(self.methods, methods))
                     and (self.store_type is None or (
                         vars(self.store_type).get('get_fuel') is self.getter
                         and vars(self.store_type).get('set_fuel') is self.setter)))
        operations = []
        for record in self.records[:self.used]:
            start, end = record['startRemaining'], record['endRemaining']
            available = (not self.active and self.restored and unchanged and record['reason'] is None
                         and record['ended'] and record['context_success'] is True
                         and start is not None and end is not None and end <= start)
            operations.append({key: value for key, value in record.items()
                               if key not in ('context_success', 'ended')} | {
                'available': available, 'contextSucceeded': record['context_success'],
                'ownerReturnObserved': record['ended'],
                'consumedFuel': start - end if available else None})
        return {'qualified': (bool(operations) and all(row['available'] for row in operations)
                              and not self.failed and not self.missing and not self.overflow),
                'operations': operations, 'stages': self.stages[:self.stage_used],
                'observationFailed': self.failed, 'missingStart': self.missing, 'overflow': self.overflow,
                'runtimeMethodsUnchanged': unchanged, 'profilersRestored': self.restored,
                'qualification': 'Guest fuel in successful normal original scopes; excludes bootstrap, '
                    'independent cleanup and failed units. Not wall latency, a Run outcome or physical ACK.'}


def plain(value):
    if isinstance(value, Mapping):
        return {key: plain(child) for key, child in value.items()}
    if isinstance(value, (list, tuple)):
        return [plain(child) for child in value]
    return value


def write_event(phase, **details):
    with (ROOT / 'events.jsonl').open('a', encoding='utf-8') as target:
        target.write(json.dumps({'pid': os.getpid(), 'phase': phase,
                                 'elapsed': time.monotonic() - START, **details}) + '\n')
        target.flush()


def inventory(client):
    host = client._client._local_host
    names = ('_prepared_inputs', '_run_loans', '_public_run_references', '_run_state_custody',
             '_run_publications', '_row_outputs', '_run_rows', '_journal_outputs',
             '_physical_starts', '_source_free_computes', '_source_free_invocations',
             '_publication_preflights', '_publishers', '_tasks', '_result_exports',
             '_result_chunks', '_publications', '_saved_result_reads', '_payloads',
             '_inputs', '_response_streams', '_projections', '_physical_work')
    counts = {name: len(getattr(host, name)) for name in names}
    counts['stopped_work'] = sum(work.stopped for work in tuple(host._physical_work))
    counts['core_loans'] = len(host._core._loans)
    counts['core_retained_work'] = host._core._host_retained_work is not None
    return counts


def rows(run, expected):
    state = run.status()
    assert state['status'] == 'succeeded'
    actual = run.result('answer').all(max_rows=1)
    assert type(actual) is list and len(actual) == 1
    assert type(actual[0]) is dict and set(actual[0]) == {'n'}
    assert type(actual[0]['n']) is int and actual[0]['n'] == expected


def failure_data(error):
    result = {'type': type(error).__name__}
    code = getattr(error, 'code', None)
    if type(code) is str and len(code) <= 256:
        result['code'] = code
    return result


def run_phase(phase):
    from actql import Client
    client = None
    failed = False
    try:
        client = Client.open()
        write_event('opened', mode=phase, inventory=inventory(client))
        if phase == 'warm':
            originals, executions = [], []
            for ordinal in range(1, 11):
                submission = client.new_submission()
                write_event('submission-created', ordinal=ordinal)
                expected = 40 + ordinal
                execution = client.start_source(f'SELECT {expected} AS n', format='sql',
                                                submission_ref=submission)
                original = {'ordinal': ordinal, 'expected': expected,
                            'submission': plain(submission), 'run': plain(execution.ref)}
                assert all(item['run'] != original['run'] for item in originals)
                originals.append(original)
                # Persist every actual reference before its first wait.
                temporary = ROOT / 'originals.pending.json'
                temporary.write_text(json.dumps({'producer_pid': os.getpid(), 'runs': originals}) + '\n')
                temporary.replace(ROOT / 'originals.json')
                write_event('original-recorded-before-wait', ordinal=ordinal)
                assert execution.wait()['status'] == 'succeeded'
                rows(execution, expected)
                executions.append(execution)
                write_event('result-complete', ordinal=ordinal, inventory=inventory(client))
                if ordinal in (1, 3, 10):
                    for prior, item in zip(executions, originals):
                        rows(prior, item['expected'])
                        attached = client.attach(item['run'])
                        assert plain(attached.ref) == item['run']
                        rows(attached, item['expected'])
                    write_event('checkpoint-complete', ordinal=ordinal, inventory=inventory(client))
            write_event('warm-complete', runs=len(originals), inventory=inventory(client))
        elif phase == 'saved':
            original = json.loads((ROOT / 'originals.json').read_text())
            assert original['producer_pid'] != os.getpid()
            assert len(original['runs']) == 10
            for item in original['runs']:
                observed = client.lookup_submission(item['submission'])
                assert observed['kind'] == 'ready'
                assert plain(observed['admission']['ref']) == item['run']
                execution = client.attach(item['run'])
                assert plain(execution.ref) == item['run']
                rows(execution, item['expected'])
                write_event('saved-result-complete', ordinal=item['ordinal'])
            write_event('saved-complete', runs=10, inventory=inventory(client))
        else:
            raise ValueError('Unknown repeated-Host fixture phase')
    except BaseException as primary:
        failed = True
        write_event('primary-failure', mode=phase, error=failure_data(primary))
        raise
    finally:
        if client is not None:
            write_event('first-close-attempted', mode=phase, inventory=inventory(client))
            try:
                client.close()
            except BaseException as cleanup:
                write_event('first-close-failed', mode=phase, error=failure_data(cleanup))
                if not failed:
                    raise
            else:
                write_event('first-close-returned', mode=phase)


START = time.monotonic()
if __name__ == '__main__':
    run_phase(sys.argv[1])
