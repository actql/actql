"""Actual project/File/Host custody with explicit Core semantic ports."""
import hashlib
import errno
import json
import os
from contextlib import nullcontext
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_product import InstalledLocalHost, LocalProductCleanupPending
from local_abi_declaration_fixture import original_byte_fixture_port
import test_local_product as product_fixture


CONFIG = ('{"version":"actql-config/0.1","state_dir":"./configured-state",'
          '"profile":"production","mock":{"data":"./raw.json",'
          '"answers":{"task:z":"./answer.yaml"}}}\r\n')
LOCATIONS = ('{"connectors":null,"model_tasks":null,"lock":null,'
             '"state_dir":"./configured-state","profile":"mock",'
             '"mock_data":"./raw.json","mock_answers":[["task:z","./answer.yaml"]]}')


class LocalProjectHostTests(unittest.TestCase):
    def core(self, *, produce_code=0, locations=LOCATIONS):
        core, calls, _, _ = product_fixture.LocalProductAssemblyTests().core()
        previous = core._call
        selections = {}
        payload = json.dumps({'body': locations,
            'cid': 'sha256:' + hashlib.sha256(locations.encode()).hexdigest()}).encode()

        def call(family, name, *args):
            if (family, name) == ('original', 'reserve') and args[1] == 5:
                handle = previous(family, name, *args)
                selections[handle] = args[0]
                return handle
            if family == 'original' and args[0] in selections:
                if name == 'produce':
                    fields = json.loads(core._inputs[selections[args[0]] - 100].payload)
                    self.assertEqual(fields, {'configuration': CONFIG, 'profile': 'mock'})
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
        (root / 'raw.json').write_bytes(b'{"records":["exact\\r\\n"]}')
        (root / 'answer.yaml').write_bytes(b'original: answer\r\n')

    def test_same_project_originals_are_retained_before_store_and_returned_on_close(self):
        with TemporaryDirectory(prefix='actql-project-host-') as temporary:
            root = Path(temporary)
            self.project(root)
            core, calls = self.core()
            host = InstalledLocalHost(core, root / 'explicit-state', now=lambda: 0,
                observed_at='2026-11-02T00:00:00.000Z',
                _project_directory=root, _project_profile='mock')
            try:
                self.assertEqual(host._installation._path, root / 'explicit-state')
                self.assertFalse((root / 'configured-state').exists())
                self.assertEqual(host._project_locations.profile, 'mock')
                self.assertIs(host._project_configuration._core, core)
                self.assertIs(host._project_files._core, core)
                self.assertEqual([role for role, _, _ in host._project_members],
                                 ['mock_data', 'mock_answer'])
                self.assertEqual(host._project_files.original_bytes(host._project_members[1][2]),
                                 b'original: answer\r\n')
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

    def test_failed_original_configuration_keeps_same_host_before_state_creation(self):
        with TemporaryDirectory(prefix='actql-project-host-failure-') as temporary:
            root = Path(temporary)
            self.project(root)
            core, calls = self.core(produce_code=-31)
            with self.assertRaises(LocalProductCleanupPending) as caught:
                InstalledLocalHost(core, root / 'not-created', now=lambda: 0,
                    observed_at='2026-11-02T00:00:00.000Z',
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
                observed_at='2026-11-02T00:00:00.000Z',
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

    def test_repeated_selected_path_retains_same_original_file_not_second_read(self):
        locations = ('{"connectors":null,"model_tasks":null,"lock":null,'
            '"state_dir":"./configured-state","profile":"mock",'
            '"mock_data":"./raw.json","mock_answers":[["task:z","./raw.json"]]}')
        with TemporaryDirectory(prefix='actql-project-alias-') as temporary:
            root = Path(temporary)
            self.project(root)
            core, calls = self.core(locations=locations)
            host = InstalledLocalHost(core, None, now=lambda: 0,
                observed_at='2026-11-02T00:00:00.000Z',
                _project_directory=root, _project_profile='mock')
            try:
                self.assertIs(host._project_members[0][2], host._project_members[1][2])
                self.assertEqual(len(host._project_files._files), 2)
            finally:
                self.assertTrue(host.close())

    def test_failed_project_descriptor_cleanup_preserves_same_host_until_ack(self):
        with TemporaryDirectory(prefix='actql-project-close-') as temporary:
            root = Path(temporary)
            self.project(root)
            core, calls = self.core()
            host = InstalledLocalHost(core, None, now=lambda: 0,
                observed_at='2026-11-02T00:00:00.000Z',
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
            self.assertEqual((root / 'raw.json').read_bytes(), b'{"records":["exact\\r\\n"]}')


class LocalProjectFactoryTests(unittest.TestCase):
    def test_existing_factory_forwards_project_before_any_state_creation(self):
        class ConstructorPort(InstalledLocalHost):
            def __init__(self, *args, **kwargs):
                self.original_arguments = (args, kwargs)

        core, _ = LocalProjectHostTests().core()
        self.addCleanup(core.close)
        with TemporaryDirectory(prefix='actql-project-factory-') as temporary:
            directory = Path(temporary)
            with patch('actql_sdk._local_product.installed_local_components', return_value=object()), \
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
            self.assertTrue(options['sdk_finite'])


if __name__ == '__main__':
    unittest.main()
