"""Fresh 1-GiB original-parent conformance, not image or normal admission.

The independent source declaration tests actual parent/domain/process ownership.
It intentionally has no original Wasm module or Engine recipe acceptance.
Old compiler attempts/FDs and the old 64/48-page fixture are never operated on.
"""
from __future__ import annotations

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
sys.path.insert(0, str(ROOT/'packages/python-sdk/src'))
from actql_sdk._local_distribution import _read_file
from actql_sdk._local_native_domain_custody import _OriginalDomainMaterialFunctions
from actql_sdk._local_worker_slot import _OriginalDescriptor

if len(sys.argv) != 3 or sys.argv[2] not in ('domain', 'process'):
    raise ValueError('Select an original initial-parent plan and one case')
plan = json.loads(Path(sys.argv[1]).read_bytes())
case = sys.argv[2]
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == plan['source']
assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)
for item in plan['consumer_inputs']:
    raw = (ROOT/item['path']).read_bytes()
    assert len(raw) == item['bytes'] and hashlib.sha256(raw).hexdigest() == item['sha256']
library = plan['library']
_read_file(Path(library['path']), maximum=16*1024*1024, expected=library['bytes'], digest=library['sha256'])
spec = importlib.util.spec_from_file_location('original_initial_compiler_parent', ROOT/'scripts/compile-python-local-image.py')
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)
fixture = Path(tempfile.mkdtemp(prefix='actql-compiler-initial-parent-', dir='/private/tmp'))
output = Path(plan['output'])
parent = None
descriptor = None
completed = False

def retain_observation():
    (output/(case+'-original-observation.json')).write_text(json.dumps(dict(
        pid=os.getpid(), fixture=str(fixture), completed=completed,
        parent_closed=parent._closed if parent is not None else False,
        descriptor_closed=descriptor.closed if descriptor is not None else False,
        runtime_retirement_ACK=False, process_exit_is_retirement_ACK=False))+'\n')
atexit.register(retain_observation)
(fixture/'packages/python-local-runtime').mkdir(parents=True)
(fixture/'.gitignore').write_text('*.backing\n*.slot\n')
subprocess.run(['git','init','-q'], cwd=fixture, check=True)
# Preserve the existing maintainer 1-GiB operational envelope. These markers
# are independent conformance inputs, never a fabricated Module/Engine proof.
capacity = 1073741824
engine_body = b'independent initial compiler parent; no Engine or module admission'
holding = dict(scope='image_compiler_only', module_sha256='0'*64,
    engine_sha256=hashlib.sha256(engine_body).hexdigest(), runtime_library_sha256='0'*64,
    provider_library_sha256=library['sha256'], capacity_bytes=capacity, generation=1)
holding_path=fixture/'packages/python-local-runtime/selected-compiler-holding.json'
holding_path.write_text(json.dumps(holding,sort_keys=True)+'\n')
selection=dict(scope='image_compiler_parent_only', holding_sha256=hashlib.sha256(holding_path.read_bytes()).hexdigest(),
    parent=dict(bytes=capacity,work=20,attempts=8,holdings=4,transfer=30,
                retained=0,execution=capacity,control_envelope=65536),
    child=dict(kind='initial_execution_domain',work=2,attempts=1,holdings=1,transfer=3))
(fixture/'packages/python-local-runtime/selected-compiler-parent.json').write_text(json.dumps(selection,sort_keys=True)+'\n')
subprocess.run(['git','add','.'],cwd=fixture,check=True)
subprocess.run(['git','-c','user.name=ActQL conformance','-c','user.email=conformance@invalid.local',
                '-c','maintenance.auto=false','commit','-qm','test: retain independent initial compiler parent'],cwd=fixture,check=True)
fixture_source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=fixture,text=True).strip()
recipe=SimpleNamespace(engine_body=engine_body,runtime_library_sha256='0'*64,
    provider_library_sha256=library['sha256'],provider_library_bytes=library['bytes'])
compiler.ROOT=fixture
original=dict(source=fixture_source,module_sha256='0'*64,recipe=recipe,provider_library=Path(library['path']))
selected=compiler._compiler_holding_original(original)
backing=fixture/'original.backing'
descriptor=_OriginalDescriptor(os.open(backing,os.O_RDWR|os.O_CREAT|os.O_EXCL,0o600))
os.ftruncate(descriptor.value,capacity)
initial=os.fstat(descriptor.value)
(output/(case+'-fixture-start.json')).write_text(json.dumps(dict(pid=os.getpid(),fixture=str(fixture),
    backing=str(backing),device=initial.st_dev,inode=initial.st_ino,capacity=capacity,
    product_source=plan['source'],fixture_source=fixture_source,normal_profile=None))+'\n')
try:
    parent=compiler._acquire_compiler_parent(original,selected,descriptor)
    material=parent.domain._project_original_material(_OriginalDomainMaterialFunctions(parent.library))
    assert material.source==fixture_source and material.recipe==parent.original.recipe
    assert material.scalars[0]==1 and material.scalars[1:4]==(initial.st_dev,initial.st_ino,capacity)
    assert 0 < material.scalars[7] < capacity
    assert material.scalars[9:]==(2,1,1,3,0,material.scalars[7])
    assert parent.domain._owner is parent.host and parent.domain._scope is parent.backing
    assert parent.domain._descriptor is descriptor and parent.host._borrowed_fd is descriptor
    if case=='process':
        process=parent.prepare_process(path=str(fixture/'original.slot'),nonce=19)
        assert parent.domain._installed_process_original is process
        process.current()
        # No child has been prepared/spawned. Only the existing original Owner
        # may confirm this unstarted process cleanup and return its references.
        process.close_unstarted()
        assert process._closed and parent.domain._installed_process_original is None
    parent.close_unstarted()
    parent.close_unstarted()
    assert parent._closed and parent.domain._closed and parent.backing._closed and parent.host._closed
    assert not descriptor.close_attempted
    os.fstat(descriptor.value)
    descriptor.close()
    assert descriptor.closed
    parent.runtime.current()
except BaseException as primary:
    if parent is None:
        parent=getattr(primary,'cleanup_parent',None)
    # Preserve every same partial original; no stop/close inference or replay
    # is made by this failure reporter or by this process eventually exiting.
    raise
completed=True
print(json.dumps(dict(case=case,discovered=1,executed=1,passed=1,failed=0,
    pid=os.getpid(),fixture=str(fixture),backing=str(backing),capacity=capacity,
    actual_payload_bytes=material.scalars[7],material=material.scalars,
    product_source=plan['source'],fixture_source=fixture_source,Native_compile_source=plan['native_compile_source'],
    parent_closed=True,descriptor_closed=True,domain_closed=True,unstarted_process_closed=case=='process',
    child_spawned=False,runtime_retirement_ACK=False,compiler_module_admission=False,
    Engine=0,VM=0,wheel=0,public_Local=0,normal_profile=None)))
