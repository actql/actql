"""Public factory/custody shape; scalar Host, no actual installed product PASS."""
import asyncio
import inspect
from pathlib import Path
import os
import stat
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import ANY, Mock, patch

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

    def test_missing_initial_funding_refuses_before_cohort_discovery(self):
        with patch('actql_sdk._local_product.installed_local_components',
                   side_effect=AssertionError('Discovery before initial funding')) as resolve:
            with self.assertRaises(LocalWorkerFundingUnavailable):
                InstalledLocalHost.installed(state_dir='.actql')
        resolve.assert_not_called()

    def test_missing_initial_funding_refuses_before_module_capture_vm_directory_or_fallback(self):
        case = components_fixture.LocalDistributionTests()
        case.setUp();self.addCleanup(case.doCleanups)
        components = case.inspect()
        with patch('actql_sdk._local_product.installed_local_components', return_value=components) as resolve, \
             patch('actql_sdk._local_product.LocalCore._from_installed_image', side_effect=AssertionError('No module capture')) as capture, \
             patch('actql_sdk._local_product.LocalCore', side_effect=AssertionError('No VM')) as vm, \
             patch('actql_sdk._local_product._default_directory', side_effect=AssertionError('No Store')) as state:
            with self.assertRaises(LocalWorkerFundingUnavailable):
                InstalledLocalHost.installed()
            resolve.assert_not_called()
            self.assertEqual((capture.call_count, vm.call_count, state.call_count), (0, 0, 0))

    def test_public_factories_allow_signer_without_host_token_path_or_capacity_arguments(self):
        self.assertEqual(set(inspect.signature(Client.open).parameters), {'state_dir', 'signer'})
        self.assertEqual(set(inspect.signature(AsyncClient.open).parameters), {'state_dir', 'signer'})
        with patch.object(InstalledLocalHost, 'installed', side_effect=AssertionError('No construction')) as build:
            for options in ({'resources': object()}, {'token': 'not-local'}, {'module': '/private/foreign'}):
                with self.assertRaises(TypeError): Client.open(**options)
            self.assertEqual(build.call_count, 0)

    def test_explicit_directory_does_not_bypass_original_funding_or_create_store(self):
        case = components_fixture.LocalDistributionTests()
        case.setUp(); self.addCleanup(case.doCleanups)
        components = case.inspect()
        with patch('actql_sdk._local_product.installed_local_components', return_value=components), \
             patch('actql_sdk._local_product.LocalCore._from_installed_image', side_effect=AssertionError('No VM')) as vm, \
             patch('actql_sdk._local_product._private_state_directory', side_effect=AssertionError('No Store')) as state:
            with self.assertRaises(LocalWorkerFundingUnavailable):
                InstalledLocalHost.installed(state_dir='.actql')
        vm.assert_not_called()
        state.assert_not_called()

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
                build.assert_called_once_with(_initial_preparation=ANY)
                original = build.call_args.kwargs['_initial_preparation']
                original.require_current()
                self.assertIsNone(original._state_dir)
                self.addCleanup(original.retire_input)
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
    def test_product_directory_factory_keeps_original_pending_cleanup_client(self):
        import actql
        with TemporaryDirectory() as directory:
            case = host_fixture.LocalOperationPortTests(); self.addCleanup(case.doCleanups)
            host, core, _, _ = case.host(Path(directory))
            selected = str(Path(directory) / 'selected-state')
            with patch.object(InstalledLocalHost, 'installed', side_effect=LocalProductCleanupPending(host)) as build:
                with self.assertRaises(ClientError) as failure:
                    actql.open(state_dir=selected)
            build.assert_called_once_with(state_dir=selected, _initial_preparation=ANY)
            original = build.call_args.kwargs['_initial_preparation']
            self.assertIs(original._state_dir, selected)
            original.require_current()
            self.addCleanup(original.retire_input)
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
                build.assert_called_once_with(_initial_preparation=ANY)
                original = build.call_args.kwargs['_initial_preparation']
                original.require_current()
                self.addCleanup(original.retire_input)
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
