"""Actual same-provider scoped packaged Runtime transport; not ordinary installed funding.

Fresh disposable FDs only. The complete diagnostic allocation profile is
reused from accepted D Source0df87e9d6ff6ba9b9500fe1468363b631f6ff867,
installed_product_observation_conformance. This is a distinct profile from the
old 64/48-page capture that exhausted on a 24-byte scoped allocation. It does
not enlarge or rescue that original failed backing/attempt. The plan is maintainer diagnostic input, never
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
from actql_sdk._local_native_runtime import (
    _OriginalPackagedRuntimeCustody, _OriginalPackagedRuntimeFunctions,
    _OriginalPackagedRuntimeError,
)

plan = json.loads(Path(sys.argv[1]).read_bytes())
case = sys.argv[2]
assert case in ('runtime-close', 'runtime-changed', 'runtime-invalid', 'runtime-partial')
for item in plan['files']:
    raw = Path(item['path']).read_bytes()
    assert len(raw) == item['bytes'] and hashlib.sha256(raw).hexdigest() == item['sha256'], item['path']
loaded = []
for name in ('_local_native_original_read', '_local_native_domain_custody',
             '_local_native_control_custody', '_local_native_runtime'):
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
runtime_functions = _OriginalPackagedRuntimeFunctions(lib)
prepare = helper.actql_fixture_runtime_preparation_into
prepare.argtypes = [C.POINTER(C.c_void_p)]; prepare.restype = C.c_int
page = os.sysconf('SC_PAGE_SIZE')
directory = Path(tempfile.mkdtemp(prefix='actql-' + case + '-', dir='/private/tmp'))
Path(plan['output'], case + '-start.json').write_text(json.dumps({
    'pid': os.getpid(), 'directory': str(directory), 'host_pages': 8192,
    'domain_pages': 7168, 'normal_profile': None, 'loaded': loaded}) + '\n')
originals = []


def domain():
    reply = C.c_void_p(); assert prepare(C.byref(reply)) == 0
    host = _OriginalControlCustody._take_original_reply(control, reply)
    fd = _OriginalDescriptor(os.open(directory / str(len(originals)),
        os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600))
    os.ftruncate(fd.value, 8192 * page); host.acquire_fd(fd)
    scope = _OriginalBackingCustody._borrow_original(host, backing)
    with scope._physical_scope():
        d = _OriginalDomainCustody._prepare_original(host, scope, fd, domains,
            size=7168 * page, work=2, attempts=2, holdings=1, transfer=3,
            retained=32 * page, execution=6144 * page)
    d.transfer(); d._prepare_read_context(read)
    originals.append((host, fd, scope, d))
    return d


def acquire(d, **kw):
    return _OriginalParentReadCustody._prepare_original(d, parent,
        **({'bootstrap_retained':16*page, 'bootstrap_execution':16*page,
            'workspace_execution':4096*page, 'read_retained':16*page, 'read_execution':1024*page} | kw))


def finish():
    for host, fd, scope, d in reversed(originals):
        scope.return_after_stop(); d.close_after_stop(); host.close()
        assert d._closed and host._closed and not fd.close_attempted
        os.fstat(fd.value); fd.close()


# Independently described physical files; no DLL/Engine is loaded from this
# captured package. These "abc" members exercise capture/current/Root cleanup,
# not configuration adoption or a verified executable runtime cohort.
root = directory / 'runtime'; root.mkdir()
digest = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
def member(path, **extra):
    file = root / path; file.parent.mkdir(parents=True, exist_ok=True)
    file.write_bytes(b'abc')
    return {'path': path, 'bytes': 3, 'sha256': digest, **extra}
notice = member('licenses/fixture.txt')
libraries = [member('lib/' + role + '.bin', role=role, license='licenses/fixture.txt',
                   dependencies=['/usr/lib/libSystem.B.dylib'],
                   abi={'minimumMacOS': '26.0'}) for role in ('sqlite', 'crypto')]
assets = [member('data/' + role + '.json', role=role)
          for role in ('environment', 'registry', 'values', 'fragment', 'result-policy')]
manifest = json.dumps({'sourceSha': 'a' * 40, 'platform': 'darwin-arm64',
    'licenses': [notice], 'libraries': libraries, 'assets': assets},
    separators=(',', ':')).encode()
if case == 'runtime-partial': manifest = b'{}'
(root / 'local-runtime.json').write_bytes(manifest)
selection = {'root_path': str(root), 'source_sha': 'a' * 40,
    'platform': 'darwin-arm64', 'manifest_sha256': hashlib.sha256(manifest).hexdigest(),
    'diagnostic_ceiling': 128}
d = domain(); original = acquire(d)
if case == 'runtime-invalid':
    try:
        _OriginalPackagedRuntimeCustody._capture_original(original, runtime_functions,
            **(selection | {'root_path': 'relative'}))
    except _OriginalPackagedRuntimeError as error:
        assert not error.unknown and error.fact.issue_family == 1
        runtime = error.cleanup_runtime
        assert runtime._closed and runtime._runtime.value is None
    else: raise AssertionError('Invalid path acquired a Runtime')
else:
    try:
        runtime = _OriginalPackagedRuntimeCustody._capture_original(original, runtime_functions,
            **selection)
    except _OriginalPackagedRuntimeError as error:
        assert case == 'runtime-partial' and not error.unknown
        assert error.fact.issue_family == 2
        runtime = error.cleanup_runtime
        # Existing local_runtime_finish_open closes partial construction;
        # successful physical cleanup returns Refused with no Runtime alias.
        assert runtime._runtime.value is None and runtime._closed
    else:
        assert case != 'runtime-partial'
        assert runtime.current().issue_family == 0
        if case == 'runtime-changed':
            (root / 'data/values.json').write_bytes(b'bad')
            try: runtime.current()
            except _OriginalPackagedRuntimeError as error:
                # The existing file witness Owner reports GenerationMismatch;
                # Runtime maps that original issue to Physical, not Changed.
                print(json.dumps({'observation': 'changed-member-current',
                    'operation': error.fact.operation,
                    'issue_family': error.fact.issue_family}), flush=True)
                assert not error.unknown and error.fact.issue_family == 5
                assert error.cleanup_runtime is runtime
            else: raise AssertionError('Changed member retained current status')
    if not runtime._closed:
        for action in (original.close, lambda: original.scope().__enter__()):
            try: action()
            except ValueError: pass
            else: raise AssertionError('Parent retired or reentered during Runtime custody')
        runtime.close(); runtime.close()
        assert runtime._closed and runtime._runtime.value is None
    else:
        assert case == 'runtime-partial'
assert not original._closed and not d._closed and not d._owner._closed
original.close(); original.close()
try: runtime.current()
except ValueError: pass
else: raise AssertionError('Retired Runtime remained current')
finish()
assert all(h._closed and fd.closed and d._closed for h, fd, s, d in originals)
print(json.dumps({'success': True, 'case': case, 'discovered': 1, 'executed': 1,
    'passed': 1, 'failed': 0, 'all_originals_closed': True, 'initializer_calls': 1,
    'package_libraries_loaded': 0, 'VM': 0, 'public_e2e': 0}))
