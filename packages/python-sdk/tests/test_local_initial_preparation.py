"""Real pinned interpreter service; no Native/worker/wheel funding supplied."""
import copy
import os
from pathlib import Path
import pickle
from threading import Thread
import unittest
from unittest.mock import patch

from actql_sdk._local_initial_preparation import (
    _OriginalPythonPreparation, _PythonPreparationPending, _allocator_snapshot,
)
from actql_sdk._local_product import InstalledLocalHost
from actql_sdk._local_worker_funding import LocalWorkerFundingUnavailable


class InitialPreparationTests(unittest.TestCase):
    def test_actual_interpreter_allocator_domains_and_bounded_copy(self):
        before = _allocator_snapshot()
        original = _OriginalPythonPreparation()
        original.capture_state_dir('/selected/\U0001f642')
        self.assertEqual(original._state_dir_bytes, os.fsencode('/selected/\U0001f642'))
        self.assertEqual(original._allocators, before)
        self.assertEqual(len(before), 3)
        self.assertTrue(all(all(domain[1:]) for domain in before))
        original.require_current()
        original.retire_input()
        self.assertEqual(_allocator_snapshot(), before)
        with self.assertRaises(ValueError): original.require_current()

    def test_retained_original_text_alias_does_not_imply_pool_retirement(self):
        original = _OriginalPythonPreparation()
        original.capture_state_dir('/retained')
        alias = original._state_dir_bytes
        original.retire_input()
        self.assertEqual(alias, b'/retained')
        self.assertIsNone(original._state_dir_bytes)
        with self.assertRaises(ValueError): original.capture_state_dir('/again')

    def test_foreign_copied_and_serialized_carriers_refuse(self):
        original = _OriginalPythonPreparation()
        for operation in (copy.copy, copy.deepcopy, pickle.dumps):
            with self.assertRaises(TypeError): operation(original)
        clone = object.__new__(_OriginalPythonPreparation)
        for name in original.__slots__: setattr(clone, name, getattr(original, name))
        with self.assertRaises(ValueError): clone.require_current()
        with self.assertRaises(ValueError): clone.retire_input()
        original.require_current()
        original.retire_input()

    def test_foreign_thread_refuses_without_changing_original(self):
        original = _OriginalPythonPreparation()
        failures = []
        def foreign():
            for call in (original.require_current, original.retire_input):
                try: call()
                except ValueError: failures.append(True)
        thread = Thread(target=foreign)
        thread.start(); thread.join()
        self.assertEqual(failures, [True, True])
        original.require_current()
        original.retire_input()

    def test_changed_interpreter_or_allocator_refuses_before_copy(self):
        original = _OriginalPythonPreparation()
        for target, replacement in (('_interpreter', original._interpreter + 1),
                ('_allocator_snapshot', ())):
            with patch('actql_sdk._local_initial_preparation.' + target, return_value=replacement), \
                    patch('actql_sdk._local_initial_preparation.os.fsencode') as encode:
                with self.assertRaises(ValueError): original.capture_state_dir('/selected')
                encode.assert_not_called()
        self.assertFalse(original._attempted)
        original.retire_input()

    def test_changed_filesystem_codec_refuses_before_encoding(self):
        original = _OriginalPythonPreparation()
        with patch('actql_sdk._local_initial_preparation.sys.getfilesystemencoding',
                return_value='foreign-codec'), \
                patch('actql_sdk._local_initial_preparation.os.fsencode') as encode:
            with self.assertRaises(ValueError): original.capture_state_dir('/selected')
            with self.assertRaises(RuntimeError): _OriginalPythonPreparation()
            encode.assert_not_called()
        self.assertFalse(original._attempted)
        original.retire_input()

    def test_input_bounds_and_callback_refusal_precede_copy(self):
        class CallbackPath:
            def __fspath__(self): raise AssertionError('Callback must not run')
        original = _OriginalPythonPreparation()
        with patch('actql_sdk._local_initial_preparation.os.fsencode') as encode:
            for value in ('/' + 'x' * 4096, CallbackPath(), Path('/selected'), '', '/bad\x00'):
                with self.assertRaises(ValueError): original.capture_state_dir(value)
            encode.assert_not_called()
        self.assertFalse(original._attempted)
        original.retire_input()

    def test_copy_failure_keeps_same_original_and_forbids_retry(self):
        original = _OriginalPythonPreparation()
        failure = MemoryError('Selected allocator refused')
        with patch('actql_sdk._local_initial_preparation.os.fsencode', side_effect=failure):
            with self.assertRaises(_PythonPreparationPending) as caught:
                original.capture_state_dir('/selected')
        self.assertIs(caught.exception.cleanup_preparation, original)
        self.assertIs(original._failure, failure)
        with self.assertRaises(_PythonPreparationPending): original.capture_state_dir('/replacement')
        self.assertEqual(original._state_dir, '/selected')
        original.retire_input()

    def test_encoding_limit_retains_original_failure(self):
        original = _OriginalPythonPreparation()
        with self.assertRaises(_PythonPreparationPending) as caught:
            original.capture_state_dir('/' + '\U0001f642' * 1024)
        self.assertIs(caught.exception.cleanup_preparation, original)
        self.assertIsInstance(original._failure, ValueError)
        original.retire_input()

    def test_ordinary_factory_keeps_actual_initial_carrier_without_discovery(self):
        with patch('actql_sdk._local_product.installed_local_components',
                side_effect=AssertionError('No discovery before actual worker funding')) as discovery:
            with self.assertRaises(LocalWorkerFundingUnavailable) as caught:
                InstalledLocalHost.installed(state_dir='/selected')
        original = caught.exception.cleanup_preparation
        self.assertIs(type(original), _OriginalPythonPreparation)
        self.assertEqual(original._state_dir_bytes, b'/selected')
        original.require_current()
        discovery.assert_not_called()
        original.retire_input()
