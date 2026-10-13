import assert from 'node:assert/strict';
import test from 'node:test';
import {releaseInstalledRowCapture} from './installed-row-capture-cleanup.mjs';

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
