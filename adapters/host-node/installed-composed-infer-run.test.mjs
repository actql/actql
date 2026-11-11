import assert from 'node:assert/strict';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {runInstalledComposedInfers} from './installed-composed-infer-run.mjs';

function beforeInstallation({failClose = false, retainedBytes = 0n, abort = false} = {}) {
  const setup = {};
  const cause = new Error('InjectedBeforeDriverOwnership');
  const controller = new AbortController();
  let owner, stops = 0, closes = 0, reservations = retainedBytes;
  const moon = {
    clientProgramResultCount: () => 0,
    clientProgramOpenCapturedComposedInferHost: () => setup,
    strategyHostStop(actual) {assert.equal(actual, setup); stops++;},
    strategyHostCloseOutputs(actual) {
      assert.equal(actual, setup); closes++;
      if (failClose && closes === 1) throw cause;
    },
    strategyHostUsage(actual) {
      assert.equal(actual, setup);
      return [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, reservations, 0n, 0n];
    },
  };
  return {
    cause, controller,
    arguments: {
      moon, selected: {components: []}, preparedProgram: {},
      plan: {runDefinition: {wire: '{"run_id":"original-run"}'}},
      acquiredInfer: {captured: {capture: {source: () => ({})}}},
      modelController: {discover: () => []}, computeConfigurations: {},
      signal: controller.signal,
      retainExecution(value) {assert.equal(owner, undefined); owner = value;},
      beginPhysicalWork() {
        assert.ok(owner, 'retain custody before the asynchronous driver boundary');
        if (abort) controller.abort(cause);
        else throw cause;
      },
    },
    owner: () => owner,
    counts: () => ({stops, closes}),
    releaseReservations() {reservations = 0n;},
  };
}

test('composed setup keeps the original Owner when start fails before driver installation', async () => {
  const boundary = beforeInstallation();
  await assert.rejects(runInstalledComposedInfers(boundary.arguments), error => error === boundary.cause);
  const owner = boundary.owner();
  assert.equal(owner.cleanupPending(), true);
  assert.equal(await owner.cleanup(), true);
  assert.equal(owner.cleanupPending(), false);
  assert.deepEqual(boundary.counts(), {stops: 1, closes: 1});
  assert.equal(await owner.close(), true);
  assert.deepEqual(boundary.counts(), {stops: 1, closes: 1}, 'successful cleanup is not repeated');
});

test('composed setup retains failed output close and retries the same exact setup', async () => {
  const boundary = beforeInstallation({failClose: true});
  await assert.rejects(runInstalledComposedInfers(boundary.arguments), error => error === boundary.cause);
  const owner = boundary.owner();
  await assert.rejects(owner.close(), error => error === boundary.cause);
  assert.equal(owner.cleanupPending(), true);
  assert.equal(await owner.cleanup(), true);
  assert.deepEqual(boundary.counts(), {stops: 2, closes: 2});
  assert.equal(owner.cleanupPending(), false);
});

test('composed setup does not report release while its retained reservations remain', async () => {
  const boundary = beforeInstallation({retainedBytes: 64n});
  await assert.rejects(runInstalledComposedInfers(boundary.arguments));
  const owner = boundary.owner();
  assert.equal(await owner.cleanup(), false);
  assert.equal(owner.cleanupPending(), true);
  boundary.releaseReservations();
  assert.equal(await owner.cleanup(), true);
  assert.equal(owner.cleanupPending(), false);
  assert.deepEqual(boundary.counts(), {stops: 2, closes: 2});
});

test('composed cleanup retains the actual reserved-attempt and holding fields', async () => {
  for (const index of [2, 3]) {
    const boundary = beforeInstallation();
    const original = boundary.arguments.moon.strategyHostUsage;
    let pending = true;
    boundary.arguments.moon.strategyHostUsage = actual => {
      original(actual);
      const values = Array(13).fill(0n);
      if (pending) values[index] = 1n;
      return values;
    };
    await assert.rejects(runInstalledComposedInfers(boundary.arguments), error => error === boundary.cause);
    assert.equal(await boundary.owner().cleanup(), false);
    assert.equal(boundary.owner().cleanupPending(), true);
    pending = false;
    assert.equal(await boundary.owner().cleanup(), true);
  }
});

