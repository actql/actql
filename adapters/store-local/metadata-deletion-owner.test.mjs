import test from 'node:test';
import assert from 'node:assert/strict';
import {createMetadataDeletionOwner} from './metadata-deletion-owner.mjs';

const failure = code => Object.assign(new Error(code), {code});

function fixture() {
  const calls = [];
  let busy = Promise.resolve();
  let resultReady = true;
  let holdingReady = true;
  let syncFailures = 0;
  let reclaimed = false;
  const marker = Object.freeze({
    results: Object.freeze(['result']),
    physical_holding_cids: Object.freeze(['holding']),
    contract_objects: Object.freeze(['contract']),
  });
  const owner = createMetadataDeletionOwner(marker, {
    serialize(run) {
      const operation = busy.then(run);
      busy = operation.catch(() => {});
      return operation;
    },
    async syncObjects() {
      calls.push('sync');
      if (syncFailures-- > 0) throw failure('SYNC_FAILED');
    },
    releaseUnconfirmed(objects) {
      calls.push(`account:${[...objects.values()].join(',')}`);
    },
    async retireResult() { calls.push('result'); return resultReady; },
    async retireHolding() { calls.push('holding'); return holdingReady; },
    async removeRunDirectories() { calls.push('run'); },
    async removeIndex() { calls.push('index'); },
    async reclaimContract(_object, unconfirmed) {
      calls.push('contract');
      if (!reclaimed) {
        unconfirmed.set('object', 17);
        reclaimed = true;
      }
    },
    async removeResultDeletionDirectory() { calls.push('results-directory'); },
    async removeInventory() { calls.push('inventory'); },
    async compactMarker() { calls.push('compact'); },
    settle() { calls.push('settle'); },
  });
  return {
    owner,
    calls,
    setResultReady(value) { resultReady = value; },
    setHoldingReady(value) { holdingReady = value; },
    failSync() { syncFailures++; },
  };
}

test('reader and holding retention stop before metadata removal', async () => {
  const {owner, calls, setResultReady, setHoldingReady} = fixture();
  setResultReady(false);
  assert.equal((await owner.retry()).pending, true);
  assert.deepEqual(calls, ['result']);
  setResultReady(true);
  setHoldingReady(false);
  assert.equal((await owner.retry()).pending, true);
  assert.deepEqual(calls, ['result', 'result', 'holding']);
  setHoldingReady(true);
  assert.equal((await owner.retry()).pending, false);
  assert.equal(calls.filter(call => call === 'compact').length, 1);
});

test('unlink durability failure retains capacity and retries only its sync',
  async () => {
    const {owner, calls, failSync} = fixture();
    failSync();
    await assert.rejects(owner.retry(), {code: 'SYNC_FAILED'});
    assert.equal(owner.status().pending, true);
    assert.equal(owner.status().errors.length, 1);
    assert.equal(calls.some(call => call.startsWith('account:')), false);
    assert.equal((await owner.retry()).pending, false);
    assert.equal(calls.filter(call => call === 'account:17').length, 1);
    assert.equal(calls.filter(call => call === 'compact').length, 1);
  });

test('concurrent retries do not compact or release capacity twice',
  async () => {
    const {owner, calls} = fixture();
    const results = await Promise.all([owner.retry(), owner.retry()]);
    assert.deepEqual(results.map(result => result.pending), [false, false]);
    assert.equal(calls.filter(call => call === 'account:17').length, 1);
    assert.equal(calls.filter(call => call === 'compact').length, 1);
    assert.equal(calls.filter(call => call === 'settle').length, 1);
    assert.equal((await owner.retry()).pending, false);
    assert.equal(calls.filter(call => call === 'compact').length, 1);
  });
