"""Strict delivery lookup ABI/borrow only; actual Wasm/Store observation absent."""
from local_abi_declaration_fixture import assert_current_local_abi
import copy
import unittest
from actql_sdk._local_core import LOCAL_CORE_ABI, LocalCoreError, _PUBLICATION_COMMIT_EXPORT_SIGNATURES
import test_local_sdk_read_original as original_fixture
import test_local_sdk_read_store as store_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class SDKDeliveryLookupPortTests(unittest.TestCase):
    def test_original_signature_copy_and_boolean_refusal_precede_abi(self):
        assert_current_local_abi(self, LOCAL_CORE_ABI)
        self.assertEqual(_PUBLICATION_COMMIT_EXPORT_SIGNATURES['produce_sdk_delivery_lookup'],
                         ('i64 i32 i32 i32 i32', 'i32'))
        core, request, output, calls, status = original_fixture.SDKReadOriginalTests.bridge(self)
        for borrowed, submitted, run, current in (
                (copy.copy(output), request, 29, 23), (output, copy.copy(request), 29, 23),
                (output, request, True, 23), (output, request, 29, True)):
            with self.assertRaises(ValueError): core.produce_publication_sdk_delivery_lookup(borrowed, submitted, run, current)
        self.assertFalse(calls)
        core.produce_publication_sdk_delivery_lookup(output, request, 29, 23)
        self.assertEqual(calls, [('publication_commit_export', 'produce_sdk_delivery_lookup', (19, 17, 29, 23))])
        for code in (-35, -41, -32, -4, -9):
            status[0] = code
            with self.assertRaises(LocalCoreError) as error: core.produce_publication_sdk_delivery_lookup(output, request, 29, 23)
            self.assertEqual(error.exception.code, code)
            self.assertIs(core._loans[request.ticket], request)
            self.assertIs(core._loans[output.ticket], output)


class SDKDeliveryLookupStoreTests(unittest.TestCase):
    """Real File/SQLite fences; opaque Core response, not Wasm acceptance."""

    def test_lookup_is_read_only_and_failed_consumption_preserves_cleanup_custody(self):
        from pathlib import Path
        from tempfile import TemporaryDirectory
        import test_local_reader_facts as physical_fixture
        helper = physical_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory) / 'store.sqlite') as store:
            reader = helper.transfer_ready(root, final)
            fixture = store_fixture.SDKReadStoreReconciliationTests()
            core, record, projection, facts, transfers, caller, calls, state, request = fixture.bridge(root, reader, store)
            previous = core._call
            outputs = {}
            expected = b'{"kind":"not_found"}'
            def call(family, name, *args):
                if family == 'publication_commit_export' and name == 'produce_sdk_delivery_lookup':
                    calls.append((family, name, args))
                    self.assertEqual(args[1:], (909, 37, 31))
                    outputs[args[0]] = expected
                    return 0
                if family == 'publication_commit_export' and name == 'length' and args[0] in outputs:
                    return len(outputs[args[0]])
                if family == 'buffer' and name == 'byte' and args[0] in outputs:
                    return outputs[args[0]][args[1]]
                return previous(family, name, *args)
            core._call = original_byte_fixture_port(call)
            before = store._connection.total_changes
            consumed = []
            def consume(raw):
                self.assertEqual(raw, expected)
                self.assertEqual(len(projection.pending_outputs), 1)
                self.assertIs(core._loans[99], request)
                consumed.append(raw)
            caller.project_sdk_delivery_lookup(request, 37, consume)
            self.assertEqual(consumed, [expected])
            self.assertEqual(projection.pending_outputs, ())
            self.assertEqual(store._connection.total_changes, before)
            def refuse(_):
                raise OSError('Original lookup consumer failed')
            with self.assertRaisesRegex(OSError, 'lookup consumer failed'):
                caller.project_sdk_delivery_lookup(request, 37, refuse)
            pending = projection.pending_outputs
            self.assertEqual(len(pending), 1)
            count = sum(name == 'produce_sdk_delivery_lookup' for _, name, _ in calls)
            with self.assertRaises(RuntimeError):
                caller.project_sdk_delivery_lookup(request, 37, consume)
            state['cleanup'] = False
            self.assertFalse(projection.retire_outputs())
            self.assertEqual(projection.pending_outputs, pending)
            self.assertIs(core._loans[pending[0].ticket], pending[0])
            state['cleanup'] = True
            self.assertTrue(projection.retire_outputs())
            self.assertEqual(sum(name == 'produce_sdk_delivery_lookup' for _, name, _ in calls), count)
            self.assertEqual(store._connection.total_changes, before)
            self.assertFalse(store._connection.in_transaction)
            self.assertIs(core._loans[10], record)
            self.assertIs(core._loans[99], request)
            self.assertFalse(any(name == 'finish_commit' for _, name, _ in calls))
            state['borrow'] = False
            self.assertTrue(all(transfer.close() for transfer in reversed(transfers)))
            self.assertTrue(facts.close())