test('composed cleanup does not retain spent transfer or historical peak as a live resource', async () => {
  const boundary = beforeInstallation();
  const original = boundary.arguments.moon.strategyHostUsage;
  boundary.arguments.moon.strategyHostUsage = actual => {
    original(actual);
    return [7n, 3n, 0n, 0n, 0n, 0n, 83n, 0n, 0n, 0n, 0n, 0n, 211n];
  };
  await assert.rejects(runInstalledComposedInfers(boundary.arguments), error => error === boundary.cause);
  assert.equal(await boundary.owner().cleanup(), true);
  assert.equal(boundary.owner().cleanupPending(), false);
});

test('composed setup is retained across the actual captured driver early AbortSignal check', async () => {
  const boundary = beforeInstallation({abort: true});
  await assert.rejects(runInstalledComposedInfers(boundary.arguments), error => error === boundary.cause);
  assert.equal(boundary.controller.signal.aborted, true);
  const owner = boundary.owner();
  assert.equal(owner.cleanupPending(), true);
  assert.equal(await owner.cleanup(), true);
  assert.deepEqual(boundary.counts(), {stops: 1, closes: 1});
});

// Isolate a cached driver close failure without changing the real early-abort
// test above or adding a product dependency-injection execution path.
test('composed driver cleanup recovers without awaiting its rejected close again', () => {
  const child = spawnSync(process.execPath, ['--input-type=module', '-e', `
    import assert from 'node:assert/strict';
    import {registerHooks} from 'node:module';
    const cause = new Error('InjectedDriverClose');
    const rejected = Promise.reject(cause);
    rejected.catch(() => {});
    let closes = 0, retries = 0, pending = true, owner;
    globalThis.composedTestExecution = {
      status: 'host-tasks-failed',
      close() {closes++; return rejected;},
      cleanupPending: () => pending,
      async cleanup() {retries++; pending = false; return true;},
    };
    const entry = new URL('./adapters/host-node/entry.mjs', 'file://' + process.cwd() + '/').href;
    const hook = registerHooks({load(url, context, next) {
      if (url === entry) return {format: 'module', shortCircuit: true,
        source: 'export async function runCapturedInternalStrategy() {return globalThis.composedTestExecution;}'};
      return next(url, context);
    }});
    const {runInstalledComposedInfers} = await import('./adapters/host-node/installed-composed-infer-run.mjs');
    hook.deregister();
    const setup = {};
    const moon = {clientProgramResultCount: () => 0,
      clientProgramOpenCapturedComposedInferHost: () => setup,
      strategyHostStop() {assert.fail('returned execution owns the setup');}};
    await assert.rejects(runInstalledComposedInfers({
      moon, selected: {components: []}, preparedProgram: {},
      plan: {runDefinition: {wire: '{"run_id":"original-run"}'}},
      acquiredInfer: {captured: {capture: {source: () => ({})}}},
      modelController: {discover: () => [], unresolved: () => false},
      computeConfigurations: {}, signal: new AbortController().signal,
      retainExecution(value) {owner = value;}, beginPhysicalWork() {},
    }), {message: 'InstalledComposedInferComputationFailed'});
    await assert.rejects(owner.close(), error => error === cause);
    assert.equal(owner.cleanupPending(), true);
    assert.equal(await owner.cleanup(), true);
    assert.equal(owner.cleanupPending(), false);
    assert.equal(closes, 1);
    assert.equal(retries, 1);
    assert.equal(await owner.close(), true);
    assert.equal(closes, 1);
    assert.equal(retries, 1);
  `], {cwd: fileURLToPath(new URL('../../', import.meta.url)), encoding: 'utf8', timeout: 30000});
  assert.equal(child.status, 0, child.stdout + child.stderr);
});


