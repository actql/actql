import assert from 'node:assert/strict';
import {test} from 'node:test';
import {sitePlanning} from './index.mjs';

const input = {durationMilliseconds: 3n, startupMilliseconds: 2n,
  capacitySupported: true, acceptsTransfer: true,
  transferProviderAvailable: true, transferMilliseconds: 4n,
  transferRequired: [true], sharedTransfer: [false], sourceRevoked: [false],
  estimateAvailable: [true], transferBytes: [8n], retainedBytes: [8n],
  executionBytes: [16n]};

test('packaged common planner counts a distinct copy and stable Site ties', () => {
  assert.deepEqual(sitePlanning.plan(input), {code: 0, durationMilliseconds: 9n});
  assert.equal(sitePlanning.select([9n, 9n], ['runner', 'cloud']), 1);
  assert.equal(sitePlanning.select([9n, 8n], ['cloud', 'runner']), 1);
});

test('unknown, capacity, movement feasibility and invalid copies stay excluded', () => {
  for (const [change, code] of [
    [{durationMilliseconds: null}, 1], [{capacitySupported: false}, 2],
    [{acceptsTransfer: false}, 3], [{transferProviderAvailable: false}, 4],
    [{sourceRevoked: [true]}, 5], [{estimateAvailable: [false]}, 6],
    [{transferBytes: []}, 7],
  ]) assert.deepEqual(sitePlanning.plan({...input, ...change}),
    {code, durationMilliseconds: null});
  assert.equal(sitePlanning.select([], []), -1);
  assert.equal(sitePlanning.select([1n, 2n], ['same', 'same']), -3);
});

test('the public boundary rejects truncation and unbounded input before Moon admission', () => {
  for (const value of [-1n, 9223372036854775808n, 3, '3']) {
    assert.throws(() => sitePlanning.plan({...input, durationMilliseconds: value}),
      /InvalidSitePlanningInput/u);
    assert.throws(() => sitePlanning.select([value], ['cloud']), /InvalidSitePlanningInput/u);
  }
  assert.throws(() => sitePlanning.plan({...input, transferBytes: Array(65).fill(0n)}),
    /InvalidSitePlanningInput/u);
  assert.throws(() => sitePlanning.plan({...input, capacitySupported: 1}), /InvalidSitePlanningInput/u);
  assert.throws(() => sitePlanning.select([1n], ['x'.repeat(257)]), /InvalidSitePlanningInput/u);
});
