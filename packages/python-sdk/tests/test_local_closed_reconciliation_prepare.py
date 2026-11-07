"""Exact prepare receipts on real SQLite, files and genuine Wasmtime exports.

The mini module is only a neutral physical transport fixture. It neither proves
Account decisions nor substitutes for an installed product/latency campaign.
No pinned product method is patched to count calls or inject mutations.
"""
import copy
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
from threading import Thread
import unittest
from unittest.mock import patch

import wasmtime

from actql_sdk._local_commit_projection import OriginalCommitProjection
from actql_sdk._local_core import (
    _MEMORY_LIMIT, _RECONCILIATION_PREPARE_BYTES, _Output,
    _original_metadata_cleanup, _original_metadata_stopped,
)
from actql_sdk._local_host_binding import _OriginalPublisherPort
from actql_sdk._local_observation_transfer import OriginalObservationTransfer
from actql_sdk._local_reader_facts import OriginalReaderFacts
from actql_sdk._local_reconciliation_prepare import (
    _EXPORT_NAMES, _PREPARE_MAX_METADATA_BYTES, _prepare_supported,
)
from actql_sdk._local_storage import LocalByteStore, LocalStorageError
from actql_sdk._local_store_reconciliation import OriginalStoreReconciliation
import test_local_closed_invocation as closed
import test_local_reader_facts as files
import test_local_store_reconciliation as reconciliation


