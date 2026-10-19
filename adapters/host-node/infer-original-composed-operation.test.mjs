// Adapter delegation with explicit ports, not a nominal resource issuer or
// an actual Model/Host qualification. The same Common Owner performs admission.
import assert from 'node:assert/strict';
import test from 'node:test';
import {openNodeComposedInferProvider, openNodeInferOperation} from './infer-operation.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

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
