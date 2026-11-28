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

from actql_sdk._local_core import LocalCore, _MEMORY_LIMIT
from actql_sdk._local_host_binding import _InvocationObservation
from actql_sdk._local_files import LocalFileError
from actql_sdk._local_storage import ByteFence, ByteWrite, LocalStorageError, StoredBytes
from actql_sdk._local_storage_physical import _SQLiteByteDatabase, _TrackedSQLiteConnection
import test_local_closed_invocation as closed


class ClosedWasmSqlTests(unittest.TestCase):
    def fixture(self, *, effect=None, capture=True, legacy_census_supplier=False,
                census_export='prepare_sdk_payload_input', effect_import='test_effect'):
        fixture = closed.ClosedInvocationTests()
        self.addCleanup(fixture.doCleanups)
        core, binding, store, path, _ = fixture.fixture()
        store.compare_exchange(store.namespaced_key('probe', 'row'), None, b'payload')
        engine = wasmtime.Engine()
        core._store = wasmtime.Store(engine)
        ticket = binding._current.ticket
        module = wasmtime.Module(engine, f'''(module
            (import "test" "current" (func $current (param i32) (result i64)))
            (import "test" "saved" (func $saved (param i32) (result i64)))
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
            (func (export "actql_publication_commit_export_{census_export}")
                    (param i64) (param $effect i32) (param $negotiate i32) (result i32)
                (local $before i32)
                i32.const {ticket} call $current i64.const 1 i64.eq
                if else unreachable end
                i32.const 0 call $one i32.eqz if else unreachable end
                i32.const {ticket} call $release drop
                i32.const {ticket} call $schema i32.const 1 i32.le_u
                if else unreachable end
                local.get $negotiate
                if
                    i32.const {ticket} call $saved i32.wrap_i64 local.set $before
                end
                local.get $before i32.const 1 i32.eq
                if (result i32)
                    local.get $effect if call $effect drop end
                    local.get $before i32.const 10 i32.mul
                    i32.const {ticket} call $saved i32.wrap_i64 i32.add
                else
                    i32.const 0
                end)
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
        def unavailable_saved_reader(current_ticket):
            self.assertEqual(current_ticket, ticket)
            return 0

        definitions = [
            ('journal_current_operation', core._journal_current_operation, ['i32'], 'i64', False),
            ('journal_saved_reader', unavailable_saved_reader if legacy_census_supplier
             else core._journal_saved_reader, ['i32'], 'i64', False),
            ('journal_begin', core._journal_begin, ['i32'] * 4, 'i32', False),
            ('journal_query_copy', core._journal_query_copy, ['i32'] * 4, 'i32', True),
            ('journal_query', core._journal_query, ['i32'], 'i32', False),
            ('journal_length', core._journal_length, ['i32'] * 2, 'i32', False),
            ('journal_release', core._journal_release, ['i32'], 'i32', False),
            (effect_import, effect or (lambda: 0), [], 'i32', False),
            ('journal_schema', core._journal_schema, ['i32'], 'i32', False),
        ]
        imports = [wasmtime.Func(core._store,
            wasmtime.FuncType([getattr(wasmtime.ValType, item)() for item in params],
                              [getattr(wasmtime.ValType, result)()]),
            core._observation_import(name, callback), access_caller=caller)
            for name, callback, params, result, caller in definitions]
        core._instance = wasmtime.Instance(core._store, module, imports)
        core._exports = core._instance.exports(core._store)
        if capture:
            core._observe_platform_vm(wasmtime)
        return core, binding, store, path

    def run_export(self, core, binding, *, count=1, rows=0, effect=0):
        returned = []
        binding.inspect(lambda _: returned.append(core._call('probe', 'run', count, rows, effect)))
        return returned

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
        self.assertEqual(observed, [None, None])
        self.assertEqual(returned, [1, 1])
        self.assertIsNone(store._connection._closed_invocation)

    def test_saved_census_proof_stays_inside_the_original_closed_export(self):
        for capture, effect, legacy, negotiate, expected in (
                (True, 0, False, 1, 11), (True, 1, False, 1, 10),
                (False, 0, False, 1, 0), (True, 0, True, 1, 0), (True, 0, False, 0, 0)):
            with self.subTest(capture=capture, effect=effect, legacy=legacy, negotiate=negotiate):
                core, binding, store, _ = self.fixture(capture=capture, legacy_census_supplier=legacy)
                actual = []
                binding.inspect(lambda _: actual.append(
                    LocalCore._call(core, 'publication_commit_export', 'prepare_sdk_payload_input', effect, negotiate)))
                self.assertEqual(actual, [expected])
                self.assertIsNone(binding._observed_reader)
                self.assertIsNone(store._connection._closed_invocation)

    def test_saved_census_proof_cannot_hide_a_same_size_mutation(self):
        def effect():
            sqlite3.Connection.execute(store._connection,
                "UPDATE core_bytes SET payload=X'72657669736564' WHERE key=?",
                (store.namespaced_key('probe', 'row'),))
            return 0

        for export in ('prepare_sdk_payload_input', 'produce_sdk_payload_chunk',
                       'observe_sdk_terminal', 'prepare_sdk_payload_codecs',
                       'sdk_payload_ordinal', 'bind_sdk_payload_record'):
            with self.subTest(export=export):
                core, binding, store, _ = self.fixture(effect=effect, census_export=export)
                with self.assertRaises(LocalStorageError):
                    binding.inspect(lambda _: LocalCore._call(
                        core, 'publication_commit_export', export, 1, 1))
                self.assertTrue(core._closing)
                self.assertIsNone(binding._observed_reader)
                self.assertIsNone(store._connection._closed_invocation)

    def test_saved_chunk_census_proof_expires_at_effect_and_refuses_receipt_export(self):
        for export, effect, expected in (
                ('produce_sdk_payload_chunk', 0, 11),
                ('produce_sdk_payload_chunk', 1, 10),
                ('produce_sdk_payload_receipt', 0, 0)):
            with self.subTest(export=export, effect=effect):
                core, binding, store, _ = self.fixture(census_export=export)
                actual = []
                binding.inspect(lambda _: actual.append(
                    LocalCore._call(core, 'publication_commit_export', export, effect, 1)))
                self.assertEqual(actual, [expected])
                self.assertIsNone(binding._observed_reader)
                self.assertIsNone(store._connection._closed_invocation)

    def test_saved_routing_census_proof_requires_the_original_closed_export(self):
        for export in ('sdk_payload_ordinal', 'bind_sdk_payload_record'):
            for capture, effect, legacy, negotiate, expected in (
                    (True, 0, False, 1, 11), (True, 1, False, 1, 10),
                    (False, 0, False, 1, 0), (True, 0, True, 1, 0),
                    (True, 0, False, 0, 0)):
                with self.subTest(export=export, capture=capture, effect=effect,
                                  legacy=legacy, negotiate=negotiate):
                    core, binding, store, _ = self.fixture(
                        capture=capture, census_export=export, legacy_census_supplier=legacy)
                    actual = []
                    binding.inspect(lambda _: actual.append(
                        LocalCore._call(core, 'publication_commit_export', export, effect, negotiate)))
                    self.assertEqual(actual, [expected])
                    self.assertIsNone(binding._observed_reader)
                    self.assertIsNone(store._connection._closed_invocation)

    def test_saved_terminal_census_proof_stays_in_the_committed_readback(self):
        for export, effect, legacy, negotiate, expected in (
                ('observe_sdk_terminal', 0, False, 1, 11),
                ('observe_sdk_terminal', 1, False, 1, 10),
                ('observe_sdk_terminal', 0, True, 1, 0),
                ('observe_sdk_terminal', 0, False, 0, 0),
                ('produce_sdk_terminal_storage', 0, False, 1, 0),
                ('measure_sdk_read_delivery_storage', 0, False, 1, 0),
                ('emit_sdk_read_delivery_storage', 0, False, 1, 0),
                ('validate_sdk_read_delivery_storage', 0, False, 1, 0)):
            with self.subTest(export=export, effect=effect, legacy=legacy, negotiate=negotiate):
                core, binding, store, _ = self.fixture(census_export=export,
                                                      legacy_census_supplier=legacy)
                actual = []
                binding.inspect(lambda _: actual.append(
                    LocalCore._call(core, 'publication_commit_export', export, effect, negotiate)))
                self.assertEqual(actual, [expected])
                self.assertIsNone(binding._observed_reader)
                self.assertIsNone(store._connection._closed_invocation)

    def test_saved_codec_census_proof_expires_at_reader_stop(self):
        for stop, legacy, expected in ((0, False, 11), (1, False, 10), (1, True, 0)):
            with self.subTest(stop=stop, legacy=legacy):
                export = 'prepare_sdk_payload_codecs'
                stopped = []
                def reader_stop():
                    stopped.append(True)
                    self.assertTrue(core._invocation_observation.effect_seen)
                    return 0
                core, binding, store, _ = self.fixture(
                    effect=reader_stop, effect_import='reader_stop',
                    census_export=export, legacy_census_supplier=legacy)
                actual = []
                binding.inspect(lambda _: actual.append(
                    LocalCore._call(core, 'publication_commit_export', export, stop, 1)))
                self.assertEqual(actual, [expected])
                self.assertEqual(stopped, [True] if stop and not legacy else [])
                self.assertIsNone(binding._observed_reader)
                self.assertIsNone(store._connection._closed_invocation)

    def terminal_original(self, store):
        key = store.namespaced_key('probe', 'row')
        self.assertTrue(store.reserve_capacity('publication_payload', key, 7, 1, 32, 1))
        reservation = store.read_capacity('publication_payload', key)
        self.assertIsNotNone(reservation)
        return ((ByteFence(key, 0, b'payload'), reservation),)

    def test_saved_terminal_proposal_closes_proof_before_writing(self):
        self._check_proposal_read('produce_sdk_terminal_storage')

    def test_saved_terminal_precommit_proves_only_its_fresh_same_reader(self):
        self._check_proposal_read('produce_sdk_terminal_storage', terminal_precommit=True)

    def test_saved_terminal_reader_pair_restarts_after_each_physical_cas(self):
        export = 'validate_saved_reader_facts'
        core, binding, store, _ = self.fixture(census_export=export)
        originals = self.terminal_original(store)
        writes = [
            ByteWrite(store.namespaced_key('terminal', str(ordinal)), None, b'staged')
            for ordinal in range(3)
        ]
        changes, readers = [], []

        def validate(effect=0):
            readers.append(binding._observed_reader)
            changes.append(store._connection.total_changes)
            self.assertEqual(LocalCore._call(
                core, 'publication_commit_export', export, effect, 1), 10 if effect else 11)

        def project(ordinal, consume):
            reader = binding._observed_reader
            self.assertIsNone(reader._terminal_read_baseline(
                'actql_publication_commit_export_produce_sdk_terminal_storage'))
            validate()
            consume(writes[ordinal])
            validate(effect=1)

        def inspect(reader, take):
            binding.inspect_reader(reader, lambda _: take())

        with binding.fenced() as fences:
            start = store._connection.total_changes
            self.assertEqual(store.compare_exchange_projected_inspected(
                3, project, originals, fences, inspect=inspect, current=binding._current_observer,
                before_commit=validate, _sdk_delivery_prewrite=True, _sdk_terminal_precommit=True),
                (0, 0, 0))
        self.assertEqual(changes, [start + n for n in (0, 1, 1, 2, 2, 3, 3)])
        self.assertTrue(all(reader is readers[0] for reader in readers))
        self.assertIsNone(readers[0]._terminal_read_baseline(
            'actql_publication_commit_export_validate_saved_reader_facts'))
        self.assertIsNone(store._connection._closed_invocation)

    def test_saved_terminal_reader_pair_refuses_cas_from_its_effect(self):
        callbacks = []
        key = 'terminal-row'
        write = ByteWrite(key, None, b'staged')

        def effect():
            callbacks[0](write)
            return 0

        export = 'validate_saved_reader_facts'
        core, binding, store, _ = self.fixture(census_export=export, effect=effect)
        originals = self.terminal_original(store)

        def project(_, consume):
            callbacks.append(consume)
            LocalCore._call(core, 'publication_commit_export', export, 1, 1)

        def inspect(reader, take):
            binding.inspect_reader(reader, lambda _: take())

        with binding.fenced() as fences:
            changes = store._connection.total_changes
            with self.assertRaisesRegex(LocalStorageError, 'Terminal writes require'):
                store.compare_exchange_projected_inspected(
                    3, project, originals, fences, inspect=inspect, current=binding._current_observer,
                    before_commit=lambda: None, _sdk_delivery_prewrite=True, _sdk_terminal_precommit=True)
        self.assertEqual(len(callbacks), 1)
        self.assertEqual(store._connection.total_changes, changes)
        self.assertIsNone(store.read(key))
        self.assertIsNone(store._connection._closed_invocation)

    def test_saved_terminal_precommit_refuses_same_size_mutation_and_rolls_back(self):
        def effect():
            sqlite3.Connection.execute(store._connection,
                "UPDATE core_bytes SET payload=X'72657669736564' WHERE key=?",
                (store.namespaced_key('probe', 'row'),))
            return 0

        export = 'produce_sdk_terminal_storage'
        core, binding, store, _ = self.fixture(census_export=export, effect=effect)
        originals = self.terminal_original(store)
        writes = [
            ByteWrite(store.namespaced_key('terminal', str(ordinal)), None, b'staged')
            for ordinal in range(3)
        ]
        entered = []

        def inspect(reader, take):
            def produce(_):
                self.assertEqual(LocalCore._call(
                    core, 'publication_commit_export', export, 0, 1), 11)
                take()
            binding.inspect_reader(reader, produce)

        def before_commit():
            entered.append(store._connection.total_changes)
            LocalCore._call(core, 'publication_commit_export', export, 1, 1)

        with binding.fenced() as fences:
            changes = store._connection.total_changes
            with self.assertRaises(LocalStorageError):
                store.compare_exchange_projected_inspected(
                    3, lambda ordinal, consume: consume(writes[ordinal]),
                    originals, fences, inspect=inspect, current=binding._current_observer,
                    before_commit=before_commit, _sdk_delivery_prewrite=True,
                    _sdk_terminal_precommit=True)
        self.assertEqual(entered, [changes + 3])
        self.assertEqual(store._connection.total_changes, changes + 4)
        self.assertFalse(store._connection.in_transaction)
        self.assertIsNone(store._connection._closed_invocation)
        self.assertEqual(store.read(store.namespaced_key('probe', 'row')), StoredBytes(0, b'payload'))
        self.assertTrue(all(store.read(write.key) is None for write in writes))

    def test_saved_first_delivery_proof_closes_before_writing(self):
        for export in ('measure_sdk_read_delivery_storage', 'emit_sdk_read_delivery_storage'):
            with self.subTest(export=export):
                self._check_proposal_read(export)

    def test_saved_evidence_proposal_closes_proof_before_writing(self):
        self._check_proposal_read('produce_sdk_read_evidence_decision', insert_only=True)

    def _check_proposal_read(self, export, *, insert_only=False, terminal_precommit=False):
        cases = [(True, 0, False, False, [11, 11 if terminal_precommit else 0]),
                 (False, 0, False, False, [0, 0]),
                 (True, 1, False, False, [10, 10 if terminal_precommit else 0]),
                 (True, 0, True, False, [0, 0])]
        if insert_only:
            cases.append((True, 0, False, True, [11, 0]))
        for enabled, effect, legacy, retained, expected in cases:
            with self.subTest(enabled=enabled, effect=effect, legacy=legacy, retained=retained):
                core, binding, store, _ = self.fixture(
                    census_export=export, legacy_census_supplier=legacy)
                originals = self.terminal_original(store)
                observed, readers, epochs, changes_at_export = [], [], [], []
                key = store.namespaced_key('probe', 'inserted')
                write = ByteWrite(key, None, b'new-original')
                writes = [write]
                if terminal_precommit:
                    writes.extend(ByteWrite(store.namespaced_key('probe', f'terminal{ordinal}'),
                                            None, b'new-original') for ordinal in (1, 2))
                if retained:
                    self.assertEqual(store.compare_exchange(key, None, write.payload), 0)
                def observe():
                    readers.append(binding._observed_reader)
                    epochs.append(store._connection._transaction_epoch)
                    changes_at_export.append(store._connection.total_changes)
                    observed.append(LocalCore._call(core, 'publication_commit_export', export, effect, 1))
                def inspect(reader, take):
                    def prepare(_):
                        observe()
                        take()
                    binding.inspect_reader(reader, prepare)
                def stage(ordinal, consume):
                    if insert_only:
                        observe()
                    consume(writes[ordinal])
                def before_commit():
                    rows = []
                    binding._observed_reader.read('probe', 'inserted', rows.append)
                    self.assertEqual(rows, [('inserted', StoredBytes(0, write.payload))])
                    observe()
                with binding.fenced() as fences:
                    changes = store._connection.total_changes
                    project = (store.store_publication_projected_inspected if insert_only
                               else store.compare_exchange_projected_inspected)
                    options = {'_sdk_terminal_precommit': enabled} if terminal_precommit else {}
                    self.assertEqual(project(
                        len(writes), stage, originals, fences, inspect=inspect,
                        current=binding._current_observer, before_commit=before_commit,
                        _sdk_delivery_prewrite=enabled, **options), (0,) * len(writes))
                self.assertTrue(all(reader is readers[0] for reader in readers))
                self.assertEqual(epochs, [epochs[0]] * len(observed))
                if insert_only:
                    expected = [expected[0], *expected]
                self.assertEqual(observed, expected)
                if terminal_precommit:
                    self.assertEqual(changes_at_export, [changes, changes + 3])
                    if enabled:
                        self.assertIsNone(readers[0]._terminal_read_baseline(
                            'actql_publication_commit_export_produce_sdk_terminal_storage'))
                self.assertEqual(store._connection.total_changes, changes + (0 if retained else len(writes)))
                self.assertEqual(store.read(key), StoredBytes(0, write.payload))
                self.assertIsNone(store._connection._closed_invocation)

    def test_saved_terminal_proposal_cannot_write_during_original_wasm_callback(self):
        self._reject_write_during_proposal('produce_sdk_terminal_storage')

    def test_saved_first_delivery_cannot_write_during_original_wasm_callback(self):
        for export in ('measure_sdk_read_delivery_storage', 'emit_sdk_read_delivery_storage'):
            with self.subTest(export=export):
                self._reject_write_during_proposal(export)

    def test_saved_evidence_proposal_cannot_write_during_original_wasm_callback(self):
        self._reject_write_during_proposal('produce_sdk_read_evidence_decision', insert_only=True)

    def test_saved_evidence_row_consumer_cannot_write_during_its_proposal(self):
        consumers, failures = [], []
        def effect():
            try:
                consumers[0](write)
            except LocalStorageError as failure:
                failures.append(failure)
            return 0
        export = 'produce_sdk_read_evidence_decision'
        core, binding, store, _ = self.fixture(census_export=export, effect=effect)
        originals = self.terminal_original(store)
        write = ByteWrite(store.namespaced_key('probe', 'do-not-insert'), None, b'bytes')
        def project(_, consume):
            consumers.append(consume)
            LocalCore._call(core, 'publication_commit_export', export, 1, 1)
        def inspect(reader, take):
            binding.inspect_reader(reader, lambda _: take())
        with binding.fenced() as fences:
            changes = store._connection.total_changes
            with self.assertRaisesRegex(LocalStorageError, 'prewrite invocation') as raised:
                store.store_publication_projected_inspected(
                    1, project, originals, fences, inspect=inspect,
                    current=binding._current_observer, before_commit=lambda: None,
                    _sdk_delivery_prewrite=True)
        self.assertEqual(len(failures), 1)
        self.assertIs(raised.exception, failures[0])
        self.assertEqual(store._connection.total_changes, changes)
        self.assertIsNone(store.read(write.key))
        self.assertIsNone(store._connection._closed_invocation)

    def _reject_write_during_proposal(self, export, *, insert_only=False):
        consumers = []
        def effect():
            consumers[0]()
            return 0
        core, binding, store, _ = self.fixture(census_export=export, effect=effect)
        originals = self.terminal_original(store)
        key = store.namespaced_key('probe', 'do-not-insert')
        def inspect(reader, take):
            consumers.append(take)
            binding.inspect_reader(reader, lambda _: LocalCore._call(
                core, 'publication_commit_export', export, 1, 1))
        with binding.fenced() as fences:
            changes = store._connection.total_changes
            project = (store.store_publication_projected_inspected if insert_only
                       else store.compare_exchange_projected_inspected)
            with self.assertRaisesRegex(LocalStorageError, 'prewrite invocation'):
                project(
                    1, lambda _, consume: consume(ByteWrite(key, None, b'bytes')), originals, fences,
                    inspect=inspect, current=binding._current_observer,
                    before_commit=lambda: None, _sdk_delivery_prewrite=True)
        self.assertEqual(store._connection.total_changes, changes)
        self.assertIsNone(store.read(key))
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
        for kind in ('row', 'main', 'temp', 'transaction'):
            with self.subTest(kind=kind):
                held = []
                def effect():
                    core, _, store, _ = held[0]
                    connection = store._connection
                    if kind == 'row':
                        connection.execute("INSERT INTO core_bytes VALUES ('unexpected', 0, X'01')")
                    elif kind in ('main', 'temp'):
                        connection.execute(f'CREATE {"TEMP " if kind == "temp" else ""}TABLE unexpected(value)')
                    else:
                        store._physical.finish_read()
                        store._physical.begin_read()
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


if __name__ == '__main__':
    unittest.main()
