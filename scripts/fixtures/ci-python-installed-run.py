"""Observe suppressed failure locations without changing installed consumer behavior.

Only CI copies this wrapper outside the repository. It never prints exception
messages, locals, reference values, source lines, or full paths. The known Core
buffer seal failure may report its original signed ABI status, without decoding
it into a business outcome. Public Unknown semantics and the original exception
are retained; no operation is repeated.
"""
from __future__ import annotations

from collections import deque
import json
from pathlib import Path
import runpy
import sys
import traceback


MAX_CONTEXTS = 16
MAX_FRAMES = 32
MAX_LABEL = 128
MAX_OUTPUT_BYTES = 65536


def report_contexts(failure: BaseException, stream) -> None:
    seen: set[int] = set()
    pending = [failure]
    emitted = 0
    while pending and len(seen) < MAX_CONTEXTS:
        current = pending.pop()
        if id(current) in seen:
            continue
        seen.add(id(current))
        frames = [{'file': Path(frame.f_code.co_filename).name[:MAX_LABEL], 'line': line,
                   'function': frame.f_code.co_name[:MAX_LABEL]}
                  for frame, line in deque(traceback.walk_tb(current.__traceback__), maxlen=MAX_FRAMES)]
        record = {'stage': 'installed-consumer-failure-location',
                  'exception_type': type(current).__name__[:MAX_LABEL], 'frames': frames}
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
                pending.append(linked)


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
