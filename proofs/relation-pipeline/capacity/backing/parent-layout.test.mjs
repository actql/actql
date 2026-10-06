import test from 'node:test';
import assert from 'node:assert/strict';
import { parentStartupLayout, inspectParentStartup } from './parent-layout.mjs';
// Synthetic validator fixture, not the saved native execution result.
const fact = () => ({ kind: 'parent control investigation', count: 2, rootBytes: 208,
  callbackBytes: 248, childrenContainerBytes: 40, completedContainerBytes: 48, knownOwnedLowerBytes: 544,
  matchedEnvironment: 1, environmentBytes: 120, unclassifiedCaptures: 0,
  unclassifiedRegularBytes: 0, embeddedCaptures: 0, allowance: 512 });
test('source field layout exposes the unsupported two-child component allowance', () => {
  const model = parentStartupLayout();
  assert.equal(model.blocks.startEnvironment, 120);
  assert.equal(model.blocks.advance, 96);
  assert.equal(model.startupLower, 664);
  const claim = inspectParentStartup(fact(), 'native');
  assert.equal(claim.componentBoundContradicted, true);
  assert.equal(claim.totalReservationViolationProven, false);
  assert.equal(claim.completePipelineUpper, false);
});
test('byte equality does not replace actual capture identity or target correspondence', () => {
  for (const mutate of [f => f.matchedEnvironment = 0, f => f.count = 3,
    f => f.unclassifiedCaptures = 1, f => f.environmentBytes = 112,
    f => f.knownOwnedLowerBytes = 496, f => delete f.completedContainerBytes]) {
    const f = fact(); mutate(f); assert.throws(() => inspectParentStartup(f, 'native'));
  }
  for (const target of ['js', 'wasm']) assert.throws(() => inspectParentStartup(fact(), target));
});
