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
from threading import Thread
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
            'publisher_current', 'publisher_finish', 'input_cleanup', 'reader_stop',
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

    def test_sql_mutation_schema_and_raw_transaction_replacement_refuse(self):
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
                        store._connection.execute('COMMIT')
                        store._connection.execute('BEGIN')
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

    def test_user_trace_before_entry_keeps_legacy_and_unsetting_does_not_restore_eligibility(self):
        core, binding, store, _, current = self.fixture()
        traced = []
        store._connection.set_trace_callback(traced.append)
        store._connection.set_trace_callback(None)
        def export():
            self.assertIsNone(core._invocation_observation)
            self.assertIsNone(binding._observed_reader._invocation_check)
            self.assertEqual(current(), 0)
            return 7
        self.assertEqual(self.run_export(core, binding, export), [7])

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

    def test_other_thread_customization_is_rejected_before_installation_and_is_latched(self):
        for mode in ('trace', 'factory'):
            with self.subTest(mode=mode):
                core, binding, store, _, current = self.fixture()
                failures, callbacks = [], []
                def customize():
                    try:
                        if mode == 'trace':
                            store._connection.set_trace_callback(lambda _: callbacks.append(True))
                        else:
                            store._connection.text_factory = lambda _: callbacks.append(True)
                    except RuntimeError as error:
                        failures.append(error)
                def export():
                    self.assertEqual(current(), 0)
                    thread = Thread(target=customize)
                    thread.start()
                    thread.join()
                    return 7
                with self.assertRaises(RuntimeError) as raised:
                    self.run_export(core, binding, export)
                self.assertIs(raised.exception, failures[0])
                self.assertFalse(callbacks)
                self.assertIsNone(store._connection._user_trace)
                self.assertIs(store._connection.text_factory, str)

    def test_late_primitive_adapter_refuses_without_calling_it(self):
        core, binding, store, _, current = self.fixture()
        key = (str, sqlite3.PrepareProtocol)
        present, previous = key in sqlite3.adapters, sqlite3.adapters.get(key)
        invoked, failures = [], []
        def adapter(value):
            invoked.append(value)
            return value
        def export():
            self.assertEqual(current(), 0)
            thread = Thread(target=lambda: sqlite3.register_adapter(str, adapter))
            thread.start()
            thread.join()
            try:
                store._physical.read_header('original')
            except ValueError as error:
                failures.append(error)
            return 7
        try:
            with self.assertRaises(ValueError) as raised:
                self.run_export(core, binding, export)
            self.assertIs(raised.exception, failures[0])
            self.assertFalse(invoked)
        finally:
            if present:
                sqlite3.adapters[key] = previous
            else:
                sqlite3.adapters.pop(key, None)

    def test_literal_queries_preserve_quotes_nul_unicode_and_maximum_keys(self):
        core, binding, store, _, current = self.fixture()
        prefix = 'namespace:5:probe:'
        keys = ("quote' nul\x00 café 東京 ?", 'x' * (4096 - len(prefix)))
        for key in keys:
            store.compare_exchange(store.namespaced_key('probe', key), None, b'original')
        execute = _TrackedSQLiteConnection.execute
        statements = []
        def capture(connection, sql, parameters=()):
            if connection._closed_invocation is not None:
                self.assertEqual(parameters, ())
                statements.append(sql)
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
        self.assertTrue(any('CAST(X' in statement for statement in statements))
        self.assertTrue(all(len(statement.encode('utf-8')) <= 65536 for statement in statements))

    def test_zero_parameters_cannot_dispatch_an_adapter_registered_after_the_guard(self):
        core, binding, store, _, current = self.fixture()
        adapter_key = (str, sqlite3.PrepareProtocol)
        present, previous = adapter_key in sqlite3.adapters, sqlite3.adapters.get(adapter_key)
        invoked, statements = [], []
        execute = _TrackedSQLiteConnection.execute
        def adapter(value):
            invoked.append(value)
            return value
        def race(connection, sql, parameters=()):
            if connection._closed_invocation is None or 'CAST(X' not in sql:
                return execute(connection, sql, parameters)
            self.assertEqual(parameters, ())
            statements.append(sql)
            thread = Thread(target=lambda: sqlite3.register_adapter(str, adapter))
            thread.start()
            thread.join()
            try:
                # Deliberately exercise the final SQLite call after a raced
                # registry change. With no parameters there is no adaptation.
                return sqlite3.Connection.execute(connection, sql)
            finally:
                if present:
                    sqlite3.adapters[adapter_key] = previous
                else:
                    sqlite3.adapters.pop(adapter_key, None)
        def export():
            self.assertEqual(current(), 0)
            self.assertIsNotNone(store._physical.read_header(binding._fences[0].key))
            return 7
        with patch.object(_TrackedSQLiteConnection, 'execute', race):
            self.assertEqual(self.run_export(core, binding, export), [7])
        self.assertTrue(statements)
        self.assertFalse(invoked)


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

    def test_all_supported_callback_registration_paths_permanently_disable_eligibility(self):
        registrations = (
            lambda c: c.set_trace_callback(None),
            lambda c: c.set_progress_handler(None, 0),
            lambda c: c.set_authorizer(None),
            lambda c: c.create_function('probe', 0, lambda: 1),
            lambda c: c.create_aggregate('probe', 1, object),
            lambda c: c.create_window_function('probe', 1, object),
            lambda c: c.create_collation('probe', lambda a, b: 0),
            lambda c: setattr(c, 'row_factory', None),
            lambda c: setattr(c, 'text_factory', str),
            lambda c: c.enable_load_extension(False),
            lambda c: c.load_extension('/nonexistent/actql-test-extension'),
        )
        for register in registrations:
            connection = sqlite3.connect(':memory:', isolation_level=None, factory=_TrackedSQLiteConnection)
            try:
                connection._qualify_encoding()
                self.assertTrue(connection._closed_eligible())
                try:
                    register(connection)
                except (sqlite3.Error, AttributeError):
                    pass  # Unsupported extension facilities still disqualify.
                self.assertFalse(connection._closed_eligible())
            finally:
                connection.close()


if __name__ == '__main__':
    unittest.main()
