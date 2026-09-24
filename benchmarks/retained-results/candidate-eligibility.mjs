import {workloads} from './fixtures.mjs';

// A sound lower bound for the registered Local reuse program. Each of its
// filter and select steps retains every row and charges every output field
// name and text value to one cumulative output ValueBudget. This proof does
// not use a measured execution time or relax the registered ceiling.
export function registeredLocalEligibility(fixture) {
  if (fixture.workload !== workloads[2] || fixture.layout !== 'text-1024') {
    return Object.freeze({eligible: true});
  }
  const names = fixture.fields.reduce((bytes, name) =>
    bytes + Buffer.byteLength(name, 'utf8'), 0);
  const payload = Buffer.byteLength(fixture.sourceRow(0).payload, 'utf8');
  const minimumTextBytes = 2 * fixture.rows * (names + payload);
  const ceilingTextBytes = fixture.limits.cumulativeValueTextBytes;
  if (minimumTextBytes <= ceilingTextBytes) {
    throw new Error('InvalidRegisteredLocalEligibilityProof');
  }
  return Object.freeze({eligible: false, reason: 'cumulative_output_text_limit',
    minimumTextBytes, ceilingTextBytes,
    scope: 'two mandatory materialized outputs in each Local reuse task'});
}
