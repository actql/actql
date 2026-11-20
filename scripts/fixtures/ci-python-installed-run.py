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
import json
from pathlib import Path
import runpy
import sys
import traceback
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


def post_close_task_snapshot(host, work):
    """Read bounded scalar evidence, never another close or an historical arm.

    Only the same finished original worker's retained tasks are selected. No
    guest entry runs while another thread holds the Core lock. Observation is
    optional: its refusal/failure cannot replace the original consumer error.
    """
    result = {'scope': 'post-close-current-snapshot', 'available': False,
              'lock_busy': False, 'observation_failed': False,
              'refusal_code': None, 'tasks': []}
    try:
        product = sys.modules.get('actql_sdk._local_product')
        core_module = sys.modules.get('actql_sdk._local_core')
        work_module = sys.modules.get('actql_sdk._local_work')
        if not all(type(module) is ModuleType for module in (product, core_module, work_module)):
            return result
        host_type, original_type = (vars(product).get('InstalledLocalHost'),
                                    vars(product).get('_OriginalExecution'))
        core_type, task_type = (vars(core_module).get('LocalCore'), vars(core_module).get('_Task'))
        work_type = vars(work_module).get('OriginalLocalWork')
        if (type(host) is not host_type or type(work) is not work_type
                or vars(host).get('_original') is not host or vars(work).get('_original') is not work):
            return result
        core, original = vars(host).get('_core'), vars(work).get('_invoke')
        future = vars(work).get('_future')
        if (type(core) is not core_type or type(original) is not original_type
                or original.host is not host or original.run is not vars(work).get('_owner')
                or type(future) is not Future or not future.done() or future.cancelled()):
            return result
        lock = vars(core).get('_lock')
        if type(lock) is not _thread.RLock or '_call' in vars(core):
            return result
        if not lock.acquire(blocking=False):
            result['lock_busy'] = True
            return result
        try:
            tasks, loans = original.tasks, vars(core).get('_task_loans')
            if (type(tasks) is not list or len(tasks) > MAX_WORK_RECORDS
                    or type(loans) is not dict):
                return result
            observations = []
            for task in tasks:
                if (type(task) is not task_type or task.owner is not vars(core).get('_identity')
                        or type(task.handle) is not int or task.handle <= 0):
                    return result
                if loans.get(task.handle) is not task:
                    continue  # Already returned originals need no guest observation.
                # These existing scalar ports return no handles, rows or error
                # payloads. Keep execution and cleanup causes independent; the
                # Common classifier alone defines their numeric vocabulary.
                stage = core._call('task', 'progress', task.handle, 6)
                cleanup = core._call('task', 'progress', task.handle, 7)
                issue = core._call('task', 'issue', task.handle)
                if any(type(code) is not int or not -(1 << 31) <= code < (1 << 31)
                       for code in (stage, cleanup, issue)):
                    return result
                if stage < 0 or cleanup < 0:
                    result['refusal_code'] = stage if stage < 0 else cleanup
                    return result
                observations.append({'stage_code': stage,
                    'execution_issue_code': issue, 'cleanup_issue_code': cleanup})
            result['tasks'] = observations
            result['available'] = True
        finally:
            lock.release()
    except BaseException:
        # No formatter or exception payload is copied. Same pending custody,
        # initiating error and first public close remain owned by their callers.
        result['observation_failed'] = True
    if not result['available']:
        result['tasks'].clear()
    return result


def selected_local_work(failure: BaseException, *, task_retirement=False):
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
        if task_retirement:
            bits['task_retirement'] = post_close_task_snapshot(host, selected[0])
        return bits, [(error, role) for error, role in errors if isinstance(error, BaseException)]
    return None


def report_contexts(failure: BaseException, stream, *, task_retirement=False) -> None:
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
        # Local submission preserves its original failure as a retained
        # exception attribute before raising outside the except block. Read
        # only that known exception carrier, never arbitrary diagnostic values.
        retained = fields.get('original_error')
        for linked in (current.__context__, current.__cause__, retained):
            if isinstance(linked, BaseException):
                pending.append((linked, None))


def run_consumer(target: Path) -> None:
    try:
        runpy.run_path(str(target), run_name='__main__')
    except Exception as failure:
        try:
            # Only the existing failed installed sync cancellation initial case
            # selects the optional task snapshot. Other acceptance paths keep
            # their existing failure report and perform no extra Core calls.
            args = sys.argv[1:]
            selected = target.name == 'python-product-installed.py' and all(
                args.count(flag) == 1 and args.index(flag) + 1 < len(args)
                and args[args.index(flag) + 1] == expected
                for flag, expected in (('--mode', 'local'), ('--facade', 'sync'),
                                       ('--case', 'cancellation'), ('--phase', 'initial')))
            report_contexts(failure, sys.stderr, task_retirement=selected)
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
