import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {checked} from '../host-common/runtime-result.mjs';
import {prepareInstalledEffectOwnedRequestChild, prepareInstalledEffectRequestChild,
  prepareInstalledPhysicalWritePlanRecipe, captureInstalledEffectPlanRecipe}
  from './installed-effect-plan.mjs';

function ownedFixture() {
  const token = {}, prepared = {}, request = {}, parent = {}, plan = {};
  let entered = 0, completed = 0, retired = 0, aliases = false, refined = 0;
  const runtime = {
    clientProgramInstalledEffectManagedOperationPlan: () => ({$tag: 1, _0: plan}),
    clientProgramInstalledEffectOperationConstructionRetain: () => ({$tag: 1, _0: token}),
    clientProgramInstalledEffectOperationConstructionBegin(actual) {
      assert.strictEqual(actual, token); entered++; return {$tag: 1};
    },
    clientProgramInstalledEffectOperationConstructionComplete(actual) {
      assert.strictEqual(actual, token); completed++; return {$tag: 1};
    },
    clientProgramInstalledEffectOperationConstructionCompleteOutput(actual, wire) {
      assert.strictEqual(actual, token); assert.equal(typeof wire, 'string');
      refined++; completed++; return {$tag: 1};
    },
    clientProgramInstalledEffectOperationRetire(actual) {
      assert.strictEqual(actual, token); retired++; return {$tag: 1, _0: true};
    },
  };
  const run = {runtime, prepared, request, value: parent, operationPlan: plan,
    readPlan: runtime.clientProgramInstalledEffectManagedOperationPlan};
  return {options: {run, memberIndex: 0, rowIndex: 0, operationIndex: 0, operation: 'file.request',
    requestsRetired: () => aliases}, aliases() {aliases = true;},
    counts: () => ({entered, completed, retired}), refined: () => refined};
}

test('owned async file request retains its same child before preparation and joins before completion', async () => {
  const f = ownedFixture(), output = {}; let finish, released = false, factories = 0;
  const task = new Promise(resolve => {finish = resolve;});
  const original = {prepare() {assert.equal(factories, 1); return task;},
    async release() {await task; return released;}, retry: () => released, status: () => ({pending: !released})};
  const child = prepareInstalledEffectOwnedRequestChild({...f.options, constructChild() {factories++; return original;}});
  const pending = child.prepare(); assert.deepEqual(f.counts(), {entered: 1, completed: 0, retired: 0});
  f.aliases(); const closing = child.release();
  assert.equal(f.counts().retired, 0);
  finish(output); assert.strictEqual(await pending, output); assert.equal(await closing, false);
  assert.equal(f.counts().completed, 1); assert.equal(f.counts().retired, 0);
  released = true; assert.equal(await child.retry(), true);
  assert.deepEqual(f.counts(), {entered: 1, completed: 1, retired: 1}); assert.equal(factories, 1);
});

test('owned async file failure preserves undefined and retains cleanup until the same physical retry', async () => {
  const f = ownedFixture(); let reject, closed = false, attempts = 0;
  const task = new Promise((_yes, no) => {reject = no;});
  const original = {prepare() {attempts++; return task;}, release: () => false,
    retry: () => closed, status: () => ({pending: !closed})};
  const child = prepareInstalledEffectOwnedRequestChild({...f.options, constructChild: () => original});
  const pending = child.prepare(); reject(undefined);
  let caught = false; try {await pending;} catch (cause) {caught = true; assert.strictEqual(cause, undefined);}
  assert(caught); f.aliases(); assert.equal(await child.release(), false);
  assert.equal(f.counts().retired, 0); assert.equal(f.counts().completed, 0);
  closed = true; assert.equal(await child.retry(), true); assert.equal(attempts, 1);
  assert.equal(f.counts().retired, 1);
});

test('owned async request rechecks the same original after await and never completes a foreign record', async () => {
  const f = ownedFixture(); let finish, closed = false;
  const task = new Promise(resolve => {finish = resolve;});
  const original = {prepare: () => task, release() {closed = true; return true;},
    retry() {closed = true; return true;}, status: () => ({pending: !closed})};
  const child = prepareInstalledEffectOwnedRequestChild({...f.options, constructChild: () => original});
  const pending = child.prepare(); f.options.run.request = {}; finish({});
  await assert.rejects(pending, {code: 'ForeignInstalledEffectManagedRun'});
  assert.equal(f.counts().completed, 0); f.aliases(); assert.equal(await child.release(), true);
});

