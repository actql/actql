"""Fresh POSIX/SQLite group observations; not Core or public acceptance evidence."""
import copy
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_files import LocalFileError
from actql_sdk._local_host_binding import OriginalHostBinding
from actql_sdk._local_installation import OriginalLocalInstallation
from actql_sdk._local_storage import LocalByteStore, LocalStorageError


class OriginalInstallationFileGroupTests(unittest.TestCase):
    def fixture(self):
        directory = TemporaryDirectory(prefix='actql-installation-file-group-')
        self.addCleanup(directory.cleanup)
        path = Path(directory.name)
        (path / 'source').mkdir(mode=0o700)
        (path / 'state').mkdir(mode=0o700)
        (path / 'source' / 'results').mkdir(mode=0o700)
        installation = OriginalLocalInstallation.__new__(OriginalLocalInstallation)
        installation._original = installation
        installation._closing = False
        installation._roots, installation._root_names = [], []
        installation._readers, installation._pins = [], []
        installation._root(path)
        source = installation._root(path / 'source')
        state = installation._root(path / 'state')
        installation._root(path / 'source' / 'results')
        installation._source, installation._state = source, state
        names = ('account.json', 'initialization.json', 'configuration.json', 'journal.json')
        for root_path, members in ((path / 'source', ('account.json', 'policy.json', 'raw.json')),
                                    (path / 'state', names)):
            for name in members:
                target = root_path / name
                target.write_bytes(b'original-' + name.encode())
                target.chmod(0o600)
        store = LocalByteStore(path / 'state' / 'client.sqlite3', max_records=8,
                               max_record_bytes=256, max_payload_bytes=2048)
        installation._store = store
        def cleanup():
            for pins in reversed(installation._pins):
                pins.close()
            for root, reader in reversed(installation._readers):
                root.close_original(reader)
            store.close()
            for root in reversed(installation._roots):
                root.close()
        self.addCleanup(cleanup)
        # Keep BOTH original descriptors for the same name. Grouping cannot
        # infer that one descriptor replaces the other's original custody.
        installation._read(source, 'account.json', 64)
        installation._read(source, 'raw.json', 64)
        installation._read(state, 'journal.json', 64)
        source_pins = installation._pin(source, store, 2)
        state_pins = installation._pin(state, store, 4)
        account = source_pins.read_original('account.json', max_bytes=64)
        selected = source_pins.read_original('policy.json', max_bytes=64)
        originals = tuple(state_pins.read_original(name, max_bytes=64) for name in names)
        # Exercise the real physical-current dispatcher without manufacturing
        # a Core permission result or running the unrelated scalar ABI fixture.
        binding = OriginalHostBinding.__new__(OriginalHostBinding)
        binding._original = binding
        binding._closing = False
        binding._source, binding._state = source_pins, state_pins
        binding._account, binding._selected = account, (selected,)
        (binding._staged_account, binding._initialization,
         binding._configuration, binding._journal) = originals
        binding._current, binding._expected = None, ()
        binding._active, binding._frame_epoch = True, object()
        return path, installation, binding

    def test_each_current_walks_roots_once_and_observes_every_original_descriptor_and_name(self):
        _, installation, binding = self.fixture()
        readers = [reader for _, reader in installation._readers]
        readers += [member.reader for pins in installation._pins for member in pins._files.values()]
        real_fstat, real_stat = os.fstat, os.stat
        descriptors, names = [], []
        def fstat(fd):
            descriptors.append(fd)
            return real_fstat(fd)
        def stat(name, *args, **kwargs):
            if kwargs.get('dir_fd') is not None:
                names.append((kwargs['dir_fd'], name))
            return real_stat(name, *args, **kwargs)
        with patch.object(installation, '_observe_roots', wraps=installation._observe_roots) as roots, \
                patch.object(installation._store, 'observe_generation',
                             wraps=installation._store.observe_generation) as generation, \
                patch('actql_sdk._local_files.os.fstat', side_effect=fstat), \
                patch('actql_sdk._local_files.os.stat', side_effect=stat):
            binding._physical_current()
            binding._physical_current()
        self.assertEqual(roots.call_count, 2)
        self.assertEqual(generation.call_count, 4)
        for reader in readers:
            self.assertEqual(descriptors.count(reader.descriptor), 2)
        # The raw account and journal readers and their separate pins each
        # observe the same pathname. No equal-inode/name de-duplication occurs.
        self.assertEqual(names.count((installation._source._open(), 'account.json')), 4)
        self.assertEqual(names.count((installation._state._open(), 'journal.json')), 4)
        self.assertEqual(names.count((installation._source._open(), 'raw.json')), 2)

    def test_second_call_refuses_changed_unpaired_raw_reader_without_retiring_custody(self):
        path, installation, binding = self.fixture()
        original = tuple(installation._readers)
        binding._physical_current()
        (path / 'source' / 'raw.json').write_bytes(b'changed')
        with self.assertRaises(LocalFileError):
            binding._physical_current()
        self.assertEqual(tuple(installation._readers), original)
        self.assertTrue(all(reader.descriptor is not None for _, reader in original))

    def test_raw_descriptor_failure_is_not_hidden_by_its_healthy_pin(self):
        _, installation, binding = self.fixture()
        reader = installation._readers[0][1]
        failure = OSError('original raw descriptor observation failed')
        original = os.fstat
        def fstat(fd):
            if fd == reader.descriptor:
                raise failure
            return original(fd)
        with patch('actql_sdk._local_files.os.fstat', side_effect=fstat):
            with self.assertRaises(OSError) as caught:
                binding._physical_current()
        self.assertIs(caught.exception, failure)
        self.assertIs(installation._source._original_readers[id(reader)], reader)
        self.assertIsNotNone(reader.descriptor)

    def test_same_arbitrary_observer_keeps_two_calls_in_source_state_order(self):
        _, installation, binding = self.fixture()
        events = []
        def callback():
            events.append('callback')
        for pins in installation._pins:
            pins._installation = None
            pins._observe_roots = callback
        source_observe = binding._source._observe_current_files
        state_observe = binding._state._observe_current_files
        def source():
            events.append('source')
            source_observe()
        def state():
            events.append('state')
            state_observe()
        with patch.object(binding._source, '_observe_current_files', side_effect=source), \
                patch.object(binding._state, '_observe_current_files', side_effect=state):
            binding._physical_current()
        self.assertEqual(events, ['callback', 'source', 'callback', 'state'])

    def test_arbitrary_callback_failure_stops_before_state_without_fallback(self):
        _, installation, binding = self.fixture()
        failure = OSError('original observer refused')
        def callback():
            raise failure
        for pins in installation._pins:
            pins._installation = None
            pins._observe_roots = callback
        with patch.object(binding._state, 'require_current_originals',
                          side_effect=AssertionError('State ran after source failure')):
            with self.assertRaises(OSError) as caught:
                binding._physical_current()
        self.assertIs(caught.exception, failure)

    def test_copied_installation_pin_and_member_refuse_before_observation(self):
        _, installation, binding = self.fixture()
        source_values = (binding._account, *binding._selected)
        state_values = (binding._staged_account, binding._initialization,
                        binding._configuration, binding._journal)
        with patch.object(installation, '_observe_roots',
                          side_effect=AssertionError('Invalid original reached physical I/O')):
            with self.assertRaises(ValueError):
                copy.copy(installation)._require_current_host_files(
                    binding._source, source_values, binding._state, state_values)
            with self.assertRaises(ValueError):
                installation._require_current_host_files(
                    copy.copy(binding._source), source_values, binding._state, state_values)
            with self.assertRaises(ValueError):
                installation._require_current_host_files(
                    binding._source, source_values, binding._state, (copy.copy(state_values[0]),))

    def test_pending_and_closing_state_refuse_before_root_observation(self):
        for state in ('closing', 'pending'):
            with self.subTest(state=state):
                _, _, binding = self.fixture()
                if state == 'closing':
                    binding._state._closing = True
                else:
                    reader = binding._state._files['account.json'].reader
                    binding._state._pending[id(reader)] = reader
                try:
                    with patch.object(binding._source._installation, '_observe_roots',
                                      side_effect=AssertionError('Unavailable pins reached I/O')):
                        with self.assertRaises(ValueError):
                            binding._physical_current()
                finally:
                    binding._state._pending.clear()

    def test_changed_named_root_and_store_are_observed_again(self):
        for target in ('root', 'store'):
            with self.subTest(target=target):
                path, _, binding = self.fixture()
                binding._physical_current()
                if target == 'root':
                    (path / 'source' / 'results').rename(path / 'source' / 'old-results')
                    (path / 'source' / 'results').mkdir(mode=0o700)
                    error = ValueError
                else:
                    store = path / 'state' / 'client.sqlite3'
                    store.rename(store.with_suffix('.original'))
                    store.write_bytes(b'foreign')
                    store.chmod(0o600)
                    error = LocalStorageError
                with self.assertRaises(error):
                    binding._physical_current()


if __name__ == '__main__':
    unittest.main()
