"""Actual private stop request and distinct retirement through one provider.

Each case initializes its own selected component once and uses one independently
specified64/48-page parent/domain fixture. These are not compiler/VM funding,
production worker issuance, a Run outcome or a normal numerical profile.
"""
import atexit
import ctypes as C
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'packages/python-sdk/src')]
from actql_sdk._local_distribution import _read_file
from actql_sdk._local_worker_slot import _OriginalDescriptor
from actql_sdk._local_native_control_custody import _OriginalControlCustody, _OriginalControlFunctions
from actql_sdk._local_native_process_custody import _OriginalInstalledProcessError

if len(sys.argv) not in (2, 3):
    raise ValueError('Select the original stop-request conformance plan and optional case')
plan = json.loads(Path(sys.argv[1]).read_bytes())
case = sys.argv[2] if len(sys.argv) == 3 else None
if case not in (None, 'unstarted', 'stopped'):
    raise ValueError('Select an original stop-request conformance case')
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == plan['source']
assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)
for item in plan['consumer_inputs']:
    raw = (ROOT / item['path']).read_bytes()
    assert len(raw) == item['bytes'] and hashlib.sha256(raw).hexdigest() == item['sha256']
library_path = Path(plan['library']['path'])
_read_file(library_path, maximum=16 * 1024 * 1024,
           expected=plan['library']['bytes'], digest=plan['library']['sha256'])
output = Path(plan['output'])
if case is None:
    records = []
    for name in ('unstarted', 'stopped'):
        result = subprocess.run([sys.executable, '-I', '-B', str(Path(__file__).resolve()),
                                 sys.argv[1], name], cwd=ROOT,
                                env={'PATH': os.defpath, 'LC_ALL': 'C'},
                                capture_output=True, text=True, timeout=15)
        (output / (name + '.stdout')).write_text(result.stdout)
        (output / (name + '.stderr')).write_text(result.stderr)
        assert result.returncode == 0, (name, result.returncode)
        record = json.loads(result.stdout.strip().splitlines()[-1])
        assert record['discovered'] == record['executed'] == record['passed'] == 1
        assert record['failed'] == record['skipped'] == 0 and record['originals_closed']
        records.append(record)
    print(json.dumps(dict(discovered=2, executed=2, passed=2, failed=0, skipped=0,
        source=plan['source'], provider_source=plan['provider_source'], cases=records,
        library_sha256=plan['library']['sha256'], normal_profile=None,
        Engine=0, VM=0, Run=0, wheel=0, public_E2E=0)), flush=True)
    raise SystemExit(0)

spec = importlib.util.spec_from_file_location('original_process_stop_compiler',
                                             ROOT / 'scripts/compile-python-local-image.py')
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)
page = os.sysconf('SC_PAGE_SIZE')
fixture = Path(tempfile.mkdtemp(prefix='actql-original-stop-capi-', dir='/private/tmp'))
(output / (case + '-fixture.json')).write_text(json.dumps(dict(
    source=plan['source'], pid=os.getpid(), path=str(fixture),
    parent_pages=64, child_pages=48, normal_profile=None)) + '\n')
(fixture / 'packages/python-local-runtime').mkdir(parents=True)
(fixture / '.gitignore').write_text('*.backing\n*.slot\n')
subprocess.run(['git', 'init', '-q'], cwd=fixture, check=True)
engine_body = b'independent stop-request conformance; no Engine/VM or image'
holding = dict(scope='image_compiler_only', module_sha256='0' * 64,
    engine_sha256=hashlib.sha256(engine_body).hexdigest(), runtime_library_sha256='0' * 64,
    provider_library_sha256=plan['library']['sha256'], capacity_bytes=64 * page, generation=7)
selected = fixture / 'packages/python-local-runtime/selected-compiler-holding.json'
selected.write_text(json.dumps(holding, sort_keys=True) + '\n')
parent_body = dict(scope='image_compiler_parent_only',
    holding_sha256=hashlib.sha256(selected.read_bytes()).hexdigest(),
    parent=dict(bytes=64 * page, work=20, attempts=8, holdings=4, transfer=30,
                retained=0, execution=64 * page, control_envelope=65536),
    child=dict(bytes=48 * page, work=2, attempts=1, holdings=1, transfer=3,
               retained=0, execution=48 * page))
(fixture / 'packages/python-local-runtime/selected-compiler-parent.json').write_text(
    json.dumps(parent_body, sort_keys=True) + '\n')
