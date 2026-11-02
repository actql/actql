import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareInstalledRowCaptureChild, retainInstalledRowCaptureChild, releaseInstalledRowCapture} from './installed-row-capture-cleanup.mjs';
import {releasePreparedResults} from '../host-common/completed-run-publication.mjs';

// Explicit Common progress-law doubles, matching the existing cleanup tests.
// The actual prepared cleanup owner remains the production implementation.
const control = {
  publicationPreparedReleaseAction(index, count, inspected, pending, attempted) {
    if (index < 0) return 'finished';
    if (!inspected) return 'inspect';
    return pending && !attempted ? 'release' : 'advance';
  },
  publicationCleanupOwnerAction(index, count, inspected, pending, available, attempted) {
    if (index >= count) return 'finished';
    if (!inspected) return 'inspect';
    return pending && available && !attempted ? 'retry' : 'advance';
  },
};
function payload(name, events, failures = 0) {
  let pending = true;
  const release = async () => {
    events.push(name);
    if (failures-- > 0) throw new Error(`release:${name}`);
    pending = false;
  };
  return {prepared: {release, retry: release, status: () => ({pending})}};
}

test('retired original capture children are observed linearly across all dependent payloads', async () => {
  const count = 12, children = [], events = [];
  let observations = 0;
  for (let index = 0; index < count; index++) {
    let pending = true;
    const release = () => {pending = false;};
    await prepareInstalledRowCaptureChild({children, create: () => ({
      prepare() {}, release, retry: release, status: () => ({pending})})});
    const original = children[index].prepared;
    await original.release();
    children[index].prepared = Object.freeze({...original,
      status() {observations++; return original.status();}});
  }
  const primary = new Error('original completed capture');
  await assert.rejects(releaseInstalledRowCapture({children, control,
    payloads: Array.from({length: count}, (_, index) => payload(`source:${index}`, events)),
    releaseResults() {events.push('results');}, releaseInputs() {events.push('inputs');}}, primary),
  error => error === primary);
  assert.equal(events.length, count + 2);
  assert.equal(observations, count * 3, 'one original retirement scan plus initial/final owner inspection');
});

test('one cleanup status and retry result each observe the original owner once per boundary', async () => {
  const calls = [0, 0], owners = calls.map((_, index) => ({prepared: {
    status() {calls[index]++; return {pending: true, outcome: 'retained', errors: []};},
    release() {return false;}, retry() {return false;},
  }}));
  let failure;
  await assert.rejects(releasePreparedResults(owners, new Error('original'), control), error => {
    failure = error; return error.cleanupPending === true;
  });
  calls.fill(0);
  assert.deepEqual(failure.cleanupHandle.status(), {pending: true, outcome: 'retained', errors: []});
  assert.deepEqual(calls, [1, 1]);
  calls.fill(0);
  assert.equal((await failure.cleanupHandle.retry()).pending, true);
  assert.deepEqual(calls, [2, 2], 'original inspection and one post-retry observation are separate boundaries');
});

test('retirement cursor retains a newly appended pending original before any parent release', async () => {
  let appended = false, pending = true, released = false, failure;
  const children = [{prepared: {status() {
    if (!appended) {
      appended = true;
      children.push({prepared: {status: () => ({pending}), release() {}, retry() {}}});
    }
    return {pending: false};
  }, release() {}, retry() {}}}];
  const primary = new Error('original append during observation');
  await assert.rejects(releaseInstalledRowCapture({children, control,
    releaseInputs() {released = true;}}, primary), error => {failure = error; return error.cleanupPending;});
  assert.equal(released, false); assert.equal(failure.cleanupHandle.status().pending, true);
  pending = false;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(released, true);
});

test('synchronous original child release reentry cannot start a second release before its flight is retained', async () => {
  const children = [];
  let calls = 0, pending = true, reentered;
  await prepareInstalledRowCaptureChild({children, create: () => ({prepare() {},
    release() {
      calls++;
      if (calls === 1) reentered = children[0].prepared.release();
      pending = false;
    }, retry() {assert.fail('No retry required');}, status: () => ({pending})})});
  await children[0].prepared.release(); await reentered;
  assert.equal(calls, 1); assert.equal(children[0].prepared.status().pending, false);
});

