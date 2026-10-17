"""Actual same-provider process/child transport in fresh private fixtures.

The original independent parent4 and its64/48-page declarations remain intact.
The new process cases exercise the existing Native Holder, captured region,
closed argv/env snapshot and typed stop via the ordinary generated ctypes ABI.
No production OriginalWorkerFunding, Engine/VM, Run or service is fabricated.
"""
import atexit
import ctypes as C
import json
import os
from pathlib import Path
import runpy
import select
import time

original = runpy.run_path(str(Path(__file__).with_name('python-native-compiler-parent.py')))
compiler, base, plan = original['compiler'], original['base'], original['plan']
parents, descriptors, cases = original['parents'], original['descriptors'], original['cases']
assert len(cases) == 4
from actql_sdk._local_native_process_custody import (
    _OriginalInstalledProcessCustody as Process,
    _OriginalInstalledProcessFunctions as Functions,
    _OriginalInstalledProcessError as ProcessError,
)
from actql_sdk._local_native_domain_custody import _OriginalDomainError

processes = []

def observe():
    (Path(plan['output'])/'process-original-observation.json').write_text(json.dumps(dict(
        process_closed=[p._closed for p in processes],
        process_unknown=[p._unknown is not None for p in processes],
        parent_closed=[p._closed for p in parents],
        caller_descriptor_closed=[d.closed for d in descriptors],
        process_exit_is_retirement_ACK=False, normal_profile=None))+'\n')
atexit.register(observe)

def acquire(label):
    value, selected = original['original'](base)
    fd = original['descriptor'](label+'.backing')
    parent = compiler._acquire_compiler_parent(value, selected, fd)
    parents.append(parent)
    functions = Functions(parent.library)
    process = Process._prepare_original(parent.domain, functions,
        path=str(original['fixture']/(label+'.slot')), nonce=7,
        retained=0, execution=48*original['page'])
    processes.append(process)
    return parent, fd, process

def finish(parent, fd, process):
    assert process._closed and process._unknown is None
    assert parent.domain._installed_process_original is None
    parent.close_unstarted()
    assert parent._closed and not fd.close_attempted
    os.fstat(fd.value)
    fd.close()

parent, fd, process = acquire('process-unstarted')
functions = process._functions
assert process._domain is parent.domain and process._owner is parent.host
assert process._process.value is not None and process._frame.value is not None
process.current()
cases.append('actual same Host/domain registers its original process, channel and Common frame')

try: parent.domain.current()
except _OriginalDomainError as failure: assert not failure.unknown
else: raise AssertionError('Generic domain current must not bypass original process custody')
try: parent.domain.close_after_stop()
except ValueError: pass
else: raise AssertionError('Parent cannot retire before original process cleanup')
assert parent.domain._unknown is None and not parent._closed
cases.append('actual generic domain refusal and Python parent fence retain original responsibility')

_, facts = process._operate(3)
assert facts[0] >= 0 and facts[1] >= 0 and facts[0] != facts[1]
_, captured = process._operate(9)
assert captured[2] >= 10 and captured[2] != fd.value
assert os.fstat(captured[2]).st_ino == os.fstat(fd.value).st_ino
occupied = C.c_void_p(1)
assert functions.operate(process._host, process._native_domain, process._process,
                         2, C.byref(occupied)) == -2 and occupied.value == 1
assert process._reply.value is None
cases.append('actual captured FD identity and occupied C output refusal preserve original slots')

try: process.prepare_child('/bin/sh', (), (('LANG', 'C'), ('LANG', 'other')))
except ProcessError as failure: assert not failure.unknown and failure.fact.issue_family == 9
else: raise AssertionError('Duplicate selected environment must refuse')
assert process._unknown is None and not process._closed
process.current()
cases.append('actual selected environment refusal is known and original current remains available')

try: process.close_unstarted()
except ProcessError as failure: assert not failure.unknown
else: raise AssertionError('Active endpoint borrow must block early physical cleanup')
assert not process._closed and not parent._closed and not fd.close_attempted
cases.append('actual early cleanup refusal keeps original endpoints, region and parent fenced')

process.restrict_transport(); process.return_transport(); process.close_unstarted()
assert all(slot.value is None for slot in process._slots())
process.close_unstarted()
finish(parent, fd, process)
cases.append('actual same-original unstarted cleanup and typed data retirement precede parent retirement')

parent, fd, process = acquire('process-child')
_, facts = process._operate(3)
writer, reader = facts[:2]
script = 'read token; test "$token" = original && test -f /dev/fd/4 && test "$LANG" = C && printf "native-original\\n"'
process.prepare_child('/bin/sh', ('-c', script), (('LANG', 'C'),))
process.spawn()
assert os.write(writer, b'original\n') == 9
assert select.select([reader], [], [], 2)[0] == [reader]
assert os.read(reader, 64) == b'native-original\n'
process.restrict_transport(); process.return_transport()
for _ in range(500):
    if process.poll_stop(): break
    time.sleep(0.001)
else: raise AssertionError('Original typed process stop was not observed')
process.retire_stopped()
finish(parent, fd, process)
cases.append('actual Native child FD4/selected environment/pipe roundtrip and typed Stop/physical cleanup')

parent, fd, process = acquire('process-known-spawn-refusal')
process.prepare_child(str(original['fixture']/'absent-executable'), (), ())
try: process.spawn()
except ProcessError as failure: assert not failure.unknown and failure.fact.issue_family == 9
else: raise AssertionError('Absent executable must retain original refused spawn')
assert process._unknown is None and not process._closed and process._reply.value is None
process.restrict_transport(); process.return_transport(); process.close_unstarted()
finish(parent, fd, process)
cases.append('actual known failed spawn uses original no-child cleanup without stop or relaunch')

assert len(cases) == 12 and all(p._closed for p in processes)
assert all(p._closed for p in parents) and all(d.closed for d in descriptors)
original['_read_file'](original['library_path'], maximum=16*1024*1024,
    expected=plan['library']['bytes'], digest=plan['library']['sha256'])
print(json.dumps(dict(discovered=12,executed=12,passed=12,failed=0,skipped=0,
    cases=cases,original_parent_cases=4,new_process_cases=8,
    source=plan['source'],library_sha256=plan['library']['sha256'],
    regular_C_source=plan['regular_C_source'],provider_source=plan['actual_provider_compile_source'],
    original_parent_pages=64,original_child_pages=48,actual_test_child=1,
    known_refused_spawn=1,initializer_calls=1,originals_closed=True,
    Engine=0,VM=0,worker=0,OriginalWorkerFunding=0,wheel=0,public_E2E=0,
    normal_profile=None)),flush=True)
