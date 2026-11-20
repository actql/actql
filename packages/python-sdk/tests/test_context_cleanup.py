"""Imported public Client contexts with actual HTTP cleanup and no Local VM."""
import asyncio
import unittest

import httpx

from actql_sdk import AsyncClient, Client, ClientError
from fixtures import PROFILE


class CleanupTransport(httpx.MockTransport):
    def __init__(self, *, fail=True, error=None):
        self.operations = []
        self.closes = 0
        self.fail = fail
        self.error = error
        super().__init__(self.reply)

    def reply(self, request):
        self.operations.append(request.url.path.rsplit('/', 1)[-1])
        return httpx.Response(200, json=PROFILE)

    async def aclose(self):
        self.closes += 1
        if self.fail and self.closes == 1:
            raise self.error if self.error is not None else OSError('Original physical cleanup is pending')


class MetadataRefusal(Exception):
    def __setattr__(self, name, value):
        if name == 'cleanup_error':
            raise RuntimeError('Exception metadata is unavailable')
        super().__setattr__(name, value)


def primaries():
    return (ClientError('OriginalBodyUnknown'), ValueError('Original body failure'),
            asyncio.CancelledError(), BaseException('Original body stop'))


class AsyncContextCleanupTests(unittest.IsolatedAsyncioTestCase):
    async def test_body_exception_remains_primary_and_same_client_can_finish_cleanup(self):
        for primary in primaries():
            with self.subTest(primary=type(primary).__name__):
                transport = CleanupTransport()
                client = await AsyncClient.connect('https://host.invalid/', 'token', transport=transport)
                older = ClientError('EarlierCleanupFailed')
                cause = RuntimeError('Original body cause')
                primary.cleanup_error = older
                primary.__cause__ = cause
                try:
                    with self.assertRaises(type(primary)) as caught:
                        async with client:
                            raise primary
                    self.assertIs(caught.exception, primary)
                    self.assertIs(primary.__cause__, cause)
                    cleanup = primary.cleanup_error
                    self.assertIsInstance(cleanup, ClientError)
                    self.assertEqual(cleanup.code, 'ClientCleanupFailed')
                    self.assertIs(cleanup.cleanup_error, older)
                    self.assertIs(cleanup.cleanup_client, client)
                    if isinstance(primary, ClientError):
                        self.assertIs(primary.cleanup_client, client)
                    self.assertEqual(transport.closes, 1)
                    with self.assertRaises(ClientError) as closed:
                        client.new_submission()
                    self.assertEqual(closed.exception.code, 'ClientClosed')
                    await cleanup.cleanup_client.aclose()
                    await client.aclose()
                    self.assertEqual(transport.closes, 2)
                    self.assertIs(primary.cleanup_error, cleanup)
                    self.assertIs(cleanup.cleanup_error, older)
                    self.assertEqual(transport.operations, ['connect'])
                finally:
                    await client.aclose()

    async def test_foreign_metadata_refusal_keeps_original_with_actual_handling_context(self):
        transport = CleanupTransport()
        client = await AsyncClient.connect('https://host.invalid/', 'token', transport=transport)
        primary = MetadataRefusal('Original body failure')
        try:
            with self.assertRaises(MetadataRefusal) as caught:
                async with client:
                    raise primary
            self.assertIs(caught.exception, primary)
            self.assertIsInstance(primary.__context__, RuntimeError)
            cleanup = primary.__context__.__context__
            self.assertEqual(cleanup.code, 'ClientCleanupFailed')
            self.assertIs(cleanup.cleanup_client, client)
            self.assertEqual(transport.closes, 1)
        finally:
            await client.aclose()

    async def test_close_failure_without_body_failure_is_not_suppressed(self):
        transport = CleanupTransport()
        client = await AsyncClient.connect('https://host.invalid/', 'token', transport=transport)
        try:
            with self.assertRaises(ClientError) as caught:
                async with client:
                    pass
            self.assertEqual(caught.exception.code, 'ClientCleanupFailed')
            self.assertIsNone(caught.exception.cleanup_error)
            self.assertEqual(transport.closes, 1)
            await client.aclose()
            self.assertEqual(transport.closes, 2)
        finally:
            await client.aclose()

    async def test_no_body_preserves_same_baseexception_from_close(self):
        original = BaseException('Original cleanup stop')
        transport = CleanupTransport(error=original)
        client = await AsyncClient.connect('https://host.invalid/', 'token', transport=transport)
        try:
            with self.assertRaises(BaseException) as caught:
                async with client:
                    pass
            self.assertIs(caught.exception, original)
            self.assertEqual(transport.closes, 1)
        finally:
            await client.aclose()

    async def test_both_existing_cleanup_chains_and_prior_handle_survive(self):
        earlier_close, earlier_body = ClientError('EarlierClose'), ClientError('EarlierBody')
        cleanup = BaseException('Original cleanup stop')
        cleanup.cleanup_error = earlier_close
        previous_handle = object()
        primary = ClientError('OriginalBodyUnknown', cleanup_error=earlier_body, cleanup_client=previous_handle)
        transport = CleanupTransport(error=cleanup)
        client = await AsyncClient.connect('https://host.invalid/', 'token', transport=transport)
        try:
            with self.assertRaises(ClientError) as caught:
                async with client:
                    raise primary
            self.assertIs(caught.exception, primary)
            self.assertIs(primary.cleanup_error, cleanup)
            self.assertIs(cleanup.cleanup_error, earlier_close)
            self.assertIs(earlier_close.cleanup_error, earlier_body)
            self.assertIs(primary.cleanup_client, previous_handle)
            self.assertEqual(transport.closes, 1)
        finally:
            await client.aclose()

    async def test_successful_close_keeps_body_failure_and_earlier_association(self):
        transport = CleanupTransport(fail=False)
        client = await AsyncClient.connect('https://host.invalid/', 'token', transport=transport)
        primary = ClientError('OriginalBodyUnknown', cleanup_error=ClientError('EarlierCleanupFailed'))
        older = primary.cleanup_error
        with self.assertRaises(ClientError) as caught:
            async with client:
                raise primary
        self.assertIs(caught.exception, primary)
        self.assertIs(primary.cleanup_error, older)
        self.assertEqual(transport.closes, 1)
        await client.aclose()
        self.assertEqual(transport.closes, 1)