test('synchronous original parent release reentry keeps the same outer retry and pending result', async () => {
  let calls = 0, failure, reentered;
  const primary = new Error('original pending input');
  await assert.rejects(releaseInstalledRowCapture({control, releaseInputs() {
    calls++;
    if (calls === 1) return false;
    if (calls === 2) reentered = failure.cleanupHandle.retry();
  }}, primary), error => {failure = error; return error.cleanupPending;});
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  await reentered;
  assert.equal(calls, 2); assert.equal(failure.cleanupHandle.status().pending, false);
});

test('synchronous original payload release reentry cannot replace its retained callback receiver', async () => {
  let calls = 0, pending = true, childPending = true, failure, reentered;
  const original = {status: () => ({pending}), release() {
    assert.equal(this, original); calls++;
    if (calls === 1) reentered = failure.cleanupHandle.retry();
    pending = false;
  }, retry() {assert.fail('The first actual payload release is not a retry');}};
  const children = [{prepared: {status: () => ({pending: childPending}), release() {}, retry() {}}}];
  await assert.rejects(releaseInstalledRowCapture({control, children,
    payloads: [{prepared: original}]}, new Error('original payload pending')),
  error => {failure = error; return error.cleanupPending;});
  assert.equal(calls, 0); childPending = false;
  assert.equal((await failure.cleanupHandle.retry()).pending, false); await reentered;
  assert.equal(calls, 1); assert.equal(failure.cleanupHandle.status().pending, false);
});

test('failed first payload does not skip siblings, public Results or input pins', async () => {
  const events = [], a = payload('a', events, 1), b = payload('b', events);
  const primary = Object.freeze(new Error('original-capture-failure'));
  let failure;
  await assert.rejects(releaseInstalledRowCapture({payloads: [a, b], control,
    releaseResults: async () => { events.push('results'); },
    releaseInputs: () => { events.push('inputs'); }}, primary), error => {
    failure = error;
    return error.primaryFailure === primary && error.cleanupPending === true;
  });
  assert.deepEqual(events, ['a', 'b', 'results', 'inputs']);
  assert.equal(b.prepared.status().pending, false);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.match(failure.cleanupErrors[0].message, /release:a/u);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.deepEqual(events, ['a', 'b', 'results', 'inputs', 'a']);
});

test('Result and input release failures retain independent retry ownership', async () => {
  const events = [], a = payload('a', events);
  let results = 0, inputs = 0, failure;
  await assert.rejects(releaseInstalledRowCapture({payloads: [a], control,
    releaseResults: async () => {
      events.push('results');
      if (++results === 1) throw new Error('result-release');
    }, releaseInputs: () => {
      events.push('inputs');
      if (++inputs === 1) throw new Error('input-release');
    }}, 'original primitive failure'), error => {
    failure = error;
    return error.primaryFailure === 'original primitive failure';
  });
  assert.deepEqual(events, ['a', 'results', 'inputs']);
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.deepEqual(events, ['a', 'results', 'inputs', 'inputs', 'results']);
});

test('nested preexisting cleanup custody survives the new capture failure drain', async () => {
  const events = [];
  let nestedPending = true;
  const primary = Object.freeze({code: 'original', cleanupPending: true,
    cleanupHandle: {status: () => ({pending: nestedPending}),
      async retry() { events.push('nested'); nestedPending = false; }}});
  let failure;
  await assert.rejects(releaseInstalledRowCapture({control,
    releaseResults: async () => { events.push('results'); }}, primary), error => {
    failure = error;
    return error.primaryFailure === primary;
  });
  assert.deepEqual(events, ['results']);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.deepEqual(events, ['results', 'nested']);
});

