"""Actual same-provider parent-read transport; not ordinary installed funding.

Fresh disposable FDs only. The plan is maintainer diagnostic input, never
public Client configuration or an alternative to the missing normal supplier.
"""
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

from actql_sdk._local_native_control_custody import _OriginalControlCustody, _OriginalControlFunctions, _OriginalControlError
from actql_sdk._local_native_backing_custody import _OriginalBackingCustody, _OriginalBackingFunctions
from actql_sdk._local_native_domain_custody import _OriginalDomainCustody, _OriginalDomainFunctions, _OriginalDomainReadFunctions
from actql_sdk._local_native_original_read import _OriginalParentReadCustody, _OriginalParentReadFunctions, _OriginalParentReadError
from actql_sdk._local_worker_slot import _OriginalDescriptor

plan = json.loads(Path(sys.argv[1]).read_bytes())
case = sys.argv[2]
assert case in ('parent-read-alias', 'parent-read-invalid-budget',
                'parent-read-foreign-closing', 'parent-read-scoped-one-shot')
for item in plan['files']:
    raw = Path(item['path']).read_bytes()
    assert len(raw) == item['bytes'] and hashlib.sha256(raw).hexdigest() == item['sha256'], item['path']
loaded = []
for name in ('_local_native_original_read', '_local_native_domain_custody',
             '_local_native_control_custody'):
    path = Path(sys.modules['actql_sdk.' + name].__file__).resolve()
    assert path == Path(plan['root'], 'packages/python-sdk/src/actql_sdk', name + '.py')
    loaded.append({'module': name, 'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
lib = C.CDLL(plan['library'])
helper = C.CDLL(plan['helper'])
for name in ('actql_native_owned_current', 'actql_native_owned_allocate',
             'actql_bootstrap_current_read_context'):
    assert C.cast(getattr(lib, name), C.c_void_p).value == C.cast(getattr(helper, name), C.c_void_p).value
initialize = lib.actql_original_control_initialize
initialize.argtypes = [C.c_int, C.POINTER(C.c_char_p)]; initialize.restype = C.c_int
assert initialize(1, (C.c_char_p * 1)(b'private-parent-read')) == 0
control, backing = _OriginalControlFunctions(lib), _OriginalBackingFunctions(lib)
domains, read = _OriginalDomainFunctions(lib), _OriginalDomainReadFunctions(lib)
parent = _OriginalParentReadFunctions(lib)
prepare = helper.actql_fixture_read_preparation_into
prepare.argtypes = [C.POINTER(C.c_void_p)]; prepare.restype = C.c_int
aliases = helper.actql_fixture_read_aliases
aliases.argtypes = []; aliases.restype = C.c_void_p
release = helper.actql_fixture_read_release_alias
release.argtypes = [C.c_void_p]; release.restype = None
page = os.sysconf('SC_PAGE_SIZE')
directory = Path(tempfile.mkdtemp(prefix='actql-' + case + '-', dir='/private/tmp'))
Path(plan['output'], case + '-start.json').write_text(json.dumps({
    'pid': os.getpid(), 'directory': str(directory), 'host_pages': 64,
    'domain_pages': 48, 'normal_profile': None, 'loaded': loaded}) + '\n')
originals = []


def domain():
    reply = C.c_void_p(); assert prepare(C.byref(reply)) == 0
    host = _OriginalControlCustody._take_original_reply(control, reply)
    fd = _OriginalDescriptor(os.open(directory / str(len(originals)),
        os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600))
    os.ftruncate(fd.value, 64 * page); host.acquire_fd(fd)
    scope = _OriginalBackingCustody._borrow_original(host, backing)
    with scope._physical_scope():
        d = _OriginalDomainCustody._prepare_original(host, scope, fd, domains,
            size=48 * page, work=2, attempts=2, holdings=1, transfer=3,
            retained=2 * page, execution=16 * page)
    d.transfer(); d._prepare_read_context(read)
    originals.append((host, fd, scope, d))
    return d


def acquire(d, **kw):
    return _OriginalParentReadCustody._prepare_original(d, parent,
        **({'bootstrap_retained':page, 'bootstrap_execution':page,
            'workspace_execution':8*page, 'read_retained':page, 'read_execution':4*page} | kw))


def finish():
    for host, fd, scope, d in reversed(originals):
        scope.return_after_stop(); d.close_after_stop(); host.close()
        assert d._closed and host._closed and not fd.close_attempted
        os.fstat(fd.value); fd.close()


d = domain()
if case == 'parent-read-invalid-budget':
    try: acquire(d, bootstrap_retained=0)
    except _OriginalParentReadError as error:
        assert not error.unknown and error.fact.issue_family == 11
        original = error.cleanup_read
        assert original._closed and original._original.value is None
    else: raise AssertionError('Invalid declaration became a read grant')
    finish()
else:
    original = acquire(d)
    assert original.current().issue_family == 0
    try: d.close_after_stop()
    except ValueError: pass
    else: raise AssertionError('Parent ignored original read custody')
    if case == 'parent-read-alias':
        with original.scope():
            value = aliases(); assert value
        for remaining in (2, 1):
            try: original.close()
            except _OriginalParentReadError as error:
                assert not error.unknown and error.fact.issue_family == 6
                assert not original._closed and original._original.value is not None
            else: raise AssertionError('Original cleanup ignored a managed alias')
            release(value)
    elif case == 'parent-read-foreign-closing':
        other = domain()
        reply = C.c_void_p()
        assert parent.current(other._host, original._original, C.byref(reply)) == 0
        assert parent.operation(reply) == 2 and parent.issue(reply) == 2
        assert parent.drop(C.byref(reply), original._host, original._native_domain, original._original) == 0
        try: d._owner.close()
        except _OriginalControlError as error:
            assert not error.unknown and error.fact.issue_family == 5
        else: raise AssertionError('Host closing ignored read custody')
        try: original.current()
        except _OriginalParentReadError as error:
            assert not error.unknown and error.fact.issue_family == 4
        else: raise AssertionError('Closing Host granted current read')
    else:
        with original.scope():
            try: original.close()
            except ValueError: pass
            else: raise AssertionError('Scoped caller claimed its own retirement')
            out = C.c_void_p()
            assert parent.prepare(d._host, d._domain, page, page, 8*page, page, 4*page, C.byref(out)) == -1
            assert out.value is None
        original.current()
    original.close(); original.close()
    assert original._closed and not original._scope_open
    for action in (original.current, lambda: acquire(d)):
        try: action()
        except ValueError: pass
        else: raise AssertionError('Retired carrier or same domain was reissued')
    finish()
assert all(h._closed and fd.closed and d._closed for h, fd, s, d in originals)
print(json.dumps({'success':True, 'case':case, 'discovered':1, 'executed':1,
                  'passed':1, 'failed':0, 'all_originals_closed':True,
                  'initializer_calls':1, 'VM':0, 'public_e2e':0}))
