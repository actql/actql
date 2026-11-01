"""Read evidence/grant scalar and original output custody; actual Wasm is absent."""
import copy
import unittest

from actql_sdk._local_core import LocalCoreError, _Input, _PUBLICATION_COMMIT_EXPORT_SIGNATURES
from actql_sdk._local_storage import ByteWrite, LocalByteStore
import test_local_sdk_read_original as original_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class SDKReadStoreScalarTests(unittest.TestCase):
    def test_closed_signatures_forward_only_original_handles(self):
        core, request, output, calls, _ = original_fixture.SDKReadOriginalTests.bridge(self)
        for operation in ('evidence', 'grant'):
            name = 'produce_sdk_read_' + operation
            self.assertEqual(_PUBLICATION_COMMIT_EXPORT_SIGNATURES[name],
                             ('i64 i32 i32 i32 i32 i32', 'i32'))
            producer = getattr(core, 'produce_publication_sdk_read_' + operation)
            for field, code in (('wire', 0), ('identity', 1)):
                producer(output, request, 29, 23, field=field)
                self.assertEqual(calls[-1], ('publication_commit_export', name,
                                             (19, 17, 29, 23, code)))
        self.assertEqual(_PUBLICATION_COMMIT_EXPORT_SIGNATURES['produce_sdk_read_evidence_decision'],
                         ('i64 i32 i32 i32 i32', 'i32'))
        core.produce_publication_sdk_read_evidence_decision(output, request, 29, 23)
        self.assertEqual(calls[-1], ('publication_commit_export', 'produce_sdk_read_evidence_decision',
                                     (19, 17, 29, 23)))
        self.assertIs(core._loans[3], request)
        self.assertIs(core._loans[4], output)

    def test_copy_bool_foreign_selector_and_invalid_run_refuse_before_io(self):
        core, request, output, calls, _ = original_fixture.SDKReadOriginalTests.bridge(self)
        for kind in ('evidence', 'grant', 'evidence_decision'):
            producer = getattr(core, 'produce_publication_sdk_read_' + kind)
            extra = {} if kind == 'evidence_decision' else {'field': 'wire'}
            for candidate, original, run, current in (
                (copy.copy(output), request, 29, 23),
                (output, copy.copy(request), 29, 23),
                (output, _Input(object(), 3, 17, 127), 29, 23),
                (output, request, True, 23), (output, request, 0, 23),
                (output, request, 29, True), (output, request, 29, 2**31),
            ):
                with self.assertRaises(ValueError):
                    producer(candidate, original, run, current, **extra)
            if extra:
                with self.assertRaises(ValueError):
                    producer(output, request, 29, 23, field='permission')
        self.assertEqual(calls, [])

    def test_missing_query_failure_denial_changed_and_cleanup_retain_loans(self):
        for kind in ('evidence', 'grant', 'evidence_decision'):
            for code in (-37, -30, -35, -32, -36, -42, -4, -9):
                core, request, output, calls, status = original_fixture.SDKReadOriginalTests.bridge(self)
                status[0] = code
                extra = {} if kind == 'evidence_decision' else {'field': 'wire'}
                with self.assertRaises(LocalCoreError) as issue:
                    getattr(core, 'produce_publication_sdk_read_' + kind)(
                        output, request, 29, 23, **extra)
                self.assertEqual(issue.exception.code, code)
                self.assertEqual(len(calls), 1)
                self.assertIs(core._loans[3], request)
                self.assertIs(core._loans[4], output)

    def test_boolean_response_and_closing_cannot_issue_a_grant(self):
        for kind in ('evidence', 'grant', 'evidence_decision'):
            core, request, output, _, status = original_fixture.SDKReadOriginalTests.bridge(self)
            del core._call
            core._closed = core._retired = core._invoking = False
            core._store, core._nonce = None, 1
            core._exports = {'actql_publication_commit_export_produce_sdk_read_' + kind:
                             lambda *_: status[0]}
            extra = {} if kind == 'evidence_decision' else {'field': 'wire'}
            producer = getattr(core, 'produce_publication_sdk_read_' + kind)
            for value in (True, False, None, 0.0):
                status[0] = value
                with self.assertRaisesRegex(RuntimeError, 'Invalid Local Core scalar response'):
                    producer(output, request, 29, 23, **extra)
            core._closing = True
            with self.assertRaisesRegex(RuntimeError, 'closing'):
                producer(output, request, 29, 23, **extra)
            self.assertIs(core._loans[3], request)


