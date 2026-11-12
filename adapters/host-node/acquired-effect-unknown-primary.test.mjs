import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';

// Execute the original coordination branches with explicit ports. No physical
// Model, Journal, Source or cleanup acknowledgement is supplied by this test.
const acquired = readFileSync(new URL('./acquired-effect-computation.mjs', import.meta.url), 'utf8');
const dispatch = readFileSync(new URL('./client-dispatch-owner.mjs', import.meta.url), 'utf8');
const site = readFileSync(new URL('./installed-effect-site.mjs', import.meta.url), 'utf8');
const dispatchTree = parse(dispatch, {ecmaVersion: 'latest', sourceType: 'module'});
const retainDeclaration = dispatchTree.body.find(node => node.type === 'FunctionDeclaration' &&
  node.id.name === 'retainDispatchPrimaryFailure');
assert(retainDeclaration);
const diagnosticDeclaration = dispatchTree.body.find(node => node.type === 'FunctionDeclaration' &&
  node.id.name === 'dispatchFailureSnapshot');
assert(diagnosticDeclaration);
const dispatchFailureSnapshot = new Function(
  `${dispatch.slice(diagnosticDeclaration.start, diagnosticDeclaration.end)};return dispatchFailureSnapshot;`)();
const retainDispatchPrimaryFailure = new Function(
  `${dispatch.slice(retainDeclaration.start, retainDeclaration.end)};return retainDispatchPrimaryFailure;`)();
