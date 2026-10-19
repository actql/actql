import assert from 'node:assert/strict';
import test from 'node:test';
import source from './source-managed-phase-envelope.cjs';
import control from './initial-control-phase-envelope.cjs';
import {readSourceManagedOriginalInput} from './source-managed-original-input.mjs';

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
  assert.equal(phase.limits.sourceOccurrences,2);
  assert.equal(phase.occurrencePartitions.length,2);
  assert.equal(phase.occurrencePartitions[0].responseStart,0);
  assert.equal(phase.occurrencePartitions[1].responseStart,64);
  assert.equal(phase.occurrencePartitions.reduce((sum,part)=>sum+part.responses,0),128);
  assert.equal(phase.occurrencePartitions.reduce((sum,part)=>sum+part.responseBackingBytes,0),phase.responseBackingBytes);
  assert(phase.occurrencePartitions.every(Object.isFrozen));
  assert.equal(phase.inputLimits.maxOpaqueAliases,0);
  assert.equal(phase.inputLimits.maxArrayItems,0);
  assert.equal(phase.issue,undefined);assert.equal(phase.begin,undefined);
  assert(Object.isFrozen(phase.managedOverlap));assert(Object.isFrozen(phase.externalRequired));
});

test('the same Source recipe includes the original submission epoch rather than a shallower replacement', () => {
  const phase=source.declareSourceManagedPhaseEnvelope(control.declareInitialControlPhaseEnvelope(4*1024**3));
  const epoch=Object.freeze({version:'actql-submission-epoch/0.1',authorityScopeCid:'original-scope',
    epochNonce:'original-epoch',authenticator:'original-proof',notBefore:1,expiresAt:2});
  const options=Object.freeze({format:'sql',parameters:null,
    submissionRef:Object.freeze({nonce:'original-nonce',epoch})});
  const read=readSourceManagedOriginalInput('aql','SELECT 1',options,phase.inputLimits);
  assert.equal(read.usage.depth,4);
  assert.equal(read.packet.options.submissionRef.epoch.authenticator,epoch.authenticator);
  assert.equal(read.originalReferences.length,0);
  assert.equal(read.packet.options.parameters,null);
  assert.notEqual(read.packet.options,options);
});

test('Source intake cannot borrow a callback graph under a zero opaque-alias recipe', () => {
  const phase=source.declareSourceManagedPhaseEnvelope(control.declareInitialControlPhaseEnvelope(4*1024**3));
  let called=0;
  assert.throws(()=>readSourceManagedOriginalInput('aql','SELECT 1',
    {format:'sql',callback(){called++;}},phase.inputLimits),{code:'NodeSourceManagedInputUnavailable'});
  assert.equal(called,0);
});

test('source-free Compute shares the original runtime without Source byte or child credit', () => {
  const original=control.declareInitialControlPhaseEnvelope(4*1024**3);
  const phase=source.declareSourceFreeManagedComputePhaseEnvelope(original);
  assert.strictEqual(phase.controlDeclaration,original);
  assert.equal(phase.sourceOccurrences,0);
  assert.equal(phase.requests,1);
  assert.equal(phase.additionalManagedHeapBytes,0);
  assert.equal(phase.additionalWholeNativeDomainBytes,0);
  assert.equal(phase.limits.transferBytes,1024*1000000);
  assert.equal(phase.limits.retainedBytes,536870912);
  assert.equal(phase.limits.executionBytes,536870912);
  assert.equal(phase.responseBackingBytes,undefined);
  assert.equal(phase.occurrencePartitions,undefined);
  assert.equal(phase.replenishedOnClose,false);
});
