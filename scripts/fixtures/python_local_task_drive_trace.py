"""Closed diagnostic phases for the existing raw mixed-task control only."""
import json
import sys
import time


class MixedTaskDriveTrace:
    _PHASES = frozenset({
        'fixture-start', 'first-core-begin', 'first-core-ready', 'first-host-ready',
        'execution-begin', 'submission-returned', 'terminal-returned', 'result-checked',
        'first-cleanup-begin', 'first-cleanup-returned', 'saved-core-begin',
        'saved-core-ready', 'saved-host-ready', 'saved-read-begin', 'saved-read-checked',
        'saved-cleanup-begin', 'saved-cleanup-returned',
    })

    def __init__(self, *, stream=None, clock=time.monotonic):
        self._stream = sys.stderr if stream is None else stream
        self._clock = clock
        self._started = clock()
        self._seen = set()

    def mark(self, phase):
        if type(phase) is not str or phase not in self._PHASES or phase in self._seen:
            raise ValueError('Unknown or repeated mixed-task diagnostic phase')
        self._seen.add(phase)
        record = {'stage': 'task-drive-phase', 'phase': phase,
                  'elapsed_seconds': round(self._clock() - self._started, 3)}
        try:
            self._stream.write(json.dumps(record) + '\n')
            self._stream.flush()
        except Exception:
            # Optional reporting must not replace original execution/cleanup.
            pass
