import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {checked} from '../host-common/runtime-result.mjs';
import {configureInferEvidence} from './infer-evaluation-evidence.mjs';

// Original Host expressions with explicit execution/observation ports. This
// supplies no Account grant, Run claim, Store receipt or physical capacity.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const named = [], resultCaptures = [];
function collect(node) {
  if (node === null || typeof node !== 'object') return;
  if (node.type === 'VariableDeclarator' && node.id.name === 'submitEffect') named.push(node.init);
  if (node.type === 'Property' && node.key.name === 'captureResultOperation') resultCaptures.push(node.value);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(collect);
    else if (value !== null && typeof value === 'object') collect(value);
  }
}
collect(ast);
assert.equal(named.length, 1);
const install = compileFunction(`return ${source.slice(named[0].start, named[0].end)};`,
  ['effectRun', 'checkpoints', 'runAcceptance', 'admitEffectDefinition', 'diagnostic',
    'settleHeldRun', 'runIdOf', 'observation']);
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => {resolve = yes; reject = no;});
  return {promise, resolve, reject};
};

for (const failed of [false, true]) {
  test(`initial Effect observation retains settlement after early acceptance (${failed ? 'failure' : 'success'})`, async () => {
    const work = deferred(), holding = deferred(), entered = deferred(), retained = [], diagnostics = [];
    const accepted = {ref: {runDefinitionCid: 'explicit-original'}, durability: 'explicit', revision: 1};
    const primary = new Error('OriginalEffectFailure');
    let starts = 0, settlements = 0;
    const submit = install({checkSupported() {}, start(original) {
      starts++; assert.equal(original, accepted); return work.promise;
    }}, undefined, undefined, async () => accepted,
    (...args) => diagnostics.push(args), async original => {
      assert.equal(original, accepted); settlements++; entered.resolve(); await holding.promise;
    }, () => 'explicit-run', {retainOperation(promise) {retained.push(promise);}});
    try {
      assert.deepEqual(await submit({preparedProgram: {}, requestId: 'explicit-request'}, {}, []), accepted);
      assert.equal(starts, 1);
      assert.equal(retained.length, 1);
      assert.notEqual(retained[0], work.promise);
      let settled = false;
      retained[0].then(() => {settled = true;});
      if (failed) work.reject(primary); else work.resolve({kind: 'started'});
      await entered.promise;
      assert.equal(settled, false);
      holding.resolve(); await retained[0];
      assert.equal(settled, true);
      assert.equal(settlements, 1);
      assert.equal(diagnostics.length, failed ? 1 : 0);
      if (failed) assert.equal(diagnostics[0][0], 'effect_start_failed');
    } finally {
      work.resolve({kind: 'started'}); holding.resolve();
      await work.promise.catch(() => {});
      if (retained.length) await retained[0];
    }
  });
}

test('Result operation capture forwards the same installed optional holder on demand', () => {
  assert.equal(resultCaptures.length, 1);
  const capture = compileFunction(`return ${source.slice(resultCaptures[0].start,
    resultCaptures[0].end)};`, ['observation']);
  assert.equal(capture(undefined), undefined);
  let calls = 0;
  const holder = Object.freeze({run(work) {return work();}, release() {}});
  const original = {captureCurrentOperation() {assert.equal(this, original); calls++; return holder;}};
  const read = capture(original);
  assert.equal(calls, 0);
  assert.equal(read(), holder);
  assert.equal(calls, 1);
});

// Execute the original Effect caller and target-read closure with explicit
// Journal/current/child ports. Actual SQLite row admission is tested by the
// Journal owner; this fixture grants no permission or physical acknowledgement.
const effectFunctions = new Map();
function collectEffectFunctions(node) {
  if (node === null || typeof node !== 'object') return;
  if (node.type === 'VariableDeclarator' &&
      ['executeEffectComputation', 'openEffectTargetReads', 'prepareMockModelInputs'].includes(node.id.name)) {
    assert.equal(effectFunctions.has(node.id.name), false);
    effectFunctions.set(node.id.name, source.slice(node.init.start, node.init.end));
  }
  for (const child of Object.values(node)) {
    if (Array.isArray(child)) child.forEach(collectEffectFunctions);
    else if (child && typeof child === 'object') collectEffectFunctions(child);
  }
}
collectEffectFunctions(ast);
assert.equal(effectFunctions.size, 3);

