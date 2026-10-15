"""Actual same-Runtime metadata transport; never a trusted installed release.

Synthetic three-byte members are only observed, not loaded. The complete
Source0df87e9d6 private diagnostic profile is unchanged. Every case uses a new
disposable FD and closes inner Runtime data before the original outer read.
"""
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

from actql_sdk._local_native_backing_custody import _OriginalBackingCustody, _OriginalBackingFunctions
from actql_sdk._local_native_control_custody import _OriginalControlCustody, _OriginalControlFunctions
from actql_sdk._local_native_domain_custody import (
    _OriginalDomainCustody, _OriginalDomainFunctions, _OriginalDomainReadFunctions,
)
from actql_sdk._local_native_original_read import _OriginalParentReadCustody, _OriginalParentReadFunctions
from actql_sdk._local_native_product import _OriginalPackagedProductFunctions
from actql_sdk._local_native_runtime import (
    _OriginalPackagedRuntimeCustody, _OriginalPackagedRuntimeFunctions,
    _OriginalPackagedRuntimeError,
)
from actql_sdk._local_worker_slot import _OriginalDescriptor


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def wire(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def materials(directory):
    """Independent formal census and expected digests, not product output."""
    launcher = directory / 'node_modules/actql'
    platform = directory / 'node_modules/@actql/cli-darwin-arm64'
    records = {}
    def member(root, path, data=b'abc', mode=0o644):
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data); target.chmod(mode)
        entry = {'path': path, 'bytes': len(data), 'sha256': digest(data), 'mode': mode}
        records.setdefault(root, []).append(entry)
        return {k: entry[k] for k in ('path', 'bytes', 'sha256')}
    notice = member(platform, 'licenses/fixture.txt')
    libraries = [member(platform, 'lib/' + role + '.bin') | {
        'role': role, 'license': 'licenses/fixture.txt',
        'dependencies': ['/usr/lib/libSystem.B.dylib'], 'abi': {'minimumMacOS': '26.0'},
    } for role in ('sqlite', 'crypto')]
    assets = [member(platform, 'data/' + role + '.json') | {'role': role}
              for role in ('environment', 'registry', 'values', 'fragment', 'result-policy')]
    manifest = wire({'sourceSha': 'a' * 40, 'platform': 'darwin-arm64',
                     'licenses': [notice], 'libraries': libraries, 'assets': assets})
    member(platform, 'local-runtime.json', manifest)
    for name in ('LICENSE', 'artifact.json', 'package.json'):
        member(platform, name)
    member(platform, 'empty.txt', b'')
    member(platform, 'bin/actql-native-client', mode=0o755)
    for name in ('README.md', 'package.json', 'platforms.json'):
        member(launcher, name)
    member(launcher, 'bin/actql.mjs', mode=0o755)
    inventories = []
    for root, name in ((launcher, 'actql'), (platform, '@actql/cli-darwin-arm64')):
        raw = wire({'files': sorted(records[root], key=lambda x: x['path']),
                    'packageName': name, 'platform': 'darwin-arm64', 'sourceSha': 'a' * 40})
        (root / 'local-product-members.json').write_bytes(raw)
        (root / 'local-product-members.json').chmod(0o644)
        inventories.append(digest(raw))
    expected = wire({'launcher_inventory_sha256': inventories[0],
                     'native_binary_sha256': digest(b'abc'), 'platform': 'darwin-arm64',
                     'platform_inventory_sha256': inventories[1],
                     'runtime_manifest_sha256': digest(manifest), 'source_sha': 'a' * 40}).decode()
    return launcher, platform, digest(manifest), inventories, expected


plan = json.loads(Path(sys.argv[1]).read_bytes()); case = sys.argv[2]
assert case in ('product-current', 'product-changed', 'product-invalid')
for item in plan['files']:
    raw = Path(item['path']).read_bytes()
    assert len(raw) == item['bytes'] and digest(raw) == item['sha256'], item['path']
loaded = []
for name in ('_local_native_product', '_local_native_runtime', '_local_native_original_read'):
    path = Path(sys.modules['actql_sdk.' + name].__file__).resolve()
    assert path == Path(plan['root'], 'packages/python-sdk/src/actql_sdk', name + '.py')
    loaded.append({'path': str(path), 'sha256': digest(path.read_bytes())})
lib, helper = C.CDLL(plan['library']), C.CDLL(plan['helper'])
for name in ('actql_native_owned_current', 'actql_native_owned_allocate',
             'actql_bootstrap_control_scope_clear'):
    assert C.cast(getattr(lib, name), C.c_void_p).value == C.cast(getattr(helper, name), C.c_void_p).value
