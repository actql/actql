"""Observe suppressed failure locations without changing installed consumer behavior.

Only CI copies this wrapper outside the repository. It never prints exception
messages, locals, reference values, source lines, or full paths. Known Core
buffer seal and selected original task-drive failures may report their signed
ABI status without decoding a business outcome. Public Unknown semantics and the
original exception are retained; no operation is repeated.
"""
from __future__ import annotations

import _thread
from collections import deque
from concurrent.futures import Future
from itertools import islice
import json
from pathlib import Path
import runpy
import sys
import traceback
import threading
import weakref
from types import FunctionType, MappingProxyType, ModuleType


MAX_CONTEXTS = 16
MAX_FRAMES = 32
MAX_LABEL = 128
MAX_OUTPUT_BYTES = 65536
MAX_WORK_RECORDS = 16
MAX_SELECTION_BYTES = 16384
MAX_VALUE_NODES = 4096
MAX_VALUE_DEPTH = 64
MAX_VALUE_CHARACTERS = 1048576


def bounded_json_data(value):
    """Decline diagnostic classification of foreign, cyclic or oversized DATA."""
    pending, seen, characters, nodes = [(value, 0)], set(), 0, 0
    while pending:
        current, depth = pending.pop()
        nodes += 1
        if nodes > MAX_VALUE_NODES or depth > MAX_VALUE_DEPTH:
            return False
        if type(current) is str:
            characters += len(current)
        elif type(current) in (dict, list):
            if (id(current) in seen or len(current) > MAX_VALUE_NODES
                    or nodes + len(pending) + len(current) > MAX_VALUE_NODES):
                return False
            seen.add(id(current))
            if type(current) is dict:
                for key, child in current.items():
                    if type(key) is not str:
                        return False
                    characters += len(key)
                    pending.append((child, depth + 1))
            else:
                pending.extend((child, depth + 1) for child in current)
        elif current is not None and type(current) not in (bool, int, float):
            return False
        if characters > MAX_VALUE_CHARACTERS:
            return False
    return True


def own_schema_validator(wire_fields):
    """Only the same generated pure codec and tables, never forwarded copies."""
    codec = sys.modules.get('actql_sdk._wire_codec')
    fields = vars(codec) if type(codec) is ModuleType else {}
    validator = fields.get('valid')
    if (type(validator) is FunctionType and validator.__globals__ is fields
            and wire_fields.get('valid') is validator
            and wire_fields.get('SCHEMAS') is fields.get('SCHEMAS')
            and wire_fields.get('CONTRACT') is fields.get('CONTRACT')):
        return validator
    return None


def rejected_wait_shape(value, body, wire_fields):
    """Closed facts about the SAME rejected value, not another Host request."""
    bits = {'wait_state_schema_valid': None, 'wait_status': None,
            'wait_since_none': body.get('since') is None,
            'wait_since_valid': None, 'wait_revision_after_since': None,
            'wait_control_schema_valid': None, 'wait_cancellation_requested': None,
            'wait_physical_stop': None, 'wait_result_available': None,
            'wait_availability_schema_valid': None, 'wait_availability_bounded': None,
            'wait_availability_nonempty': None,
            'wait_availability_all_unavailable': None}
    schemas, contract = wire_fields.get('SCHEMAS'), wire_fields.get('CONTRACT')
    schema = schemas.get('run_state') if type(schemas) is dict else None
    properties = schema.get('properties') if type(schema) is dict else None
    rules = contract.get('request_response_rules') if type(contract) is dict else None
    rule = rules.get('run_wait') if type(rules) is dict else None
    validator = own_schema_validator(wire_fields)
    if (type(value) is not dict or type(properties) is not dict or type(rule) is not dict
            or validator is None or not bounded_json_data(value)):
        return bits
    bits['wait_state_schema_valid'] = validator(value, 'run_state') is True
    status_schema = properties.get('status')
    known = status_schema.get('enum') if type(status_schema) is dict else None
    status = value.get('status')
    if (type(status) is str and type(known) is list and len(known) <= MAX_WORK_RECORDS
            and all(type(item) is str and len(item) <= MAX_LABEL for item in known)
            and status in known):
        bits['wait_status'] = status
    revision_schema = properties.get(rule.get('revisionField'))
    since = body.get('since')
    bits['wait_since_valid'] = since is None or validator(since, revision_schema) is True
    revision = value.get(rule.get('revisionField'))
    bits['wait_revision_after_since'] = (True if since is None else
        revision > since if type(revision) is int and type(since) is int else None)
    control, control_schema = value.get('control'), properties.get('control')
    bits['wait_control_schema_valid'] = validator(control, control_schema) is True
    if type(control) is dict:
        cancelled = control.get('cancellation_requested')
        bits['wait_cancellation_requested'] = cancelled if type(cancelled) is bool else None
        fields = control_schema.get('properties') if type(control_schema) is dict else None
        physical = fields.get('physical_stop') if type(fields) is dict else None
        choices = physical.get('enum') if type(physical) is dict else None
        stopped = control.get('physical_stop')
        if (type(stopped) is str and type(choices) is list and len(choices) <= MAX_WORK_RECORDS
                and all(type(item) is str and len(item) <= MAX_LABEL for item in choices)
                and stopped in choices):
            bits['wait_physical_stop'] = stopped
    available = value.get('result_available')
    bits['wait_result_available'] = available if type(available) is bool else None
    availability = value.get('result_availability')
    bits['wait_availability_schema_valid'] = validator(
        availability, properties.get('result_availability')) is True
    bits['wait_availability_bounded'] = type(availability) is dict and len(availability) <= MAX_WORK_RECORDS
    if bits['wait_availability_bounded']:
        bits['wait_availability_nonempty'] = bool(availability)
        # No result name, observation timestamp, reason or payload is emitted.
        bits['wait_availability_all_unavailable'] = all(
            type(item) is dict and item.get('state') == 'unavailable'
            for item in availability.values())
    return bits


