"""ABI and original buffer custody only; physical Wasm/usage ACK absent."""
import copy
import unittest

from actql_sdk._local_core import LOCAL_CORE_ABI, LocalCoreError, _PUBLICATION_COMMIT_EXPORT_SIGNATURES
import test_local_sdk_read_original as original_fixture
import test_local_sdk_read_store as store_fixture


class SDKDeliveryPortTests(unittest.TestCase):
    def test_transport_retirement_keeps_same_semantic_loan_and_rejects_copies(self):
        self.assertEqual(_PUBLICATION_COMMIT_EXPORT_SIGNATURES['retire_sdk_delivery_output'],
                         ('i64 i32', 'i32'))
        core, request, output, calls, status = original_fixture.SDKReadOriginalTests.bridge(self)
        with self.assertRaises(ValueError):
            core.retire_publication_sdk_delivery_output(copy.copy(output))
        self.assertEqual(calls, [])
        status[0] = -9
        self.assertFalse(core.retire_publication_sdk_delivery_output(output))
        self.assertIs(core._loans[output.ticket], output)
        self.assertIs(core._loans[request.ticket], request)
        status[0] = 0
        self.assertTrue(core.retire_publication_sdk_delivery_output(output))
        self.assertTrue(core.retire_publication_sdk_delivery_output(output))
        status[0] = 1
        with self.assertRaises(LocalCoreError) as failure:
            core.retire_publication_sdk_delivery_output(output)
        self.assertEqual(failure.exception.code, 1)
        status[0] = False
        with self.assertRaisesRegex(RuntimeError, 'retirement status'):
            core.retire_publication_sdk_delivery_output(output)
        self.assertIs(core._loans[output.ticket], output)
        self.assertTrue(all(name == 'retire_sdk_delivery_output' for _, name, _ in calls))

    def test_strict_original_signature_and_copy_bool_unknown_boundaries(self):
        self.assertEqual(LOCAL_CORE_ABI, 67)
        self.assertEqual(_PUBLICATION_COMMIT_EXPORT_SIGNATURES['produce_sdk_read_delivery_storage'],
                         ('i64 i32 i32 i32 i32', 'i32'))
        core, request, output, calls, status = original_fixture.SDKReadOriginalTests.bridge(self)
        for candidate, submitted, run, current in (
                (copy.copy(output), request, 29, 23),
                (output, copy.copy(request), 29, 23),
                (output, request, True, 23), (output, request, 29, True)):
            with self.assertRaises(ValueError):
                core.produce_publication_sdk_read_delivery_storage(candidate, submitted, run, current)
        self.assertFalse(calls)
        core.produce_publication_sdk_read_delivery_storage(output, request, 29, 23)
        self.assertEqual(calls, [('publication_commit_export', 'produce_sdk_read_delivery_storage',
                                  (19, 17, 29, 23))])
        for code in (-41, -33, -35, -37, -32, -4, -9):
            status[0] = code
            with self.assertRaises(LocalCoreError) as error:
                core.produce_publication_sdk_read_delivery_storage(output, request, 29, 23)
            self.assertEqual(error.exception.code, code)
            self.assertIs(core._loans[request.ticket], request)
            self.assertIs(core._loans[output.ticket], output)

    def test_original_packet_borrow_lives_through_consumer_and_cleanup_failure(self):
        fixture = store_fixture.SDKReadStoreProjectionTests()
        values = fixture.bridge('delivery_storage')
        core, parent, request, projection, calls, state, _, body = values
        consumed = []
        def consume(raw):
            self.assertEqual(raw, body)
            self.assertEqual(len(projection.pending_outputs), 1)
            self.assertIs(core._loans[request.ticket], request)
            consumed.append(True)
        projection.project_sdk_read_delivery_storage(request, 37, consume)
        self.assertEqual(consumed, [True])
        self.assertFalse(projection.pending_outputs)
        state['cleanup'] = False
        with self.assertRaises(LocalCoreError):
            projection.project_sdk_read_delivery_storage(request, 37, consume)
        self.assertEqual(len(projection.pending_outputs), 1)
        self.assertIs(core._loans[parent.ticket], parent)
        self.assertIs(core._loans[request.ticket], request)
        state['cleanup'] = True
        self.assertTrue(projection.retire_outputs())

    def test_consumer_exception_retains_same_output_and_request(self):
        fixture = store_fixture.SDKReadStoreProjectionTests()
        core, _, request, projection, _, _, _, _ = fixture.bridge('delivery_storage')
        with self.assertRaisesRegex(RuntimeError, 'Original consumer failure'):
            projection.project_sdk_read_delivery_storage(request, 37,
                lambda _: (_ for _ in ()).throw(RuntimeError('Original consumer failure')))
        self.assertEqual(len(projection.pending_outputs), 1)
        self.assertIs(core._loans[request.ticket], request)
        self.assertTrue(projection.retire_outputs())
