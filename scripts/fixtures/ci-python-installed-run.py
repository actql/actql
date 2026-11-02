"""Observe suppressed failure locations without changing installed consumer behavior.

Only CI copies this wrapper outside the repository. It never prints exception
messages, locals, reference values, source lines, or full paths. Public Unknown
semantics and the original exception are retained; no operation is repeated.
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
        wire = json.dumps({'stage': 'installed-consumer-failure-location',
                           'exception_type': type(current).__name__[:MAX_LABEL], 'frames': frames}) + '\n'
        emitted += len(wire.encode('utf-8'))
        if emitted > MAX_OUTPUT_BYTES:
            break
        stream.write(wire)
        stream.flush()
        for linked in (current.__context__, current.__cause__):
            if linked is not None:
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
