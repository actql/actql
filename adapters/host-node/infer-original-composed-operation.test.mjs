// Adapter delegation with explicit ports, not a nominal resource issuer or
// an actual Model/Host qualification. The same Common Owner performs admission.
import assert from 'node:assert/strict';
import test from 'node:test';
import {openNodeComposedInferProvider, openNodeInferOperation} from './infer-operation.mjs';
import * as inferOperation from './infer-operation.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {createInferIoNotification} from './infer-io-notification.mjs';

const originalReadCleaned = read => inferOperation.inferOriginalReadCleanupComplete?.(read) === true;

function fixture({claimIssue, startIssue} = {}) {
  const active = {}, consumer = {}, read = {}, rawCompiled = {}, rawDefinition = {}, scope = {}, prepared = {};
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
  const compiled = control.prepareCheckedClientCompiledRun(prepared, 'infer', {
    resultDataPolicy: {kind: 'data_policy', cid: 'fixture-policy', wire: '{}'},
  }, graph);
  const originalPreparation = {compiled, runDefinition, scope, read, control,
    readRetainedBytes: 7n, readExecutionBytes: 5n,
    modelRetainedBytes: 100n, modelExecutionBytes: 0n};
  const options = {moon, graph, provider, originalPreparation,
    composedInput: {occurrence, prefix, inputs, sources}};
  return {moon, active, consumer, rawCompiled, rawDefinition, prepared, originalPreparation, occurrence, graph, prefix,
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

function deferredProvider(f, originalPreparation, restoredInput, deferred = false) {
  let open;
  f.moon.clientProgramComposedInferLocalProvider = (_occurrence, callback) => {
    open = callback; return f.provider;
  };
  const selected = {occurrence: f.occurrence, graph: f.graph, computePrefix: f.prefix, provider: f.provider};
  const context = {selected, sources: f.sources, originalPreparation, restoredInput,
    plan: {compiled: f.originalPreparation.compiled, runDefinition: f.originalPreparation.runDefinition},
    control: {
      bindCheckedClientInferRun() { f.calls.push(['run']); },
      bindCheckedClientInferDispatch() { f.calls.push(['dispatch']); },
    }, now: () => '2026-10-20T00:00:00.000Z',
    retainOperation() { f.calls.push(['retain']); }};
  const component = openNodeComposedInferProvider(deferred
    ? {moon: f.moon, selected, deferred: true} : {moon: f.moon, ...context});
  if (deferred) component.bindOriginal(context);
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


test('Request composed suffix binder receives the same active only after original operation custody and retains typed failure', async () => {
  const f = originalNodeComposedFixture(), cause = Object.freeze({issue: 'OriginalSuffixBindingRefused'});
  let open, retained, binds = 0;
  f.moon.clientProgramComposedInferLocalProvider = (_occurrence, actualOpen) => {open = actualOpen; return {};};
  const component = openNodeComposedInferProvider({moon: f.moon,
    selected: {occurrence: f.occurrence, graph: f.graph, provider: f.provider,
      computeSuffix: Object.freeze({source: 'earlier-query-selection'})},
    sources: f.sources, control: f.originalPreparation.control,
    originalPreparation: f.originalPreparation,
    retainOperation(value) {retained = value;},
    bindComputeSuffix(active) {
      assert.strictEqual(active, f.active); assert(retained); binds++;
      return {$tag: 0, _0: cause};
    }});
  assert.strictEqual(open(f.inputs), undefined);
  assert.equal(binds, 1); assert.strictEqual(component.operation(), retained);
  assert.strictEqual(component.failure().cause, cause);
  assert.strictEqual(component.failure().cleanupOwner, retained);
  assert.equal(originalReadCleaned(f.originalPreparation.read), false);
  await retained.close();
  assert.equal(originalReadCleaned(f.originalPreparation.read), true);
});


function originalRestoredFixture() {
  const f = fixture(), savedScope = {}, token = {available: true}, snapshot = {
    binding: 'original-input', descriptorWire: 'original-descriptor', rows: ['original-row'],
  };
  f.moon.clientProgramStartOriginalRestoredComposedInferExecution = (...args) => {
    f.calls.push(['restore', ...args]); return {$tag: 1, _0: f.active};
  };
  const sendMask = [false];
  f.moon.clientProgramRestrictInferSendSlots = (active, mask) => {
    assert.strictEqual(active, f.active); assert.strictEqual(mask, sendMask);
    f.calls.push(['mask']); return {$tag: 1, _0: undefined};
  };
  f.moon.clientProgramStartRestoredComposedInferInput = () => assert.fail('no unowned restored input');
  return {...f, restoredInput: {savedScope, token, snapshot, sendMask}};
}

test('original restored composed read uses its explicit cold port and same nominal original before saved input', async () => {
  const f = originalRestoredFixture(), view = Object.freeze(f.originalPreparation);
  let reads = 0;
  const original = {
    prepareRead() { assert.fail('saved input is never fresh preparation'); },
    restoreRead(input) {
      assert.strictEqual(this, original); assert.strictEqual(input, f.restoredInput);
      reads++; f.calls.push(['restoreRead']); return view;
    },
  };
  const {component, open} = deferredProvider(f, original, f.restoredInput, true);
  assert.equal(reads, 0); const active = open();
  assert.equal(component.failure(), undefined); assert.strictEqual(active, f.active);
  assert.deepEqual(f.calls.map(x => x[0]), ['restoreRead', 'claim', 'restore', 'retain', 'mask', 'run', 'dispatch']);
  assert.deepEqual(f.calls[1], ['claim', view.read, f.rawCompiled, f.rawDefinition, f.graph, 7n, 5n]);
  const args = f.calls[2].slice(1), input = f.restoredInput;
  const expected = [f.occurrence, f.graph, f.prefix, f.provider,
    input.snapshot.binding, input.snapshot.descriptorWire, input.snapshot.rows,
    args[7], input.savedScope, f.rawCompiled, f.rawDefinition, f.consumer,
    7n, 5n, 100n, 0n, undefined];
  sameArguments(args, expected);
  assert.equal(args[7](), true); input.token.available = false; assert.equal(args[7](), false);
  assert.strictEqual(component.operation().originalResourceScope(), view.scope);
  assert.equal(open(), undefined); assert.equal(reads, 1);
  await component.operation().close();
});

function sameArguments(actual, expected) {
  assert.equal(actual.length, expected.length);
  actual.forEach((value, i) => assert.strictEqual(value, expected[i]));
}

test('original restored composed read refuses a fresh-only owner before issuing or claiming anything', () => {
  const f = originalRestoredFixture(); let reads = 0;
  assert.throws(() => deferredProvider(f, {prepareRead() { reads++; return f.originalPreparation; }},
    f.restoredInput), /InvalidComposedInferOriginalPreparation/u);
  assert.equal(reads, 0); assert.equal(f.calls.length, 0);
});

test('original restored composed failure retains the original owner failure without reissuing its read', () => {
  const f = originalRestoredFixture(), cause = new Error('OriginalColdReadPending'); let reads = 0;
  const {component, open} = deferredProvider(f, {restoreRead() { reads++; throw cause; }}, f.restoredInput);
  assert.equal(open(), undefined); assert.strictEqual(component.failure(), cause);
  assert.equal(open(), undefined); assert.strictEqual(component.failure(), cause);
  assert.equal(reads, 1); assert.equal(f.calls.length, 0);
});

test('original restored composed private control refuses foreign compiled and Definition wrappers before saved start', () => {
  for (const mutate of [
    f => { f.originalPreparation.compiled = {...f.originalPreparation.compiled}; },
    f => { f.originalPreparation.runDefinition = {...f.originalPreparation.runDefinition}; },
    f => { f.originalPreparation.control = runtimeCore({...f.moon}).publicationControl; },
  ]) {
    const f = originalRestoredFixture(); mutate(f);
    assert.throws(() => openNodeInferOperation({...f.options, originalPreparation: undefined,
      restoredPreparation: f.originalPreparation, restoredInput: f.restoredInput}),
    /Foreign (?:Client compiled Infer preparation|publication contract)/u);
    assert.equal(f.calls.length, 0);
  }
});

test('original restored composed input cannot combine fresh and cold originals or omit the saved scope', () => {
  for (const mutate of [
    options => { options.originalPreparation = options.restoredPreparation; },
    options => { options.restoredInput = {}; },
    options => { options.composedInput = undefined; },
    options => { options.keyedInput = {}; },
  ]) {
    const f = originalRestoredFixture(), options = {...f.options, originalPreparation: undefined,
      restoredPreparation: f.originalPreparation, restoredInput: f.restoredInput};
    mutate(options);
    assert.throws(() => openNodeInferOperation(options), /InvalidInferOriginalPreparation/u);
    assert.equal(f.calls.length, 0);
  }
});


test('a direct original operation still refuses simultaneous suffix issuers before claiming a read', () => {
  const f = fixture();
  assert.throws(() => openNodeInferOperation({...f.options,
    computeSuffix: {}, bindComputeSuffix() {assert.fail('no suffix callback before refusal');}}),
  {message: 'InvalidInferOriginalSuffixBinding'});
  assert.equal(f.calls.length, 0);
  assert.equal(originalReadCleaned(f.originalPreparation.read), false);
});

// The same composed input representation can belong to one direct checked
// Unit. This explicit-port test enters the real adapter/opaque compiled Owner;
// it does not issue physical capacity, Model send authority or ordinary IO.
test('original single Unit composed input runs its same retained kernel instead of the Local component fence', async () => {
  const f = fixture(), preparedCallSet = {}, poll = {}, events = [];
  f.options.preparedProgram = f.prepared;
  f.inputs.length = 0;
  f.moon.clientProgramCompiledRunMatches = (compiled, prepared) => {
    assert.equal(compiled, f.rawCompiled); events.push('same compiled owner');
    return prepared === f.prepared;
  };
  f.moon.clientProgramTaskCount = value => {assert.equal(value, f.prepared); return 1;};
  f.moon.clientProgramAcquisitionCount = value => {assert.equal(value, f.prepared); return 1;};
  f.moon.clientProgramAdvanceInferExecution = (active, quantum) => {
    assert.equal(active, f.active); assert.equal(quantum, 256);
    events.push('original advance'); return {$tag: 1, _0: poll};
  };
  f.moon.clientProgramInferExecutionPollKind = value => {assert.equal(value, poll); return 'waiting';};
  f.moon.clientProgramInferPreparedCallSet = active => {assert.equal(active, f.active); return preparedCallSet;};
  const operation = openNodeInferOperation(f.options);
  expectOriginalStart(f);
  assert.deepEqual(await operation.run(), {status: 'waiting', preparedCallSet});
  assert.deepEqual(events, ['same compiled owner', 'original advance']);
  await operation.close();
  assert.equal(originalReadCleaned(f.originalPreparation.read), true);
});

test('original single Unit driver refuses foreign Prepared and non-single captured shape before claiming a read', () => {
  for (const mode of ['foreign', 'multiple', 'source-free', 'missing-source']) {
    const f = fixture();
    f.options.preparedProgram = mode === 'foreign' ? {} : f.prepared;
    f.inputs.length = 0;
    if (mode === 'missing-source') f.options.composedInput.sources = undefined;
    f.moon.clientProgramCompiledRunMatches = (compiled, prepared) => {
      assert.equal(compiled, f.rawCompiled); return prepared === f.prepared;
    };
    f.moon.clientProgramTaskCount = () => mode === 'multiple' ? 2 : 1;
    f.moon.clientProgramAcquisitionCount = () => mode === 'source-free' ? 0 : 1;
    assert.throws(() => openNodeInferOperation(f.options), mode === 'foreign'
      ? /Foreign Client compiled Run/ : /InvalidInferOriginalComposedRun/);
    assert.equal(f.calls.length, 0, mode+' must not spend its original claim');
  }
});

test('original single Unit asynchronous drive retains the same nominal IO wake and original current boundaries', async () => {
  const f = fixture(), waiting = {}, ioPoll = {}, preparedCallSet = {}, events = [];
  f.options.preparedProgram = f.prepared;
  f.inputs.length = 0;
  const notification = createInferIoNotification();
  f.options.ioNotification = notification;
  f.options.assertRuntimeCurrent = () => events.push('original current');
  f.moon.clientProgramBindInferPhysicalPreflightCurrent = () => {assert.fail('No physical callback is installed by this fixture');};
  f.moon.clientProgramCompiledRunMatches = (compiled, prepared) => {
    assert.equal(compiled, f.rawCompiled); return prepared === f.prepared;
  };
  f.moon.clientProgramTaskCount = () => 1;
  f.moon.clientProgramAcquisitionCount = () => 1;
  let advances = 0;
  f.moon.clientProgramAdvanceInferExecution = active => {
    assert.equal(active, f.active); events.push('original advance');
    if (advances++ === 0) {notification.notify(); return {$tag: 1, _0: ioPoll};}
    return {$tag: 1, _0: waiting};
  };
  f.moon.clientProgramInferExecutionPollKind = poll => poll === ioPoll ? 'await_io' : 'waiting';
  f.moon.clientProgramInferPreparedCallSet = active => {assert.equal(active, f.active); return preparedCallSet;};
  // The existing runtime observation binding remains its own original gate.
  f.moon.clientProgramBindInferModelObservation = (active, prepared, callback) => {
    assert.equal(active, f.active); assert.equal(prepared, preparedCallSet);
    assert.equal(typeof callback, 'function'); return true;
  };
  const operation = openNodeInferOperation(f.options);
  assert.deepEqual(await operation.run(), {status: 'waiting', preparedCallSet});
  assert.equal(advances, 2);
  assert.ok(events.filter(value => value === 'original current').length >= 2);
  await operation.close();
  assert.equal(notification.notify(), false);
  assert.equal(originalReadCleaned(f.originalPreparation.read), true);
});

test('original restored single Unit drives its saved kernel for zero or one Source without reopening input', async () => {
  for (const sourceCount of [0, 1]) {
    const f = originalRestoredFixture(), waiting = {}, preparedCallSet = {};
    const options = {...f.options, preparedProgram: f.prepared, originalPreparation: undefined,
      restoredPreparation: f.originalPreparation, restoredInput: f.restoredInput};
    f.moon.clientProgramCompiledRunMatches = (compiled, prepared) =>
      compiled === f.rawCompiled && prepared === f.prepared;
    f.moon.clientProgramTaskCount = () => 1;
    f.moon.clientProgramAcquisitionCount = () => sourceCount;
    f.moon.clientProgramAdvanceInferExecution = active => {
      assert.strictEqual(active, f.active); return {$tag: 1, _0: waiting};
    };
    f.moon.clientProgramInferExecutionPollKind = () => 'waiting';
    f.moon.clientProgramInferPreparedCallSet = () => preparedCallSet;
    const operation = openNodeInferOperation(options);
    assert.deepEqual(await operation.run(), {status: 'waiting', preparedCallSet});
    assert.equal(f.calls.filter(value => value[0] === 'restore').length, 1);
    assert.equal(f.calls.filter(value => value[0] === 'start').length, 0);
    await operation.close();
    assert.equal(originalReadCleaned(f.originalPreparation.read), true);
  }
});


test('restored composed provider drives its same original operation before Host construction and never reopens Local', async () => {
  const f = fixture(), savedScope = {}, snapshot = {binding: 'saved-binding', descriptorWire: 'saved-descriptor', rows: ['same saved row']};
  const restoredInput = {savedScope, snapshot, token: {available: true}};
  let localOpen, retained, claims = 0, advances = 0;
  f.moon.clientProgramComposedInferLocalProvider = (_occurrence, open) => {localOpen = open; return {};};
  f.moon.clientProgramStartOriginalRestoredComposedInferExecution = (...args) => {
    assert.strictEqual(args[0], f.occurrence); assert.strictEqual(args[4], snapshot.binding);
    assert.strictEqual(args[8], savedScope); assert.strictEqual(args[9], f.rawCompiled);
    assert.strictEqual(args[10], f.rawDefinition); return {$tag: 1, _0: f.active};
  };
  f.moon.clientProgramBindInferRun = () => ({$tag: 1, _0: undefined});
  f.moon.clientProgramRequireInferCallEntry = () => ({$tag: 1, _0: undefined});
  f.moon.clientProgramRestrictInferSendSlots = () => ({$tag: 1, _0: undefined});
  f.moon.clientProgramAdvanceInferExecution = value => {
    assert.strictEqual(value, f.active); assert.strictEqual(retained, component.operation());
    advances++; return {$tag: 1, _0: {}};
  };
  f.moon.clientProgramInferExecutionPollKind = () => 'complete';
  const output = {};
  f.moon.clientProgramInferExecutionOutput = () => output;
  const preparation = {restoreRead(actual) {assert.strictEqual(actual, restoredInput); claims++; return f.originalPreparation;}};
  const selected = {occurrence: f.occurrence, graph: f.graph, provider: f.provider, computePrefix: f.prefix};
  const component = openNodeComposedInferProvider({moon: f.moon, selected, deferred: true});
  component.bindOriginal({selected, restoredInput, originalPreparation: preparation,
    control: {bindCheckedClientInferRun() {}}, plan: {compiled: f.originalPreparation.compiled,
      runDefinition: f.originalPreparation.runDefinition}, durableCalls: true,
    retainOperation(value) {retained = value;}});
  const operation = component.startRestored(); assert.strictEqual(operation, retained);
  assert.strictEqual(await operation.run(), output); assert.equal(advances, 1); assert.equal(claims, 1);
  assert.equal(localOpen([]), undefined); assert.equal(claims, 1);
  assert.throws(() => component.startRestored(), {message: 'ComposedInferAlreadyOpened'});
  await operation.close();
});

test('restored Host facade unwraps only its original compiled and definition and preserves refused results', () => {
  const f = fixture(), managed = {}, bound = {}, sources = [{}], pin = {};
  let calls = 0;
  f.moon.clientProgramInstalledEffectManagedRestoredModelHostOpen = (...args) => {
    calls++; assert.deepEqual(args, [managed, bound, sources, pin, f.rawCompiled, f.rawDefinition, f.graph]);
    return {$tag: 0, _0: 'OriginalHostRefused'};
  };
  const c = f.originalPreparation.control, compiled = f.originalPreparation.compiled, definition = f.originalPreparation.runDefinition;
  assert.throws(() => c.openCheckedClientInstalledRestoredModelEffectHost(
    compiled, definition, managed, bound, sources, pin, f.graph),
    error => error.cause === 'OriginalHostRefused');
  assert.equal(calls, 1);
  for (const pair of [[{...compiled}, definition], [compiled, {...definition}]]) {
    assert.throws(() => c.openCheckedClientInstalledRestoredModelEffectHost(...pair, managed, bound, sources, pin, f.graph), /Foreign/u);
  }
  assert.equal(calls, 1);
});

test('restored Source projection preserves actual evidence originals in the private control namespace', () => {
  const f = fixture(), scope = {}, original = {identity: 'original-source', wire: 'original-source-wire'},
    logical = {identity: 'original-logical'};
  let calls = 0;
  f.moon.clientProgramRestoredInferSourceOriginals = (...args) => {
    calls++; assert.deepEqual(args, [scope, f.rawCompiled, f.rawDefinition, f.occurrence, f.graph]);
    return {$tag: 1, _0: [{_0: original, _1: logical}]};
  };
  f.moon.strategyRunEvidenceIdentity = value => value.identity;
  f.moon.strategyRunEvidenceJson = value => value.wire;
  const p = f.originalPreparation, values = p.control.restoredInferSourceOriginals(
    p.compiled, p.runDefinition, scope, f.occurrence, f.graph);
  assert.equal(values[0].logicalRelationCid, logical.identity);
  assert.equal(values[0].source.identity, original.identity);
  assert.equal(values[0].source.wire, original.wire);
  assert(Object.isFrozen(values) && Object.isFrozen(values[0]));
  f.moon.clientProgramAdmitComposedInferSources = (...args) => {
    assert.strictEqual(args[5][0], original); return {$tag: 1, _0: {}};
  };
  p.control.admitComposedInferSources(f.occurrence, [{capture: {source: () => ({})}}],
    [values[0].source], 'scope', 'start', 'end');
  assert.throws(() => p.control.restoredInferSourceOriginals({...p.compiled},
    p.runDefinition, scope, f.occurrence, f.graph), /Foreign/u);
  assert.equal(calls, 1);
});


test('Whole composed Source admission forwards original capacities and evidence without Query conversion', () => {
  const f = fixture(), scope = {}, pin = {};
  const originals = [{identity: 'source-a', wire: 'source-a-wire'}, {identity: 'source-b', wire: 'source-b-wire'}];
  const logicals = [{}, {}], sources = [{}, {}], identities = [{}, {}], capacities = [{}, {}], keyed = {}, admitted = {};
  f.moon.clientProgramRestoredInferSourceOriginals = () => ({$tag: 1,
    _0: originals.map((source, index) => ({_0: source, _1: logicals[index]}))});
  f.moon.strategyRunEvidenceIdentity = value => value.identity;
  f.moon.strategyRunEvidenceJson = value => value.wire;
  const p = f.originalPreparation;
  const evidence = p.control.restoredInferSourceOriginals(p.compiled, p.runDefinition, scope, f.occurrence, pin)
    .map(value => value.source);
  let calls = 0;
  f.moon.clientProgramAdmitComposedInferSources = () => {assert.fail('Whole input cannot become a Query requirement');};
  f.moon.clientProgramAdmitComposedInferWholeSources = (...args) => {
    calls++;
    assert.deepEqual(args, [f.occurrence, sources, identities, capacities, logicals, originals, 'scope', 'start', 'end', keyed]);
    return {$tag: 1, _0: admitted};
  };
  const captures = sources.map((source, index) => ({inputKind: 'whole-input', identity: identities[index],
    wholeCapacity: capacities[index], logicalInput: logicals[index], capture: {source: () => source}}));
  assert.strictEqual(p.control.admitComposedInferSources(f.occurrence, captures, evidence, 'scope', 'start', 'end', keyed), admitted);
  assert.equal(calls, 1);
  const refusal = {};
  f.moon.clientProgramAdmitComposedInferWholeSources = () => {calls++; return {$tag: 0, _0: refusal};};
  assert.throws(() => p.control.admitComposedInferSources(f.occurrence, captures, evidence, 'scope', 'start', 'end', keyed),
    error => error.code === 'MoonBitHostFailure' && error.cause === refusal);
  assert.equal(calls, 2);
  delete captures[1].inputKind;
  assert.throws(() => p.control.admitComposedInferSources(f.occurrence, captures, evidence, 'scope', 'start', 'end', keyed),
    /Unsupported mixed original Model Source inputs/);
  assert.equal(calls, 2);
});

test('restored composed async driver keeps the existing original IO notification through stop and cleanup', async () => {
  const f = originalRestoredFixture(), poll = {}, output = {};
  let retained, advances = 0;
  f.moon.clientProgramComposedInferLocalProvider = () => ({});
  f.moon.clientProgramRequireInferCallEntry = () => ({$tag: 1, _0: undefined});
  f.moon.clientProgramAdvanceInferExecution = active => {
    assert.strictEqual(active, f.active);
    if (advances++ === 0) {
      assert(retained.ioNotification); retained.ioNotification.notify();
      return {$tag: 1, _0: poll};
    }
    return {$tag: 1, _0: output};
  };
  f.moon.clientProgramInferExecutionPollKind = value => value === poll ? 'await_io' : 'complete';
  f.moon.clientProgramInferExecutionOutput = value => value;
  const selected = {occurrence: f.occurrence, graph: f.graph, provider: f.provider,
    computePrefix: f.prefix, entryPersistence: 'async'};
  const component = openNodeComposedInferProvider({moon: f.moon, selected, deferred: true});
  component.bindOriginal({selected, restoredInput: f.restoredInput,
    originalPreparation: {restoreRead: () => f.originalPreparation},
    control: {bindCheckedClientInferRun() {}}, durableCalls: true,
    plan: {compiled: f.originalPreparation.compiled, runDefinition: f.originalPreparation.runDefinition},
    retainOperation(value) {retained = value;}});
  const operation = component.startRestored();
  assert.strictEqual(await operation.run(), output); assert.equal(advances, 2);
  const notification = operation.ioNotification;
  await operation.close(); assert.equal(notification.notify(), false);
});

for (const refusal of [undefined, 'lowering']) {
  test(`cold composed input lowers its original segments after retained Read (refusal=${refusal ?? 'none'})`, async () => {
    const f = originalRestoredFixture(), suffix = {}, events = [];
    const failure = new Error('OriginalSegmentPreparationRefused');
    let open, reads = 0, lowered = 0, retained;
    f.moon.clientProgramComposedInferLocalProvider = (_occurrence, callback, _issue, _retain, _cleanup, prefix) => {
      assert.equal(prefix, undefined); open = callback; return {};
    };
    f.moon.clientProgramBindInferComputeSuffix = (active, actual) => {
      assert.strictEqual(active, f.active); assert.strictEqual(actual, suffix);
      events.push('bind-suffix'); return {$tag: 1, _0: undefined};
    };
    f.moon.clientProgramRequireInferCallEntry = () => ({$tag: 1, _0: undefined});
    const selected = {occurrence: f.occurrence, graph: f.graph, provider: f.provider};
    const original = {restoreRead(input) {
      assert.strictEqual(input, f.restoredInput); reads++; events.push('retain-read');
      return f.originalPreparation;
    }};
    const component = openNodeComposedInferProvider({moon: f.moon, selected,
      restoredInput: f.restoredInput, originalPreparation: original,
      prepareInputSegments() {
        assert.equal(reads, 1); assert.equal(f.calls.length, 0, 'lowering precedes the original consumer claim');
        lowered++; events.push('lower-segments');
        if (refusal !== undefined) throw failure;
        return {_0: f.prefix, _1: suffix};
      }, control: {bindCheckedClientInferRun() {events.push('bind-run');}},
      plan: {compiled: f.originalPreparation.compiled, runDefinition: f.originalPreparation.runDefinition},
      durableCalls: true, retainOperation(value) {retained = value; events.push('retain-operation');}});
    assert.equal(reads, 0); assert.equal(lowered, 0);
    if (refusal === undefined) {
      const opened = open([]); assert.ifError(component.failure());
      assert.strictEqual(opened, f.active); assert.strictEqual(retained, component.operation());
      const restored = f.calls.find(call => call[0] === 'restore');
      assert.strictEqual(restored[3], f.prefix);
      assert.deepEqual(events, ['retain-read', 'lower-segments', 'retain-operation', 'bind-suffix', 'bind-run']);
      assert.equal(open([]), undefined); assert.equal(reads, 1); assert.equal(lowered, 1);
      await retained.close(); assert.equal(originalReadCleaned(f.originalPreparation.read), true);
    } else {
      assert.equal(open([]), undefined); assert.strictEqual(component.failure(), failure);
      assert.equal(open([]), undefined); assert.strictEqual(component.failure(), failure);
      assert.equal(reads, 1); assert.equal(lowered, 1); assert.equal(f.calls.length, 0);
      assert.equal(component.operation(), undefined);
      assert.equal(originalReadCleaned(f.originalPreparation.read), false,
        'failed lowering keeps the actual retained Read with its existing parent cleanup');
    }
  });
}
