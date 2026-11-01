// Adapter delegation with explicit ports, not a nominal resource issuer or
// an actual Model/Host qualification. The same Common Owner performs admission.
import assert from 'node:assert/strict';
import test from 'node:test';
import {openNodeComposedInferProvider, openNodeInferOperation} from './infer-operation.mjs';
import * as inferOperation from './infer-operation.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

const originalReadCleaned = read => inferOperation.inferOriginalReadCleanupComplete?.(read) === true;

function fixture({claimIssue, startIssue} = {}) {
  const active = {}, consumer = {}, read = {}, rawCompiled = {}, rawDefinition = {}, scope = {};
  const occurrence = {}, graph = {}, prefix = {}, sources = {}, provider = {};
  const inputs = [{producer: 'left'}, {producer: 'right'}], calls = [];
  let claimed = false, stopped = false;
  const moon = {
    strategyRemoteManagedOutputEvidenceKind: () => 'fixture-managed-output',
    // Construct wrappers through the existing private-map Owner, not a raw
    // getter, map injection or a hand-authored public wrapper object.
    strategyPublicationAdmit: () => ({$tag: 1, _0: rawDefinition}),
    strategyPublicationContractName: () => 'run_definition',
    strategyPublicationContractIdentityField: () => 'run_definition_cid',
    strategyPublicationContractIdentity: () => 'definition',
    strategyPublicationContractJson: () => '{}',
    strategyRunEvidenceName: () => 'fixture-evidence',
    strategyRunEvidenceIdentity: () => 'evidence',
    strategyRunEvidenceJson: () => '{}',
    clientProgramCompileLocalInfer: () => ({$tag: 1, _0: {}}),
    clientProgramIssueTaskCompiledRun: () => ({$tag: 1, _0: rawCompiled}),
    clientProgramBindCompiledInferResultPolicy: value => ({$tag: 1, _0: value}),
    clientProgramCompiledRunTemplate: () => ({}),
    clientProgramCompiledRunPlan: () => ({}),
    clientProgramCompiledRunPrepared: () => ({}),
    clientProgramCompiledRunAuthorization: () => ({}),
    clientProgramCompiledRunAdmission: () => ({}),
    clientProgramClaimInferOriginalPreparation(...args) {
      calls.push(['claim', ...args]);
      if (claimIssue !== undefined || claimed) return {$tag: 0, _0: claimIssue ?? 'SpentClaim'};
      claimed = true;
      return {$tag: 1, _0: consumer};
    },
    clientProgramStartOriginalComposedInferExecution(...args) {
      calls.push(['start', ...args]);
      return startIssue === undefined ? {$tag: 1, _0: active} : {$tag: 0, _0: startIssue};
    },
    clientProgramStartOriginalInferExecution() { assert.fail('not a source-free original'); },
    clientProgramStartComposedInferExecution() { assert.fail('never fall back to an unowned composed start'); },
    clientProgramCancelInferExecution(value) { assert.strictEqual(value, active); stopped = true; },
    clientProgramInferExecutionStopped(value) { assert.strictEqual(value, active); return stopped; },
    clientProgramCleanupInferExecution(value) { assert.strictEqual(value, active); return {$tag: 1, _0: true}; },
  };
  const control = runtimeCore(moon).publicationControl;
  const runDefinition = control.admit('run_definition', '{}', {maxWireBytes: 2, maxNodes: 1, maxDepth: 1});
  const compiled = control.prepareCheckedClientCompiledRun({}, 'infer', {
    resultDataPolicy: {kind: 'data_policy', cid: 'fixture-policy', wire: '{}'},
  }, graph);
  const originalPreparation = {compiled, runDefinition, scope, read, control,
    readRetainedBytes: 7n, readExecutionBytes: 5n,
    modelRetainedBytes: 100n, modelExecutionBytes: 0n};
  const options = {moon, graph, provider, originalPreparation,
    composedInput: {occurrence, prefix, inputs, sources}};
  return {moon, active, consumer, rawCompiled, rawDefinition, originalPreparation, occurrence, graph, prefix,
    sources, inputs, provider, calls, options};
}

