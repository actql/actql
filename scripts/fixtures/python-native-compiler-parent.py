"""Actual Native parent/domain assembly in a fresh maintainer fixture.

The declarations are an independent private 64/48-page conformance selection,
not the selected compiler module/Engine, installed funding or a normal profile.
The product source reader and the real Native Ledger/domain owners both run.
"""
import ctypes as C
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
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk._local_distribution import _read_file
from actql_sdk._local_native_control_custody import _OriginalControlCustody, _OriginalControlFunctions, _OriginalControlError
from actql_sdk._local_native_domain_custody import _OriginalDomainMaterialFunctions
from actql_sdk._local_native_shim_abi import bind
from actql_sdk._local_worker_slot import _OriginalDescriptor

plan = json.loads(Path(sys.argv[1]).read_bytes())
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == plan['source']
assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)
for item in plan['consumer_inputs']:
    raw = (ROOT / item['path']).read_bytes()
    assert len(raw) == item['bytes'] and hashlib.sha256(raw).hexdigest() == item['sha256']
library_path = Path(plan['library']['path'])
_read_file(library_path, maximum=16*1024*1024, expected=plan['library']['bytes'], digest=plan['library']['sha256'])
library = C.CDLL(str(library_path))
initialize = library.actql_original_control_initialize
initialize.argtypes = [C.c_int, C.POINTER(C.c_char_p)]; initialize.restype = C.c_int
assert initialize(1, (C.c_char_p * 1)(b'compiler-parent-private-conformance')) == 0
spec = importlib.util.spec_from_file_location('compiler_original_parent_conformance', ROOT/'scripts/compile-python-local-image.py')
compiler = importlib.util.module_from_spec(spec); spec.loader.exec_module(compiler)
control = _OriginalControlFunctions(library)
page = os.sysconf('SC_PAGE_SIZE')
fixture = Path(tempfile.mkdtemp(prefix='actql-compiler-parent-original-', dir='/private/tmp'))
# No old Store/Run/DB or keys. Keep source/FD fixture and its identity as evidence.
(fixture/'packages/python-local-runtime').mkdir(parents=True)
(fixture/'.gitignore').write_text('*.backing\n')
subprocess.run(['git','init','-q'],cwd=fixture,check=True)
engine_body = b'independent compiler-parent fixture; no Engine or VM'
holding = dict(scope='image_compiler_only',module_sha256='0'*64,
    engine_sha256=hashlib.sha256(engine_body).hexdigest(), runtime_library_sha256='0'*64,
    provider_library_sha256=plan['library']['sha256'],capacity_bytes=64*page,generation=7)
path = fixture/'packages/python-local-runtime/selected-compiler-holding.json'
path.write_text(json.dumps(holding,sort_keys=True)+'\n')
base = dict(scope='image_compiler_parent_only',holding_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
    parent=dict(bytes=64*page,work=20,attempts=8,holdings=4,transfer=30,retained=0,execution=64*page,control_envelope=65536),
    child=dict(bytes=48*page,work=2,attempts=1,holdings=1,transfer=3,retained=0,execution=48*page))
recipe = SimpleNamespace(engine_body=engine_body,runtime_library_sha256='0'*64,
    provider_library_sha256=plan['library']['sha256'],provider_library_bytes=plan['library']['bytes'])
compiler.ROOT = fixture
parents=[];descriptors=[];cases=[]

def original(body):
    (fixture/'packages/python-local-runtime/selected-compiler-parent.json').write_text(json.dumps(body,sort_keys=True)+'\n')
    subprocess.run(['git','add','.'],cwd=fixture,check=True)
    subprocess.run(['git','-c','user.name=ActQL conformance','-c','user.email=conformance@invalid.local',
                    'commit','-qm','test: retain independent compiler parent fixture'],cwd=fixture,check=True)
    source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=fixture,text=True).strip()
    value=dict(source=source,module_sha256='0'*64,recipe=recipe,provider_library=library_path)
    return value,compiler._compiler_holding_original(value)