test('concurrent retries share original Result release flight and false remains pending', async () => {
  let calls = 0, resume, failure;
  await assert.rejects(releaseInstalledRowCapture({control,
    releaseResults: async () => {
      calls++;
      if (calls === 1) return false;
      await new Promise(resolve => { resume = resolve; });
    }}, new Error('primary')), error => { failure = error; return error.cleanupPending; });
  const first = failure.cleanupHandle.retry(), second = failure.cleanupHandle.retry();
  assert.equal(calls, 2);
  resume();
  await Promise.all([first, second]);
  assert.equal(calls, 2);
  assert.equal(failure.cleanupHandle.status().pending, false);
});

test('successful independent cleanup rethrows the exact primary without wrapping', async () => {
  const primary = Object.freeze(new Error('unchanged'));
  const events = [];
  await assert.rejects(releaseInstalledRowCapture({payloads: [payload('a', events)],
    control, releaseResults: async () => { events.push('results'); }}, primary),
  error => error === primary);
  assert.deepEqual(events, ['a', 'results']);
});

test('request child is retained before current refusal and blocks every parent until actual retirement', async () => {
  const children = [], events = [];
  let current = true, allowed = false, prepares = 0, released = false, failure;
  const primary = Object.freeze(new Error('original-current-changed'));
  const child = {prepare() { prepares++; },
    async release() { events.push('child'); if (!allowed) return false; released = true; },
    async retry() { events.push('child-retry'); if (!allowed) return false; released = true; },
    status: () => ({pending: !released})};
  await assert.rejects(prepareInstalledRowCaptureChild({children,
    create() { current = false; return child; },
    assertCurrent() { if (!current) throw primary; }}), error => error === primary);
  assert.equal(prepares, 0);
  assert.equal(children.length, 1);
  assert.equal(children[0].prepared.status().pending, true);
  const parent = payload('source', events);
  await assert.rejects(releaseInstalledRowCapture({children, payloads: [parent], control,
    releaseResults() { events.push('results'); },
    releaseInputs() { events.push('inputs'); }}, primary), error => {
    failure = error;
    return error.primaryFailure === primary && error.cleanupPending === true;
  });
  assert.deepEqual(events, ['child']);
  assert.equal(parent.prepared.status().pending, true);
  allowed = true;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.deepEqual(events, ['child', 'child-retry', 'inputs', 'results', 'source']);
  assert.equal(children[0].prepared.status().pending, false);
  assert.equal(prepares, 0);
});

test('a pending child does not skip independent child siblings or permit early parent release', async () => {
  const children = [], events = [];
  let allowed = false, failure;
  for (const name of ['a', 'b']) {
    let pending = true;
    const release = async () => {
      events.push(name);
      if (name === 'a' && !allowed) return false;
      pending = false;
    };
    await prepareInstalledRowCaptureChild({children, create: () => ({
      prepare: () => name, release, retry: release, status: () => ({pending})})});
  }
  const primary = Object.freeze(new Error('original-capture'));
  await assert.rejects(releaseInstalledRowCapture({children, control,
    payloads: [payload('source', events)],
    releaseInputs() { events.push('inputs'); }}, primary), error => {
    failure = error; return error.cleanupPending;
  });
  assert.deepEqual(events, ['a', 'b']);
  assert.equal(children[1].prepared.status().pending, false);
  allowed = true;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.deepEqual(events, ['a', 'b', 'a', 'inputs', 'source']);
});

test('prepare Promise settlement and child close are separate, including an early close observation', async () => {
  const children = [], events = [];
  let finish, failure, prepares = 0;
  let pending = true;
  const release = async () => { events.push('close'); pending = false; return true; };
  const preparing = prepareInstalledRowCaptureChild({children, create: () => ({
    prepare() { prepares++; return new Promise(resolve => { finish = resolve; }); },
    release, retry: release, status: () => ({pending})})});
  const primary = Object.freeze(new Error('stop-during-prepare'));
  await assert.rejects(releaseInstalledRowCapture({children, control,
    releaseInputs() { events.push('inputs'); }}, primary), error => {
    failure = error; return error.cleanupPending;
  });
  assert.deepEqual(events, ['close']);
  assert.equal(children[0].prepared.status().pending, true,
    'A close callback cannot drop the original unresolved prepare Promise');
  const request = Object.freeze({request: 'original'});
  finish(request);
  assert.strictEqual(await preparing, request);
  assert.equal(children[0].prepared.status().pending, true,
    'A settled request is not the final retirement observation');
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.deepEqual(events, ['close', 'close', 'inputs']);
  assert.equal(prepares, 1);
});

