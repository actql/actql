import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {checked} from '../host-common/runtime-result.mjs';
import type {CallExpression, FunctionDeclaration, Identifier, ObjectExpression, Property, VariableDeclaration} from 'acorn';
import {prepareInstalledEffectOwnedRequestChild, prepareInstalledEffectRequestChild}
  from './installed-effect-child-construction.mjs';
import {prepareInstalledPhysicalWritePlanRecipe} from './installed-effect-recipe-construction.mjs';
import {captureInstalledEffectPlanRecipe} from './installed-effect-recipe.mjs';

type OwnedOptions = Parameters<typeof prepareInstalledEffectOwnedRequestChild>[0];
type Run = OwnedOptions['run'];
type Runtime = {-readonly [Field in keyof Run['runtime']]: Run['runtime'][Field]} & {
  clientProgramInstalledEffectManagedOperationPlan: Run['readPlan'];
};
type PhysicalRuntime = Parameters<typeof prepareInstalledPhysicalWritePlanRecipe>[0]['moon'];
type ManagedChild = ReturnType<typeof prepareInstalledEffectOwnedRequestChild>;
type OriginalChild = ReturnType<OwnedOptions['constructChild']>;
type TargetOptions = Readonly<{authorize(): Promise<unknown>; consume(bytes: Uint8Array): unknown}>;

// Recipe composition, replacement charging and versioned partial updates use
// actual Catalog/Common/file controls in installed-project-mock.actual.test.mjs.
// Do not reconstruct the private recipe or send method to fake their dependencies.

function ownedFixture() {
  const token = {}, prepared = {}, request = {}, parent = {}, plan = {};
  let entered = 0, completed = 0, retired = 0, aliases = false, refined = 0;
  const runtime: Runtime = {
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
  const f = ownedFixture(), output = {}; let finish: (value: object) => void, released = false, factories = 0;
  const task = new Promise<object>(resolve => {finish = resolve;});
  const original = {prepare() {assert.equal(factories, 1); return task;},
    async release() {await task; return released;}, retry: () => released, status: () => ({pending: !released})};
  const child = prepareInstalledEffectOwnedRequestChild({...f.options, constructChild() {factories++; return original;}});
  const pending = child.prepare(); assert.deepEqual(f.counts(), {entered: 1, completed: 0, retired: 0});
  f.aliases(); const closing = child.release();
  assert.equal(f.counts().retired, 0);
  finish!(output); assert.strictEqual(await pending, output); assert.equal(await closing, false);
  assert.equal(f.counts().completed, 1); assert.equal(f.counts().retired, 0);
  released = true; assert.equal(await child.retry(), true);
  assert.deepEqual(f.counts(), {entered: 1, completed: 1, retired: 1}); assert.equal(factories, 1);
});

test('owned async file failure preserves undefined and retains cleanup until the same physical retry', async () => {
  const f = ownedFixture(); let reject: (reason: unknown) => void, closed = false, attempts = 0;
  const task = new Promise((_yes, no) => {reject = no;});
  const original = {prepare() {attempts++; return task;}, release: () => false,
    retry: () => closed, status: () => ({pending: !closed})};
  const child = prepareInstalledEffectOwnedRequestChild({...f.options, constructChild: () => original});
  const pending = child.prepare(); reject!(undefined);
  let caught = false; try {await pending;} catch (cause) {caught = true; assert.strictEqual(cause, undefined);}
  assert(caught); f.aliases(); assert.equal(await child.release(), false);
  assert.equal(f.counts().retired, 0); assert.equal(f.counts().completed, 0);
  closed = true; assert.equal(await child.retry(), true); assert.equal(attempts, 1);
  assert.equal(f.counts().retired, 1);
});

test('owned async request rechecks the same original after await and never completes a foreign record', async () => {
  const f = ownedFixture(); let finish: (value: object) => void, closed = false;
  const task = new Promise<object>(resolve => {finish = resolve;});
  const original = {prepare: () => task, release() {closed = true; return true;},
    retry() {closed = true; return true;}, status: () => ({pending: !closed})};
  const child = prepareInstalledEffectOwnedRequestChild({...f.options, constructChild: () => original});
  const pending = child.prepare(); f.options.run.request = {}; finish!({});
  await assert.rejects(pending as Promise<unknown>, {code: 'ForeignInstalledEffectManagedRun'});
  assert.equal(f.counts().completed, 0); f.aliases(); assert.equal(await child.release(), true);
});

