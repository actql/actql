"""Existing public factories; explicit Host port, not installed Mock execution."""
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk import AsyncClient, ClientError
from actql_sdk._local_product import InstalledLocalHost
import test_local_product_operation_port as host_fixture


class AsyncProjectConnectionTests(unittest.IsolatedAsyncioTestCase):
    async def test_named_profile_reaches_same_installed_factory_and_original_cleanup(self):
        with TemporaryDirectory(prefix='actql-project-async-') as directory:
            case = host_fixture.LocalOperationPortTests()
            self.addCleanup(case.doCleanups)
            host, core, _, _ = case.host(Path(directory))
            with patch.object(InstalledLocalHost, 'installed', return_value=host) as build:
                async with await AsyncClient.connect(mode='local', installation='.actql',
                                                     profile='mock') as client:
                    self.assertIs(client._local_host, host)
                build.assert_called_once_with(state_dir='.actql', _discover_project=True,
                                              _project_profile='mock')
            self.assertTrue(core._closed)

    async def test_invalid_profile_refuses_before_local_or_remote_acquisition(self):
        class ProfileAlias(str):
            pass
        with patch.object(InstalledLocalHost, 'installed', side_effect=AssertionError('no Host')) as build:
            for profile in (True, object(), ProfileAlias('mock'), 'x' * 65537):
                with self.assertRaises(ClientError) as caught:
                    await AsyncClient.connect(mode='local', profile=profile)
                self.assertEqual(caught.exception.code, 'InvalidConnectionOptions')
            build.assert_not_called()


class SyncProjectConnectionTests(unittest.TestCase):
    def test_readme_profile_uses_same_sync_runner_and_host(self):
        import actql
        with TemporaryDirectory(prefix='actql-project-sync-') as directory:
            case = host_fixture.LocalOperationPortTests()
            self.addCleanup(case.doCleanups)
            host, core, _, _ = case.host(Path(directory))
            with patch.object(InstalledLocalHost, 'installed', return_value=host) as build:
                with actql.connect(mode='local', installation='.actql', profile='mock') as client:
                    self.assertIs(client._client._local_host, host)
                build.assert_called_once_with(state_dir='.actql', _discover_project=True,
                                              _project_profile='mock')
            self.assertTrue(core._closed)


if __name__ == '__main__':
    unittest.main()
