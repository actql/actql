import assert from 'node:assert/strict';
import { oracle } from '../engine.mjs';
export const subject = 'numeric/null sequential Relation; DISTINCT filled container entries and custody, not backing capacity or heap bytes';
export const unresolved = Object.freeze([
  'dynamic Array/Map backing capacity, growth overlap and runtime headers',
  'Session, control, closure, Ref, schema and cursor object byte sizes',
  'parent count * 256 byte allowance',
  'complete child/base allocation byte bounds and final Host reservation handoff',
]);
export function bound(rows, width) {
  assert(Number.isSafeInteger(rows) && rows >= 0 && rows <= 2147483647);
  assert(Number.isSafeInteger(width) && width > 0 && width <= 2147483647);
  const n = BigInt(rows), w = BigInt(width);
  return { rows, width, borrowedCells: n * w,
    metadata: 4n * w, index: 2n * n, keep: n, terms: w,
    outputRows: n, outputCells: n * w, roots: n,
    rowTemporary: 6n * w, measureFrames: 5n,
    ownedFilledEntries: n * w + 5n * n + 11n * w + 5n,
    // IEEE754 numeric content octets, not representation allocation bytes.
    numericContentOctets: 8n * n * w };
}
// Derived from the restricted numeric, short-name execution phases: metadata
// 4w, sort terms w, two index buffers 2n; later keep n plus two row arrays 2w.
// Input measurement has at most one scalar frame and cannot exceed these for
// n>0,w>0. Empty input never constructs an output row.
export function workspaceBound(n, w) { return n === 0 ? 5 * w : Math.max(5 * w + 2 * n, 6 * w + n); }
export function inputs(testCase, registry) {
  const expected = oracle(testCase, registry);
  return testCase.steps.flatMap((step, index) => step.op === 'distinct'
    ? [{ step: step.id, index, ...bound(expected.stages[index].input.length,
      expected.states[index + 1].fields.length) }] : []);
}
export function violation(event) {
  if (event.kind !== 'capacity observation') return null;
  if (event.event === 'commit' && !event.sharedCapture) return 'output custody lost';
  if (event.event === 'output-transfer' && !event.sharedOutput) return 'output custody lost';
  if (event.event === 'input-view' && !event.sharedBacking) return 'borrowed backing was replaced';
  if (event.event === 'index-admission' && event.delta !== 2 * event.n) return 'live DISTINCT scratch underreserved';
  if (event.event === 'index-transfer' && (event.delta !== -event.n || event.length !== event.n)) return 'live DISTINCT scratch underreserved';
  if (event.event === 'premature-release' && event.keep > 0 && event.delta < 0) return 'live DISTINCT scratch underreserved';
  if (event.event === 'index' && event.alias) return 'independent index buffers aliased';
  if (event.event === 'checkpoint' || event.event === 'before-cleanup') {
    if (event.live < 0) return 'invalid or duplicate workspace release';
    // This lower bound uses objects still owned by the real state. Accepted
    // rows have separate retained/output accounting; never call their transfer
    // to that category a physical deallocation.
    if (event.live < event.index + event.keep + event.terms) return 'live DISTINCT scratch underreserved';
  }
  return null;
}
export function inspectEvents(testCase, observation, registry) {
  const obligations = inputs(testCase, registry);
  const events = observation.faults.filter(e => e.kind === 'capacity observation');
  const declarations = observation.faults.filter(e => e.kind === 'capacity declaration');
  assert(declarations.length > 0, 'Missing declared capacity from the actual started provider');
  assert.equal(declarations[0].steps, testCase.steps.length);
  for (const d of declarations) assert(Number.isSafeInteger(d.retainedBytes) && d.retainedBytes >= 0 &&
    Number.isSafeInteger(d.executionBytes) && d.executionBytes >= d.retainedBytes);
  const starts = events.filter(e => e.event === 'start');
  assert.equal(obligations.length, 1, 'Pilot requires one DISTINCT occurrence');
  assert.equal(starts.length, obligations.length * (observation.correspondence ? 4 : 1), 'Missing actual DISTINCT start');
  const b = obligations[0];
  for (const start of starts) {
    assert.equal(start.n, b.rows); assert.equal(start.w, b.width);
  }
    for (const e of events) {
      if (e.n !== undefined) assert.equal(e.n, b.rows);
      if (e.w !== undefined) assert.equal(e.w, b.width);
      assert.equal(violation(e), null, JSON.stringify(e));
      if (e.event === 'checkpoint' || e.event === 'before-cleanup' || e.event === 'after-cleanup') {
        for (const key of ['metadata', 'index', 'keep', 'terms', 'outputRows', 'outputCells', 'roots', 'rowTemporary', 'measureFrames']) {
          assert(Number.isInteger(e[key]) && e[key] >= 0 && BigInt(e[key]) <= b[key], `Exceeded ${key}`);
        }
        const filled = ['metadata', 'index', 'keep', 'terms', 'outputRows', 'outputCells', 'roots', 'rowTemporary', 'measureFrames']
          .reduce((sum, k) => sum + BigInt(e[k]), 0n);
        assert(filled <= b.ownedFilledEntries);
        assert(e.live >= 0 && e.live <= e.limit);
        assert.equal(e.unmodeledEntries, 0, 'Nonempty unmodeled DISTINCT container');
      }
    }
  assert.equal(events.filter(e => e.event === 'after-cleanup').length, starts.length, 'Missing actual cleanup checkpoint');
  assert(events.some(e => e.event === 'output-transfer' && e.sharedOutput), 'Missing actual output-backing transfer identity');
  assert(events.some(e => e.event === 'input-view' && e.sharedBacking), 'Missing actual input-backing identity');
  return { distinctChildren: obligations.length, events: events.length };
}
// These are claim admission rules. They do not change production admission.
export function admitClaim(claim) {
  assert.deepEqual(Object.keys(claim).sort(), ['subject', 'kind', 'unresolved', 'units', 'unconditionalAllocationBytes'].sort());
  assert.equal(claim.subject, subject);
  assert.equal(claim.kind, 'structural-model-and-finite-correspondence');
  assert.deepEqual(claim.unresolved, [...unresolved]);
  assert.equal(claim.units, 'filled entries and numeric content octets');
  assert.equal(claim.unconditionalAllocationBytes, false, 'Missing runtime evidence for unconditional byte claims');
  return claim;
}
