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
  return 'native startup receipt: portable-slot substitution, unsupported guarantee, detached facts and missing executed artifacts rejected';
}
