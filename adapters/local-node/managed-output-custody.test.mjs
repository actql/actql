import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {beginManagedFailureProgress, recordManagedFailureExecutionSettled} from
  '../host-common/managed-failure.mjs';
import {closeCompletedLocalManagedOutput, refreshCompletedLocalManagedScratch} from './managed-output-custody.mjs';

for (const result of ['released', 'pending', 'error']) {
  test(`completed Local output keeps original cleanup ownership: ${result}`, async () => {
    let release = result === 'released';
    let closed = false;
    let refreshes = 0;
    const primary = new Error('FixturePhysicalReleaseUnavailable');
    const operations = {
      close() { closed = true; },
      settle() { assert.fail('accepted completion cannot settle another execution'); },
      advance() { assert.fail('cleanup cannot advance Compute'); },
      cleanup_refresh() {
        assert.equal(closed, true);
        refreshes++;
        if (result === 'error' && !release) throw primary;
        return release;
      },
    };
    const progress = beginManagedFailureProgress(moon, true, false);
    recordManagedFailureExecutionSettled(progress);
    if (release) {
      closeCompletedLocalManagedOutput(operations, checked, progress);
      assert.equal(refreshes, 1);
      return;
    }
    let failure;
    assert.throws(() => closeCompletedLocalManagedOutput(operations, checked,
      progress), error => { failure = error; return error.cleanupPending === true; });
    const handle = failure.cleanupHandle;
    assert.equal(handle.status().pending, true);
    await handle.retry();
    assert.equal(handle.status().pending, true);
    if (result === 'error') assert.equal(failure.primaryFailure, primary);
    release = true;
    await handle.retry();
    assert.equal(handle.status().pending, false);
    assert.equal(failure.cleanupHandle, handle);
    const settled = refreshes;
    await handle.retry();
    assert.equal(refreshes, settled, 'release is not charged twice');
  });
}

test('completed Local output drains progressing finite scratch in the original retry', async () => {
  let remaining = 1024;
  let retired = 0n;
  let closes = 0;
  let yielded = false;
  const operations = {
    close() { closes++; },
    settle() { assert.fail('completed execution must not settle again'); },
    advance() { assert.fail('cleanup must not advance Compute'); },
    cleanup_refresh() {
      const slice = Math.min(64, remaining);
      remaining -= slice;
      retired += BigInt(slice);
      return remaining === 0;
    },
    cleanup_progress() { return retired; },
  };
  const progress = beginManagedFailureProgress(moon, true, false);
  recordManagedFailureExecutionSettled(progress);
  let failure;
  assert.throws(() => closeCompletedLocalManagedOutput(operations, checked,
    progress), error => { failure = error; return error.cleanupPending === true; });
  const handle = failure.cleanupHandle;
  setImmediate(() => { yielded = true; });
  const first = handle.retry();
  assert.equal(handle.retry(), first, 'concurrent callers share the original cleanup flight');
  await first;
  assert.equal(handle.status().pending, false);
  assert.equal(remaining, 0);
  assert.equal(yielded, true, 'bounded slices yield to the event loop');
  assert.equal(failure.cleanupHandle, handle);
  assert.equal(closes, 2, 'retry drives cleanup, not another close or Compute');
  const completed = retired;
  await handle.retry();
  assert.equal(retired, completed);
});

test('completed Local output stops automatic drain at a physical cleanup stall', async () => {
  let refreshes = 0;
  let released = false;
  const operations = {
    close() {},
    settle() { assert.fail('completed execution must not settle again'); },
    cleanup_refresh() { refreshes++; return released; },
    cleanup_progress() { return 64n; },
  };
  const progress = beginManagedFailureProgress(moon, true, false);
  recordManagedFailureExecutionSettled(progress);
  let failure;
  assert.throws(() => closeCompletedLocalManagedOutput(operations, checked,
    progress), error => { failure = error; return error.cleanupPending === true; });
  const handle = failure.cleanupHandle;
  const before = refreshes;
  await handle.retry();
  assert.equal(handle.status().pending, true);
  assert.ok(refreshes - before <= 2, 'an unchanged physical owner is not polled indefinitely');
  released = true;
  await handle.retry();
  assert.equal(handle.status().pending, false);
});