def descriptor(name):
    value=_OriginalDescriptor(os.open(fixture/name,os.O_RDWR|os.O_CREAT|os.O_EXCL,0o600))
    descriptors.append(value);os.ftruncate(value.value,64*page)
    return value

# 1: Real source-bound selection -> real Native Ledger/acquire/backing/domain.
value,selected=original(base);fd=descriptor('first.backing')
parent=compiler._acquire_compiler_parent(value,selected,fd);parents.append(parent)
material=parent.domain._project_original_material(_OriginalDomainMaterialFunctions(library))
assert material.source == value['source'] and material.recipe == parent.original.recipe
assert material.scalars[0] == 7 and parent.domain._descriptor is fd
assert parent.domain._owner is parent.host and parent.domain._scope is parent.backing
parent.close_unstarted();parent.close_unstarted();assert parent._closed and not fd.close_attempted
os.fstat(fd.value);fd.close();cases.append('same original source/FD/parent/domain and confirmed unstarted cleanup')

# 2: Same fixed 64-page parent cannot lend all 64 as a child as well as control.
# Only the original Common/Native owner decides this refusal; no new extent.
over=json.loads(json.dumps(base));over['child']['bytes']=over['child']['execution']=64*page
value,selected=original(over);fd=descriptor('exhausted.backing')
try:compiler._acquire_compiler_parent(value,selected,fd)
except compiler.CompilerParentAcquisitionError as failure:
    parent=failure.cleanup_parent;parents.append(parent)
    assert parent.host is not None and parent.backing is not None and parent.domain is not None
    assert parent.domain._unknown is None and not parent.domain._closed
    assert parent.descriptor is fd and not fd.close_attempted
    parent.close_unstarted();assert parent._closed;fd.close()
else:raise AssertionError('Native parent control must remain charged inside the original capacity')
cases.append('same backing capacity refusal retains original partial domain and cleanup')

# 3: Native typed preparation refuses an invalid arena selection without acquire.
try:_OriginalControlCustody._prepare_original(control,source='a'*40,recipe=b'r'*32,generation=7,
    size=64*page,work=20,attempts=8,holdings=4,transfer=30,retained=1,execution=64*page,envelope=65536)
except _OriginalControlError as failure:
    assert not failure.unknown and failure.fact.operation == 1 and failure.fact.issue_family == 1
    assert failure.cleanup_host._closed and not failure.cleanup_host._acquire_started
    failure.cleanup_host.close()
else:raise AssertionError('Native Owner must reject retained quota in this arena selection')
cases.append('typed refused preparation issues no acquired Host')

# 4: Actual C transport rejects malformed bounded copies/nonempty output first.
prepare=bind(library,'actql_control_prepare_utf16_into');source=(C.c_uint16*40)(*map(ord,'a'*40));raw=(C.c_ubyte*32)(*([17]*32))
slot=C.c_void_p()
assert prepare(source,39,raw,32,7,64*page,20,8,4,30,0,64*page,65536,C.byref(slot)) == -2 and slot.value is None
slot.value=1
assert prepare(source,40,raw,32,7,64*page,20,8,4,30,0,64*page,65536,C.byref(slot)) == -2 and slot.value == 1
slot.value=None
cases.append('actual bounded C copy and occupied output refusal')
assert len(cases)==4 and all(p._closed for p in parents) and all(d.closed for d in descriptors)
_read_file(library_path,maximum=16*1024*1024,expected=plan['library']['bytes'],digest=plan['library']['sha256'])
print(json.dumps(dict(discovered=4,executed=4,passed=4,failed=0,skipped=0,cases=cases,
    fixture=str(fixture),product_source=plan['source'],normal_profile=None,
    original_native_compile_source=plan['original_compile_source'],library_sha256=plan['library']['sha256'],
    originals_closed=True,initializer_calls=1,Engine=0,VM=0,worker=0,Run=0,wheel=0,public_E2E=0)),flush=True)
