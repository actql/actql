"""Original physical transfer/cleanup doubles, not native acquisition or Run admission."""
from ctypes import c_void_p
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreInitializationError
from actql_sdk._local_native_holding import _NativeHoldingLease, NativeHoldingTransferError
import test_local_installed_image as fixture


class NativeTransferTests(unittest.TestCase):
    def setUp(self):
        self.case = fixture.InstalledImageTests(); self.case.setUp()
        self.holding, self.library = self.case._holding([(0, True)])

    def test_native_transfer_uses_original_acquire_context_once_before_engine(self):
        original_config = self.case.wasmtime.Config
        def config():
            self.assertEqual(self.library.actql_owned_transfer.calls, [(123, 7, b'r' * 32)])
            return original_config()
        self.case.wasmtime.Config = config
        core, _ = self.case._construct_with_baseline(holding=self.holding)
        self.assertTrue(core.close()); self.assertTrue(core.close())
        self.assertEqual(self.library.actql_owned_transfer.calls, [(123, 7, b'r' * 32)])

    def test_denied_transfer_never_imports_or_initializes_engine(self):
        self.library.actql_owned_transfer.reply = -1
        with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Engine import')):
            with self.assertRaises(NativeHoldingTransferError) as failure:
                self.case.create(_physical_holding=self.holding)
        self.assertEqual(failure.exception.code, -1)
        self.assertEqual(self.case.events, [('retire', 123)])
        self.assertIsNone(self.holding._pointer.value)

    def test_unknown_transfer_retains_same_cleanup_core_and_never_replays_transfer(self):
        original = OSError('Original physical transfer outcome unknown')
        self.library.actql_owned_transfer.reply = original
        self.library.actql_owned_try_close.replies = [(-2, False), (0, True)]
        with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Engine import')):
            with self.assertRaises(LocalCoreInitializationError) as failure:
                self.case.create(_physical_holding=self.holding)
        core = failure.exception.cleanup_core
        self.assertIs(failure.exception.__cause__, original)
        self.assertIs(core._physical_holding, self.holding)
        self.assertIs(self.holding._core_identity, core._identity)
        self.assertFalse(core._closed)
        self.assertTrue(core._retired)
        with self.assertRaisesRegex(ValueError, 'unavailable'):
            self.holding._transfer_to_core(core._identity)
        self.assertTrue(core.close()); self.assertTrue(core.close())
        self.assertEqual(self.library.actql_owned_transfer.calls, [(123, 7, b'r' * 32)])
        self.assertEqual(self.case.events, [('retire', 123), ('retire', 123)])

    def test_wrong_native_generation_or_recipe_is_not_overridden_by_nominal_type(self):
        for kind in ('generation', 'recipe'):
            with self.subTest(kind=kind):
                self.setUp()
                calls = []
                def transfer(pointer, generation, recipe):
                    calls.append((pointer.value, generation, bytes(recipe)))
                    # These are independent original native acquire facts.
                    return 0 if generation == 7 and bytes(recipe) == b'r' * 32 else -1
                self.library.actql_owned_transfer = transfer
                if kind == 'generation': self.holding._generation = 8
                else: self.holding._recipe = b's' * 32
                with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Engine import')):
                    with self.assertRaises(NativeHoldingTransferError):
                        self.case.create(_physical_holding=self.holding)
                self.assertEqual(len(calls), 1)
                self.assertIsNone(self.holding._pointer.value)

    def test_invalid_context_refuses_before_library_access_or_pointer_consumption(self):
        for generation, recipe in ((True, b'r' * 32), (0, b'r' * 32),
                (2**64, b'r' * 32), (7, b'r' * 31), (7, bytearray(b'r' * 32))):
            with self.subTest(generation=generation, recipe=recipe):
                slot = c_void_p(123)
                with self.assertRaisesRegex(ValueError, 'acquisition context'):
                    _NativeHoldingLease(slot, SimpleNamespace(), generation=generation, recipe=recipe)
                self.assertEqual(slot.value, 123)

    def test_foreign_core_identity_cannot_invoke_native_transfer_or_retire_original(self):
        core, _ = self.case._construct_with_baseline(holding=self.holding)
        with self.assertRaises(ValueError): self.holding._transfer_to_core(object())
        with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Second Engine')):
            with self.assertRaisesRegex(ValueError, 'already transferred'):
                self.case.create(_physical_holding=self.holding)
        self.assertIs(self.holding._core_identity, core._identity)
        self.assertEqual(self.case.events[-1][0], 'limits')
        self.assertEqual(len(self.library.actql_owned_transfer.calls), 1)
        self.assertTrue(core.close())

    def test_malformed_native_transfer_status_never_becomes_confirmed_transfer(self):
        for reply in (True, None, '0'):
            with self.subTest(reply=reply):
                self.setUp()
                self.library.actql_owned_transfer.reply = reply
                with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Engine import')):
                    with self.assertRaises(NativeHoldingTransferError) as failure:
                        self.case.create(_physical_holding=self.holding)
                self.assertIsNone(failure.exception.code)
                self.assertEqual(len(self.library.actql_owned_transfer.calls), 1)
