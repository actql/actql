"""Same-instance/Store/holding doubles only; actual Engine and VM execution = 0."""
from copy import copy, deepcopy
from ctypes import c_void_p
import pickle
from threading import Thread
from unittest.mock import patch
import unittest

from actql_sdk._local_native_holding import NativeHoldingRetirementError, NativeHoldingScopeError
from actql_sdk._local_native_vm import _OriginalVMObservation
import test_local_installed_image as fixture


class NativeVMObservationTests(unittest.TestCase):
    def setUp(self):
        self.case = fixture.InstalledImageTests(); self.case.setUp()
        self.holding, self.library = self.case._holding([(0, True)])
        self.core, self.calls = self.case._construct_with_baseline(holding=self.holding)
        self.observation = self.core._physical_vm_observation

    def caller(self, *, context=345, address=234):
        class Memory(self.case.wasmtime.Memory):
            def data_ptr(self, store): return c_void_p(address)
        class Caller(self.case.wasmtime.Caller):
            def _context(self): return c_void_p(context)
            def get(self, name): return Memory() if name == 'memory' else None
        return Caller()

    def test_original_caller_wraps_same_memory_and_keeps_original_transfer(self):
        observer = self.observation
        self.assertIs(observer._core, self.core)
        self.assertIs(observer._holding, self.holding)
        self.assertIs(observer._library, self.library)
        observer._require_caller(self.caller(), self.core._nonce)
        self.assertEqual(self.library.span_calls[-1], (123, 234, 16777216))
        self.assertEqual([name for name, _ in self.calls], ['open'])
        with self.assertRaises(ValueError):
            _OriginalVMObservation._capture(self.core, self.case.wasmtime)

    def test_nonce_is_not_permission_for_foreign_store_or_instance(self):
        for caller in (self.caller(context=346), self.caller(address=235), object()):
            with self.subTest(caller=caller), self.assertRaises(ValueError):
                self.observation._require_caller(caller, self.core._nonce)
        for nonce in (True, 0, self.core._nonce + 1):
            with self.subTest(nonce=nonce), self.assertRaises(ValueError):
                self.observation._require_caller(self.caller(), nonce)
        self.assertEqual([name for name, _ in self.calls], ['open'])

    def test_same_store_with_missing_or_foreign_memory_is_rejected(self):
        for memory in (None, object()):
            caller = self.caller()
            caller.get = lambda name: memory
            with self.subTest(memory=memory), self.assertRaises(ValueError):
                self.observation._require_caller(caller, self.core._nonce)

    def test_invalidated_caller_cannot_reuse_original_nonce(self):
        caller = self.caller()
        caller._context = lambda: (_ for _ in ()).throw(ValueError('caller is no longer valid'))
        with self.assertRaisesRegex(ValueError, 'no longer valid'):
            self.observation._require_caller(caller, self.core._nonce)

    def test_generation_recipe_library_and_identity_are_not_replaceable(self):
        changes = [(self.holding, '_generation', 8), (self.holding, '_recipe', b's' * 32),
                   (self.holding, '_library', object()), (self.holding, '_core_identity', object()),
                   (self.core, '_identity', object()), (self.core, '_store', object()),
                   (self.core, '_exports', dict(self.core._exports)),
                   (self.core, '_physical_vm_span', (235, 16777216)),
                   (self.core, '_physical_holding', object())]
        for owner, name, changed in changes:
            original = getattr(owner, name)
            with self.subTest(name=name):
                setattr(owner, name, changed)
                try:
                    with self.assertRaises(ValueError): self.observation._require_core_current()
                finally: setattr(owner, name, original)

    def test_store_context_and_memory_pointer_are_checked_again(self):
        self.core._store._context = lambda: c_void_p(346)
        with self.assertRaises(ValueError): self.observation._require_core_current()
        self.core._store._context = lambda: c_void_p(345)
        self.core._exports['memory'].data_ptr = lambda store: c_void_p(235)
        with self.assertRaises(ValueError): self.observation._require_core_current()

    def test_callback_postcheck_preserves_same_holding_on_change(self):
        caller = self.caller()
        original_get = caller.get
        def get(name):
            self.holding._generation += 1
            return original_get(name)
        caller.get = get
        with self.assertRaises(ValueError):
            self.observation._require_caller(caller, self.core._nonce)
        self.assertIs(self.core._physical_holding, self.holding)

    def test_closing_lifecycle_remains_observable_but_retirement_does_not(self):
        self.core._closing = True
        self.observation._require_caller(self.caller(), self.core._nonce)
        self.core._retired = True
        before = len(self.library.span_calls)
        with self.assertRaises(ValueError): self.observation._require_core_current()
        self.assertEqual(len(self.library.span_calls), before)

    def test_unknown_physical_holding_is_not_current_success(self):
        unknown = NativeHoldingRetirementError(None)
        self.holding._close_failure = unknown
        with self.assertRaises(NativeHoldingRetirementError) as failure:
            self.observation._require_core_current()
        self.assertIs(failure.exception, unknown)
        self.assertIs(self.core._physical_vm_observation, self.observation)

    def test_pid_copy_and_serialization_do_not_create_an_original(self):
        for operation in (copy, deepcopy, pickle.dumps):
            with self.subTest(operation=operation), self.assertRaises(TypeError):
                operation(self.observation)
        clone = _OriginalVMObservation.__new__(_OriginalVMObservation)
        clone.__dict__.update(self.observation.__dict__)
        with self.assertRaises(ValueError): clone._require_core_current()
        with patch('actql_sdk._local_native_vm.getpid', return_value=-1):
            with self.assertRaises(ValueError): self.observation._require_core_current()

    def test_serialized_original_work_thread_uses_same_store_and_provider(self):
        outcomes = []
        def invoke():
            try:
                with self.core._lock:
                    self.observation._require_caller(self.caller(), self.core._nonce)
                    self.core._call('buffer', 'open')
                outcomes.append(None)
            except BaseException as error:
                outcomes.append(error)
        work = Thread(target=invoke)
        work.start(); work.join(timeout=5)
        self.assertFalse(work.is_alive())
        self.assertEqual(outcomes, [None])
        self.assertIs(self.core._physical_holding, self.holding)
        self.assertEqual([name for name, _ in self.calls], ['open', 'open'])

    def test_original_provider_scope_still_rejects_disallowed_work(self):
        self.library.scope.enter_replies = [-3]
        with self.assertRaises(NativeHoldingScopeError): self.core._call('buffer', 'open')
        self.assertEqual([name for name, _ in self.calls], ['open'])
        self.assertIs(self.core._physical_holding, self.holding)

    def test_original_core_calls_recheck_before_guest_execution(self):
        self.holding._generation += 1
        with self.assertRaises(ValueError): self.core._call('buffer', 'open')
        self.assertEqual([name for name, _ in self.calls], ['open'])
        self.assertTrue(self.core._closing)
        self.assertIs(self.core._physical_vm_observation, self.observation)

    def test_membership_scope_leave_failure_does_not_execute_guest(self):
        self.library.scope.leave_replies = [-1]
        with self.assertRaises(NativeHoldingScopeError): self.core._call('buffer', 'close_pool')
        self.assertEqual([name for name, _ in self.calls], ['open'])
        self.assertTrue(self.core._closing)
        self.assertIs(self.core._physical_holding, self.holding)
        self.assertIs(self.core._physical_vm_observation, self.observation)
        self.assertFalse(any(event[0] == 'retire' for event in self.case.events))

    def test_store_failure_retains_observation_and_original_cleanup(self):
        self.core._store.failures = 1
        with self.assertRaises(OSError): self.core.close()
        self.assertIs(self.core._physical_vm_observation, self.observation)
        self.assertIs(self.observation._store, self.core._store)
        self.assertFalse(any(event[0] == 'retire' for event in self.case.events))
        with self.assertRaises(ValueError): self.observation._require_core_current()
        self.assertTrue(self.core.close())
        self.assertIsNone(self.observation._core)
        self.assertIsNone(self.core._physical_vm_observation)

    def test_holding_failure_keeps_original_after_store_retirement(self):
        self.library.actql_owned_try_close.replies = [(-2, False), (0, True)]
        with self.assertRaises(NativeHoldingRetirementError): self.core.close()
        self.assertIsNone(self.core._store)
        self.assertIs(self.core._physical_vm_observation, self.observation)
        with self.assertRaises(ValueError): self.observation._require_core_current()
        with self.assertRaises(ValueError): self.observation._retire_metadata(self.core)
        self.assertTrue(self.core.close()); self.assertTrue(self.core.close())
        self.assertIsNone(self.observation._core)
        self.assertEqual([event for event in self.case.events if event == ('close', 'store')],
                         [('close', 'store')])

    def test_successful_close_breaks_metadata_without_issuing_physical_ack(self):
        with self.assertRaises(ValueError): self.observation._retire_metadata(self.core)
        self.assertTrue(self.core.close())
        self.assertIsNone(self.observation._core)
        with self.assertRaises(ValueError): self.observation._require_core_current()
        self.assertEqual([event for event in self.case.events if event[0] == 'retire'], [('retire', 123)])


if __name__ == '__main__':
    unittest.main()