def same_frame_cancellation_kind(frames, requested, wire_fields):
    """A same-reference original caller outcome label, never cancel authority."""
    validator = own_schema_validator(wire_fields)
    if validator is None:
        return None
    schemas = wire_fields.get('SCHEMAS')
    schema = schemas.get('cancellation') if type(schemas) is dict else None
    properties = schema.get('properties') if type(schema) is dict else None
    kind_schema = properties.get('kind') if type(properties) is dict else None
    choices = kind_schema.get('enum') if type(kind_schema) is dict else None
    if (type(choices) is not list or len(choices) > MAX_WORK_RECORDS
            or not all(type(item) is str and len(item) <= MAX_LABEL for item in choices)):
        return None
    matches = []
    for frame, _ in frames:
        candidate = frame.f_locals.get('cancellation')
        if (type(candidate) is not dict or not bounded_json_data(candidate)
                or set(candidate) != {'ref', 'cancelRef', 'kind', 'revision'}
                or candidate.get('ref') != requested):
            continue
        if validator(candidate, 'cancellation') is True and candidate.get('kind') in choices:
            matches.append(candidate['kind'])
    return matches[0] if matches and all(item == matches[0] for item in matches) else None


class _TaskRetirementObservation:
    """Bounded CI samples inside the original allowance, never another close.

    Samples own only scalars and nonowning work associations. Reporting after
    failure does not enter Core after the worker returned its operation scope.
    """

    def __init__(self):
        self.samples = [None] * MAX_WORK_RECORDS
        self.count, self.overflow, self.failed = 0, False, False
        self.active, self.installed, self.restored = False, False, False
        self.previous = (sys.getprofile(), threading.getprofile())
        self.profile = self._profile

    def __enter__(self):
        if any(previous is not None for previous in self.previous):
            self.failed = True
            return self
        self.installed = True
        try:
            sys.setprofile(self.profile)
            threading.setprofile(self.profile)
            self.active = True
        except BaseException:
            self.failed = True
            self._finish()
        return self

    def _finish(self):
        self.active = False
        if not self.installed:
            return
        for restore, previous in ((sys.setprofile, self.previous[0]),
                                  (threading.setprofile, self.previous[1])):
            try:
                restore(previous)
            except BaseException:
                self.failed = True
        self.restored = (sys.getprofile() is self.previous[0]
                         and threading.getprofile() is self.previous[1])
        self.installed = False

    def __exit__(self, kind, primary, trace):
        self._finish()
        return False

    def _profile(self, frame, event, returned):
        if not self.active or event != 'return' or returned is not False:
            return
        try:
            product = sys.modules.get('actql_sdk._local_product')
            core_module = sys.modules.get('actql_sdk._local_core')
            work_module = sys.modules.get('actql_sdk._local_work')
            if not all(type(module) is ModuleType for module in (product, core_module, work_module)):
                return
            core_type, task_type = (vars(core_module).get('LocalCore'), vars(core_module).get('_Task'))
            close = vars(core_type).get('close_task') if type(core_type) is type else None
            if type(close) is not FunctionType or frame.f_code is not close.__code__:
                return
            core, task = frame.f_locals.get('self'), frame.f_locals.get('value')
            if (type(core) is not core_type or type(task) is not task_type
                    or frame.f_locals.get('code') != -9):
                return
            state = vars(core)
            retained, lock = state.get('_host_retained_work'), state.get('_lock')
            if (type(retained) is not tuple or len(retained) != 3
                    or type(lock) is not _thread.RLock or not lock._is_owned()
                    or state.get('_invoking') is not False
                    or state.get('_ordinary_host') is not True
                    or state.get('_host_fuel_phase') != 'operation'
                    or retained[1] is not state.get('_host_operation_scope')
                    or type(retained[2]) is not int or retained[2] <= 0
                    or retained[2] != state.get('_host_operation_id') or '_call' in state):
                return
            work = retained[0]
            work_type = vars(work_module).get('OriginalLocalWork')
            if (type(work) is not work_type or vars(work).get('_original') is not work
                    or vars(work).get('_thread') is not threading.current_thread()):
                return
            future = vars(work).get('_future')
            original = vars(work).get('_invoke')
            if (type(future) is not Future or not future.running()
                    or type(original) is not vars(product).get('_OriginalExecution')):
                return
            host = original.host
            if (type(host) is not vars(product).get('InstalledLocalHost')
                    or vars(host).get('_original') is not host or vars(host).get('_core') is not core
                    or original.run is not vars(work).get('_owner')
                    or type(original.tasks) is not list or len(original.tasks) > MAX_WORK_RECORDS
                    or not any(value is task for value in original.tasks)
                    or task.owner is not state.get('_identity')
                    or type(state.get('_task_loans')) is not dict
                    or state['_task_loans'].get(task.handle) is not task):
                return
            if self.count == MAX_WORK_RECORDS:
                self.overflow = True
                return
            slot = self.count
            self.count += 1  # Reserve the bounded diagnostic slot BEFORE guest entries.
            # The same worker and outer retirement lock still own the original
            # operation. These reads do not create a scope or replenish fuel.
            stage = core._call('task', 'progress', task.handle, 6)
            cleanup = core._call('task', 'progress', task.handle, 7)
            issue = core._call('task', 'issue', task.handle)
            if any(type(code) is not int or not -(1 << 31) <= code < (1 << 31)
                   for code in (stage, cleanup, issue)):
                self.failed = True
                return
            self.samples[slot] = (weakref.ref(work), stage, cleanup, issue)
        except BaseException:
            # Never format, retain or replace an optional diagnostic exception.
            self.failed = True

    def snapshot(self, work):
        records = [{'stage_code': item[1], 'cleanup_issue_code': item[2],
                    'execution_issue_code': item[3]}
                   for item in self.samples if item is not None and item[0]() is work]
        refusal = next((code for item in records for code in
                        (item['stage_code'], item['cleanup_issue_code']) if code < 0), None)
        return {'scope': 'post-close-current-snapshot',
                'available': bool(records) and self.restored and not self.failed
                             and not self.overflow and refusal is None,
                'observation_failed': self.failed, 'overflow': self.overflow,
                'profilers_restored': self.restored, 'refusal_code': refusal, 'tasks': records}


