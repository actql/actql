import assert from 'node:assert/strict';
import {graphGraftSourceSuccesses, graphGraftSourceRefusals,
  graphGraftSourceExecutionFailures} from './graph-graft-source-input.mjs';
import {graphReachSourceSuccesses, graphReachSourceRefusals}
  from './graph-reach-source-input.mjs';
import {graphShortestSourceSuccesses, graphShortestSourceRefusals}
  from './graph-shortest-source-input.mjs';
import {graphMeanSourceOracles, graphMeanSourceRefusals}
  from './graph-mean-source-input.mjs';

// Select existing authored oracles without changing them or registering a
// second copy in the normal corpus. One installation exercises all four
// families before its existing fresh-process retained Result reader.
export const graphRemainingOperationInputs = {
  successes: [...graphGraftSourceSuccesses, ...graphReachSourceSuccesses,
    ...graphShortestSourceSuccesses, ...graphMeanSourceOracles],
  refusals: [...graphGraftSourceRefusals, ...graphReachSourceRefusals,
    ...graphShortestSourceRefusals, ...graphMeanSourceRefusals],
  executionFailures: graphGraftSourceExecutionFailures,
};

// Keep the shared two-boundary restart reader and its budgets unchanged. Each
// operation owns a finite cohort so none can disappear between generic corpus
// boundaries. Preserve the authored fixtures and their per-kind order.
export function graphRemainingOperationCohortInputs(inputs) {
  const families = ['graft', 'reach', 'shortest', 'mean'];
  const kinds = ['successes', 'executionFailures', 'refusals'];
  const groups = families.map(family => Object.fromEntries(kinds.map(kind =>
    [kind, (inputs[kind] ?? []).filter(item => item.name.startsWith(`graph-${family}-`))])));
  for (const kind of kinds) {
    assert.deepEqual(groups.flatMap(group => group[kind]), inputs[kind] ?? [],
      `Graph operation cohorts must preserve every ${kind} fixture in order`);
  }
  assert.ok(groups.every(group => group.successes.length > 0),
    'Every Graph operation must have a fresh-process Result cohort');
  return groups;
}