function expectOriginalStart(f) {
  const p = f.originalPreparation;
  const expected = [f.occurrence, f.graph, f.prefix, f.inputs, f.provider,
    f.rawCompiled, f.rawDefinition, f.consumer, 7n, 5n, 100n, 0n, f.sources];
  assert.deepEqual(f.calls[0], ['claim', p.read, f.rawCompiled, f.rawDefinition, f.graph, 7n, 5n]);
  assert.equal(f.calls[1][0], 'start');
  assert.equal(f.calls[1].length, expected.length + 1);
  for (const [index, value] of expected.entries()) assert.strictEqual(f.calls[1][index + 1], value);
}

test('original read cleanup is observable only after the actual Core execution acknowledges it', async () => {
  const f = fixture(), read = f.originalPreparation.read;
  let ready = false, cleanups = 0;
  f.moon.clientProgramCleanupInferExecution = active => {
    assert.strictEqual(active, f.active); cleanups++; return {$tag: 1, _0: ready};
  };
  const operation = openNodeInferOperation(f.options);
  assert.equal(originalReadCleaned(read), false);
  assert.equal(operation.cleanup(), false);
  assert.equal(cleanups, 0);
  await operation.stop();
  assert.equal(originalReadCleaned(read), false);
  assert.equal(operation.cleanup(), false);
  assert.equal(cleanups, 1);
  assert.equal(originalReadCleaned(read), false);
  ready = true;
  assert.equal(operation.cleanup(), true);
  assert.equal(originalReadCleaned(read), true);
  assert.equal(operation.cleanup(), true);
  assert.equal(cleanups, 2);
});

test('original read cleanup never acknowledges copied foreign or sibling read tokens', async () => {
  const f = fixture(), other = fixture();
  const operation = openNodeInferOperation(f.options), sibling = openNodeInferOperation(other.options);
  const read = f.originalPreparation.read, foreign = other.originalPreparation.read;
  await sibling.close();
  assert.equal(originalReadCleaned(foreign), true);
  assert.equal(originalReadCleaned(read), false);
  await operation.close();
  assert.equal(originalReadCleaned(read), true);
  for (const value of [{...read}, {}, undefined, null, 0, 'same-looking-token']) {
    assert.equal(originalReadCleaned(value), false);
  }
});

test('original read cleanup preserves a thrown original failure without inventing an acknowledgement', async () => {
  const f = fixture(), issue = Object.freeze({issue: 'OriginalCleanupUnknown'});
  const operation = openNodeInferOperation(f.options), read = f.originalPreparation.read;
  f.moon.clientProgramCleanupInferExecution = () => ({$tag: 0, _0: issue});
  await operation.stop();
  assert.throws(() => operation.cleanup(), error => error.code === 'MoonBitHostFailure' && error.cause === issue);
  assert.equal(originalReadCleaned(read), false);
  assert.equal(operation.cleanupPending(), true);
  f.moon.clientProgramCleanupInferExecution = () => ({$tag: 1, _0: true});
  assert.equal(operation.cleanup(), true);
  assert.equal(originalReadCleaned(read), true);
});

test('original read cleanup retains the exact claimed token rather than a later property replacement', async () => {
  const f = fixture(), read = f.originalPreparation.read;
  const operation = openNodeInferOperation(f.options);
  const replaced = f.originalPreparation.read = {};
  await operation.close();
  assert.equal(originalReadCleaned(read), true);
  assert.equal(originalReadCleaned(replaced), false);
});