class SyncContextCleanupTests(unittest.TestCase):
    def test_body_exception_remains_primary_and_same_client_can_finish_cleanup(self):
        for primary in primaries():
            with self.subTest(primary=type(primary).__name__):
                transport = CleanupTransport()
                client = Client.connect('https://host.invalid/', 'token', transport=transport)
                older = ClientError('EarlierCleanupFailed')
                primary.cleanup_error = older
                try:
                    with self.assertRaises(type(primary)) as caught:
                        with client:
                            raise primary
                    self.assertIs(caught.exception, primary)
                    cleanup = primary.cleanup_error
                    self.assertEqual(cleanup.code, 'ClientCleanupFailed')
                    self.assertIs(cleanup.cleanup_error, older)
                    self.assertIs(cleanup.cleanup_client, client)
                    if isinstance(primary, ClientError):
                        self.assertIs(primary.cleanup_client, client)
                    self.assertEqual(transport.closes, 1)
                    with self.assertRaises(ClientError) as closed:
                        client.new_submission()
                    self.assertEqual(closed.exception.code, 'ClientClosed')
                    cleanup.cleanup_client.close()
                    client.close()
                    self.assertEqual(transport.closes, 2)
                    self.assertIs(primary.cleanup_error, cleanup)
                    self.assertEqual(transport.operations, ['connect'])
                finally:
                    client.close()

    def test_foreign_metadata_refusal_keeps_original_with_actual_handling_context(self):
        transport = CleanupTransport()
        client = Client.connect('https://host.invalid/', 'token', transport=transport)
        primary = MetadataRefusal('Original body failure')
        try:
            with self.assertRaises(MetadataRefusal) as caught:
                with client:
                    raise primary
            self.assertIs(caught.exception, primary)
            self.assertIsInstance(primary.__context__, RuntimeError)
            cleanup = primary.__context__.__context__
            self.assertEqual(cleanup.code, 'ClientCleanupFailed')
            self.assertIs(cleanup.cleanup_client, client)
            self.assertEqual(transport.closes, 1)
        finally:
            client.close()

    def test_close_failure_without_body_failure_is_not_suppressed(self):
        transport = CleanupTransport()
        client = Client.connect('https://host.invalid/', 'token', transport=transport)
        try:
            with self.assertRaises(ClientError) as caught:
                with client:
                    pass
            self.assertEqual(caught.exception.code, 'ClientCleanupFailed')
            self.assertIsNone(caught.exception.cleanup_error)
            self.assertEqual(transport.closes, 1)
            client.close()
            self.assertEqual(transport.closes, 2)
        finally:
            client.close()

    def test_no_body_preserves_same_baseexception_from_close(self):
        original = BaseException('Original cleanup stop')
        transport = CleanupTransport(error=original)
        client = Client.connect('https://host.invalid/', 'token', transport=transport)
        try:
            with self.assertRaises(BaseException) as caught:
                with client:
                    pass
            self.assertIs(caught.exception, original)
            self.assertEqual(transport.closes, 1)
        finally:
            client.close()

    def test_both_existing_cleanup_chains_and_prior_handle_survive(self):
        earlier_close, earlier_body = ClientError('EarlierClose'), ClientError('EarlierBody')
        cleanup = BaseException('Original cleanup stop')
        cleanup.cleanup_error = earlier_close
        previous_handle = object()
        primary = ClientError('OriginalBodyUnknown', cleanup_error=earlier_body, cleanup_client=previous_handle)
        transport = CleanupTransport(error=cleanup)
        client = Client.connect('https://host.invalid/', 'token', transport=transport)
        try:
            with self.assertRaises(ClientError) as caught:
                with client:
                    raise primary
            self.assertIs(caught.exception, primary)
            self.assertIs(primary.cleanup_error, cleanup)
            self.assertIs(cleanup.cleanup_error, earlier_close)
            self.assertIs(earlier_close.cleanup_error, earlier_body)
            self.assertIs(primary.cleanup_client, previous_handle)
            self.assertEqual(transport.closes, 1)
        finally:
            client.close()

    def test_successful_close_keeps_body_failure_and_earlier_association(self):
        transport = CleanupTransport(fail=False)
        client = Client.connect('https://host.invalid/', 'token', transport=transport)
        primary = ClientError('OriginalBodyUnknown', cleanup_error=ClientError('EarlierCleanupFailed'))
        older = primary.cleanup_error
        with self.assertRaises(ClientError) as caught:
            with client:
                raise primary
        self.assertIs(caught.exception, primary)
        self.assertIs(primary.cleanup_error, older)
        self.assertEqual(transport.closes, 1)
        client.close()
        self.assertEqual(transport.closes, 1)
