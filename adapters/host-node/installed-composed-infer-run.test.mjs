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

function publishedModelReadCaller({acquired = false, grouped = false} = {}) {
  const child = spawnSync(process.execPath, ['--input-type=module', '-e', `
    import assert from 'node:assert/strict';
    import {registerHooks} from 'node:module';
    const acquired = ${acquired}, grouped = ${grouped};
    const prepared = {}, compiled = {}, definition = {}, scope = {}, read = {}, holder = {}, ledger = {};
    const control = {prepareCheckedClientInferOriginalRead(c, d, g, s, budget) {
      assert.strictEqual(c, compiled); assert.strictEqual(d, definition);
      assert(models.some(model => model.graph === g && model.scope === s && model.budget === budget));
      reads++; return read;
    }};
    let reads = 0, entered = 0;
    globalThis.originalModelCaller = facts => {
      assert.strictEqual(facts.preparedProgram, prepared);
      assert.strictEqual(facts.plan, plan);
      assert.strictEqual(facts.control, control);
      assert.strictEqual(facts.acquiredInfer, source);
      const original = facts.originalPreparation;
      original.retain();
      for (const [index, view] of (original.components ?? [original]).entries()) {
        const body = view.prepareRead();
        assert.strictEqual(body.read, models[index].read);
        assert.strictEqual(body.inputBodyRead, body.read, 'published Model must retain its SAME original input body');
        assert.strictEqual(body.control, control); assert.strictEqual(body.compiled, compiled);
        assert.strictEqual(body.runDefinition, definition); assert.strictEqual(body.scope, models[index].scope);
        assert.throws(() => view.prepareRead(), /InvalidInstalledRequestModelPreparation/u);
      }
      assert.equal(reads, models.length);
      entered++;
    };
    const module = new URL('./adapters/host-node/installed-composed-infer-run.mjs', 'file://' + process.cwd() + '/').href;
    const hook = registerHooks({load(url, context, next) {
      if (url === module) return {format: 'module', shortCircuit: true,
        source: 'export async function runInstalledComposedInfers(facts) { return globalThis.originalModelCaller(facts); }'};
      return next(url, context);
    }});
    const {installNodeInferRun} = await import('./adapters/host-node/installed-infer-run.mjs');
    hook.deregister();
    const graphs = grouped ? [{}, {}] : [{}];
    const selections = graphs.map(graph => ({graph, occurrence: {}}));
    const selected = grouped ? {graph: graphs, components: selections} : selections[0];
    const plan = {compiled, runDefinition: definition, inferGraph: selected.graph};
    const moon = {clientProgramAcquisitionCount: () => acquired ? 1 : 0, clientProgramTaskCount: () => 2};
    const managed = {runtime: moon, prepared, value: {}, request: {}};
    const models = selections.map(selection => ({prepared, selection, graph: selection.graph,
      control, compiled, runDefinition: definition, managed, scope: {},
      component: {bindOriginal() {}}, publicationCapacity: () => ({}),
      budget: {readRetainedBytes: 7n, readExecutionBytes: 5n, modelRetainedBytes: 11n, modelExecutionBytes: 3n}}));
    const model = grouped ? {components: Object.freeze(models), scopes: models.map(model => model.scope),
      selection: selected, graph: selected.graph, control, compiled, runDefinition: definition, managed} : models[0];
    managed.model = model;
    if (grouped) for (const member of models) member.group = model;
    const source = acquired ? {managedRun: managed.value, ledger, captured: {}} : undefined;
    if (acquired) model.sourceLedger = ledger;
    const run = installNodeInferRun({moon, core: {publicationControl: control},
      selections: new Map([[prepared, selected]]), prepareOriginalModelRun(p, admitted, selection) {
        assert.strictEqual(p, prepared); assert.strictEqual(admitted, plan); assert.strictEqual(selection, selected);
        return model;
      }});
    await run({preparedProgram: prepared, plan, acquiredInfer: source,
      preparationHolder: acquired ? holder : undefined});
    assert.equal(entered, 1);
  `], {cwd: fileURLToPath(new URL('../../', import.meta.url)), encoding: 'utf8', timeout: 30000});
  assert.equal(child.status, 0, child.stdout + child.stderr);
}

test('ordinary published Model source-free caller forwards its same required input body read', () => {
  publishedModelReadCaller();
});

test('ordinary published Model captured caller forwards its same required input body read', () => {
  publishedModelReadCaller({acquired: true});
});

test('ordinary published Model group caller forwards each same required input body read', () => {
  publishedModelReadCaller({acquired: true, grouped: true});
});

