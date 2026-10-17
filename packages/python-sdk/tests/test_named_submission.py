"""Independent named-wire and public-caller vectors, not a Journal simulator.

Real durable resolve-or-bind/reopen acceptance is kept with the HTTPS fixture.
These transport doubles expose the selected protocol and immutable call input.
"""
import asyncio
from copy import deepcopy
import hashlib
import json
import unittest

import httpx
import rfc8785

import actql_sdk
from actql_sdk import (AsyncClient, Client, ClientError, get_submission_input,
                       get_submission_check_observation, get_check_input)
from actql_sdk import _wire as wire
from fixtures import ADMISSION, EPOCH, PROFILE, SELECTED, reference, check_report


def named_body():
    return {'connection': deepcopy(SELECTED), 'requestName': 'nightly-original',
            'submissionRef': reference('new-candidate'), 'intentCid': 'sha256:' + 'c' * 64,
            'kind': 'aql', 'input': {'text': 'SELECT 1 AS n', 'format': 'sql'},
            'parameters': None, 'attemptRef': {'operation': 'submit', 'attemptId': 'original-attempt'}}


def observed(body, original=None):
    return {'kind': 'observed', 'requestName': body['requestName'], 'intentCid': body['intentCid'],
            'attemptRef': deepcopy(body['attemptRef']), 'outcome': {
                'kind': 'ready', 'submissionRef': deepcopy(original or body['submissionRef']),
                'intentCid': body['intentCid'], 'admission': deepcopy(ADMISSION)}}


class NamedWireTests(unittest.TestCase):
    def test_closed_named_body_reuses_existing_intent_rules(self):
        original = named_body()
        self.assertTrue(wire.valid_body('submit-named-intent', original))
        self.assertTrue(wire.valid_body('submit-named-intent', original | {'readOnly': True, 'stopBefore': 'commit'}))
        for patch in [{'foreign': True}, {'readOnly': False}, {'readOnly': None},
                      {'stopBefore': None}, {'parameters': []}, {'intentCid': 'unknown'}]:
            with self.subTest(patch=patch):
                self.assertFalse(wire.valid_body('submit-named-intent', original | patch))

    def test_name_uses_exact_existing_canonical_submission_name_class(self):
        original = named_body()
        for name in ['nightly-original', 'é', '😀' * 64, 'a b', '\u2028\u2029']:
            self.assertTrue(wire.valid_body('submit-named-intent', original | {'requestName': name}))
        for name in ['', None, False, 1, 'e\u0301', 'x\n', 'x\r', 'x\u0080', '\x7f', '\ud800', '😀' * 65]:
            with self.subTest(name=repr(name)):
                self.assertFalse(wire.valid_body('submit-named-intent', original | {'requestName': name}))

    def test_original_ref_can_differ_but_name_scope_intent_attempt_must_match(self):
        body = named_body()
        original = reference('saved-original')
        original['epoch']['epochNonce'] = 'd' * 64
        value = observed(body, original)
        self.assertTrue(wire.named_submission_attempt(value, SELECTED, body))
        explicit = {'kind': 'recorded', 'attemptRef': value['attemptRef'], 'outcome': value['outcome']}
        self.assertFalse(wire.submission_attempt(explicit, SELECTED, body))
        mutations = []
        for field, replacement in [('requestName', 'other'), ('intentCid', 'sha256:' + '0' * 64),
                                   ('attemptRef', {'operation': 'submit', 'attemptId': 'other'}),
                                   ('kind', 'recorded')]:
            mutations.append(value | {field: replacement})
        bad = deepcopy(value); bad['outcome']['submissionRef']['epoch']['authorityScopeCid'] = 'sha256:' + 'f' * 64; mutations.append(bad)
        bad = deepcopy(value); bad['outcome']['admission']['ref']['authorityScopeCid'] = 'sha256:' + 'f' * 64; mutations.append(bad)
        bad = deepcopy(value); bad['outcome']['intentCid'] = 'sha256:' + 'f' * 64; mutations.append(bad)
        mutations.append(value | {'foreign': True})
        for bad in mutations:
            self.assertFalse(wire.named_submission_attempt(bad, SELECTED, body))

    def test_refused_conflict_and_unresolvable_are_distinct_closed_observations(self):
        body = named_body(); correlation = {k: deepcopy(body[k]) for k in ('requestName', 'intentCid', 'attemptRef')}
        refused = correlation | {'kind': 'refused', 'guarantee': 'attempt_uncommitted_unconsumed', 'reason': 'authorization'}
        conflict = correlation | {'kind': 'conflict', 'reason': 'intent'}
        unresolved = correlation | {'kind': 'observed', 'outcome': {'kind': 'unresolvable',
            'submissionRef': reference('retired-original'), 'problem': {'code': 'submission_history_unresolvable'}}}
        for value in [refused, conflict, unresolved]:
            self.assertTrue(wire.named_submission_attempt(value, SELECTED, body))
        self.assertFalse(wire.named_submission_attempt({k: v for k, v in refused.items() if k != 'guarantee'}, SELECTED, body))
        self.assertFalse(wire.named_submission_attempt(conflict | {'reason': 'authorization'}, SELECTED, body))


