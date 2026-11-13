import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, open, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as sources from './ordinary-source-managed.mjs';
import resource from './ordinary-node-resource-runtime.cjs';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {snapshotClientRequest} from '../../packages/client-wire/index.mjs';

// Explicit Host/preparation and managed-limit ports. Physical FileHandles are
// real, but this is not Common, a public Host or Source permission evidence.
async function fixture() {
  assert.equal(typeof sources.prepareOrdinaryProjectSourceManagedInstallation, 'function');
  const directory = await mkdtemp(join(tmpdir(), 'actql-project-source-custody-'));
  await writeFile(join(directory, 'original'), 'original');
  const originals = {}, prepared = {}, request = {}, identity = {}, declaration = {}, parent = {}, holder = {}, managed = {}, plan = {};
  const coordinates = [[0, 0, 0], [0, 1, 0]];
  const bundle = Object.freeze({sources: Object.freeze([{declaration}])});
  const ok = value => ({$tag: 1, _0: value});
  let valid = true, original, ports, retiring = false, returned = false;
  const current = () => {if (!valid) throw new Error('OriginalProjectSourceChanged');};
  const policy = {};
  // Core phase/body results are explicit ports, as the former legacy Run
  // fixture was. The real ordinary Root and real FileHandles remain actual.
  // This does not qualify a compiled Common, Ledger tariff or public Host.
  const moon = {
    clientLocalResourcePolicyOriginal: () => policy,
    clientProgramRequestPreparationControl: () => [1024n, 0n],
    clientLocalPreparationResourceLimits: () => [100n, 10n, 10n, 10000n, 10000n, 10000n],
    clientProgramPrepareLocalPreparationAdmission(value, receipt) {
      original = value; ports = resource.prepareOriginalLocalPreparationPorts(value, receipt);
      return ok({});
    },
    clientProgramBeginRequestPreparation() {assert.equal(ports.status(0), 0); return ok(parent);},
    clientProgramReserveRequestSnapshot: () => ok(),
    clientProgramAbortRequestPreparation() {return ok();},
    clientProgramPrepareRequestNativeComputation: () => ok(),
    clientProgramPrepareRequestSourceComputation: () => ok(),
    clientProgramFinishRequestComputation: () => ok('effect_free'),
    clientProgramPrepareRequestPolicySubjects: () => assert.fail('No verifier selected'),
    clientProgramReadRequestPolicySubject: () => assert.fail('No verifier selected'),
    clientProgramBindRequestPolicySubject: () => assert.fail('No verifier selected'),
    clientProgramFinishRequestPolicySubjects: () => assert.fail('No verifier selected'),
    clientProgramPrepareRequestProgramModuleBody: () => assert.fail('No source-free module'),
    clientProgramRequestProgramModuleIssueCode() {},
    clientProgramBorrowRequestProgramPlanInput: () => ok(holder),
    clientProgramPreparationBorrowRead: value => {assert.strictEqual(value, holder); return prepared;},
    clientProgramComposedInferOccurrences: () => ok([]),
    clientProgramSerializationOccurrences: () => [],
    clientProgramAcquisitionCount: () => coordinates.length,
    clientProgramRequestParametersOriginal: () => ok(undefined),
    clientProgramAdoptRequestProgramPreparation: () => assert.fail('No source-free adoption'),
    clientProgramPrepareRequestCaptureModuleBody: () => ok(),
    clientProgramAdoptRequestCapturePreparation: () => ok(managed),
    clientProgramInstalledManagedSourceOccurrence(value, owner, intent, slot) {
      assert.strictEqual(value, managed); assert.strictEqual(owner, prepared);
      assert.strictEqual(intent, identity);
      if (!coordinates[slot]) throw Object.assign(new Error('OriginalPlanSlotUnavailable'),
        {code: 'OriginalPlanSlotUnavailable'});
      const [stage, input, task] = coordinates[slot];
      return ok({_0: stage, _1: input, _2: task});
    },
    clientProgramPreparationBorrowRetirementStarted: () => retiring,
    clientProgramPreparationBorrowReturn(value) {
      assert.strictEqual(value, holder); assert(retiring); assert(!returned); returned = true; return ok(true);
    },
  };
  const context = Object.freeze({runtime: moon, preparedEnvironment: {}, retainedRelationOutput: true});
  originals.installation = {sequenceContractOriginal: {moon, admission: {}}};
  const view = await sources.prepareOrdinaryProjectSourceManagedInstallation(originals, {
    validator(value) {assert.strictEqual(value, originals); current();},
    retainedValidator(value) {assert.strictEqual(value, originals); current();},
    async prepare() {}, read: () => bundle,
    request(value, owner) {assert.strictEqual(owner, prepared); return request;},
    preparationContext: () => context, retireInitialPreparation() {},
  });
  assert.equal(view.prepareRun, undefined, 'Project Sources cannot create a detached ordinary Root');
  const connection = Object.freeze({mode: 'local', owner: 'local',
    consentRefs: Object.freeze([]), runners: Object.freeze([])});
  const program = {version: 'actql/0.1', id: 'original-project-source', stages: [{id: 'scan',
    inputs: {remote: {connector: 'fixture', resource: 'records'},
      other: {connector: 'fixture', resource: 'records'}},
    steps: [{filter: 'true'}, {select: ['id'], as: 'rows'}],
    results: {rows: {from: 'rows', fields: ['id']}}}],
    results: {rows: {from: {stage: 'scan', result: 'rows'}}}};
  const receipt = view.beforeSourceSnapshot('program', program, {}, connection);
  const body = view.captureSourceSnapshot(receipt, {kind: 'program', input: program}, snapshotClientRequest);
  view.bindSourceSnapshot(receipt, body); view.bindSourceRequest(receipt, body, request);
  await view.fundedPreparation(request, undefined);
  const adopted = view.adoptCapturePreparation(prepared, request, identity, () => plan);
  assert.strictEqual(adopted.original, original); assert.strictEqual(adopted.value, managed);
  return {view, prepared, declaration, original, ports, directory, managed, identity,
    child(index = 0, changes = {}) {
      const [stage, input, computeTask] = coordinates[index] ?? [0, 0, 0];
      return view.prepareRead(prepared, declaration, managed,
        {stage, input, task: index, computeTask, ...changes}, identity);
    },
    finish() {view.finishSourceProducer(receipt, 'returned');
      assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0, 0, 0), 0);},
    sever() {retiring = true; view.severPreparation(prepared, original); assert(returned);},
    retired() {view.retireSeveredPreparation(original);},
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
  f.sever(); assert.equal(f.ports.status(2), 0); f.retired();
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
  f.sever(); assert.equal(f.ports.status(2), 0); f.retired();
  assert.equal((await f.view.close()).pending, false);
});