test('original read cleanup cannot acknowledge an unclaimed or failed-construction read', () => {
  const f = fixture({startIssue: 'OriginalStartFailure'});
  assert.throws(() => openNodeInferOperation(f.options), error =>
    error.code === 'MoonBitHostFailure' && error.cause === 'OriginalStartFailure');
  assert.equal(originalReadCleaned(f.originalPreparation.read), false);
  const rejected = fixture({claimIssue: 'ForeignOriginalRead'});
  assert.throws(() => openNodeInferOperation(rejected.options), error =>
    error.code === 'MoonBitHostFailure' && error.cause === 'ForeignOriginalRead');
  assert.equal(originalReadCleaned(rejected.originalPreparation.read), false);
});

test('original composed start claims once and forwards the same read and producer inputs without IO ports', async () => {
  const f = fixture();
  const operation = openNodeInferOperation(f.options);
  expectOriginalStart(f);
  assert.strictEqual(operation.originalResourceScope(), f.originalPreparation.scope);
  assert.equal(f.calls.length, 2);
  await assert.rejects(operation.run(), {message: 'InferComponentDrivenByLocal'});
  assert.throws(() => openNodeInferOperation(f.options), error =>
    error.code === 'MoonBitHostFailure' && error.cause === 'SpentClaim');
  assert.equal(f.calls.filter(x => x[0] === 'start').length, 1);
  await operation.close();
});

test('original composed claim refusal is returned before start with no replacement claim', () => {
  const cause = Object.freeze({issue: 'ForeignOriginalRun'}), f = fixture({claimIssue: cause});
  assert.throws(() => openNodeInferOperation(f.options), error =>
    error.code === 'MoonBitHostFailure' && error.cause === cause);
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0][0], 'claim');
});

test('original composed start refusal remains typed and cannot reset the same consumed claim', () => {
  const cause = Object.freeze({issue: 'ChangedOriginalRead'}), f = fixture({startIssue: cause});
  assert.throws(() => openNodeInferOperation(f.options), error =>
    error.code === 'MoonBitHostFailure' && error.cause === cause);
  expectOriginalStart(f);
  assert.throws(() => openNodeInferOperation(f.options), error =>
    error.code === 'MoonBitHostFailure' && error.cause === 'SpentClaim');
  assert.equal(f.calls.filter(x => x[0] === 'start').length, 1);
});

test('original composed input does not reinterpret legacy node installation or saved input as fresh preparation', () => {
  for (const mutate of [
    f => { f.originalPreparation.nodeInstallation = {}; },
    f => { f.options.restoredInput = {}; },
    f => { f.options.acquiredInput = {}; },
    f => { f.options.keyedInput = {}; },
    f => { f.options.savedCapture = {}; },
    f => { f.options.savedSlots = {}; },
  ]) {
    const f = fixture(); mutate(f);
    assert.throws(() => openNodeInferOperation(f.options), /InvalidInferOriginalPreparation/u);
    assert.equal(f.calls.length, 0);
  }
});

test('original composed control refuses copied wrappers and a foreign private-map namespace before claim', () => {
  for (const mutate of [
    f => { f.originalPreparation.compiled = {...f.originalPreparation.compiled}; },
    f => { f.originalPreparation.runDefinition = {...f.originalPreparation.runDefinition}; },
    f => { f.originalPreparation.control = runtimeCore({...f.moon}).publicationControl; },
  ]) {
    const f = fixture(); mutate(f);
    assert.throws(() => openNodeInferOperation(f.options), /Foreign (?:Client compiled Infer preparation|publication contract)/u);
    assert.equal(f.calls.length, 0);
  }
});

