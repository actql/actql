"""Real pinned interpreter service; no Native/worker/wheel funding supplied."""
import copy
import os
from pathlib import Path
import pickle
import subprocess
import sys
from threading import Thread
import unittest
from unittest.mock import patch

from actql_sdk._local_initial_preparation import (
    _OriginalPythonPreparation, _PythonPreparationPending, _allocator_snapshot,
    _capture_initial_preparation,
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

    def test_ambient_fsencode_substitution_cannot_change_original_bytes(self):
        original = _OriginalPythonPreparation()
        try:
            with patch('actql_sdk._local_initial_preparation.os.fsencode',
                    return_value=b'/foreign') as replacement:
                original.capture_state_dir('/selected')
                self.assertEqual(original._state_dir, '/selected')
                self.assertEqual(original._state_dir_bytes, b'/selected')
                replacement.assert_not_called()
        finally:
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

    def test_post_copy_failure_keeps_same_original_and_forbids_retry(self):
        original = _OriginalPythonPreparation()
        failure = MemoryError('Selected allocator refused')
        # Inject failure in the post-copy CAPI observation; do not replace
        # the selected immutable builtin codec or change the global allocator.
        with patch('actql_sdk._local_initial_preparation._interpreter',
                side_effect=(original._interpreter, failure)):
            with self.assertRaises(_PythonPreparationPending) as caught:
                original.capture_state_dir('/selected')
        self.assertIs(caught.exception.cleanup_preparation, original)
        self.assertIs(original._failure, failure)
        with self.assertRaises(_PythonPreparationPending): original.capture_state_dir('/replacement')
        self.assertEqual(original._state_dir, '/selected')
        self.assertEqual(original._state_dir_bytes, b'/selected')
        original.retire_input()

    def test_closed_codec_preserves_unicode_surrogateescape_and_byte_boundary(self):
        vectors = (('/café', b'/caf\xc3\xa9'),
            ('/café', b'/cafe\xcc\x81'),
            ('/\udc80\udcff', b'/\x80\xff'),
            ('/' + '\U0001f642' * 1023 + 'abc',
             b'/' + b'\xf0\x9f\x99\x82' * 1023 + b'abc'))
        for text, expected in vectors:
            with self.subTest(text=text):
                original = _OriginalPythonPreparation()
                original.capture_state_dir(text)
                self.assertEqual(original._state_dir, text)
                self.assertEqual(original._state_dir_bytes, expected)
                self.assertLessEqual(len(expected), 4096)
                original.retire_input()
        original = _OriginalPythonPreparation()
        with self.assertRaises(_PythonPreparationPending):
            original.capture_state_dir('/\ud800')
        self.assertIsInstance(original._failure, UnicodeEncodeError)
        self.assertEqual(original._state_dir, '/\ud800')
        with self.assertRaises(_PythonPreparationPending):
            original.capture_state_dir('/replacement')
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

    def test_factory_adopts_same_input_once_without_copy_or_new_baseline(self):
        selected = '/selected'
        original = _capture_initial_preparation(selected)
        with patch('actql_sdk._local_product.installed_local_components',
                   side_effect=AssertionError('No discovery')) as discovery:
            with self.assertRaises(LocalWorkerFundingUnavailable) as first:
                InstalledLocalHost.installed(state_dir=selected, _initial_preparation=original)
            self.assertIs(first.exception.cleanup_preparation, original)
            self.assertTrue(original._adopted)
            with self.assertRaises(LocalWorkerFundingUnavailable) as second:
                InstalledLocalHost.installed(state_dir=selected, _initial_preparation=original)
            self.assertIs(second.exception.cleanup_preparation, original)
            self.assertIsInstance(second.exception.__cause__, ValueError)
            discovery.assert_not_called()
        original.require_current()
        original.retire_input()

    def test_equal_foreign_input_cannot_replace_original_admission(self):
        selected = '/selected'
        original = _capture_initial_preparation(selected)
        foreign = selected.encode().decode()
        self.assertEqual(foreign, selected)
        self.assertIsNot(foreign, selected)
        with self.assertRaises(LocalWorkerFundingUnavailable) as refused:
            InstalledLocalHost.installed(state_dir=foreign, _initial_preparation=original)
        self.assertIs(refused.exception.cleanup_preparation, original)
        self.assertFalse(original._adopted)
        self.assertIs(original._state_dir, selected)
        original.retire_input()

    def test_actual_public_entry_prepares_before_local_import_and_retains_failure(self):
        source = str(Path(__file__).resolve().parents[1] / 'src')
        child = r'''import asyncio,builtins,json,sys
sys.path.insert(0,sys.argv[1])
from actql_sdk import AsyncClient,ClientError
for name in ['_local_product','_local_core','_local_distribution']:
 assert 'actql_sdk.'+name not in sys.modules,name
actual_import=builtins.__import__
seen=[]
failure=MemoryError('actual initial import boundary')
def observe(name,globals=None,locals=None,fromlist=(),level=0):
 if name=='_local_product' and level==1:
  original=sys._getframe(1).f_locals['initial']
  assert original._attempted and not original._adopted
  assert original._state_dir_bytes==b'/selected'
  assert len(original._allocators)==3
  original.require_current()
  seen.append(original)
  if sys.argv[2]=='failed': raise failure
 return actual_import(name,globals,locals,fromlist,level)
builtins.__import__=observe
async def run():
 try: await AsyncClient.open(state_dir='/selected')
 except ClientError as error:
  assert error.code=='LocalExecutionFundingUnavailable',error.code
  original=error.original_error.cleanup_preparation
  assert len(seen)==1 and original is seen[0]
  assert original._adopted==(sys.argv[2]=='ordinary')
  if sys.argv[2]=='failed':
   assert error.original_error.__cause__ is failure
   assert 'actql_sdk._local_product' not in sys.modules
   assert original._failure is failure
   from actql_sdk._local_initial_preparation import _PythonPreparationPending
   try: original.adopt_captured_state_dir('/selected')
   except _PythonPreparationPending as pending:
    assert pending.cleanup_preparation is original
   else: raise AssertionError('Failed import cannot resume normal preparation')
  else: original.require_current()
  alias=original._state_dir_bytes
  original.retire_input()
  assert alias==b'/selected'
 else: raise AssertionError('No actual worker supplier')
asyncio.run(run())
print(json.dumps({'mode':sys.argv[2],'same_initial_original':True,'ordinary_worker':False}))
'''
        for mode in ('ordinary', 'failed'):
            with self.subTest(mode=mode):
                result = subprocess.run([sys.executable, '-I', '-B', '-c', child, source, mode],
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
