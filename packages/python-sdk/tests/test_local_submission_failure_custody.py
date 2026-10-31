"""Direct-port failure custody controls; no installed Core or runtime claim."""
import asyncio
import unittest

import httpx

from actql_sdk import AsyncClient, ClientError, get_submission_input
from fixtures import PROFILE, reference
from test_local_client_transport import DirectHost, LOCAL_PROFILE


class LocalSubmissionFailureCustodyTests(unittest.IsolatedAsyncioTestCase):
    async def test_local_unknown_keeps_original_failure_without_resending(self):
        original = OSError('Original local operation failed')

        def respond(operation, body):
            if operation == 'connect':
                return httpx.Response(200, json=LOCAL_PROFILE)
            raise original

        host = DirectHost(respond)
        client = await AsyncClient._connect_local(host)
        try:
            with self.assertRaises(ClientError) as raised:
                await client.start_source('SELECT 1', format='sql',
                    submission_ref=reference(), attempt_id='original-attempt')
            failure = raised.exception
            self.assertEqual(failure.code, 'SubmissionUnknown')
            self.assertEqual(failure.submission_ref, reference())
            self.assertEqual(failure.attempt_ref['attemptId'], 'original-attempt')
            self.assertEqual(get_submission_input(failure)['input']['text'], 'SELECT 1')
            exchange = failure.original_error
            self.assertIsInstance(exchange, ClientError)
            self.assertEqual(exchange.code, 'ClientTransportUnknown')
            self.assertIs(exchange.__context__, original)
            self.assertEqual([op for op, _ in host.requests], ['connect', 'submit-intent'])
        finally:
            await client.aclose()
        self.assertEqual(host.closes, 1)

    async def test_local_invalid_outcome_keeps_validator_failure_and_identity(self):
        host = DirectHost(lambda op, _: httpx.Response(200,
            json=LOCAL_PROFILE if op == 'connect' else {'kind': 'not-an-outcome'}))
        client = await AsyncClient._connect_local(host)
        try:
            with self.assertRaises(ClientError) as raised:
                await client.start_source('SELECT 2', format='sql',
                    submission_ref=reference(), attempt_id='validator-attempt')
            failure = raised.exception
            self.assertEqual(failure.code, 'SubmissionUnknown')
            self.assertEqual(failure.submission_ref, reference())
            self.assertEqual(failure.attempt_ref['attemptId'], 'validator-attempt')
            self.assertEqual(failure.original_error.code, 'InvalidHostSubmissionOutcome')
            self.assertEqual([op for op, _ in host.requests], ['connect', 'submit-intent'])
        finally:
            await client.aclose()
        self.assertEqual(host.closes, 1)

    async def test_remote_transport_diagnostic_stays_unexposed(self):
        operations = []

        async def respond(request):
            operation = request.url.path.rsplit('/', 1)[-1]
            operations.append(operation)
            if operation == 'connect':
                return httpx.Response(200, json=PROFILE)
            raise httpx.ReadError('Borrowed remote diagnostic')

        client = await AsyncClient.connect('https://host.invalid/', 'original-token',
            transport=httpx.MockTransport(respond))
        try:
            with self.assertRaises(ClientError) as raised:
                await client.start_source('SELECT 3', format='sql',
                    submission_ref=reference(), attempt_id='remote-attempt')
            self.assertEqual(raised.exception.code, 'SubmissionUnknown')
            self.assertEqual(raised.exception.submission_ref, reference())
            self.assertIsNone(raised.exception.original_error)
            self.assertEqual(operations, ['connect', 'submit-intent'])
        finally:
            await client.aclose()

    async def test_local_cancellation_retains_same_carrier_and_is_not_unknown(self):
        original = asyncio.CancelledError()

        def respond(operation, body):
            if operation == 'connect':
                return httpx.Response(200, json=LOCAL_PROFILE)
            raise original

        host = DirectHost(respond)
        client = await AsyncClient._connect_local(host)
        try:
            with self.assertRaises(asyncio.CancelledError) as raised:
                await client.start_source('SELECT 4', format='sql',
                    submission_ref=reference(), attempt_id='cancelled-attempt')
            self.assertIs(raised.exception, original)
            self.assertEqual(original.submission_ref, reference())
            self.assertEqual(original.attempt_ref['attemptId'], 'cancelled-attempt')
            self.assertEqual([op for op, _ in host.requests], ['connect', 'submit-intent'])
        finally:
            await client.aclose()
        self.assertEqual(host.closes, 1)