subprocess.run(['git', 'add', '.'], cwd=fixture, check=True)
subprocess.run(['git', '-c', 'user.name=ActQL conformance', '-c',
                'user.email=conformance@invalid.local', 'commit', '-qm',
                'test: retain the original stop-request fixture'], cwd=fixture, check=True)
source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=fixture, text=True).strip()
compiler.ROOT = fixture
original = dict(source=source, module_sha256='0' * 64, provider_library=library_path,
    recipe=SimpleNamespace(engine_body=engine_body, runtime_library_sha256='0' * 64,
        provider_library_sha256=plan['library']['sha256'], provider_library_bytes=plan['library']['bytes']))
descriptor = _OriginalDescriptor(os.open(fixture / 'parent.backing',
    os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600))
os.ftruncate(descriptor.value, 64 * page)
parent = None
process = None
other = None
spawn_attempted = False

def cleanup_known_unstarted():
    if spawn_attempted or parent is None:
        return
    if any(getattr(x, "_unknown", None) is not None for x in (other, process, parent.host, parent.domain)):
        return
    if other is not None and not other._closed:
        other.close()
    if process is not None and not process._closed:
        process.restrict_transport()
        process.return_transport()
        process.close_unstarted()
    if not parent._closed:
        parent.close_unstarted()
    if not descriptor.closed:
        descriptor.close()

def observe():
    (output / (case + '-original-observation.json')).write_text(json.dumps(dict(
        parent_closed=getattr(parent, '_closed', False),
        process_closed=getattr(process, '_closed', False),
        descriptor_closed=descriptor.closed,
        other_host_closed=getattr(other, '_closed', None),
        process_runtime_retirement_ACK=False, normal_profile=None)) + '\n')
atexit.register(observe)
# atexit is LIFO: known original cleanup precedes the observation. An exception
# here is retained by Python and cannot become a successful case or an ACK.
atexit.register(cleanup_known_unstarted)
parent = compiler._acquire_compiler_parent(original,
    compiler._compiler_holding_original(original), descriptor)
process = parent.prepare_process(path=str(fixture / 'process.slot'), nonce=7)
if case == 'unstarted':
    try:
        process.request_stop()
    except _OriginalInstalledProcessError as refused:
        assert not refused.unknown and refused.fact.operation == 12
    else:
        raise AssertionError('Unstarted original must not select a child')
    assert process._unknown is None and not process._closed
    other = _OriginalControlCustody._prepare_original(_OriginalControlFunctions(parent.library),
        source='a' * 40, recipe=b'b' * 32, generation=7, size=64 * page,
        work=20, attempts=8, holdings=4, transfer=30, retained=0,
        execution=64 * page, envelope=65536)
    reply = C.c_void_p()
    functions = process._functions
    assert functions.operate(other._original, process._native_domain, process._process,
                             12, C.byref(reply)) == 0 and reply.value is not None
    assert functions.operation(reply) == 12 and functions.issue(reply) != 0
    assert functions.drop(C.byref(reply), process._host,
                          process._native_domain, process._process) == 0 and reply.value is None
    other.close()
    process.restrict_transport()
    process.return_transport()
    process.close_unstarted()
else:
    process.prepare_child('/bin/sh', ('-c', 'read command'), ())
    spawn_attempted = True
    process.spawn()
    # ACTUAL original child stop request. The existing C tag and copied DATA
    # do not close any nominal slot or substitute for typed process stop.
    assert process.request_stop() is True
    assert not process._closed and process._unknown is None
    assert parent.domain._installed_process_original is process
    assert not parent._closed and not descriptor.close_attempted
    process.restrict_transport()
    process.return_transport()
    for _ in range(500):
        if process.poll_stop():
            break
        time.sleep(0.001)
    else:
        raise AssertionError('Original typed stop remains unconfirmed')
    assert process.request_stop() is False and not process._closed
    process.retire_stopped()
assert process._closed and process._unknown is None
assert parent.domain._installed_process_original is None
parent.close_unstarted()
assert parent._closed and not descriptor.close_attempted
os.fstat(descriptor.value)
descriptor.close()
_read_file(library_path, maximum=16 * 1024 * 1024,
           expected=plan['library']['bytes'], digest=plan['library']['sha256'])
print(json.dumps(dict(discovered=1, executed=1, passed=1, failed=0, skipped=0,
    case=case, fixture=str(fixture), source=plan['source'], provider_source=plan['provider_source'],
    library_sha256=plan['library']['sha256'], initializer_calls=1, originals_closed=True,
    process_runtime_retirement_ACK=False, normal_profile=None,
    Engine=0, VM=0, Run=0, wheel=0, public_E2E=0)), flush=True)
