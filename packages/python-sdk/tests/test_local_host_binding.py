"""Actual file/SQLite supplier, scalar Core double; not actual Wasm or adoption."""
import copy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import RLock
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCore, LocalCoreError, _Output, _PhysicalInput
from actql_sdk._local_files import LocalFileRoot, LocalFileError
from actql_sdk._local_host_binding import OriginalHostBinding, LocalHostBindingCleanupPending
from actql_sdk._local_host_files import LocalHostFiles
from actql_sdk._local_storage import ByteWrite, LocalByteStore, LocalStorageError
from actql_sdk._local_submission import LocalSubmissionAuthority, LocalSubmissionIdentityError


class OriginalHostBindingTests(unittest.TestCase):
    def test_owned_inventory_uses_direct_rows_without_arbitrary_consumer_callbacks(self):
        _, store, core, _, _, _, _, calls, _, _, binding = self.fixture()
        original = LocalByteStore._inspect_namespace_locked
        counts = {'direct': 0, 'consumer': 0}
        readers = []
        def inspect_frame(owner, inspect, fences, current, **kwargs):
            def inspect_reader(reader):
                readers.append(reader)
                query, scan = reader.query_current, reader.scan_after
                def direct(view, mode, namespace, key, observer):
                    result = query(view, mode, namespace, key, observer)
                    counts['direct'] += 1
                    return result
                def callback(namespace, cursor, consume):
                    counts['consumer'] += 1
                    return scan(namespace, cursor, consume)
                # Retain the actual same reader/closure identities. A copied
                # reader must not substitute for the enclosing Store frame.
                object.__setattr__(reader, 'query_current', direct)
                object.__setattr__(reader, 'scan_after', callback)
                return inspect(reader)
            return original(owner, inspect_reader, fences, current, **kwargs)
        changes = store._connection.total_changes
        with patch.object(LocalByteStore, '_inspect_namespace_locked', inspect_frame):
            binding.inspect(lambda current: self.assertIs(current, binding._current))
        self.assertEqual(counts['consumer'], 0)
        # Two complete singleton/settings inventories, including each trailing
        # absence: adoption2 + settings3 before and after the Core consumer.
        self.assertEqual(counts['direct'], 10)
        self.assertEqual(store._connection.total_changes, changes)
        self.assertFalse(store._connection.in_transaction)
        self.assertEqual([name for family, name, _ in calls if family == 'current'][-2:],
                         ['bind', 'validate'])
        with self.assertRaises(ValueError):
            readers[0].query_current(readers[0], 0, 'client_local_adoption', '',
                                     binding._current_observer)
        self.assertEqual(counts['direct'], 10)
        self.assertIsNone(core._journal_callbacks(binding._current.ticket).reader)
        self.assertTrue(binding.close())

    def test_owned_inventory_return_observes_changed_file_and_temp_schema(self):
        for mutation in ('file', 'temp-schema'):
            with self.subTest(mutation=mutation):
                path, store, core, _, _, _, _, calls, _, _, binding = self.fixture()
                raw = type(store._physical).scan_range
                queries = []
                def changed(database, *args, **kwargs):
                    result = raw(database, *args, **kwargs)
                    queries.append(True)
                    if mutation == 'file':
                        (path / 'source' / 'account.json').write_bytes(b'changed-original')
                    else:
                        store._connection.execute('CREATE TEMP TABLE core_bytes(key, generation, payload)')
                    return result
                before = len(calls)
                error = LocalFileError if mutation == 'file' else LocalStorageError
                original = binding._current
                with patch.object(type(store._physical), 'scan_range', changed):
                    with self.assertRaises(error):
                        binding.inspect(lambda _: self.fail('Changed original inventory reached Core'))
                self.assertEqual(len(queries), 1)
                self.assertEqual(len(calls), before)
                self.assertIs(core._loans[original.ticket], original)
                self.assertIsNone(core._journal_callbacks(original.ticket).reader)
                self.assertFalse(store._connection.in_transaction)
                self.assertTrue(binding.close())

    def test_owned_inventory_sql_failure_keeps_original_cause_without_fallback(self):
        import sqlite3
        _, store, core, _, _, _, _, calls, _, _, binding = self.fixture()
        failure = sqlite3.OperationalError('original owned inventory read failure')
        original = binding._current
        before = len(calls)
        with patch.object(type(store._physical), 'scan_range', side_effect=failure) as read:
            with self.assertRaises(sqlite3.OperationalError) as caught:
                binding.inspect(lambda _: self.fail('Failed inventory reached Core'))
        self.assertIs(caught.exception, failure)
        self.assertEqual(read.call_count, 1)
        self.assertEqual(len(calls), before)
        self.assertIs(core._loans[original.ticket], original)
        self.assertIsNone(core._journal_callbacks(original.ticket).reader)
        self.assertFalse(store._connection.in_transaction)
        self.assertTrue(binding.close())

    def test_owned_inventory_direct_rows_keep_independent_physical_adapter_checks(self):
        _, store, _, _, _, _, _, _, _, _, binding = self.fixture()
        database = store._physical
        class ExistingPhysicalPort:
            def __getattr__(self, name):
                return getattr(database, name)
        store._physical = ExistingPhysicalPort()
        seen = []
        binding.inspect(lambda current: seen.append(current))
        self.assertEqual(seen, [binding._current])
        self.assertFalse(store._connection.in_transaction)
        self.assertTrue(binding.close())

    def fixture(self, *, create=True):
        directory = TemporaryDirectory(prefix='actql-original-host-binding-')
        self.addCleanup(directory.cleanup)
        path = Path(directory.name)
        source_path, state_path = path / 'source', path / 'state'
        source_path.mkdir(mode=0o700)
        state_path.mkdir(mode=0o700)
        account = b'{"original":"e\xcc\x81\\r\\n","absent":null}'
        policy = b'{"original":"policy"}'
        # Independent opaque inputs to the neutral scalar projection. They do
        # not stand in for Common's contract/Account/adoption validation.
        bodies = (b'original-initialization', b'original-configuration',
                  b'original-journal', b'original-selected-manifest')
        for parent, name, body in (
            (source_path, 'account.json', account), (source_path, 'policy.json', policy),
            (state_path, 'account.json', account), (state_path, 'initialization.json', bodies[0]),
            (state_path, 'configuration-custody.json', bodies[1]),
            (state_path, 'journal-custody.json', bodies[2]),
        ):
            (parent / name).write_bytes(body)
            (parent / name).chmod(0o600)
        source_root = LocalFileRoot(source_path, max_files=8, max_chunk_bytes=16)
        state_root = LocalFileRoot(state_path, max_files=8, max_chunk_bytes=16)
        store = LocalByteStore(state_path / 'client.sqlite3', max_records=64,
                               max_record_bytes=65536, max_payload_bytes=262144)
        self.addCleanup(store.close)
        epoch = LocalSubmissionAuthority(store, lambda *args: (_ for _ in ()).throw(
            AssertionError('Unexpected epoch issuance/projection')), now=lambda: 10)
        store.compare_exchange_many(tuple(ByteWrite(store.namespaced_key(namespace, key), None, body)
            for namespace, key, body in (
                ('client_local_adoption', 'adoption', bodies[2]),
                ('client_local_settings', 'manifest', bodies[3]),
                ('client_local_settings', 'file:policy.json', policy))))
        source = LocalHostFiles(source_root, store, max_files=2, max_bytes=128)
        state = LocalHostFiles(state_root, store, max_files=4, max_bytes=256)
        for root, pins in ((source_root, source), (state_root, state)):
            self.addCleanup(root.close)
            self.addCleanup(pins.close)
        source_account = source.read_original('account.json', max_bytes=64)
        selected = source.read_original('policy.json', max_bytes=64)
        staged = state.read_original('account.json', max_bytes=64)
        originals = tuple(state.read_original(name, max_bytes=64) for name in (
            'initialization.json', 'configuration-custody.json', 'journal-custody.json'))
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._inputs = {}
        core._loans = {}
        core._released = set()
        core._next_ticket = 5
        core._closing = core._closed = False
        expected = []
        for ticket, body in enumerate(bodies, 1):
            packet = json.dumps({'body': body.decode(), 'cid': 'sha256:' + 'a' * 64}).encode()
            value = _Output(core._identity, ticket, 100 + ticket, 65536, 'original')
            core._inputs[ticket] = _PhysicalInput(packet, lambda: True, lambda _: True)
            core._loans[ticket] = value
            expected.append(value)
        calls, codes = [], {}
        def call(family, name, *args):
            calls.append((family, name, args))
            if (family, name) in codes:
                result = codes[family, name]
                if isinstance(result, BaseException):
                    raise result
                return result
            if name == 'reserve':
                return 200 + (args[0] if family != 'current' else args[1])
            if family == 'buffer' and name in ('fill', 'seal'):
                return 0
            if family == 'current' and name in ('bind', 'validate'):
                ticket = args[0] - 200
                self.assertIsNotNone(core._journal_callbacks(ticket).reader)
                return 0
            if name == 'close':
                ticket = args[0] - 200
                return 0 if core._cleanup(ticket) == 0 else -9
            raise AssertionError('Unexpected execution, scope issuance, COMMIT or publication')
        core._call = call
        def factory():
            value = OriginalHostBinding(core, source, state, source_account, staged,
                *originals, (selected,), tuple(expected), epoch,
                principal='local-cli', connection='local')
            self.addCleanup(value.close)
            return value
        binding = factory() if create else None
        return path, store, core, epoch, source, state, tuple(expected), calls, codes, factory, binding

    def test_original_current_input_is_completed_before_acquisition(self):
        _, _, _, _, _, _, _, calls, _, _, binding = self.fixture()
        original = binding._input
        assert original is not None
        transfers = [(name, args) for family, name, args in calls
                     if family == 'buffer' and name in ('fill', 'seal')]
        self.assertEqual(transfers, [('fill', (original.handle, 0, original.length)),
                                     ('seal', (original.handle,))])
        sealed = next(i for i, call in enumerate(calls) if call[:2] == ('buffer', 'seal'))
        acquired = next(i for i, call in enumerate(calls) if call[:2] == ('current', 'reserve'))
        self.assertLess(sealed, acquired)

    def test_incomplete_original_transfer_retains_same_input_without_current_acquisition(self):
        _, _, core, _, _, _, _, calls, codes, factory, _ = self.fixture(create=False)
        codes['buffer', 'fill'] = LocalCoreError('fill', -9)
        with self.assertRaises(LocalHostBindingCleanupPending) as raised:
            factory()
        binding = raised.exception.cleanup_binding
        assert binding._input is not None
        self.assertIs(core._loans[binding._input.ticket], binding._input)
        self.assertIsNone(binding._current)
        self.assertFalse(any(call[:2] == ('current', 'reserve') for call in calls))
        self.assertTrue(binding.close())

    def test_same_original_store_snapshot_and_exact_bytes_without_writes_or_execution(self):
        _, store, core, _, source, _, _, calls, _, _, binding = self.fixture()
        changes = store._connection.total_changes
        frames = []
        def consume(value):
            callbacks = core._journal_callbacks(value.ticket)
            frames.append(callbacks.reader)
            self.assertIs(callbacks.reader.owner, store)
            self.assertIsNone(source.current())
            self.assertEqual(json.loads(core._inputs[binding._input.ticket].payload)['account'],
                             '{"original":"e\u0301\\r\\n","absent":null}')
        binding.inspect(consume)
        self.assertEqual(store._connection.total_changes, changes)
        self.assertIsNone(core._journal_callbacks(binding._current.ticket).reader)
        with self.assertRaises(ValueError):
            core.validate_host_current(binding._current)
        self.assertTrue(binding.close())
        self.assertTrue(all(family in ('buffer', 'workspace', 'current') for family, _, _ in calls))
        self.assertFalse(store._connection.in_transaction)
        self.assertEqual(len(frames), 1)

    def test_each_current_callback_observes_every_original_file_once_without_caching(self):
        path, _, _, _, source, state, _, _, _, _, binding = self.fixture()
        # Grouped observation still validates every original file descriptor
        # and name. Observe that actual member check, not the single-file API.
        with patch.object(source._root, '_validate_original_member',
                          wraps=source._root._validate_original_member) as source_observe, \
                patch.object(state._root, '_validate_original_member',
                             wraps=state._root._validate_original_member) as state_observe:
            binding._physical_current()
            self.assertEqual((source_observe.call_count, state_observe.call_count), (2, 4))
            binding._physical_current()
            self.assertEqual((source_observe.call_count, state_observe.call_count), (4, 8))
            # A second operation must observe the original again. Identical
            # prior bytes/currentness cannot mask a changed physical file.
            (path / 'source' / 'account.json').write_bytes(b'changed')
            with self.assertRaises(LocalFileError):
                binding._physical_current()

    def test_missing_changed_or_extra_settings_refuse_before_core_binding(self):
        for mutation in ('missing', 'changed', 'extra'):
            with self.subTest(mutation=mutation):
                _, store, _, _, _, _, _, calls, _, _, binding = self.fixture()
                key = store.namespaced_key('client_local_settings', 'file:policy.json')
                if mutation == 'missing':
                    store._connection.execute('DELETE FROM core_bytes WHERE key=?', (key,))
                elif mutation == 'changed':
                    store.compare_exchange(key, 0, b'changed')
                else:
                    store.compare_exchange(store.namespaced_key('client_local_settings', 'unexpected'), None, b'extra')
                before = len(calls)
                with self.assertRaises(LocalStorageError):
                    binding.inspect(lambda _: self.fail('Unverified settings reached consumer'))
                self.assertEqual(len(calls), before)
                self.assertFalse(store._connection.in_transaction)

    def test_changed_original_file_or_epoch_refuses_before_protected_core_work(self):
        for mutation in ('file', 'epoch'):
            with self.subTest(mutation=mutation):
                path, store, _, _, _, _, _, calls, _, _, binding = self.fixture()
                if mutation == 'file':
                    (path / 'source' / 'account.json').write_bytes(b'changed')
                    expected_error = LocalFileError
                else:
                    row = store.read('submission-epoch-authority')
                    value = json.loads(row.payload)
                    value['authentication_key'] = '0' * 64 if value['authentication_key'] != '0' * 64 else '1' * 64
                    store.compare_exchange('submission-epoch-authority', row.generation, json.dumps(value).encode())
                    expected_error = LocalSubmissionIdentityError
                before = len(calls)
                with self.assertRaises(expected_error):
                    binding.inspect(lambda _: self.fail('Changed originals reached consumer'))
                self.assertEqual(len(calls), before)

    def test_original_custody_mismatch_retains_workspace_and_saved_bytes_for_cleanup(self):
        path, _, core, _, _, _, expected, calls, _, factory, _ = self.fixture(create=False)
        core._inputs[expected[1].ticket].payload = json.dumps(
            {'body': 'wrong', 'cid': 'sha256:' + 'a' * 64}).encode()
        with self.assertRaises(LocalHostBindingCleanupPending) as raised:
            factory()
        value = raised.exception.cleanup_binding
        self.assertIsNotNone(value._workspace)
        self.assertIsNone(value._current)
        self.assertTrue(value.close())
        self.assertEqual((path / 'state' / 'configuration-custody.json').read_bytes(), b'original-configuration')
        self.assertEqual([family for family, _, _ in calls], ['workspace', 'workspace'])

    def test_core_refused_or_unknown_binding_never_reaches_consumer_and_keeps_loans(self):
        for status in (-32, -35, -41):
            with self.subTest(status=status):
                _, store, core, _, _, _, _, _, codes, _, binding = self.fixture()
                codes['current', 'bind'] = status
                loan = binding._current
                with self.assertRaises(LocalCoreError) as raised:
                    binding.inspect(lambda _: self.fail('Refusal became a Host permission'))
                self.assertEqual(raised.exception.code, status)
                self.assertIs(core._loans[loan.ticket], loan)
                self.assertIsNone(core._journal_callbacks(loan.ticket).reader)
                self.assertFalse(store._connection.in_transaction)

    def test_failed_cleanup_retains_same_current_input_workspace_without_reissuing(self):
        _, _, core, _, _, _, _, calls, codes, _, binding = self.fixture()
        loan, original_input, workspace = binding._current, binding._input, binding._workspace
        codes['current', 'close'] = -9
        self.assertFalse(binding.close())
        self.assertIs(binding._current, loan)
        self.assertIs(binding._input, original_input)
        self.assertIs(binding._workspace, workspace)
        self.assertIs(core._loans[loan.ticket], loan)
        del codes['current', 'close']
        self.assertTrue(binding.close())
        self.assertEqual(sum(name == 'reserve' for _, name, _ in calls), 3)
        with self.assertRaises(ValueError):
            binding.inspect(lambda _: self.fail('Closed supplier reused'))

    def test_copies_retired_original_projections_and_nested_frames_refuse(self):
        _, _, core, _, _, _, expected, calls, _, _, binding = self.fixture()
        before = len(calls)
        with self.assertRaises(ValueError):
            copy.copy(binding).inspect(lambda _: None)
        binding.inspect(lambda _: self.assertRaises(ValueError, binding.inspect, lambda _: None))
        core._loans.pop(expected[0].ticket)
        after = len(calls)
        with self.assertRaises(ValueError):
            binding.inspect(lambda _: None)
        self.assertEqual(len(calls), after)
        self.assertGreater(after, before)

    def test_reserve_trap_retains_exact_ticket_and_requires_original_instance_retirement(self):
        _, _, core, _, _, _, _, calls, codes, factory, _ = self.fixture(create=False)
        failure = OSError('original current reservation unknown')
        codes['current', 'reserve'] = failure
        with self.assertRaises(LocalHostBindingCleanupPending) as raised:
            factory()
        binding = raised.exception.cleanup_binding
        self.assertIs(raised.exception.__cause__, failure)
        self.assertIn(binding._uncertain_ticket, core._inputs)
        self.assertIsNotNone(binding._input)
        self.assertFalse(binding.close())
        self.assertEqual(sum(name == 'reserve' for _, name, _ in calls), 3)
        core._closed = True  # Scalar double of actual whole-instance retirement.
        core._inputs.clear()
        core._loans.clear()
        self.assertTrue(binding.close())

    def test_live_close_seals_new_work_but_detaches_reader_for_same_handle_cleanup(self):
        _, store, core, _, _, _, _, calls, _, _, binding = self.fixture()
        loan = binding._current
        def stop(value):
            self.assertFalse(binding.close())
            self.assertIs(binding._current, value)
        with self.assertRaises(ValueError):
            binding.inspect(stop)
        self.assertIsNone(core._journal_callbacks(loan.ticket).reader)
        self.assertFalse(store._connection.in_transaction)
        self.assertTrue(binding.close())
        self.assertFalse(any(name in ('cancel', 'produce', 'commit') for _, name, _ in calls))


if __name__ == '__main__':
    unittest.main()
