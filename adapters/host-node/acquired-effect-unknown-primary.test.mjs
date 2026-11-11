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
    CapturedRunPublicationError: class ExplicitPublicationError extends Error {},
    diagnostic: (name, facts) => diagnostics.push({name, facts}), runtimeTag: () => undefined,
    runtimeOptionalField: () => undefined, barrierFailureOutcome: null});
  await assert.rejects(failed(cleanup), error => error === cleanup);
  assert.strictEqual(entry.primaryFailure, primary);assert.strictEqual(entry.cleanupFailure, cleanup);
  assert.strictEqual(entry.cleanupOwner, custody);assert.equal(entry.terminalOutcome, undefined);
  assert.equal(diagnostics.length, 1);assert.equal(diagnostics[0].name, 'dispatch_failed');
  assert.equal(diagnostics[0].facts.code, cleanup.code);
  assert.equal(diagnostics[0].facts.primaryCode, primary.code);
});