const {continueLocalManagedFailureCleanup} = await import('./managed-output-custody.mjs');
for (const mode of ['finite', 'blocked', 'stalled', 'error', 'blocked-after-yield']) {
  test(`failed Local finalization continues only original runnable cleanup: ${mode}`, async () => {
    let cursor = 0n, retries = 0, released = false, blocked = mode === 'blocked';
    const primary = Object.assign(new Error('OriginalFinalizationFailure'), {code: 'OriginalFinalizationFailure'});
    const failure = Object.assign(new Error('OwnedFailure', {cause: primary}), {
      primaryFailure: primary, cleanupPending: true,
      cleanupHandle: {
        status() { return {pending: !released, errors: []}; },
        async retry() {
          retries++;
          assert.equal(released, false);
          if (mode === 'error') return {pending: true, errors: [new Error('CleanupError')]};
          if (mode !== 'stalled') cursor += 64n;
          if (cursor >= 640n) released = true;
          failure.cleanupPending = !released;
          return {pending: !released, errors: []};
        },
      },
    });
    const handle = failure.cleanupHandle;
    const operations = {
      cleanup_local_continuation() { return blocked ? -1n : cursor; },
      advance() { assert.fail('cleanup must not repeat Compute'); },
      request_cancel() { assert.fail('cleanup must not replace cancellation authority'); },
    };
    let yielded = false;
    setTimeout(() => { yielded = true; if (mode === 'blocked-after-yield') blocked = true; }, 0);
    assert.equal(await continueLocalManagedFailureCleanup(failure, operations), failure);
    assert.equal(failure.primaryFailure, primary);
    assert.equal(primary.code, 'OriginalFinalizationFailure');
    assert.equal(failure.cleanupHandle, handle);
    if (mode === 'finite') {
      assert.equal(retries, 10); assert.equal(released, true); assert.equal(yielded, true);
    } else {
      assert.equal(released, false);
      assert.ok(retries <= 1, 'blocked or non-progressing owner is not polled');
    }
  });
}

test('failure continuation shares one flight and retains reservation until release witness', async () => {
  let cursor = 0n, charged = true, retries = 0, cancellationRequested = false;
  const failure = {cleanupHandle: {
    status() { return {pending: charged, errors: []}; },
    async retry() {
      assert.equal(charged, true, 'no early reservation refund');
      retries++; cursor += 64n;
      if (cursor === 640n) charged = false;
      return {pending: charged, errors: []};
    },
  }};
  const operations = {cleanup_local_continuation: () => cursor};
  setTimeout(() => {cancellationRequested = true;}, 0);
  const first = continueLocalManagedFailureCleanup(failure, operations);
  assert.equal(continueLocalManagedFailureCleanup(failure, operations), first);
  await first;
  assert.equal(cancellationRequested, true, 'cancellation can run between cleanup slices');
  assert.equal(charged, false); assert.equal(retries, 10);
});

for (const witness of [-1n, 0xffffffffffffffffn, 1n << 64n, -(1n << 63n) - 1n]) {
  test(`failure continuation refuses blocked or invalid Int64 witness ${witness}`, async () => {
    let retries = 0;
    const failure = {cleanupHandle: {
      status: () => ({pending: true, errors: []}),
      async retry() { retries++; return {pending: true, errors: []}; },
    }};
    const operations = {cleanup_local_continuation: () => witness};
    assert.equal(await continueLocalManagedFailureCleanup(failure, operations), failure);
    assert.equal(retries, 0, 'blocked or non-Int64 witness cannot authorize a cleanup slice');
    assert.equal(failure.cleanupHandle.status().pending, true);
  });
}


const {closeCompletedLocalManagedOutputAsync} = await import('./managed-output-custody.mjs');
const {registerManagedMemoryInput} = await import('../store-local/managed-memory-representations.mjs');
for (const mode of ['finite','stalled','error','foreign','negative','overflow']) {
  test(`completed output async close preserves original retirement: ${mode}`, async () => {
    let retired=0n, refreshes=0, closeCalls=0;
    const originalIssue=new Error('OriginalRetirementIssue');
    const operations={
      close(){closeCalls++;},
      settle(){assert.fail('completed execution cannot settle again');},
      advance(){assert.fail('cleanup cannot execute Compute');},
      cleanup_progress(){return mode==='negative'?-1n:mode==='overflow'?(1n<<63n):retired;},
      cleanup_refresh(){
        refreshes++;
        if(mode==='error' && refreshes>=3)throw originalIssue;
        if(mode==='stalled' && refreshes>=3)return false;
        retired+=64n;return retired>=1024n;
      },
    };
    const progress=beginManagedFailureProgress(moon,true,false);
    recordManagedFailureExecutionSettled(progress);
    const material={};
    const memory=registerManagedMemoryInput(material,()=>true,()=>true,{async read(){}},
      ()=>closeCompletedLocalManagedOutput(operations,checked,progress));
    let outer;
    const selected=mode==='foreign'?{...operations}:operations;
    if(mode==='finite') {
      await Promise.all([closeCompletedLocalManagedOutputAsync(selected,checked,progress,memory),
        closeCompletedLocalManagedOutputAsync(selected,checked,progress,memory)]);
      assert.equal(memory.status().released,true);
      assert.equal(retired,1024n);
      const done=refreshes;await memory.close();assert.equal(refreshes,done);
    } else {
      await assert.rejects(closeCompletedLocalManagedOutputAsync(selected,checked,progress,memory),error=>{outer=error;return error.code==='ManagedInputReleaseFailed';});
      if(mode!=='error')assert.equal(memory.status().released,false);
      assert.ok(refreshes<=4,'blocked/nonprogressing cleanup cannot be polled');
      if(mode==='error')assert.ok(outer.primaryFailure.cleanupHandle.status().errors.includes(originalIssue));
    }
    assert.equal(closeCalls,2,'one original release plus managed failure close, never a replacement');
  });
}

