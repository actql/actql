"""Closed SQL checks on genuine Wasmtime exports, actual SQLite and original files.

The tiny fixture only exercises physical Host imports. Source/Account decisions
still use the unchanged explicit scalar double; this is not installed E2E or
latency evidence. Every fixture import is wrapped, including its test effect.
"""
import sys
import sqlite3
from threading import Thread
import unittest
from unittest.mock import patch

import wasmtime

from actql_sdk._local_core import LocalCore, _ClosedWasmExports, _CLOSED_WASM_RECEIPT_BYTES, _MEMORY_LIMIT
from actql_sdk._local_host_binding import _InvocationObservation
from actql_sdk._local_files import LocalFileError
from actql_sdk._local_storage import LocalStorageError
from actql_sdk._local_storage_physical import _SQLiteByteDatabase, _TrackedSQLiteConnection
import test_local_closed_invocation as closed


class ClosedWasmSqlTests(unittest.TestCase):
    def fixture(self, *, effect=None, capture=True):
        fixture = closed.ClosedInvocationTests()
        self.addCleanup(fixture.doCleanups)
        core, binding, store, path, _ = fixture.fixture()
        store.compare_exchange(store.namespaced_key('probe', 'row'), None, b'payload')
        engine = wasmtime.Engine()
        core._store = wasmtime.Store(engine)
        ticket = binding._current.ticket
        module = wasmtime.Module(engine, f'''(module
            (import "test" "current" (func $current (param i32) (result i64)))
            (import "test" "begin" (func $begin (param i32 i32 i32 i32) (result i32)))
            (import "test" "copy" (func $copy (param i32 i32 i32 i32) (result i32)))
            (import "test" "query" (func $query (param i32) (result i32)))
            (import "test" "length" (func $length (param i32 i32) (result i32)))
            (import "test" "release" (func $release (param i32) (result i32)))
            (import "test" "effect" (func $effect (result i32)))
            (import "test" "schema" (func $schema (param i32) (result i32)))
            (memory (export "memory") 1 {_MEMORY_LIMIT // 65536})
            (data (i32.const 64) "proberow")
            (func $one (param $after i32) (result i32)
                i32.const {ticket} i32.const 0 i32.const 5 local.get $after
                call $begin i32.eqz if else unreachable end
                i32.const {ticket} i32.const 0 i32.const 64
                i32.const 5 local.get $after i32.add call $copy
                i32.const 5 local.get $after i32.add i32.eq if else unreachable end
                i32.const {ticket} call $query)
            (func (export "actql_probe_schema") (param i64) (result i32)
                i32.const {ticket} call $current i64.const 1 i64.eq
                if else unreachable end
                i32.const {ticket} call $schema)
            (func (export "actql_probe_run")
                    (param i64) (param $count i32) (param $rows i32) (param $effect i32) (result i32)
                (local $index i32)
                loop $again
                    i32.const {ticket} call $current i64.const 1 i64.eq
                    if else unreachable end
                    local.get $rows if
                        i32.const 0 call $one i32.eqz if else unreachable end
                        i32.const {ticket} i32.const 1 call $length i32.const 7 i32.eq
                        if else unreachable end
                        i32.const {ticket} call $release drop
                        i32.const 3 call $one i32.const 1 i32.eq if else unreachable end
                        i32.const {ticket} call $release drop
                    end
                    local.get $index i32.const 1 i32.add local.tee $index
                    local.get $count i32.lt_u br_if $again
                end
                local.get $effect if call $effect drop end
                i32.const 7))''')
        definitions = [
            ('journal_current_operation', core._journal_current_operation, ['i32'], 'i64', False),
            ('journal_begin', core._journal_begin, ['i32'] * 4, 'i32', False),
            ('journal_query_copy', core._journal_query_copy, ['i32'] * 4, 'i32', True),
            ('journal_query', core._journal_query, ['i32'], 'i32', False),
            ('journal_length', core._journal_length, ['i32'] * 2, 'i32', False),
            ('journal_release', core._journal_release, ['i32'], 'i32', False),
            ('test_effect', effect or (lambda: 0), [], 'i32', False),
            ('journal_schema', core._journal_schema, ['i32'], 'i32', False),
        ]
        imports = [wasmtime.Func(core._store,
            wasmtime.FuncType([getattr(wasmtime.ValType, item)() for item in params],
                              [getattr(wasmtime.ValType, result)()]),
            core._observation_import(name, callback), access_caller=caller)
            for name, callback, params, result, caller in definitions]
        core._instance = wasmtime.Instance(core._store, module, imports)
        core._exports = core._instance.exports(core._store)
        core._observe_platform_vm(wasmtime)
        # Production captures this only in LocalCore.__init__, after validating
        # its full ABI and registering every import through the same wrapper.
        # This deliberately smaller physical fixture does not claim that ABI.
        core._closed_wasm_exports = core._closed_wasm_workspace = None
        if capture:
            core._capture_closed_wasm_exports(wasmtime)
        return core, binding, store, path

    def run_export(self, core, binding, *, count=1, rows=0, effect=0):
        returned = []
        binding.inspect(lambda _: returned.append(core._call('probe', 'run', count, rows, effect)))
        return returned

    def test_native_export_kind_and_handle_qualify_only_the_original_function(self):
        core, _, _, _ = self.fixture()
        receipt = core._closed_wasm_exports
        export = core._exports['actql_probe_run']
        self.assertTrue(receipt._qualify('actql_probe_run', export))
        self.assertFalse(receipt._qualify('memory', core._exports['memory']))
        self.assertFalse(receipt._qualify('actql_probe_run', lambda *_: 7))
        foreign = wasmtime.Func(core._store,
            wasmtime.FuncType([wasmtime.ValType.i64()] + [wasmtime.ValType.i32()] * 3,
                              [wasmtime.ValType.i32()]), lambda *_: 7)
        core._exports._extern_map['actql_probe_run'] = foreign
        self.assertFalse(receipt._qualify('actql_probe_run', foreign))

    def test_actual_wasm_journal_schema_reads_keep_the_closed_epoch(self):
        core, binding, store, _ = self.fixture()
        original = _SQLiteByteDatabase._journal_schema
        observed, returned = [], []
        def schema(database):
            span = core._invocation_observation
            self.assertIsNotNone(span.wasm_export)
            self.assertTrue(span.admitted)
            self.assertTrue(span._reuse_sql_snapshot())
            before = store._connection._closed_statement_epoch
            result = original(database)
            self.assertEqual(store._connection._closed_statement_epoch, before)
            observed.append(result)
            return result
        with patch.object(_SQLiteByteDatabase, '_journal_schema', schema):
            binding.inspect(lambda _: returned.extend(
                core._call('probe', 'schema') for _ in range(2)))
        self.assertEqual(len(observed), 2)
        self.assertEqual(returned, observed)
        self.assertTrue(all(result in (0, 1) for result in returned))
        self.assertIsNone(store._connection._closed_invocation)

    def test_journal_metadata_assignments_still_poison_closed_epoch(self):
        for setting in ('application_id', 'user_version'):
            for assignment in ('equals', 'parentheses'):
                with self.subTest(setting=setting, assignment=assignment):
                    held = []
                    def effect():
                        _, _, store, _ = held[0]
                        connection = store._connection
                        value = sqlite3.Connection.execute(connection,
                            f'PRAGMA main.{setting}').fetchone()[0]
                        statement = (f'PRAGMA main.{setting} = {value}' if assignment == 'equals'
                                     else f'PRAGMA main.{setting}({value})')
                        # Even writing the identical header value is an effect,
                        # not one of the exact audited read-only templates.
                        sqlite3.Connection.execute(connection, statement)
                        return 0
                    held.append(self.fixture(effect=effect))
                    core, binding, store, _ = held[0]
                    with self.assertRaises(LocalStorageError):
                        self.run_export(core, binding, effect=1)
                    self.assertTrue(core._closing)
                    self.assertIsNone(store._connection._closed_invocation)

    def test_many_current_imports_reuse_only_inside_same_real_export(self):
        core, binding, store, _ = self.fixture()
        original = _SQLiteByteDatabase._snapshot_identity
        snapshots, spans, counts = [], [], []
        def snapshot(database):
            snapshots.append(database)
            return original(database)
        def consume(_):
            for count in (1, 40):
                before = len(snapshots)
                self.assertEqual(core._call('probe', 'run', count, 0, 0), 7)
                counts.append(len(snapshots) - before)
                self.assertIsNone(store._connection._closed_invocation)
                self.assertIsNone(core._invocation_observation)
        original_check = _InvocationObservation.check
        def check(span, *, physical=False):
            if physical:
                spans.append(span)
                self.assertIsNotNone(span.wasm_export)
            return original_check(span, physical=physical)
        with patch.object(_SQLiteByteDatabase, '_snapshot_identity', snapshot), \
                patch.object(_InvocationObservation, 'check', check):
            binding.inspect(consume)
        self.assertGreater(counts[0], 0)
        self.assertEqual(counts[0], counts[1])
        self.assertEqual(len(spans), 4)  # Entry and return for each original call.
        self.assertIsNot(spans[0], spans[2])
        self.assertTrue(all(not span.active and span.wasm_export is None for span in spans))

    def test_query_rows_and_eof_remain_real_without_per_query_schema_pragmas(self):
        core, binding, _, _ = self.fixture()
        original_snapshot, original_scan = _SQLiteByteDatabase._snapshot_identity, _SQLiteByteDatabase.scan_range
        snapshots, rows, counts = [], [], []
        def snapshot(database):
            snapshots.append(database)
            return original_snapshot(database)
        def scan(database, lower, upper, limit, **kwargs):
            row = original_scan(database, lower, upper, limit, **kwargs)
            if lower.startswith('namespace:5:probe:'):
                rows.append(row)
            return row
        def consume(_):
            for count in (1, 12):
                before = len(snapshots)
                self.assertEqual(core._call('probe', 'run', count, 1, 0), 7)
                counts.append(len(snapshots) - before)
        with patch.object(_SQLiteByteDatabase, '_snapshot_identity', snapshot), \
                patch.object(_SQLiteByteDatabase, 'scan_range', scan):
            binding.inspect(consume)
        self.assertEqual(counts[0], counts[1])
        self.assertEqual(len(rows), 26)
        self.assertEqual(sum(row is None for row in rows), 13)
        self.assertTrue(all(row[2] == b'payload' for row in rows if row is not None))

    def test_unknown_effect_has_full_before_after_and_inside_callback_fences(self):
        events, observed, held = [], [], []
        def effect():
            core, binding, _, _ = held[0]
            span = core._invocation_observation
            self.assertTrue(span.suspended)
            self.assertFalse(span._reuse_sql_snapshot())
            before = len(events)
            binding._observed_reader.current()
            observed.append(len(events) - before)
            return 0
        held.append(self.fixture(effect=effect))
        core, binding, _, _ = held[0]
        original_snapshot, original_check = _SQLiteByteDatabase._snapshot_identity, _InvocationObservation.check
        physical = []
        def snapshot(database):
            events.append(database)
            return original_snapshot(database)
        def counted(span, **kwargs):
            before = len(events)
            result = original_check(span, **kwargs)
            if kwargs.get('physical'):
                self.assertGreater(len(events), before)
                physical.append(span)
            return result
        with patch.object(_SQLiteByteDatabase, '_snapshot_identity', snapshot), \
                patch.object(_InvocationObservation, 'check', counted):
            self.assertEqual(self.run_export(core, binding, effect=1), [7])
        self.assertEqual(len(physical), 4)
        self.assertEqual(len(observed), 1)
        self.assertGreater(observed[0], 0)

    def test_effect_mutations_refuse_and_release_only_transient_observation(self):
        for kind in ('row', 'main', 'temp', 'savepoint', 'transaction', 'callback'):
            with self.subTest(kind=kind):
                held = []
                def effect():
                    core, _, store, _ = held[0]
                    connection = store._connection
                    if kind == 'row':
                        connection.execute("INSERT INTO core_bytes VALUES ('unexpected', 0, X'01')")
                    elif kind in ('main', 'temp'):
                        connection.execute(f'CREATE {"TEMP " if kind == "temp" else ""}TABLE unexpected(value)')
                    elif kind == 'savepoint':
                        connection.execute('SAVEPOINT unexpected')
                        connection.execute('RELEASE unexpected')
                    elif kind == 'transaction':
                        connection.execute('COMMIT')
                        connection.execute('BEGIN')
                    else:
                        try:
                            connection.set_progress_handler(lambda: 0, 1)
                        except RuntimeError:
                            pass
                    return 0
                held.append(self.fixture(effect=effect))
                core, binding, store, _ = held[0]
                original = binding._current
                with self.assertRaises((LocalStorageError, RuntimeError, ValueError)):
                    self.run_export(core, binding, effect=1)
                self.assertTrue(core._closing)
                self.assertIs(core._loans[original.ticket], original)
                self.assertIsNone(core._invocation_observation)
                self.assertIsNone(store._connection._closed_invocation)
                self.assertIsNone(core._journal_callbacks(original.ticket).reader)

    def test_scalar_wrapper_and_replaced_runtime_members_keep_full_checks(self):
        for kind in ('scalar', 'function', 'method', 'exports_method', 'instance_method'):
            with self.subTest(kind=kind):
                core, binding, _, _ = self.fixture()
                export = core._exports['actql_probe_run']
                if kind == 'scalar':
                    core._exports._extern_map['actql_probe_run'] = lambda *args: export(*args)
                elif kind == 'function':
                    custom = wasmtime.Func(core._store,
                        wasmtime.FuncType([wasmtime.ValType.i64()] + [wasmtime.ValType.i32()] * 3,
                                          [wasmtime.ValType.i32()]),
                        lambda *args: export(core._store, *args))
                    core._exports._extern_map['actql_probe_run'] = custom
                elif kind == 'method':
                    export.type = export.type
                elif kind == 'exports_method':
                    core._exports.get = core._exports.get
                elif kind == 'instance_method':
                    core._instance.exports = core._instance.exports
                original = _SQLiteByteDatabase._snapshot_identity
                observed = []
                def snapshot(database):
                    span = core._invocation_observation
                    if span is not None and span.admitted:
                        self.assertIsNone(span.wasm_export)
                        observed.append(database)
                    return original(database)
                with patch.object(_SQLiteByteDatabase, '_snapshot_identity', snapshot):
                    self.assertEqual(self.run_export(core, binding, count=8), [7])
                self.assertGreaterEqual(len(observed), 16)

    def test_memory_buffer_helper_override_before_admission_keeps_full_checks(self):
        for target in ('instance', 'class'):
            with self.subTest(target=target):
                core, binding, _, _ = self.fixture()
                memory = core._exports['memory']
                original, helper_calls, snapshots = wasmtime.Memory.get_buffer_ptr, [], []
                def helper(receiver, *args, **kwargs):
                    self.assertIsNone(core._invocation_observation.wasm_export)
                    helper_calls.append(True)
                    return original(receiver, *args, **kwargs)
                replacement = helper if target == 'class' else lambda *a, **kw: helper(memory, *a, **kw)
                original_snapshot = _SQLiteByteDatabase._snapshot_identity
                def snapshot(database):
                    span = core._invocation_observation
                    if span is not None and span.admitted:
                        self.assertIsNone(span.wasm_export)
                        snapshots.append(database)
                    return original_snapshot(database)
                with patch.object(wasmtime.Memory if target == 'class' else memory,
                                  'get_buffer_ptr', replacement), \
                        patch.object(_SQLiteByteDatabase, '_snapshot_identity', snapshot):
                    self.assertEqual(self.run_export(core, binding, count=2, rows=1), [7])
                self.assertTrue(helper_calls)
                self.assertGreaterEqual(len(snapshots), 16)

    def test_memory_buffer_helper_override_after_admission_refuses_before_use(self):
        for target in ('instance', 'class'):
            with self.subTest(target=target):
                held, patches, calls = [], [], []
                def effect():
                    core, _, _, _ = held[0]
                    span = core._invocation_observation
                    self.assertTrue(span.admitted)
                    self.assertIsNotNone(span.wasm_export)
                    owner = wasmtime.Memory if target == 'class' else core._exports['memory']
                    replacement = patch.object(owner, 'get_buffer_ptr',
                        lambda *_a, **_kw: calls.append(True))
                    patches.append(replacement)
                    replacement.start()
                    return 0
                held.append(self.fixture(effect=effect))
                core, binding, store, _ = held[0]
                try:
                    with self.assertRaisesRegex(ValueError, 'Wasmtime methods changed'):
                        self.run_export(core, binding, effect=1)
                finally:
                    for replacement in patches:
                        replacement.stop()
                self.assertFalse(calls)
                self.assertTrue(core._closing)
                self.assertIsNone(store._connection._closed_invocation)

    def test_caller_memory_factory_replacement_cannot_qualify(self):
        from importlib import import_module
        for owner, name in ((wasmtime.Memory, '_from_raw'),
                            (wasmtime.Memory, '__new__'),
                            (wasmtime.Caller, '__init__'),
                            (wasmtime.Caller, '_invalidate'),
                            (wasmtime.Caller, '__getattribute__'),
                            (import_module('wasmtime._func'), 'wrap_extern')):
            with self.subTest(name=name):
                core, _, _, _ = self.fixture()
                receipt, export = core._closed_wasm_exports, core._exports['actql_probe_run']
                self.assertTrue(receipt._qualify('actql_probe_run', export))
                with patch.object(owner, name, lambda *_: None):
                    self.assertFalse(receipt._qualify('actql_probe_run', export))

    def test_runtime_identity_inspection_does_not_invoke_replacement_descriptor(self):
        core, _, _, _ = self.fixture()
        calls = []
        class Replacement:
            def __get__(self, instance, owner):
                calls.append(True)
                raise AssertionError('Replacement descriptor was invoked')
        with patch.object(wasmtime.Memory, 'get_buffer_ptr', Replacement()):
            self.assertFalse(core._closed_wasm_exports._qualify(
                'actql_probe_run', core._exports['actql_probe_run']))
        self.assertFalse(calls)

    def test_trace_never_normalizes_large_or_non_pragma_statements(self):
        class NoNormalization(str):
            def strip(self, *args):
                raise AssertionError('Unbounded SQL normalization')
            def rstrip(self, *args):
                raise AssertionError('Unbounded SQL normalization')
            def upper(self):
                raise AssertionError('Unbounded SQL normalization')
        connection = _TrackedSQLiteConnection(':memory:')
        self.addCleanup(connection.close)
        before = connection._closed_statement_epoch
        for statement in (
                "INSERT INTO core_bytes VALUES ('large', 0, X'" + '00' * 32768 + "')",
                'CREATE TABLE large (' + 'value, ' * 8192 + 'last)',
                'PRAGMA main.user_version' + ' ' * 65536):
            connection._trace_transaction(NoNormalization(statement))
        self.assertEqual(connection._closed_statement_epoch, before + 3)

    def test_replaced_export_during_effect_latches_failure(self):
        held, failures = [], []
        def effect():
            core, _, _, _ = held[0]
            original = core._exports._extern_map['actql_probe_run']
            core._exports._extern_map['actql_probe_run'] = lambda *_: 7
            try:
                core._invocation_observation._guard_sql()
            except ValueError as error:
                failures.append(error)
            finally:
                core._exports._extern_map['actql_probe_run'] = original
            return 0
        held.append(self.fixture(effect=effect))
        core, binding, _, _ = held[0]
        with self.assertRaises(ValueError) as raised:
            self.run_export(core, binding, effect=1)
        self.assertIs(raised.exception, failures[0])

    def test_raw_connection_and_cursor_ddl_restore_cannot_evade_closed_epoch(self):
        for route in ('base', 'cursor', 'thread'):
            with self.subTest(route=route):
                held = []
                def effect():
                    _, _, store, _ = held[0]
                    connection = store._connection
                    # These bypass the overridden Connection.execute. Restoring
                    # both schema versions must not restore a closed observation.
                    def mutate():
                        execute = (connection.cursor().execute if route == 'cursor'
                                   else lambda sql: sqlite3.Connection.execute(connection, sql))
                        for schema in ('main', 'temp'):
                            before = execute(f'PRAGMA {schema}.schema_version').fetchone()[0]
                            execute(f'CREATE TABLE {schema}.unexpected(value)')
                            execute(f'DROP TABLE {schema}.unexpected')
                            execute(f'PRAGMA {schema}.schema_version = {before}')
                    if route == 'thread':
                        thread = Thread(target=mutate)
                        thread.start()
                        thread.join()
                    else:
                        mutate()
                    return 0
                held.append(self.fixture(effect=effect))
                core, binding, store, _ = held[0]
                with self.assertRaises(LocalStorageError):
                    self.run_export(core, binding, effect=1)
                self.assertTrue(core._closing)
                self.assertIsNone(store._connection._closed_invocation)

    def test_raw_sql_during_an_actual_audited_import_is_sticky(self):
        # Injection is diagnostic only, at the physical scan. The raw SQL runs
        # on another thread while the original Wasm export/import is active.
        for statement in ('CREATE TEMP TABLE concurrent(value)',
                          'PRAGMA schema_version = 0',
                          "ATTACH DATABASE ':memory:' AS unexpected"):
            with self.subTest(statement=statement):
                core, binding, store, _ = self.fixture()
                original = _SQLiteByteDatabase.scan_range
                failures, executed = [], []
                def scan(database, lower, upper, limit, **kwargs):
                    if lower.startswith('namespace:5:probe:'):
                        span = core._invocation_observation
                        self.assertTrue(span._reuse_sql_snapshot())
                        def mutate():
                            try:
                                sqlite3.Connection.execute(store._connection, statement)
                                executed.append(True)
                            except BaseException as error:
                                failures.append(error)
                        thread = Thread(target=mutate)
                        thread.start()
                        thread.join()
                    return original(database, lower, upper, limit, **kwargs)
                with patch.object(_SQLiteByteDatabase, 'scan_range', scan):
                    with self.assertRaises(LocalStorageError):
                        self.run_export(core, binding, rows=1)
                self.assertFalse(failures)
                self.assertEqual(executed, [True])
                self.assertTrue(core._closing)
                self.assertIsNone(store._connection._closed_invocation)

    def test_pre_admission_attempted_mutation_keeps_legacy_route(self):
        core, binding, store, _ = self.fixture()
        observed = []
        original = _SQLiteByteDatabase._snapshot_identity
        def snapshot(database):
            span = core._invocation_observation
            if span is not None:
                observed.append(span)
            return original(database)
        def consume(_):
            sqlite3.Connection.execute(store._connection,
                'UPDATE core_bytes SET generation = generation WHERE 0')
            self.assertEqual(core._call('probe', 'run', 8, 0, 0), 7)
        with patch.object(_SQLiteByteDatabase, '_snapshot_identity', snapshot):
            binding.inspect(consume)
        self.assertTrue(observed)
        self.assertTrue(all(span.disabled and not span.admitted for span in observed))

    def test_file_mutation_still_blocks_effect_and_return(self):
        for effect in (0, 1):
            with self.subTest(effect=effect):
                effects, changed = [], []
                core, binding, _, path = self.fixture(effect=lambda: effects.append(True) or 0)
                original = _SQLiteByteDatabase.scan_range
                def scan(database, lower, upper, limit, **kwargs):
                    if lower.startswith('namespace:5:probe:') and not changed:
                        changed.append(True)
                        (path / 'source' / binding._account.name).write_bytes(b'changed')
                    return original(database, lower, upper, limit, **kwargs)
                with patch.object(_SQLiteByteDatabase, 'scan_range', scan):
                    with self.assertRaises(LocalFileError):
                        self.run_export(core, binding, rows=1, effect=effect)
                self.assertEqual(changed, [True])
                self.assertFalse(effects)
                self.assertTrue(core._closing)

    def test_original_cumulative_query_limit_still_refuses(self):
        core, binding, store, _ = self.fixture()
        store._max_inspection_queries = 24
        with self.assertRaisesRegex(LocalStorageError, 'inspection capacity'):
            self.run_export(core, binding, count=40, rows=1)
        self.assertTrue(core._closing)
        self.assertIsNone(store._connection._closed_invocation)

    def test_receipt_reservation_failure_allocates_no_receipt(self):
        core, _, _, _ = self.fixture(capture=False)
        failure = RuntimeError('original workspace refused')
        with patch.object(core, 'reserve_workspace', side_effect=failure), \
                patch.object(_ClosedWasmExports, '__init__') as constructor:
            with self.assertRaises(RuntimeError) as raised:
                core._capture_closed_wasm_exports(wasmtime)
        self.assertIs(raised.exception, failure)
        constructor.assert_not_called()
        self.assertIsNone(core._closed_wasm_workspace)
        self.assertIsNone(core._closed_wasm_exports)

    def test_failed_receipt_construction_retains_original_funded_cleanup(self):
        core, _, _, _ = self.fixture(capture=False)
        constructor = _ClosedWasmExports.__init__
        failure = RuntimeError('receipt construction failed after acquisition')
        retained = []
        def fail(receipt, receiver, runtime):
            constructor(receipt, receiver, runtime)
            retained.append(receipt)
            raise failure
        with patch.object(_ClosedWasmExports, '__init__', fail):
            with self.assertRaises(RuntimeError) as raised:
                core._capture_closed_wasm_exports(wasmtime)
        self.assertIs(raised.exception, failure)
        self.assertIs(core._closed_wasm_exports, retained[0])
        workspace = core._closed_wasm_workspace
        self.assertIs(core._loans[workspace.ticket], workspace)
        self.assertTrue(core.close_workspace(workspace))
        self.assertIsNone(core._closed_wasm_exports)

    def test_pending_receipt_workspace_prevents_pool_retirement(self):
        core, _, _, _ = self.fixture()
        workspace, receipt, scalar = core._closed_wasm_workspace, core._closed_wasm_exports, core._call
        events = []
        def call(family, name, *args):
            if (family, name) == ('workspace', 'close'):
                events.append('workspace')
                if len(events) == 1:
                    return -9
            if (family, name) == ('buffer', 'close_pool'):
                events.append('pool')
                return 0
            return scalar(family, name, *args)
        core._call = call
        with patch.object(core, '_dispose') as dispose:
            self.assertFalse(LocalCore._close_core(core))
            self.assertIs(core._closed_wasm_workspace, workspace)
            self.assertIs(core._closed_wasm_exports, receipt)
            dispose.assert_not_called()
            self.assertTrue(LocalCore._close_core(core))
            dispose.assert_called_once()
        self.assertEqual(events, ['workspace', 'workspace', 'pool'])
        self.assertIsNone(core._closed_wasm_workspace)
        self.assertIsNone(core._closed_wasm_exports)

    def test_metadata_is_bounded_by_the_original_issued_workspace(self):
        core, _, _, _ = self.fixture()
        receipt, workspace = core._closed_wasm_exports, core._closed_wasm_workspace
        self.assertIs(core._loans[workspace.ticket], workspace)
        self.assertLessEqual(receipt._retained_bytes() + 2048, _CLOSED_WASM_RECEIPT_BYTES)
        self.assertIs(receipt.mapping, core._exports._extern_map)
        self.assertIs(receipt.sequence, core._exports._extern_seq)
        self.assertGreaterEqual(sys.getsizeof(object.__new__(_InvocationObservation)),
                                len(_InvocationObservation.__slots__) * 8)


if __name__ == '__main__':
    unittest.main()
