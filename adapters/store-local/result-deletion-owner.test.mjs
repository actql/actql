import test from 'node:test';
import assert from 'node:assert/strict';
import {createResultDeletionOwner} from './result-deletion-owner.mjs';

const failure = code => Object.assign(new Error(code), {code});

function fixture() {
  const calls = [];
  let retention = 'free';
  let allocation = 'exclusive';
  let syncFailures = 0;
  let unlinkFailures = 0;
  let busy = Promise.resolve();
  const operations = {
    serialize(run) {
      calls.push('serialize');
      const operation = busy.then(run);
      busy = operation.catch(() => {});
      return operation;
    },
    async ensureMarker() { calls.push('marker'); },
    async retention() { calls.push('retention'); return retention; },
    markReclaiming() { calls.push('reclaiming'); },
    async inspectAllocation() { calls.push('inspect'); return allocation; },
    async unlink() {
      calls.push('unlink');
      if (unlinkFailures-- > 0) throw failure('UNLINK_FAILED');
    },
    async syncObjects() {
      calls.push('sync');
      if (syncFailures-- > 0) throw failure('SYNC_FAILED');
    },
    releaseCapacity() { calls.push('account'); },
    settle(clearReclaiming) {
      calls.push(clearReclaiming ? 'settle-reclaim' : 'settle-reference');
    },
  };
  return {
    owner: createResultDeletionOwner(operations),
    calls,
    setRetention: value => { retention = value; },
    setAllocation: value => { allocation = value; },
    failSync: () => { syncFailures++; },
    failUnlink: () => { unlinkFailures++; },
  };
}

test('active readers retain deletion without unlink or capacity release',
  async () => {
    const {owner, calls, setRetention} = fixture();
    setRetention('wait');
    assert.equal((await owner.retry()).pending, true);
    assert.deepEqual(calls, ['serialize', 'marker', 'retention']);
    setRetention('free');
    assert.equal((await owner.retry()).pending, false);
    assert.deepEqual(calls.slice(3), [
      'serialize', 'marker', 'retention', 'reclaiming', 'inspect', 'unlink',
      'sync', 'account', 'settle-reclaim',
    ]);
    assert.equal((await owner.retry()).pending, false);
    assert.equal(calls.filter(call => call === 'account').length, 1);
  });

test('unlink failure keeps the exact allocation for retry', async () => {
  const {owner, calls, failUnlink} = fixture();
  failUnlink();
  await assert.rejects(owner.retry(), {code: 'UNLINK_FAILED'});
  assert.equal(owner.status().pending, true);
  assert.equal(owner.status().errors.length, 1);
  assert.equal((await owner.retry()).pending, false);
  assert.equal(calls.filter(call => call === 'unlink').length, 2);
  assert.equal(calls.filter(call => call === 'account').length, 1);
});

test('sync failure retries durability without a second unlink or early release',
  async () => {
    const {owner, calls, failSync} = fixture();
    failSync();
    await assert.rejects(owner.retry(), {code: 'SYNC_FAILED'});
    assert.equal(owner.status().pending, true);
    assert.equal(calls.filter(call => call === 'account').length, 0);
    assert.equal((await owner.retry()).pending, false);
    assert.equal(calls.filter(call => call === 'unlink').length, 1);
    assert.equal(calls.filter(call => call === 'sync').length, 2);
    assert.equal(calls.filter(call => call === 'account').length, 1);
  });

test('shared or absent allocation settles without releasing Store capacity',
  async () => {
    for (const allocation of ['shared', 'missing']) {
      const {owner, calls, setAllocation} = fixture();
      setAllocation(allocation);
      assert.equal((await owner.retry()).pending, false);
      assert.equal(calls.includes('unlink'), false);
      assert.equal(calls.includes('account'), false);
      assert.equal(calls.at(-1), 'settle-reclaim');
    }
  });

test('another live reference settles this deletion without reclaiming',
  async () => {
    const {owner, calls, setRetention} = fixture();
    setRetention('settled');
    assert.equal((await owner.retry()).pending, false);
    assert.deepEqual(calls, [
      'serialize', 'marker', 'retention', 'settle-reference',
    ]);
  });

test('concurrent retries unlink and release capacity only once', async () => {
  const {owner, calls} = fixture();
  const results = await Promise.all([owner.retry(), owner.retry()]);
  assert.deepEqual(results.map(result => result.pending), [false, false]);
  assert.equal(calls.filter(call => call === 'unlink').length, 1);
  assert.equal(calls.filter(call => call === 'account').length, 1);
});