test('completed memory retirement refuses copied wrappers and replaced recovery handles', async () => {
  const {managedMemoryReleaseFailureMatches}=await import('../store-local/managed-memory-representations.mjs');
  let retired=0n,retries=0;
  const operations={close(){},settle(){assert.fail('no new settlement');},
    cleanup_progress:()=>retired,cleanup_refresh(){retired+=1n;return false;}};
  const progress=beginManagedFailureProgress(moon,true,false);
  recordManagedFailureExecutionSettled(progress);
  const memory=registerManagedMemoryInput({},()=>true,()=>true,{async read(){}},
    ()=>closeCompletedLocalManagedOutput(operations,checked,progress));
  let failure;await assert.rejects(memory.close(),error=>{failure=error;return true;});
  assert.equal(managedMemoryReleaseFailureMatches(memory,failure),true);
  const copied={...failure};
  const fakeHandle={status:()=>({pending:false,errors:[]}),retry:async()=>{retries++;return {pending:false,errors:[]};}};
  copied.cleanupHandle=fakeHandle;
  const foreign={close:async()=>{throw copied;}};
  await assert.rejects(closeCompletedLocalManagedOutputAsync(operations,checked,progress,foreign),error=>error===copied);
  assert.equal(managedMemoryReleaseFailureMatches(memory,copied),false);
  failure.cleanupHandle=fakeHandle;
  assert.equal(managedMemoryReleaseFailureMatches(memory,failure),false);
  assert.equal(retries,0);
});


test('memory close shares one original failure and never converts error-bearing cleanup to release', async () => {
  let releases=0,retries=0;
  const physicalIssue=new Error('RealCleanupObservationFailure');
  const handle={status:()=>({pending:false,errors:[physicalIssue]}),
    async retry(){retries++;return this.status();}};
  const original=Object.assign(new Error('OriginalPendingClose'),{cleanupPending:true,cleanupHandle:handle});
  const memory=registerManagedMemoryInput({},()=>true,()=>true,{async read(){}},()=>{releases++;throw original;});
  const outcomes=await Promise.allSettled([memory.close(),memory.close(),memory.close()]);
  const failure=outcomes[0].reason;
  assert.ok(outcomes.every(item=>item.status==='rejected' && item.reason===failure));
  assert.equal(failure.primaryFailure,original);
  assert.equal((await failure.cleanupHandle.retry()).pending,true);
  assert.equal(memory.status().released,false);
  await assert.rejects(memory.close(),error=>error===failure);
  await failure.cleanupHandle.retry();
  assert.equal(memory.status().released,false);
  assert.ok(failure.cleanupHandle.status().errors.includes(physicalIssue));
  assert.equal(releases,1);assert.equal(retries,2);
});

test('memory recovery cannot acknowledge a stopped owner with recorded cleanup errors', async () => {
  const physicalIssue=new Error('RecordedStopError');
  const handle={status:()=>({pending:false,errors:[physicalIssue]}),async retry(){return this.status();}};
  const original=Object.assign(new Error('PendingOwner'),{cleanupPending:true,cleanupHandle:handle});
  const memory=registerManagedMemoryInput({},()=>true,()=>true,{async read(){}},()=>{throw original;});
  let failure;await assert.rejects(memory.close(),error=>{failure=error;return true;});
  assert.equal((await failure.cleanupHandle.retry()).pending,true);
  assert.equal(memory.status().released,false);
  await assert.rejects(memory.close());
});


test('completed live Local material refreshes only progressing original scratch without close or ACK', async () => {
  let cursor = 0n, refreshes = 0;
  const operations = {
    close() {assert.fail('successful live output must not close');},
    settle() {assert.fail('no new physical settlement');},
    advance() {assert.fail('no Compute replay');},
    cleanup_refresh() {refreshes++; cursor += 64n; return false;},
    cleanup_local_continuation: () => cursor < 256n ? cursor : -1n,
  };
  assert.equal(await refreshCompletedLocalManagedScratch(operations, () => true), undefined);
  assert.equal(cursor, 256n); assert.equal(refreshes, 4);
});

test('completed scratch refresh stops at original external or nonprogressing custody', async () => {
  for (const witness of [-1n, (1n << 64n) - 1n, 0n, undefined]) {
    let refreshes = 0;
    const operations = {cleanup_refresh() {refreshes++; return false;},
      cleanup_local_continuation: () => witness};
    await refreshCompletedLocalManagedScratch(operations, () => true);
    assert.equal(refreshes, witness === 0n ? 2 : 1);
  }
});

test('completed scratch refresh preserves original errors and stops when its live output closes', async () => {
  const original = new Error('original scratch retirement refusal');
  await assert.rejects(refreshCompletedLocalManagedScratch({
    cleanup_refresh() {throw original;}, cleanup_local_continuation: () => 0n,
  }, () => true), error => error === original);
  let live = true, refreshes = 0;
  const running = refreshCompletedLocalManagedScratch({
    cleanup_refresh() {refreshes++; return false;}, cleanup_local_continuation: () => 1n,
  }, () => live);
  live = false;
  await assert.rejects(running, {message: 'ReleasedLocalManagedOutput'});
  assert.equal(refreshes, 1);
});