test('ordinary constructors still refuse a Promise instead of borrowing the owned-child join', async () => {
  const f = ownedFixture(),
    // @ts-expect-error The runtime must refuse a Promise from this synchronous constructor.
    child = prepareInstalledEffectRequestChild({...f.options, construct: () => Promise.resolve({})});
  await assert.rejects(child.prepare() as Promise<unknown>, {code: 'InstalledEffectConstructorNotSynchronous'});
  assert.equal(f.counts().completed, 0); f.aliases(); assert.equal(child.release(), true);
});

test('non-HTTP target phases have distinct original constructor slots and reject aliasing another role', () => {
  const capacities = Array.from({length: 6}, () => ({}));
  const moon = {
    clientProgramInstalledSourceConstructionCapacity: () => ({$tag: 1, _0: {}}),
    clientProgramInstalledEffectControlWireBound: () => ({$tag: 1, _0: 1024}),
    clientProgramInstalledPhysicalWriteRecipeCapacitiesWithRequest: () => ({$tag: 1, _0: capacities}),
    clientProgramInstalledEffectCaptureRecipeExtentPrepare: () => ({$tag: 1, _0: {}}),
    clientProgramInstalledEffectOperationStagedExtentPrepare: (initial: unknown, maximum: unknown) => ({$tag: 1, _0: {initial, maximum}}),
    clientProgramInstalledEffectOperationExtentFromCapacityPrepare: () => ({$tag: 1, _0: {}}),
  } as unknown as PhysicalRuntime;
  const zero = Object.freeze({nodes: 0n, text: 0n, wire: 0n});
  const recipe = prepareInstalledPhysicalWritePlanRecipe({moon, operation: 'file.update', targetReadOperation: 'file.observe',
    construction: Object.freeze({retained: zero, workspace: zero}), requestConstruction: {},
    inputLimits: {body: {maxBytes: 100, maxNodes: 100, maxDepth: 16}, preview: {maxWireBytes: 100, maxNodes: 100, maxDepth: 16}},
    limits: {maxRequestBytes: 100, maxRecoveryBytes: 100, maxResponseBytes: 100, maxOutcomeBytes: 100, maxTransferBytes: 100}});
  assert.deepEqual(recipe.ownedReadOperations, [
    {phase: 'capture-target', operationIndex: 2}, {phase: 'apply-target', operationIndex: 3},
    {phase: 'resume-target', operationIndex: 4}]);
  assert.equal(recipe.requestConstruction!.operationIndex, 0); assert.equal(recipe.physicalWrite!.operationIndex, 1);
  for (const operations of [[{phase: 'capture-target', operationIndex: 0}],
    [{phase: 'capture-target', operationIndex: 2}, {phase: 'apply-target', operationIndex: 2}],
    [{phase: 'capture-target', operationIndex: 2}, {phase: 'capture-target', operationIndex: 3}]]) {
    assert.throws(() => captureInstalledEffectPlanRecipe({...recipe, ownedReadOperations: operations}, 7),
      {code: 'InvalidInstalledEffectPlanRecipe'});
  }
});

