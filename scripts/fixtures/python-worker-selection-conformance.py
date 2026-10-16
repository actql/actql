"""Actual ctypes/regular-C original selection conformance; no worker or VM."""
import ctypes
import hashlib
import json
import pickle
import copy
import sys
from pathlib import Path
from actql_sdk._local_native_control_custody import _OriginalControlCustody, _OriginalControlFunctions
from actql_sdk._local_native_worker_selection import (
    _OriginalWorkerSelectionCustody, _OriginalWorkerSelectionFunctions,
    _OriginalWorkerSelectionError,
)

plan = json.loads(Path(sys.argv[1]).read_text())
for item in plan['inputs']:
    data = Path(item['path']).read_bytes()
    assert len(data) == item['bytes'] and hashlib.sha256(data).hexdigest() == item['sha256']
root = Path(plan['root'])
for name in ('_local_native_control_custody', '_local_native_worker_selection'):
    module = sys.modules['actql_sdk.' + name]
    actual = Path(module.__file__).resolve()
    assert actual == root / 'packages/python-sdk/src/actql_sdk' / (name + '.py')
    assert hashlib.sha256(actual.read_bytes()).hexdigest() == plan['python'][name]

library = ctypes.CDLL(plan['library'])
fixture = ctypes.CDLL(plan['fixture'])
for symbol in ('actql_native_owned_current', 'actql_control_prepare'):
    assert ctypes.cast(getattr(fixture, symbol), ctypes.c_void_p).value == ctypes.cast(getattr(library, symbol), ctypes.c_void_p).value
initialize = library.actql_original_control_initialize
initialize.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_char_p)]
initialize.restype = ctypes.c_int
assert initialize(1, (ctypes.c_char_p * 1)(b'worker-selection-private')) == 0
prepare = fixture.actql_fixture_worker_prepare_into
prepare.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
prepare.restype = ctypes.c_int
control = _OriginalControlFunctions(library)
functions = _OriginalWorkerSelectionFunctions(library)
cases = []


def host():
    original_reply = ctypes.c_void_p()
    assert prepare(ctypes.byref(original_reply)) == 0 and original_reply.value is not None
    return _OriginalControlCustody._take_original_reply(control, original_reply)


owner = host()
selection = _OriginalWorkerSelectionCustody._select_original(owner, functions)
assert selection.current().issue_family == 0
assert owner.current().issue_family == 1, 'metadata selection must not acquire funding'
selection.close(); selection.close()
assert selection._closed and not owner._closed
owner.close()
cases.append('same actual nominal metadata, repeated data close, no arena acquisition')

owner = host()
selection = _OriginalWorkerSelectionCustody._select_original(owner, functions)
for copy_operation in (copy.copy, copy.deepcopy, pickle.dumps):
    try: copy_operation(selection)
    except TypeError: pass
    else: raise AssertionError('nominal selection was copied')
foreign = _OriginalWorkerSelectionFunctions(ctypes.CDLL(plan['library']))
try: _OriginalWorkerSelectionCustody._select_original(owner, foreign)
except ValueError: pass
else: raise AssertionError('foreign component wrapper acquired selection')
assert selection.current().issue_family == 0
selection.close(); owner.close()
cases.append('copied metadata and foreign component wrapper are refused')

owner = host()
selection = _OriginalWorkerSelectionCustody._select_original(owner, functions)
owner.close()
try: selection.current()
except _OriginalWorkerSelectionError as failure:
    assert not failure.unknown and failure.fact.issue_family == 4
    assert failure.cleanup_selection is selection
else: raise AssertionError('closed original became current')
selection.close()
assert selection._closed and owner._closed
cases.append('closing original refusal retains exact data cleanup without another Host close')

owner = host()
selection = _OriginalWorkerSelectionCustody._select_original(owner, functions)
original_finish = functions.finish
calls = []


def lost_finish(*args):
    calls.append('finish')
    assert original_finish(*args) == 0
    raise OSError('private injected response loss after actual C reference retirement')


functions.finish = lost_finish
try: selection.close()
except _OriginalWorkerSelectionError as failure:
    unknown = failure
    assert failure.unknown and failure.cleanup_selection is selection
else: raise AssertionError('lost response became confirmed metadata close')
assert selection._host.value is None and selection._selection.value is None
assert not selection._closed and not owner._closed
try: selection.close()
except _OriginalWorkerSelectionError as failure: assert failure is unknown
else: raise AssertionError('lost metadata reply was retried')
assert calls == ['finish']
owner.close()
cases.append('actual C clears persistent slots before lost reply; sticky Unknown without repeated free')
assert len(cases) == 4
print(json.dumps({'discovered': 4, 'executed': 4, 'passed': 4, 'failed': 0, 'cases': cases,
                  'initializer': 1, 'provider_copies': 1, 'arena_acquisition': 0,
                  'preserved_unknown_metadata': True, 'worker': 0, 'Engine': 0,
                  'public_e2e': 0}))