def selected_local_work(failure: BaseException, *, task_retirement=None):
    """Observe only an already-selected original; never wait or invoke it."""
    product = sys.modules.get('actql_sdk._local_product')
    core_module = sys.modules.get('actql_sdk._local_core')
    work_module = sys.modules.get('actql_sdk._local_work')
    if product is None or core_module is None or work_module is None:
        return None
    host_type = vars(product).get('InstalledLocalHost')
    reference_type = vars(product).get('_OriginalRunReference')
    core_type = vars(core_module).get('LocalCore')
    input_type = vars(core_module).get('_Input')
    physical_type = vars(core_module).get('_PhysicalInput')
    work_type = vars(work_module).get('OriginalLocalWork')
    if not all(type(value) is type for value in
               (host_type, reference_type, core_type, input_type, physical_type, work_type)):
        return None
    async_module = sys.modules.get('actql_sdk._async')
    async_fields = vars(async_module) if type(async_module) is ModuleType else {}
    execution_type, client_type = (async_fields.get('AsyncExecution'), async_fields.get('AsyncClient'))
    observe = vars(execution_type).get('_observe') if type(execution_type) is type else None
    observe_code = observe.__code__ if type(observe) is FunctionType else None
    frames = deque(traceback.walk_tb(failure.__traceback__), maxlen=MAX_FRAMES)
    for frame, _ in frames:
        admission = None
        if frame.f_code is host_type.open.__code__:
            host, payload = frame.f_locals.get('self'), frame.f_locals.get('payload')
            operation = frame.f_locals.get('operation')
            if (type(payload) is not bytes or len(payload) > MAX_SELECTION_BYTES
                    or type(operation) is not str
                    or operation not in ('status', 'wait', 'cancel', 'lookup-cancellation')):
                continue
        elif observe_code is not None and frame.f_code is observe_code:
            execution = frame.f_locals.get('self')
            operation, body = frame.f_locals.get('operation'), frame.f_locals.get('body')
            if (type(execution) is not execution_type or type(client_type) is not type
                    or type(operation) is not str or operation != 'wait'
                    or type(body) is not dict or body.get('since') is not None
                    or frame.f_locals.get('accepted') is not False):
                continue
            client = vars(execution).get('_client')
            if type(client) is not client_type:
                continue
            client_fields = vars(client)
            host = client_fields.get('_local_host')
            if client_fields.get('_transport') is not host:
                continue
            admission = vars(execution).get('_admission')
            if type(admission) is not MappingProxyType:
                continue
        else:
            continue
        if type(host) is not host_type:
            continue
        fields = vars(host)
        core = fields.get('_core')
        if fields.get('_original') is not host or type(core) is not core_type:
            continue
        state = vars(core)
        references, works, inputs = (fields.get('_public_run_references'),
                                    fields.get('_physical_work'), state.get('_inputs'))
        bits = {'observed_after_consumer_failure': True,
                'host_closing': fields.get('_closing') if type(fields.get('_closing')) is bool else None,
                'core_closing': state.get('_closing') if type(state.get('_closing')) is bool else None,
                'installation_present': fields.get('_installation') is not None,
                'selected': False}
        if (type(references) is not list or type(works) is not list or type(inputs) is not dict
                or len(references) > MAX_WORK_RECORDS or len(works) > MAX_WORK_RECORDS):
            return bits, []
        if admission is None:
            requested = json.loads(payload).get('ref')
        else:
            # The same SDK constructor froze this admission. Its reference is
            # only a bounded locator for the retained original below, never
            # authority from the rejected response or a replacement Run.
            reference = admission.get('ref')
            if type(reference) is not MappingProxyType or not 0 < len(reference) <= MAX_WORK_RECORDS:
                return bits, []
            requested = {}
            selection_characters = 0
            for key, value in reference.items():
                if (type(key) is not str or type(value) is not str
                        or len(key) > MAX_LABEL or len(value) > 4096):
                    return bits, []
                selection_characters += len(key) + len(value)
                if selection_characters > 4096:
                    return bits, []
                requested[key] = value
            encoded_reference = json.dumps(requested, ensure_ascii=False)
            if len(encoded_reference) > 4096 or len(encoded_reference.encode('utf-8')) > 4096:
                return bits, []
            bits.update(rejected_wait=True, wait_status_known=None, wait_status_stable=None)
            # Observe the retained rejected frame and classify its bounded DATA
            # with the original pure schema codec. No Host/Core port is called.
            value = frame.f_locals.get('value')
            wire = async_fields.get('wire')
            wire_fields = vars(wire) if type(wire) is ModuleType else {}
            contract, schemas = wire_fields.get('CONTRACT'), wire_fields.get('SCHEMAS')
            rules = contract.get('request_response_rules') if type(contract) is dict else None
            rule = rules.get('run_wait') if type(rules) is dict else None
            stable = rule.get('stableStatuses') if type(rule) is dict else None
            schema = schemas.get('run_state') if type(schemas) is dict else None
            properties = schema.get('properties') if type(schema) is dict else None
            status_schema = properties.get('status') if type(properties) is dict else None
            known = status_schema.get('enum') if type(status_schema) is dict else None
            status = value.get('status') if type(value) is dict else None
            if type(status) is str and len(status) <= MAX_LABEL:
                for label, choices in (('wait_status_known', known), ('wait_status_stable', stable)):
                    if (type(choices) is list and len(choices) <= MAX_WORK_RECORDS
                            and all(type(item) is str and len(item) <= MAX_LABEL for item in choices)):
                        bits[label] = status in choices
            bits.update(rejected_wait_shape(value, body, wire_fields))
            bits['wait_original_cancellation_kind'] = same_frame_cancellation_kind(
                frames, requested, wire_fields)
        if type(requested) is not dict:
            return bits, []
        matches = []
        for reference in references:
            if type(reference) is not reference_type or type(reference.source) is not input_type:
                return bits, []
            source = reference.source
            physical = inputs.get(source.ticket)
            if (source.owner is not state.get('_identity') or type(physical) is not physical_type
                    or type(physical.payload) is not bytes or len(physical.payload) > 4096):
                return bits, []
            if json.loads(physical.payload) == requested:
                matches.append(reference.run)
        if len(matches) != 1:
            return bits, []
        selected = [work for work in works if type(work) is work_type
                    and vars(work).get('_original') is work
                    and vars(work).get('_owner') is matches[0]]
        if len(selected) != 1:
            return bits, []
        work = vars(selected[0])
        future = work.get('_future')
        if type(future) is not Future:
            return bits, []
        bits.update(selected=True, future_done=future.done())
        if not bits['future_done'] or future.cancelled():
            return bits, []
        # timeout=0 cannot wait for completion. This reads the retained object;
        # no public status, cleanup, physical call or exception formatter runs.
        original = future.exception(timeout=0)
        errors = [(original, 'physical-original'),
                  (work.get('_cleanup_error'), 'physical-cleanup'),
                  (work.get('_exit_error'), 'physical-exit')]
        if type(task_retirement) is _TaskRetirementObservation:
            bits['task_retirement'] = task_retirement.snapshot(selected[0])
        return bits, [(error, role) for error, role in errors if isinstance(error, BaseException)]
    return None