test('ordinary constructors still refuse a Promise instead of borrowing the owned-child join', async () => {
  const f = ownedFixture(), child = prepareInstalledEffectRequestChild({...f.options, construct: () => Promise.resolve({})});
  await assert.rejects(child.prepare(), {code: 'InstalledEffectConstructorNotSynchronous'});
  assert.equal(f.counts().completed, 0); f.aliases(); assert.equal(child.release(), true);
});

test('Mock file recipe composes actual file decode into request and physical windows without changing policy', () => {
  const text = readFileSync(new URL('../local-node/installed-mock-row-effect.mjs', import.meta.url), 'utf8');
  const ast = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  const node = ast.body.find(value => value.type === 'FunctionDeclaration' && value.id.name === 'mockFileEffectPlanRecipe');
  assert(node);
  const limits = {maxFileBytes: 1048576, maxNodes: 16384, maxDepth: 32, maxRows: 100,
    maxResponseBytes: 65536};
  const decode = {}, native = [], composed = [], policy = {};
  const moon = {
    clientProgramInstalledSourceConstructionCapacity(...geometry) {const value = {geometry}; native.push(value); return {$tag: 1, _0: value};},
    clientProgramInstalledFileEffectConstructionCapacity(provider, bytes, nodes, depth) {
      assert.deepEqual(provider.geometry, Array(6).fill(0n));
      assert.deepEqual([bytes, nodes, depth], [1048576, 16384, 32]); return {$tag: 1, _0: decode};
    },
    clientProgramComposeInstalledSourceConstructionCapacity(provider, originals) {
      assert.deepEqual(originals, [decode]); const result = {provider, originals}; composed.push(result); return {$tag: 1, _0: result};
    },
  };
  const run = Function('targetLimits', 'checked', 'installedRowEffectConstructionLimits', 'prepareInstalledPhysicalWritePlanRecipe',
    'return ('+text.slice(node.start, node.end)+');')(limits, checked,
    value => {assert.deepEqual(value, {maxRows: 100}); return policy;}, value => value);
  const one = run(moon, {sources: [{physical: [{}]}]}, 'file.update');
  const two = run(moon, {sources: [{physical: [{}]}, {physical: [{}]}]}, 'file.update');
  for (const recipe of [one, two]) {
    assert.strictEqual(recipe.physicalConstruction, decode); assert.strictEqual(recipe.inputLimits, policy);
    assert(composed.includes(recipe.requestConstruction));
    assert.deepEqual(recipe.construction.retained, {nodes: 0n, text: 0n, wire: 0n});
    assert.equal(recipe.construction.workspace.wire, 2n * 1048576n);
    assert.equal(recipe.limits.maxTransferBytes, 2 * 1048576);
  }
  assert(two.construction.workspace.nodes > one.construction.workspace.nodes);
  assert(two.construction.workspace.text > one.construction.workspace.text);
  assert.equal(two.limits.maxRequestBytes, one.limits.maxRequestBytes);
  assert.equal(native.length, 4, 'one zero decoder base and one actual request workspace per recipe');
});

