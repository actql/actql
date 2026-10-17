"""Actual same-provider channel/frame FFI, with no spawn or funding substitute.

Reuse the unchanged four-case private parent fixture and its actual 64/48-page
Native acquisition. No OriginalWorkerFunding or production worker is fabricated.
The ten additional cases keep original pipes and extra managed aliases through
separate same-caller cleanup. Python syscall/reply fault tests remain distinct.
"""
import ctypes as C
from pathlib import Path
import os
import runpy

# This performs the existing parent4, initializes once, and retains its original
# source/library/failure observation. It has no Engine/VM/worker/Run operation.
original = runpy.run_path(str(Path(__file__).with_name('python-native-compiler-parent.py')))
compiler, base = original['compiler'], original['base']
plan, library = original['plan'], original['library']
parents, descriptors, cases = original['parents'], original['descriptors'], original['cases']
original_case_count = len(cases)
assert original_case_count == 4
from actql_sdk._local_native_live_channel import _OriginalLivePreparationFunctions

functions = _OriginalLivePreparationFunctions(library)
legacy = functions.legacy
value, selected = original['original'](base)
fd = original['descriptor']('channel-frame.backing')
parent = compiler._acquire_compiler_parent(value, selected, fd)
parents.append(parent)
assert parent.host is not None and parent.domain is not None
h, d = parent.domain._host, parent.domain._domain
host, domain, channel, reply = C.c_void_p(), C.c_void_p(), C.c_void_p(), C.c_void_p()
fh, fdomain, fchannel, frame, frame_reply = (C.c_void_p() for _ in range(5))
pipe_fds = [original['_OriginalDescriptor'](number) for _ in range(2) for number in os.pipe()]
descriptors.extend(pipe_fds)
read, write = pipe_fds[0], pipe_fds[3]

def drop_live():
    assert legacy.drop(C.byref(reply), host, domain, channel) == 0
    assert reply.value is None

def live(operation, *, expected_issue=None):
    assert reply.value is None
    assert legacy.operate(host, domain, channel, operation, C.byref(reply)) == 0
    assert legacy.operation(reply) == operation
    issue = legacy.issue(reply)
    if expected_issue is None: assert issue == 0, (operation, issue)
    else: assert issue != 0
    return issue

def resource(operation, retained=0, execution=0, *, refused=False):
    assert frame_reply.value is None
    assert functions.operate(fh, fdomain, fchannel, frame, operation, retained,
                             execution, C.byref(frame_reply)) == 0
    assert functions.operation(frame_reply) == operation
    issue = functions.issue(frame_reply)
    if refused: assert 0 < issue < 10, (operation, issue)
    else: assert issue == 0, (operation, issue)
    return issue

def drop_frame():
    assert functions.drop(C.byref(frame_reply), fh, fdomain, fchannel, frame) == 0
    assert frame_reply.value is None

# 1: Code roots and actual same Host/domain/pipe prepare, before any child.
assert functions.before(h, d, read.value, write.value, 7, C.byref(reply)) == 0
assert legacy.operation(reply) == 10 and legacy.issue(reply) == 0
assert legacy.originals(reply, C.byref(host), C.byref(domain), C.byref(channel)) == 0
assert host.value == h.value and domain.value == d.value and channel.value is not None
drop_live()
cases.append('actual pre-spawn same-original pipes, operation10 and owned channel aliases')

# 2: Pre-spawn pipes are not admitted VM/child authority.
live(3, expected_issue=True); drop_live()
cases.append('actual original pre-spawn channel cannot admit a VM')

# 4: Same channel/ticket creates exactly its existing Common frame, then starts.
assert functions.prepare(host, domain, channel, C.byref(frame_reply)) == 0
assert functions.operation(frame_reply) == 1 and functions.issue(frame_reply) == 0, (functions.operation(frame_reply), functions.issue(frame_reply))
assert functions.originals(frame_reply, C.byref(fh), C.byref(fdomain),
                           C.byref(fchannel), C.byref(frame)) == 0
assert (fh.value, fdomain.value, fchannel.value) == (host.value, domain.value, channel.value)
assert frame.value is not None
drop_frame(); resource(2); drop_frame(); resource(5)
limits = (C.c_int64 * 6)(*([-1]*6))
assert functions.limits(frame_reply, fh, fdomain, fchannel, frame, limits) == 0
assert tuple(limits) == (2, 1, 1, 3, 0, 48*original['page'])
drop_frame()
cases.append('actual original Common frame start and inherited six-field limits')

