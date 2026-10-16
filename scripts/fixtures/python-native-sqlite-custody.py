"""Actual same-provider Native/Core/SQLite/Python boundary, not product funding."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

from actql_sdk._local_native_control_custody import _OriginalControlCustody, _OriginalControlFunctions, _OriginalControlError
from actql_sdk._local_native_backing_custody import _OriginalBackingCustody, _OriginalBackingFunctions
from actql_sdk._local_native_domain_custody import _OriginalDomainCustody, _OriginalDomainFunctions, _OriginalDomainReadFunctions, _OriginalDomainError
from actql_sdk._local_native_sqlite import _OriginalSqliteCustody, _OriginalSqliteFunctions, _OriginalSqliteError
from actql_sdk._local_worker_slot import _OriginalDescriptor

plan = json.loads(Path(sys.argv[1]).read_bytes())
name = sys.argv[2]
root = Path(plan['root'])
bundle, helper_path = Path(plan['bundle']), Path(plan['helper'])
for item in plan['files']:
    raw = Path(item['path']).read_bytes()
    assert len(raw) == item['bytes'] and hashlib.sha256(raw).hexdigest() == item['sha256']
modules = []
for module_name in ('_local_native_control_custody', '_local_native_domain_custody', '_local_native_sqlite'):
    module = sys.modules['actql_sdk.' + module_name]
    path = Path(module.__file__).resolve()
    assert path == root / 'packages/python-sdk/src/actql_sdk' / (module_name + '.py')
    modules.append({'module': module_name, 'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
lib = ctypes.CDLL(str(bundle / 'libactql_native_control.dylib'))
helper = ctypes.CDLL(str(helper_path))
for symbol in ('actql_native_owned_current', 'actql_native_owned_allocate', 'actql_bootstrap_current_read_context'):
    assert ctypes.cast(getattr(lib, symbol), ctypes.c_void_p).value == ctypes.cast(getattr(helper, symbol), ctypes.c_void_p).value
initialize = lib.actql_original_control_initialize
initialize.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_char_p)]; initialize.restype = ctypes.c_int
assert initialize(1, (ctypes.c_char_p * 1)(b'private-original-sqlite')) == 0
control, backing = _OriginalControlFunctions(lib), _OriginalBackingFunctions(lib)
functions, read = _OriginalDomainFunctions(lib), _OriginalDomainReadFunctions(lib)
sqlite = _OriginalSqliteFunctions(lib)
prepare = helper.actql_fixture_read_preparation_into
prepare.argtypes = [ctypes.POINTER(ctypes.c_void_p)]; prepare.restype = ctypes.c_int
aliases = helper.actql_fixture_read_aliases; aliases.argtypes = []; aliases.restype = ctypes.c_void_p
release = helper.actql_fixture_read_release_alias; release.argtypes = [ctypes.c_void_p]; release.restype = None
page = os.sysconf('SC_PAGE_SIZE')
directory = Path(tempfile.mkdtemp(prefix='actql-native-sqlite-' + name + '-', dir='/private/tmp'))
owners, domains, descriptors = [], [], []
Path(plan['output'], name + '-start.json').write_text(json.dumps({'pid': os.getpid(), 'fixture_directory': str(directory), 'parent_pages':64, 'payload_pages':48, 'heap_pages':32, 'normal_profile':None}) + '\n')


def host_domain():
    reply = ctypes.c_void_p(); assert prepare(ctypes.byref(reply)) == 0
    host = _OriginalControlCustody._take_original_reply(control, reply); owners.append(host)
    descriptor = _OriginalDescriptor(os.open(str(directory / str(len(descriptors))), os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600))
    descriptors.append(descriptor); os.ftruncate(descriptor.value, 64 * page)
    host.acquire_fd(descriptor)
    scope = _OriginalBackingCustody._borrow_original(host, backing)
    # A new private SQLite slice inside the unchanged 64-page parent/FD.
    # The previous read-only conformance keeps its separate 16-page slice.
    with scope._physical_scope():
        domain = _OriginalDomainCustody._prepare_original(host, scope, descriptor, functions,
            size=48 * page, work=2, attempts=1, holdings=1, transfer=3, retained=0, execution=48 * page)
    domains.append(domain); domain.transfer(); domain._prepare_read_context(read)
    return host, descriptor, scope, domain


def finish(host, descriptor, scope, domain):
    domain._close_read_context(read)
    scope.return_after_stop(); domain.close_after_stop(); host.close()
    assert domain._closed and host._closed and not descriptor.close_attempted
    os.fstat(descriptor.value); descriptor.close()


def acquire(domain, path=None):
    return _OriginalSqliteCustody._prepare_original(domain, sqlite,
        path=str(bundle / 'libactql_sqlite_component.dylib') if path is None else path,
        heap_bytes=32 * page, diagnostic_ceiling=128)


host, fd, scope, domain = host_domain()
try:
    if name == 'original-library-and-alias':
        original = acquire(domain)
        assert original.current().issue_family == 0
        try: domain.close_after_stop()
        except ValueError: pass
        else: raise AssertionError('Python retired a domain with original Library custody')
        try: domain._close_read_context(read)
        except _OriginalDomainError as error: assert not error.unknown and error.fact.issue_family == 5
        else: raise AssertionError('Core retired an original Library read context')
        with domain._read_scope(read):
            alias = aliases(); assert alias
        original.close(); original.close()
        try: domain._close_read_context(read)
        except _OriginalDomainError as error: assert not error.unknown and error.fact.issue_family == 6
        else: raise AssertionError('Escaped original managed alias was ignored')
        release(alias); release(alias)
        finish(host, fd, scope, domain)
    elif name == 'partial-loader-cleanup':
        try: acquire(domain, '/actql/no-original-component/missing.dylib')
        except _OriginalSqliteError as error:
            assert not error.unknown and error.fact.issue_family == 12
            original = error.cleanup_library
        else: raise AssertionError('Missing component became a ready Library')
        assert original._original.value is not None and domain._sqlite_library_original is original
        original.close(); assert original._closed
        finish(host, fd, scope, domain)
    elif name == 'closing-current-and-cleanup':
        original = acquire(domain)
        try: host.close()
        except _OriginalControlError as error: assert not error.unknown and error.fact.issue_family == 5
        else: raise AssertionError('Host ignored original Library/domain')
        try: original.current()
        except _OriginalSqliteError as error: assert not error.unknown and error.fact.issue_family == 4
        else: raise AssertionError('Closing Host still supplied current Library')
        original.close(); finish(host, fd, scope, domain)
    elif name == 'foreign-active-scope-and-one-shot':
        foreign_functions = _OriginalSqliteFunctions(ctypes.CDLL(str(bundle / 'libactql_native_control.dylib')))
        try:
            _OriginalSqliteCustody._prepare_original(domain, foreign_functions,
                path=str(bundle / 'libactql_sqlite_component.dylib'), heap_bytes=32 * page, diagnostic_ceiling=128)
        except ValueError: pass
        else: raise AssertionError('Foreign component wrapper gained custody')
        original = acquire(domain)
        other, other_fd, other_scope, other_domain = host_domain()
        reply = ctypes.c_void_p()
        assert sqlite.current(other._original, original._original, ctypes.byref(reply)) == 0
        assert sqlite.operation(reply) == 2 and sqlite.issue(reply) == 2
        assert sqlite.drop(ctypes.byref(reply), original._host, original._native_domain, original._original) == 0
        assert reply.value is None
        # Controller allocations must not escape from their own child scope.
        raw = '/candidate/component.dylib'.encode('utf-16-le')
        text = (ctypes.c_uint16 * (len(raw)//2)).from_buffer_copy(raw)
        with domain._read_scope(read):
            assert sqlite.prepare(domain._host, domain._domain, text, len(text), 32*page, 128, ctypes.byref(reply)) == -1
            assert reply.value is None
        original.current(); original.close()
        # Python tombstone rejects first; raw trusted C also observes Core's
        # same-domain read-use closing at the earlier current fence. Existing
        # enter_backed_read_cleanup stops the Common use before physical close.
        assert sqlite.prepare(domain._host, domain._domain, text, len(text), 32*page, 128, ctypes.byref(reply)) == 0
        assert sqlite.operation(reply) == 1 and sqlite.issue(reply) == 8
        h, d, o = ctypes.c_void_p(), ctypes.c_void_p(), ctypes.c_void_p()
        assert sqlite.originals(reply, ctypes.byref(h), ctypes.byref(d), ctypes.byref(o)) == 0
        assert h.value == domain._host.value and d.value == domain._domain.value and o.value is None
        assert sqlite.refused(ctypes.byref(h), ctypes.byref(d), ctypes.byref(reply)) == 0
        assert not any(v.value is not None for v in (h, d, o, reply))
        finish(other, other_fd, other_scope, other_domain)
        finish(host, fd, scope, domain)
    else:
        raise AssertionError('Unknown fixed case')
except BaseException as error:
    fact = getattr(error, "fact", None)
    observed = {"type": type(error).__name__, "unknown": getattr(error, "unknown", None),
                "operation": getattr(fact, "operation", None), "issue_family": getattr(fact, "issue_family", None)}
    Path(plan['output'], name + '-partial-custody.json').write_text(json.dumps({
        'directory': str(directory), 'Host_closed': [h._closed for h in owners],
        'domain_closed': [d._closed for d in domains], 'FD_closed': [d.closed for d in descriptors],
        'cleanup_confirmed': False, 'observed_error': observed}, indent=2) + '\n')
    raise
assert all(h._closed for h in owners) and all(d._closed for d in domains) and all(d.closed for d in descriptors)
print(json.dumps({'case': name, 'pass': True, 'initializer_calls': 1, 'parent_pages': 64,
    'sqlite_payload_pages': 48, 'heap_pages': 32, 'same_provider': True,
    'Core_Common_actual': True, 'Host_closed': len(owners), 'domain_closed': len(domains),
    'FD_closed': len(descriptors), 'fixture_directory': str(directory), 'loaded_python': modules,
    'normal_profile': None, 'VM': 0, 'worker': 0, 'wheel': 0, 'public_E2E': 0}), flush=True)