class SDKReadStoreProjectionTests(unittest.TestCase):
    def bridge(self, kind):
        core, parent, request, projection, calls, state, identity, body = (
            original_fixture.SDKReadOriginalProjectionTests.bridge(self))
        previous = core._call
        outputs = {}
        def call(family, name, *args):
            if family == 'publication_commit_export' and name == 'produce_sdk_read_' + kind:
                calls.append((family, name, args))
                self.assertEqual(args[1:4], (29, 37, 31))
                if state['produce']:
                    return state['produce']
                outputs[args[0]] = body if kind in ('evidence_decision', 'delivery_storage') or args[4] == 0 else identity
                return 0
            if family == 'publication_commit_export' and name == 'length' and args[0] in outputs:
                return len(outputs[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][args[1]]
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        return core, parent, request, projection, calls, state, identity, body

    def test_exact_key_bytes_and_pair_custody_are_consumed_before_retirement(self):
        for kind, table in (('evidence', 'client_local_read_evidence'), ('grant', 'publication_contract')):
            core, parent, request, projection, calls, _, identity, body = self.bridge(kind)
            consumed = []
            def consume(write):
                self.assertEqual(write, ByteWrite(LocalByteStore.namespaced_key(table, identity.decode()), None, body))
                self.assertEqual(len(projection.pending_outputs), 2)
                self.assertIs(core._loans[5], request)
                consumed.append(True)
            getattr(projection, 'project_sdk_read_' + kind)(request, 37, consume)
            self.assertEqual(consumed, [True])
            self.assertEqual(projection.pending_outputs, ())
            self.assertIs(core._loans[7], parent)
            self.assertFalse(any(family in ('run', 'source', 'task', 'effect') for family, _, _ in calls))

    def test_decision_is_opaque_and_retired_only_after_synchronous_consumption(self):
        core, parent, request, projection, calls, _, _, body = self.bridge('evidence_decision')
        consumed = []
        def consume(raw):
            self.assertEqual(raw, body)
            self.assertEqual(len(projection.pending_outputs), 1)
            consumed.append(True)
        projection.project_sdk_read_evidence_decision(request, 37, consume)
        self.assertEqual(consumed, [True])
        self.assertEqual(projection.pending_outputs, ())
        self.assertIs(core._loans[5], request)
        self.assertIs(core._loans[7], parent)
        self.assertEqual(sum(name == 'produce_sdk_read_evidence_decision' for _, name, _ in calls), 1)

    def test_failure_retains_original_outputs_and_cleanup_does_not_reproject(self):
        for kind in ('evidence', 'grant', 'evidence_decision'):
            core, parent, request, projection, calls, state, _, _ = self.bridge(kind)
            def refuse(_):
                raise OSError('Original physical consumer failed')
            with self.assertRaisesRegex(OSError, 'consumer failed'):
                getattr(projection, 'project_sdk_read_' + kind)(request, 37, refuse)
            pending = projection.pending_outputs
            self.assertEqual(len(pending), 1 if kind == 'evidence_decision' else 2)
            before = [call for call in calls if call[1] == 'reserve' or call[1].startswith('produce_sdk_read_')]
            with self.assertRaises(RuntimeError):
                getattr(projection, 'project_sdk_read_' + kind)(request, 37, lambda _: None)
            state['cleanup'] = False
            self.assertFalse(projection.retire_outputs())
            self.assertEqual(projection.pending_outputs, pending)
            self.assertTrue(all(core._loans[value.ticket] is value for value in pending))
            state['cleanup'] = True
            self.assertTrue(projection.retire_outputs())
            self.assertEqual([call for call in calls if call[1] == 'reserve' or call[1].startswith('produce_sdk_read_')], before)
            self.assertIs(core._loans[5], request)
            self.assertIs(core._loans[7], parent)


class SDKReadStoreReconciliationTests(unittest.TestCase):
    """Actual File/SQLite facts with stubbed Core, not Store ACK/grant acceptance."""
    def bridge(self, root, reader, store):
        import test_local_store_reconciliation as reconciliation_fixture
        helper = reconciliation_fixture.StoreReconciliationTests()
        core, record, projection, facts, transfers, caller, calls, state, _ = helper.bridge(root, reader, store)
        caller.prepare()
        request = _Input(core._identity, 99, 909, 127)
        core._loans[99] = request
        previous = core._call
        outputs = {}
        def call(family, name, *args):
            if family == 'publication_commit_export' and name.startswith('produce_sdk_read_'):
                calls.append((family, name, args))
                self.assertEqual(args[1:4], (909, 37, 31))
                if state['produce']:
                    return state['produce']
                outputs[args[0]] = (b'opaque-closed-decision' if name.endswith('decision') else
                                   b'sha256:' + b'e' * 64 if args[4] == 1 else b'opaque-grant-body')
                return 0
            if family == 'publication_commit_export' and name == 'length' and args[0] in outputs:
                return len(outputs[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][args[1]]
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        return core, record, projection, facts, transfers, caller, calls, state, request

    def test_original_facts_surround_every_read_projection_without_store_writes(self):
        from pathlib import Path
        from tempfile import TemporaryDirectory
        import test_local_reader_facts as physical_fixture
        helper = physical_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'store.sqlite') as store:
            reader = helper.transfer_ready(root, final)
            core, record, projection, facts, transfers, caller, calls, state, request = self.bridge(root, reader, store)
            before = store._connection.total_changes
            consumed = []
            for kind in ('evidence_decision', 'evidence', 'grant'):
                def consume(value):
                    self.assertTrue(projection.pending_outputs)
                    self.assertIs(core._loans[99], request)
                    consumed.append(value)
                getattr(caller, 'project_sdk_read_' + kind)(request, 37, consume)
            self.assertEqual(len(consumed), 3)
            self.assertEqual(store._connection.total_changes, before)
            self.assertFalse(store._connection.in_transaction)
            self.assertIs(core._loans[10], record)
            self.assertIs(root._readers[id(reader)], reader)
            self.assertFalse(any(name == 'finish_commit' for _, name, _ in calls))
            state['borrow'] = False
            self.assertTrue(all(transfer.close() for transfer in reversed(transfers)))
            self.assertTrue(facts.close())

    def test_file_change_in_consumer_refuses_return_and_preserves_exact_loans(self):
        import os
        from pathlib import Path
        from tempfile import TemporaryDirectory
        from actql_sdk._local_files import LocalFileError
        import test_local_reader_facts as physical_fixture
        helper = physical_fixture.ReaderFactsTests()
        with helper.file() as (path, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'store.sqlite') as store:
            reader = helper.transfer_ready(root, final)
            core, record, projection, facts, transfers, caller, calls, state, request = self.bridge(root, reader, store)
            original = facts.pending_input
            def consume(_):
                os.utime(path/'payload-original', ns=(1, 1))
            with self.assertRaises(LocalFileError):
                caller.project_sdk_read_grant(request, 37, consume)
            pending = projection.pending_outputs
            self.assertEqual(len(pending), 2)
            self.assertTrue(all(core._loans[value.ticket] is value for value in pending))
            self.assertIs(facts.pending_input, original)
            self.assertIs(core._loans[99], request)
            self.assertIs(core._loans[10], record)
            self.assertFalse(store._connection.in_transaction)
            state['cleanup'] = False
            self.assertFalse(projection.retire_outputs())
            state['cleanup'] = True
            self.assertTrue(projection.retire_outputs())
            state['borrow'] = False
            self.assertTrue(all(transfer.close() for transfer in reversed(transfers)))
