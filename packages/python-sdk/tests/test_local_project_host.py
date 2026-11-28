"""Actual project/File/Host custody with explicit Core semantic ports."""
import hashlib
import errno
import json
import os
from contextlib import nullcontext
from pathlib import Path
from types import SimpleNamespace
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_installation import _FILES, _SDK_FILES
from actql_sdk._local_product import InstalledLocalHost, LocalProductCleanupPending
from local_abi_declaration_fixture import original_byte_fixture_port
import test_local_product as product_fixture


CONFIG = ('{"version":"actql-config/0.1","state_dir":"./configured-state",'
          '"profile":"mock","connectors":"./connectors.json","model_tasks":"./model-tasks.json",'
          '"mock":{"catalog":"./catalog.json","data":"./raw.json",'
          '"answers":{"task:z":"./answer.yaml"}}}\r\n')
LOCATIONS = ('{"connectors":"./connectors.json","model_tasks":"./model-tasks.json","lock":null,'
             '"state_dir":"./configured-state","profile":"mock",'
             '"mock_catalog":"./catalog.json","mock_data":"./raw.json","mock_answers":[["task:z","./answer.yaml"]]}')

MOCK_DATA = rb'{"records":["exact\r\n"]}'


class LocalProjectHostTests(unittest.TestCase):
    def core(self, *, produce_code=0, locations=LOCATIONS, configuration=CONFIG):
        core, calls, _, _ = product_fixture.LocalProductAssemblyTests().core()
        previous = core._call
        selections, originals, setup_inputs, outputs = {}, {}, {}, {}
        payload = json.dumps({'body': locations,
            'cid': 'sha256:' + hashlib.sha256(locations.encode()).hexdigest()}).encode()

        def call(family, name, *args):
            if (family, name) == ('original', 'reserve') and args[1] == 6:
                handle = previous(family, name, *args)
                originals[handle] = json.loads(core._inputs[args[0] - 100].payload)
                return handle
            if (family, name) == ('original', 'produce') and args[0] in originals:
                descriptor = originals[args[0]]
                self.assertEqual(set(descriptor), {'project', 'connectors', 'catalog', 'registry'})
                self.assertIn(descriptor['project'], selections)
                calls.append((family, name, args))
                return 0
            if (family, name) == ('bootstrap', 'reserve'):
                handle = previous(family, name, *args)
                setup_inputs[handle] = args[0]
                return handle
            if (family, name) == ('bootstrap', 'produce_sdk'):
                request = json.loads(core._inputs[setup_inputs[args[0]] - 100].payload)
                self.assertIn(request['mock_project'], originals)
                outputs[args[0]] = json.dumps({
                    key: '{"opaque":"fixture original"}' for key in (_FILES | _SDK_FILES)
                }).encode()
                calls.append((family, name, args))
                return 0
            if (family, name) == ('run', 'install_sdk_configuration'):
                current, source = args
                self.assertIsNotNone(core._journal_callbacks(current - 100).reader)
                self.assertIn(json.loads(core._inputs[source - 100].payload)['mock_project'], originals)
                calls.append((family, name, args))
                return 1000000
            if name == 'length' and args[0] in outputs:
                return len(outputs[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][args[1]]
            if (family, name) == ('original', 'reserve') and args[1] == 5:
                handle = previous(family, name, *args)
                selections[handle] = args[0]
                return handle
            if family == 'original' and args[0] in selections:
                if name == 'produce':
                    fields = json.loads(core._inputs[selections[args[0]] - 100].payload)
                    self.assertEqual(fields, {'configuration': configuration, 'profile': 'mock'})
                    calls.append((family, name, args))
                    return produce_code
                if name == 'length':
                    return len(payload)
            if family == 'buffer' and name == 'byte' and args[0] in selections:
                return payload[args[1]]
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        return core, calls

    def project(self, root):
        (root / 'actql.config.json').write_bytes(CONFIG.encode())
        (root / 'connectors.json').write_bytes(b'{}')
        (root / 'model-tasks.json').write_bytes(b'{}')
        (root / 'catalog.json').write_bytes(b'{"connections":{}}\n')
        (root / 'raw.json').write_bytes(MOCK_DATA)
        (root / 'answer.yaml').write_bytes(b'original: answer\r\n')

    def test_project_metadata_opens_without_the_seed_and_returns_on_close(self):
        with TemporaryDirectory(prefix='actql-project-host-') as temporary:
            root = Path(temporary)
            self.project(root)
            core, calls = self.core()
            with patch('actql_sdk._local_project_files.os.open', wraps=os.open) as opened:
                host = InstalledLocalHost(core, root / 'explicit-state', now=lambda: 0,
                    observed_at='2026-11-02T00:00:00.000Z', sdk_finite=True,
                    _project_directory=root, _project_profile='mock')
                self.assertFalse(any(call.args[0] in ('raw.json', root / 'raw.json')
                                     for call in opened.call_args_list))
            try:
                self.assertEqual(host._installation._path, root / 'explicit-state')
                self.assertFalse((root / 'configured-state').exists())
                self.assertEqual(host._project_locations.profile, 'mock')
                self.assertIs(host._project_configuration._core, core)
                self.assertIs(host._project_files._core, core)
                members = {role: member for role, _, member in host._project_members}
                self.assertEqual(set(members),
                    {'connectors', 'model_tasks', 'mock_catalog', 'mock_answer'})
                self.assertEqual(host._project_files.original_bytes(members['mock_answer']),
                                 b'original: answer\r\n')
                self.assertEqual(host._project_files.original_bytes(members['mock_catalog']),
                                 b'{"connections":{}}\n')
                project = host._original_project_bootstrap()
                configuration, files = host._project_configuration, host._project_files
                self.assertEqual(configuration.mock_data_path(files, project), root / 'raw.json')
                self.assertIsNone(files._mock_data)
                with patch('actql_sdk._local_project_files.os.open', wraps=os.open) as opened:
                    data = configuration.acquire_mock_data(files, project)
                    self.assertIs(configuration.acquire_mock_data(files, project), data)
                    self.assertEqual(sum(call.args[0] == 'raw.json'
                                         for call in opened.call_args_list), 1)
                self.assertEqual(files.mock_data_bytes(data), MOCK_DATA)
                before = len(calls)
                with self.assertRaisesRegex(ValueError, 'project execution environment'):
                    host._original_check_environment()
                self.assertEqual(len(calls), before)
                self.assertTrue(host.close())
                self.assertTrue(core._closed)
                self.assertEqual((root / 'actql.config.json').read_bytes(), CONFIG.encode())
                self.assertEqual((root / 'answer.yaml').read_bytes(), b'original: answer\r\n')
            finally:
                host.close()

    def test_incomplete_project_refuses_before_bootstrap(self):
        with TemporaryDirectory(prefix='actql-incomplete-project-') as temporary:
            root = Path(temporary)
            self.project(root)
            fields = json.loads(CONFIG)
            del fields['connectors'], fields['model_tasks']
            configuration = json.dumps(fields)
            (root / 'actql.config.json').write_text(configuration)
            locations = json.dumps({**json.loads(LOCATIONS), 'connectors': None, 'model_tasks': None})
            core, calls = self.core(locations=locations, configuration=configuration)
            with self.assertRaises(LocalProductCleanupPending) as caught:
                InstalledLocalHost(core, None, now=lambda: 0,
                    observed_at='2026-11-02T00:00:00.000Z', sdk_finite=True,
                    _project_directory=root, _project_profile='mock')
            self.assertIn('execution environment is not installed',
                          str(caught.exception.__cause__.__cause__))
            self.assertFalse(any(family == 'bootstrap' for family, _, _ in calls))
            self.assertTrue(caught.exception.cleanup_host.close())

    def test_failed_original_configuration_keeps_same_host_before_state_creation(self):
        with TemporaryDirectory(prefix='actql-project-host-failure-') as temporary:
            root = Path(temporary)
            self.project(root)
            core, calls = self.core(produce_code=-31)
            with self.assertRaises(LocalProductCleanupPending) as caught:
                InstalledLocalHost(core, root / 'not-created', now=lambda: 0,
                    observed_at='2026-11-02T00:00:00.000Z', sdk_finite=True,
                    _project_directory=root, _project_profile='mock')
            host = caught.exception.cleanup_host
            self.assertIs(host._core, core)
            self.assertIsNotNone(host._project_files)
            self.assertIsNotNone(host._project_configuration)
            self.assertIsNone(host._installation)
            self.assertFalse((root / 'not-created').exists())
            self.assertTrue(host.close())
            self.assertTrue(core._closed)
            self.assertEqual(sum(family == 'original' and name == 'produce'
                for family, name, _ in calls), 1)

    def test_project_state_is_relative_to_original_config_and_change_refuses_before_core(self):
        with TemporaryDirectory(prefix='actql-project-state-') as temporary:
            root = Path(temporary)
            self.project(root)
            child = root / 'child'
            child.mkdir()
            core, calls = self.core()
            host = InstalledLocalHost(core, None, now=lambda: 0,
                observed_at='2026-11-02T00:00:00.000Z', sdk_finite=True,
                _project_directory=child, _project_profile='mock')
            try:
                self.assertEqual(host._installation._path, root / 'configured-state')
                self.assertFalse((child / 'configured-state').exists())
                (root / 'actql.config.json').write_bytes(b'changed-original')
                before = len(calls)
                with self.assertRaisesRegex(ValueError, 'generation changed'):
                    host._original_check_environment()
                self.assertEqual(len(calls), before)
            finally:
                self.assertTrue(host.close())

    def test_mutable_mock_data_cannot_alias_retained_project_metadata(self):
        locations = ('{"connectors":"./connectors.json","model_tasks":"./model-tasks.json","lock":null,'
            '"state_dir":"./configured-state","profile":"mock",'
            '"mock_catalog":"./raw.json","mock_data":"./raw.json","mock_answers":[["task:z","./raw.json"]]}')
        with TemporaryDirectory(prefix='actql-project-alias-') as temporary:
            root = Path(temporary)
            self.project(root)
            core, calls = self.core(locations=locations)
            with self.assertRaises(LocalProductCleanupPending) as failed:
                InstalledLocalHost(core, None, now=lambda: 0,
                    observed_at='2026-11-02T00:00:00.000Z', sdk_finite=True,
                    _project_directory=root, _project_profile='mock')
            self.assertIsInstance(failed.exception.__cause__, ValueError)
            self.assertFalse((root / 'configured-state').exists())
            self.assertFalse(any(family == 'bootstrap' for family, _, _ in calls))
            self.assertTrue(failed.exception.cleanup_host.close())
            self.assertTrue(core._closed)

    def test_failed_project_descriptor_cleanup_preserves_same_host_until_ack(self):
        with TemporaryDirectory(prefix='actql-project-close-') as temporary:
            root = Path(temporary)
            self.project(root)
            core, calls = self.core()
            host = InstalledLocalHost(core, None, now=lambda: 0,
                observed_at='2026-11-02T00:00:00.000Z', sdk_finite=True,
                _project_directory=root, _project_profile='mock')
            files = host._project_files
            descriptor = host._project_members[0][2]._descriptor.fd
            real_close = os.close

            def lost_ack(fd):
                real_close(fd)
                if fd == descriptor:
                    raise OSError(errno.EINTR, 'original close reply lost')

            with patch('actql_sdk._local_project_files.os.close', side_effect=lost_ack):
                self.assertFalse(host.close())
            self.assertIs(host._project_files, files)
            self.assertFalse(core._closed)
            self.assertIsNone(host._project_configuration)
            before = len(calls)
            self.assertTrue(host.close())
            self.assertTrue(core._closed)
            self.assertFalse(any(name == 'produce' for _, name, _ in calls[before:]))
            self.assertEqual((root / 'raw.json').read_bytes(), MOCK_DATA)


class LocalProjectFactoryTests(unittest.TestCase):
    def test_existing_factory_forwards_project_before_any_state_creation(self):
        class ConstructorPort(InstalledLocalHost):
            def __init__(self, *args, **kwargs):
                self.original_arguments = (args, kwargs)

        core, _ = LocalProjectHostTests().core()
        self.addCleanup(core.close)
        with TemporaryDirectory(prefix='actql-project-factory-') as temporary:
            directory = Path(temporary)
            with patch('actql_sdk._local_product.installed_local_components',
                       return_value=SimpleNamespace(artifact_sha256='a' * 64, model_crypto=None)), \
                 patch.object(LocalProductCleanupPending, '__init__', side_effect=AssertionError('no failure')), \
                 patch('actql_sdk._local_product.LocalCore._from_installed_image', return_value=core), \
                 patch.object(core, '_host_operation', return_value=nullcontext()), \
                 patch('actql_sdk._local_product.Path.cwd', return_value=directory), \
                 patch('actql_sdk._local_product._private_state_directory', side_effect=AssertionError('early state')), \
                 patch('actql_sdk._local_product._default_directory', side_effect=AssertionError('wrong state')):
                host = ConstructorPort.installed(state_dir='selected-state',
                    _discover_project=True, _project_profile='mock')
            args, options = host.original_arguments
            self.assertEqual(args, (core, Path('selected-state')))
            self.assertIs(options['_project_directory'], directory)
            self.assertEqual(options['_project_profile'], 'mock')
            self.assertEqual(options['_project_runtime_cid'], 'sha256:' + 'a' * 64)
            self.assertTrue(options['sdk_finite'])


if __name__ == '__main__':
    unittest.main()