test('original composed provider retains original preparation through the existing Local callback and Run binding', async () => {
  const f = fixture(); let open, retained;
  f.moon.clientProgramComposedInferLocalProvider = (occurrence, callback) => {
    assert.strictEqual(occurrence, f.occurrence); open = callback; return f.provider;
  };
  const plan = {compiled: f.originalPreparation.compiled, runDefinition: f.originalPreparation.runDefinition};
  const control = {
    bindCheckedClientInferRun(compiled, active, definition) {
      assert.strictEqual(compiled, plan.compiled); assert.strictEqual(active, f.active);
      assert.strictEqual(definition, plan.runDefinition); assert(retained); f.calls.push(['run']);
    },
    bindCheckedClientInferDispatch(compiled, active, definition) {
      assert.strictEqual(compiled, plan.compiled); assert.strictEqual(active, f.active);
      assert.strictEqual(definition, plan.runDefinition); f.calls.push(['dispatch']);
    },
  };
  const result = openNodeComposedInferProvider({moon: f.moon, sources: f.sources,
    selected: {occurrence: f.occurrence, graph: f.graph, computePrefix: f.prefix, provider: f.provider},
    originalPreparation: f.originalPreparation, control, plan, now: () => '2026-10-20T00:00:00.000Z',
    retainOperation(value) { retained = value; f.calls.push(['retain']); }});
  assert.deepEqual(f.calls, []);
  assert.strictEqual(open(f.inputs), f.active);
  expectOriginalStart(f);
  assert.deepEqual(f.calls.map(x => x[0]), ['claim', 'start', 'retain', 'run', 'dispatch']);
  assert.strictEqual(retained.originalResourceScope(), f.originalPreparation.scope);
  assert.strictEqual(result.operation(), retained);
  assert.equal(result.failure(), undefined);
  await retained.close();
});

function deferredProvider(f, originalPreparation) {
  let open;
  f.moon.clientProgramComposedInferLocalProvider = (_occurrence, callback) => {
    open = callback; return f.provider;
  };
  const component = openNodeComposedInferProvider({moon: f.moon, sources: f.sources,
    selected: {occurrence: f.occurrence, graph: f.graph, computePrefix: f.prefix, provider: f.provider},
    originalPreparation, plan: {compiled: f.originalPreparation.compiled,
      runDefinition: f.originalPreparation.runDefinition},
    control: {
      bindCheckedClientInferRun() { f.calls.push(['run']); },
      bindCheckedClientInferDispatch() { f.calls.push(['dispatch']); },
    }, now: () => '2026-10-20T00:00:00.000Z',
    retainOperation() { f.calls.push(['retain']); }});
  return {component, open: () => open(f.inputs)};
}

test('deferred composed read is issued after inputs arrive using the captured original callback and receiver', async () => {
  const f = fixture(), view = Object.freeze(f.originalPreparation);
  let sourcesReady = false, reads = 0;
  const original = {prepareRead() {
    assert.strictEqual(this, original); assert(sourcesReady);
    reads++; f.calls.push(['prepareRead']); return view;
  }};
  const {component, open} = deferredProvider(f, original);
  assert.equal(reads, 0); assert.deepEqual(f.calls, []);
  await Promise.resolve();
  sourcesReady = true;
  original.prepareRead = () => assert.fail('replacement read issuer');
  assert.strictEqual(open(), f.active);
  assert.equal(reads, 1);
  assert.deepEqual(f.calls.map(x => x[0]), ['prepareRead', 'claim', 'start', 'retain', 'run', 'dispatch']);
  assert.strictEqual(f.calls[1][1], view.read);
  assert.strictEqual(component.operation().originalResourceScope(), view.scope);
  assert.equal(open(), undefined); assert.equal(reads, 1);
  await component.operation().close();
});

test('deferred composed read failure remains the original failure without a replacement attempt', () => {
  const f = fixture(), cause = new Error('OriginalReadIssueFailed'); let reads = 0;
  const {component, open} = deferredProvider(f, {prepareRead() { reads++; throw cause; }});
  assert.equal(open(), undefined);
  assert.strictEqual(component.failure(), cause);
  assert.equal(open(), undefined);
  assert.strictEqual(component.failure(), cause);
  assert.equal(reads, 1); assert.equal(f.calls.length, 0);
});

