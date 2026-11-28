"""Closed invocation fences with actual files/SQLite and a scalar export double.

These tests exercise the real Python _call/import boundary, not Wasm Account
decisions or installed-product acceptance. Authorization remains Core-owned.
"""
import copy
import ast
import inspect
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
from threading import Event, Thread
import textwrap
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCore
from actql_sdk._local_host_binding import OriginalHostBinding
from actql_sdk._local_storage import LocalStorageError
from actql_sdk._local_files import LocalFileError
from actql_sdk._local_storage_physical import _TrackedSQLiteConnection
from test_local_installation import OriginalLocalInstallationTests


class ClosedInvocationTests(unittest.TestCase):
    def fixture(self):
        temporary = TemporaryDirectory(prefix='actql-closed-invocation-')
        self.addCleanup(temporary.cleanup)
        fixture = OriginalLocalInstallationTests()
        self.addCleanup(fixture.doCleanups)
        core, _ = fixture.core()
        installation = fixture.create(core, Path(temporary.name))
        binding, store = installation.binding, installation._store
        scalar = core._call
        core._ordinary_host = True
        core._host_fuel_phase = 'operation'
        core._host_cleanup_depth = 0
        core._host_operation_id = core._host_operation_sequence = 1
        core._retired = core._invoking = False
        core._physical_holding = core._physical_child_control = None
        core._physical_vm_observation = core._platform_vm_original = None
        core._host_current_binding = core._invocation_observation = None
        core._store, core._nonce = object(), 1
        core._exports = {}
        def call(family, name, *args):
            if family == 'probe':
                return LocalCore._call(core, family, name, *args)
            return scalar(family, name, *args)
        core._call = call
        current = core._observation_import('journal_current', core._journal_current)
        return core, binding, store, Path(temporary.name), lambda: current(binding._current.ticket)

    def run_export(self, core, binding, action):
        core._exports['actql_probe_run'] = lambda *_: action()
        returned = []
        binding.inspect(lambda _: returned.append(core._call('probe', 'run')))
        return returned

    def test_cleanup_frame_excludes_other_thread_original_quantum_until_same_scope_returns(self):
        core, binding, store, _, current = self.fixture()
        attempted, returned = Event(), Event()
        acquired, spans, failures = [], [], []
        original_operation = core._host_operation_id

        def export():
            spans.append(core._invocation_observation)
            self.assertEqual(current(), 0)
            return 7

        def invoke():
            try:
                first = core._lock.acquire(blocking=False)
                acquired.append(first)
                try:
                    if first:
                        self.assertEqual(self.run_export(core, binding, export), [7])
                finally:
                    if first:
                        core._lock.release()
                    attempted.set()
                if not returned.wait(2):
                    raise TimeoutError('Original cleanup frame did not return')
                if not first:
                    self.assertEqual(self.run_export(core, binding, export), [7])
            except BaseException as cause:
                failures.append(cause)
                attempted.set()

        worker = Thread(target=invoke)
        try:
            with core._host_cleanup():
                worker.start()
                self.assertTrue(attempted.wait(2))
                self.assertFalse(failures)
                self.assertEqual(acquired, [False],
                    'Another original quantum cannot observe a foreign cleanup depth')
                self.assertEqual(spans, [])
                self.assertEqual(core._host_operation_id, original_operation)
        finally:
            returned.set()
            worker.join(3)
        self.assertFalse(worker.is_alive())
        self.assertFalse(failures)
        self.assertEqual(len(spans), 1)
        from actql_sdk._local_host_binding import _InvocationObservation
        self.assertIs(type(spans[0]), _InvocationObservation)
        self.assertFalse(spans[0].active)
        self.assertIsNone(binding._observed_reader)
        self.assertIsNone(core._invocation_observation)
        self.assertIsNone(store._connection._closed_invocation)
        self.assertEqual(core._host_cleanup_depth, 0)
        self.assertEqual(core._host_operation_id, original_operation)

    def test_repeated_current_imports_keep_calls_but_group_graph_walks_per_invocation(self):
        core, binding, store, _, current = self.fixture()
        original = OriginalHostBinding._physical_current
        graphs, imports, observations = [], [], []
        def graph(receiver):
            graphs.append(receiver)
            return original(receiver)
        def export():
            before = len(graphs)
            for _ in range(20):
                imports.append(current())
            observations.append(core._invocation_observation)
            self.assertTrue(observations[-1].admitted)
            self.assertEqual(len(graphs) - before, 1)
            return 7
        with patch.object(OriginalHostBinding, '_physical_current', graph):
            core._exports['actql_probe_run'] = lambda *_: export()
            def consume(_):
                for _ in range(2):
                    before = len(graphs)
                    self.assertEqual(core._call('probe', 'run'), 7)
                    self.assertEqual(len(graphs) - before, 2)
                    self.assertIsNone(store._connection._closed_invocation)
                    self.assertIsNone(core._invocation_observation)
            binding.inspect(consume)
        self.assertEqual(imports, [0] * 40)
        self.assertIsNot(observations[0], observations[1])
        self.assertFalse(any(value.active for value in observations))

    def test_scalar_export_without_current_does_not_add_graph_walks(self):
        core, binding, _, _, _ = self.fixture()
        original = OriginalHostBinding._physical_current
        graphs = []
        def graph(receiver):
            graphs.append(True)
            return original(receiver)
        core._exports['actql_probe_run'] = lambda *_: 7
        def consume(_):
            before = len(graphs)
            self.assertEqual(core._call('probe', 'run'), 7)
            self.assertEqual(len(graphs), before)
        with patch.object(OriginalHostBinding, '_physical_current', graph):
            binding.inspect(consume)

    def test_effect_and_unknown_imports_suspend_current_and_are_not_removed(self):
        core, binding, _, _, current = self.fixture()
        effects = []
        def effect():
            self.assertTrue(core._invocation_observation.suspended)
            binding.current()
            effects.append(True)
            return 0
        imports = [core._observation_import(name, effect) for name in (
            'publisher_current', 'publisher_finish', 'input_cleanup', 'input_copy',
            'journal_query_header', 'platform_vm_observation', 'reader_stop',
            'native_settled', 'execution_child_admit', 'future_unknown_import')]
        def export():
            self.assertEqual(current(), 0)
            for invoke in imports:
                self.assertEqual(invoke(), 0)
                self.assertFalse(core._invocation_observation.suspended)
                self.assertEqual(current(), 0)
            return 7
        self.assertEqual(self.run_export(core, binding, export), [7])
        self.assertEqual(len(effects), len(imports))

    def test_file_mutation_blocks_effect_before_callback_and_retains_custody(self):
        core, binding, store, path, current = self.fixture()
        effects, escaped = [], []
        original = binding._current
        effect = core._observation_import('publisher_finish', lambda: effects.append(True))
        def export():
            self.assertEqual(current(), 0)
            (path / 'source' / binding._account.name).write_bytes(b'changed')
            effect()
            escaped.append(True)
            return 7
        with self.assertRaises(LocalFileError):
            self.run_export(core, binding, export)
        self.assertFalse(effects or escaped)
        self.assertTrue(core._closing)
        self.assertIs(core._loans[original.ticket], original)
        self.assertIsNone(core._journal_callbacks(original.ticket).reader)
        self.assertIsNone(store._connection._closed_invocation)
        self.assertIsNone(core._invocation_observation)

    def test_final_file_and_root_changes_refuse_before_result_escapes(self):
        for mutation in ('file', 'root'):
            with self.subTest(mutation=mutation):
                core, binding, _, path, current = self.fixture()
                def export():
                    self.assertEqual(current(), 0)
                    if mutation == 'file':
                        (path / 'source' / binding._account.name).write_bytes(b'changed')
                    else:
                        (path / 'source').rename(path / 'source-original')
                        (path / 'source').mkdir(mode=0o700)
                    return 7
                with self.assertRaises((LocalFileError, ValueError)):
                    self.run_export(core, binding, export)
                self.assertTrue(core._closing)

    def test_sql_mutation_schema_and_owned_transaction_replacement_refuse(self):
        for mutation in ('row', 'schema', 'transaction'):
            with self.subTest(mutation=mutation):
                core, binding, store, _, current = self.fixture()
                def export():
                    self.assertEqual(current(), 0)
                    if mutation == 'row':
                        store._connection.execute("INSERT INTO core_bytes VALUES ('extra', 0, X'01')")
                    elif mutation == 'schema':
                        store._connection.execute('CREATE TEMP TABLE unexpected (value INTEGER)')
                    else:
                        store._physical.finish_read()
                        store._physical.begin_read()
                    return 7
                with self.assertRaises(LocalStorageError):
                    self.run_export(core, binding, export)
                self.assertTrue(core._closing)

    def test_callback_exception_close_and_swallowed_reentry_poison_original_invocation(self):
        for mode in ('throw', 'close', 'reentry', 'cleanup', 'operation'):
            with self.subTest(mode=mode):
                core, binding, _, _, current = self.fixture()
                failures = []
                original = RuntimeError('original external callback failed')
                def callback():
                    if mode == 'throw':
                        raise original
                    if mode == 'close':
                        core._closing = True
                    else:
                        try:
                            if mode == 'cleanup':
                                with core._host_cleanup():
                                    self.fail('Reentrant cleanup was entered')
                            elif mode == 'operation':
                                with core._host_operation():
                                    self.fail('Reentrant operation was entered')
                            else:
                                core._call('probe', 'run')
                        except RuntimeError as error:
                            failures.append(error)
                    return 0
                effect = core._observation_import('future_unknown_import', callback)
                def export():
                    self.assertEqual(current(), 0)
                    try:
                        effect()
                    except (RuntimeError, ValueError) as error:
                        if not failures:
                            failures.append(error)
                    return 7
                with self.assertRaises((RuntimeError, ValueError)) as raised:
                    self.run_export(core, binding, export)
                self.assertIs(raised.exception, original if mode == 'throw' else failures[0])
                self.assertTrue(core._closing)

    def test_copied_current_and_reader_identity_cannot_be_restored_after_failure(self):
        for member in ('_current', '_observed_reader'):
            with self.subTest(member=member):
                core, binding, _, _, current = self.fixture()
                failures = []
                def export():
                    self.assertEqual(current(), 0)
                    original = getattr(binding, member)
                    setattr(binding, member, copy.copy(original))
                    try:
                        current()
                    except ValueError as error:
                        failures.append(error)
                    finally:
                        setattr(binding, member, original)
                    return 7
                with self.assertRaises(ValueError) as raised:
                    self.run_export(core, binding, export)
                self.assertIs(raised.exception, failures[0])

    def test_owned_queries_remain_complete_and_public_reader_reentry_still_refuses(self):
        core, binding, store, _, current = self.fixture()
        scan = type(store._physical).scan_range
        failures = []
        def export():
            self.assertEqual(current(), 0)
            reader = binding._observed_reader
            row = reader.query_current(reader, 1, 'client_local_adoption', 'adoption', binding._current_observer)
            self.assertEqual(row[0], 'adoption')
            def reentrant(database, *args, **kwargs):
                try:
                    reader.check_unchanged(reader)
                except ValueError as error:
                    failures.append(error)
                return scan(database, *args, **kwargs)
            with patch.object(type(store._physical), 'scan_range', reentrant):
                try:
                    reader.query_current(reader, 1, 'client_local_adoption', 'adoption', binding._current_observer)
                except ValueError:
                    pass
            return 7
        with self.assertRaises(ValueError) as raised:
            self.run_export(core, binding, export)
        self.assertIs(raised.exception, failures[0])

    def test_write_transaction_readers_do_not_admit_closed_observations(self):
        core, binding, store, _, current = self.fixture()
        def export():
            self.assertIsNone(core._invocation_observation)
            self.assertIsNone(binding._observed_reader._invocation_check)
            self.assertEqual(current(), 0)
            return 7
        core._exports['actql_probe_run'] = lambda *_: export()
        with binding.fenced() as fences:
            store._physical.begin_immediate()
            try:
                store._inspect_namespace_locked(lambda reader: binding.inspect_reader(
                    reader, lambda _: self.assertEqual(core._call('probe', 'run'), 7)),
                    fences, binding._current_observer)
            finally:
                store._physical.rollback()

    def test_closed_inventory_queries_bind_the_same_statement(self):
        core, binding, store, _, current = self.fixture()
        prefix = 'namespace:5:probe:'
        keys = ("quote' nul\x00 café 東京 ?", 'x' * (4096 - len(prefix)))
        for key in keys:
            store.compare_exchange(store.namespaced_key('probe', key), None, b'original')
        execute = _TrackedSQLiteConnection.execute
        statements = []
        def capture(connection, sql, parameters=()):
            if (connection._closed_invocation is not None
                    and sql.startswith('SELECT generation, length(payload)')):
                statements.append((sql, parameters))
            return execute(connection, sql, parameters)
        def export():
            self.assertEqual(current(), 0)
            reader = binding._observed_reader
            for key in keys:
                row = reader.query_current(reader, 1, 'probe', key, binding._current_observer)
                self.assertEqual(row[0], key)
                self.assertEqual(row[1].payload, b'original')
                self.assertEqual(store._physical.read_header(prefix + key), (0, 8))
            return 7
        with patch.object(_TrackedSQLiteConnection, 'execute', capture):
            self.assertEqual(self.run_export(core, binding, export), [7])
        self.assertEqual(len(statements), 2)
        self.assertEqual(statements[0][0], statements[1][0])
        self.assertEqual([parameters for _, parameters in statements], [(prefix + key,) for key in keys])