// Actual Effect publication consumer; stop at its existing plan constructor.
// Logical dependency identity is a set, while each acquired Source occurrence
// and its admitted evidence remain distinct inputs to the original invocation.
test('actual multi-Source Effect publication keeps all Source originals but unique logical Result dependencies', () => {
  const logical = 'sha256:' + 'a'.repeat(64), stop = new Error('ReachedOriginalResultPlan');
  const sources = [0, 1, 2].map(slot => ({captured: {identity: {slot},
    occurrence: {stage: slot, input: 0, task: slot}}, sourceEvidence: {slot}}));
  const acquired = {prepared: {}, compilation: {}, admission: {}, definition: {},
    runDefinition: {wire: '{"created_at":"2026-11-11T00:00:00.000Z"}'},
    compiledPlan: {identity: 'original-plan'}};
  let invocations = 0, plans = 0;
  acquired.moon = {clientProgramEffectPublicationDataPolicyCid: () => 'original-policy',
    clientProgramEffectDefinitionCid: () => 'original-definition',
    clientProgramEffectCompilationResultNames: () => ['answer'],
    clientProgramCapturedSourceLogicalCid(identity) {assert(sources.some(source => source.captured.identity === identity)); return logical;}};
  acquired.control = {issueCheckedClientEffectMultiCapturedInvocation(prepared, compilation, admission, definition, actual) {
    assert.strictEqual(prepared, acquired.prepared); assert.strictEqual(compilation, acquired.compilation);
    assert.strictEqual(admission, acquired.admission); assert.strictEqual(definition, acquired.definition);
    assert.strictEqual(actual, sources); invocations++;
    return {observation: {}, invocation: {}};
  }};
  const run = composedSourceFunction('./local-values-plan.mjs', 'acquiredMultiEffectPublicationPlan', {
    limits: {}, buildLocalPublicationPlan(facts) {
      plans++; assert.deepEqual(facts.inputRelationCids, [logical]);
      assert.equal(facts.sourceEvidence.length, 3);
      for (const [index, original] of sources.entries()) assert.strictEqual(facts.sourceEvidence[index], original.sourceEvidence);
      throw stop;
    },
  });
  assert.throws(() => run({acquired, sources}), error => error === stop);
  assert.deepEqual({invocations, plans}, {invocations: 1, plans: 1});
});


// Execute the actual publication consumer with explicit same-Owner metadata
// ports. This does not execute a JOIN or supply a completed Artifact; that
// boundary is covered by the Core completed-producer fixture and normal Host.
for (const units of [[0, 0], [0, 0, 2]]) {
  test('multi-Source Effect publication groups originals by checked Unit ' + units.join(','), () => {
    const sourcePlan = {}, sourcePublication = {}, retention = {wire: '{}'}, combined = {invocation: {}, catalogBodies: []};
    const singles = new Map(), calls = [];
    const sources = units.map((stage, slot) => ({captured: {inputKind: 'whole-input',
      occurrence: {stage, input: slot < 2 ? slot : 0, task: slot, computeTask: stage},
      identity: {slot}, capture: {source: () => ({slot})}, wholeCapacity: {}, logicalInput: {}}, sourceEvidence: {slot}}));
    const acquired = {prepared: {}, requestIdentity: {}, compilation: {}, admission: {}, definition: {},
      runDefinition: {wire: '{"created_at":"2026-11-11T00:00:00.000Z"}'}, compiledPlan: {identity: 'original-plan'}};
    const moon = acquired.moon = {clientProgramEffectPublicationDataPolicyCid: () => 'original-policy',
      clientProgramEffectDefinitionCid: () => 'original-definition', clientProgramEffectCompilationResultNames: () => ['joined'],
      clientProgramCapturedSourceLogicalCid: identity => 'logical-' + identity.slot,
      clientProgramCapturedSourceSchemaCid: () => 'original-schema',
      clientProgramCapturedSourceDependencyBodies: identity => ['rows-' + identity.slot, 'original-schema-body'],
      clientProgramEffectPublicationPolicyBodies: () => ({ok: []})};
    acquired.control = {issueCheckedInstalledEffectDirectSourcesInvocation(plan, prepared, request, compilation, admission, definition, actual, evidence) {
      assert.strictEqual(plan, sourcePlan); assert.strictEqual(prepared, acquired.prepared); assert.strictEqual(request, acquired.requestIdentity);
      assert.strictEqual(actual, sources); assert.equal(evidence.length, sources.length); calls.push('full-invocation');
      return {observation: {}, invocation: {}, owner: {}, sourcePublication};
    }, prepareCombinedEffectSourceUnit(original, unit, policy) {
      assert.strictEqual(original, sourcePublication); assert.equal(unit, 0); assert.strictEqual(policy, retention);
      calls.push('combined-0'); return combined;
    }, issueCheckedWholeEffectSourceUnit(plan, prepared, request, slot) {
      assert.equal(units[slot], 2, 'a contribution to the joined Unit must never enter the single-producer issuer');
      calls.push('single-2'); const value = {catalogBodies: []}; singles.set(2, value); return value;
    }};
    const run = composedSourceFunction('./local-values-plan.mjs', 'acquiredMultiEffectPublicationPlan', {
      limits: {}, runtimeField: (value, index) => value[index], runtimeOptionalField: (value, index) => value[index],
      checked: value => value.ok, buildLocalPublicationPlan(facts) {
        assert.equal(facts.sourceEvidence.length, sources.length);
        return {plan: {}, retention, retentionDependencies: []};
      },
    });
    const plan = run({acquired, sources, sourcePlan});
    assert.deepEqual(calls, units.length === 2 ? ['full-invocation', 'combined-0'] : ['full-invocation', 'combined-0', 'single-2']);
    assert.strictEqual(plan.localEvidenceContext.acquiredEvidenceByUnit[0], combined);
    assert.equal(plan.localEvidenceContext.acquiredEvidenceByUnit[1], undefined);
    if (units.length === 3) assert.strictEqual(plan.localEvidenceContext.acquiredEvidenceByUnit[2], singles.get(2));
    assert.equal(plan.localEvidenceContext.acquisitionDependencies.length, sources.length * 2);
  });
}

