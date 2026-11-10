import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {parse} from 'acorn';
import {compileFunction} from 'node:vm';
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
  assert.equal(Object.hasOwn(r, 'conditionalWireHistory'), false);
  assert.equal(Object.hasOwn(r, 'maxHostOperations'), false);
  assert.equal(Object.hasOwn(r, 'maxStoreOperations'), false);
  assert.throws(() => resultRecipe.declareHostResultServiceRecipe({}, f.journal, f.source, f.compute));
});

test('Store selection preserves finite selected policy without treating default equality as ownership', () => {
  const {value: r} = recipe(), directory = '/selected/original/publication';
  const selected = r.selectStoreArguments(options(directory), directory);
  assert.equal(selected.capacityBytes, 536870912); assert(Object.isFrozen(selected));
  let entered = 0;
  const getter = options(directory); Object.defineProperty(getter, 'maxObjectBytes', {get() {entered++; return 1;}});
  const proxy = new Proxy({}, {ownKeys() {entered++; return [];}});
  for (const bad of [getter, proxy, {...options(directory), extra: undefined},
    {...options(directory), maxObjects: 2147483648}, {...options(directory), maxObjectBytes: 0},
    {...options(directory), maxContractDepth: 65}, {...options(directory), capacityBytes: NaN},
    {...options(directory), privateEvidenceKey: new Uint8Array(32)}]) {
    assert.throws(() => r.selectStoreArguments(bad, directory), {code: 'HostResultPublicationUnavailable'});
  }
  for (const bytes of [9999999, 10000000, 10000001]) {
    const selected = r.selectStoreArguments({...options(directory), maxObjectBytes: bytes,
      maxObjects: 10001, maxContractNodes: bytes}, directory);
    assert.equal(selected.maxObjectBytes, bytes);assert.equal(selected.maxObjects, 10001);
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
  const preparationDeclarations = new Map();
  visit(submissionAst, node => {
    if (node.type === 'VariableDeclaration' && node.declarations.length === 1) {
      const name = node.declarations[0].id.name;
      if (['copyRequest', 'preparedSubmission', 'refusalProperty', 'originalPreparationRefusal'].includes(name)) {
        assert.equal(preparationDeclarations.has(name), false);
        preparationDeclarations.set(name, node);
      }
    }
    if (node.type !== 'BlockStatement') return;
    for (let i = 2; i < node.body.length; i++) {
      const current = node.body[i], previous = node.body[i - 1];
      if (current.type === 'ExpressionStatement' && current.expression.type === 'AssignmentExpression' &&
          current.expression.left.name === 'retained' &&
          submissionSource.slice(current.start, current.end).includes('journal.recordSubmittedIntent') &&
          previous.type === 'TryStatement' && submissionSource.slice(previous.start, previous.end).includes('admitPreparedSubmission')) {
        const candidate = node.body[i - 2];
        assert.equal(candidate.type, 'VariableDeclaration');
        assert.equal(candidate.declarations.length, 1);
        assert.equal(candidate.declarations[0].id.name, 'admissionCandidate');
        matches.push([candidate, previous, current]);
      }
    }
  });
  assert.equal(matches.length, 1);
  assert.deepEqual([...preparationDeclarations.keys()],
    ['copyRequest', 'preparedSubmission', 'refusalProperty', 'originalPreparationRefusal']);
  return new (async function() {}).constructor('admitPreparedSubmission', 'preparedProgram', 'journal', `
    const value={},requestId='original-request',input={},current={},moon={},attempt=undefined,preparationCustody=undefined;
    const own=(parent,derived)=>derived,restartFields=value=>value;
    const retainPreparationRefusal=async error=>{throw error;};
    const fail=code=>{throw Object.assign(new Error(code),{code});};let retained;
    ${[...preparationDeclarations.values()].map(node => submissionSource.slice(node.start, node.end)).join('\n')}
    ${matches[0].map(node => submissionSource.slice(node.start, node.end)).join('\n')}
    return retained;`);
}

test('actual Submission calls same prepared candidate before its first durable business record', async () => {
  const run = beforeBusinessRecord(), prepared = {}, order = [], record = {};
  const journal = {recordSubmittedIntent() {order.push('record'); return record;}};
  const observed = await run(value => {
    assert.strictEqual(value.preparedProgram, prepared); assert.equal(value.requestId, 'original-request');
    order.push('candidate');
  }, prepared, journal);
  assert.strictEqual(observed, record); assert.deepEqual(order, ['candidate', 'record']);
});

test('candidate refusal, Promise or Boolean cannot cross the actual durable record boundary', async () => {
  const run = beforeBusinessRecord(), marker = new Error('OriginalCandidateRefusal'); let records = 0;
  const journal = {recordSubmittedIntent() {records++;}};
  await assert.rejects(run(() => {throw marker;}, {}, journal), error => error === marker);
  for (const result of [false, true, Promise.resolve()]) {
    await assert.rejects(run(() => result, {}, journal), {code: 'ClientPreparedSubmissionUnavailable'});
  }
  assert.equal(records, 0);
});

test('candidate refusal projection preserves its own callback and exact frozen candidate', async () => {
  const run = beforeBusinessRecord(), marker = new Error('OriginalCandidateRefusal');
  const prepared = {}, seen = []; let records = 0, projections = 0;
  const journal = {recordSubmittedIntent() {records++;}};
  const admit = candidate => {seen.push(candidate); throw marker;};
  Object.defineProperty(admit, 'isOriginalPreparationRefusal', {value(error, candidate) {
    projections++;
    assert.strictEqual(this, admit); assert.strictEqual(error, marker);
    assert.strictEqual(candidate, seen[0]); assert.strictEqual(candidate.preparedProgram, prepared);
    assert(Object.isFrozen(candidate)); return true;
  }});
  await assert.rejects(run(admit, prepared, journal), error => error === marker);
  assert.equal(seen.length, 1); assert.equal(projections, 1); assert.equal(records, 0);

  let getters = 0;
  const accessor = () => {throw marker;};
  Object.defineProperty(accessor, 'isOriginalPreparationRefusal', {
    get() {getters++; throw new Error('AccessorMustNotRun');},
  });
  await assert.rejects(run(accessor, prepared, journal), error => error === marker);
  assert.equal(getters, 0); assert.equal(records, 0);
});

test('same original Result service admits later bounded operations without a lifetime call quota', () => {
  // Execute the five actual Source functions, with explicit original service
  // and Journal doubles. This does not issue physical backing or normal Host
  // admission; Reader/Store budgets remain separately selected and tested.
  const source = readFileSync(new URL('./node-public-initial-control-bootstrap.cjs', import.meta.url), 'utf8');
  const names = ['prepareResult', 'resultOriginal', 'resultCurrent',
    'beforeResultOperation', 'beforeResultRead'];
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'script'});
  const bodies = names.map(name => {
    const nodes = ast.body.filter(node => node.type === 'FunctionDeclaration' && node.id.name === name);
    assert.equal(nodes.length, 1);return source.slice(nodes[0].start, nodes[0].end);
  }).join('\n');
  const make = compileFunction(`
    let resultInstallation;
    const apply=Reflect.apply, freeze=Object.freeze;
    const field=(value,name)=>value[name];
    const resultUnavailable=()=>{throw Object.assign(new Error('HostResultPublicationUnavailable'),
      {code:'HostResultPublicationUnavailable'});};
    const resultCarrier=(_entry,cause)=>cause;
    ${bodies}
    return {prepare:prepareResult,operation:beforeResultOperation,read:beforeResultRead,
      storeCurrent:()=>resultInstallation.storeCurrent()};`,
    ['state', 'journalInstallation', 'assertSamePreparation', 'assertResultServiceCurrent', 'journalCurrent']);
  const held = {installation: {projectRuntime: {}}}, service = {}, ownership = {};
  const journal = {originals: held, original: {}, journal: {}, ownership,
    paths: {root: '/original-result-service', principalId: 'original-principal'}};
  const subject = {root: journal.paths.root, principalId: journal.paths.principalId,
    runtime: held.installation.projectRuntime};
  Object.assign(service, {namespace: {}, callbacks: {read(original) {
    assert.equal(original, held);return subject;
  }}});
  let current = true, currentChecks = 0;
  const lost = new Error('OriginalResultOwnerRetired');
  const check = () => {currentChecks++;if (!current) throw lost;};
  const actual = make({resultService: service}, journal,
    original => {assert.equal(original, held);check();},
    original => {assert.equal(original, service);check();},
    (original, input) => {assert.equal(original, journal.original);assert.equal(input, held);check();return journal;});
  const original = actual.prepare(held);
  let optionReads = 0;
  const options = new Proxy({}, {get() {optionReads++;throw new Error('OwnerMustNotReadOptions');}});
  for (let i=0;i<130;i++) {
    actual.operation(original, held, 'describe');actual.read(held, options, undefined);
  }
  for (let i=0;i<4100;i++) actual.storeCurrent();
  assert.equal(optionReads, 0);assert(currentChecks >= 3 * (1 + 260 + 4100));
  assert.throws(() => actual.operation({}, held, 'describe'), {code: 'HostResultPublicationUnavailable'});
  current = false;
  assert.throws(() => actual.storeCurrent(), cause => cause === lost);
  // Pending retirement remains attached to the same original, with no reset,
  // second installation, quota refill or ability to use it after retirement.
  assert.throws(() => actual.read(held, undefined, undefined), {code: 'HostResultPublicationUnavailable'});
  assert.throws(() => actual.prepare(held), cause => cause === lost);
});
