"""Public factory/custody shape; scalar Host, no actual installed product PASS."""
import asyncio
import inspect
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import Mock, patch

from actql_sdk import AsyncClient, Client, ClientError
from actql_sdk._local_distribution import LocalInstallationError
from actql_sdk._local_core import LocalCoreInitializationError
from actql_sdk._local_product import InstalledLocalHost, LocalProductCleanupPending
import test_local_distribution as components_fixture
import test_local_product_operation_port as host_fixture


class LocalFactoryResourcesTests(unittest.TestCase):
    def test_unadopted_capacity_refuses_before_module_capture_vm_directory_or_fallback(self):
        case = components_fixture.LocalDistributionTests()
        case.setUp();self.addCleanup(case.doCleanups)
        components = case.inspect()
        with patch('actql_sdk._local_product.installed_local_components', return_value=components) as resolve, \
             patch('actql_sdk._local_product.LocalCore._from_installed_image', side_effect=AssertionError('No module capture')) as capture, \
             patch('actql_sdk._local_product.LocalCore', side_effect=AssertionError('No VM')) as vm, \
             patch('actql_sdk._local_product._default_directory', side_effect=AssertionError('No Store')) as state:
            with self.assertRaisesRegex(LocalInstallationError, 'capacity original is unavailable'):
                InstalledLocalHost.installed()
            self.assertEqual(resolve.call_count, 1)
            self.assertEqual((capture.call_count, vm.call_count, state.call_count), (0, 0, 0))

    def test_public_factories_accept_no_host_token_path_or_capacity_arguments(self):
        self.assertEqual(tuple(inspect.signature(Client.open).parameters), ())
        self.assertEqual(tuple(inspect.signature(AsyncClient.open).parameters), ())
        with patch.object(InstalledLocalHost, 'installed', side_effect=AssertionError('No construction')) as build:
            for options in ({'resources': object()}, {'token': 'not-local'}, {'module': '/private/foreign'}):
                with self.assertRaises(TypeError): Client.open(**options)
            self.assertEqual(build.call_count, 0)


class AsyncLocalFactoryTests(unittest.IsolatedAsyncioTestCase):
    async def test_argumentless_factory_uses_existing_host_profile_and_close_without_run(self):
        with TemporaryDirectory() as directory:
            case = host_fixture.LocalOperationPortTests();self.addCleanup(case.doCleanups)
            host, core, events, _ = case.host(Path(directory))
            before = len(events)
            with patch.object(InstalledLocalHost, 'installed', return_value=host) as build:
                async with await AsyncClient.open() as client:
                    self.assertIs(client._local_host, host)
                    self.assertEqual(client.profile['mode'], 'local')
                build.assert_called_once_with()
            self.assertTrue(core._closed)
            self.assertFalse(host._run_loans)
            self.assertFalse(any(name in ('cancel', 'start', 'reserve_task') for _, name in events[before:]))

    async def test_missing_capacity_is_explicit_unavailability_and_not_remote_connect(self):
        with patch.object(InstalledLocalHost, 'installed', side_effect=LocalInstallationError('Unknown native envelope')) as build:
            with self.assertRaises(ClientError) as failure: await AsyncClient.open()
            self.assertEqual(failure.exception.code, 'LocalInstallationUnavailable')
            self.assertIsInstance(failure.exception.original_error, LocalInstallationError)
            self.assertEqual(build.call_count, 1)

    async def test_pending_constructor_keeps_cleanup_only_client_without_profile_io(self):
        with TemporaryDirectory() as directory:
            case = host_fixture.LocalOperationPortTests();self.addCleanup(case.doCleanups)
            host, core, events, _ = case.host(Path(directory))
            before = len(events)
            with patch.object(InstalledLocalHost, 'installed', side_effect=LocalProductCleanupPending(host)):
                with self.assertRaises(ClientError) as failure: await AsyncClient.open()
            self.assertEqual(failure.exception.code, 'LocalClientInitializationCleanupPending')
            client = failure.exception.cleanup_client
            self.assertTrue(client._closed)
            self.assertIsNone(client.profile)
            self.assertEqual(events[before:], [])
            with patch.object(host, 'close', return_value=False):
                with self.assertRaises(ClientError): await client.aclose()
            self.assertIs(client._transport, host)
            await client.aclose()
            await client.aclose()
            self.assertTrue(core._closed)
            self.assertFalse(any(name == 'cancel' for _, name in events[before:]))

    async def test_failed_vm_retains_same_core_through_public_cleanup_client(self):
        core = Mock()
        core.close.side_effect = [False, True]
        with patch.object(InstalledLocalHost, 'installed', side_effect=LocalCoreInitializationError(core)):
            with self.assertRaises(ClientError) as failure: await AsyncClient.open()
        self.assertEqual(failure.exception.code, 'LocalCoreInitializationCleanupPending')
        client = failure.exception.cleanup_client
        self.assertTrue(client._closed)
        self.assertIsNone(client.profile)
        with self.assertRaises(ClientError): await client.aclose()
        await client.aclose()
        await client.aclose()
        self.assertEqual(core.close.call_count, 2)

    async def test_sync_factory_rejects_running_application_loop_before_io(self):
        with patch.object(InstalledLocalHost, 'installed', side_effect=AssertionError('No I/O')) as build:
            with self.assertRaises(ClientError) as failure: Client.open()
            self.assertEqual(failure.exception.code, 'SyncClientInRunningEventLoop')
            self.assertEqual(build.call_count, 0)


class SyncLocalFactoryTests(unittest.TestCase):
    def test_same_argumentless_factory_negotiates_existing_host_and_closes_its_runner(self):
        with TemporaryDirectory() as directory:
            case = host_fixture.LocalOperationPortTests();self.addCleanup(case.doCleanups)
            host, core, events, _ = case.host(Path(directory))
            with patch.object(InstalledLocalHost, 'installed', return_value=host) as build:
                with Client.open() as client:
                    self.assertIs(client._client._local_host, host)
                    self.assertEqual(client.profile['mode'], 'local')
                build.assert_called_once_with()
            self.assertTrue(core._closed)
            self.assertFalse(any(name == 'cancel' for _, name in events))

    def test_failed_constructor_cleanup_retains_same_runner_and_host(self):
        with TemporaryDirectory() as directory:
            case = host_fixture.LocalOperationPortTests();self.addCleanup(case.doCleanups)
            host, core, _, _ = case.host(Path(directory))
            with patch.object(InstalledLocalHost, 'installed', side_effect=LocalProductCleanupPending(host)):
                with self.assertRaises(ClientError) as failure: Client.open()
            client = failure.exception.cleanup_client
            self.assertIsInstance(client, Client)
            with patch.object(host, 'close', return_value=False):
                with self.assertRaises(ClientError): client.close()
            client.close()
            client.close()
            self.assertTrue(core._closed)
