"""Observe suppressed failure locations without changing installed consumer behavior.

Only CI copies this wrapper outside the repository. It never prints exception
messages, locals, reference values, source lines, or full paths. The known Core
buffer seal failure may report its original signed ABI status, without decoding
it into a business outcome. Public Unknown semantics and the original exception
are retained; no operation is repeated.
"""
from __future__ import annotations

from collections import deque
from concurrent.futures import Future
import json
from pathlib import Path
import runpy
import sys
import traceback


MAX_CONTEXTS = 16
MAX_FRAMES = 32
MAX_LABEL = 128
MAX_OUTPUT_BYTES = 65536
MAX_WORK_RECORDS = 16
MAX_SELECTION_BYTES = 16384


def selected_local_work(failure: BaseException):
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
    frames = deque(traceback.walk_tb(failure.__traceback__), maxlen=MAX_FRAMES)
    for frame, _ in frames:
        if frame.f_code is not host_type.open.__code__:
            continue
        host, payload = frame.f_locals.get('self'), frame.f_locals.get('payload')
        operation = frame.f_locals.get('operation')
        if (type(host) is not host_type or type(payload) is not bytes
                or len(payload) > MAX_SELECTION_BYTES
                or type(operation) is not str
                or operation not in ('status', 'wait', 'cancel', 'lookup-cancellation')):
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
        requested = json.loads(payload).get('ref')
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
        return bits, [(error, role) for error, role in errors if isinstance(error, BaseException)]
    return None


def report_contexts(failure: BaseException, stream) -> None:
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
            selected = selected_local_work(current)
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
                and fields.get('operation') == 'seal'
                and type(fields.get('code')) is int
                and -(1 << 31) <= fields['code'] < (1 << 31)):
            record['core_buffer_seal_code'] = fields['code']
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
            report_contexts(failure, sys.stderr)
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
