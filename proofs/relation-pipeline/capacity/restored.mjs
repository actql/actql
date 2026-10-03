// Additional post-restoration observations, distinct from the fifteen healthy
// instrumented replays. This owner starts only after the instrumented one closes.
import assert from 'node:assert/strict';
import { createExecutor, executions, root } from '../execute.mjs';
import { workspaceIdentity } from '../workspaces.mjs';
import { snapshot } from '../inventory.mjs';
import { compareSemantics } from '../evidence.mjs';
import { registry } from '../registry.mjs';
import { recordCapacityOwner } from './parts.mjs';
export function replayRestoredMinima({ report, targets, source, predecessor, probe }) {
  assert(predecessor.closed, 'Instrumented owner has not closed');
  assert.deepEqual(snapshot(root), source, 'Post-restore source differs');
  const began = performance.now();
  const replayMs = {};
  const first = executions.length;
  const executor = createExecutor(workspaceIdentity(root, 'normal', source));
  const records = [];
  try {
    for (const mutation of report.mutations) {
      const observations = {};
      replayMs[mutation.name] = {};
      for (const target of targets) {
        const targetBegan = performance.now();
        observations[target] = probe([mutation.minimal], target, `${mutation.name}-post-restore`, true, executor.execute)[0];
        compareSemantics(mutation.minimal, observations[target], registry);
        assert.deepEqual(observations[target].faults, [], 'Post-restore execution remains instrumented');
        replayMs[mutation.name][target] = performance.now() - targetBegan;
      }
      records.push({ name: mutation.name, minimal: mutation.minimal, observations });
    }
  } finally { executor.close(); }
  assert.deepEqual(snapshot(root), source, 'Post-restore source changed');
  const owner = recordCapacityOwner(executions.slice(first), 'post-restore', predecessor.id);
  assert.equal(owner.root, predecessor.root, 'Post-restore replay changed checkout');
  assert.notEqual(owner.id, predecessor.id, 'Post-restore replay reused its predecessor');
  return { owner, evidence: { owner: owner.id, predecessor: predecessor.id, sourceDigest: source.digest, records,
    timings: { totalMs: performance.now() - began, replayMs } } };
}
