"""Public SDK/Host read caller with opaque transport doubles; product E2E0."""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import httpx

from actql_sdk import AsyncClient, ClientError
from actql_sdk._local_storage import LocalStorageCommitUnknown
import test_local_public_run_observation as fixture


class PublicLocalReadTests(unittest.IsolatedAsyncioTestCase):
    def pipeline(self, host, core, run, projection):
        calls = []
        holder = SimpleNamespace()
        fact = object()
        def persist(request, original_run):
            core._owned_input(request)
            self.assertEqual(original_run, run.handle)
            body = json.loads(core._inputs[request.ticket].payload)
            self.assertEqual((body['result_name'], body['format']), ('answer', 'jsonl'))
            calls.append(('first', request))
        holder.persist = persist
        def prepare(request, clock):
            calls.append(('codecs', request))
            calls.append(('selected', request))
            return fact
        holder.prepare_original_payload = prepare
        def evidence(original_run, candidate, request):
            self.assertIs(original_run, run)
            self.assertIs(candidate, projection)
            calls.append(('evidence', request))
        def acquire(storage, request, clock, selected):
            self.assertIs(storage, holder)
            self.assertIs(selected, fact)
            calls.append(('reader', request))
            return SimpleNamespace(request=request)
        class Stream(httpx.AsyncByteStream):
            def __init__(self, original_host, reader):
                self._attached = False
                self._host = original_host
                self._host._response_streams.add(self)
            async def __aiter__(self):
                # Fixed wire vector only: this fixture does not fabricate
                # Core sink/receipt/ACK evidence or claim installed success.
                yield b'{"n":1}\n'
                yield b'\x1e'
            def _close(self):
                self._host._response_streams.discard(self)
                return True
            async def aclose(self): self._close()
        patches = [patch.object(host, '_original_sdk_delivery_store', return_value=holder),
                   patch.object(host, '_persist_original_sdk_read_evidence', side_effect=evidence),
                   patch('actql_sdk._local_product.OriginalSDKPayloadReader', side_effect=acquire),
                   patch('actql_sdk._local_product.OriginalLocalSDKResponseStream', Stream)]
        for p in patches: p.start();self.addCleanup(p.stop)
        return calls, holder

    async def test_public_read_routes_existing_owners_and_sdk_parses_expected_jsonl(self):
        with TemporaryDirectory() as directory:
            case = fixture.PublicRunObservationTests();self.addCleanup(case.doCleanups)
            host, core, events, _ = case.host(Path(directory))
            client, execution = await case.start(host)
            run, projection, _, _ = case.publication(host, core, execution)
            calls, _ = self.pipeline(host, core, run, projection)
            before = len(events)
            rows = await execution.result('answer').all()
            self.assertEqual(rows, [{'n': 1}])
            self.assertEqual([name for name, _ in calls], ['evidence', 'first', 'codecs', 'selected', 'reader'])
            self.assertTrue(all(request is calls[0][1] for _, request in calls))
            self.assertFalse(host._response_streams)
            self.assertFalse(any(family in ('run', 'compute', 'task', 'source') for family, _ in events[before:]))
            await client.aclose()

    async def test_first_commit_unknown_does_not_reissue_or_open_descriptor(self):
        with TemporaryDirectory() as directory:
            case = fixture.PublicRunObservationTests();self.addCleanup(case.doCleanups)
            host, core, _, _ = case.host(Path(directory))
            client, execution = await case.start(host)
            run, projection, _, _ = case.publication(host, core, execution)
            calls, holder = self.pipeline(host, core, run, projection)
            with patch.object(holder, 'persist', side_effect=LocalStorageCommitUnknown(host._installation._store)) as commit:
                with self.assertRaises(ClientError) as error: await execution.result('answer').all()
                self.assertEqual(error.exception.code, 'ClientTransportUnknown')
                self.assertEqual(commit.call_count, 1)
            self.assertEqual([name for name, _ in calls], ['evidence'])
            self.assertFalse(host._response_streams)
            await client.aclose()


class SyncPublicLocalReadTests(unittest.TestCase):
    def test_sync_facade_uses_same_host_read_chain_without_compute_or_cancel(self):
        import asyncio
        from actql_sdk import Client
        import test_local_product_operation_port as operation_fixture
        with TemporaryDirectory() as directory:
            case = fixture.PublicRunObservationTests();self.addCleanup(case.doCleanups)
            host, core, events, _ = case.host(Path(directory))
            runner = asyncio.Runner()
            client = Client(runner, runner.run(AsyncClient._connect_local(host)))
            original = json.loads(operation_fixture.PORT_INTENT)
            with client:
                execution = client.start_source(original['input']['text'], format='sql',
                    parameters=original['parameters'], submission_ref=client.new_submission(nonce='original'),
                    attempt_id='original-invocation')
                run, projection, _, _ = case.publication(host, core, execution._execution)
                pipeline = PublicLocalReadTests();self.addCleanup(pipeline.doCleanups)
                calls, _ = pipeline.pipeline(host, core, run, projection)
                before = len(events)
                self.assertEqual(execution.result('answer').all(), [{'n': 1}])
                self.assertEqual([name for name, _ in calls], ['evidence', 'first', 'codecs', 'selected', 'reader'])
                self.assertFalse(any(family in ('run', 'compute', 'task', 'source') for family, _ in events[before:]))
            self.assertFalse(any(name == 'cancel' for _, name in events))
            self.assertTrue(core._closed)