// A final Model observation does not erase an upstream Unit's original Source
// context. These explicit ports exercise the actual consumer, not a provider.
test('combined upstream Source Unit publication remains available when later Models exist', () => {
  const managedRun = {}, sourcePlan = {}, unitInputs = {}, retention = {wire: '{}'}, combined = {catalogBodies: []};
  const sources = [0, 1].map(slot => ({captured: {inputKind: 'whole-input',
    occurrence: {stage: 0}, identity: {slot}, capture: {source: () => ({slot})}, logicalInput: {}},
    sourceEvidence: {slot}}));
  const model = {unit: 1}, calls = [];
  const acquired = {prepared: {}, requestIdentity: {}, compilation: {}, admission: {}, definition: {},
    runDefinition: {wire: '{"created_at":"2026-11-12T00:00:00.000Z"}'}, compiledPlan: {identity: 'same-plan'}};
  acquired.moon = {clientProgramEffectPublicationDataPolicyCid: () => 'original-policy',
    clientProgramEffectDefinitionCid: () => 'original-definition', clientProgramEffectCompilationResultNames: () => ['joined'],
    clientProgramCapturedSourceLogicalCid: identity => 'logical-' + identity.slot,
    clientProgramCapturedSourceSchemaCid: () => 'original-schema',
    clientProgramCapturedSourceDependencyBodies: identity => ['rows-' + identity.slot, 'schema'],
    clientProgramEffectPublicationPolicyBodies: () => ({ok: []})};
  acquired.control = {checkedClientEffectInferInvocation() {calls.push('complete-model'); return {
    observation: {}, invocation: {}, owner: {}};},
    issueCheckedInstalledEffectDirectSourcesInvocation() {assert.fail('no Source-only whole-Run observation');},
    prepareCheckedInstalledEffectSourceUnits(plan, prepared, request, compilation, admission, definition, actual, evidence) {
      assert.strictEqual(plan, sourcePlan); assert.strictEqual(prepared, acquired.prepared);
      assert.strictEqual(request, acquired.requestIdentity); assert.strictEqual(actual, sources);
      assert.equal(evidence.length, 2); calls.push('original-source-units'); return unitInputs;
    }, prepareInstalledEffectModelSourceUnit(actualRun, actualPlan, request, original, unit, policy) {
      assert.strictEqual(actualRun, managedRun); assert.strictEqual(actualPlan, sourcePlan);
      assert.strictEqual(request, acquired.requestIdentity);
      assert.strictEqual(original, unitInputs); assert.equal(unit, 0); assert.strictEqual(policy, retention);
      calls.push('combined-0'); return combined;
    }};
  const run = composedSourceFunction('./local-values-plan.mjs', 'acquiredMultiEffectPublicationPlan', {
    limits: {}, runtimeField: (value, index) => value[index], runtimeOptionalField: (value, index) => value[index],
    checked: value => value.ok, buildLocalPublicationPlan: () => ({plan: {}, retention, retentionDependencies: []}),
  });
  const plan = run({acquired, sources, sourcePlan, managedRun, issuedModel: {}, modelOriginals: [model]});
  assert.deepEqual(calls, ['complete-model', 'original-source-units', 'combined-0']);
  assert.strictEqual(plan.localEvidenceContext.acquiredEvidenceByUnit[0], combined);
  assert.strictEqual(plan.localEvidenceContext.modelOriginalByUnit[1], model);
  assert.equal(plan.localEvidenceContext.acquisitionDependencies.length, 4);
  assert.throws(() => run({acquired, sources, issuedModel: {}, modelOriginals: [model]}),
    /WholeEffectProducerUnitOriginalRequired/u);
});