initialize = lib.actql_original_control_initialize
initialize.argtypes = [C.c_int, C.POINTER(C.c_char_p)]; initialize.restype = C.c_int
assert initialize(1, (C.c_char_p * 1)(b'private-product-read')) == 0
control, backing = _OriginalControlFunctions(lib), _OriginalBackingFunctions(lib)
domains, read = _OriginalDomainFunctions(lib), _OriginalDomainReadFunctions(lib)
parent = _OriginalParentReadFunctions(lib)
runtime_functions, product = _OriginalPackagedRuntimeFunctions(lib), _OriginalPackagedProductFunctions(lib)
prepare = helper.actql_fixture_runtime_preparation_into
prepare.argtypes = [C.POINTER(C.c_void_p)]; prepare.restype = C.c_int
directory = Path(tempfile.mkdtemp(prefix='actql-' + case + '-', dir='/private/tmp'))
page = os.sysconf('SC_PAGE_SIZE')
Path(plan['output'], case + '-start.json').write_text(json.dumps({
    'pid': os.getpid(), 'directory': str(directory), 'loaded': loaded,
    'host_pages': 8192, 'domain_pages': 7168, 'normal_profile': None}) + '\n')
launcher, platform, manifest_hash, inventories, expected = materials(directory)
reply = C.c_void_p(); assert prepare(C.byref(reply)) == 0
host = _OriginalControlCustody._take_original_reply(control, reply)
fd = _OriginalDescriptor(os.open(directory / 'fresh-backing', os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600))
os.ftruncate(fd.value, 8192 * page); host.acquire_fd(fd)
scope = _OriginalBackingCustody._borrow_original(host, backing)
with scope._physical_scope():
    # Owned depth is nonzero while valid read-context pointer is NULL. Neither
    # a nullable getter nor one nested leave can admit a control callback.
    untouched = C.c_void_p()
    assert product.identity(C.c_void_p(1), C.byref(untouched)) == -1
    assert untouched.value is None
    for call in (runtime_functions.current, runtime_functions.close):
        assert call(C.c_void_p(1), C.byref(untouched)) == -1
        assert untouched.value is None
    domain = _OriginalDomainCustody._prepare_original(host, scope, fd, domains,
        size=7168 * page, work=2, attempts=2, holdings=1, transfer=3,
        retained=32 * page, execution=6144 * page)
domain.transfer(); domain._prepare_read_context(read)
original = _OriginalParentReadCustody._prepare_original(domain, parent,
    bootstrap_retained=16 * page, bootstrap_execution=16 * page,
    workspace_execution=4096 * page, read_retained=16 * page, read_execution=1024 * page)
runtime = _OriginalPackagedRuntimeCustody._capture_original(original, runtime_functions,
    root_path=str(platform), source_sha='a' * 40, platform='darwin-arm64',
    manifest_sha256=manifest_hash, diagnostic_ceiling=128)
selection = {'launcher_root': str(launcher), 'launcher_descriptor_sha256': inventories[0],
             'platform_descriptor_sha256': inventories[1], 'diagnostic_ceiling': 128}
if case == 'product-invalid':
    # Independently bind the modified descriptor's bytes; do not manufacture a
    # hash failure instead of exercising the existing closed-body validator.
    path = launcher / 'local-product-members.json'
    body = json.loads(path.read_bytes()); body['unknown'] = True
    raw = wire(body); path.write_bytes(raw)
    selection['launcher_descriptor_sha256'] = digest(raw)
    try: product.observe_members(runtime, **selection)
    except _OriginalPackagedRuntimeError as error:
        assert not error.unknown and error.fact.issue_family == 2
        assert error.cleanup_runtime is runtime
    else: raise AssertionError('Unknown metadata field was accepted')
else:
    assert product.observe_members(runtime, **selection).issue_family == 0
    actual = product.identity_wire(runtime)
    assert actual == expected
    assert product.identity_wire(runtime) == expected
    if case == 'product-changed':
        (launcher / 'bin/actql.mjs').write_bytes(b'bad')
        try: product.identity_wire(runtime)
        except _OriginalPackagedRuntimeError as error:
            assert not error.unknown and error.fact.issue_family == 5
            assert error.cleanup_runtime is runtime
        else: raise AssertionError('Changed original image retained current metadata')
    else:
        # Metadata copies do not renew the one-shot observation/adoption.
        try: product.observe_members(runtime, **selection)
        except _OriginalPackagedRuntimeError as error:
            assert not error.unknown and error.fact.issue_family == 3
        else: raise AssertionError('Original product observation was reissued')
runtime.close(); runtime.close()
assert runtime._closed and runtime._product_reply.value is None and not original._closed
try: product.identity_wire(runtime)
except ValueError: pass
else: raise AssertionError('Retired Runtime still issued metadata')
original.close(); scope.return_after_stop(); domain.close_after_stop(); host.close()
assert host._closed and domain._closed and not fd.close_attempted
os.fstat(fd.value); fd.close()
print(json.dumps({'success': True, 'case': case, 'discovered': 1, 'executed': 1,
    'passed': 1, 'failed': 0, 'all_originals_closed': True, 'initializer_calls': 1,
    'package_libraries_loaded': 0, 'VM': 0, 'public_e2e': 0}))
