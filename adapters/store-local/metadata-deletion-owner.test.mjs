import test from 'node:test';
import assert from 'node:assert/strict';
import {createMetadataDeletionOwner} from './metadata-deletion-owner.mjs';

const failure = code => Object.assign(new Error(code), {code});

function fixture() {
  const calls = [];
  let busy = Promise.resolve();
  let resultReady = true;
  let holdingReady = true;
  const syncFailures = [];
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
      if (syncFailures.length !== 0) throw syncFailures.shift();
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
        calls.push('retain-contract');
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
    failSync(error = failure('SYNC_FAILED')) { syncFailures.push(error); },
    failSyncWith(error) { syncFailures.push(error); },
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

test('metadata cleanup keeps first/latest original diagnostics through repeated failure without releasing custody', async () => {
  const f = fixture(), first = Object.freeze(new Error('original first sync failure'));
  const failures = [first, undefined, first, 'primitive sync failure', Object.freeze(new Error('original last sync failure'))];
  const snapshots = [];
  for (let index = 0; index < failures.length; index++) {
    f.failSyncWith(failures[index]);
    await f.owner.retry().then(() => assert.fail('Expected original sync refusal'),
      error => assert.equal(error, failures[index]));
    const status = f.owner.status(); snapshots.push(status);
    assert.equal(status.pending, true);
    assert.deepEqual(status.errors, index === 0 ? [first] : [first, failures[index]]);
    assert.ok(Object.isFrozen(status) && Object.isFrozen(status.errors));
    assert.equal(f.calls.some(call => call.startsWith('account:')), false);
    assert.equal(f.calls.includes('settle'), false);
    for (let old = 0; old < snapshots.length; old++) {
      assert.deepEqual(snapshots[old].errors, old === 0 ? [first] : [first, failures[old]]);
    }
  }
  const finished = await f.owner.retry();
  assert.equal(finished.pending, false);
  assert.deepEqual(finished.errors, [first, failures.at(-1)]);
  assert.equal(f.calls.filter(call => call === 'account:17').length, 1);
  assert.equal(f.calls.filter(call => call === 'retain-contract').length, 1);
  assert.equal(f.calls.filter(call => call === 'settle').length, 1);
});
