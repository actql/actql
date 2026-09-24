import test from 'node:test';
import assert from 'node:assert/strict';
import {retainedCase, workloads} from './fixtures.mjs';
import {registeredLocalEligibility} from './candidate-eligibility.mjs';

test('registered text reuse exceeds cumulative Local output text budget', () => {
  for (const rows of [100, 1000, 10000, 100000]) {
    const fixture = retainedCase(workloads[2], 'text-1024', rows);
    assert.deepEqual(registeredLocalEligibility(fixture), {
      eligible: false, reason: 'cumulative_output_text_limit',
      minimumTextBytes: 2066 * rows, ceilingTextBytes: 2048 * rows,
      scope: 'two mandatory materialized outputs in each Local reuse task',
    });
  }
});

test('other registered candidates are not excluded by this proof', () => {
  for (const workload of workloads) {
    for (const layout of ['narrow', 'numeric-64', 'text-1024']) {
      if (workload === workloads[2] && layout === 'text-1024') continue;
      assert.deepEqual(registeredLocalEligibility(
        retainedCase(workload, layout, 100)), {eligible: true});
    }
  }
});
