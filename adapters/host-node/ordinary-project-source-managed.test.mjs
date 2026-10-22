import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, open, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as sources from './ordinary-source-managed.mjs';
import resource from './ordinary-node-resource-runtime.cjs';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';

// Explicit Host/preparation and managed-limit ports. Physical FileHandles are
// real, but this is not Common, a public Host or Source permission evidence.
async function fixture() {
  assert.equal(typeof sources.prepareOrdinaryProjectSourceManagedInstallation, 'function');
  const directory = await mkdtemp(join(tmpdir(), 'actql-project-source-custody-'));
  await writeFile(join(directory, 'original'), 'original');
  const originals = {}, prepared = {}, request = {}, body = {}, declaration = {};
  const bundle = Object.freeze({sources: Object.freeze([{declaration}])});
  let valid = true;
  const current = () => {if (!valid) throw new Error('OriginalProjectSourceChanged');};
  const view = await sources.prepareOrdinaryProjectSourceManagedInstallation(originals, {
    validator(value) {assert.strictEqual(value, originals); current();},
    async prepare() {}, read: () => bundle,
    request(value, owner) {assert.strictEqual(owner, prepared); return request;},
    requirements: () => ({planningWork: 100, attempts: 10, holdings: 10,
      transferBytes: 10000n, retainedBytes: 10000n, executionBytes: 10000n}),
    intent: () => 'sha256:' + 'a'.repeat(64),
  });
  const receipt = view.beforeSourceSnapshot('aql', 'text', {});
  view.bindSourceSnapshot(receipt, body); view.bindSourceRequest(receipt, body, request);
  const original = view.prepareRun(prepared);
  const ports = resource.prepareOriginalManagedRunPorts(original, prepared);
  assert.equal(ports.status(0), 0);
  return {view, prepared, declaration, original, ports, directory,
    child(index = 0) {return view.prepareRead(prepared, declaration, original,
      {stage: index, input: 0, task: index});},
    finish() {view.finishSourceProducer(receipt, 'returned');
      assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n), 0);},
    invalidate() {valid = false;}};
}

test('Project Source retains a real reader before current refusal and closes with the captured original receiver', async () => {
  const f = await fixture(), child = f.child();
  assert.equal(child.readOriginalBytes, undefined, 'Local files do not borrow Mock document reads');
  const file = await open(join(f.directory, 'original'), 'r');
  let closed = false, calls = 0;
  const actual = {status() {assert.strictEqual(this, actual); return {pending: !closed};},
    async close() {assert.strictEqual(this, actual); calls++; await file.close(); closed = true;
      return {pending: false};}};
  f.invalidate();
  assert.throws(() => child.retainChild(actual), /OriginalProjectSourceChanged/u);
  actual.close = () => assert.fail('Replacement close is not the acquired reader');
  f.finish();
  assert.equal(f.ports.status(2), -42);
  assert.equal((await child.close()).pending, false);
  assert.equal(calls, 1); assert.equal(file.fd, -1);
  assert.equal(f.ports.status(2), 0);
  assert.equal((await f.view.close()).pending, false);
});

test('Project Source distinguishes same-declaration occurrences and preserves pending child custody', async () => {
  const f = await fixture(), first = f.child(0), second = f.child(1);
  assert.throws(() => f.child(0), {code: 'InstalledSourcePreparationMismatch'});
  const file = await open(join(f.directory, 'original'), 'r');
  let ready = false, firstClosed = false, closeCalls = 0, secondClosed = false;
  const actual = {status: () => ({pending: !firstClosed}), async close() {
    closeCalls++;
    if (!ready) return {pending: true};
    await file.close(); firstClosed = true; return {pending: false};}};
  first.retainChild(actual);
  second.retainChild({status: () => ({pending: !secondClosed}),
    close() {secondClosed = true; return {pending: false};}});
  f.finish();
  assert.equal((await f.view.close()).pending, true);
  assert.equal(secondClosed, true, 'A pending sibling does not suppress independent cleanup');
  assert.equal(f.ports.status(2), -42); assert.notEqual(file.fd, -1);
  ready = true;
  assert.equal((await first.close()).pending, false);
  assert.equal(closeCalls, 2); assert.equal(file.fd, -1);
  assert.equal(f.ports.status(2), 0);
  assert.equal((await f.view.close()).pending, false);
});

test('Project Source retries only an unobserved original getter and never replaces a retained child', async () => {
  const f = await fixture(), child = f.child();
  const original = new Error('UnobservedReaderCloseGetter');
  let gets = 0, closes = 0, closed = false;
  const close = function () {assert.strictEqual(this, actual); closes++; closed = true; return {pending: false};};
  const actual = {get close() {if (++gets === 1) throw original; return close;},
    status() {assert.strictEqual(this, actual); return {pending: !closed};}};
  assert.throws(() => child.retainChild(actual), cause => cause === original);
  assert.throws(() => child.retainChild({close, status: () => ({pending: false})}),
    {code: 'InstalledSourcePreparationMismatch'});
  f.finish();
  assert.equal(f.ports.status(2), -42);
  assert.equal((await child.close()).pending, false);
  assert.equal(gets, 2); assert.equal(closes, 1);
  assert.equal(f.ports.status(2), 0);
  assert.equal((await f.view.close()).pending, false);
});