def captured_task_retirement(failure: BaseException, observer):
    """Associate existing samples, never reconstruct current debt after close."""
    if type(observer) is not _TaskRetirementObservation:
        return None
    samples = vars(observer).get('samples')
    if type(samples) is not list or len(samples) != MAX_WORK_RECORDS:
        return None
    modules = [sys.modules.get(name) for name in
               ('actql_sdk._local_product', 'actql_sdk._local_core', 'actql_sdk._local_work')]
    if not all(type(module) is ModuleType for module in modules):
        return None
    product, core_module, work_module = map(vars, modules)
    pending, stop_type, execution_type = (product.get('LocalProductCleanupPending'),
        product.get('_OriginalCancellationStop'), product.get('_OriginalExecution'))
    host_type, core_type, work_type = (product.get('InstalledLocalHost'),
        core_module.get('LocalCore'), work_module.get('OriginalLocalWork'))
    if not all(type(kind) is type for kind in
               (pending, stop_type, execution_type, host_type, core_type, work_type)):
        return None
    run_method, invoke_method = vars(work_type).get('_run'), vars(execution_type).get('__call__')
    if (type(failure) is not pending or type(failure.__context__) is not stop_type
            or type(run_method) is not FunctionType or type(invoke_method) is not FunctionType):
        return None
    # Bound visits as well as storage. Missing frames leave evidence unavailable.
    frames = tuple(islice(traceback.walk_tb(failure.__traceback__), MAX_FRAMES))
    for frame, _ in frames:
        if frame.f_code is not run_method.__code__ or frame.f_locals.get('failure') is not failure:
            continue
        work = frame.f_locals.get('self')
        if type(work) is not work_type or vars(work).get('_original') is not work:
            continue
        fields = vars(work)
        original, future = fields.get('_invoke'), fields.get('_future')
        if (type(original) is not execution_type or type(future) is not Future
                or vars(future).get('_exception') is not failure
                or fields.get('_owner') is not original.run
                or failure.__context__.original is not original):
            continue
        host = original.host
        if (type(host) is not host_type or vars(host).get('_original') is not host
                or type(vars(host).get('_core')) is not core_type
                or vars(failure).get('cleanup_host') is not host
                or not any(other.f_code is invoke_method.__code__
                           and other.f_locals.get('self') is original
                           and other.f_locals.get('work') is work for other, _ in frames)):
            continue
        return {'association': 'same-original-worker-traceback',
                'sample_timing': 'original-task-close-return-before-worker-exit',
                'live_selection': False, 'snapshot': observer.snapshot(work)}
    return None