function selectedBranch(text, marker, bodyMarker = '') {
  const found = [];
  function visit(node) {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'IfStatement' && text.slice(node.test.start, node.test.end).includes(marker) &&
        text.slice(node.consequent.start, node.consequent.end).includes(bodyMarker)) found.push(node);
    for (const value of Object.values(node)) {
      for (const child of Array.isArray(value) ? value : [value]) visit(child);
    }
  }
  visit(parse(text, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(found.length, 1);
  return text.slice(found[0].start, found[0].end);
}
const unknown = selectedBranch(acquired, 'modelController.unresolved(');
const reconciliation = selectedBranch(dispatch, "result?.status === 'needs_reconciliation'", 'InstalledInferUnknownNotRecorded');
const siteUnknown = selectedBranch(site, "opened?.status === 'needs_reconciliation'");

function modelUnknown({component, modelGroup, failure}) {
  const execution = {status: 'host-tasks-failed', failure}, checkedHost = {}, custody = {};
  const ports = {component, modelGroup, execution, checkedHost, custody,
    acquired: {runDefinition: {}, control: {runDefinitionRunId: () => 'same-run'}},
    modelController: {unresolved(run) {assert.equal(run, 'same-run');return true;}}};
  const result = new Function(...Object.keys(ports), unknown)(...Object.values(ports));
  assert.equal(result.status, 'needs_reconciliation');assert.equal(result.modelUnknown, true);
  assert.strictEqual(result.execution, execution);assert.strictEqual(result.checkedHost, checkedHost);
  assert.strictEqual(result.cleanupOwner, custody);assert(Object.isFrozen(result));
  return result;
}

test('Model Unknown retains the same original single or plural failure without replacing its outcome', () => {
  for (const original of [new Error('OriginalModelFailure'), null, undefined]) {
    const fallback = new Error('LaterComputeFailure');
    assert.strictEqual(modelUnknown({component: {hasFailure: () => true, failure: () => original},
      failure: fallback}).primaryFailure, original);
    assert.strictEqual(modelUnknown({modelGroup: {hasFailure: () => true, failure: () => original},
      failure: fallback}).primaryFailure, original);
  }
  const executionFailure = new Error('OriginalComputeFailure');
  assert.strictEqual(modelUnknown({component: {hasFailure: () => false},
    failure: executionFailure}).primaryFailure, executionFailure);
});

test('diagnostic failure inspection cannot replace a Model Unknown outcome or its original custody', () => {
  const result = modelUnknown({component: {hasFailure: () => true,
    failure() {throw new Error('FailureInspectionRefused');}}});
  assert.equal(result.primaryFailure, undefined);
});

test('dispatch retains that same Unknown primary before its existing cleanup and state observation', async () => {
  const primary = new Error('OriginalModelFailure'), custody = {}, entry = {cleanupOwner: custody};
  const events = [], ref = {}, definition = {}, result = {status: 'needs_reconciliation', primaryFailure: primary};
  const ports = {result, entry, retainDispatchPrimaryFailure,
    accepted: {ref, runDefinition: definition}, journal: {}, moon: {},
    control: {runDefinitionRunId(original) {assert.strictEqual(original, definition);return 'same-run';}},
    checkpoints: {journal: {hasUnresolvedModelCalls(run) {assert.equal(run, 'same-run');return true;}}},
    async step(name) {events.push(name);},
    async settleCleanup(original) {
      assert.strictEqual(original, entry);assert.strictEqual(original.cleanupOwner, custody);
      assert.strictEqual(original.primaryFailure, primary);events.push('cleanup');
    },
    async finishRun(original) {assert.strictEqual(original, entry);events.push('observe');},
    recordNodeRunPhysicalStop() {assert.fail('A diagnostic cannot issue a physical-stop receipt');},
  };
  await new Function(...Object.keys(ports), `return (async()=>{${reconciliation}})();`)(...Object.values(ports));
  assert.deepEqual(events, ['infer_needs_reconciliation', 'cleanup', 'observe']);
  assert.strictEqual(entry.primaryFailure, primary);assert.strictEqual(entry.cleanupOwner, custody);
});

test('the real Effect Site forwards only original own failure DATA while remaining Unknown', () => {
  const primary = new Error('OriginalModelFailure');
  const run = new Function('opened', siteUnknown);
  const result = run(Object.freeze({status: 'needs_reconciliation', modelUnknown: true, primaryFailure: primary}));
  assert(Object.isFrozen(result));assert.equal(result.status, 'needs_reconciliation');
  assert.equal(result.modelUnknown, true);assert.strictEqual(result.primaryFailure, primary);
  const unobserved = run({status: 'needs_reconciliation', modelUnknown: true,
    get primaryFailure() {assert.fail('failure accessors are not diagnostic DATA');}});
  assert.equal(Object.hasOwn(unobserved, 'primaryFailure'), false);
});

test('diagnostic handoff preserves a recorded null or undefined and never consumes an accessor', () => {
  for (const primary of [null, undefined]) {
    const entry = {};
    retainDispatchPrimaryFailure(entry, {primaryFailure: primary});
    retainDispatchPrimaryFailure(entry, {primaryFailure: new Error('LaterCleanupFailure')});
    assert(Object.hasOwn(entry, 'primaryFailure'));assert.strictEqual(entry.primaryFailure, primary);
  }
  const entry = {};
  retainDispatchPrimaryFailure(entry, {get primaryFailure() {assert.fail('no getter');}});
  assert.equal(Object.hasOwn(entry, 'primaryFailure'), false);
});

function trackCallback(method, marker) {
  const found = [];
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression' &&
        node.callee.property.name === method && node.arguments[0]?.type === 'ArrowFunctionExpression' &&
        dispatch.slice(node.arguments[0].start, node.arguments[0].end).includes(marker)) {
      found.push(node.arguments[0]);
    }
    for (const value of Object.values(node)) for (const child of Array.isArray(value) ? value : [value]) visit(child);
  }
  visit(dispatchTree);assert.equal(found.length, 1);
  return dispatch.slice(found[0].start, found[0].end);
}
const trackedResult = trackCallback('then', "result?.status === 'failed_without_effect_dispatch'");
const trackedFailure = trackCallback('catch', 'if (!entry.runInvoked)');

test('the actual tracked Effect caller keeps the Model primary across a later cleanup refusal', async () => {
  const primary = Object.assign(new Error('OriginalModelFailure'), {code: 'OriginalModelFailure'});
  const cleanup = Object.assign(new Error('OriginalCleanupPending'), {code: 'ClientDispatchCleanupPending'});
  const custody = {}, entry = {runInvoked: true, cleanupOwner: custody};
  const make = (source, ports) => new Function(...Object.keys(ports), `return (${source});`)(...Object.values(ports));
  const next = make(trackedResult, {entry, retainDispatchPrimaryFailure,
    settleCleanup: async actual => {
      assert.strictEqual(actual.primaryFailure, primary);assert.strictEqual(actual.cleanupOwner, custody);throw cleanup;
    }});
  await assert.rejects(next({status: 'needs_reconciliation', primaryFailure: primary}), error => error === cleanup);
  const diagnostics = [];
  const failed = make(trackedFailure, {entry, settleCleanup: async () => {throw cleanup;},
    CapturedRunPublicationError: class ExplicitPublicationError extends Error {}, dispatchFailureSnapshot,
    diagnostic: (name, facts) => diagnostics.push({name, facts}), runtimeTag: () => undefined,
    runtimeOptionalField: () => undefined, barrierFailureOutcome: null});
  await assert.rejects(failed(cleanup), error => error === cleanup);
  assert.strictEqual(entry.primaryFailure, primary);assert.strictEqual(entry.cleanupFailure, cleanup);
  assert.strictEqual(entry.cleanupOwner, custody);assert.equal(entry.terminalOutcome, undefined);
  assert.equal(diagnostics.length, 1);assert.equal(diagnostics[0].name, 'dispatch_failed');
  assert.equal(diagnostics[0].facts.code, cleanup.code);
  assert.equal(diagnostics[0].facts.primaryCode, primary.code);
});