// Execute the real Host's quote projection with explicit Core/Project ports.
// Actual Core compilation and the integrated Host remain separate checks.
const hostSource = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const hostAst = parse(hostSource, {ecmaVersion: 'latest', sourceType: 'module'});
function quoteFixture(refs) {
  const node = hostAst.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'readSourceManagedRunRequirementsOwned');
  assert(node);
  const declarations = [{}, {}], sources = declarations.map((declaration, index) => ({declaration,
    wire: JSON.stringify({views: [{source_ref: `source${index}`}]}),
    limits: {maxPages: 2 + index, maxPageBytes: 10 + index}}));
  const bundle = {sources}, calls = [], original = {};
  let reads = 0, compute = 0, valid = true;
  const moon = {
    clientProgramAcquisitionCount: prepared => {assert.strictEqual(prepared, original); return refs.length;},
    clientProgramPrepareLocalQueryRequirement(...args) {
      assert.strictEqual(args[0], original); assert.equal(args[2], 0);
      calls.push(['requirement', args[1]]); return {ref: refs[args[1]]};
    },
    clientProgramQueryRequirementSourceRef: requirement => requirement.ref,
    clientProgramInstalledManagedRunRequirements(...args) {
      calls.push(['limits', args]); return [10n, 11n, 12n, 13n, 14n, 15n];
    },
  };
  const originals = {installation: {initialControl: {}, projectRuntime: moon, projectSourcePreparation: {}}};
  const ports = {assertSourceManagedHostPreparation: value => {
    assert.strictEqual(value, originals); if (!valid) throw new Error('OriginalHostChanged');
  }, originalSourceManagedHostRequest: (value, prepared) => {assert.strictEqual(prepared, original);},
  readInstalledProjectSourcePreparation: () => {reads++; return bundle;},
  readManagedComputeRunRequirements: (value, prepared) => {assert.strictEqual(prepared, original); compute++; return 'compute';},
  readInitialControlInstallationAsset: (scope, value, path) => path === 'spec/contracts/actql-aoa.json'
    ? JSON.stringify({execution_contracts: {'REL.values': {}, 'ACTQL.expression_fragment/0.1': {}, 'REL.derive.ordered': {}}}) : path,
  clientOperationError: code => Object.assign(new Error(code), {code}), checked: value => value, profiles: {
    mockPreparation() {assert.fail('Project Source is not Mock');},
  }};
  const contracts = hostAst.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'installedManagedRunContracts');
  assert(contracts);
  const quote = new Function(...Object.keys(ports), `${hostSource.slice(contracts.start, contracts.end)};
    ${hostSource.slice(node.start, node.end)};
    return readSourceManagedRunRequirementsOwned;`)(...Object.values(ports));
  return {declarations, calls, original, quote: () => quote(originals, original, false),
    observed: () => ({reads, compute}), invalidate() {valid = false;}};
}

test('actual Host quote follows checked capture occurrences, not configured connection cardinality', () => {
  for (const refs of [['source1'], ['source0', 'source0']]) {
    const f = quoteFixture(refs);
    assert.deepEqual(f.quote(), {planningWork: 10, attempts: 11, holdings: 12,
      transferBytes: 13n, retainedBytes: 14n, executionBytes: 15n});
    const args = f.calls.find(value => value[0] === 'limits')[1];
    const indices = refs.map(ref => Number(ref.at(-1)));
    assert.deepEqual(args[1], indices.map(index => f.declarations[index]));
    assert.deepEqual(args[4], indices.map(index => BigInt((2 + index) * (10 + index))));
    assert.deepEqual(args[5], indices.map(index => BigInt(10 + index)));
    assert.equal(f.observed().reads, 2);
  }
});

test('actual Host zero-capture quote uses the same joint Compute graph without borrowing configured Source bytes', () => {
  const f = quoteFixture([]);
  assert.equal(f.quote(), 'compute');
  assert.deepEqual(f.observed(), {reads: 0, compute: 1});
  assert.deepEqual(f.calls, []);
});

test('actual Host refuses a missing original Source view or retired Host before issuing its quote', () => {
  const missing = quoteFixture(['foreign']);
  assert.throws(missing.quote, {code: 'InstalledSourcePreparationMismatch'});
  assert.equal(missing.calls.some(value => value[0] === 'limits'), false);
  const changed = quoteFixture(['source0']); changed.invalidate();
  assert.throws(changed.quote, /OriginalHostChanged/u);
  assert.deepEqual(changed.calls, []);
});