test('post-await cancellation retains the original child and never returns its request', async () => {
  const children = [], controller = new AbortController();
  let finish, closes = 0;
  const preparing = prepareInstalledRowCaptureChild({children, signal: controller.signal,
    create: () => ({prepare: () => new Promise(resolve => { finish = resolve; }),
      release() { closes++; return false; }, retry() { closes++; return false; },
      status: () => ({pending: true})})});
  const primary = Object.freeze(new Error('original-cancel'));
  controller.abort(primary);
  finish({request: 'must-not-be-adopted'});
  await assert.rejects(preparing, error => error === primary);
  assert.equal(children[0].prepared.status().pending, true);
  let failure;
  await assert.rejects(releaseInstalledRowCapture({children, control,
    releaseInputs: () => assert.fail('Cancelled input still has an original borrower')}, primary),
  error => { failure = error; return error.primaryFailure === primary && error.cleanupPending; });
  assert.equal(closes, 1);
  assert.equal(failure.cleanupHandle.status().pending, true);
});

test('child methods are captured once with their original receiver', async () => {
  const children = [], reads = {prepare: 0, release: 0, retry: 0, status: 0};
  const original = {pending: true};
  const methods = {
    prepare() { assert.strictEqual(this, original); return 'exact-request'; },
    release() { assert.strictEqual(this, original); this.pending = false; },
    retry() { assert.strictEqual(this, original); this.pending = false; },
    status() { assert.strictEqual(this, original); return {pending: this.pending}; },
  };
  for (const name of Object.keys(methods)) Object.defineProperty(original, name, {
    configurable: true, get() { reads[name]++; return methods[name]; }});
  assert.equal(await prepareInstalledRowCaptureChild({children, create: () => original}), 'exact-request');
  for (const name of Object.keys(methods)) Object.defineProperty(original, name,
    {value: () => assert.fail('A later method cannot replace the original')});
  const primary = Object.freeze(new Error('primary'));
  await assert.rejects(releaseInstalledRowCapture({children, control}, primary), error => error === primary);
  assert.deepEqual(reads, {prepare: 1, release: 1, retry: 1, status: 1});
  assert.equal(children[0].prepared.status().pending, false);
});

test('malformed returned child stays retained instead of releasing its parents', async () => {
  const children = [];
  await assert.rejects(prepareInstalledRowCaptureChild({children,
    create: () => ({prepare() { assert.fail('Invalid child cannot begin'); }})}),
  {code: 'InvalidInstalledRowRequestChild'});
  assert.equal(children.length, 1);
  assert.equal(children[0].prepared.status().pending, true);
  await assert.rejects(releaseInstalledRowCapture({children, control,
    releaseInputs: () => assert.fail('Unknown child retains the same original parent')}, 'primary'),
  error => error.primaryFailure === 'primary' && error.cleanupPending);
});


test('deferred preparation latches before original current can reenter the SAME retained child', async () => {
  const children=[];let retained,nested,entered=false,prepares=0,pending=true;
  const original={prepare(){prepares++;return 'original';},release(){pending=false;return true;},
    retry(){pending=false;return true;},status:()=>({pending})};
  retained=retainInstalledRowCaptureChild({children,create:()=>original,assertCurrent(){
    if(retained!==undefined&&!entered){entered=true;
      nested=retained.prepare().then(()=>assert.fail('reentered prepare must refuse'),error=>error.code);}
  }});
  assert.equal(await retained.prepare(),'original');
  assert.equal(await nested,'InvalidInstalledRowRequestChild');
  assert.equal(prepares,1);
  await children[0].prepared.release();assert.equal(children[0].prepared.status().pending,false);
});
