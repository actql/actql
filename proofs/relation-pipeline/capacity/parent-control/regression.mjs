import assert from 'node:assert/strict';
import { auditParentStartup } from './audit.mjs';
// Reuse the complete, internally consistent executed receipt, rather than
// changing just a fact label. No extra MoonBit execution is needed.
export function rejectParentSubstitutions(report, source, read) {
  auditParentStartup(report, source, read);
  for (const target of ['js', 'wasm']) {
    const copy = structuredClone(report);
    copy.target = target;
    assert.throws(() => auditParentStartup(copy, source, read), /Requested parent probe target/);
  }
  const claim = structuredClone(report);
  claim.unconditionalAllocationBytes = true;
  assert.throws(() => auditParentStartup(claim, source, read), /unconditional capacity guarantee/);
  const relabeled = structuredClone(report);
  relabeled.observation.faults.find(f => f.kind === 'parent control investigation').environmentBytes = 112;
  assert.throws(() => auditParentStartup(relabeled, source, read), /AssertionError/);
  const archives = structuredClone(report);
  archives.execution.parentArchives = {};
  assert.throws(() => auditParentStartup(archives, source, read), /AssertionError/);
  const bound = structuredClone(report);
  bound.retainedCore.recipe.bytes = '512';
  assert.throws(() => auditParentStartup(bound, source, read), /recipe differs/);
  const model = structuredClone(report);
  model.model.sourceDigest = '0'.repeat(64);
  assert.throws(() => auditParentStartup(model, source, read), /independent execution receipt/);
  const candidates = structuredClone(report);
  candidates.providerConstruction.recipe.bytes = 512;
  assert.throws(() => auditParentStartup(candidates, source, read), /Provider recipe differs/);
  const incomplete = structuredClone(report);
  delete incomplete.providerConstruction;
  assert.throws(() => auditParentStartup(incomplete, source, read), /Provider recipe differs/);
  return 'native parent receipt: portable-slot substitution, unsupported guarantee, detached facts, changed core/provider recipe, missing provider evidence, stale model and missing executed artifacts rejected';
}
