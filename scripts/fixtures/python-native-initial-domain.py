"""Actual first-domain transport in four fresh private component processes.

A disposable 64-page selection tests the existing Owner. It is not the 1-GiB
compiler envelope, a VM/Engine, an installed supplier or a normal profile.
"""
from __future__ import annotations

import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk._local_distribution import _read_file
from actql_sdk._local_native_backing_custody import _OriginalBackingCustody, _OriginalBackingFunctions
from actql_sdk._local_native_control_custody import _OriginalControlCustody, _OriginalControlFunctions
from actql_sdk._local_native_domain_custody import (
    _OriginalDomainCustody, _OriginalDomainError, _OriginalDomainFunctions,
    _OriginalDomainMaterialFunctions,
)
from actql_sdk._local_native_shim_abi import bind
from actql_sdk._local_worker_slot import _OriginalDescriptor

if len(sys.argv) not in (2, 3):
    raise ValueError('Select an original first-domain plan and optional case')
plan = json.loads(Path(sys.argv[1]).read_bytes())
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == plan['source']
assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)
for item in plan['consumer_inputs']:
    raw = (ROOT / item['path']).read_bytes()
    assert len(raw) == item['bytes'] and hashlib.sha256(raw).hexdigest() == item['sha256']
names = ('original', 'retired', 'pending', 'slots')
output = Path(plan['output'])
if len(sys.argv) == 2:
    cases = []
    for case in names:
        result = subprocess.run([sys.executable, '-I', '-B', str(Path(__file__).resolve()), sys.argv[1], case],
            cwd=ROOT, env={'PATH': os.defpath, 'LC_ALL': 'C'}, capture_output=True, text=True, timeout=15)
        (output / (case + '.stdout')).write_text(result.stdout)
        (output / (case + '.stderr')).write_text(result.stderr)
        assert result.returncode == 0, (case, result.returncode)
        record = json.loads(result.stdout.strip().splitlines()[-1])
        assert record['discovered'] == record['executed'] == record['passed'] == 1
        assert record['arena_originals_closed'] and record['FD_closed']
        assert record['process_runtime_retirement_ACK'] is False
        cases.append(record)
    print(json.dumps(dict(discovered=4, executed=4, passed=4, failed=0, cases=cases,
        Source=plan['source'], Native_compile_Source=plan['native_compile_source'],
        Engine=0, VM=0, worker=0, wheel=0, public_E2E=0, normal_profile=None)))
    raise SystemExit(0)
case = sys.argv[2]
assert case in names
library_path = Path(plan['library']['path'])
_read_file(library_path, maximum=16*1024*1024, expected=plan['library']['bytes'], digest=plan['library']['sha256'])
library = C.CDLL(str(library_path))
_read_file(library_path, maximum=16*1024*1024, expected=plan['library']['bytes'], digest=plan['library']['sha256'])
runtime = C.c_void_p()
assert bind(library, 'actql_control_runtime_initialize_into')(C.byref(runtime)) == 0
assert runtime.value is not None
current_runtime = bind(library, 'actql_control_runtime_current')
assert current_runtime(runtime) == 0
fixture = Path(tempfile.mkdtemp(prefix='actql-initial-domain-original-', dir='/private/tmp'))
page = os.sysconf('SC_PAGE_SIZE')
recipe = hashlib.sha256(b'independent initial-domain fixture').digest()
host = _OriginalControlCustody._prepare_original(_OriginalControlFunctions(library),
    source=plan['source'], recipe=recipe, generation=7, size=64*page,
    work=20, attempts=8, holdings=4, transfer=30, retained=0, execution=64*page, envelope=65536)
descriptor = _OriginalDescriptor(os.open(fixture/'first.backing', os.O_RDWR|os.O_CREAT|os.O_EXCL, 0o600))
os.ftruncate(descriptor.value, 64*page)
(output/(case+'-fixture.json')).write_text(json.dumps(dict(pid=os.getpid(), fixture=str(fixture),
    dev=os.fstat(descriptor.value).st_dev, inode=os.fstat(descriptor.value).st_ino, pages=64))+'\n')
owner_descriptor = descriptor
if case == 'pending':
    # The same parent cannot lend an unrelated inode. Its ordinary pending
    # domain must remain reachable until that original Owner retires it.
    owner_descriptor = _OriginalDescriptor(os.open(fixture/'parent.backing', os.O_RDWR|os.O_CREAT|os.O_EXCL, 0o600))
    os.ftruncate(owner_descriptor.value, 64*page)
host.acquire_fd(owner_descriptor)
scope = _OriginalBackingCustody._borrow_original(host, _OriginalBackingFunctions(library))
functions = _OriginalDomainFunctions(library)
material = None
with scope._physical_scope():
    if case == 'slots':
        prepare = bind(library, 'actql_domain_prepare_initial_into')
        slot = C.c_void_p(1)
        assert prepare(host._original, scope._loan, descriptor.value, 2, 1, 1, 3, C.byref(slot)) == -2
        assert slot.value == 1
        slot.value = None
        assert prepare(C.c_void_p(), scope._loan, descriptor.value, 2, 1, 1, 3, C.byref(slot)) == -2
        assert slot.value is None
    try:
        domain = _OriginalDomainCustody._prepare_initial_original(host, scope, descriptor, functions,
            work=2, attempts=1, holdings=1, transfer=3)
    except _OriginalDomainError as refused:
        assert case == 'pending' and not refused.unknown
        assert refused.fact.operation == 1 and refused.fact.issue_family == 6
        domain = refused.cleanup_domain
        assert domain._domain.value is not None and not domain._closed
    else:
        assert case != 'pending'
        domain.transfer()
        material = domain._project_original_material(_OriginalDomainMaterialFunctions(library))
        assert material.source == plan['source'] and material.recipe == recipe
        assert material.scalars[0] == 7 and material.scalars[3] == 64*page
        assert 0 < material.scalars[7] < 64*page
        assert material.scalars[9:] == (2, 1, 1, 3, 0, material.scalars[7])
    assert domain._owner is host and domain._scope is scope and domain._descriptor is descriptor
scope.return_after_stop()
domain.close_after_stop()
assert domain._closed and not descriptor.close_attempted
if case == 'retired':
    later = _OriginalBackingCustody._borrow_original(host, _OriginalBackingFunctions(library))
    with later._physical_scope():
        try:
            _OriginalDomainCustody._prepare_initial_original(host, later, descriptor, functions,
                work=2, attempts=1, holdings=1, transfer=3)
        except _OriginalDomainError as refused:
            assert not refused.unknown and refused.fact.issue_family == 3
            assert refused.cleanup_domain._closed
        else:
            raise AssertionError('Retired first identity cannot become a new first attempt')
    later.return_after_stop()
host.close()
assert host._closed
os.fstat(descriptor.value)
descriptor.close()
if owner_descriptor is not descriptor:
    os.fstat(owner_descriptor.value)
    owner_descriptor.close()
assert descriptor.closed and owner_descriptor.closed and current_runtime(runtime) == 0
print(json.dumps(dict(case=case, discovered=1, executed=1, passed=1, failed=0,
    pid=os.getpid(), fixture=str(fixture), material=material.scalars if material else None,
    arena_originals_closed=True, FD_closed=True, process_runtime_retirement_ACK=False,
    normal_profile=None)))