test('dispatch copies only inert typed primary diagnostic DATA without invoking failure getters',()=>{
  const data=Object.freeze({code:'MoonBitHostFailure',phase:'original_model_acquired_effect_evidence',
    kind:'invocation.foreign_captured_input',task:4,unit:2,step:5});
  const primary=Object.assign(new Error('private original'),{code:'MoonBitHostFailure',primaryDiagnostic:data});
  assert.deepEqual(dispatchFailureSnapshot(primary).primaryDiagnostic,data);
  const accessor=Object.defineProperty(new Error('original'),'primaryDiagnostic',{
    get(){assert.fail('Optional DATA must not invoke an accessor');}});
  assert.equal(dispatchFailureSnapshot(accessor).primaryDiagnostic,undefined);
  const invalid=Object.assign(new Error('original'),{primaryDiagnostic:{...data,kind:'private payload value'}});
  assert.equal(dispatchFailureSnapshot(invalid).primaryDiagnostic,undefined);
  const missing=Object.assign(new Error('original'),{primaryDiagnostic:{...data,task:undefined}});
  assert.equal(dispatchFailureSnapshot(missing).primaryDiagnostic,undefined);
  assert.equal(primary.code,'MoonBitHostFailure');assert.strictEqual(primary.primaryDiagnostic,data);
});


test('dispatch admits only explicit Source Unit export phase with inert real occurrence DATA', () => {
  const data = {code: 'MoonBitHostFailure', phase: 'original_effect_source_unit_result_export',
    kind: 'export.completed.unavailable', task: 4, unit: 2, step: 5};
  const primary = Object.assign(new Error('private'), {primaryDiagnostic: data});
  assert.deepEqual(dispatchFailureSnapshot(primary).primaryDiagnostic, data);
  for (const invalid of [{...data, phase: 'arbitrary_new_phase'}, {...data, task: -1},
    {...data, unit: 2147483648}, {...data, step: undefined}, {...data, kind: 'private payload'}]) {
    assert.equal(dispatchFailureSnapshot({primaryDiagnostic: invalid}).primaryDiagnostic, undefined);
  }
  const accessor = Object.defineProperty({...data}, 'unit', {get() {assert.fail('No getter invocation');}});
  assert.equal(dispatchFailureSnapshot({primaryDiagnostic: accessor}).primaryDiagnostic, undefined);
  const cleanup = Object.assign(new Error('cleanup'), {primaryFailure: primary});
  assert.deepEqual(dispatchFailureSnapshot(cleanup).primaryDiagnostic, data);
  assert.strictEqual(cleanup.primaryFailure, primary);
});


test('dispatch admits only explicit Source Unit artifact phase with inert real occurrence DATA', () => {
  const data = {code: 'MoonBitHostFailure', phase: 'original_effect_source_unit_artifact',
    kind: 'run.foreign_original', task: 4, unit: 2, step: 5};
  const primary = Object.assign(new Error('private'), {primaryDiagnostic: data});
  assert.deepEqual(dispatchFailureSnapshot(primary).primaryDiagnostic, data);
  for (const invalid of [{...data, phase: 'arbitrary_new_phase'}, {...data, task: -1},
    {...data, unit: 2147483648}, {...data, step: undefined}, {...data, kind: 'private payload'}]) {
    assert.equal(dispatchFailureSnapshot({primaryDiagnostic: invalid}).primaryDiagnostic, undefined);
  }
  const accessor = Object.defineProperty({...data}, 'unit', {get() {assert.fail('No getter invocation');}});
  assert.equal(dispatchFailureSnapshot({primaryDiagnostic: accessor}).primaryDiagnostic, undefined);
  const cleanup = Object.assign(new Error('cleanup'), {primaryFailure: primary});
  assert.deepEqual(dispatchFailureSnapshot(cleanup).primaryDiagnostic, data);
  assert.strictEqual(cleanup.primaryFailure, primary);
});
