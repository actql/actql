import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareOrdinarySourceManagedInstallation} from './ordinary-source-managed.mjs';

test('ordinary producers have no cumulative lifetime issuance limit after completed requests', async () => {
  const originals = Object.freeze({});
  const first = await prepareOrdinarySourceManagedInstallation(originals, {validator() {}}, false);
  const second = await prepareOrdinarySourceManagedInstallation(Object.freeze({}), {validator() {}}, false);
  let last;
  for (let index = 0; index < 4098; index++) {
    const receipt = first.beforeSourceSnapshot('aql', 'SELECT 1');
    const body = Object.freeze({index});
    const request = Object.freeze({index});
    first.bindSourceSnapshot(receipt, body);
    first.bindSourceRequest(receipt, body, request);
    first.finishSourceProducer(receipt, index % 2 === 0 ? 'returned' : 'failed');
    last = receipt;
  }
  assert.throws(() => second.bindSourceSnapshot(last, {}), {code: 'ForeignInstalledSourceProducer'});
  assert.throws(() => first.bindSourceSnapshot(Object.freeze({}), {}), {code: 'ForeignInstalledSourceProducer'});
  const next = first.beforeSourceSnapshot('aql', 'SELECT 2');
  first.finishSourceProducer(next, 'returned');
  assert.deepEqual(await first.close(), {pending: false});
  assert.throws(() => first.beforeSourceSnapshot('aql', 'SELECT 3'), {code: 'SourceManagedPreparationUnavailable'});
  const independent = second.beforeSourceSnapshot('aql', 'SELECT 4');
  second.finishSourceProducer(independent, 'returned');
  assert.deepEqual(await second.close(), {pending: false});
});
