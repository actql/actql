"""Imported Host wait assembly with explicit observation/current/stop ports.

No VM, physical worker, Account admission, SQLite ACK or installed acceptance.
The state fixtures are independent DATA; the real generated wait predicate is
used. Physical completion below is a port, never evidence of Common retirement.
"""
import asyncio
from contextlib import nullcontext
import json
from threading import RLock
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from actql_sdk import _wire as wire
from actql_sdk._local_product import (
    InstalledLocalHost, LocalProductCleanupPending, _OriginalExecution, _LOCAL_SELECTION,
)
from actql_sdk._local_storage import LocalStorageCommitUnknown
from actql_sdk._local_work import OriginalLocalWork
from actql_sdk._values import wire_bytes


RUNNING = {'version': 'actql-run-state/0.1', 'run_id': 'original-port-run',
    'revision': 2, 'status': 'running', 'updated_at': '2026-11-19T00:00:00.000Z',
    'next_action': {'kind': 'none'}, 'result_available': False,
    'result_availability': {}}
CANCELLED = RUNNING | {'status': 'cancelled'}


class LocalWaitReadinessTests(unittest.IsolatedAsyncioTestCase):
    def bridge(self, state=RUNNING):
        host = InstalledLocalHost.__new__(InstalledLocalHost)
        run = SimpleNamespace(handle=17)
        reference = {'fixture': 'same retained reference DATA, not an admission'}
        source, output, current = object(), SimpleNamespace(ticket=19), object()
        events, streams = [], []
        options = {'state': state, 'close': True, 'kind': 'retained',
                   'confirm_error': None, 'commit_error': None}
        core = SimpleNamespace(_lock=RLock(), _loans={output.ticket: output})
        host._core = core
        host._configuration = SimpleNamespace(handle=13, sdk=True)
        host._state_observing = False
        host._run_state_custody = {}
        host._physical_work = []
        host._run_publications = []
        host._commit_projections = []
        host._projections = []
        host._append_sources = {}
        host._response_streams = set()
        host._now = lambda: 0
        host._reserve = lambda acquire: acquire()
        host._copy = lambda _: source

        def inspect(consume):
            events.append('current')
            return consume(current)

        def commit(writes, fences, *, inspect, current):
            events.append('commit')
            inspect(object())
            if options['commit_error'] is not None:
                raise options['commit_error']
            return object()

        store = SimpleNamespace(namespaced_key=lambda *args: '/'.join(args),
            compare_exchange_many_inspected=commit)
        binding = SimpleNamespace(inspect=inspect, fenced=lambda: nullcontext(()),
            inspect_reader=lambda reader, consume: consume(current),
            _current_observer=lambda: None)
        installation = SimpleNamespace(_store=store, binding=binding)
        host._active = lambda: installation

        def selected(candidate):
            self.assertIs(candidate, reference)
            events.append('authorized-original')
            return run, object()

        host._select_original_run = selected
        host._has_live_original_run_reference = lambda _: True
        host._runs = SimpleNamespace(_run=lambda candidate: self.assertIs(candidate, run))
        core.reserve_submission_projection = lambda *args, **kwargs: output
        core.produce_unpublished_state = lambda *args: events.append('produce')
        core.validate_unpublished_state = lambda *args: events.append('validate')

        def read(*args):
            events.append('read')
            return wire_bytes({'kind': options['kind'], 'key': 'original-key',
                'revision': '2', 'body': 'same original metadata',
                'state': wire_bytes(options['state']).decode()})

        core.read_unpublished_state = read
        core.read_unpublished_state_candidate = lambda *args: (events.append('candidate'), read())[1]

        def confirm(*args):
            events.append('confirm')
            if options['confirm_error'] is not None:
                raise options['confirm_error']

        core.confirm_unpublished_state = confirm

        def close(candidate):
            self.assertIs(candidate, output)
            events.append('close')
            if options['close']:
                core._loans.pop(output.ticket, None)
            return options['close']

        host._close_projection = close

        class Stream:
            def __init__(self, owner, raw, **kwargs):
                self._attached = False
                self.raw = raw
                streams.append(self)

            def _close(self):
                events.append('stream-close')
                return True

        original_stream = patch('actql_sdk._local_product.OriginalLocalResponseStream', Stream)
        original_stream.start()
        self.addCleanup(original_stream.stop)
        return host, core, run, reference, options, events, streams

    def work(self, host, run, *, primary=None, exit_error=None, cleanup=None):
        original = _OriginalExecution(host, run)
        work = OriginalLocalWork(original, owner=run)
        # Explicit completed physical-work port. No thread is started here.
        work._invoked = True
        if primary is None:
            work._future.set_result(None)
        else:
            work._future.set_exception(primary)
        work._exit_error, work._cleanup_error = exit_error, cleanup
        host._physical_work.append(work)
        return work

    def observe(self, host, reference, operation='wait'):
        return host._open_operation_locked(operation,
            {'ref': reference, 'until': 'terminal', 'since': None})

    async def test_stopped_unpublished_running_is_not_a_wait_response_or_a_retry_loop(self):
        self.assertTrue(wire.valid(RUNNING, 'run_state'))
        self.assertFalse(wire.valid_run_wait(RUNNING, None))
        host, _, run, reference, _, events, streams = self.bridge()
        work = self.work(host, run)
        self.assertTrue(work.stopped)
        with self.assertRaisesRegex(ValueError, 'wait condition supplier is unavailable'):
            self.observe(host, reference)
        self.assertEqual(events.count('produce'), 1)
        self.assertEqual(events.count('confirm'), 1)
        self.assertEqual(events.count('close'), 1)
        self.assertFalse(streams)
        self.assertFalse(host._run_state_custody)
        self.assertIs(host._physical_work[0], work)
        self.assertIs(work._owner, run)

    async def test_ready_common_bytes_and_generated_predicate_are_used_unchanged(self):
        self.assertTrue(wire.valid_run_wait(CANCELLED, None))
        host, _, run, reference, _, events, streams = self.bridge(CANCELLED)
        self.work(host, run)
        response = self.observe(host, reference)
        self.assertIs(response.stream, streams[0])
        self.assertTrue(streams[0]._attached)
        self.assertEqual(streams[0].raw, wire_bytes(CANCELLED))
        self.assertEqual(events.count('confirm'), 1)
        with patch.object(wire, 'valid_run_wait', return_value=False) as predicate:
            with self.assertRaises(ValueError):
                self.observe(host, reference)
        predicate.assert_called_once_with(CANCELLED, None)
        self.assertEqual(len(streams), 1)

    async def test_authorization_precedes_same_worker_primary_and_foreign_errors_never_escape(self):
        class OpaqueError(Exception):
            def __str__(self):
                raise AssertionError('Original error must not be formatted')

        for kind in ('physical', 'exit', 'cleanup'):
            with self.subTest(kind=kind):
                host, _, run, reference, _, events, streams = self.bridge()
                primary, cleanup = OpaqueError(), OpaqueError()
                work = self.work(host, run, primary=primary if kind == 'physical' else None,
                    exit_error=primary if kind == 'exit' else None,
                    cleanup=primary if kind == 'cleanup' else cleanup)
                with self.assertRaises(OpaqueError) as failed:
                    self.observe(host, reference)
                self.assertIs(failed.exception, primary)
                self.assertEqual(events, ['authorized-original'])
                self.assertFalse(streams)
                self.assertIs(work._cleanup_error, primary if kind == 'cleanup' else cleanup)
                refused = ValueError('Original authorization refused')
                with patch.object(host, '_select_original_run', side_effect=refused):
                    with self.assertRaises(ValueError) as failed:
                        self.observe(host, reference)
                self.assertIs(failed.exception, refused)
                work._invoke.host = object()  # A foreign original is not this Run's error source.
                with self.assertRaisesRegex(ValueError, 'wait condition supplier is unavailable'):
                    self.observe(host, reference)
                self.assertIs(host._physical_work[0], work)

    async def test_status_still_returns_nonstable_common_data_despite_worker_error(self):
        host, _, run, reference, _, _, streams = self.bridge()
        self.work(host, run, primary=RuntimeError('physical port failure'))
        response = self.observe(host, reference, 'status')
        self.assertIs(response.stream, streams[0])
        self.assertEqual(json.loads(streams[0].raw), RUNNING)

    async def test_saved_and_published_wait_routes_apply_the_same_generated_readiness(self):
        for route in ('saved', 'published'):
            for state in (RUNNING, CANCELLED):
                with self.subTest(route=route, status=state['status']):
                    host, core, run, reference, _, events, streams = self.bridge(state)
                    if route == 'saved':
                        host._has_live_original_run_reference = lambda _: False

                        def read(candidate, *, kind):
                            self.assertIs(candidate, reference)
                            self.assertEqual(kind, 7)
                            events.append('authorized-saved')
                            return wire_bytes(state)

                        host._read_original_reference = read
                    else:
                        publication = object()
                        projection = SimpleNamespace(_configuration=host._configuration.handle,
                            _publication=publication)
                        host._run_publications = [(run, publication)]
                        host._commit_projections = [projection]
                        core.validate_publication_run = lambda *args: events.append('validate-publication')
                        host._ensure_original_publication_observation = lambda _: None
                        host._project_original_sdk_run_state = lambda original, candidate, consume: consume(wire_bytes(state))
                    if state is RUNNING:
                        with self.assertRaisesRegex(ValueError, 'wait condition supplier is unavailable'):
                            self.observe(host, reference)
                        self.assertFalse(streams)
                    else:
                        response = self.observe(host, reference)
                        self.assertIs(response.stream, streams[0])
                        self.assertEqual(streams[0].raw, wire_bytes(state))
                    self.assertTrue(events)

    async def test_current_refusal_and_partial_close_keep_same_candidate_without_a_response(self):
        host, _, run, reference, options, events, streams = self.bridge(CANCELLED)
        self.work(host, run)
        refusal = RuntimeError('Original current port refused')
        options['confirm_error'] = refusal
        with self.assertRaises(RuntimeError) as failed:
            self.observe(host, reference)
        self.assertIs(failed.exception, refusal)
        self.assertFalse(streams)

        host, _, run, reference, options, events, streams = self.bridge(CANCELLED)
        self.work(host, run)
        options['close'] = False
        with self.assertRaises(LocalProductCleanupPending):
            self.observe(host, reference)
        held = host._run_state_custody[run.handle]
        self.assertTrue(held.metadata_confirmed)
        self.assertFalse(streams)
        options['close'] = True
        self.observe(host, reference)
        self.assertEqual(events.count('produce'), 1)
        self.assertEqual(len(streams), 1)
        self.assertFalse(host._run_state_custody)

    async def test_commit_unknown_retains_same_candidate_without_reprepare_or_second_write(self):
        host, _, run, reference, options, events, streams = self.bridge(CANCELLED)
        self.work(host, run)
        options['kind'] = 'replace'
        unknown = LocalStorageCommitUnknown(object())
        options['commit_error'] = unknown
        with self.assertRaises(LocalStorageCommitUnknown) as failed:
            self.observe(host, reference)
        self.assertIs(failed.exception, unknown)
        held = host._run_state_custody[run.handle]
        self.assertIs(held.first_failure, unknown)
        self.assertTrue(held.write_attempted)
        self.assertFalse(streams)
        options['commit_error'] = None
        response = self.observe(host, reference)
        self.assertIs(response.stream, streams[0])
        self.assertEqual(events.count('produce'), 1)
        self.assertEqual(events.count('commit'), 1)
        self.assertEqual(events.count('candidate'), 1)

    async def test_cancelled_wait_releases_core_lock_and_retains_original_worker(self):
        host, core, run, reference, _, _, streams = self.bridge()
        original = _OriginalExecution(host, run)
        work = OriginalLocalWork(original, owner=run)
        work._invoked = True
        host._physical_work.append(work)
        host._find_original_run_reference = lambda _: SimpleNamespace(run=run)
        entered = asyncio.Event()

        async def waiting():
            self.assertFalse(core._lock._is_owned())
            entered.set()
            await asyncio.Event().wait()

        with patch.object(work, 'wait_stopped', side_effect=waiting), patch.object(
                wire, 'valid_body', return_value=True):
            task = asyncio.create_task(host.open('wait', wire_bytes({
                'connection': _LOCAL_SELECTION, 'ref': reference, 'until': 'terminal', 'since': None})))
            # Explicit request-admission port above; no real Account/Run admission.
            await asyncio.wait_for(entered.wait(), 1)
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task
        self.assertFalse(core._lock._is_owned())
        self.assertFalse(work._future.done())
        self.assertIs(host._physical_work[0], work)
        self.assertFalse(streams)
