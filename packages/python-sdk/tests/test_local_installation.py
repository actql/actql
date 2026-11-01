"""Actual original installation IO with neutral scalar Core; not Wasm/public PASS."""
import hashlib
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import RLock
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCore
from actql_sdk._local_files import LocalFileRoot
from actql_sdk._local_installation import OriginalLocalInstallation, LocalInstallationCleanupPending
from actql_sdk._local_storage import LocalByteStore, LocalStorageCommitUnknown
from local_abi_declaration_fixture import original_byte_fixture_port


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()


class OriginalLocalInstallationTests(unittest.TestCase):
    def core(self):
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._inputs = {}
        core._loans = {}
        core._released = set()
        core._next_ticket = 1
        core._closing = core._closed = False
        calls = []
        outputs = {}
        projections = {}
        # Independent opaque material, not an assertion of Account/Policy
        # validation. The real Core must still perform its own admission.
        packet = {name: '{"original":"e\u0301\\r\\n","null":null}' for name in (
            'account', 'retention_dependencies', 'retention_policy', 'store',
            'result_policy', 'environment', 'compute')}
        def source(handle):
            return core._inputs[handle - 100].payload
        def call(family, name, *args):
            calls.append((family, name, args))
            if name == 'reserve':
                ticket = args[0] if family in ('workspace', 'buffer') else args[1] if family == 'bootstrap' else args[2] if family == 'original' else args[1]
                handle = 100 + ticket
                if family == 'original':
                    projections[handle] = (args[0], args[1])
                return handle
            if family == 'buffer' and name in ('fill', 'seal'):
                return 0
            if family == 'bootstrap' and name == 'produce':
                outputs[args[0]] = encode(packet)
                return 0
            if family == 'original' and name == 'produce':
                original, kind = projections[args[0]]
                fields = json.loads(source(original))
                # Canonical transport only for the independent scalar double.
                # No Scope, Allow, Run, publication or ACK is emitted here.
                body = json.dumps(fields if kind == 1 else {'kind': kind, 'fields': fields}, ensure_ascii=False,
                                  sort_keys=True, separators=(',', ':'))
                outputs[args[0]] = encode({'body': body, 'cid': 'sha256:' + hashlib.sha256(body.encode()).hexdigest()})
                return 0
            if name == 'length':
                return len(outputs[args[0]])
            if family == 'buffer' and name == 'byte':
                return outputs[args[0]][args[1]]
            if family == 'current' and name in ('bind', 'validate'):
                self.assertIsNotNone(core._journal_callbacks(args[0] - 100).reader)
                return 0
            if name == 'close':
                return 0 if core._cleanup(args[0] - 100) == 0 else -9
            raise AssertionError('Unexpected Source/Compute/Model/Effect/Run/permission call')
        core._call = original_byte_fixture_port(call)
        return core, calls

    def create(self, core, path):
        value = OriginalLocalInstallation(core, path, observed_at='2026-10-12T00:00:00.000Z',
            now=lambda: 0, project_epoch=lambda *_: self.fail('Unexpected epoch issue/projection'))
        self.addCleanup(value.close)
        return value

    def test_consumed_bootstrap_transfer_is_closed_before_installation_returns(self):
        with TemporaryDirectory(prefix='actql-install-') as directory:
            core, calls = self.core()
            value = self.create(core, Path(directory))
            self.assertFalse(any(family in ('bootstrap', 'bootstrap_sdk')
                                 for family, _ in value._outputs))
            produced = next(args[0] for family, name, args in calls
                            if (family, name) == ('bootstrap', 'produce'))
            self.assertTrue(any((family, name, args) == ('bootstrap', 'close', (produced,))
                                for family, name, args in calls))

    def test_consumed_initial_readers_retire_after_same_original_host_pins_bind(self):
        # Actual filesystem/Store/pins with the existing explicit scalar Core
        # port. This is not actual Common/normal installed qualification.
        with TemporaryDirectory(prefix='actql-install-') as directory:
            core, calls = self.core()
            value = self.create(core, Path(directory))
            pins = {(pin._root, member.name): member
                    for pin in value._pins for member in pin._files.values()}
            redundant = [(root, reader) for root, reader in value._readers
                         if (root, reader.name) in pins]
            self.assertEqual(redundant, [])
            self.assertEqual(len(pins), 11)
            for (root, _), member in pins.items():
                self.assertIs(root._original_readers[id(member.reader)], member.reader)
                self.assertEqual(root.observe_original(member.reader), member.snapshot)
            before = len(calls)
            value.binding.inspect(lambda _: None)
            self.assertGreater(len(calls), before)
            self.assertTrue(value.close())

    def test_unmatched_initial_reader_is_kept_under_the_same_installation(self):
        with TemporaryDirectory(prefix='actql-install-') as directory:
            core, _ = self.core()
            value = self.create(core, Path(directory))
            path = Path(directory) / 'source/unpaired.json'
            path.write_bytes(b'{"original":"unpaired"}')
            path.chmod(0o600)
            self.assertEqual(value._read(value._source, path.name, 64), path.read_bytes())
            original = value._readers[0]
            value._retire_preparation_readers()
            self.assertEqual(value._readers, [original])
            self.assertIs(original[0]._original_readers[id(original[1])], original[1])
            self.assertTrue(value.close())
            self.assertTrue(path.exists())

    def test_equal_bytes_foreign_file_refuses_before_consumed_reader_retirement(self):
        with TemporaryDirectory(prefix='actql-install-') as directory:
            path = Path(directory)
            core, calls = self.core()
            retire = OriginalLocalInstallation._retire_preparation_readers
            selected = []
            def replace(value):
                root, reader = value._readers[0]
                selected.append((root, reader))
                file = path / 'source' / reader.name
                raw = file.read_bytes()
                file.rename(file.with_suffix('.original'))
                file.write_bytes(raw)
                file.chmod(0o600)
                return retire(value)
            with patch.object(OriginalLocalInstallation, '_retire_preparation_readers', replace):
                with self.assertRaises(LocalInstallationCleanupPending) as raised:
                    self.create(core, path)
            value = raised.exception.cleanup_installation
            self.assertIn(selected[0], value._readers)
            self.assertIsNotNone(selected[0][1].descriptor)
            self.assertTrue(value.close())
            self.assertEqual(sum((family, name) == ('bootstrap', 'produce')
                                 for family, name, _ in calls), 1)

    def test_lost_consumed_reader_close_ack_retains_same_cleanup_without_reclose(self):
        with TemporaryDirectory(prefix='actql-install-') as directory:
            core, calls = self.core()
            close = LocalFileRoot.close_original
            physical_close = os.close
            stopped = []
            def lost_ack(root, reader):
                stopped.append((root, reader, reader.descriptor))
                def stop(descriptor):
                    physical_close(descriptor)
                    raise OSError('Original preparation reader close ack lost')
                with patch('actql_sdk._local_files.os.close', side_effect=stop):
                    return close(root, reader)
            with patch.object(LocalFileRoot, 'close_original', lost_ack):
                with self.assertRaises(LocalInstallationCleanupPending) as raised:
                    self.create(core, Path(directory))
            self.assertEqual(len(stopped), 1)
            root, reader, descriptor = stopped[0]
            value = raised.exception.cleanup_installation
            self.assertIn((root, reader), value._readers)
            self.assertTrue(reader.close_pending)
            self.assertIs(root._original_readers[id(reader)], reader)
            with patch('actql_sdk._local_files.os.close', wraps=physical_close) as closed:
                self.assertTrue(value.close())
                self.assertNotIn((descriptor,), [call.args for call in closed.call_args_list])
            self.assertEqual(sum((family, name) == ('bootstrap', 'produce')
                                 for family, name, _ in calls), 1)

    def test_changed_pin_after_consumed_reader_close_refuses_with_remaining_owner(self):
        with TemporaryDirectory(prefix='actql-install-') as directory:
            path = Path(directory)
            core, _ = self.core()
            close = LocalFileRoot.close_original
            stopped = []
            def change(root, reader):
                result = close(root, reader)
                stopped.append((root, reader))
                (path / 'source' / reader.name).write_bytes(b'{"changed":true}')
                return result
            with patch.object(LocalFileRoot, 'close_original', change):
                with self.assertRaises(LocalInstallationCleanupPending) as raised:
                    self.create(core, path)
            self.assertEqual(len(stopped), 1)
            value = raised.exception.cleanup_installation
            self.assertNotIn(stopped[0], value._readers)
            self.assertTrue(value._pins)
            self.assertTrue(value.close())

    def test_named_root_change_after_consumed_close_refuses_before_constructor_returns(self):
        with TemporaryDirectory(prefix='actql-install-') as directory:
            path = Path(directory)
            core, _ = self.core()
            close = LocalFileRoot.close_original
            stopped = []
            def change(root, reader):
                result = close(root, reader)
                stopped.append((root, reader))
                if len(stopped) == 1:
                    source = path / 'source'
                    source.rename(path / 'source-original')
                    source.mkdir(mode=0o700)
                return result
            with patch.object(LocalFileRoot, 'close_original', change):
                with self.assertRaises(LocalInstallationCleanupPending) as raised:
                    self.create(core, path)
            self.assertEqual(len(stopped), 1)
            value = raised.exception.cleanup_installation
            self.assertNotIn(stopped[0], value._readers)
            self.assertTrue(value.close())

    def test_pending_bootstrap_retirement_keeps_same_output_without_rebootstrap(self):
        with TemporaryDirectory(prefix='actql-install-') as directory:
            core, calls = self.core()
            original_call = core._call
            pending = True
            def call(family, name, *args):
                if (family, name) == ('bootstrap', 'close') and pending:
                    calls.append((family, name, args))
                    return -9
                return original_call(family, name, *args)
            core._call = original_byte_fixture_port(call)
            with self.assertRaises(LocalInstallationCleanupPending) as raised:
                self.create(core, Path(directory))
            value = raised.exception.cleanup_installation
            bootstrap = next(output for family, output in value._outputs if family == 'bootstrap')
            self.assertIs(core._loans[bootstrap.ticket], bootstrap)
            pending = False
            self.assertTrue(value.close())
            self.assertEqual(sum((family, name) == ('bootstrap', 'produce')
                                 for family, name, _ in calls), 1)

    def test_initial_originals_marker_store_and_reopen_never_bootstrap_again(self):
        with TemporaryDirectory(prefix='actql-install-') as directory:
            path = Path(directory)
            core, calls = self.core()
            value = self.create(core, path)
            original = {str(p.relative_to(path)): p.read_bytes() for p in path.rglob('*.json')}
            epoch = value._store.read('submission-epoch-authority')
            generation = value._store.observe_generation()
            value.binding.inspect(lambda _: None)
            self.assertTrue(value.close())
            self.assertEqual(sum(family == 'bootstrap' and name == 'produce' for family, name, _ in calls), 1)
            other_core, other_calls = self.core()
            reopened = self.create(other_core, path)
            self.assertEqual(reopened._store.observe_generation(), generation)
            self.assertEqual(reopened._store.read('submission-epoch-authority'), epoch)
            self.assertEqual({str(p.relative_to(path)): p.read_bytes() for p in path.rglob('*.json')}, original)
            self.assertFalse(any(family == 'bootstrap' for family, _, _ in other_calls))
            self.assertTrue(reopened.close())

    def test_partial_installation_does_not_bootstrap_or_create_state(self):
        with TemporaryDirectory(prefix='actql-install-') as directory:
            path = Path(directory)
            (path / 'source').mkdir(mode=0o700)
            core, calls = self.core()
            with self.assertRaises(LocalInstallationCleanupPending) as raised:
                self.create(core, path)
            self.assertTrue(raised.exception.cleanup_installation.close())
            self.assertEqual(calls, [])
            self.assertFalse((path / 'state').exists())

    def test_missing_saved_policy_is_not_repaired_or_reissued(self):
        with TemporaryDirectory(prefix='actql-install-') as directory:
            path = Path(directory)
            core, _ = self.core()
            first = self.create(core, path)
            self.assertTrue(first.close())
            policy = path / 'source/result-policy.json'
            policy.unlink()
            other, calls = self.core()
            with self.assertRaises(LocalInstallationCleanupPending) as raised:
                self.create(other, path)
            self.assertTrue(raised.exception.cleanup_installation.close())
            self.assertFalse(policy.exists())
            self.assertFalse(any(family == 'bootstrap' for family, _, _ in calls))

    def test_named_source_or_managed_directory_change_invalidates_current(self):
        for name in ('source', 'source/results'):
            with self.subTest(name=name), TemporaryDirectory(prefix='actql-install-') as directory:
                path = Path(directory)
                core, calls = self.core()
                value = self.create(core, path)
                original = path / name
                original.rename(original.with_name(original.name + '-old'))
                original.mkdir(mode=0o700)
                before = len(calls)
                with self.assertRaises(ValueError):
                    value.binding.inspect(lambda _: self.fail('Foreign directory reached Core work'))
                self.assertEqual(len(calls), before)
                self.assertTrue(value.close())

    def test_short_or_unknown_initial_write_preserves_partial_files_and_same_handle(self):
        with TemporaryDirectory(prefix='actql-install-') as directory:
            path = Path(directory)
            core, calls = self.core()
            failure = OSError('Original installation write unknown')
            with patch('actql_sdk._local_files.os.write', side_effect=failure) as written:
                with self.assertRaises(LocalInstallationCleanupPending) as raised:
                    self.create(core, path)
                self.assertEqual(written.call_count, 1)
            value = raised.exception.cleanup_installation
            self.assertIs(raised.exception.__cause__, failure)
            self.assertEqual(len(value._writers), 1)
            self.assertTrue(value.close())
            self.assertTrue((path / 'source/account.json').exists())
            self.assertFalse((path / 'state/client.sqlite3').exists())
            next_core, next_calls = self.core()
            with self.assertRaises(LocalInstallationCleanupPending) as reopened:
                self.create(next_core, path)
            self.assertTrue(reopened.exception.cleanup_installation.close())
            self.assertFalse(any(family == 'bootstrap' for family, _, _ in next_calls))

    def test_initial_key_settings_and_adoption_share_one_commit_and_lost_ack_is_only_reopened(self):
        with TemporaryDirectory(prefix='actql-install-') as directory:
            path = Path(directory)
            core, _ = self.core()
            original = LocalByteStore.compare_exchange_many
            batches = []
            def lose(store, writes, *args, **kwargs):
                result = original(store, writes, *args, **kwargs)
                if any(write.key == 'submission-epoch-authority' for write in writes):
                    batches.append(writes)
                    raise LocalStorageCommitUnknown(store)
                return result
            with patch.object(LocalByteStore, 'compare_exchange_many', autospec=True, side_effect=lose):
                with self.assertRaises(LocalInstallationCleanupPending) as raised:
                    self.create(core, path)
            pending = raised.exception.cleanup_installation
            self.assertEqual(len(batches), 1)
            keys = {write.key for write in batches[0]}
            self.assertIn('submission-epoch-authority', keys)
            self.assertIn(pending._store.namespaced_key('client_local_adoption', 'adoption'), keys)
            self.assertIn(pending._store.namespaced_key('client_local_settings', 'manifest'), keys)
            retained_key = pending._store.read('submission-epoch-authority')
            self.assertTrue(pending.close())
            next_core, calls = self.core()
            with patch.object(LocalByteStore, 'compare_exchange_many', side_effect=AssertionError('Reopen replayed initialization')):
                reopened = self.create(next_core, path)
            self.assertEqual(reopened._store.read('submission-epoch-authority'), retained_key)
            self.assertFalse(any(family == 'bootstrap' for family, _, _ in calls))
            self.assertTrue(reopened.close())


if __name__ == '__main__':
    unittest.main()
