import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {parse} from 'acorn';
import resultRecipe from './host-result-service-recipe.cjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';

// These support DATA and actual-statement/Store counters issue no operational
// original, authorization or Ledger. The ordinary Root cases are separate.
function recipe() {
  const control = {}, journal = {sharedControl: control}, source = {}, compute = {};
  return {control, journal, source, compute,
    value: resultRecipe.declareHostResultServiceRecipe(control, journal, source, compute)};
}
const options = directory => ({directory, storeAuthorityCid: 'sha256:' + 'a'.repeat(64),
  capacityBytes: 536870912, maxObjectBytes: 10000000, maxObjects: 10000,
  maxContractNodes: 10000, maxContractDepth: 64});
const controlFixture = () => Object.fromEntries(['admit', 'recordTransition', 'deliveryTransition',
  'deliverySuccessValid', 'trustedClockNotBefore', 'recordAllowsCommit', 'effectFreeCommitValid']
  .map(name => [name, () => assert.fail(name + ' unused')]));

test('Result recipe retains original shared declarations without a backed amount or refill', () => {
  const f = recipe(), r = f.value;
  assert.strictEqual(r.sharedControl, f.control); assert.strictEqual(r.journal, f.journal);
  assert.strictEqual(r.sourceCompute, f.source); assert.strictEqual(r.sourceFreeCompute, f.compute);
  assert(Object.isFrozen(r)); assert.equal(r.numericalBackingClaim, false);
  assert.equal(r.allocationSuccessGuaranteed, false); assert.equal(r.refilledOnClose, false);
  assert.equal(r.conditionalWireHistory.publication, 100000000n);
  assert.equal(r.conditionalWireHistory.storeCalls, 40960000000n);
  assert.equal(r.conditionalWireHistory.reads, 1342177280n);
  assert.throws(() => resultRecipe.declareHostResultServiceRecipe({}, f.journal, f.source, f.compute));
});

test('Store selection preserves exact arguments and refuses keys, accessors, proxies or larger support', () => {
  const {value: r} = recipe(), directory = '/selected/original/publication';
  const selected = r.selectStoreArguments(options(directory), directory);
  assert.equal(selected.capacityBytes, 536870912); assert(Object.isFrozen(selected));
  let entered = 0;
  const getter = options(directory); Object.defineProperty(getter, 'maxObjectBytes', {get() {entered++; return 1;}});
  const proxy = new Proxy({}, {ownKeys() {entered++; return [];}});
  for (const bad of [getter, proxy, {...options(directory), extra: undefined},
    {...options(directory), maxObjects: 10001}, {...options(directory), privateEvidenceKey: new Uint8Array(32)}]) {
    assert.throws(() => r.selectStoreArguments(bad, directory), {code: 'HostResultPublicationUnavailable'});
  }
  assert.equal(entered, 0);
});

test('actual Store refuses lost service currentness but closes through its same original without current', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-result-service-current-'));
  let current = true, reads = 0;
  const marker = new Error('OriginalResultServiceRetired');
  const store = await openLocalPublicationStore(options(directory), controlFixture(), undefined,
    undefined, undefined, () => {reads++; if (!current) throw marker;});
  const held = {requiredBytes: 1, objectCount: 1, maxObjectBytes: 1};
  assert.equal(store.publicationCapacitySupports(held), true);
  current = false;
  assert.throws(() => store.publicationCapacitySupports(held), error => error === marker);
  const before = reads;
  await store.close(); assert.equal(store.status().closed, true); assert.equal(reads, before);
  // The new physical test state stays at its original path after close.
});

const submissionSource = readFileSync(new URL('./client-submission.mjs', import.meta.url), 'utf8');
const submissionAst = parse(submissionSource, {ecmaVersion: 'latest', sourceType: 'module'});
function visit(node, fn) {
  if (!node || typeof node !== 'object') return;
  if (node.type) fn(node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(child => visit(child, fn));
    else if (value && typeof value === 'object') visit(value, fn);
  }
}
function beforeBusinessRecord() {
  const matches = [];
  visit(submissionAst, node => {
    if (node.type !== 'BlockStatement') return;
    for (let i = 1; i < node.body.length; i++) {
      const current = node.body[i], previous = node.body[i - 1];
      if (current.type === 'ExpressionStatement' && current.expression.type === 'AssignmentExpression' &&
          current.expression.left.name === 'retained' &&
          submissionSource.slice(current.start, current.end).includes('journal.recordSubmittedIntent') &&
          previous.type === 'IfStatement' && submissionSource.slice(previous.start, previous.end).includes('admitPreparedSubmission')) {
        matches.push([previous, current]);
      }
    }
  });
  assert.equal(matches.length, 1);
  return new Function('admitPreparedSubmission', 'preparedProgram', 'journal', `
    const value={},requestId='original-request',input={},current={},moon={},attempt=undefined;
    const own=(parent,derived)=>derived,restartFields=value=>value;
    const fail=code=>{throw Object.assign(new Error(code),{code});};let retained;
    ${matches[0].map(node => submissionSource.slice(node.start, node.end)).join('\n')}
    return retained;`);
}

test('actual Submission calls same prepared candidate before its first durable business record', () => {
  const run = beforeBusinessRecord(), prepared = {}, order = [], record = {};
  const journal = {recordSubmittedIntent() {order.push('record'); return record;}};
  const observed = run(value => {
    assert.strictEqual(value.preparedProgram, prepared); assert.equal(value.requestId, 'original-request');
    order.push('candidate');
  }, prepared, journal);
  assert.strictEqual(observed, record); assert.deepEqual(order, ['candidate', 'record']);
});

test('candidate refusal, Promise or Boolean cannot cross the actual durable record boundary', () => {
  const run = beforeBusinessRecord(), marker = new Error('OriginalCandidateRefusal'); let records = 0;
  const journal = {recordSubmittedIntent() {records++;}};
  assert.throws(() => run(() => {throw marker;}, {}, journal), error => error === marker);
  for (const result of [false, true, Promise.resolve()]) {
    assert.throws(() => run(() => result, {}, journal), {code: 'ClientPreparedSubmissionUnavailable'});
  }
  assert.equal(records, 0);
});
