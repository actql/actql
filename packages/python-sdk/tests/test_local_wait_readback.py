"""Actual worker/Host recovery callers with explicit Store/Core readback ports.

No physical thread, VM, SQLite transaction or installed acceptance. The
publication exception handler and existing ensure/advance/read response callers
are imported intact; index/current/read admission remain explicit ports.
"""
from concurrent.futures import Future
from types import SimpleNamespace
import unittest

from actql_sdk import _wire as wire
from actql_sdk._local_storage import LocalStorageCommitUnknown
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