test('Project Source uses the retained Plan coordinates and refuses swapped or foreign originals before a child', async () => {
  const f = await fixture();
  for (const changed of [{stage: 1}, {input: 0}, {task: 0}, {computeTask: 1}]) {
    assert.throws(() => f.child(1, changed), {code: 'InstalledSourcePreparationMismatch'});
  }
  assert.throws(() => f.child(2), {code: 'OriginalPlanSlotUnavailable'});
  assert.throws(() => f.view.prepareRead({}, f.declaration, f.managed,
    {stage: 0, input: 1, task: 1, computeTask: 0}, f.identity));
  assert.throws(() => f.view.prepareRead(f.prepared, {}, f.managed,
    {stage: 0, input: 1, task: 1, computeTask: 0}, f.identity), {code: 'InstalledSourcePreparationMismatch'});
  assert.throws(() => f.view.prepareRead(f.prepared, f.declaration, {},
    {stage: 0, input: 1, task: 1, computeTask: 0}, f.identity), {code: 'InstalledSourcePreparationMismatch'});
  assert.throws(() => f.view.prepareRead(f.prepared, f.declaration, f.managed,
    {stage: 0, input: 1, task: 1, computeTask: 0}, {}));
  const child = f.child(1);
  let closed = false;
  child.retainChild({status: () => ({pending: !closed}),
    close() {closed = true; return {pending: false};}});
  f.finish();
  assert.equal((await child.close()).pending, false);
  f.sever(); assert.equal(f.ports.status(2), 0); f.retired();
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
  f.sever(); assert.equal(f.ports.status(2), 0); f.retired();
  assert.equal((await f.view.close()).pending, false);
});

// Execute the real Host's quote projection with explicit Core/Project ports.
// Actual Core compilation and the integrated Host remain separate checks.
test('Project Source retirement fences new children while original physical cleanup remains live', async () => {
  const f = await fixture(), child = f.child();
  let closed = false;
  child.retainChild({status: () => ({pending: !closed}),
    close() {closed = true; return {pending: false};}});
  f.finish(); f.sever();
  assert.throws(() => f.child(1), {code: 'InstalledSourcePreparationMismatch'});
  assert.equal(f.ports.status(2), -42);
  assert.equal((await child.close()).pending, false);
  assert.equal(f.ports.status(2), 0); f.retired();
  assert.equal((await f.view.close()).pending, false);
});

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
  const manifests = {}, admission = {}, installationCalls = [];
  const moon = {
    clientPrepareInstalledCompilationManifests(...args) {
      assert.strictEqual(this, moon); assert.deepEqual(args, []);
      installationCalls.push('manifests'); return manifests;
    },
    clientPrepareInstalledSequenceContracts(...args) {
      assert.strictEqual(this, moon); assert.equal(installationCalls.at(-1), 'manifests');
      assert.deepEqual(args, ['spec/dependencies/aoa-pipeline-registry.json', '{}', '{}', '{}']);
      installationCalls.push('sequence'); return admission;
    },
    clientProgramAcquisitionCount: prepared => {assert.strictEqual(prepared, original); return refs.length;},
    clientProgramPrepareLocalQueryRequirement(...args) {
      assert.strictEqual(args[0], original); assert.equal(args[2], 0);
      assert.strictEqual(args[3], admission);
      calls.push(['requirement', args[1]]); return {ref: refs[args[1]]};
    },
    clientProgramQueryRequirementSourceRef: requirement => requirement.ref,
    clientProgramInstalledManagedRunRequirements(...args) {
      assert.strictEqual(args[6], admission);
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
  const prepare = hostAst.body.find(node => node.type === 'ExportNamedDeclaration' &&
    node.declaration?.type === 'FunctionDeclaration' &&
    node.declaration.id.name === 'prepareInstalledSequenceContractOriginal').declaration;
  assert(prepare);
  const quote = new Function(...Object.keys(ports), `${hostSource.slice(contracts.start, contracts.end)};
    ${hostSource.slice(prepare.start, prepare.end)};
    ${hostSource.slice(node.start, node.end)};
    return readSourceManagedRunRequirementsOwned;`)(...Object.values(ports));
  return {declarations, calls, original, installationCalls, quote: () => quote(originals, original, false),
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
    assert.deepEqual(f.installationCalls, ['manifests', 'sequence'], 'One retained installed contract admission');
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
  assert.deepEqual(missing.installationCalls, ['manifests', 'sequence']);
  const changed = quoteFixture(['source0']); changed.invalidate();
  assert.throws(changed.quote, /OriginalHostChanged/u);
  assert.deepEqual(changed.calls, []);
  assert.deepEqual(changed.installationCalls, [], 'A retired Host cannot prepare new installed contracts');
});
