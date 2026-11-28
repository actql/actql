"""Fixed reconciliation read on real SQLite, files and Wasmtime exports.

The mini module is only a neutral physical transport fixture. It neither proves
Account decisions nor substitutes for an installed product/latency campaign.
No pinned product method is patched to count calls or inject mutations.
"""
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
    _MEMORY_LIMIT, LocalCoreError, _Output,
    _original_metadata_cleanup, _original_metadata_stopped,
)
from actql_sdk._local_files import LocalFileError
from actql_sdk._local_host_binding import _OriginalPublisherPort
from actql_sdk._local_observation_transfer import OriginalObservationTransfer
from actql_sdk._local_reader_facts import OriginalReaderFacts
from actql_sdk._local_storage import LocalByteStore, LocalStorageError
from actql_sdk._local_store_reconciliation import OriginalStoreReconciliation
import test_local_closed_invocation as closed
import test_local_reader_facts as files
import test_local_store_reconciliation as reconciliation


class ClosedReconciliationPrepareTests(unittest.TestCase):
    def fixture(self, *, effect=None, publisher_namespace='local'):
        bootstrap = closed.ClosedInvocationTests()
        self.addCleanup(bootstrap.doCleanups)
        core, binding, store, _, _ = bootstrap.fixture()
        scalar_call = core._call
        helper = files.ReaderFactsTests()
        directory, root, _, final = self.enterContext(helper.file())
        self.payload_path = directory / 'payload-original'
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
        publisher_fact = json.dumps(dict(stage='request', namespace_id=publisher_namespace,
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
        export('publication_commit_export_reserve_bounded', 4, '''
            local.get $p2 i32.const 64 i32.eq
            local.get $p2 i32.const 71 i32.eq i32.or
            if (result i32) local.get $p1 i32.const 100 i32.add else i32.const -4 end''')
        export('publication_commit_export_produce_index_key', 2, '''
            i32.const 64 global.set $length i32.const 64 global.set $address
            global.get $effect_enabled i32.const 1 i32.eq
            if call $test_effect drop end i32.const 0''')
        export('publication_commit_export_produce_lookup_reference', 3, '''
            i32.const 71 global.set $length local.get $p2
            if (result i32) i32.const 256 else i32.const 128 end
            global.set $address i32.const 0''')
        export('publication_commit_export_length', 1, 'global.get $length')
        export('buffer_read_block', 3, 'global.get $address local.get $p1 i32.add')
        export('publication_commit_export_close', 1, '''global.get $refuse_cleanup
            if (result i32) i32.const -9 else
            local.get $p0 i32.const 100 i32.sub call $input_cleanup end''')
        counted('publication_prepare_lookup', 4, 'lookups', '''
            global.get $effect_enabled i32.const 2 i32.eq
            if call $test_effect drop end i32.const 0''')
        constant('publication_observation_exact_index', 2, 0)
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
        # This fixture selects the ordinary SQLite route for its genuine imports.
        store._ordinary = True
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
        source = reconciliation.StoreReconciliationTests
        for name in ('bindings', 'snapshots', 'authorizations'):
            self.assertGreater(self.counter(core, name), 0)
        self.assertEqual([self.counter(core, name) for name in ('lookups', 'responses')], [1, 1])
        for ticket, loan in original_loans.items():
            self.assertIs(core._loans[ticket], loan)
        self.assertIs(owner._facts[0].pending_input, metadata)
        lookup = core._inputs[owner._lookup.pending_input.ticket].payload
        response = core._inputs[owner._response.pending_input.ticket].payload
        self.assertEqual(json.loads(lookup), {'identity': source.ref.decode(), 'index': source.index.decode()})
        self.assertEqual(json.loads(response), {'kind': 'stored', 'index': source.index.decode(),
            'request': source.request.decode(), 'attempt': source.attempt.decode()})
        self.assertFalse(store._connection.in_transaction)
        self.assertIsNone(binding._observed_reader)
        self.assertEqual(owner._projection.pending_outputs, ())

    def test_private_modules_import_in_either_order(self):
        from actql_sdk import __file__ as sdk_file
        source = str(Path(sdk_file).resolve().parents[1])
        modules = ('actql_sdk._local_storage', 'actql_sdk._local_store_reconciliation')
        for order in (modules, tuple(reversed(modules))):
            with self.subTest(first=order[0]):
                result = subprocess.run([sys.executable, '-c',
                    '; '.join('import ' + name for name in order)],
                    capture_output=True, text=True,
                    env=os.environ | {'PYTHONPATH': source}, timeout=20)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_real_query_failure_keeps_named_report_and_original_exception(self):
        held, interrupted = [], []
        def effect():
            core, binding, store, owner = held[0]
            self.assertIsNotNone(binding._observed_reader)
            self.assertTrue(store._connection.in_transaction)
            key = reconciliation.StoreReconciliationTests.scope_key
            target = False

            def observe_statement(sql):
                nonlocal target
                target = sql.startswith('SELECT generation,') and sql.endswith(
                    "WHERE key = '" + key + "'")
                if target:
                    interrupted.append(sql)

            # The fixed query shares a template with current fences. Interrupt
            # actual SQLite stepping only for the selected lookup key.
            store._connection.set_trace_callback(observe_statement)
            store._connection.set_progress_handler(lambda: int(target), 1)
            return 0

        held.append(self.fixture(effect=effect))
        core, binding, store, owner = held[0]
        core._exports['effect_enabled'].set_value(core._store, 1)
        try:
            with self.assertRaises(sqlite3.Error) as raised:
                owner.prepare(binding=binding)
        finally:
            store._connection.set_progress_handler(None, 0)
            store._connection.set_trace_callback(None)
        self.assertEqual(len(interrupted), 1)
        self.assertEqual(raised.exception.sqlite_errorcode, sqlite3.SQLITE_INTERRUPT)
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

    def test_legal_mutation_before_reader_is_not_a_stale_phase(self):
        core, binding, store, owner = self.fixture()
        store.compare_exchange(store.namespaced_key('probe', 'prior'), None, b'legal prior write')
        owner.prepare(binding=binding)
        self.assertEqual(self.counter(core, 'lookups'), 1)
        self.assertEqual(self.counter(core, 'responses'), 1)

    def test_reentrant_prepare_cannot_resume_or_be_replayed(self):
        held = []
        def effect():
            _, binding, _, owner = held[0]
            owner.prepare(binding=binding)
            raise AssertionError('Original reconciliation accepted reentry')
        held.append(self.fixture(effect=effect))
        core, binding, store, owner = held[0]
        core._exports['effect_enabled'].set_value(core._store, 1)
        with self.assertRaisesRegex(RuntimeError, 'cannot be repeated'):
            owner.prepare(binding=binding)
        self.assertEqual(self.counter(core, 'responses'), 0)
        self.assertFalse(store._connection.in_transaction)
        with self.assertRaisesRegex(RuntimeError, 'cannot be repeated'):
            owner.prepare(binding=binding)

    def test_query_and_copy_budgets_remain_cumulative(self):
        for mode in ('queries', 'bytes'):
            with self.subTest(mode=mode):
                held = []
                def effect():
                    core, _, store, _ = held[0]
                    self.assertTrue(store._connection.in_transaction)
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
                self.assertEqual(self.counter(core, 'responses'), 0)
                self.assertFalse(store._connection.in_transaction)
                before = self.counter(core, 'bindings')
                with self.assertRaises(RuntimeError):
                    owner.prepare(binding=binding)
                self.assertEqual(self.counter(core, 'bindings'), before)
    def test_refuses_a_changed_file_after_the_original_index_was_read(self):
        changed = []
        def effect():
            os.utime(self.payload_path, ns=(1, 1))
            changed.append(True)
            return 0
        core, binding, store, owner = self.fixture(effect=effect)
        core._exports['effect_enabled'].set_value(core._store, 2)
        with self.assertRaises(LocalFileError):
            owner.prepare(binding=binding)
        self.assertEqual(changed, [True])
        self.assertEqual(self.counter(core, 'lookups'), 1)
        self.assertEqual(self.counter(core, 'responses'), 0)
        self.assertIsNotNone(owner._lookup.pending_input)
        self.assertFalse(store._connection.in_transaction)

    def test_denied_original_publisher_stops_before_index_lookup(self):
        core, binding, store, owner = self.fixture(publisher_namespace='denied')
        with self.assertRaises(LocalCoreError):
            owner.prepare(binding=binding)
        self.assertEqual(self.counter(core, 'lookups'), 0)
        self.assertEqual(self.counter(core, 'responses'), 0)
        self.assertIsNone(owner._lookup.pending_input)
        self.assertFalse(store._connection.in_transaction)

    def test_refused_output_cleanup_keeps_original_output_and_disallows_replay(self):
        core, binding, _, owner = self.fixture()
        core._exports['refuse_cleanup'].set_value(core._store, 1)
        with self.assertRaises((RuntimeError, ValueError)):
            owner.prepare(binding=binding)
        output, = owner._projection.pending_outputs
        self.assertIs(core._loans[output.ticket], output)
        self.assertIn(output.ticket, core._inputs)
        before = self.counter(core, 'bindings')
        with self.assertRaises(RuntimeError):
            owner.prepare(binding=binding)
        self.assertEqual(self.counter(core, 'bindings'), before)


if __name__ == '__main__':
    unittest.main()
