import assert from 'node:assert/strict';
import test from 'node:test';
import {operationTargets, assessLatency} from './operation-performance.mjs';

// Independent product acceptance expectations, not values copied from the
// assessor under test. Synthetic samples exercise the oracle, not product speed.
const adopted = {
  'warm-select': {samples: 100, medianMs: 5, p95Ms: 10},
  'warm-result': {samples: 100, medianMs: 5, p95Ms: 10},
  'warm-status': {samples: 100, medianMs: 5, p95Ms: 10},
  'warm-join': {samples: 100, p95Ms: 500},
  'warm-union': {samples: 100, p95Ms: 500},
  'warm-decimal-sum': {samples: 100, p95Ms: 500},
  'cold-existing': {samples: 30, p95Ms: 2000},
  'first-init': {samples: 30, p95Ms: 5000},
  'mock-workflow': {samples: 30, p95Ms: 5000},
};
const cohort = '1'.repeat(64), fixture = '2'.repeat(64), environment = '3'.repeat(64);
function evidence(operation, target) {
  return {operation, mode: 'final', profiled: false, load: 'isolated',
    cohortSha256: cohort, fixtureSha256: fixture, environmentSha256: environment,
    samples: Array.from({length: target.samples}, (_, iteration) => ({
      iteration, wallNs: (target.medianMs ?? target.p95Ms) * 1e6,
      cpuUserUs: 0, cpuSystemUs: 0, cpuScope: 'synthetic-oracle-test',
      cohortSha256: cohort, fixtureSha256: fixture,
      pid: operation === 'cold-existing' ? iteration + 1 : 1,
      hostId: 'same-warm-host', stateId: operation === 'first-init' ? `new-${iteration}` : 'same-state',
      completed: true, verified: true,
    }))};
}

test('all adopted operation targets and sample minima remain exact', () => {
  assert.deepEqual(operationTargets, adopted);
});

for (const [operation, target] of Object.entries(adopted)) {
  test(`${operation} accepts its boundary and refuses a one-nanosecond p95 excess`, () => {
    const row = evidence(operation, target);
    // The upper six of 100, or two of 30, contain the nearest-rank p95.
    const first = Math.ceil(target.samples * 0.95) - 1;
    row.samples.slice(first).forEach(sample => { sample.wallNs = target.p95Ms * 1e6; });
    const at = assessLatency(row);
    assert.equal(at.status, 'passed');
    assert.equal(at.summary.p95Ms, target.p95Ms);
    row.samples.slice(first).forEach(sample => { sample.wallNs += 1; });
    assert.ok(assessLatency(row).failures.includes('p95 latency exceeds target'));
  });

  test(`${operation} cannot replace the required distribution with fewer samples`, () => {
    const row = evidence(operation, target);
    row.samples.pop();
    const result = assessLatency(row);
    assert.equal(result.status, 'incomplete');
    assert.equal(result.summary.p95Ms, null);
    assert.equal(result.summary.minimum, target.samples);
  });

  if (target.medianMs !== undefined) {
    test(`${operation} enforces the independent median below its p95 ceiling`, () => {
      const row = evidence(operation, target);
      row.samples.slice(49).forEach(sample => { sample.wallNs += 1; });
      const result = assessLatency(row);
      assert.ok(result.failures.includes('median latency exceeds target'));
      assert.ok(!result.failures.includes('p95 latency exceeds target'));
    });
  }
}
