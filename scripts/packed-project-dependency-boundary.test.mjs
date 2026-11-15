import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {dependencyBoundaryFailureData} from './fixtures/project-effect-dependency-observation.mjs';
import {observeTableWidthDataRecord} from './fixtures/table-dependency-width-cases.mjs';
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
  const requestCid = name => 'sha256:' + createHash('sha256').update(name).digest('hex');
  const seedRecords = Array.from({length: selected.sourceStarts}, (_, index) => ({
    operation: {request_cid: requestCid(`seed-${index}`)},
    receipt: {request_cid: requestCid(`seed-${index}`)}}));
  const stored = {operation: {request_cid: requestCid('summary'), action: 'create',
    catalog_identity_cid: cid('8'), namespace: ['test'], table_name: 'summary'},
  receipt: {request_cid: requestCid('summary'), row_count: 1}};
  const target = {record: stored, generation: stored.receipt, rows: [{n: 7}]};
  const make = (name, pid) => {
    const work = {complete: true, sourceAcquisitionStarts: name === 'capture' ? selected.sourceStarts : 0,
      modelCallStarts: 0, effectReplacementReturns: caseId === 'width' ? 0 : name === 'approve' ? 1 : 0};
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
    catalog: {catalogCid: cid('8')}, seedRecords, allCommits: [...seedRecords, stored],
    ledger: {successfulStores: selected.writes}, unavailableDataFiles: Array(selected.sourceStarts).fill({})};
  const input = {selected, phase, actual, pid: actual.pid, original, previous};
  return {input, verify: () => assertPackedDependencyBoundaryPhase(input)};
}

test('physical WIDTH oracle compares complete own DATA across JSON representations without invoking getters', () => {
  const expected = {document_chars: 18886464, id_sum: 73536, row_count: 384};
  const actual = Object.assign(Object.create(null), expected);
  assert.deepEqual(observeTableWidthDataRecord(actual, expected), expected);
  assert.deepEqual(observeTableWidthDataRecord({...expected}, expected), expected);
  let getterCalls = 0, proxyCalls = 0;
  const accessor = {...actual};
  Object.defineProperty(accessor, 'id_sum', {enumerable: true,
    get() { getterCalls++; return expected.id_sum; }});
  const proxy = new Proxy(actual, {getPrototypeOf() { proxyCalls++; return null; }});
  for (const value of [accessor, proxy, {...expected, row_count: 383},
    {...expected, unexpected: 0}, {id_sum: expected.id_sum, row_count: expected.row_count},
    Object.assign(Object.create({foreign: true}), expected), {...expected, id_sum: Infinity}]) {
    assert.throws(() => observeTableWidthDataRecord(value, expected), {code: 'ERR_ASSERTION'});
  }
  assert.equal(getterCalls, 0); assert.equal(proxyCalls, 0);
});

test('Table dependency acceptance uses the exact new Catalog target rather than File replacement diagnostics', () => {
  fixture('width', 'approve').verify();
  for (const mutate of [
    f => f.input.original.allCommits.pop(),
    f => f.input.original.allCommits.push(f.input.original.allCommits.at(-1)),
    f => f.input.original.allCommits[0].receipt.request_cid = cid('f'),
    f => f.input.actual.target.record.operation.table_name = 'other',
    f => f.input.actual.target.rows[0].n = 8,
    f => f.input.actual.target.generation.request_cid = cid('f'),
  ]) {
    const f = fixture('width', 'saved'); mutate(f);
    assert.throws(f.verify, {code: 'ERR_ASSERTION'});
  }
});

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

for (const depth of [8, 10]) {
  test(`dependency diagnostics preserve bounded prototype enum DATA at depth ${depth} without getters`, () => {
    const inspect = value => dependencyBoundaryFailureData(value, depth);
    let getters = 0;
    const leaf = Object.assign(Object.create({$tag: 7}), {_0: 11, required: 19, available: 8});
    const cause = Object.assign(Object.create({$tag: 3}), {_0: leaf, _1: true});
    Object.defineProperty(cause, 'issue', {get() {getters++; throw new Error('unexpected getter');}});
    const primary = {code: 'MoonBitHostFailure', phase: 'source', cause,
      message: 'private body', schema: {private: true}};
    assert.deepEqual(inspect(primary), {code: 'MoonBitHostFailure', phase: 'source',
      cause: {$tag: 3, _0: {$tag: 7, required: 19, available: 8, _0: 11}, _1: true}});
    assert.equal(getters, 0);
    const shadowed = Object.create({$tag: 5});
    Object.defineProperty(shadowed, '$tag', {get() {getters++; return 9;}});
    assert.deepEqual(inspect(shadowed), {});
    let within = {$tag: 13};
    for (let index = 0; index < 3; index++) within = Object.create(within);
    assert.equal(inspect(within).$tag, 13);
    assert.deepEqual(inspect(Object.create(within)), {});
    const unreadable = new Proxy({}, {getPrototypeOf() {throw new Error('unreadable diagnostic');}});
    assert.deepEqual(inspect({code: 'OriginalFailure', cause: unreadable}),
      {code: 'OriginalFailure', cause: {}});
    assert.equal(getters, 0);
  });
}