function targetFixture({pending = false, prepareFailure}: Readonly<{pending?: boolean; prepareFailure?: Readonly<{cause: unknown}>}> = {}) {
  const text = readFileSync(new URL('../local-node/installed-mock-row-effect.mjs', import.meta.url), 'utf8');
  const ast = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  const driver = ast.body.find((node): node is FunctionDeclaration => node.type === 'FunctionDeclaration' && node.id!.name === 'mockRowEffectDriver')!;
  const declaration = driver.body.body.flatMap(node => (node as Partial<VariableDeclaration>).declarations ?? []).find(node => (node.id as Identifier).name === 'driver')!;
  const method = ((declaration.init as CallExpression).arguments[0] as ObjectExpression).properties.find((node): node is Property => ((node as Property).key as Identifier).name === 'observeTargets')!;
  const retire = driver.body.body.find((node): node is FunctionDeclaration => node.type === 'FunctionDeclaration' && node.id!.name === 'retireChild')!;
  const f = ownedFixture(), member = {}, selected = {}, request = {}, runOriginal = {}, events: string[] = [];
  const target = {}, record = {target: 'same-target'};
  let child: OriginalChild | undefined, managed: ManagedChild | undefined, originalChild: OriginalChild | undefined,
    closed = false, constructorCalls = 0;
  const ports = {memberCurrent: (actual: unknown) => {assert.strictEqual(actual, member); return target;},
    targetForRecord: (actual: unknown) => {assert.strictEqual(actual, record); return target;},
    description(actual: unknown, run: unknown, observedTarget: unknown) {
      assert.strictEqual(actual, selected); assert.strictEqual(run, runOriginal);
      assert.strictEqual(observedTarget, target);
    },
    runCurrent: (actual: unknown) => assert.strictEqual(actual, runOriginal),
    own: (actual: unknown) => {assert.strictEqual(actual, request); return {record};},
    consume: () => ({}), admit(bytes: unknown, actual: unknown) {assert.strictEqual(actual, target); return {};},
    observe: () => ({versionCid: 'same-version', before: {id: 'same-target'}, beforeWire: '{"id":"same-target"}'}),
    wire: JSON.stringify,
    fail: (code: string) => {throw Object.assign(new Error(code), {code});},
    file: {readChild(options: TargetOptions) {
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
    authorizationForRow: async (index: number) => {assert.equal(index, 0); return {};},
    ownedReadChild(constructChild: OwnedOptions['constructChild'], rowIndex: number) {
      assert.equal(rowIndex, 0);
      managed = prepareInstalledEffectOwnedRequestChild({...f.options, constructChild() {
        originalChild = constructChild(); return originalChild;
      }});
      return managed.prepare();
    }}), managed: () => managed!, original: () => originalChild!, f, events, constructors: () => constructorCalls};
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
      assert.equal((issue as {code: string}).code, 'MockFileCleanupPending'); assert.equal(await f.managed().release(), false);
      assert.equal(await f.managed().retry(), true);
    } else {assert.strictEqual(issue, undefined); assert.equal(await f.managed().release(), true);}
    assert.equal(f.f.counts().retired, 1); assert.equal(f.constructors(), 1);
  }
});


test('owned output uses its original wire only after actual close and preserves its opaque output', async () => {
  const f = ownedFixture(), output = Object.freeze({}), events: string[] = []; let closed = false;
  const original = {async prepare() {events.push('prepare'); return output;},
    async release() {events.push('close'); closed = true; return {pending: false};},
    retry: () => ({pending: !closed}), status: () => ({pending: !closed}),
    retainedOutputWire(actual: unknown) {assert.strictEqual(actual, output); assert(closed); events.push('wire'); return '{"id":1}';}};
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
      if (thrown) assert.strictEqual(cause, undefined); else assert.equal((cause as {code: string}).code, 'InstalledEffectRequestChildCleanupPending');}
    assert(caught); assert.equal(f.refined(), 0); assert.equal(f.counts().completed, 0); assert.equal(wires, 0);
    f.aliases(); assert.equal(await child.retry(), true); assert.equal(preparations, 1); assert.equal(f.counts().retired, 1);
  }
});

test('owned output rechecks original tuple after physical close before exposing or refining wire', async () => {
  const f = ownedFixture(), output = {}; let finish: () => void, closed = false, wires = 0;
  const closing = new Promise<void>(resolve => {finish = resolve;});
  const original = {async prepare() {return output;},
    async release() {await closing; closed = true; return true;}, retry: () => true, status: () => ({pending: !closed}),
    retainedOutputWire() {wires++; return '{}';}};
  const child = prepareInstalledEffectOwnedRequestChild({...f.options, constructChild: () => original});
  const pending = child.prepare(); await new Promise(resolve => setImmediate(resolve));
  f.options.run.request = {}; finish!(); await assert.rejects(pending as Promise<unknown>, {code: 'ForeignInstalledEffectManagedRun'});
  assert.equal(wires, 0); assert.equal(f.refined(), 0); f.aliases(); assert.equal(await child.release(), true);
});


test('actual target output wire stays bound to its same closed immutable observation', async () => {
  const f = targetFixture(); const rows = await f.run();
  assert.deepEqual(JSON.parse(f.original().retainedOutputWire!(rows[0])), rows[0]);
  assert.throws(() => f.original().retainedOutputWire!({...rows[0]}), {code: 'ForeignMockTargetObservation'});
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
