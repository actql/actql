"""Scalar/loan boundary only; no real Wasm, grant, delivery or Store ACK."""
from local_abi_declaration_fixture import assert_current_local_abi
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import (
    LocalCore, LocalCoreError, _Input, _Output, LOCAL_CORE_ABI,
    _PUBLICATION_COMMIT_EXPORT_SIGNATURES,
)
import test_local_commit_store_caller as original_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class SDKReadOriginalTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        source = _Input(core._identity, 3, 17, 127)
        output = _Output(core._identity, 4, 19, 1048576, 'publication_commit_export')
        core._loans = {3: source, 4: output}
        calls, status = [], [0]
        def call(family, name, *args):
            calls.append((family, name, args))
            return status[0]
        core._call = original_byte_fixture_port(call)
        return core, source, output, calls, status

    def test_closed_signature_and_exact_original_loans_are_forwarded(self):
        core, source, output, calls, _ = self.bridge()
        assert_current_local_abi(self, LOCAL_CORE_ABI)
        self.assertEqual(_PUBLICATION_COMMIT_EXPORT_SIGNATURES['produce_sdk_read_original'],
                         ('i64 i32 i32 i32 i32 i32 i32', 'i32'))
        for ordinal in range(3):
            for field, code in (('wire', 0), ('identity', 1)):
                self.assertIsNone(core.produce_publication_sdk_read_original(
                    output, source, 29, 23, ordinal, field=field))
                self.assertEqual(calls[-1], ('publication_commit_export',
                    'produce_sdk_read_original', (19, 17, 29, 23, ordinal, code)))
        self.assertIs(core._loans[3], source)
        self.assertIs(core._loans[4], output)

    def test_copy_foreign_invalid_original_and_selector_refuse_before_abi(self):
        core, source, output, calls, _ = self.bridge()
        for candidate, request, run, current, ordinal, field in (
            (copy.copy(output), source, 29, 23, 0, 'wire'),
            (output, copy.copy(source), 29, 23, 0, 'wire'),
            (output, _Input(object(), 3, 17, 127), 29, 23, 0, 'wire'),
            (output, source, True, 23, 0, 'wire'),
            (output, source, 0, 23, 0, 'wire'),
            (output, source, 29, True, 0, 'wire'),
            (output, source, 29, 2**31, 0, 'wire'),
            (output, source, 29, 23, True, 'wire'),
            (output, source, 29, 23, 3, 'wire'),
            (output, source, 29, 23, -1, 'wire'),
            (output, source, 29, 23, 0, 'grant'),
        ):
            with self.assertRaises(ValueError):
                core.produce_publication_sdk_read_original(
                    candidate, request, run, current, ordinal, field=field)
        self.assertEqual(calls, [])

    def test_denial_unknown_expiry_capacity_and_cleanup_keep_original_loans(self):
        for code in (-35, -36, -32, -33, -42, -4, -9, -30):
            core, source, output, calls, status = self.bridge()
            status[0] = code
            with self.assertRaises(LocalCoreError) as error:
                core.produce_publication_sdk_read_original(
                    output, source, 29, 23, 2, field='wire')
            self.assertEqual(error.exception.code, code)
            self.assertIs(core._loans[3], source)
            self.assertIs(core._loans[4], output)
            self.assertEqual(len(calls), 1)

    def test_boolean_scalar_and_closing_never_become_original_evidence(self):
        core, source, output, _, status = self.bridge()
        del core._call
        core._closed = core._retired = core._invoking = False
        core._store = None
        core._nonce = 1
        core._exports = {'actql_publication_commit_export_produce_sdk_read_original':
                         lambda *_: status[0]}
        for value in (True, False, None, 0.0):
            status[0] = value
            with self.assertRaisesRegex(RuntimeError, 'Invalid Local Core scalar response'):
                core.produce_publication_sdk_read_original(
                    output, source, 29, 23, 0, field='wire')
        core._closing = True
        with self.assertRaisesRegex(RuntimeError, 'closing'):
            core.produce_publication_sdk_read_original(
                output, source, 29, 23, 0, field='wire')
        self.assertIs(core._loans[3], source)
        self.assertIs(core._loans[4], output)


class SDKReadOriginalProjectionTests(unittest.TestCase):
    def bridge(self):
        core, parent, _, projection, calls, state, _, _, _ = (
            original_fixture.OriginalCommitStoreCallerTests.bridge(self))
        request = _Input(core._identity, 5, 29, 127)
        core._loans[5] = request
        original_call = core._call
        outputs = {}
        identity, body = b'sha256:' + b'e' * 64, b'opaque-original-body\r\n'
        def call(family, name, *args):
            if family == 'publication_commit_export' and name == 'produce_sdk_read_original':
                calls.append((family, name, args))
                self.assertEqual(args[1:5], (29, 37, 31, 2))
                if state['produce']:
                    return state['produce']
                outputs[args[0]] = body if args[5] == 0 else identity
                return 0
            if family == 'publication_commit_export' and name == 'length' and args[0] in outputs:
                return len(outputs[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][args[1]]
            return original_call(family, name, *args)
        core._call = original_byte_fixture_port(call)
        return core, parent, request, projection, calls, state, identity, body

    def test_synchronous_pair_consumption_keeps_request_and_original_parent(self):
        core, parent, request, projection, calls, _, identity, body = self.bridge()
        consumed = []
        def consume(actual_identity, actual_body):
            self.assertEqual((actual_identity, actual_body), (identity, body))
            self.assertEqual(len(projection.pending_outputs), 2)
            self.assertIs(core._loans[5], request)
            consumed.append(True)
        projection.project_sdk_read_original(request, 37, 2, consume)
        self.assertEqual(consumed, [True])
        self.assertEqual(projection.pending_outputs, ())
        self.assertIs(core._loans[5], request)
        self.assertIs(core._loans[7], parent)
        self.assertFalse(any(f in ('run', 'source', 'task', 'model', 'effect', 'publication')
                             for f, _, _ in calls))

    def test_consumer_and_cleanup_failure_keep_exact_outputs_without_reprojection(self):
        core, _, request, projection, calls, state, _, _ = self.bridge()
        def refuse(*_):
            raise OSError('Physical original consumer failed')
        with self.assertRaisesRegex(OSError, 'consumer failed'):
            projection.project_sdk_read_original(request, 37, 2, refuse)
        outputs = projection.pending_outputs
        self.assertEqual(len(outputs), 2)
        before = [call for call in calls if call[1] in ('reserve', 'produce_sdk_read_original')]
        with self.assertRaises(RuntimeError):
            projection.project_sdk_read_original(request, 37, 2, lambda *_: None)
        self.assertEqual([call for call in calls
                          if call[1] in ('reserve', 'produce_sdk_read_original')], before)
        state['cleanup'] = False
        self.assertFalse(projection.retire_outputs())
        self.assertEqual(projection.pending_outputs, outputs)
        for output in outputs:
            self.assertIs(core._loans[output.ticket], output)
        self.assertIs(core._loans[5], request)
        state['cleanup'] = True
        self.assertTrue(projection.retire_outputs())
        self.assertEqual(projection.pending_outputs, ())
        self.assertIs(core._loans[5], request)