test('deferred composed claim refusal preserves the same issued read and cannot issue another', () => {
  const cause = Object.freeze({issue: 'ChangedOriginalRead'}), f = fixture({claimIssue: cause});
  let reads = 0;
  const {component, open} = deferredProvider(f, {prepareRead() { reads++; return Object.freeze(f.originalPreparation); }});
  assert.equal(open(), undefined);
  const failure = component.failure(); assert.strictEqual(failure.cause, cause);
  assert.equal(open(), undefined);
  assert.strictEqual(component.failure(), failure);
  assert.equal(reads, 1); assert.equal(f.calls.length, 1);
  assert.strictEqual(f.calls[0][1], f.originalPreparation.read);
});

test('deferred composed read cannot return no view or an asynchronous view and fall back to an unowned start', () => {
  for (const result of [undefined, null, Promise.resolve({})]) {
    const f = fixture(); let reads = 0;
    const {component, open} = deferredProvider(f, {prepareRead() { reads++; return result; }});
    assert.equal(open(), undefined);
    assert.equal(component.failure()?.message, 'InvalidComposedInferOriginalPreparation');
    const failure = component.failure(); assert.equal(open(), undefined);
    assert.strictEqual(component.failure(), failure);
    assert.equal(reads, 1); assert.equal(f.calls.length, 0);
  }
});

test('deferred composed read never invokes an inherited then getter on the returned original', async () => {
  const f = fixture(); let observed = 0;
  const prototype = {get then() { observed++; throw new Error('UnownedThenGetter'); }};
  const view = Object.freeze(Object.assign(Object.create(prototype), f.originalPreparation));
  const {component, open} = deferredProvider(f, {prepareRead() { return view; }});
  assert.strictEqual(open(), f.active);
  assert.equal(observed, 0);
  assert.equal(component.failure(), undefined);
  await component.operation().close();
});


function originalNodeComposedFixture({refuse = false} = {}) {
  const f = fixture(), layout = {}, installation = {}, probability = {},
    nodeInstallation = Object.freeze({layout, installation, probability,
      runtimeArtifactCid: 'original-runtime', layoutArtifactCid: 'original-layout'});
  f.originalPreparation.nodeInstallation = nodeInstallation;
  const cause = Object.freeze({issue: 'OriginalNodeLayoutRefusal'});
  let claims = 0;
  f.moon.clientProgramClaimInferNodePreparationLayout = (...actual) => {
    claims++;
    const expected = [f.originalPreparation.read, f.rawCompiled, f.rawDefinition,
      f.graph, layout, installation, 'original-runtime', 'original-layout', probability];
    assert.equal(actual.length, expected.length);
    for (const [i, value] of expected.entries()) assert.strictEqual(actual[i], value);
    f.calls.push(['layout-claim', ...actual]);
    return refuse ? {$tag: 0, _0: cause} : {$tag: 1, _0: f.consumer};
  };
  f.moon.clientProgramClaimInferOriginalPreparation = () => assert.fail('Node installation cannot use the private envelope claim');
  return {...f, cause, claims: () => claims};
}

test('installed Node composed input claims the same original layout before its original composed start', async () => {
  const f = originalNodeComposedFixture();
  const operation = openNodeInferOperation(f.options);
  assert.equal(f.claims(), 1);
  assert.equal(f.calls[0][0], 'layout-claim');
  assert.equal(f.calls[1][0], 'start');
  assert.strictEqual(f.calls[1][3], f.prefix);
  assert.strictEqual(f.calls[1][8], f.consumer);
  assert.strictEqual(operation.originalResourceScope(), f.originalPreparation.scope);
  await operation.close();
  assert.equal(originalReadCleaned(f.originalPreparation.read), true);
});

test('installed Node composed layout refusal preserves the original cause and never retries an envelope or unowned start', () => {
  const f = originalNodeComposedFixture({refuse: true});
  assert.throws(() => openNodeInferOperation(f.options), error =>
    error.code === 'MoonBitHostFailure' && error.cause === f.cause);
  assert.equal(f.claims(), 1);
  assert.equal(f.calls.length, 1);
  assert.equal(originalReadCleaned(f.originalPreparation.read), false);
});
