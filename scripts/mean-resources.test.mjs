import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const fixture = JSON.parse(readFileSync(new URL('../portability/corpus/mean-resource-scopes.json', import.meta.url), 'utf8'));

// These are explicit selected meter traces, independent of a numerical evaluator
// and of its implementation-specific instruction costs.
test('mean resource contracts cover all samples and exact accumulator growth', () => {
  assert.deepEqual(fixture.aggregation, ['sum', 'sum', 'sum', 'peak', 'peak']);
  for (const sample of fixture.cases) {
    const usage = fixture.meters.map(() => 0);
    for (const event of sample.trace) {
      assert.equal(event.length, usage.length);
      event.forEach((v, i) => {
        assert.ok(Number.isSafeInteger(v) && v >= 0);
        usage[i] = fixture.aggregation[i] === 'sum' ? usage[i] + v : Math.max(usage[i], v);
      });
    }
    assert.deepEqual(usage, sample.usage, sample.name);
    assert.equal(sample.complete && usage.every((v, i) => v <= sample.limits[i]), sample.accept, sample.name);
  }
  const repeated = fixture.cases.find(c => c.name === 'no-exact-budget-reset');
  assert.ok(repeated.trace.every(e => e[1] <= repeated.limits[1]));
  assert.equal(repeated.accept, false);
});