function effectCancellationFixture({inferEvidence} = {}) {
  const evidenceConfiguration = configureInferEvidence(inferEvidence);
  const ref = Object.freeze({namespaceId: 'namespace', authorityScopeCid: 'scope', runDefinitionCid: 'run'});
  const prepared = {}, identity = {}, managedRun = {}, operationPlan = {};
  const managedEffect = Object.freeze({value: managedRun});
  const work = deferred(), entered = deferred();
  const counts = {legacyLookups: 0, observers: 0, probes: 0, target: 0, resume: 0, mockPreparations: 0};
  let row = Object.freeze({revision: 1, cancellationRequested: false});
  let targetCurrent, sourceCurrent, originalCurrent;
  const read = () => {counts.probes++; if (row instanceof Error) throw row; return row;};
  const moon = {
    clientProgramEffectSerializationOccurrences: () => [{}],
    clientProgramEffectAcquisitionCount: () => 0,
    clientProgramEffectCompilationUnitId: () => 'unit',
    clientProgramEffectCompilationResultNames: () => ['updates'],
    clientProgramInstalledEffectManagedOperationPlan(owner, actualPrepared, actualIdentity) {
      assert.strictEqual(owner, managedRun); assert.strictEqual(actualPrepared, prepared);
      assert.strictEqual(actualIdentity, identity); return {$tag: 1, _0: operationPlan};
    },
  };
  const control = {runDefinitionRunId: () => 'original-run'};
  const journal = {
    lookupRunDefinition(actual, requestControl, publicationControl) {
      assert.strictEqual(actual, ref); assert.strictEqual(requestControl, moon);
      assert.strictEqual(publicationControl, control); counts.legacyLookups++; return read();
    },
    observeRunCancellation(actual, requestControl, publicationControl) {
      assert.strictEqual(actual, ref); assert.strictEqual(requestControl, moon);
      assert.strictEqual(publicationControl, control); counts.observers++; return read;
    },
  };
  const selection = Object.freeze({targetReadInventory: () => []});
  const ports = {moon, control, journal, checked, installedEffect: undefined,
    preparation: {effectManagedPlanRun(actualMoon, actualPrepared, actualIdentity) {
      assert.strictEqual(actualMoon, moon); assert.strictEqual(actualPrepared, prepared);
      assert.strictEqual(actualIdentity, identity); return managedEffect;
    }},
    selectedInstalledEffect: () => selection, principalId: 'actor',
    checkpoints: {}, effectSubmissions: new WeakMap(), inferSelections: new WeakMap(),
    effectTargetReadContinuation(options) {targetCurrent = options.assertCurrent; return {assertCurrent: targetCurrent};},
    effectInstallation: {targetReadInventory: selection.targetReadInventory, async execute(facts) {
      facts.assertUpdateSelectionCurrent();
      targetCurrent();
      await Promise.resolve();
      facts.assertUpdateSelectionCurrent();
      return facts.openComputation({retainComputationOwner() {}});
    }},
    dispatchOwner: {track(actual, options) {
      assert.strictEqual(actual, ref);
      return Promise.resolve().then(() => options.run({signal: new AbortController().signal,
        retainExecution() {}, beginPhysicalWork() {}, observePreEffectFailure() {}}));
    }},
    selectAcquiredEffectSources(options) {
      assert.strictEqual(options.preparedEffect, prepared);
      assert.strictEqual(options.requestIdentity, identity);
      assert.strictEqual(options.managedPlan, operationPlan); return [];
    }, sourceProfile: {}, registry: {}, values: {}, fragment: {}, ordered: {},
    acquiredEffectContinuation(options) {sourceCurrent = options.currentRun; return {};},
    async openAcquiredEffectComputation(options) {
      assert.strictEqual(options.managedRun, managedRun);
      assert.ok(Object.hasOwn(options, 'inferEvidence'));
      assert.strictEqual(options.inferEvidence, evidenceConfiguration);
      originalCurrent = options.assertUpdateSelectionCurrent;
      originalCurrent(); options.assertContinuationCurrent();
      entered.resolve(); return work.promise;
    },
    earlyMockEffectPlans: new WeakMap(), localSnapshotConfiguration: {},
    withLocalExecutionPauseHandler() {}, store: {}, storeAuthorityCid: 'store',
    authorityScopeCid: 'scope', now: () => 'original-time', runContent() {}, authorization: undefined,
    observation: undefined, modelController: undefined, evidenceConfiguration, diagnostic() {},
    clientOperationError: code => Object.assign(new Error(code), {code}),
  };
  const install = name => compileFunction(`return ${effectFunctions.get(name)};`, Object.keys(ports))(...Object.values(ports));
  // The actual caller now also crosses its original LIVE Mock preparation
  // helper. These cancellation fixtures have NO selected Model, so execute
  // that same helper and refuse any unexpected physical answer intake.
  ports.mockModels = {prepareAnswersForRuntime() {assert.fail('No Model answer input is selected by this fixture');}};
  const prepareMockModelInputs = install('prepareMockModelInputs');
  ports.prepareMockModelInputs = selected => {
    assert.strictEqual(selected, managedEffect.modelSelection); counts.mockPreparations++;
    return prepareMockModelInputs(selected);
  };
  ports.openEffectTargetReads = install('openEffectTargetReads');
  const execute = install('executeEffectComputation');
  const facts = Object.freeze({ref, prepared, identity, runDefinition: {}, compilation: {}, preparedExecution: {},
    updateTargetSelections: {}, assertUpdateSelectionCurrent() {counts.target++;}});
  const resume = Object.freeze({active: false, assertCurrent() {counts.resume++;}});
  return {counts, facts, evidenceConfiguration, entered: entered.promise, execute: () => execute(facts, resume),
    setRow: value => {row = value;}, target: () => targetCurrent(),
    source: () => sourceCurrent(), original: () => originalCurrent(),
    independentTarget: () => ports.openEffectTargetReads(facts, {activeResume: resume}),
    finish: () => work.resolve({status: 'waiting_checkpoint'})};
}

