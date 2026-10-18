import assert from 'node:assert/strict';
import test from 'node:test';
import source from './source-managed-phase-envelope.cjs';
import control from './initial-control-phase-envelope.cjs';

// Pure equation/finite-recipe checks only. Actual Root, same-Host Source
// admission and all distinct physical external suppliers remain separate.
test('control and Source share one managed/native domain while external overlaps are additive', () => {
  const original=control.declareInitialControlPhaseEnvelope(4*1024**3);
  const phase=source.declareSourceManagedPhaseEnvelope(original);
  assert.equal(phase.controlDeclaration,original);
  assert.equal(phase.sharedManagedHeapBytes,4*1024**3);
  assert.equal(phase.additionalManagedHeapBytes,0);
  assert.equal(phase.additionalWholeNativeDomainBytes,0);
  assert.equal(phase.responseBackingBytes,128*1024**2);
  assert.equal(phase.externalWorkspaceBytes,16*1024**2);
  assert.equal(phase.simultaneousBytes,original.bytes+144*1024**2);
  assert.equal(phase.replenishedOnSourceClose,false);
  assert.equal(phase.limits.sourceOccurrences,1);
  assert.equal(phase.inputLimits.maxOpaqueAliases,0);
  assert.equal(phase.inputLimits.maxArrayItems,0);
  assert.equal(phase.issue,undefined);assert.equal(phase.begin,undefined);
  assert(Object.isFrozen(phase.managedOverlap));assert(Object.isFrozen(phase.externalRequired));
});