# 5: C rejects occupied output, wrong role and nonreserve byte amounts before
# a malformed call can claim a new operation or change the immutable output.
occupied = C.c_void_p(1)
assert functions.operate(fh, fdomain, fchannel, frame, 4, 0, 0, C.byref(occupied)) == -2
assert occupied.value == 1
assert functions.operate(fh, fdomain, fchannel, frame, 4, 1, 0, C.byref(frame_reply)) == -2
assert frame_reply.value is None
resource(5); limits[:] = [-1]*6
assert functions.limits(frame_reply, C.c_void_p(), fdomain, fchannel, frame, limits) == -2
assert tuple(limits) == (-1,)*6
drop_frame()
cases.append('actual occupied/closed-amount/wrong-original refusal preserves outputs')

# 6: Reserve only from this child's same original Common subledger. This does
# not acquire any process/control/FD/VM domain, grant or second physical extent.
resource(3, 0, 48*original['page']); drop_frame()
resource(4); drop_frame(); resource(9); drop_frame()
resource(6); drop_frame(); resource(6); drop_frame()
cases.append('actual original bootstrap reservation/current and cumulative reports')

# End parent transport use through the same actual Common frame. This leaves
# the exact original aliases and every pipe open: it is not a physical ACK.
before_restriction = (fh.value, fdomain.value, fchannel.value, frame.value)
resource(10); drop_frame()
assert (fh.value, fdomain.value, fchannel.value, frame.value) == before_restriction
assert not parent._closed and not any(descriptor.closed for descriptor in pipe_fds)
for descriptor in pipe_fds: os.fstat(descriptor.value)
cases.append('actual operation10 restricts same original transport without closing pipes or aliases')

# Restriction refuses fresh current/limit work but keeps the original cleanup
# report and repeat restriction available, without substituting a new frame.
resource(4, refused=True); drop_frame()
resource(5, refused=True); drop_frame()
resource(6); drop_frame(); resource(10); drop_frame()
for operation, retained, execution in ((11, 0, 0), (10, 1, 0), (10, 0, 1)):
    assert functions.operate(fh, fdomain, fchannel, frame, operation, retained,
                             execution, C.byref(frame_reply)) == -2
    assert frame_reply.value is None
assert (fh.value, fdomain.value, fchannel.value, frame.value) == before_restriction
cases.append('actual restricted current refuses, cleanup report remains, closed opcode amounts refuse')

# 7: Logical stop refuses new work; frame aliases cannot be freed using it as
# the channel's physical retirement reply. All original slots remain retained.
resource(7); drop_frame(); resource(4, refused=True)
old_values = (fh.value, fdomain.value, fchannel.value, frame.value, frame_reply.value)
assert functions.finish(C.byref(fh), C.byref(fdomain), C.byref(fchannel), C.byref(frame),
                        C.byref(frame_reply), C.c_void_p()) == -2
assert (fh.value, fdomain.value, fchannel.value, frame.value, frame_reply.value) == old_values
drop_frame()
cases.append('actual logical stop/current refusal cannot retire original frame aliases')

# A rejected child bind deliberately invalidates the original physical channel.
# Test it after all fresh-work counters, retaining that refusal for cleanup;
# it must not be used as the input to a new resource-frame preparation.
# 3: Parent PID is refused and cannot be replaced on a second child bind.
for pid in (os.getpid(), 1):
    assert functions.child(host, domain, channel, pid, C.byref(reply)) == 0
    assert legacy.operation(reply) == 11 and legacy.issue(reply) != 0
    drop_live()
cases.append('actual parent PID and second child binding refuse; no child is created')

# 8: The original fixture never spawned or sent anything. Confirm its exact
# pipes closed, then retire metadata using both exact successful typed replies.
for descriptor in pipe_fds: descriptor.close()
assert all(descriptor.closed for descriptor in pipe_fds)
resource(8)
live(8)
assert functions.finish(C.byref(fh), C.byref(fdomain), C.byref(fchannel), C.byref(frame),
                        C.byref(frame_reply), reply) == 0
assert all(slot.value is None for slot in (fh, fdomain, fchannel, frame, frame_reply))
assert legacy.finish(C.byref(host), C.byref(domain), C.byref(channel), C.byref(reply)) == 0
assert all(slot.value is None for slot in (host, domain, channel, reply))
parent.close_unstarted(); assert parent._closed and not fd.close_attempted
fd.close()
cases.append('actual same-caller pipe closes and typed frame/channel retirement before parent close')
assert len(cases) == 14 and all(p._closed for p in parents) and all(d.closed for d in descriptors)
original['retain_observation']()
print(original['json'].dumps(dict(discovered=14,executed=14,passed=14,failed=0,skipped=0,
    original_parent_cases=4,original_channel_frame_cases=8,new_transport_restriction_cases=2,cases=cases,
    product_source=plan['source'],library_sha256=plan['library']['sha256'],
    original_regular_C_source=plan['regular_C_source'],initializer_calls=1,
    originals_closed=True,normal_profile=None,Engine=0,VM=0,worker=0,Run=0,
    OriginalWorkerFunding=0,wheel=0,public_E2E=0)),flush=True)
