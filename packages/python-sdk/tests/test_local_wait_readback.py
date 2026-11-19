"""Actual worker/Host recovery callers with explicit Store/Core readback ports.

No physical thread, VM, SQLite transaction or installed acceptance. The
publication exception handler and existing ensure/advance/read response callers
are imported intact; index/current/read admission remain explicit ports.
"""
from concurrent.futures import Future
import copy
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from actql_sdk import _wire as wire
from actql_sdk._local_storage import LocalStorageCommitUnknown
from actql_sdk._local_product import LocalProductCleanupPending
from actql_sdk._values import wire_bytes
import test_local_wait_readiness as readiness_fixture


SUCCEEDED = readiness_fixture.RUNNING | {'status': 'succeeded'}


class LocalWaitReadbackTests(unittest.IsolatedAsyncioTestCase):
    def bridge(self):
        fixture = readiness_fixture.LocalWaitReadinessTests()
        self.addCleanup(fixture.doCleanups)
        host, core, run, reference, options, events, streams = fixture.bridge(SUCCEEDED)
        work = fixture.work(host, run)
        original = work._invoke
        publication, publisher, preflight = SimpleNamespace(ticket=31), object(), object()
        projection = SimpleNamespace(_publication=publication,
            _configuration=host._configuration.handle)
        original.reference = object()
        original.publication, original.publisher = publication, publisher
        host._run_publications = [(run, publication)]
        host._commit_projections = [projection]
        host._source_free_computes = []
        host._publishers = [publisher]
        host._store_observations = {}
        host._publication_write_attempts = set()
        host._pending_publication_write = host._pending_publication_publisher = None
        host._current_execution = lambda: original
        host._configure_original_compute = lambda _: object()
        host._prepare_original_publication = lambda _: (preflight, publisher)
        host._execute_original_tasks = lambda *args, **kwargs: ()
        host._capture_original_results = lambda *args: publication
        host._prepare_original_commit_candidate = lambda *args: None
        host._advance_original_commit_candidate = lambda _: projection
        host._handoff_original_step = lambda owner, value: value
        host._original_commit_reader_facts = lambda _: ()
        store = host._active()._store
        lost_reply = LocalStorageCommitUnknown(store)

        def commit(candidate, facts, originals, selected_publisher):
            self.assertIs(candidate, projection)
            self.assertIs(selected_publisher, publisher)
            events.append('single-store-attempt')
            host._publication_write_attempts.add(publication.ticket)
            host._pending_publication_write = projection
            host._pending_publication_publisher = publisher
            raise lost_reply

        host._store_original_commit = commit
        work._future = Future()
        # Invoke the actual worker and exception handler without starting a
        # thread. This physical-stop port is not Common retirement evidence.
        work._run()
        self.assertIs(work._future.exception(), lost_reply)
        self.assertIsNotNone(work._cleanup_error)
        blocked_cleanup = work._cleanup_error
        options.update(action='adopt_committed_index', index_error=None,
            read_error=None, post_error=None)

        def prepare(candidate, selected_publisher):
            self.assertIs(candidate, projection)
            self.assertIs(selected_publisher, publisher)

            def index(consume):
                events.append('full-original-index')
                if options['index_error'] is not None:
                    raise options['index_error']
                consume(b'original index identity DATA', b'complete original index DATA')

            observation = SimpleNamespace(_projection=projection, _publisher=publisher,
                advance=lambda _: SimpleNamespace(ready=True),
                finish=lambda: options['action'], project_observed_index=index)
            host._store_observations[publication.ticket] = observation

        host._prepare_original_store_observation = prepare
        core.validate_publication_run = lambda *args: events.append('nominal-publication')

        def state(owner, candidate, consume):
            self.assertIs(owner, run)
            self.assertIs(candidate, projection)
            events.append('protected-run-read')
            if options['read_error'] is not None:
                raise options['read_error']
            consume(wire_bytes(SUCCEEDED))
            events.append('post-current')
            if options['post_error'] is not None:
                raise options['post_error']

        host._project_original_sdk_run_state = state
        return (fixture, host, core, run, reference, projection, publisher,
                work, lost_reply, blocked_cleanup, options, events, streams)

    async def test_same_reply_loss_resolved_by_original_readback_can_return_the_committed_wait(self):
        self.assertTrue(wire.valid_run_wait(SUCCEEDED, None))
        (fixture, host, _, _, reference, projection, _, work,
         lost_reply, blocked_cleanup, _, events, streams) = self.bridge()
        response = fixture.observe(host, reference)
        self.assertIs(response.stream, streams[0])
        self.assertEqual(streams[0].raw, wire_bytes(SUCCEEDED))
        self.assertEqual(events.count('single-store-attempt'), 1)
        self.assertLess(events.index('full-original-index'), events.index('protected-run-read'))
        self.assertLess(events.index('protected-run-read'), events.index('post-current'))
        self.assertIsNone(host._pending_publication_write)
        self.assertIs(work._future.exception(), lost_reply)
        self.assertIs(work._cleanup_error, blocked_cleanup)
        self.assertIs(host._commit_projections[0], projection)
        self.assertIs(host._physical_work[0], work)

    async def test_action_without_original_index_and_failed_index_never_resolve_reply_loss(self):
        for phase in ('action-only', 'index-refused'):
            with self.subTest(phase=phase):
                (fixture, host, _, _, reference, projection, _, work,
                 lost_reply, blocked_cleanup, options, _, streams) = self.bridge()
                refusal = ValueError('Original index export refused')
                if phase == 'action-only':
                    options['action'] = 'confirm_uncommitted_failure'
                else:
                    options['index_error'] = refusal
                with self.assertRaises(LocalStorageCommitUnknown if phase == 'action-only' else ValueError) as failed:
                    fixture.observe(host, reference)
                self.assertIs(failed.exception, lost_reply if phase == 'action-only' else refusal)
                self.assertIs(host._pending_publication_write, projection)
                self.assertIs(work._future.exception(), lost_reply)
                self.assertIs(work._cleanup_error, blocked_cleanup)
                self.assertFalse(streams)

    async def test_exact_attempt_error_store_projection_publisher_and_cleanup_identity_are_required(self):
        for changed in ('missing', 'projection', 'publisher', 'error', 'marker', 'store', 'cleanup'):
            with self.subTest(changed=changed):
                (fixture, host, _, _, reference, _, _, work,
                 lost_reply, _, _, _, streams) = self.bridge()
                original = work._invoke
                held = original.publication_reply_loss
                self.assertIs(held[2], lost_reply)
                if changed == 'missing':
                    original.publication_reply_loss = None
                elif changed in ('projection', 'publisher', 'error', 'marker'):
                    values = list(held)
                    slot = {'projection': 0, 'publisher': 1, 'error': 2, 'marker': 3}[changed]
                    values[slot] = (copy.copy(held[0]) if changed == 'projection' else
                        LocalStorageCommitUnknown(lost_reply.cleanup_store) if changed == 'error' else
                        LocalProductCleanupPending(host) if changed == 'marker' else object())
                    original.publication_reply_loss = tuple(values)
                elif changed == 'store':
                    lost_reply.cleanup_store = object()
                else:
                    work._cleanup_error = LocalProductCleanupPending(host)
                genuine_cleanup = work._cleanup_error
                with self.assertRaises(LocalStorageCommitUnknown) as failed:
                    fixture.observe(host, reference)
                self.assertIs(failed.exception, lost_reply)
                self.assertIs(work._future.exception(), lost_reply)
                self.assertIs(work._cleanup_error, genuine_cleanup)
                self.assertFalse(streams)

    async def test_protected_read_post_current_and_independent_exit_error_are_not_suppressed(self):
        for phase in ('read', 'post-current', 'exit'):
            with self.subTest(phase=phase):
                (fixture, host, _, _, reference, _, _, work,
                 lost_reply, blocked_cleanup, options, _, streams) = self.bridge()
                refusal = RuntimeError('Original independent refusal')
                if phase == 'exit':
                    work._exit_error = refusal
                else:
                    options['read_error' if phase == 'read' else 'post_error'] = refusal
                with patch.object(work._future, 'result', wraps=work._future.result) as result:
                    with self.assertRaises(RuntimeError) as failed:
                        fixture.observe(host, reference)
                    self.assertIs(failed.exception, refusal)
                    result.assert_not_called()
                self.assertIs(work._future.exception(), lost_reply)
                self.assertIs(work._cleanup_error, blocked_cleanup)
                self.assertFalse(streams)

    async def test_unpublished_state_cannot_resolve_even_the_same_reply_loss(self):
        (fixture, host, _, _, reference, projection, _, work,
         lost_reply, blocked_cleanup, _, events, streams) = self.bridge()
        host._run_publications = []
        host._commit_projections = []
        with self.assertRaises(LocalStorageCommitUnknown) as failed:
            fixture.observe(host, reference)
        self.assertIs(failed.exception, lost_reply)
        self.assertIs(host._pending_publication_write, projection)
        self.assertNotIn('full-original-index', events)
        self.assertIs(work._cleanup_error, blocked_cleanup)
        self.assertFalse(streams)
