"""Maintainer source/physical-port faults; scalar doubles, no Engine or funding."""
from ctypes import cast, c_void_p, POINTER
import hashlib
import json
import os
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import test_local_image_compiler as image

compiler = image.compiler


class CompilerHoldingTests(unittest.TestCase):
    def setUp(self):
        self.fixture = image.ImageCompilerTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.case = self.fixture.case
        original = compiler.verify(self.case.module_file, self.case.head)
        recipe = original['recipe']
        self.body = {'scope': 'image_compiler_only',
            'module_sha256': original['module_sha256'],
            'engine_sha256': hashlib.sha256(recipe.engine_body).hexdigest(),
            'runtime_library_sha256': recipe.runtime_library_sha256,
            'provider_library_sha256': recipe.provider_library_sha256,
            'capacity_bytes': 64 * os.sysconf('SC_PAGE_SIZE'), 'generation': 7}
        self.path = self.case.source / 'packages/python-local-runtime/selected-compiler-holding.json'

    def original(self, body=None):
        self.path.write_text(json.dumps(self.body if body is None else body))
        self.case.commit()
        self.case.core['source_sha'] = self.case.head
        self.case.write_receipts()
        return compiler.verify(self.case.module_file, self.case.head)

    def provider(self, reply=0, pointer=123):
        def acquire(capacity, generation, recipe, slot):
            self.assertEqual(capacity, self.body['capacity_bytes'])
            self.assertEqual(generation, 7)
            self.assertEqual(bytes(recipe), hashlib.sha256(self.path.read_bytes()).digest())
            cast(slot, POINTER(c_void_p))[0] = pointer
            return reply
        def close(slot):
            cast(slot, POINTER(c_void_p))[0] = None
            return 0
        return SimpleNamespace(actql_native_owned_acquire=Mock(side_effect=acquire),
                               actql_native_owned_try_close=Mock(side_effect=close))

    def test_missing_original_refuses_before_provider_load_or_runtime_import(self):
        with patch.object(compiler, 'CDLL', side_effect=AssertionError('Provider load')), \
                patch.object(compiler, 'import_module', side_effect=AssertionError('Engine import')):
            with self.assertRaisesRegex(ValueError, 'compiler holding is unavailable'):
                compiler.compile_from_original(self.case.module_file, self.case.head,
                                                self.fixture.destination)

    def test_committed_original_binds_complete_compilation_and_exact_raw_fingerprint(self):
        original = self.original()
        selected = compiler._compiler_holding_original(original)
        self.assertEqual(selected.source_sha, self.case.head)
        self.assertEqual(selected.module_sha256, original['module_sha256'])
        self.assertEqual(selected.capacity_bytes, 64 * os.sysconf('SC_PAGE_SIZE'))
        self.assertEqual(selected.generation, 7)
        self.assertEqual(selected.recipe, hashlib.sha256(self.path.read_bytes()).digest())
        self.path.write_text(self.path.read_text() + '\n')
        with self.assertRaisesRegex(ValueError, 'committed original'):
            compiler._compiler_holding_original(original)

    def test_closed_original_refuses_foreign_context_bad_units_and_boolean_numbers(self):
        original = self.original()
        mutations = [{**self.body, key: value} for key, value in [
            ('scope', 'normal_product'), ('module_sha256', 'f' * 64),
            ('engine_sha256', 'f' * 64), ('runtime_library_sha256', 'f' * 64),
            ('provider_library_sha256', 'f' * 64), ('capacity_bytes', True),
            ('capacity_bytes', 0), ('capacity_bytes', 1), ('capacity_bytes', 2**63),
            ('capacity_bytes', None), ('generation', None),
            ('generation', False), ('generation', 0), ('generation', 2**64)]]
        mutations += [{**self.body, 'permission': True},
                      {k: v for k, v in self.body.items() if k != 'generation'}]
        for body in mutations:
            with self.subTest(body=body), patch.object(compiler.assembly.recipe,
                    '_source_original', return_value=json.dumps(body).encode()):
                with self.assertRaises((ValueError, image.LocalInstallationError)):
                    compiler._compiler_holding_original(original)

    def test_duplicate_original_fields_are_not_last_value_wins(self):
        original = self.original()
        raw = json.dumps(self.body).encode()
        duplicate = raw[:-1] + b', "generation": 7}'
        with patch.object(compiler.assembly.recipe, '_source_original', return_value=duplicate):
            with self.assertRaises(image.LocalInstallationError):
                compiler._compiler_holding_original(original)

    def test_other_compilation_cannot_consume_selected_original_before_provider_load(self):
        original = self.original()
        selected = compiler._compiler_holding_original(original)
        with patch.object(compiler, 'CDLL', side_effect=AssertionError('Provider load')):
            for field in ('source_sha', 'module_sha256', 'engine_sha256',
                          'runtime_library_sha256', 'provider_library_sha256'):
                with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'another selected compilation'):
                    compiler._acquire_compiler_holding(original, selected._replace(**{field: 'foreign'}))

    def test_copied_metadata_cannot_replace_original_capacity_generation_or_fingerprint(self):
        original = self.original()
        selected = compiler._compiler_holding_original(original)
        with patch.object(compiler, 'CDLL', side_effect=AssertionError('Provider load')):
            for field, value in [('capacity_bytes', selected.capacity_bytes * 2),
                                 ('generation', 8), ('recipe', b'\0' * 32)]:
                with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'another selected compilation'):
                    compiler._acquire_compiler_holding(original, selected._replace(**{field: value}))

    def test_confirmed_acquire_moves_same_slot_once_to_existing_holding_owner(self):
        original = self.original()
        selected = compiler._compiler_holding_original(original)
        provider = self.provider()
        with patch.object(compiler, 'CDLL', return_value=provider):
            holding = compiler._acquire_compiler_holding(original, selected)
        self.assertEqual(holding._pointer.value, 123)
        self.assertIs(holding._library, provider)
        self.assertIsNone(holding._core_identity)
        self.assertFalse(holding._transfer_attempted)
        holding.close(); holding.close()
        provider.actql_native_owned_acquire.assert_called_once()
        provider.actql_native_owned_try_close.assert_called_once()

    def test_known_empty_refusal_is_distinct_from_unknown_or_partial_reply(self):
        original = self.original()
        selected = compiler._compiler_holding_original(original)
        for code, pointer, refused in [(-2, None, True), (-2, 123, False),
                                       (0, None, False), (False, None, False)]:
            provider = self.provider(code, pointer)
            with self.subTest(code=code, pointer=pointer), patch.object(compiler, 'CDLL', return_value=provider):
                with self.assertRaises(compiler.CompilerHoldingAcquisitionError) as caught:
                    compiler._acquire_compiler_holding(original, selected)
            error = caught.exception
            self.assertIs(error.library, provider)
            self.assertEqual(error.slot.value, pointer)
            self.assertEqual(error.refused, refused)
            self.assertTrue(error.attempted)
            self.assertIsNone(error.holding)
            provider.actql_native_owned_acquire.assert_called_once()
            provider.actql_native_owned_try_close.assert_not_called()

    def test_acquire_reply_loss_retains_original_out_slot_without_reacquire_or_close(self):
        original = self.original()
        selected = compiler._compiler_holding_original(original)
        provider = self.provider()
        primary = OSError('Original acquire reply lost')
        def lost(*args):
            cast(args[-1], POINTER(c_void_p))[0] = 123
            raise primary
        provider.actql_native_owned_acquire.side_effect = lost
        with patch.object(compiler, 'CDLL', return_value=provider):
            with self.assertRaises(compiler.CompilerHoldingAcquisitionError) as caught:
                compiler._acquire_compiler_holding(original, selected)
        error = caught.exception
        self.assertIs(error.__cause__, primary)
        self.assertEqual(error.slot.value, 123)
        self.assertIs(error.library, provider)
        self.assertFalse(error.refused)
        provider.actql_native_owned_acquire.assert_called_once()
        provider.actql_native_owned_try_close.assert_not_called()

    def test_owner_initialization_failure_after_slot_move_retains_same_object(self):
        original = self.original()
        selected = compiler._compiler_holding_original(original)
        provider = self.provider()
        initialize = compiler._NativeHoldingLease._initialize_original
        primary = OSError('Python binding failure after original slot move')
        def lost(holding, *args):
            initialize(holding, *args)
            raise primary
        with patch.object(compiler, 'CDLL', return_value=provider), \
                patch.object(compiler._NativeHoldingLease, '_initialize_original', lost):
            with self.assertRaises(compiler.CompilerHoldingAcquisitionError) as caught:
                compiler._acquire_compiler_holding(original, selected)
        error = caught.exception
        self.assertEqual(error.code, 0)  # Native acquire ACK was confirmed.
        self.assertIs(error.__cause__, primary)
        self.assertIsNone(error.slot.value)
        self.assertEqual(error.holding._pointer.value, 123)
        provider.actql_native_owned_try_close.assert_not_called()
        # Test-only cleanup of this known scalar owner, not inferred from NULL.
        error.holding.close()
        provider.actql_native_owned_acquire.assert_called_once()
        provider.actql_native_owned_try_close.assert_called_once()

    def test_changed_loaded_provider_is_retained_without_attempting_acquire(self):
        original = self.original()
        selected = compiler._compiler_holding_original(original)
        provider = self.provider()
        with patch.object(compiler, 'CDLL', return_value=provider), \
                patch.object(compiler, '_read_file', side_effect=[b'', ValueError('Provider changed')]):
            with self.assertRaises(compiler.CompilerHoldingAcquisitionError) as caught:
                compiler._acquire_compiler_holding(original, selected)
        self.assertIs(caught.exception.library, provider)
        self.assertFalse(caught.exception.attempted)
        self.assertTrue(caught.exception.refused)
        provider.actql_native_owned_acquire.assert_not_called()

    def test_changed_second_preflight_closes_same_holding_before_reraising_primary(self):
        original = self.original()
        primary = ValueError('Second source fence changed')
        holding = SimpleNamespace(_capacity_bytes=lambda: self.body['capacity_bytes'], close=Mock())
        with patch.object(compiler, '_acquire_compiler_holding', return_value=holding), \
                patch.object(compiler, 'compile_image', side_effect=primary):
            with self.assertRaises(ValueError) as caught:
                compiler.compile_from_original(self.case.module_file, self.case.head,
                                                self.fixture.destination)
        self.assertIs(caught.exception, primary)
        holding.close.assert_called_once()

    def test_physical_capacity_mismatch_refuses_compile_and_retires_same_original(self):
        self.original()
        holding = SimpleNamespace(_capacity_bytes=lambda: self.body['capacity_bytes'] - 1, close=Mock())
        with patch.object(compiler, '_acquire_compiler_holding', return_value=holding), \
                patch.object(compiler, 'compile_image', side_effect=AssertionError('Compile')):
            with self.assertRaisesRegex(ValueError, 'Physical compiler holding'):
                compiler.compile_from_original(self.case.module_file, self.case.head,
                                                self.fixture.destination)
        holding.close.assert_called_once()

    def test_compiler_cleanup_unknown_keeps_same_carrier_without_another_close(self):
        self.original()
        holding = SimpleNamespace(_capacity_bytes=lambda: self.body['capacity_bytes'], close=Mock())
        cleanup = compiler.ImageCompilerCleanupError(compiler._CompilerCustody(holding), OSError('Primary'))
        with patch.object(compiler, '_acquire_compiler_holding', return_value=holding), \
                patch.object(compiler, 'compile_image', side_effect=cleanup):
            with self.assertRaises(compiler.ImageCompilerCleanupError) as caught:
                compiler.compile_from_original(self.case.module_file, self.case.head,
                                                self.fixture.destination)
        self.assertIs(caught.exception, cleanup)
        self.assertIs(cleanup.cleanup_compilation.holding, holding)
        holding.close.assert_not_called()
