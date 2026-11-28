"""ABI and original buffer custody only; physical Wasm/usage ACK absent."""
from local_abi_declaration_fixture import assert_current_local_abi
import copy
from dataclasses import replace
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
        assert_current_local_abi(self, LOCAL_CORE_ABI)
        signatures = _PUBLICATION_COMMIT_EXPORT_SIGNATURES
        for name in ('measure_sdk_read_delivery_storage', 'validate_sdk_read_delivery_storage'):
            self.assertEqual(signatures[name], ('i64 i32 i32 i32 i32', 'i32'))
        self.assertEqual(signatures['emit_sdk_read_delivery_storage'], ('i64 i32 i32 i32', 'i32'))
        core, request, body, calls, status = original_fixture.SDKReadOriginalTests.bridge(self)
        first = replace(body, ticket=8, handle=39, limit=1)
        core._loans[first.ticket] = first
        for candidate, submitted, run, current in (
                (copy.copy(first), request, 29, 23),
                (first, copy.copy(request), 29, 23),
                (first, request, True, 23), (first, request, 29, True)):
            with self.assertRaises(ValueError):
                core.measure_publication_sdk_read_delivery_storage(candidate, submitted, run, current)
        with self.assertRaises(ValueError):
            core.emit_publication_sdk_read_delivery_storage(copy.copy(body), first, 23)
        self.assertFalse(calls)
        status[0] = 917
        self.assertEqual(core.measure_publication_sdk_read_delivery_storage(first, request, 29, 23), 917)
        status[0] = 0
        core.emit_publication_sdk_read_delivery_storage(body, first, 23)
        core.validate_publication_sdk_read_delivery_storage(first, request, 29, 23)
        self.assertEqual(calls, [
            ('publication_commit_export', 'measure_sdk_read_delivery_storage', (39, 17, 29, 23)),
            ('publication_commit_export', 'emit_sdk_read_delivery_storage', (19, 39, 23)),
            ('publication_commit_export', 'validate_sdk_read_delivery_storage', (39, 17, 29, 23)),
        ])
        for code in (-41, -33, -35, -37, -32, -4, -9):
            status[0] = code
            with self.assertRaises(LocalCoreError) as error:
                core.measure_publication_sdk_read_delivery_storage(first, request, 29, 23)
            self.assertEqual(error.exception.code, code)
            self.assertIs(core._loans[request.ticket], request)
            self.assertIs(core._loans[first.ticket], first)

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
        projection.project_sdk_read_delivery_storage(request, 37, consume, require_frame=lambda: None)
        self.assertEqual(consumed, [True])
        self.assertFalse(projection.pending_outputs)
        state['cleanup'] = False
        with self.assertRaises(LocalCoreError):
            projection.project_sdk_read_delivery_storage(request, 37, consume, require_frame=lambda: None)
        self.assertEqual(len(projection.pending_outputs), 2)
        self.assertIs(core._loans[parent.ticket], parent)
        self.assertIs(core._loans[request.ticket], request)
        state['cleanup'] = True
        self.assertTrue(projection.retire_outputs())

    def test_consumer_exception_retains_same_output_and_request(self):
        fixture = store_fixture.SDKReadStoreProjectionTests()
        core, _, request, projection, _, _, _, _ = fixture.bridge('delivery_storage')
        with self.assertRaisesRegex(RuntimeError, 'Original consumer failure'):
            projection.project_sdk_read_delivery_storage(request, 37,
                lambda _: (_ for _ in ()).throw(RuntimeError('Original consumer failure')),
                require_frame=lambda: None)
        self.assertEqual(len(projection.pending_outputs), 1)
        self.assertIs(core._loans[request.ticket], request)
        self.assertTrue(projection.retire_outputs())

    def test_interrupted_live_delivery_only_closes_original_loans_after_unwind(self):
        fixture = store_fixture.SDKReadStoreProjectionTests()
        core, publication, request, projection, _, state, _, _ = fixture.bridge('delivery_storage')
        previous = core._call
        retirement = []
        primary = RuntimeError('Original transport invocation trapped')

        def call(family, name, *args):
            if name == 'emit_sdk_read_delivery_storage':
                core._closing = True
                raise primary
            if name == 'begin_sdk_delivery_preparation_cleanup':
                self.assertEqual(family, 'publication_commit_export')
                self.assertEqual(args, (publication.handle, first.handle))
                retirement.append(('begin', first))
                return 0
            if name == 'close':
                original = next(output for output in (first, body) if output.handle == args[0])
                retirement.append(('close', original))
            return previous(family, name, *args)

        core._call = call
        with self.assertRaises(RuntimeError) as issue:
            projection.project_sdk_read_delivery_storage(
                request, 37, lambda _: self.fail('An interrupted body cannot stage'),
                require_frame=lambda: None)
        self.assertIs(issue.exception, primary)
        first, body = projection.pending_outputs
        core._host_fuel_phase = 'cleanup'
        core._invoking = True
        with self.assertRaisesRegex(RuntimeError, 'still executing'):
            projection.close()
        self.assertEqual(retirement, [])
        core._invoking = False
        state['cleanup'] = False
        self.assertFalse(projection.close())
        self.assertEqual(retirement, [('begin', first), ('close', body)])
        self.assertEqual(projection.pending_outputs, (first, body))
        state['cleanup'] = True
        self.assertTrue(projection.close())
        self.assertEqual(retirement[2:], [('begin', first), ('close', body), ('close', first)])
        self.assertIs(core._loans[publication.ticket], publication)
        self.assertIs(core._loans[request.ticket], request)