def report_contexts(failure: BaseException, stream, *, task_retirement=None) -> None:
    seen: set[int] = set()
    pending = [(failure, None)]
    emitted = 0
    while pending and len(seen) < MAX_CONTEXTS:
        current, role = pending.pop()
        if id(current) in seen:
            continue
        seen.add(id(current))
        frames = [{'file': Path(frame.f_code.co_filename).name[:MAX_LABEL], 'line': line,
                   'function': frame.f_code.co_name[:MAX_LABEL]}
                  for frame, line in deque(traceback.walk_tb(current.__traceback__), maxlen=MAX_FRAMES)]
        record = {'stage': 'installed-consumer-failure-location',
                  'exception_type': type(current).__name__[:MAX_LABEL], 'frames': frames}
        try:
            captured = captured_task_retirement(current, task_retirement)
        except BaseException:
            # Optional evidence must not format or replace the original failure.
            captured = None
        if captured is not None:
            record['captured_task_retirement'] = captured
        if role is not None:
            record['failure_role'] = role
        try:
            selected = selected_local_work(current, task_retirement=task_retirement)
        except Exception:
            # A changed/malformed diagnostic snapshot never interrupts the
            # original bounded exception-chain report or changes its failure.
            selected = None
        if selected is not None:
            record['local_work'] = selected[0]
            pending.extend(reversed(selected[1]))
        fields = vars(current)
        # The current failure is hidden behind retained cleanup carriers. Read
        # only the known SDK exception's own plain status; never stringify its
        # message, an arbitrary operation, or a foreign diagnostic object.
        if (type(current).__module__ == 'actql_sdk._local_core'
                and type(current).__name__ == 'LocalCoreError'
                and type(fields.get('operation')) is str
                and type(fields.get('code')) is int
                and -(1 << 31) <= fields['code'] < (1 << 31)):
            if fields['operation'] == 'seal':
                record['core_buffer_seal_code'] = fields['code']
            elif role == 'physical-original' and fields['operation'] == 'task_drive':
                record['core_task_drive_code'] = fields['code']
        wire = json.dumps(record) + '\n'
        emitted += len(wire.encode('utf-8'))
        if emitted > MAX_OUTPUT_BYTES:
            break
        stream.write(wire)
        stream.flush()
        # Submission and context exit retain the original/cleanup exceptions
        # outside their native chains. Read only existing plain exception
        # associations; the same seen/output bounds apply and no error changes.
        retained = fields.get('original_error')
        cleanup = fields.get('cleanup_error')
        for linked in (current.__context__, current.__cause__, retained, cleanup):
            if isinstance(linked, BaseException):
                pending.append((linked, None))