test('upstream Source Unit preparation retains original bodies before Models and final publication reuses them', () => {
  const managedRun = {}, sourcePlan = {}, request = {}, inputs = {}, retention = {wire: '{}'}, combined = {catalogBodies: []};
  const sources = [0, 1].map(slot => ({captured: {inputKind: 'whole-input', occurrence: {stage: 0},
    identity: {slot}, capture: {source: () => ({slot})}, logicalInput: {}}, sourceEvidence: {slot}}));
  const calls = [];
  const moon = {clientProgramEffectPublicationDataPolicyCid: () => 'original-policy',
    clientProgramEffectDefinitionCid: () => 'original-definition', clientProgramEffectCompilationResultNames: () => ['joined'],
    clientProgramCapturedSourceLogicalCid: identity => 'logical-' + identity.slot,
    clientProgramCapturedSourceSchemaCid: () => 'schema',
    clientProgramCapturedSourceDependencyBodies: identity => ['rows-' + identity.slot, 'schema'],
    clientProgramEffectPublicationPolicyBodies: () => ({ok: []})};
  const acquired = {moon, prepared: {}, requestIdentity: request, compilation: {}, admission: {}, definition: {},
    runDefinition: {wire: '{"created_at":"2026-11-12T00:00:00.000Z"}'}, compiledPlan: {identity: 'same-plan'},
    selectRetention: () => Object.freeze({availableUntil: 'available', deleteBy: 'delete', metadataDeleteBy: 'metadata'})};
  acquired.control = {
    seal(kind, wire) {assert.equal(kind, 'result_retention_policy'); assert.equal(JSON.parse(wire).effective_data_policy_cid, 'original-policy');
      calls.push('retention'); return retention;},
    prepareCheckedInstalledEffectSourceUnits(plan, prepared, actualRequest, compilation, admission, definition, actualSources) {
      assert.strictEqual(plan, sourcePlan); assert.strictEqual(prepared, acquired.prepared); assert.strictEqual(actualRequest, request);
      assert.strictEqual(actualSources, sources); calls.push('source-inputs'); return inputs;
    },
    prepareInstalledEffectModelSourceUnit(run, plan, actualRequest, actualInputs, unit, policy) {
      assert.strictEqual(run, managedRun); assert.strictEqual(plan, sourcePlan); assert.strictEqual(actualRequest, request);
      assert.strictEqual(actualInputs, inputs); assert.equal(unit, 0); assert.strictEqual(policy, retention);
      calls.push('before-model-unit'); return combined;
    },
    checkedClientEffectInferInvocation() {calls.push('completed-models'); return {observation: {}, invocation: {}, owner: {}};},
  };
  const issueRetention = composedSourceFunction('./local-values-plan.mjs', 'issueLocalResultRetention', {
    retentionDependencies: [{cid: 'retention'}, {cid: 'metadata'}, {cid: 'clock'}], limits: {},
  });
  const prepare = composedSourceFunction('./local-values-plan.mjs', 'prepareAcquiredEffectSourceUnits', {
    issueLocalResultRetention: issueRetention, limits: {},
  });
  const original = prepare({acquired, sources, sourcePlan, managedRun, modelUnits: [1, 2]});
  assert.deepEqual(calls, ['retention', 'source-inputs', 'before-model-unit']);
  assert.strictEqual(original.byUnit.get(0).value, combined);
  const publish = composedSourceFunction('./local-values-plan.mjs', 'acquiredMultiEffectPublicationPlan', {
    limits: {}, runtimeField: (value, index) => value[index], runtimeOptionalField: (value, index) => value[index], checked: value => value.ok,
    buildLocalPublicationPlan(options) {assert.strictEqual(options.originalRetention, retention); return {plan: {}, retention, retentionDependencies: []};},
  });
  const final = publish({acquired, sources, sourcePlan, managedRun, sourceUnitsOriginal: original,
    issuedModel: {}, modelOriginals: [{unit: 1}, {unit: 2}]});
  assert.strictEqual(final.localEvidenceContext.acquiredEvidenceByUnit[0], combined);
  assert.deepEqual(calls, ['retention', 'source-inputs', 'before-model-unit', 'completed-models']);
  assert.throws(() => publish({acquired, sources: sources.slice(), sourcePlan, managedRun, sourceUnitsOriginal: original,
    issuedModel: {}, modelOriginals: [{unit: 1}, {unit: 2}]}), /ForeignEffectSourceUnitOriginal/u);
});
