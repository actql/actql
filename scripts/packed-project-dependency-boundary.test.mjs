import assert from 'node:assert/strict';
import test from 'node:test';
import {assertPackedDependencyBoundaryPhase, packedDependencyBoundaryCases,
  packedDependencyBoundaryPhases} from './packed-project-dependency-boundary.mjs';

// Explicit oracle inputs only. Real canonical bodies, Store restoration,
// physical Source/Effect counters and original close come from the children.
const cid = digit => 'sha256:' + digit.repeat(64);
function fixture(caseId = 'count', phase = 'saved') {
  const selected = packedDependencyBoundaryCases.find(value => value.case === caseId);
  const dependencies = {uniqueData: caseId === 'count' ? 4097 : 100,
    canonicalDataBodyBytes: caseId === 'width' ? 16777217 : 100000,
    snapshotCid: cid('a')};
  const ref = {runDefinitionCid: cid('b'), authorityScopeCid: cid('c')};
  const results = {answer: [{n: 7}]}, targets = Array.from({length: selected.writes},
    (_, index) => ({path: `${index}.jsonl`, contentCid: cid('d')}));
  const target = {generation: 'original-generation', rows: [{n: 7}]};
  const make = (name, pid) => {
    const work = {complete: true, sourceAcquisitionStarts: name === 'capture' ? selected.sourceStarts : 0,
      modelCallStarts: 0, effectReplacementReturns: name === 'approve' ? 1 : 0};
    return {case: caseId, phase: name, pid, ref, complete: true,
      firstClose: 'returned', firstCloseCalls: 1, aliveScopedFD: {before: 0, after: 0}, cleanup: [],
      submits: name === 'capture' ? 1 : 0, approvals: name === 'approve' ? 1 : 0,
      dependencies, workObservation: {...work, totals: {...work},
        unbound: {sourceAcquisitionStarts: 0, modelCallStarts: 0, effectReplacementReturns: 0}},
      requestMemory: {retainedBytes: 1073741824, executionBytes: 1073741824}, sourceFreeMaxWork: 30000000,
      zeroWritesBeforeApproval: true, originalInputsAndProgramAbsent: true,
      results: name === 'capture' ? undefined : results, targets, target,
      wholeSources: Array.from({length: selected.sourceStarts}, (_, index) => ({relationCid: `original-relation-${index}`}))};
  };
  const observations = packedDependencyBoundaryPhases.map((name, index) => make(name, index + 100));
  const index = packedDependencyBoundaryPhases.indexOf(phase), actual = structuredClone(observations[index]);
  const previous = structuredClone(observations.slice(0, index));
  const original = {ref, captureComplete: true, capturePid: 100,
    approveComplete: phase !== 'capture', approvePid: phase === 'capture' ? undefined : 101,
    dependencies: structuredClone(dependencies), results, targets, target,
    ledger: {successfulStores: selected.writes}, unavailableDataFiles: Array(selected.sourceStarts).fill({})};
  const input = {selected, phase, actual, pid: actual.pid, original, previous};
  return {input, verify: () => assertPackedDependencyBoundaryPhase(input)};
}

test('dependency acceptance requires both distinct boundaries through capture, cold approval and Saved', () => {
  assert.deepEqual(packedDependencyBoundaryCases.map(value => value.case), ['count', 'width']);
  for (const selected of packedDependencyBoundaryCases) {
    for (const phase of ['capture', 'approve', 'saved']) fixture(selected.case, phase).verify();
  }
});

test('dependency count and canonical body thresholds cannot be replaced by payload size or matching totals', () => {
  for (const [caseId, key, boundary] of [
    ['count', 'uniqueData', 4096], ['width', 'canonicalDataBodyBytes', 16777216],
  ]) {
    const f = fixture(caseId, 'capture');
    f.input.actual.dependencies[key] = boundary;
    f.input.original.dependencies[key] = boundary;
    f.input.actual.payloadBytes = 100000000;
    assert.throws(f.verify, {code: 'ERR_ASSERTION'});
  }
});

test('cold dependency use refuses replay, changed snapshot identity and reused process even with matching row counts', () => {
  for (const mutate of [
    f => {f.input.actual.workObservation.sourceAcquisitionStarts = 1;},
    f => {f.input.actual.workObservation.totals.modelCallStarts = 1;},
    f => {f.input.actual.dependencies.snapshotCid = cid('e'); f.input.original.dependencies.snapshotCid = cid('e');},
    f => {f.input.actual.pid = f.input.pid = f.input.previous[0].pid;},
    f => {f.input.actual.results.answer = [{n: 8}];},
  ]) {
    const f = fixture(); mutate(f); assert.throws(f.verify, {code: 'ERR_ASSERTION'});
  }
});

test('a pending first close, live descriptor, incomplete phase or missing Source provenance cannot pass', () => {
  for (const mutate of [
    f => {f.input.actual.firstClose = 'pending';},
    f => {f.input.actual.firstCloseCalls = 2;},
    f => {f.input.actual.aliveScopedFD.after = 1;},
    f => {f.input.actual.complete = false;},
    f => {f.input.previous.pop();},
    f => {f.input.actual.wholeSources.pop();},
  ]) {
    const f = fixture('width'); mutate(f); assert.throws(f.verify, {code: 'ERR_ASSERTION'});
  }
});
