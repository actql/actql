"""Fresh same-provider compiler transport; input refusal before Config only.

The independent 64/48-page selection is deliberately not the selected compiler
envelope or a normal profile. Actual compiler output and original physical
retirement are asserted separately; no image/Engine success is inferred.
"""
import atexit
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'scripts'), str(ROOT / 'packages/python-sdk/src')]
from actql_sdk._local_distribution import _read_file
from actql_sdk._local_worker_slot import _OriginalDescriptor
from python_compiler_process import invoke_original_compiler

plan = json.loads(Path(sys.argv[1]).read_bytes())
case = sys.argv[2]
assert case in ('missing', 'empty', 'digest')
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == plan['source']
assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)
for item in plan['inputs']:
    _read_file(Path(item['path']), maximum=item['bytes'], expected=item['bytes'], digest=item['sha256'])
output = Path(plan['output']) / case
output.mkdir(exist_ok=False)
fixture = Path(tempfile.mkdtemp(prefix='actql-compiler-child-original-', dir='/private/tmp'))
(output / 'fixture-start.json').write_text(json.dumps(dict(pid=os.getpid(), fixture=str(fixture))) + '\n')
spec = importlib.util.spec_from_file_location('compiler_original_child', ROOT / 'scripts/compile-python-local-image.py')
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)
compiler.ROOT = fixture
page = os.sysconf('SC_PAGE_SIZE')
assert page > 0
(fixture / 'packages/python-local-runtime').mkdir(parents=True)
(fixture / '.gitignore').write_text('*.backing\n*.slot\n*.wasm\n*.cwasm\n')
subprocess.run(['git', 'init', '-q'], cwd=fixture, check=True)
engine = b'independent original compiler child transport; Config never entered'
holding = dict(scope='image_compiler_only', module_sha256='0' * 64,
    engine_sha256=hashlib.sha256(engine).hexdigest(), runtime_library_sha256='0' * 64,
    provider_library_sha256=plan['provider']['sha256'], capacity_bytes=64 * page, generation=7)
holding_path = fixture / 'packages/python-local-runtime/selected-compiler-holding.json'
holding_path.write_text(json.dumps(holding, sort_keys=True) + '\n')
body = dict(scope='image_compiler_parent_only', holding_sha256=hashlib.sha256(holding_path.read_bytes()).hexdigest(),
    parent=dict(bytes=64 * page, work=20, attempts=8, holdings=4, transfer=30,
                retained=0, execution=64 * page, control_envelope=65536),
    child=dict(bytes=48 * page, work=2, attempts=1, holdings=1, transfer=3,
               retained=0, execution=48 * page))
(fixture / 'packages/python-local-runtime/selected-compiler-parent.json').write_text(json.dumps(body, sort_keys=True) + '\n')
subprocess.run(['git', 'add', '.'], cwd=fixture, check=True)
subprocess.run(['git', '-c', 'user.name=ActQL conformance', '-c', 'user.email=conformance@invalid.local',
    'commit', '-qm', 'test: retain original compiler child fixture'], cwd=fixture, check=True)
source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=fixture, text=True).strip()
recipe = SimpleNamespace(engine_body=engine, runtime_library_sha256='0' * 64,
    provider_library_sha256=plan['provider']['sha256'], provider_library_bytes=plan['provider']['bytes'])
original = dict(source=source, module_sha256='0' * 64, recipe=recipe,
                provider_library=Path(plan['provider']['path']))
selected = compiler._compiler_holding_original(original)
descriptor = _OriginalDescriptor(os.open(fixture / 'original.backing', os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600))
os.ftruncate(descriptor.value, 64 * page)
parent = None
failure = None
response = None


def observe():
    process = parent.domain._installed_process_original if parent is not None and parent.domain is not None else None
    (output / 'original-observation.json').write_text(json.dumps(dict(
        fixture=str(fixture), parent_closed=getattr(parent, '_closed', None),
        descriptor_closed=descriptor.closed, descriptor_close_attempted=descriptor.close_attempted,
        process_pending=process is not None, process_unknown=process is not None and process._unknown is not None,
        response=response, failure=failure, process_exit_is_retirement_ACK=False,
        Runtime_origin=plan['runtime_origin'], provider_origin=plan['provider_origin'], normal_profile=None)) + '\n')


atexit.register(observe)
try:
    parent = compiler._acquire_compiler_parent(original, selected, descriptor)
    module = fixture / 'module.wasm'
    if case == 'empty':
        module.write_bytes(b'')
    elif case == 'digest':
        module.write_bytes(b'\0asm\x01\0\0\0')
    destination = fixture / 'image.cwasm'
    observe()
    executable = plan['executable']
    raw = invoke_original_compiler(parent, executable=Path(executable['path']),
        executable_bytes=executable['bytes'], executable_sha256=executable['sha256'],
        module=module, destination=destination, slot=str(fixture / 'original.slot'), nonce=7, timeout=12)
    (output / 'child.stdout').write_bytes(raw)
    response = json.loads(raw)
    assert response['compilation_status'] == dict(missing=2, empty=3, digest=5)[case]
    assert not any(response[key] for key in ('config_attempted', 'engine_attempted', 'module_attempted',
                                           'instance', 'physical_acceptance', 'runtime_retained'))
    assert response['holding_closed']
    assert response['handles_close'] == response['leave'] == response['holding_close'] == 0
    assert not destination.exists()
    assert parent._closed and parent.domain._closed and parent.backing._closed
    assert parent.domain._installed_process_original is None
    assert not descriptor.close_attempted
    os.fstat(descriptor.value)
    descriptor.close()
    assert parent.runtime._initialized
    observe()
    for item in plan['inputs']:
        _read_file(Path(item['path']), maximum=item['bytes'], expected=item['bytes'], digest=item['sha256'])
    print(json.dumps(dict(discovered=1, executed=1, passed=1, failed=0, skipped=0,
        case=case, source=plan['source'], response=response,
        original_parent_pages=64, original_child_pages=48, arena_originals_closed=True,
        process_runtime_retirement_ACK=False, Engine=0, Module=0, image=0, VM=0,
        normal_profile=None, wheel=0, public_Local=0)), flush=True)
except BaseException as error:
    failure = type(error).__name__
    observe()
    raise