function sendFixture({pending = false} = {}) {
  const text = readFileSync(new URL('../local-node/installed-mock-row-effect.mjs', import.meta.url), 'utf8');
  const ast = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  const driver = ast.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'mockRowEffectDriver');
  const declaration = driver.body.body.flatMap(node => node.declarations ?? []).find(node => node.id.name === 'driver');
  const send = declaration.init.arguments[0].properties.find(node => node.key.name === 'send');
  const retire = driver.body.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'retireChild');
  const events = [], charges = [], request = {}, runOriginal = {}, selected = {}, member = {}, record = {
    target: 'original-target', version: 'original-version', value: {field: 'new'}, before: {field: 'old'}};
  let physical, options, closed = false;
  const child = {async prepare() {
    assert.strictEqual(physical, child, 'same physical child is retained before preparation or file I/O');
    events.push('prepare'); options.authorize();
    assert.deepEqual(options.replace(new Uint8Array(3)), new Uint8Array(5));
  }, async release() {events.push('release'); if (!pending) closed = true; return {pending: !closed};},
  async retry() {events.push('retry'); closed = true; return {pending: false};}, status: () => ({pending: !closed})};
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const ports = {memberCurrent: actual => assert.strictEqual(actual, member),
    description: actual => assert.strictEqual(actual, selected), runCurrent: actual => assert.strictEqual(actual, runOriginal),
    own: actual => {assert.strictEqual(actual, request); return {record, cid: 'original-request'};},
    file: {updateChild(actual) {options = actual; return child;}},
    admit: () => ({selected: {}}), observe: () => ({versionCid: record.version, before: record.before}),
    wire: JSON.stringify, call: () => ({$tag: 1, _0: new Uint8Array(5)}), checked, work: 16777216,
    consume: () => ({useCid: 'original-use'}), current() {}, fail};
  const invoke = Function(...Object.keys(ports), text.slice(retire.start, retire.end)+
    ';return ({'+text.slice(send.start, send.end)+'}).send;')(...Object.values(ports));
  return {run: () => invoke({member, request, current: selected, runOriginal,
    physicalOperation: {retainPhysicalChild(actual) {assert.equal(physical, undefined); physical = actual; events.push('retain');},
      chargeBytes(value) {charges.push(value);}}}), events, charges, child};
}

test('actual Mock send retains its original physical child before preparation and charges file and replacement bytes', async () => {
  const f = sendFixture(); const result = await f.run();
  assert.deepEqual(f.events, ['retain', 'prepare', 'release']); assert.deepEqual(f.charges, [3n, 5n]);
  assert.equal(result.observation.statusCode, 200);
});

test('actual Mock send keeps failed physical release pending and retries that same child', async () => {
  const f = sendFixture({pending: true}); let issue;
  try {await f.run();} catch (cause) {issue = cause;}
  assert.equal(issue?.code, 'MockFileCleanupPending'); assert.equal(issue.cleanupPending, true);
  assert.equal(issue.cleanupHandle.status().pending, true);
  assert.deepEqual(await issue.cleanupHandle.retry(), {pending: false});
  assert.equal(issue.cleanupHandle.status().pending, false);
  assert.deepEqual(f.events, ['retain', 'prepare', 'release', 'retry']);
});

test('non-HTTP target phases have distinct original constructor slots and reject aliasing another role', () => {
  const capacities = Array.from({length: 6}, () => ({}));
  const moon = {
    clientProgramInstalledSourceConstructionCapacity: () => ({$tag: 1, _0: {}}),
    clientProgramInstalledEffectControlWireBound: () => ({$tag: 1, _0: 1024}),
    clientProgramInstalledPhysicalWriteRecipeCapacitiesWithRequest: () => ({$tag: 1, _0: capacities}),
    clientProgramInstalledEffectCaptureRecipeExtentPrepare: () => ({$tag: 1, _0: {}}),
    clientProgramInstalledEffectOperationExtentFromCapacityPrepare: () => ({$tag: 1, _0: {}}),
  };
  const zero = Object.freeze({nodes: 0n, text: 0n, wire: 0n});
  const recipe = prepareInstalledPhysicalWritePlanRecipe({moon, operation: 'file.update', targetReadOperation: 'file.observe',
    construction: Object.freeze({retained: zero, workspace: zero}), requestConstruction: {},
    inputLimits: {body: {maxBytes: 100, maxNodes: 100, maxDepth: 16}, preview: {maxWireBytes: 100, maxNodes: 100, maxDepth: 16}},
    limits: {maxRequestBytes: 100, maxRecoveryBytes: 100, maxResponseBytes: 100, maxOutcomeBytes: 100, maxTransferBytes: 100}});
  assert.deepEqual(recipe.ownedReadOperations, [
    {phase: 'capture-target', operationIndex: 2}, {phase: 'apply-target', operationIndex: 3},
    {phase: 'resume-target', operationIndex: 4}]);
  assert.equal(recipe.requestConstruction.operationIndex, 0); assert.equal(recipe.physicalWrite.operationIndex, 1);
  for (const operations of [[{phase: 'capture-target', operationIndex: 0}],
    [{phase: 'capture-target', operationIndex: 2}, {phase: 'apply-target', operationIndex: 2}],
    [{phase: 'capture-target', operationIndex: 2}, {phase: 'capture-target', operationIndex: 3}]]) {
    assert.throws(() => captureInstalledEffectPlanRecipe({...recipe, ownedReadOperations: operations}, 7),
      {code: 'InvalidInstalledEffectPlanRecipe'});
  }
});

