"""Public admission caller over SQLite/File with an opaque execution fixture.

This fixture verifies admission/transport only, not task or product execution.
"""
import asyncio
import copy
import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Event
import unittest
from unittest.mock import patch

from actql_sdk import AsyncClient, Client, ClientError
from actql_sdk._local_product import LocalProductCleanupPending
from actql_sdk._local_response import LocalResponseCleanupPending, OriginalLocalResponseStream
from actql_sdk._local_storage import LocalStorageCommitUnknown
from actql_sdk._values import thaw, wire_bytes
import test_local_finite_run as assembly_fixture
import test_local_submission_append as input_fixture

# The public text request preserves text/format insertion order. This is an
# independent input fixture for the scalar Core's exact-byte checks, not a
# rewrite of the submitted input or an expectation copied from a response.
PORT_INTENT = b'{"kind":"aql","input":{"text":"/*\xf0\x9f\x98\x80*/\\r\\nSELECT 1 AS n","format":"sql"},"parameters":{"e\xcc\x81/~":null}}'


class LocalOperationPortTests(unittest.IsolatedAsyncioTestCase):
    def host(self, path, intent=PORT_INTENT):
        selected = patch.object(input_fixture, 'INTENT', intent)
        selected.start()
        self.addCleanup(selected.stop)
        fixture = assembly_fixture.FiniteRunAssemblyTests()
        self.addCleanup(fixture.doCleanups)
        # Public first admission must start from a genuinely missing row. The
        # material/commit fixture's default pre-held preparing row is reserved
        # for its direct commit cases; it cannot be reaccepted as a new Run.
        host, core, events, admission = fixture.assembly(path, preparing=False)
        execution = patch.object(host, '_execute_original_admitted_run')
        execution.start()
        self.addCleanup(execution.stop)
        return host, core, events, admission

    async def test_public_async_start_consumes_saved_owner_admission_with_opaque_execution_port(self):
        with TemporaryDirectory(prefix='actql-operation-port-') as directory:
            host, core, events, admission = self.host(Path(directory))
            with patch('actql_sdk._async.httpx.AsyncClient', side_effect=AssertionError('HTTP created')):
                client = await AsyncClient._connect_local(host)
            original = json.loads(input_fixture.INTENT)
            ref = client.new_submission(nonce='original')
            result = await client.start_source(original['input']['text'], format='sql',
                parameters=original['parameters'], submission_ref=ref, attempt_id='original-invocation')
            self.assertEqual(thaw(result.ref), json.loads(admission)['ref'])
            self.assertIs(result._client, client)
            self.assertEqual(result.submission['submissionRef'], ref)
            self.assertEqual(events.count(('run', 'prepare_sdk')), 1)
            self.assertFalse(any(family in ('source', 'task', 'compute', 'publication') for family, _ in events))
            self.assertFalse(host._response_streams)
            self.assertFalse(client._responses)
            self.assertIs(host._runs._runs[host._run_loans[0].handle], host._run_loans[0])
            await client.aclose()
            self.assertTrue(core._closed)
            self.assertFalse(any(name == 'cancel' for _, name in events))

    async def test_public_start_lost_saved_run_reply_is_unknown_with_original_identity_and_no_replay(self):
        with TemporaryDirectory(prefix='actql-operation-loss-') as directory:
            host, _, events, _ = self.host(Path(directory))
            client = await AsyncClient._connect_local(host)
            original = json.loads(input_fixture.INTENT)
            ref = client.new_submission(nonce='original')
            commit = host._commit_original_run_rows
            def lose(output):
                commit(output)
                raise LocalStorageCommitUnknown(host._installation._store)
            with patch.object(host, '_commit_original_run_rows', side_effect=lose) as write:
                with self.assertRaises(ClientError) as failed:
                    await client.start_source(original['input']['text'], format='sql',
                        parameters=original['parameters'], submission_ref=ref,
                        attempt_id='original-invocation')
            self.assertEqual(failed.exception.code, 'SubmissionUnknown')
            self.assertEqual(failed.exception.submission_ref, ref)
            self.assertEqual(failed.exception.attempt_ref['attemptId'], 'original-invocation')
            self.assertEqual(write.call_count, 1)
            self.assertEqual(events.count(('run', 'prepare_sdk')), 1)
            self.assertIs(host._pending_run_write, host._row_outputs[-1])
            self.assertFalse(any(family in ('journal', 'compute', 'task', 'publication') for family, _ in events))
            await client.aclose()

    async def test_original_optional_restrictions_reach_same_admission_and_fingerprint(self):
        for choices in ({'readOnly': True}, {'stopBefore': 'commit'},
                        {'stopBefore': 'commit', 'readOnly': True}):
            with self.subTest(choices=choices), TemporaryDirectory(prefix='actql-operation-choice-') as directory:
                original = json.loads(PORT_INTENT) | choices
                expected = json.dumps(original, ensure_ascii=False, separators=(',', ':')).encode()
                host, core, events, _ = self.host(Path(directory), expected)
                client = await AsyncClient._connect_local(host)
                options = {}
                if 'readOnly' in choices:
                    options['read_only'] = choices['readOnly']
                if 'stopBefore' in choices:
                    options['stop_before'] = choices['stopBefore']
                with patch.object(host, '_accept_original', wraps=host._accept_original) as accept:
                    result = await client.start_source(original['input']['text'], format='sql',
                        parameters=original['parameters'],
                        submission_ref=client.new_submission(nonce='original'),
                        attempt_id='original-invocation', **options)
                self.assertEqual(accept.call_count, 1)
                self.assertEqual(json.loads(accept.call_args.args[1]), original)
                preimage = json.dumps({'intent': original, 'version': 'actql-submitted-intent/0.1'},
                    ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
                self.assertEqual(result.submission['intentCid'], 'sha256:' + hashlib.sha256(preimage).hexdigest())
                self.assertEqual(events.count(('run', 'prepare_sdk')), 1)
                await client.aclose()
                self.assertTrue(core._closed)

    async def test_cancelled_public_start_keeps_worker_response_and_run_until_actual_stop(self):
        with TemporaryDirectory(prefix='actql-operation-worker-') as directory:
            host, core, events, _ = self.host(Path(directory))
            entered, release = Event(), Event()
            def execute(run):
                self.assertIs(run, host._run_loans[0])
                entered.set()
                if not release.wait(2):
                    raise TimeoutError('Test worker was not released')
            host._execute_original_admitted_run.side_effect = execute
            client = await AsyncClient._connect_local(host)
            original = json.loads(input_fixture.INTENT)
            ref = client.new_submission(nonce='original')
            task = asyncio.create_task(client.start_source(original['input']['text'], format='sql',
                parameters=original['parameters'], submission_ref=ref, attempt_id='original-invocation'))
            try:
                # Admission uses real SQLite/current checks. The enclosing
                # finite guard bounds this wait, without mistaking its latency
                # for physical stop or cancelling before the worker exists.
                while not entered.is_set():
                    if task.done():
                        task.result()
                        self.fail('Original worker was not reached')
                    await asyncio.sleep(0.01)
                task.cancel()
                with self.assertRaises(asyncio.CancelledError) as failed:
                    await task
                self.assertEqual(failed.exception.submission_ref, ref)
                self.assertFalse(host.close())
                self.assertFalse(core._closed)
                self.assertEqual(len(host._response_streams), 1)
                stream = next(iter(host._response_streams))
                self.assertFalse(stream._attached)
                self.assertIs(core._loans[stream._loan.ticket], stream._loan)
                self.assertIs(host._runs._runs[host._run_loans[0].handle], host._run_loans[0])
            finally:
                release.set()
                if not task.done():
                    task.cancel()
                    try:
                        await task
                    except asyncio.CancelledError:
                        pass
                await client.aclose()
            host._execute_original_admitted_run.assert_called_once()
            self.assertTrue(core._closed)
            self.assertFalse(host._response_streams)
            self.assertFalse(any(name == 'cancel' for _, name in events))

    async def test_wrong_identity_and_unknown_fields_refuse_before_original_preparation_or_write(self):
        with TemporaryDirectory(prefix='actql-operation-refusal-') as directory:
            host, _, events, _ = self.host(Path(directory))
            profile = host.profile()
            intent = json.loads(input_fixture.INTENT)
            # Independent canonical preimage; no expected value is copied from
            # the product's response or content_cid implementation.
            preimage = json.dumps({'intent': intent, 'version': 'actql-submitted-intent/0.1'},
                ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
            body = {'connection': {'mode': 'local', 'owner': 'local', 'durability': 'durable',
                'consentRefs': [], 'runners': []}, **intent,
                'submissionRef': {'epoch': profile['submissionEpoch'], 'nonce': 'original'},
                'intentCid': 'sha256:' + hashlib.sha256(preimage).hexdigest(),
                'attemptRef': {'operation': 'submit', 'attemptId': 'original-invocation'}}
            before = len(events)
            for changed in (body | {'intentCid': 'sha256:' + '0' * 64}, body | {'extra': None},
                            body | {'connection': body['connection'] | {'mode': 'remote'}}):
                with self.assertRaises(ValueError):
                    await host.open('submit-intent', wire_bytes(changed))
            self.assertEqual(events[before:], [])
            self.assertFalse(host._run_loans)
            self.assertTrue(host.close())

    async def test_response_close_physically_stops_suspended_iterator_before_ticket_release(self):
        with TemporaryDirectory(prefix='actql-response-stop-') as directory:
            host, core, _, _ = self.host(Path(directory))
            stream = OriginalLocalResponseStream(host, b'{"original":null}')
            stream._attached = True
            loan = stream._loan
            iterator = stream.__aiter__()
            self.assertEqual(await anext(iterator), b'{"original":null}')
            self.assertTrue(stream._reading)
            self.assertFalse(host.close())
            self.assertIs(core._loans[loan.ticket], loan)
            await stream.aclose()
            self.assertFalse(stream._reading)
            self.assertNotIn(loan.ticket, core._loans)
            self.assertTrue(host.close())

    async def test_response_cleanup_failure_keeps_same_input_and_close_retries_without_operation(self):
        with TemporaryDirectory(prefix='actql-response-cleanup-') as directory:
            host, core, events, _ = self.host(Path(directory))
            stream = OriginalLocalResponseStream(host, b'{"original":null}')
            stream._attached = True
            loan = stream._loan
            with patch.object(core, 'close_input', return_value=False):
                with self.assertRaises(LocalResponseCleanupPending) as failed:
                    await stream.aclose()
                self.assertIs(failed.exception.cleanup_stream, stream)
            self.assertIs(stream._loan, loan)
            self.assertIs(core._loans[loan.ticket], loan)
            self.assertIn(stream, host._response_streams)
            before = len(events)
            await stream.aclose()
            self.assertEqual(events[before:], [])
            self.assertNotIn(stream, host._response_streams)
            self.assertTrue(host.close())

    async def test_copied_response_cannot_observe_or_close_original_ticket(self):
        with TemporaryDirectory(prefix='actql-response-copy-') as directory:
            host, core, _, _ = self.host(Path(directory))
            stream = OriginalLocalResponseStream(host, b'{"original":null}')
            loan = stream._loan
            copied = copy.copy(stream)
            with self.assertRaises(ValueError): copied.__aiter__()
            with self.assertRaises(ValueError): await copied.aclose()
            self.assertIs(core._loans[loan.ticket], loan)
            await stream.aclose()
            self.assertTrue(host.close())


class SyncLocalOperationPortTests(unittest.TestCase):
    def test_sync_start_uses_same_public_model_and_owned_local_response(self):
        with TemporaryDirectory(prefix='actql-operation-sync-') as directory:
            fixture = assembly_fixture.FiniteRunAssemblyTests()
            self.addCleanup(fixture.doCleanups)
            selected = patch.object(input_fixture, 'INTENT', PORT_INTENT)
            selected.start()
            self.addCleanup(selected.stop)
            host, core, events, admission = fixture.assembly(Path(directory))
            execution_port = patch.object(host, '_execute_original_admitted_run')
            execution_port.start()
            self.addCleanup(execution_port.stop)
            runner = asyncio.Runner()
            client = Client(runner, runner.run(AsyncClient._connect_local(host)))
            with client:
                original = json.loads(input_fixture.INTENT)
                execution = client.start_source(original['input']['text'], format='sql',
                    parameters=original['parameters'], submission_ref=client.new_submission(nonce='original'),
                    attempt_id='original-invocation')
                self.assertEqual(thaw(execution.ref), json.loads(admission)['ref'])
                self.assertFalse(host._response_streams)
            self.assertTrue(core._closed)
            self.assertEqual(events.count(('run', 'prepare_sdk')), 1)
            self.assertFalse(any(family in ('task', 'compute', 'source', 'publication') for family, _ in events))


if __name__ == '__main__':
    unittest.main()