class ClosedReconciliationPrepareTests(unittest.TestCase):
    def fixture(self, *, effect=None):
        bootstrap = closed.ClosedInvocationTests()
        self.addCleanup(bootstrap.doCleanups)
        core, binding, store, _, _ = bootstrap.fixture()
        scalar_call = core._call
        helper = files.ReaderFactsTests()
        _, root, _, final = self.enterContext(helper.file())
        reader = helper.transfer_ready(root, final)

        # Only nominal parent loans are fixture data; all prepare exports and
        # Host callbacks below use the unmodified production dispatch path.
        def parent(family):
            ticket = core._next_ticket
            core._next_ticket += 1
            value = _Output(core._identity, ticket, 100 + ticket, 1048576, family)
            core._loans[ticket] = value
            return value
        publication = parent('publication')
        record = parent('payload_record')
        preflight = parent('publication_preflight')
        del core._call
        self.addCleanup(setattr, core, '_call', scalar_call)
        engine = wasmtime.Engine()
        core._store = wasmtime.Store(engine)
        fixture = reconciliation.StoreReconciliationTests
        publisher_fact = json.dumps(dict(stage='request', namespace_id='local',
            authority_scope_cid='opaque-scope', run_definition_cid='opaque-run',
            publication_request_cid='opaque-request', public_index_entry_cid=None),
            separators=(',', ':')).encode()
        definitions = [
            ('input_copy', core._input_copy, 4, True),
            ('input_cleanup', core._cleanup, 1, False),
            ('publisher_current', core._publisher_current, 1, False),
            ('publisher_begin', core._publisher_begin, 2, False),
            ('publisher_copy', core._publisher_copy, 4, True),
            ('publisher_finish', core._publisher_finish, 1, False),
            ('test_effect', effect or (lambda: 0), 0, False),
        ]
        imports = '\n'.join(f'(import "host" "{name}" (func ${name} '
            f'{"(param " + " ".join(["i32"] * count) + ")" if count else ""} (result i32)))'
            for name, _, count, _ in definitions)
        exports = []
        def export(name, count, body):
            exports.append(f'(func (export "actql_{name}") (param i64) '
                + ' '.join(f'(param $p{i} i32)' for i in range(count))
                + f' (result i32) {body})')
        def constant(name, count, result=0):
            export(name, count, f'i32.const {result}')
        def counted(name, count, counter, body='i32.const 0'):
            export(name, count, f'global.get ${counter} i32.const 1 i32.add global.set ${counter} {body}')
        constant('current_bind', 1)
        constant('current_validate', 1)
        export('workspace_reserve', 2, 'local.get $p0 i32.const 100 i32.add')
        export('buffer_reserve', 3, 'local.get $p0 i32.const 100 i32.add')
        export('buffer_fill_block', 3, '''local.get $p0 i32.const 100 i32.sub
            local.get $p1 i32.const 4096 local.get $p2 call $input_copy
            local.get $p2 i32.eq if (result i32) i32.const 0 else i32.const -5 end''')
        constant('buffer_seal', 1)
        export('publisher_reserve', 4, 'local.get $p2 i32.const 100 i32.add')
        counted('publisher_authorize', 4, 'authorizations', f'''
            local.get $p0 i32.const 100 i32.sub call $publisher_current drop
            local.get $p0 i32.const 100 i32.sub i32.const {len(publisher_fact)} call $publisher_begin drop
            local.get $p0 i32.const 100 i32.sub i32.const 0 i32.const 512
            i32.const {len(publisher_fact)} call $publisher_copy drop
            local.get $p0 i32.const 100 i32.sub call $publisher_finish''')
        constant('publication_commit_export_result_count', 2, 1)
        counted('publication_commit_export_validate_payload_binding', 5, 'bindings')
        counted('payload_record_validate_snapshot', 3, 'snapshots')
        export('publication_commit_export_reserve', 3, 'local.get $p1 i32.const 100 i32.add')
        export('publication_commit_export_produce_index_key', 2, '''
            i32.const 64 global.set $length i32.const 64 global.set $address
            global.get $effect_enabled if call $test_effect drop end i32.const 0''')
        export('publication_commit_export_produce_lookup_reference', 3, '''
            i32.const 71 global.set $length local.get $p2
            if (result i32) i32.const 256 else i32.const 128 end
            global.set $address i32.const 0''')
        export('publication_commit_export_length', 1, 'global.get $length')
        export('buffer_read_block', 3, 'global.get $address local.get $p1 i32.add')
        export('publication_commit_export_close', 1, '''global.get $refuse_cleanup
            if (result i32) i32.const -9 else
            local.get $p0 i32.const 100 i32.sub call $input_cleanup end''')
        counted('publication_prepare_lookup', 4, 'lookups')
        counted('publication_prepare_observation', 4, 'responses')
        def data(offset, raw):
            return f'(data (i32.const {offset}) "' + ''.join(f'\\{byte:02x}' for byte in raw) + '")'
        globals_ = '\n'.join(f'(global ${name} (export "{name}") (mut i32) (i32.const 0))'
            for name in ('bindings', 'snapshots', 'authorizations', 'lookups', 'responses',
                         'address', 'length', 'effect_enabled', 'refuse_cleanup'))
        module = wasmtime.Module(engine, '(module ' + imports + globals_
            + f'(memory (export "memory") 1 {_MEMORY_LIMIT // 65536})'
            + data(64, b'd' * 64) + data(128, fixture.request_ref)
            + data(256, fixture.attempt_ref) + data(512, publisher_fact)
            + '\n'.join(exports) + ')')
        functions = [wasmtime.Func(core._store,
            wasmtime.FuncType([wasmtime.ValType.i32()] * count, [wasmtime.ValType.i32()]),
            core._observation_import(name, callback), access_caller=caller)
            for name, callback, count, caller in definitions]
        core._instance = wasmtime.Instance(core._store, module, functions)
        core._exports = core._instance.exports(core._store)
        core._observe_platform_vm(wasmtime)
        core._closed_wasm_exports = core._closed_wasm_workspace = None
        core._capture_closed_wasm_exports(wasmtime)
        request = core.reserve_input(b'opaque publisher request',
            cleanup=_original_metadata_cleanup, stopped=_original_metadata_stopped)
        port = _OriginalPublisherPort(binding)
        publisher = core.reserve_publisher(preflight, request,
            current=port.current_callback, authorize=port.authorize_callback,
            cleanup=_original_metadata_cleanup, original=port)
        projection = OriginalCommitProjection(core, publication, 31, cleanup=_original_metadata_cleanup)
        facts = OriginalReaderFacts(projection, record, root, reader, 0, 0,
            'sha256:' + '1' * 64, 'sha256:' + '3' * 64,
            cleanup=_original_metadata_cleanup, stopped=_original_metadata_stopped)
        facts.validate()
        transfers = tuple(OriginalObservationTransfer(projection, publisher,
            max_source_bytes=512, max_packet_bytes=512,
            cleanup=_original_metadata_cleanup, stopped=_original_metadata_stopped,
            workspace_cleanup=_original_metadata_cleanup,
            workspace_stopped=_original_metadata_cleanup) for _ in range(2))
        for transfer in transfers:
            transfer.reserve()
        originals = helper.original(store)
        for key, raw in ((fixture.scope_key, fixture.ref), (fixture.index_key, fixture.index),
                         (fixture.request_key, fixture.request), (fixture.attempt_key, fixture.attempt)):
            store.compare_exchange(key, None, raw)
        owner = OriginalStoreReconciliation(projection, (facts,), store, originals, publisher, *transfers)
        self.assertTrue(all(core._closed_wasm_exports._qualify(name, core._exports[name])
                            for name in _EXPORT_NAMES))
        self.assertTrue(_prepare_supported(owner, binding), 'Fixture must genuinely admit exact prepare')
        for name in ('bindings', 'snapshots', 'authorizations', 'lookups', 'responses'):
            core._exports[name].set_value(core._store, 0)
        return core, binding, store, owner

    def counter(self, core, name):
        return core._exports[name].value(core._store)

    def test_complete_prepare_keeps_real_rows_all_validators_and_original_loans(self):
        core, binding, store, owner = self.fixture()
        original_loans = dict(core._loans)
        metadata = owner._facts[0].pending_input
        owner.prepare(binding=binding)
        checkpoints, reads, copied, pairs, authorizations = owner._prepare_counts
        self.assertEqual((checkpoints, reads, pairs, authorizations), (8, 4, 48, 16))
        source = reconciliation.StoreReconciliationTests
        self.assertEqual(copied, sum(map(len, (source.ref, source.index, source.request, source.attempt))))
        self.assertEqual([self.counter(core, name) for name in ('bindings', 'snapshots', 'authorizations')],
                         [48, 48, 16])
        for ticket, loan in original_loans.items():
            self.assertIs(core._loans[ticket], loan)
        self.assertIs(owner._facts[0].pending_input, metadata)
        lookup = core._inputs[owner._lookup.pending_input.ticket].payload
        response = core._inputs[owner._response.pending_input.ticket].payload
        self.assertEqual(json.loads(lookup), {'identity': source.ref.decode(), 'index': source.index.decode()})
        self.assertEqual(json.loads(response), {'kind': 'stored', 'index': source.index.decode(),
            'request': source.request.decode(), 'attempt': source.attempt.decode()})
        self.assertFalse(store._connection.in_transaction)
        self.assertIsNone(core._reconciliation_prepare)
        self.assertIsNone(store._connection._closed_prepare)
        self.assertEqual(owner._projection.pending_outputs, ())

    def test_private_modules_import_in_either_order(self):
        source = str(Path(__file__).resolve().parents[1] / 'src')
        modules = ('actql_sdk._local_reconciliation_prepare', 'actql_sdk._local_store_reconciliation')
        for order in (modules, tuple(reversed(modules))):
            with self.subTest(first=order[0]):
                result = subprocess.run([sys.executable, '-c',
                    '; '.join('import ' + name for name in order)],
                    capture_output=True, text=True,
                    env=os.environ | {'PYTHONPATH': source}, timeout=20)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_real_query_failure_keeps_named_report_and_original_exception(self):
        held, phases, limits = [], [], []
        def effect():
            core, binding, store, owner = held[0]
            phase = core._reconciliation_prepare
            self.assertIsNotNone(phase)
            self.assertTrue(phase.suspended)
            self.assertEqual(phase.reads, 0)
            phases.append(phase)
            key = reconciliation.StoreReconciliationTests.scope_key
            # Real SQLite rejects this longer literal publication-row query,
            # while the shorter original metadata/reservation queries still
            # run. No product dispatch or callback is replaced to induce it.
            template = ("SELECT generation,\n"
                "            CASE WHEN length(payload) <= " + str(store._max_record_bytes)
                + " THEN payload ELSE NULL END,\n"
                "            typeof(payload), length(payload)\n"
                "            FROM core_bytes WHERE key = CAST(X'" + key.encode().hex() + "' AS TEXT)")
            required = (*binding._fences, binding._frame_epoch,
                        *(fence for fence, _ in owner._originals))
            self.assertTrue(all(len(fence.key.encode()) < len(key.encode()) for fence in required))
            limit = len(template.encode()) - 1
            previous = sqlite3.Connection.setlimit(store._connection, sqlite3.SQLITE_LIMIT_SQL_LENGTH, limit)
            limits.append(previous)
            return 0
        held.append(self.fixture(effect=effect))
        core, binding, store, owner = held[0]
        core._exports['effect_enabled'].set_value(core._store, 1)
        try:
            with self.assertRaises(sqlite3.Error) as raised:
                owner.prepare(binding=binding)
        finally:
            if limits:
                sqlite3.Connection.setlimit(store._connection, sqlite3.SQLITE_LIMIT_SQL_LENGTH, limits[0])
        self.assertEqual(len(phases), 1)
        self.assertIs(phases[0].failure, raised.exception)
        self.assertFalse(phases[0].active)
        self.assertTrue(phases[0].suspended)
        self.assertEqual(owner._prepare_counts[1], 0)
        # Two ordinary before-lookup fences preceded the failed query. Its
        # original named failure continuation adds a third, using full checks.
        self.assertEqual([self.counter(core, name) for name in ('bindings', 'snapshots', 'authorizations')],
                         [9, 9, 3])
        self.assertEqual(self.counter(core, 'responses'), 1)
        response = owner._response.pending_input
        self.assertIsNotNone(response)
        self.assertEqual(json.loads(core._inputs[response.ticket].payload), {'kind': 'query_failed'})
        self.assertIsNone(owner._lookup.pending_input)
        self.assertEqual(owner._lookup.pending_sources, ())
        output, = owner._projection.pending_outputs
        self.assertIs(core._loans[output.ticket], output)
        self.assertFalse(store._connection.in_transaction)
        before = self.counter(core, 'bindings')
        with self.assertRaises(RuntimeError):
            owner.prepare(binding=binding)
        self.assertEqual(self.counter(core, 'bindings'), before)

    def test_replaced_later_export_selects_legacy_before_entry(self):
        core, binding, _, owner = self.fixture()
        name = 'actql_publication_prepare_observation'
        original = core._exports[name]
        core._exports._extern_map[name] = lambda *args: original(*args)
        self.assertFalse(_prepare_supported(owner, binding))
        owner.prepare(binding=binding)
        self.assertFalse(hasattr(owner, '_prepare_counts'))
        self.assertEqual(self.counter(core, 'responses'), 1)

    def test_legal_mutation_before_reader_is_not_a_stale_phase(self):
        core, binding, store, owner = self.fixture()
        store.compare_exchange(store.namespaced_key('probe', 'prior'), None, b'legal prior write')
        self.assertTrue(_prepare_supported(owner, binding))
        owner.prepare(binding=binding)
        self.assertEqual(owner._prepare_counts[1], 4)
        self.assertEqual(self.counter(core, 'responses'), 1)

    def test_unknown_effect_raw_schema_changes_are_sticky_even_after_restore(self):
        for schema in ('main', 'temp'):
            with self.subTest(schema=schema):
                held, failures, phases = [], [], []
                def effect():
                    core, _, store, _ = held[0]
                    phase = core._reconciliation_prepare
                    phases.append(phase)
                    self.assertTrue(phase.suspended)
                    self.assertTrue(core._invocation_observation.suspended)
                    connection = store._connection
                    sqlite3.Connection.execute(connection, f'CREATE TABLE {schema}.unexpected(value)')
                    sqlite3.Connection.execute(connection, f'DROP TABLE {schema}.unexpected')
                    try:
                        phase.check()
                    except (ValueError, LocalStorageError) as error:
                        failures.append(error)
                    return 0
                held.append(self.fixture(effect=effect))
                core, binding, store, owner = held[0]
                core._exports['effect_enabled'].set_value(core._store, 1)
                with self.assertRaises((ValueError, LocalStorageError)) as raised:
                    owner.prepare(binding=binding)
                self.assertTrue(failures)
                self.assertIs(raised.exception, failures[0])
                self.assertFalse(phases[0].active)
                self.assertIsNone(store._connection._closed_prepare)
                self.assertEqual(self.counter(core, 'responses'), 0)

    def test_copied_or_retired_phase_cannot_resume(self):
        for mode in ('copy', 'retire'):
            with self.subTest(mode=mode):
                held, failures = [], []
                def effect():
                    phase = held[0][0]._reconciliation_prepare
                    candidate = copy.copy(phase) if mode == 'copy' else phase
                    if mode == 'retire':
                        candidate.active = False
                    try:
                        candidate.check()
                    except (ValueError, LocalStorageError) as error:
                        failures.append(error)
                        phase._fail(error)
                    return 0
                held.append(self.fixture(effect=effect))
                core, binding, _, owner = held[0]
                core._exports['effect_enabled'].set_value(core._store, 1)
                with self.assertRaises((ValueError, LocalStorageError)) as raised:
                    owner.prepare(binding=binding)
                self.assertTrue(failures)
                self.assertIs(raised.exception, failures[0])

    def test_issued_output_callback_replacement_refuses_before_cleanup(self):
        for field in ('cleanup', 'stopped'):
            with self.subTest(field=field):
                held, invoked = [], []
                def effect():
                    phase = held[0][0]._reconciliation_prepare
                    setattr(phase.output_physical, field, lambda *_: invoked.append(True) or True)
                    return 0
                held.append(self.fixture(effect=effect))
                core, binding, _, owner = held[0]
                core._exports['effect_enabled'].set_value(core._store, 1)
                with self.assertRaises(ValueError):
                    owner.prepare(binding=binding)
                self.assertFalse(invoked)
                self.assertEqual(len(owner._projection.pending_outputs), 1)

    def test_query_and_copy_budgets_remain_cumulative(self):
        for mode in ('queries', 'bytes'):
            with self.subTest(mode=mode):
                held, phases = [], []
                def effect():
                    core, _, store, _ = held[0]
                    phase = core._reconciliation_prepare
                    self.assertIsNotNone(phase)
                    self.assertTrue(phase.active)
                    self.assertEqual(phase.reads, 0)
                    phases.append(phase)
                    # The namespace preamble retained its original capacity.
                    # Reduce only the subsequent publication-read budget.
                    if mode == 'queries':
                        store._max_inspection_queries = 3
                    else:
                        source = reconciliation.StoreReconciliationTests
                        store._max_payload_bytes = sum(map(len,
                            (source.ref, source.index, source.request, source.attempt))) - 1
                    return 0
                held.append(self.fixture(effect=effect))
                core, binding, store, owner = held[0]
                core._exports['effect_enabled'].set_value(core._store, 1)
                with self.assertRaises(LocalStorageError) as raised:
                    owner.prepare(binding=binding)
                self.assertEqual(len(phases), 1)
                self.assertIs(phases[0].failure, raised.exception)
                self.assertFalse(phases[0].active)
                self.assertTrue(hasattr(owner, '_prepare_counts'))
                self.assertEqual(owner._prepare_counts[1], 3)
                self.assertEqual(self.counter(core, 'responses'), 0)
                self.assertFalse(store._connection.in_transaction)
                before = self.counter(core, 'bindings')
                with self.assertRaises(RuntimeError):
                    owner.prepare(binding=binding)
                self.assertEqual(self.counter(core, 'bindings'), before)
                with self.assertRaises(LocalStorageError) as repeated:
                    phases[0].check()
                self.assertIs(repeated.exception, raised.exception)

    def test_foreign_thread_raw_select_poison_is_sticky(self):
        held, phases, thread_errors, selected = [], [], [], []
        def effect():
            core, _, store, _ = held[0]
            phase = core._reconciliation_prepare
            phases.append(phase)
            self.assertTrue(phase.suspended)
            before = store._connection._closed_statement_epoch
            def foreign_read():
                try:
                    # Bypass subclass execute deliberately: the retained SQLite
                    # trace must see activity even through a raw base-class API.
                    selected.append(sqlite3.Connection.execute(
                        store._connection, 'SELECT 1').fetchone())
                except BaseException as error:
                    thread_errors.append(error)
            thread = Thread(target=foreign_read)
            thread.start()
            thread.join()
            self.assertEqual(thread_errors, [])
            self.assertEqual(selected, [(1,)])
            self.assertGreater(store._connection._closed_statement_epoch, before)
            return 0
        held.append(self.fixture(effect=effect))
        core, binding, store, owner = held[0]
        core._exports['effect_enabled'].set_value(core._store, 1)
        with self.assertRaises(LocalStorageError) as raised:
            owner.prepare(binding=binding)
        self.assertEqual(len(phases), 1)
        self.assertIs(phases[0].failure, raised.exception)
        self.assertFalse(phases[0].active)
        self.assertIsNone(store._connection._closed_prepare)
        self.assertEqual(self.counter(core, 'responses'), 0)
        with self.assertRaises(LocalStorageError) as repeated:
            phases[0].check()
        self.assertIs(repeated.exception, raised.exception)

    def test_preentry_dispatch_customization_selects_legacy(self):
        for target in ('core_instance', 'defining_class'):
            with self.subTest(target=target):
                core, binding, _, owner = self.fixture()
                if target == 'core_instance':
                    replacement = patch.object(core, '_call', core._call)
                else:
                    original = LocalByteStore._read_bytes_locked
                    def customized(store, *args, **kwargs):
                        return original(store, *args, **kwargs)
                    replacement = patch.object(LocalByteStore, '_read_bytes_locked', customized)
                with replacement:
                    self.assertFalse(_prepare_supported(owner, binding))
                    owner.prepare(binding=binding)
                self.assertFalse(hasattr(owner, '_prepare_counts'))
                self.assertEqual(self.counter(core, 'responses'), 1)

    def test_maximum_fixed_receipt_metadata_is_funded(self):
        self.assertGreater(_PREPARE_MAX_METADATA_BYTES, 0)
        self.assertLessEqual(_PREPARE_MAX_METADATA_BYTES, _RECONCILIATION_PREPARE_BYTES)

    def test_refused_output_cleanup_keeps_original_output_and_disallows_replay(self):
        core, binding, _, owner = self.fixture()
        core._exports['refuse_cleanup'].set_value(core._store, 1)
        with self.assertRaises((RuntimeError, ValueError)):
            owner.prepare(binding=binding)
        self.assertTrue(hasattr(owner, '_prepare_counts'))
        output, = owner._projection.pending_outputs
        self.assertIs(core._loans[output.ticket], output)
        self.assertIn(output.ticket, core._inputs)
        before = self.counter(core, 'bindings')
        with self.assertRaises(RuntimeError):
            owner.prepare(binding=binding)
        self.assertEqual(self.counter(core, 'bindings'), before)


if __name__ == '__main__':
    unittest.main()