class ClosedSQLiteEligibilityTests(unittest.TestCase):
    def test_non_utf8_database_keeps_parameterized_legacy_path(self):
        with TemporaryDirectory(prefix='actql-utf16-fallback-') as temporary:
            path = Path(temporary) / 'original.sqlite'
            original = sqlite3.connect(path)
            try:
                original.execute("PRAGMA encoding='UTF-16'")
                original.execute('CREATE TABLE original (value TEXT)')
                original.commit()
            finally:
                original.close()
            connection = sqlite3.connect(path, factory=_TrackedSQLiteConnection)
            try:
                connection._qualify_encoding()
                self.assertFalse(connection._closed_eligible())
                self.assertEqual(connection.execute('SELECT ?', ('東京',)).fetchone(), ('東京',))
            finally:
                connection.close()

    def test_every_registered_import_uses_the_conservative_wrapper(self):
        tree = ast.parse(textwrap.dedent(inspect.getsource(LocalCore.__init__)))
        registrations = [value for value in ast.walk(tree) if isinstance(value, ast.Call)
            and isinstance(value.func, ast.Attribute) and value.func.attr == 'define_func']
        self.assertTrue(registrations)
        for registration in registrations:
            callback = registration.args[3]
            self.assertIsInstance(callback, ast.Call)
            self.assertIsInstance(callback.func, ast.Attribute)
            self.assertEqual(callback.func.attr, '_observation_import')


if __name__ == '__main__':
    unittest.main()