class Peer:
    def __init__(self):
        self.requests = []; self.credentials = 0; self.response = None; self.loss = False

    def token(self):
        self.credentials += 1
        return 'original-token'

    async def handle(self, request):
        operation = request.url.path.rsplit('/', 1)[-1]; body = json.loads(request.content)
        self.requests.append((operation, body))
        if operation == 'connect': return httpx.Response(200, json=PROFILE)
        if self.loss: raise httpx.ReadError('Original response lost')
        if operation == 'submit-named-intent':
            value = observed(body, reference('saved-original')) if self.response is None else self.response(body)
            return httpx.Response(200, json=value)
        if operation == 'submit-intent':
            return httpx.Response(200, json={'kind': 'recorded', 'attemptRef': body['attemptRef'], 'outcome': {
                'kind': 'ready', 'submissionRef': body['submissionRef'], 'intentCid': body['intentCid'], 'admission': ADMISSION}})
        if operation == 'wait':
            raise httpx.ReadError('Original wait response lost')
        raise AssertionError('Unexpected operation: ' + operation)


class AsyncNamedTests(unittest.IsolatedAsyncioTestCase):
    async def client(self, peer):
        value = await AsyncClient.connect('https://host.invalid/', peer.token, transport=httpx.MockTransport(peer.handle))
        self.addAsyncCleanup(value.aclose)
        return value

    async def test_public_source_uses_closed_named_packet_and_original_admission(self):
        peer = Peer(); client = await self.client(peer); parameters = {'x': 1}
        pending = client.start_source('SELECT @x AS n', format='sql', parameters=parameters,
            request_id='nightly-original', attempt_id='original-attempt', stop_before='commit', read_only=True)
        parameters['x'] = 9
        execution = await pending
        self.assertEqual([op for op, _ in peer.requests], ['connect', 'submit-named-intent'])
        body = peer.requests[-1][1]
        self.assertEqual(body['requestName'], 'nightly-original')
        self.assertNotEqual(body['submissionRef']['nonce'], body['requestName'])
        self.assertEqual(body['parameters'], {'x': 1})
        intent = {k: body[k] for k in ('kind', 'input', 'parameters', 'readOnly', 'stopBefore')}
        self.assertEqual(body['intentCid'], 'sha256:' + hashlib.sha256(rfc8785.dumps({
            'version': 'actql-submitted-intent/0.1', 'intent': intent})).hexdigest())
        self.assertEqual(execution.submission['submissionRef']['nonce'], 'saved-original')
        self.assertEqual(dict(execution.ref), ADMISSION['ref'])
        self.assertEqual(get_submission_input(execution)['requestName'], 'nightly-original')

    async def test_omission_and_explicit_epoch_api_keep_original_operation(self):
        peer = Peer(); client = await self.client(peer)
        await client.start_source('SELECT 1', format='sql')
        await client.start_source('SELECT 1', format='sql', submission_ref=reference('explicit-original'))
        self.assertEqual([op for op, _ in peer.requests], ['connect', 'submit-intent', 'submit-intent'])
        self.assertTrue(all('requestName' not in body for _, body in peer.requests))
        self.assertEqual(peer.requests[-1][1]['submissionRef']['nonce'], 'explicit-original')

    async def test_invalid_names_or_conflicting_identity_refuse_before_credentials(self):
        peer = Peer(); client = await self.client(peer)
        for name in ['', False, 'e\u0301', 'x\n', '😀' * 65]:
            with self.assertRaises(ClientError):
                client.start_source('SELECT 1', format='sql', request_id=name)
        with self.assertRaises(ClientError):
            client.start_source('SELECT 1', format='sql', submission_ref=reference(), request_id='name')
        self.assertEqual(peer.credentials, 1)
        self.assertEqual(len(peer.requests), 1)

    async def test_conflict_is_public_typed_request_conflict_not_a_new_run(self):
        peer = Peer(); client = await self.client(peer)
        peer.response = lambda body: {k: body[k] for k in ('requestName', 'intentCid', 'attemptRef')} | {'kind': 'conflict', 'reason': 'intent'}
        with self.assertRaises(ClientError) as failure:
            await client.start_source('SELECT 2', format='sql', request_id='nightly-original')
        self.assertEqual(failure.exception.code, 'RequestConflict')
        self.assertIsInstance(failure.exception, actql_sdk.RequestConflict)
        self.assertEqual(failure.exception.request_id, 'nightly-original')
        self.assertEqual(len(peer.requests), 2)

    async def test_unknown_retains_name_candidate_attempt_and_never_implicitly_resends(self):
        peer = Peer(); client = await self.client(peer); peer.loss = True
        with self.assertRaises(ClientError) as failure:
            await client.start_source('SELECT 1', format='sql', request_id='uncertain', attempt_id='same-attempt')
        self.assertEqual(failure.exception.code, 'SubmissionUnknown')
        self.assertEqual(failure.exception.request_id, 'uncertain')
        self.assertEqual(failure.exception.attempt_ref['attemptId'], 'same-attempt')
        self.assertEqual(get_submission_input(failure.exception)['requestName'], 'uncertain')
        self.assertEqual(len(peer.requests), 2)

    async def test_unresolvable_retains_original_ref_and_does_not_fall_back(self):
        peer = Peer(); client = await self.client(peer)
        peer.response = lambda body: {k: body[k] for k in ('requestName', 'intentCid', 'attemptRef')} | {'kind': 'observed',
            'outcome': {'kind': 'unresolvable', 'submissionRef': reference('retired-original'),
                        'problem': {'code': 'submission_history_unresolvable'}}}
        with self.assertRaises(ClientError) as failure:
            await client.start_source('SELECT 1', format='sql', request_id='retired')
        self.assertEqual(failure.exception.code, 'SubmissionUnresolvable')
        self.assertEqual(failure.exception.submission_ref['nonce'], 'retired-original')
        self.assertEqual(failure.exception.request_id, 'retired')
        self.assertEqual(len(peer.requests), 2)

    async def test_mismatched_name_reply_is_unknown_and_never_retried(self):
        peer = Peer(); client = await self.client(peer)
        peer.response = lambda body: observed(body) | {'requestName': 'foreign-original'}
        with self.assertRaises(ClientError) as failure:
            await client.start_source('SELECT 1', format='sql', request_id='original')
        self.assertEqual(failure.exception.code, 'SubmissionUnknown')
        self.assertEqual(failure.exception.request_id, 'original')
        self.assertEqual(len(peer.requests), 2)

    async def test_lazy_query_failure_keeps_returned_original_not_fresh_candidate(self):
        peer = Peer(); client = await self.client(peer)
        query = client.sql('SELECT 1', request_id='original-query')
        with self.assertRaises(ClientError) as failure:
            await query.all()
        self.assertEqual(failure.exception.code, 'QueryObservationUnknown')
        self.assertEqual(failure.exception.request_id, 'original-query')
        self.assertEqual(failure.exception.submission_ref['nonce'], 'saved-original')
        self.assertNotEqual(get_submission_input(query)['submissionRef']['nonce'], 'saved-original')
        self.assertIs(failure.exception.execution, query.execution)
        self.assertEqual([op for op, _ in peer.requests], ['connect', 'submit-named-intent', 'wait'])

    async def test_confirmed_refusal_preserves_guarantee_without_admission(self):
        peer = Peer(); client = await self.client(peer)
        peer.response = lambda body: {k: body[k] for k in ('requestName', 'intentCid', 'attemptRef')} | {
            'kind': 'refused', 'reason': 'admission_capacity', 'guarantee': 'attempt_uncommitted_unconsumed'}
        with self.assertRaises(ClientError) as failure:
            await client.start_source('SELECT 1', format='sql', request_id='refused')
        self.assertEqual(failure.exception.code, 'SubmissionRefused')
        self.assertEqual(failure.exception.outcome['guarantee'], 'attempt_uncommitted_unconsumed')
        self.assertIsNone(failure.exception.execution)
        self.assertEqual(len(peer.requests), 2)

    async def test_only_first_failed_observation_carries_original_check_input(self):
        peer = Peer(); client = await self.client(peer); first = True
        def refused(body):
            nonlocal first
            value = observed(body, reference('saved-original'))
            value['outcome'].pop('admission')
            value['outcome'] |= {'kind': 'not_accepted', 'problem': {'code': 'CheckFailed', 'classification': 'invalid_input'}}
            if first:
                value['outcome']['checkObservation'] = check_report(start=1, end=5)
                first = False
            return value
        peer.response = refused
        failures = []
        for _ in range(2):
            with self.assertRaises(ClientError) as failure:
                await client.start_source('a😀\r\nbé', format='sql', request_id='failed-original')
            self.assertEqual(failure.exception.code, 'SubmissionNotAccepted')
            self.assertEqual(failure.exception.submission_ref['nonce'], 'saved-original')
            failures.append(failure.exception)
        first_check = get_submission_check_observation(failures[0])
        self.assertEqual(get_check_input(first_check, 'source')['text'], 'a😀\r\nbé')
        self.assertIsNone(get_submission_check_observation(failures[1]))
        self.assertEqual([op for op, _ in peer.requests], ['connect', 'submit-named-intent', 'submit-named-intent'])


class SyncNamedTests(unittest.TestCase):
    def test_same_public_sync_caller_and_captured_program(self):
        peer = Peer()
        with Client.connect('https://host.invalid/', peer.token, transport=httpx.MockTransport(peer.handle)) as client:
            execution = client.start({'version': 'actql/0.1'}, request_id='sync-original')
            self.assertEqual(execution.submission['submissionRef']['nonce'], 'saved-original')
            self.assertEqual(peer.requests[-1][1]['requestName'], 'sync-original')
            self.assertEqual(get_submission_input(execution)['requestName'], 'sync-original')


if __name__ == '__main__': unittest.main()