// Execute the original coordinators with explicit nominal/physical ports.
// These controls qualify the JS handoff, not Common execution or a close ACK.
function composedSourceFunction(path, name, ports) {
  const text = readFileSync(new URL(path, import.meta.url), 'utf8');
  const node = parse(text, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .map(node => node.declaration ?? node)
    .find(node => node.type === 'FunctionDeclaration' && node.id.name === name);
  assert(node);
  return Function(...Object.keys(ports), `return (${text.slice(node.start, node.end)});`)(...Object.values(ports));
}

test('internal composed entry preserves the original fifth cleanup envelope without public Result mode', async () => {
  const setup = {}, holder = {}, owner = {}, signal = new AbortController().signal;
  const cleanup = {preparationHolder: holder, retainPreflightCleanup(actual) {assert.strictEqual(actual, owner);}};
  const poison = {retainPreflightCleanup() {assert.fail('options cannot replace installed cleanup');}};
  const native = {}, install = () => assert.fail('no installation in this Source control');
  let loads = 0;
  const create = composedSourceFunction('./entry.mjs', 'createNodeHostEntry', {
    runCapturedStrategyTarget(facts) {
      assert.strictEqual(facts.setup, setup); assert.strictEqual(facts.control.signal, signal);
      assert.strictEqual(facts.cleanup, cleanup); assert.strictEqual(facts.composition.install, install);
      assert.equal(facts.results.publishCheckedResults, false);
      assert.notStrictEqual(facts.cleanup, facts.options.cleanup);
      facts.cleanup.retainPreflightCleanup(owner);
      return facts;
    },
  });
  const entry = create(async () => {loads++; return native;}, install);
  const facts = await entry.runCapturedInternalStrategy(setup, {cleanup: poison}, signal, undefined, cleanup);
  assert.equal(loads, 0);
  assert.strictEqual(await facts.composition.loadRuntime(), native);
  assert.strictEqual(await facts.composition.loadRuntime(), native);
  assert.equal(loads, 1);
});

async function composedPublicationHandoff({complete = true, preflight = false} = {}) {
  const events = [], setup = {}, preparedProgram = {}, graph = {}, occurrence = {};
  const operation = {}, issuance = {}, sourceEvidence = {}, modelEvidence = {}, store = {}, control = {};
  const captured = {capture: {retainTask(actual, task) {assert.strictEqual(actual, setup); assert.equal(task, 0);}}};
  const selection = {graph, occurrence}, component = {provider: {}};
  const original = {selection, component};
  const parent = {components: [original], preparationHolder: {}, retain() {events.push('retain-parent');},
    openCapturedHost(captures) {assert.deepEqual(captures, [captured]); return setup;},
    async retire() {events.push('retire-parent'); return true;}};
  const plan = {runDefinition: {wire: '{"run_id":"same-original-run"}'}};
  const execution = {status: 'host-tasks-completed'};
  const observation = {name: 'observation', wire: 'original-observation', identity: 'observation-cid'};
  const invocation = {name: 'invocation', wire: 'original-invocation', identity: 'invocation-cid'};
  const finalPlan = {originalEvidence: {}};
  let context, retainedOwner, publishes = 0, cleanupRetries = 0;
  const primary = new Error('OriginalComposedPreflightRefusal');
  const partial = {status: () => ({pending: cleanupRetries < 2}),
    async retry() {cleanupRetries++; events.push('retry-original-partial');}};
  component.bindOriginal = actual => {context = actual;};
  const moon = {clientProgramResultCount: () => 0, strategyHostRun: actual => actual,
    clientProgramInferPlanBoundary: () => [0], clientProgramAdvanceInferObservationIssuance(actual) {
      assert.strictEqual(actual, issuance); events.push('seal-original'); return [true];
    }};
  control.admitComposedInferSources = (actual, captures, evidence) => {
    assert.strictEqual(actual, occurrence); assert.deepEqual(captures, [captured]);
    assert.deepEqual(evidence, [sourceEvidence]); return {};
  };
  control.modelPrivateHoldingCid = (definition, authority, name) => {
    assert.strictEqual(definition, plan.runDefinition); return name;
  };
  const run = composedSourceFunction('./installed-composed-infer-run.mjs', 'runInstalledComposedInfers', {
    runtimeField: (value, index) => value[index], checked: value => value,
    withLocalExecutionPauseHandler: value => value,
    runCapturedStrategy() {assert.fail('intermediate Model driver cannot request public checked Result mode');},
    async runCapturedInternalStrategy(actual, options, signal, observer, cleanup) {
      assert.strictEqual(actual, setup); assert.strictEqual(cleanup.preparationHolder, parent.preparationHolder);
      assert.equal(typeof cleanup.retainPreflightCleanup, 'function'); events.push('private-compute');
      if (preflight) {cleanup.retainPreflightCleanup(partial); throw primary;}
      context.retainOperation(operation);
      if (complete) assert.equal(context.retainCompleted(), true);
      return execution;
    },
    openNodeInferCaptureCustody: () => ({retainCompleted(actual) {assert.strictEqual(actual, operation); return true;},
      completedCallCount: () => 1, async persist() {events.push('persist-capture');}, modelEvidence: () => [modelEvidence]}),
    startCompleteInferObservation(facts) {
      assert.deepEqual(facts.operations, [operation]); assert.equal(facts.maxSlots, 1); return issuance;
    },
    inferTaskPublicationPlan(facts) {
      assert.strictEqual(facts.preparedProgram, preparedProgram); assert.strictEqual(facts.admitted, plan);
      assert.strictEqual(facts.operation, operation); assert.strictEqual(facts.issuance, issuance);
      assert.deepEqual(facts.sourceEvidence, [sourceEvidence]); assert.deepEqual(facts.modelEvidence, [modelEvidence]);
      events.push('publication-plan'); return {observation, invocation, plan: finalPlan};
    },
    preparePrivatePublicationHolding(actual, facts) {
      assert.strictEqual(actual, store);
      assert([observation, invocation].some(value => value.wire === facts.wire && value.identity === facts.semanticCid));
      return {async commit() {events.push('commit-' + facts.name);}};
    },
    async publishCompletedEffectFreeRun(facts) {
      assert.strictEqual(facts.originalEvidence, finalPlan.originalEvidence);
      assert.strictEqual(facts.execution, execution); assert.strictEqual(facts.store, store); assert.strictEqual(facts.control, control);
      assert.deepEqual(events.slice(-2), ['commit-observation', 'commit-invocation']);
      publishes++; events.push('publish');
    },
    async projectInferEvidence(facts) {assert.strictEqual(facts.operation, operation); events.push('project');},
  });
  const promise = run({moon, control, preparedProgram, plan, selected: {components: [selection]}, store,
    acquiredInfer: {captured, sourceEvidence}, originalPreparation: parent,
    modelController: {discover: () => []}, computeConfigurations: {}, signal: new AbortController().signal,
    retainExecution(value) {retainedOwner = value;}, beginPhysicalWork() {events.push('begin');}});
  if (preflight) {
    await assert.rejects(promise, error => error === primary);
    assert.equal(await retainedOwner.cleanup(), false);
    assert.equal(retainedOwner.cleanupPending(), true);
    assert.equal(await retainedOwner.cleanup(), true);
    assert.equal(retainedOwner.cleanupPending(), false);
    assert.equal(await retainedOwner.cleanup(), true);
    assert.equal(cleanupRetries, 2, 'same retained partial settles once; no replacement setup');
    assert.equal(publishes, 0);
    return events;
  }
  if (complete) await promise;
  else await assert.rejects(promise, /InstalledComposedInferOriginalObservationUnavailable/u);
  assert.equal(retainedOwner.cleanupPending(), true, 'publication does not issue a physical cleanup ACK');
  assert.equal(publishes, complete ? 1 : 0);
  return events;
}

test('composed private Compute transfers the same complete original evidence to the existing final publisher', async () => {
  const events = await composedPublicationHandoff();
  assert(events.indexOf('seal-original') < events.indexOf('persist-capture'));
  assert(events.indexOf('persist-capture') < events.indexOf('publication-plan'));
  assert.deepEqual(events.slice(-2), ['publish', 'project']);
});

test('composed private Compute without its original complete issuance cannot publish a Result', async () => {
  const events = await composedPublicationHandoff({complete: false});
  assert.equal(events.includes('publication-plan'), false);
  assert.equal(events.includes('publish'), false);
});

test('composed private preflight preserves the same failed owner until its actual retry settles', async () => {
  const events = await composedPublicationHandoff({preflight: true});
  assert.deepEqual(events.slice(-3), ['retry-original-partial', 'retry-original-partial', 'retire-parent']);
});