function targetFixture({pending = false, prepareFailure} = {}) {
  const text = readFileSync(new URL('../local-node/installed-mock-row-effect.mjs', import.meta.url), 'utf8');
  const ast = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  const driver = ast.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'mockRowEffectDriver');
  const declaration = driver.body.body.flatMap(node => node.declarations ?? []).find(node => node.id.name === 'driver');
  const method = declaration.init.arguments[0].properties.find(node => node.key.name === 'observeTargets');
  const retire = driver.body.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'retireChild');
  const f = ownedFixture(), member = {}, selected = {}, request = {}, runOriginal = {}, events = [];
  let child, managed, originalChild, closed = false, constructorCalls = 0;
  const ports = {memberCurrent: actual => assert.strictEqual(actual, member),
    description: actual => assert.strictEqual(actual, selected), runCurrent: actual => assert.strictEqual(actual, runOriginal),
    own: actual => {assert.strictEqual(actual, request); return {record: {target: 'same-target'}};},
    consume: () => ({}), admit: () => ({}), observe: () => ({versionCid: 'same-version', before: {id: 'same-target'}, beforeWire: '{"id":"same-target"}'}),
    wire: JSON.stringify,
    fail: code => {throw Object.assign(new Error(code), {code});},
    file: {readChild(options) {
      constructorCalls++; assert.equal(f.counts().entered, 1, 'same constructor is entered before the actual file child');
      child = {async prepare() {
        assert(managed, 'common retains the actual owned read before I/O'); events.push('read');
        await options.authorize(); if (prepareFailure) throw prepareFailure.cause;
        return options.consume(new Uint8Array(3));
      }, release() {if (closed) return {pending: false}; events.push('close'); if (!pending) closed = true; return {pending: !closed};},
      retry() {events.push('retry-close'); closed = true; return {pending: false};}, status: () => ({pending: !closed})};
      return child;
    }}};
  const invoke = Function(...Object.keys(ports), text.slice(retire.start, retire.end)+
    ';return ({'+text.slice(method.start, method.end)+'}).observeTargets;')(...Object.values(ports));
  return {run: () => invoke({member, entries: [{request}], current: selected, runOriginal,
    authorizationForRow: async index => {assert.equal(index, 0); return {};},
    ownedReadChild(constructChild, rowIndex) {
      assert.equal(rowIndex, 0);
      managed = prepareInstalledEffectOwnedRequestChild({...f.options, constructChild() {
        originalChild = constructChild(); return originalChild;
      }});
      return managed.prepare();
    }}), managed: () => managed, original: () => originalChild, f, events, constructors: () => constructorCalls};
}

test('actual target recheck uses the same owned constructor and closes its file before completing workspace', async () => {
  const f = targetFixture();
  assert.deepEqual(await f.run(), [{identity: 'same-target', versionCid: 'same-version', before: {id: 'same-target'}}]);
  assert.deepEqual(f.events, ['read', 'close']); assert.equal(f.f.counts().completed, 1); assert.equal(f.f.refined(), 1);
  assert.equal(f.f.counts().retired, 0); f.f.aliases(); assert.equal(await f.managed().release(), true);
  assert.equal(f.f.counts().retired, 1); assert.equal(f.constructors(), 1);
});

test('actual target recheck keeps failed or pending file cleanup on the same constructor and original retry', async () => {
  for (const config of [{pending: true}, {prepareFailure: {cause: undefined}}]) {
    const f = targetFixture(config); let caught = false, issue;
    try {await f.run();} catch (cause) {caught = true; issue = cause;}
    assert(caught); assert.equal(f.f.counts().completed, 0); assert.equal(f.f.counts().retired, 0);
    f.f.aliases();
    if (config.pending) {
      assert.equal(issue.code, 'MockFileCleanupPending'); assert.equal(await f.managed().release(), false);
      assert.equal(await f.managed().retry(), true);
    } else {assert.strictEqual(issue, undefined); assert.equal(await f.managed().release(), true);}
    assert.equal(f.f.counts().retired, 1); assert.equal(f.constructors(), 1);
  }
});