def run_consumer(target: Path) -> None:
    # Only these original failed cases select the optional observation. Existing
    # profilers are never replaced, and setup failure cannot prevent execution.
    args = sys.argv[1:]
    selected = target.name == 'python-product-installed.py' and all(
        args.count(flag) == 1 and args.index(flag) + 1 < len(args)
        and args[args.index(flag) + 1] in expected
        for flag, expected in (('--mode', ('local',)), ('--facade', ('sync', 'async')),
                               ('--case', ('cancellation',)), ('--phase', ('initial',))))
    observer = None
    if selected:
        try:
            observer = _TaskRetirementObservation()
            observer.__enter__()
        except BaseException:
            observer = None
    try:
        try:
            runpy.run_path(str(target), run_name='__main__')
        finally:
            if observer is not None:
                try:
                    observer.__exit__(None, None, None)
                except BaseException:
                    observer.failed = True
        # The profiler is returned before any diagnostics or further execution.
    except Exception as failure:
        try:
            report_contexts(failure, sys.stderr, task_retirement=observer)
        except Exception:
            # Diagnostics must never replace the original failure or retry it.
            pass
        raise


def main() -> None:
    target = Path(sys.argv[1]).resolve(strict=True)
    sys.argv = sys.argv[1:]
    run_consumer(target)


if __name__ == '__main__':
    main()
