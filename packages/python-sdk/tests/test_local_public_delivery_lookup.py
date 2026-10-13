"""Public sync/async Local lookup caller; scalar observation, not product E2E."""
import asyncio
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from actql_sdk import AsyncClient, Client, ClientError
import test_local_public_run_observation as public_fixture
import test_local_product_operation_port as operation_fixture


class PublicDeliveryLookupTests(unittest.IsolatedAsyncioTestCase):
    def fixture(self, host, core, execution):
        case = public_fixture.PublicRunObservationTests()
        self.addCleanup(case.doCleanups)
        run, projection, calls, _ = case.publication(host, core, execution)
        outputs = {'wire': b'{"kind":"not_found"}'}
        def project(request, original_run, consume):
            core._owned_input(request)
            self.assertEqual(original_run, run.handle)
            original = json.loads(core._inputs[request.ticket].payload)
            self.assertEqual(original['result_name'], 'answer')
            self.assertEqual(original['format'], 'jsonl')
            self.assertEqual(original['attempt_id'], 'original-read')
            self.assertIn('observed_at', original)
            calls.append(('opaque_fixture', 'delivery_lookup', ()))
            consume(outputs['wire'])
        observation = SimpleNamespace(project_sdk_delivery_lookup=project)
        def select(original_run, candidate):
            self.assertIs(original_run, run)
            self.assertIs(candidate, projection)
            return observation
        patcher = patch.object(host, '_original_sdk_read_observation', side_effect=select)
        patcher.start();self.addCleanup(patcher.stop)
        return run, projection, calls, outputs

    async def test_async_lookup_is_read_only_and_invalid_owner_wire_is_rejected(self):
        with TemporaryDirectory() as directory:
            case = public_fixture.PublicRunObservationTests()
            self.addCleanup(case.doCleanups)
            host, core, events, _ = case.host(Path(directory))
            client, execution = await case.start(host)
            run, _, calls, outputs = self.fixture(host, core, execution)
            before = len(events)
            self.assertEqual((await execution.result('answer').delivery_attempt('original-read')).to_dict(),
                             {'kind': 'not_found'})
            self.assertFalse(host._response_streams)
            self.assertIs(host._runs._runs[run.handle], run)
            self.assertFalse(any(family in ('run', 'compute', 'task', 'source') for family, _ in events[before:]))
            outputs['wire'] = b'{"kind":"found","attempt":null,"record":null,"hostReleaseReceipt":null}'
            with self.assertRaises(ClientError) as failure:
                await execution.result('answer').delivery_attempt('original-read')
            self.assertEqual(failure.exception.code, 'InvalidHostDeliveryAttempt')
            self.assertFalse(host._response_streams)
            self.assertEqual(sum(name == 'delivery_lookup' for _, name, _ in calls), 2)
            await client.aclose()
            self.assertTrue(core._closed)
            self.assertFalse(any(name == 'cancel' for _, name in events))


class SyncPublicDeliveryLookupTests(unittest.TestCase):
    def test_sync_uses_same_original_lookup_without_run_cancel_or_resubmit(self):
        with TemporaryDirectory() as directory:
            case = public_fixture.PublicRunObservationTests()
            self.addCleanup(case.doCleanups)
            host, core, events, _ = case.host(Path(directory))
            runner = asyncio.Runner()
            client = Client(runner, runner.run(AsyncClient._connect_local(host)))
            original = json.loads(operation_fixture.PORT_INTENT)
            with client:
                execution = client.start_source(original['input']['text'], format='sql',
                    parameters=original['parameters'], submission_ref=client.new_submission(nonce='original'),
                    attempt_id='original-invocation')
                fixture = PublicDeliveryLookupTests()
                self.addCleanup(fixture.doCleanups)
                run, _, _, _ = fixture.fixture(host, core, execution._execution)
                before = len(events)
                self.assertEqual(execution.result('answer').delivery_attempt('original-read').to_dict(),
                                 {'kind': 'not_found'})
                self.assertIs(host._runs._runs[run.handle], run)
                self.assertFalse(any(family in ('run', 'compute', 'task', 'source') for family, _ in events[before:]))
            self.assertTrue(core._closed)
            self.assertFalse(any(name == 'cancel' for _, name in events))