test('Effect cancellation probes share one original observer through target and Source work', async () => {
  const f = effectCancellationFixture(), execution = f.execute();
  try {
    await f.entered;
    assert.equal(f.evidenceConfiguration, undefined);
    assert.equal(f.counts.mockPreparations, 1, 'The actual no-Model preparation helper ran once');
    assert.equal(f.source(), true); f.target(); f.original();
    assert.equal(f.counts.legacyLookups, 0, 'Cancellation does not readmit the full Run at each internal check');
    assert.equal(f.counts.observers, 1, 'The same continuation owns one Journal observer');
    assert(f.counts.probes > 5, 'Actual cancellation probes still occur at current boundaries');
    assert(f.counts.target > 5); assert(f.counts.resume > 2);
  } finally {f.finish(); await execution;}
});

test('Effect cancellation forwards the actual configured Evidence token without opening Model work', async () => {
  const inferEvidence = {target: 'named', destination: 'local:evaluator', maxBytes: 4096,
    authorize() {assert.fail('No Model evidence authorization is selected by this fixture');},
    sink: {capture() {assert.fail('No Model evidence copy is selected by this fixture');},
      record() {assert.fail('No Model evidence record is selected by this fixture');}}};
  const f = effectCancellationFixture({inferEvidence}), execution = f.execute();
  try {
    await f.entered;
    assert.notStrictEqual(f.evidenceConfiguration, inferEvidence);
    assert.equal(Object.isFrozen(f.evidenceConfiguration), true);
    assert.deepEqual(f.evidenceConfiguration.target, ['named']);
    assert.equal(f.source(), true); f.target(); f.original();
    assert.equal(f.counts.mockPreparations, 1);
    assert.equal(f.counts.observers, 1);
  } finally {f.finish(); await execution;}
});

test('Effect cancellation probes retain changed missing and failed current observations', async () => {
  const f = effectCancellationFixture(), execution = f.execute();
  try {
    await f.entered;
    assert.equal(f.counts.mockPreparations, 1, 'The actual no-Model preparation helper ran once');
    for (const row of [Object.freeze({revision: 1, cancellationRequested: true}), undefined]) {
      f.setRow(row); assert.equal(f.source(), false);
      assert.throws(f.target, {code: 'ClientRunCancellationRequested'});
      assert.throws(f.original, {code: 'ClientRunCancellationRequested'});
    }
    const original = Object.assign(new Error('OriginalJournalReadFailed'), {code: 'OriginalJournalReadFailed'});
    f.setRow(original); assert.throws(f.source, error => error === original);
    assert.throws(f.target, error => error === original);
    f.setRow(Object.freeze({revision: 2, cancellationRequested: false}));
    assert.equal(f.source(), true); f.target();
    assert.equal(f.counts.observers, 1);
  } finally {f.finish(); await execution;}
});

test('Effect cancellation probes retain pending child lifetime and independent target observers', async () => {
  const f = effectCancellationFixture(), execution = f.execute();
  try {
    await f.entered;
    assert.equal(f.counts.mockPreparations, 1, 'The actual no-Model preparation helper ran once');
    f.original(); assert.equal(f.source(), true);
    await f.independentTarget();
    assert.equal(f.counts.observers, 2, 'An independent target continuation has its own Journal lifetime');
    f.setRow(Object.freeze({revision: 2, cancellationRequested: true}));
    assert.equal(f.source(), false);
    assert.throws(f.target, {code: 'ClientRunCancellationRequested'});
    assert.throws(f.original, {code: 'ClientRunCancellationRequested'});
  } finally {f.finish(); await execution;}
});
