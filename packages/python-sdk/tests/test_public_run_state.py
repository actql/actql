"""Current-wire consumer checks; no synthetic producer revision or Run execution."""
from dataclasses import asdict, FrozenInstanceError, is_dataclass
import json
import unittest

import httpx

from actql_sdk import AsyncClient, Client, ClientError, Observation, RunState
from fixtures import ADMISSION, PROFILE


def state(revision=7):
    return {'version': 'actql-run-state/0.1', 'run_id': 'original-run',
            'revision': revision, 'status': 'running',
            'updated_at': '2026-10-16T10:00:00.000Z',
            'next_action': {'kind': 'none'}, 'result_available': False,
            'result_availability': {},
            'control': {'revision': 2, 'cancellation_requested': False,
                        'physical_stop': 'unknown'}}


class RunStateValueTests(unittest.TestCase):
    def test_dataclass_attributes_and_original_mapping_keep_separate_revisions(self):
        original = state(9007199254740991)
        value = RunState(original)
        self.assertTrue(is_dataclass(value))
        self.assertIsInstance(value, Observation)
        self.assertEqual(value.status, 'running')
        self.assertEqual(value.revision, 9007199254740991)
        self.assertEqual(value.control['revision'], 2)
        self.assertEqual(value['revision'], value.revision)
        self.assertEqual(value.to_dict(), original)
        self.assertIsNone(value.checkpoint)
        self.assertNotIn('checkpoint', value)

    def test_asdict_and_to_dict_are_detached_and_never_mutate_original_state(self):
        original = state()
        value = RunState(original)
        original['control']['revision'] = 99
        original['status'] = 'cancelled'
        exported = asdict(value)
        self.assertEqual(exported['control']['revision'], 2)
        exported['control']['revision'] = 50
        exported['next_action']['kind'] = 'changed'
        self.assertEqual(value.control['revision'], 2)
        self.assertEqual(value.next_action['kind'], 'none')
        self.assertEqual(value.status, 'running')
        self.assertEqual(value.to_dict(), state())
        with self.assertRaises(FrozenInstanceError): value.revision = 10
        with self.assertRaises(TypeError): value.control['revision'] = 3
        self.assertEqual(json.loads(json.dumps(asdict(value)))['revision'], 7)

    def test_nested_result_availability_and_checkpoint_remain_immutable(self):
        original = state() | {'status': 'waiting_checkpoint',
            'checkpoint': {'checkpoint_id': 'checkpoint-original',
                'checkpoint_cid': 'sha256:' + 'a' * 64, 'kind': 'effect_set'},
            'next_action': {'kind': 'resolve_checkpoint', 'checkpoint_id': 'checkpoint-original'},
            'result_availability': {'answer': {'state': 'unknown',
                'observed_at': '2026-10-16T10:00:00.000Z', 'reason': 'store_query_failed'}}}
        value = RunState(original)
        self.assertEqual(value.checkpoint['checkpoint_id'], 'checkpoint-original')
        with self.assertRaises(TypeError): value.result_availability['answer']['reason'] = 'confirmed_present'
        exported = asdict(value)
        exported['result_availability']['answer']['state'] = 'available'
        self.assertEqual(value.result_availability['answer']['state'], 'unknown')

    def test_required_revision_uses_generated_wire_without_defaults_or_coercion(self):
        for revision in [True, False, -1, -0.0, 9007199254740992, '7', None]:
            with self.subTest(revision=repr(revision)), self.assertRaises(ClientError):
                RunState(state(revision))
        missing = state(); del missing['revision']
        with self.assertRaises(ClientError): RunState(missing)
        with self.assertRaises(ClientError): RunState(state() | {'future': True})

    def test_copied_dataclass_is_only_detached_data_not_run_or_read_authority(self):
        value = RunState(state())
        detached = RunState(value.to_dict())
        self.assertIsNot(detached, value)
        self.assertEqual(detached.to_dict(), value.to_dict())
        self.assertEqual(asdict(detached), asdict(value))
        self.assertFalse(hasattr(value, 'cancel'))
        self.assertFalse(hasattr(value, 'result'))


class RunStateAsyncConsumerTests(unittest.IsolatedAsyncioTestCase):
    async def test_actual_async_facade_projects_status_wait_and_reconcile_without_extra_io(self):
        requests = []
        def handler(request):
            operation = request.url.path.rsplit('/', 1)[-1]
            requests.append(operation)
            return httpx.Response(200, json=PROFILE if operation == 'connect'
                                  else ADMISSION if operation == 'attach' else state())
        async with await AsyncClient.connect('https://host.invalid/', 'fixture-token',
                transport=httpx.MockTransport(handler)) as client:
            run = await client.attach(ADMISSION['ref'])
            for operation in [run.status, run.wait, run.reconcile]:
                observed = await operation()
                self.assertIsInstance(observed, RunState)
                self.assertEqual(observed.revision, 7)
                self.assertEqual(asdict(observed)['control']['physical_stop'], 'unknown')
        self.assertEqual(requests, ['connect', 'attach', 'status', 'wait', 'reconcile'])

    async def test_missing_host_revision_is_rejected_without_inventing_or_retrying_state(self):
        requests = []
        def handler(request):
            operation = request.url.path.rsplit('/', 1)[-1]
            requests.append(operation)
            value = state(); del value['revision']
            return httpx.Response(200, json=PROFILE if operation == 'connect'
                                  else ADMISSION if operation == 'attach' else value)
        async with await AsyncClient.connect('https://host.invalid/', 'fixture-token',
                transport=httpx.MockTransport(handler)) as client:
            run = await client.attach(ADMISSION['ref'])
            with self.assertRaises(ClientError) as error: await run.status()
            self.assertEqual(error.exception.code, 'InvalidHostRunState')
        self.assertEqual(requests, ['connect', 'attach', 'status'])


class RunStateSyncConsumerTests(unittest.TestCase):
    def test_actual_sync_facade_returns_the_same_dataclass_and_preserves_close_semantics(self):
        requests = []
        def handler(request):
            operation = request.url.path.rsplit('/', 1)[-1]
            requests.append(operation)
            return httpx.Response(200, json=PROFILE if operation == 'connect'
                                  else ADMISSION if operation == 'attach' else state())
        with Client.connect('https://host.invalid/', 'fixture-token',
                transport=httpx.MockTransport(handler)) as client:
            run = client.attach(ADMISSION['ref'])
            self.assertIsInstance(run.wait(), RunState)
            self.assertEqual(run.status().revision, 7)
            self.assertEqual(run.reconcile().control['revision'], 2)
        self.assertEqual(requests, ['connect', 'attach', 'wait', 'status', 'reconcile'])