test('owned output uses its original wire only after actual close and preserves its opaque output', async () => {
  const f = ownedFixture(), output = Object.freeze({}), events = []; let closed = false;
  const original = {async prepare() {events.push('prepare'); return output;},
    async release() {events.push('close'); closed = true; return {pending: false};},
    retry: () => ({pending: !closed}), status: () => ({pending: !closed}),
    retainedOutputWire(actual) {assert.strictEqual(actual, output); assert(closed); events.push('wire'); return '{"id":1}';}};
  const child = prepareInstalledEffectOwnedRequestChild({...f.options, constructChild: () => original});
  assert.strictEqual(await child.prepare(), output);
  assert.deepEqual(events, ['prepare', 'close', 'wire']); assert.equal(f.refined(), 1);
  assert.equal(f.counts().retired, 0); f.aliases(); assert.equal(await child.release(), true);
  assert.equal(f.counts().retired, 1);
});

test('owned output never refines on pending or thrown physical close and keeps the same retry', async () => {
  for (const thrown of [false, true]) {
    const f = ownedFixture(), output = {}; let closed = false, preparations = 0, wires = 0;
    const original = {async prepare() {preparations++; return output;},
      release() {if (thrown) throw undefined; return false;},
      retry() {closed = true; return true;}, status: () => ({pending: !closed}),
      retainedOutputWire() {wires++; return '{}';}};
    const child = prepareInstalledEffectOwnedRequestChild({...f.options, constructChild: () => original});
    let caught = false; try {await child.prepare();} catch (cause) {caught = true;
      if (thrown) assert.strictEqual(cause, undefined); else assert.equal(cause.code, 'InstalledEffectRequestChildCleanupPending');}
    assert(caught); assert.equal(f.refined(), 0); assert.equal(f.counts().completed, 0); assert.equal(wires, 0);
    f.aliases(); assert.equal(await child.retry(), true); assert.equal(preparations, 1); assert.equal(f.counts().retired, 1);
  }
});

test('owned output rechecks original tuple after physical close before exposing or refining wire', async () => {
  const f = ownedFixture(), output = {}; let finish, closed = false, wires = 0;
  const closing = new Promise(resolve => {finish = resolve;});
  const original = {async prepare() {return output;},
    async release() {await closing; closed = true; return true;}, retry: () => true, status: () => ({pending: !closed}),
    retainedOutputWire() {wires++; return '{}';}};
  const child = prepareInstalledEffectOwnedRequestChild({...f.options, constructChild: () => original});
  const pending = child.prepare(); await new Promise(resolve => setImmediate(resolve));
  f.options.run.request = {}; finish(); await assert.rejects(pending, {code: 'ForeignInstalledEffectManagedRun'});
  assert.equal(wires, 0); assert.equal(f.refined(), 0); f.aliases(); assert.equal(await child.release(), true);
});


test('actual target output wire stays bound to its same closed immutable observation', async () => {
  const f = targetFixture(); const rows = await f.run();
  assert.deepEqual(JSON.parse(f.original().retainedOutputWire(rows[0])), rows[0]);
  assert.throws(() => f.original().retainedOutputWire({...rows[0]}), {code: 'ForeignMockTargetObservation'});
  f.f.aliases(); assert.equal(await f.managed().release(), true);
});

test('owned output refuses a missing actual completion port before invoking its child', async () => {
  const f = ownedFixture(); delete f.options.run.runtime.clientProgramInstalledEffectOperationConstructionCompleteOutput;
  let prepares = 0, closed = false;
  const original = {prepare() {prepares++; return {};},
    release() {closed = true; return true;}, retry() {closed = true; return true;},
    status: () => ({pending: !closed}), retainedOutputWire: () => '{}'};
  const child = prepareInstalledEffectOwnedRequestChild({...f.options, constructChild: () => original});
  await assert.rejects(async () => child.prepare(), {code: 'InstalledEffectOperationRuntimeUnavailable'});
  assert.equal(prepares, 0); assert.equal(f.refined(), 0); f.aliases(); assert.equal(await child.release(), true);
});
