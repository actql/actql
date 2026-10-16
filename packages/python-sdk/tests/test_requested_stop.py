"""Consumer-only requested-stop checks; the Host retains Checkpoint authority."""
import asyncio
from copy import deepcopy
import hashlib
import json
import unittest

import httpx

from actql_sdk import AsyncClient, Client, ClientError, get_submission_input
from actql_sdk import _wire as wire
from fixtures import PROFILE, SELECTED, ready, reference


def intent_cid(body):
    # Fixed ASCII fixtures and an independent canonical preimage, not the
    # product encoder. Optional absence and an explicit restriction differ.
    intent = {key: body[key] for key in ('kind', 'input', 'parameters')}
    if 'stopBefore' in body:
        intent['stopBefore'] = body['stopBefore']
    preimage = {'version': 'actql-submitted-intent/0.1', 'intent': intent}
    return 'sha256:' + hashlib.sha256(json.dumps(preimage, sort_keys=True,
        separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()


class RequestedStopWireTests(unittest.TestCase):
    def submission(self):
        return {'connection': SELECTED, 'kind': 'program', 'input': {},
                'parameters': None, 'requestId': 'original'}

    def test_selected_literal_uses_the_registered_optional_rule(self):
        body = self.submission()
        self.assertTrue(wire.valid_body('submit', body | {'stopBefore': 'commit'}))
        self.assertTrue(wire.valid_body('submit', body))

    def test_optional_value_is_not_null_bool_or_an_open_string(self):
        for value in [None, True, False, 0, '', 'Commit', 'none', {}, []]:
            with self.subTest(value=value):
                self.assertFalse(wire.valid_body('submit', self.submission() | {'stopBefore': value}))
        self.assertFalse(wire.valid_body('submit', self.submission() | {'other': 'commit'}))

    def test_original_submit_and_restart_bind_the_same_restriction(self):
        ref = reference()
        body = {'connection': SELECTED, 'kind': 'program', 'input': {}, 'parameters': None,
                'submissionRef': ref, 'intentCid': 'sha256:' + 'e' * 64,
                'attemptRef': {'operation': 'submit', 'attemptId': 'attempt-original'}, 'stopBefore': 'commit'}
        self.assertTrue(wire.valid_body('submit-intent', body))
        older = deepcopy(ref)
        older['epoch']['expiresAt'] -= 1
        restart = body | {'unresolvedHistory': {'submissionRef': older,
                        'acknowledgement': 'possible_prior_execution_and_effects'}}
        self.assertTrue(wire.valid_body('restart-intent', restart))
        for op, value in [('submit-intent', body), ('restart-intent', restart)]:
            self.assertFalse(wire.valid_body(op, value | {'stopBefore': None}))
            self.assertFalse(wire.valid_body(op, value | {'extra': 'commit'}))
        restart['unresolvedHistory']['submissionRef']['epoch']['authorityScopeCid'] = 'sha256:' + 'f' * 64
        self.assertFalse(wire.valid_body('restart-intent', restart))

    def test_optional_rule_does_not_expand_other_operations(self):
        self.assertFalse(wire.valid_body('connect', {'connection': SELECTED, 'stopBefore': 'commit'}))
        self.assertFalse(wire.valid_body('check', {'connection': SELECTED, 'kind': 'program',
            'input': {}, 'scope': 'template_only', 'stopBefore': 'commit'}))


class RequestedStopAsyncTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.requests = []
        self.credentials = 0
        self.reply = None
        def token():
            self.credentials += 1
            return 'fixture-token'
        def handler(request):
            op = request.url.path.rsplit('/', 1)[-1]
            body = json.loads(request.content)
            self.requests.append((op, body))
            if op == 'connect':
                return httpx.Response(200, json=PROFILE)
            if self.reply is not None:
                return self.reply(op, body)
            return httpx.Response(200, json=ready(body))
        self.client = await AsyncClient.connect('https://host.invalid/', token,
                                               transport=httpx.MockTransport(handler))
        self.addAsyncCleanup(self.client.aclose)

    async def test_absence_keeps_the_original_three_field_identity(self):
        run = await self.client.start({}, submission_ref=reference(), attempt_id='ordinary')
        body = self.requests[-1][1]
        self.assertNotIn('stopBefore', body)
        self.assertEqual(body['intentCid'], intent_cid(body))
        self.assertNotIn('stopBefore', get_submission_input(run))

    async def test_start_and_source_forward_the_literal_and_bind_original_identity(self):
        for kind in ['program', 'source']:
            options = {'submission_ref': reference(), 'attempt_id': 'same-attempt', 'stop_before': 'commit'}
            pending = self.client.start({}, **options) if kind == 'program' else self.client.start_source(
                'SELECT 1 AS n', format='sql', **options)
            run = await pending
            body = self.requests[-1][1]
            self.assertEqual(body['stopBefore'], 'commit')
            self.assertEqual(body['intentCid'], intent_cid(body))
            self.assertEqual(get_submission_input(run)['stopBefore'], 'commit')
            self.assertEqual(body['submissionRef'], reference())
            self.assertEqual(body['attemptRef']['attemptId'], 'same-attempt')
        self.assertEqual([op for op, _ in self.requests], ['connect', 'submit-intent', 'submit-intent'])

    async def test_invalid_literal_is_refused_before_credentials_or_transport(self):
        before = (len(self.requests), self.credentials)
        for value in [None, True, False, 0, 'Commit', 'none', {}, []]:
            for api in ['program', 'source']:
                with self.subTest(value=value, api=api), self.assertRaises(ClientError):
                    pending = self.client.start({}, submission_ref=reference(), stop_before=value) if api == 'program' else self.client.start_source(
                        'SELECT 1 AS n', format='sql', submission_ref=reference(), stop_before=value)
                    await pending
                self.assertEqual((len(self.requests), self.credentials), before)

    async def test_restriction_changes_intent_but_not_original_submission_or_attempt(self):
        for options in [{}, {'stop_before': 'commit'}]:
            await self.client.start({}, submission_ref=reference(), attempt_id='original-attempt', **options)
        ordinary, stopped = [body for _, body in self.requests[1:]]
        self.assertNotEqual(ordinary['intentCid'], stopped['intentCid'])
        self.assertEqual(ordinary['submissionRef'], stopped['submissionRef'])
        self.assertEqual(ordinary['attemptRef'], stopped['attemptRef'])
        self.assertEqual(stopped['intentCid'], intent_cid(stopped))

    async def test_snapshot_and_retained_input_are_original_not_mutable_copies(self):
        program = {'n': 1}
        parameters = {'id': 'original'}
        pending = self.client.start(program, parameters=parameters, submission_ref=reference(), stop_before='commit')
        program['n'] = 2
        parameters['id'] = 'changed'
        run = await pending
        captured = get_submission_input(run)
        self.assertEqual(captured['input'], {'n': 1})
        self.assertEqual(captured['parameters'], {'id': 'original'})
        self.assertEqual(captured['stopBefore'], 'commit')
        self.assertIsNone(get_submission_input(ClientError('SubmissionUnknown')))
        with self.assertRaises(TypeError):
            captured['stopBefore'] = 'none'

    async def test_lost_reply_keeps_the_same_restriction_without_retry_or_cancel(self):
        def lost(op, body):
            raise httpx.ReadError('original reply lost')
        self.reply = lost
        with self.assertRaises(ClientError) as error:
            await self.client.start({}, submission_ref=reference(), stop_before='commit', attempt_id='original-attempt')
        self.assertEqual(error.exception.code, 'SubmissionUnknown')
        self.assertEqual(get_submission_input(error.exception)['stopBefore'], 'commit')
        self.assertEqual(error.exception.submission_ref, reference())
        self.assertEqual(error.exception.attempt_ref['attemptId'], 'original-attempt')
        await self.client.aclose()
        self.assertEqual([op for op, _ in self.requests], ['connect', 'submit-intent'])

    async def test_original_host_conflict_does_not_retry_or_remove_the_restriction(self):
        def conflict(op, body):
            return httpx.Response(200, json={'kind': 'conflict', 'attemptRef': body['attemptRef'],
                'submissionRef': body['submissionRef'], 'intentCid': body['intentCid'],
                'reason': 'intent'})
        self.reply = conflict
        with self.assertRaises(ClientError) as error:
            await self.client.start({}, submission_ref=reference(), stop_before='commit')
        self.assertEqual(error.exception.code, 'SubmissionConflict')
        self.assertEqual(get_submission_input(error.exception)['stopBefore'], 'commit')
        self.assertEqual(len(self.requests), 2)

    async def test_closed_client_stays_closed_and_does_not_send(self):
        await self.client.aclose()
        before = self.credentials
        with self.assertRaises(ClientError):
            await self.client.start({}, submission_ref=reference(), stop_before='commit')
        self.assertEqual(self.credentials, before)
        self.assertEqual(len(self.requests), 1)


class RequestedStopSyncTests(unittest.TestCase):
    def test_both_facades_share_the_same_closed_wire_and_original_intent(self):
        requests = []
        def handler(request):
            op = request.url.path.rsplit('/', 1)[-1]
            body = json.loads(request.content)
            requests.append((op, body))
            return httpx.Response(200, json=PROFILE if op == 'connect' else ready(body))
        with Client.connect('https://host.invalid/', 'fixture-token', transport=httpx.MockTransport(handler)) as client:
            for api in ['program', 'source']:
                run = client.start({}, submission_ref=reference(), stop_before='commit') if api == 'program' else client.start_source(
                    'SELECT 1 AS n', format='sql', submission_ref=reference(), stop_before='commit')
                self.assertEqual(get_submission_input(run)['stopBefore'], 'commit')
                self.assertEqual(requests[-1][1]['intentCid'], intent_cid(requests[-1][1]))
            before = len(requests)
            with self.assertRaises(ClientError):
                client.start({}, submission_ref=reference(), stop_before=None)
            self.assertEqual(len(requests), before)
        self.assertEqual([op for op, _ in requests], ['connect', 'submit-intent', 'submit-intent'])
