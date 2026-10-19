"""Actual selected C entry through Python's original preparation carrier.

An explicitly retained diagnostic component is required. This is not an
installed distribution or a claim of complete before-load initial coverage.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]

CHILD = r'''
import copy,ctypes,json,sys,threading
sys.path.insert(0,sys.argv[1])
from actql_sdk._local_initial_preparation import _capture_initial_preparation
initial=_capture_initial_preparation('/selected')
# The same actual Python service precedes this diagnostic module load. The
# complete ordinary loader/prelude supplier is still not provided by this test.
library=ctypes.PyDLL(sys.argv[2])
from actql_sdk._local_native_initial_custody import (
    _OriginalPythonNativeInitial as Native,
    _PythonNativeInitialFunctions as Functions,
    _PythonNativeInitialPending as Pending)
functions=Functions(library)
mode=sys.argv[3]
real_begin,real_current,real_restore=functions.begin,functions.current,functions.restore
calls={'begin':0,'current':0,'restore':0}
def begin(slot):
    calls['begin']+=1
    result=real_begin(slot)
    if mode=='lost-reply':
        assert result==0
        raise RuntimeError('controlled reply loss after actual original publication')
    return result
def current(slot):
    calls['current']+=1
    return real_current(slot)
def restore(slot):
    calls['restore']+=1
    return real_restore(slot)
functions.begin,functions.current,functions.restore=begin,current,restore
try:
    original=Native.prepare(initial,functions)
except Pending as failure:
    assert mode=='lost-reply'
    original=failure.cleanup_native_initial
    assert original._slot.value and original._unknown
    assert isinstance(failure.__cause__,RuntimeError)
else:
    assert mode!='lost-reply'
assert original._initial is initial and initial._native_attempted
assert original._slot.value and bool(real_current(original._slot))
try:
    Native.prepare(initial,functions)
except ValueError:
    pass
else:
    raise AssertionError('same Python initial original was reissued')
assert calls['begin']==1
if mode=='ready':
    original.require_current()
    failures=[]
    def foreign():
        for call in (original.require_current,original.restore_default):
            try: call()
            except ValueError: failures.append(True)
            else: failures.append(False)
    thread=threading.Thread(target=foreign)
    thread.start();thread.join()
    assert failures==[True,True] and not original._unknown
    for call in (lambda:copy.copy(original),lambda:copy.deepcopy(original)):
        try:call()
        except TypeError:pass
        else:raise AssertionError('original copied')
    # Input DATA retirement is not retirement of the same interpreter service
    # or the actual Native original already retained by this caller.
    initial.retire_input()
    original.require_current()
elif mode=='duplicate':
    second_initial=_capture_initial_preparation('/second')
    try:Native.prepare(second_initial,functions)
    except Pending as failure:
        second=failure.cleanup_native_initial
        assert not second._slot.value
    else:raise AssertionError('second receiver acquired the first original')
    try:second.restore_default()
    except Pending:pass
    else:raise AssertionError('second receiver closed the first original')
    assert calls['begin']==2 and calls['restore']==0
    original.require_current()
elif mode=='lost-reply':
    try:original.require_current()
    except Pending:pass
    else:raise AssertionError('lost reply revived normal startup')
elif mode=='reentrant':
    def nested_current(slot):
        try:original.require_current()
        except Pending:pass
        else:raise AssertionError('nested current was admitted')
        return current(slot)
    functions.current=nested_current
    try:original.require_current()
    except Pending:pass
    else:raise AssertionError('outer current masked nested refusal')
    assert original._normal_refused and original._unknown
    functions.current=current
    def nested_restore(slot):
        try:original.restore_default()
        except Pending:pass
        else:raise AssertionError('nested restore was admitted')
        return restore(slot)
    functions.restore=nested_restore
    try:original.restore_default()
    except Pending:pass
    else:raise AssertionError('outer restore masked nested refusal')
    assert not original._restored and calls['restore']==1
    functions.restore=restore
else:raise AssertionError('unknown case')
original.restore_default()
assert original._restored and not bool(real_current(original._slot))
restores=calls['restore']
original.restore_default()
assert calls['restore']==restores
try:original.require_current()
except Pending:pass
else:raise AssertionError('restored default revived normal startup')
assert original._functions.library is library and original._initial is initial
print(json.dumps({'case':mode,'calls':calls,'default_restored':True,
 'mapping_module_process_retirement_ack':False,'same_python_original':True}))
'''


class NativeInitialCustodyTests(unittest.TestCase):
    def test_actual_same_python_original_and_native_custody(self):
        library = Path(os.environ['ACTQL_TEST_PYTHON_INITIAL_COMPONENT'])
        expected = os.environ['ACTQL_TEST_PYTHON_INITIAL_COMPONENT_SHA256']
        raw = library.read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), expected)
        records = []
        for mode in ('ready', 'duplicate', 'lost-reply', 'reentrant'):
            result = subprocess.run([sys.executable, '-I', '-B', '-c', CHILD,
                                     str(ROOT / 'packages/python-sdk/src'), str(library), mode],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, (mode, result.stdout, result.stderr))
            records.append(json.loads(result.stdout))
        self.assertEqual(library.read_bytes(), raw)
        print(json.dumps({'actual_python_native_cases': records,
                          'component_sha256': expected,
                          'qualification': 'Retained diagnostic module; actual original C entry, '
                          'no product Moon, pre-load supplier, Worker/VM or installed wheel'}))

    def test_selected_generated_abi_and_default_signature_tables(self):
        spec = importlib.util.spec_from_file_location(
            'initial_generator', ROOT / 'scripts/generate-local-native-shim-bindings.py')
        generator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(generator)
        self.assertEqual((ROOT / generator.INITIAL_OUTPUT).read_text(),
                         generator.render(python_initial=True))
        self.assertEqual((ROOT / generator.INITIAL_HEADER).read_text(),
                         generator.render_header(python_initial=True))
        declarations = generator.declarations(python_initial=True)
        self.assertEqual(set(declarations), {
            'actql_native_python_initial_platform_begin_into',
            'actql_native_python_initial_platform_current',
            'actql_native_python_initial_platform_restore'})
        self.assertEqual(declarations['actql_native_python_initial_platform_current'][0], 'bool')
        self.assertEqual((ROOT / generator.OUTPUT).read_text(), generator.render())


if __name__ == '__main__':
    unittest.main()
