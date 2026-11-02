"""Public factory/custody shape; scalar Host, no actual installed product PASS."""
import asyncio
import inspect
from pathlib import Path
import os
import stat
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import Mock, patch

from actql_sdk import AsyncClient, Client, ClientError
from actql_sdk._local_distribution import (
    LocalInstallationError, LocalComponentReadCleanupPending, _read_file,
)
from actql_sdk._local_core import LocalCoreInitializationError
from actql_sdk._local_worker_funding import LocalWorkerFundingUnavailable
from actql_sdk._local_product import InstalledLocalHost, LocalProductCleanupPending, _private_state_directory
import test_local_distribution as components_fixture
import test_local_product_operation_port as host_fixture


class LocalFactoryResourcesTests(unittest.TestCase):
    def test_public_factory_keeps_original_component_fd_cleanup_failure(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'original-input'
            path.write_bytes(b'original input')
            real_open, real_close = os.open, os.close
            opened = []
            def capture(*args, **kwargs):
                descriptor = real_open(*args, **kwargs)
                opened.append(descriptor)
                return descriptor
            failure = OSError('Original input close is unconfirmed')
            def close(descriptor):
                if descriptor in opened: raise failure
                return real_close(descriptor)
            try:
                # Exercise the public error/custody path with an actual fresh
                # input reader. This does not supply initial funding or a Host.
                with patch.object(InstalledLocalHost, 'installed',
                                  side_effect=lambda **options: _read_file(path, maximum=64)), \
                     patch('actql_sdk._local_distribution.os.open', side_effect=capture), \
                     patch('actql_sdk._local_distribution.os.close', side_effect=close):
                    with self.assertRaises(ClientError) as caught: Client.open()
                self.assertEqual(caught.exception.code, 'LocalInstallationUnavailable')
                original = caught.exception.original_error
                self.assertIsInstance(original, LocalComponentReadCleanupPending)
                self.assertIs(original.cleanup_error, failure)
                self.assertEqual(opened, [original.cleanup_descriptor.value])
                self.assertEqual(os.fstat(opened[0]).st_ino, path.stat().st_ino)
            finally:
                for descriptor in opened: real_close(descriptor)

    def test_ordinary_factory_checks_installed_components_without_startup_original(self):
        failure = LocalInstallationError('Missing selected component')
        with patch('actql_sdk._local_product.installed_local_components',
                   side_effect=failure) as resolve, \
             patch('actql_sdk._local_product._private_state_directory') as state:
            with self.assertRaises(LocalInstallationError) as caught:
                InstalledLocalHost.installed(state_dir='.actql')
        self.assertIs(caught.exception, failure)
        resolve.assert_called_once_with()
        state.assert_not_called()

    def test_normal_engine_allocation_failure_does_not_create_store_or_fallback(self):
        case = components_fixture.LocalDistributionTests()
        case.setUp(); self.addCleanup(case.doCleanups)
        components = case.inspect()
        failure = MemoryError('Actual Engine allocation failed')
        with patch('actql_sdk._local_product.installed_local_components', return_value=components) as resolve, \
             patch('actql_sdk._local_product.LocalCore._from_installed_image', side_effect=failure) as construct, \
             patch('actql_sdk._local_product._default_directory') as state:
            with self.assertRaises(MemoryError) as caught:
                InstalledLocalHost.installed()
        self.assertIs(caught.exception, failure)
        resolve.assert_called_once_with()
        self.assertEqual(construct.call_count, 1)
        self.assertTrue(construct.call_args.kwargs['resources'].valid())
        self.assertNotIn('_physical_holding', construct.call_args.kwargs)
        self.assertNotIn('_child_control', construct.call_args.kwargs)
        state.assert_not_called()

    def test_public_factories_allow_signer_without_host_token_path_or_capacity_arguments(self):
        self.assertEqual(set(inspect.signature(Client.open).parameters), {'state_dir', 'signer'})
        self.assertEqual(set(inspect.signature(AsyncClient.open).parameters), {'state_dir', 'signer'})
        with patch.object(InstalledLocalHost, 'installed', side_effect=AssertionError('No construction')) as build:
            for options in ({'resources': object()}, {'token': 'not-local'}, {'module': '/private/foreign'}):
                with self.assertRaises(TypeError): Client.open(**options)
            self.assertEqual(build.call_count, 0)

    def test_pathlike_is_captured_once_before_actual_component_acquisition(self):
        class SelectedPath:
            calls = 0
            def __fspath__(self):
                self.calls += 1
                return '.actql'
        selected = SelectedPath()
        failure = LocalInstallationError('No selected installed runtime')
        with patch('actql_sdk._local_product.installed_local_components', side_effect=failure) as resolve:
            with self.assertRaises(LocalInstallationError):
                InstalledLocalHost.installed(state_dir=selected)
        self.assertEqual(selected.calls, 1)
        resolve.assert_called_once_with()

    def test_invalid_or_oversized_path_refuses_before_component_acquisition(self):
        with patch('actql_sdk._local_product.installed_local_components') as resolve:
            for selected in ('', 'a\x00b', 'a' * 4097, '\U0001f642' * 1025, b'bytes'):
                with self.subTest(selected=repr(selected)[:40]):
                    with self.assertRaises((ValueError, TypeError)):
                        InstalledLocalHost.installed(state_dir=selected)
        resolve.assert_not_called()

    def test_selected_store_is_private_and_keeps_existing_original_files(self):
        with TemporaryDirectory() as directory:
            selected = Path(directory) / 'selected-state'
            self.assertEqual(_private_state_directory(selected), selected)
            self.assertEqual(stat.S_IMODE(selected.stat().st_mode), 0o700)
            original = selected / 'original'
            original.write_bytes(b'original-state')
            identity = os.stat(selected)
            self.assertEqual(_private_state_directory(selected), selected)
            self.assertEqual((selected.stat().st_dev, selected.stat().st_ino), (identity.st_dev, identity.st_ino))
            self.assertEqual(original.read_bytes(), b'original-state')

    def test_selected_store_alias_refuses_without_touching_its_target(self):
        with TemporaryDirectory() as directory:
            target = Path(directory) / 'target'
            target.mkdir(mode=0o700)
            original = target / 'original'
            original.write_bytes(b'original-state')
            selected = Path(directory) / 'selected-state'
            selected.symlink_to(target, target_is_directory=True)
            identity = target.stat()
            with self.assertRaises(ValueError): _private_state_directory(selected)
            self.assertTrue(selected.is_symlink())
            self.assertEqual((target.stat().st_dev, target.stat().st_ino), (identity.st_dev, identity.st_ino))
            self.assertEqual(original.read_bytes(), b'original-state')

    def test_nonprivate_selected_store_refuses_without_changing_permissions(self):
        with TemporaryDirectory() as directory:
            selected = Path(directory) / 'selected-state'
            selected.mkdir(mode=0o700)
            selected.chmod(0o755)
            with self.assertRaises(ValueError): _private_state_directory(selected)
            self.assertEqual(stat.S_IMODE(selected.stat().st_mode), 0o755)


class AsyncLocalFactoryTests(unittest.IsolatedAsyncioTestCase):
    async def test_named_local_connect_uses_same_installed_host_and_directory(self):
        with TemporaryDirectory() as directory:
            case = host_fixture.LocalOperationPortTests(); self.addCleanup(case.doCleanups)
            host, core, events, _ = case.host(Path(directory))
            selected = Path(directory) / 'selected-state'
            with patch.object(InstalledLocalHost, 'installed', return_value=host) as build, \
                 patch('actql_sdk._async.httpx.AsyncClient', side_effect=AssertionError('No Remote transport')):
                async with await AsyncClient.connect(mode='local', installation=selected) as client:
                    self.assertIs(client._local_host, host)
                    self.assertEqual(client.profile['mode'], 'local')
                build.assert_called_once_with(state_dir=selected, _discover_project=True,
                                              _project_profile=None)
            self.assertTrue(core._closed)
            self.assertFalse(any(name in ('cancel', 'start', 'reserve_task') for _, name in events))

    async def test_named_local_connect_keeps_same_pending_cleanup_host(self):
        with TemporaryDirectory() as directory:
            case = host_fixture.LocalOperationPortTests(); self.addCleanup(case.doCleanups)
            host, core, events, _ = case.host(Path(directory))
            before = len(events)
            with patch.object(InstalledLocalHost, 'installed', side_effect=LocalProductCleanupPending(host)) as build:
                with self.assertRaises(ClientError) as failure:
                    await AsyncClient.connect(mode='local', installation='.actql')
            self.assertEqual(failure.exception.code, 'LocalClientInitializationCleanupPending')
            client = failure.exception.cleanup_client
            self.assertIs(client._local_host, host)
            self.assertEqual(events[before:], [])
            build.assert_called_once_with(state_dir='.actql', _discover_project=True,
                                          _project_profile=None)
            await client.aclose()
            self.assertTrue(core._closed)

    async def test_named_connection_rejects_mixed_or_internal_options_before_io(self):
        with patch.object(InstalledLocalHost, 'installed', side_effect=AssertionError('No Local construction')) as build, \
             patch('actql_sdk._async.httpx.AsyncClient', side_effect=AssertionError('No Remote transport')) as remote:
            for options in ({'mode': 'local', 'endpoint': 'https://example.test'},
                            {'mode': 'local', 'token': 'not-local'},
                            {'mode': 'local', 'resources': object()},
                            {'mode': 'remote', 'endpoint': 'https://example.test', 'installation': '.actql'},
                            {'mode': 'other', 'endpoint': 'https://example.test'}):
                with self.subTest(mode=options['mode']), self.assertRaises(ClientError):
                    await AsyncClient.connect(**options)
            build.assert_not_called()
            remote.assert_not_called()

    async def test_missing_physical_worker_funding_is_typed_and_never_remote_or_vm(self):
        with patch.object(InstalledLocalHost, 'installed', side_effect=LocalWorkerFundingUnavailable('Original funding unavailable')), \
                patch('actql_sdk._async.AsyncClient.connect', side_effect=AssertionError('No Remote fallback')) as remote:
            with self.assertRaises(ClientError) as failure: await AsyncClient.open()
        self.assertEqual(failure.exception.code, 'LocalExecutionFundingUnavailable')
        self.assertIsInstance(failure.exception.original_error, LocalWorkerFundingUnavailable)
        remote.assert_not_called()

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
    def test_product_named_local_connect_keeps_same_runner_host_and_directory(self):
        import actql
        with TemporaryDirectory() as directory:
            case = host_fixture.LocalOperationPortTests(); self.addCleanup(case.doCleanups)
            host, core, events, _ = case.host(Path(directory))
            selected = Path(directory) / 'selected-state'
            with patch.object(InstalledLocalHost, 'installed', return_value=host) as build, \
                 patch('actql_sdk._async.httpx.AsyncClient', side_effect=AssertionError('No Remote transport')):
                with actql.connect(mode='local', installation=selected) as client:
                    self.assertIs(client._client._local_host, host)
                    self.assertEqual(client.profile['mode'], 'local')
                build.assert_called_once_with(state_dir=selected, _discover_project=True,
                                              _project_profile=None)
            self.assertTrue(core._closed)
            self.assertFalse(any(name in ('cancel', 'start', 'reserve_task') for _, name in events))

    def test_product_directory_factory_keeps_original_pending_cleanup_client(self):
        import actql
        with TemporaryDirectory() as directory:
            case = host_fixture.LocalOperationPortTests(); self.addCleanup(case.doCleanups)
            host, core, _, _ = case.host(Path(directory))
            selected = str(Path(directory) / 'selected-state')
            with patch.object(InstalledLocalHost, 'installed', side_effect=LocalProductCleanupPending(host)) as build:
                with self.assertRaises(ClientError) as failure:
                    actql.open(state_dir=selected)
            build.assert_called_once_with(state_dir=selected)
            client = failure.exception.cleanup_client
            self.assertIsInstance(client, Client)
            self.assertIs(client._client._local_host, host)
            with patch.object(host, 'close', return_value=False):
                with self.assertRaises(ClientError): client.close()
            client.close()
            self.assertTrue(core._closed)

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
