import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {installLocalPreparationRegistry} from './local-preparation-registry.mjs';
import {finishInstalledEffectModelScope} from './installed-effect-managed-run.mjs';

// Run the original Local caller and cleanup with explicit Host/Core ports.
// These observations are not a Common issuer, backing proof or physical ACK.
// Execute the unchanged shared retirement body with the existing explicit
// completion-observer port; the private runtime marker is not manufactured.
const retirementSource = readFileSync(new URL('./infer-operation.mjs', import.meta.url), 'utf8');
const retirementNode = parse(retirementSource, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .find(node => node.declaration?.id?.name === 'retireNodeInferOriginalRead').declaration;
const retirementFor = observer => Function('inferOriginalReadCleanupComplete',
  'return ' + retirementSource.slice(retirementNode.start, retirementNode.end))(observer);
const source = readFileSync(new URL('../local-node/installed-project-mock.mjs', import.meta.url), 'utf8');
const outer = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .find(node => node.declaration?.id?.name === 'installPreparedProjectMockSources').declaration;
const names = ['sameRun', 'prepareManagedMockModelRun', 'modelPreparation', 'retireModelRead',
  'retireRunRecord', 'closeRead', 'closePhysicalRead', 'closeSource', 'close'];
const slices = outer.body.body.filter(node => node.type === 'FunctionDeclaration' && names.includes(node.id.name) ||
  node.type === 'VariableDeclaration' && names.includes(node.declarations[0].id.name))
  .map(node => source.slice(node.start, node.end)).join('\n');

function fixture({callback = true, refuse, missingScope = false} = {}) {
  const prepared = {}, request = {}, compiled = {}, runDefinition = {}, graph = {}, occurrence = {};
  const original = {}, value = {}, scope = {}, read = {}, calls = [], records = new Map();
  const sourceReady = [true, true], sources = [], closedSources = new Set();
  const primary = new Error('original-current');
  let currentFailure, finish = true, settleFailure, readIssued = false, readSettled = false;
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const control = {
    prepareCheckedClientInferOriginalRead(c, d, g, s) {
      assert.deepEqual([c, d, g, s], [compiled, runDefinition, graph, scope]);
      calls.push('read'); readIssued = true; return read;
    },
    stopCheckedClientInferOriginalReadPreparation(c, d, g, s, r) {
      assert.deepEqual([c, d, g, s, r], [compiled, runDefinition, graph, scope, read]);
      calls.push('stop-read');
    },
    settleCheckedClientInferOriginalReadPreparation(c, d, g, r, complete) {
      assert.deepEqual([c, d, g, r, complete], [compiled, runDefinition, graph, read, true]);
      calls.push('settle-read'); if (settleFailure) throw settleFailure;
      assert(!readSettled); readSettled = true;
    },
    finishCheckedClientInferOriginalReadScope(c, d, g, s, complete) {
      assert.deepEqual([c, d, g, s, complete], [compiled, runDefinition, graph, scope, true]);
      calls.push('scope'); return finish && (!readIssued || readSettled);
    },
  };
  const current = () => {if (currentFailure) throw currentFailure;};
  const moon = {
    clientProgramInstalledManagedRunCheck(v, p, r) {
      assert.deepEqual([v, p, r], [value, prepared, request]); calls.push('check');
    },
    clientProgramInstalledSourceReadRetire: () => {calls.push('source-core-retire');},
    clientProgramInstalledManagedRunRetire: () => assert.fail('Local child cannot retire its Request parent'),
    clientProgramAcquisitionCount: () => 2,
  };
  let model, release;
  const prepareRequestModel = !callback ? undefined : (p, r, actual) => {
    assert.equal(p, prepared); assert.equal(r, request);
    assert.equal(records.get(prepared).model, actual, 'Retain carrier before the Host can issue Scope');
    model = actual; release = actual.releaseAliases; calls.push('host');
    assert.equal(model.control, control); assert.equal(model.scope, undefined);
    if (!missingScope) model.scope = scope;
    model.budget = {readRetainedBytes: 3n, readExecutionBytes: 4n,
      modelRetainedBytes: 5n, modelExecutionBytes: 6n};
    if (refuse) throw refuse;
    return {original, value};
  };
  const api = Function('current', 'records', 'fail', 'checked', 'moon', 'sources', 'closedSources',
    'retireNodeInferOriginalRead', 'prepareRequestModel',
    `let closing=false;const effectRuns=new WeakMap(),effectReads=new Set();${slices};return {prepareManagedMockModelRun,modelPreparation,close};`)(
    current, records, fail, value => value, moon, sources, closedSources, retirementFor(() => false), prepareRequestModel);
  sources.push(...[0, 1].map(index => ({close: async () => {
    for (const record of records.values()) for (const read of record.reads) {
      if (read?.source === index && !read.closed) {
        const result = await Reflect.apply(read.close, read.raw, []);
        if (result.pending) fail('InstalledMockSourceCleanupPending');
        read.closed = true;
      }
    }
  }})));
  const plan = {compiled, runDefinition}, selection = {graph, occurrence};
  return {api, calls, records, prepared, request, control, plan, selection, scope, original, value, primary, sourceReady,
    begin: () => api.prepareManagedMockModelRun(prepared, request, control, plan, selection),
    preparation: () => api.modelPreparation(prepared, plan),
    get model() {return model;},
    get release() {return release;},
    attachSources() {records.get(prepared).reads = [0, 1].map(source => ({source, closed: false,
      raw: {source}, close() {calls.push('source'+this.source); return {pending: !sourceReady[this.source]};}}));},
    setFinish: value => {finish = value;}, setSettleFailure: value => {settleFailure = value;},
    loseCurrent: () => {currentFailure = primary;}};
}

test('Local Model retains the exact Request carrier before the actual Host constructor and never issues a standalone Run', () => {
  const f = fixture(); f.begin(); const record = f.records.get(f.prepared);
  assert.equal(record.original, f.original); assert.equal(record.value, f.value);
  assert.equal(record.model.scope, f.scope); assert.equal(record.requestOwned, true);
  f.begin(); assert.equal(f.calls.filter(value => value === 'host').length, 1);
  assert.throws(() => f.api.prepareManagedMockModelRun(f.prepared, {}, f.control, f.plan, f.selection),
    {code: 'ForeignInstalledModelPreparation'});
  assert.throws(() => f.api.prepareManagedMockModelRun(f.prepared, f.request, {}, f.plan, f.selection),
    {code: 'ForeignInstalledModelPreparation'});
  f.loseCurrent(); assert.throws(f.begin, error => error === f.primary);
  const g = fixture({callback: false});
  assert.throws(g.begin, {code: 'InstalledMockModelOperationalAdmissionUnavailable'});
  assert.equal(g.records.size, 0);
});

test('Local Model pending Sources and original read settlement retain the same parent until Scope cleanup', async () => {
  const f = fixture(); f.begin(); f.attachSources();
  const model = f.model, preparation = f.preparation(); preparation.retain(); preparation.prepareRead();
  f.sourceReady[0] = false;
  await assert.rejects(preparation.retire(), {code: 'InstalledMockSourceCleanupPending'});
  assert(!f.calls.includes('settle-read')); assert.equal(model.scope, f.scope);
  assert.throws(() => Reflect.apply(f.release, model, []), {code: 'InstalledMockModelCleanupPending'});
  f.sourceReady[0] = true; const primary = new Error('original-read-settlement'); f.setSettleFailure(primary);
  await assert.rejects(preparation.retire(), error => error === primary);
  assert(model.read); assert(!f.calls.includes('scope'));
  f.setSettleFailure(undefined); f.setFinish(false);
  assert.equal(await preparation.retire(), false); assert.equal(model.read, undefined);
  assert.equal(model.scopeFinished, undefined); assert.equal(f.records.get(f.prepared).value, f.value);
  f.setFinish(true); assert.equal(await preparation.retire(), true);
  assert.equal(model.scopeFinished, true); assert.equal(model.closed, true);
  assert.equal(f.records.get(f.prepared).original, f.original);
  assert.equal(await preparation.retire(), true);
  assert.equal(f.calls.filter(value => value === 'scope').length, 2);
  // This is the existing Host's later alias-retirement continuation; the
  // component does not manufacture its Core payload-sever witness.
  Reflect.apply(f.release, model, []);
  assert.equal(f.records.size, 0); assert.equal(model.scope, undefined);
  Reflect.apply(f.release, model, []);
  assert.throws(() => Reflect.apply(f.release, {}, []), {code: 'ForeignInstalledModelPreparation'});
});

test('Local Model constructor failure keeps its issued Scope and original failure for the same cleanup', async () => {
  const primary = new Error('original-completion-refusal'), f = fixture({refuse: primary});
  assert.throws(f.begin, error => error === primary); const model = f.model;
  assert.equal(model.scope, f.scope); assert.equal(f.records.get(f.prepared).failure, primary);
  assert.throws(f.begin, error => error === primary);
  assert.equal(f.calls.filter(value => value === 'host').length, 1);
  f.setFinish(false); await assert.rejects(f.api.close(), {message: 'InstalledMockSourceCleanupPending'});
  assert.equal(model.scope, f.scope);
  f.setFinish(true); await f.api.close();
  assert.equal(model.scopeFinished, true); assert.equal(model.scope, f.scope);
  Reflect.apply(f.release, model, []); assert.equal(model.scope, undefined);
});

const managerSource = readFileSync(new URL('./ordinary-source-managed.mjs', import.meta.url), 'utf8');
const managerHelpers = managerSource.slice(managerSource.indexOf('  function constructRequestDomain('), managerSource.indexOf('  const view = Object.freeze({'));
const methodStart = managerSource.indexOf('    prepareModelRun(');
const methodEnd = managerSource.indexOf('    adoptModelPreparation(', methodStart);
assert(methodStart >= 0 && methodEnd > methodStart);
function managerFixture(refusal) {
  const prepared = {}, request = {}, identity = {}, model = {graph: {}}, parent = {}, input = {}, compilation = {}, plan = {};
  const state = {prepared, compilationFamily: 'model', parent}, producer = {preparation: state, receipt: input};
  const calls = [], adopted = {};
  const fail = code => {throw Object.assign(new Error(code), {code});};
  let object;
  const view = {
    prepareModelCompilation(p, r, graph) {
      assert.deepEqual([p, r, graph], [prepared, request, model.graph]); calls.push('compile'); return compilation;
    },
    adoptModelPreparation(p, i, value, actual) {
      assert.deepEqual([p, i, value, actual], [prepared, identity, plan, model]);
      assert.equal(state.preparing, false); calls.push('adopt'); return adopted;
    },
  };
  object = Function('current', 'producerForRequest', 'fail', 'view',
    `const pendingRunRegistrations=new Set();${managerHelpers}return ({${managerSource.slice(methodStart, methodEnd).trim().replace(/,$/u, '')}});`)(
    () => {}, r => {assert.equal(r, request); return producer;}, fail, view);
  const construct = (p, i, c) => {
    assert.deepEqual([p, i, c], [parent, input, compilation]); assert.equal(state.preparing, true);
    calls.push('construct');
    assert.throws(() => object.prepareModelRun(prepared, request, identity, model, construct),
      {code: 'ForeignInstalledSourceProducer'});
    if (refusal) throw refusal; return plan;
  };
  return {state, calls, adopted, invoke: () => object.prepareModelRun(prepared, request, identity, model, construct)};
}

test('Model manager hands the same parent, input and original compiler to one guarded constructor before adoption', () => {
  const f = managerFixture(); assert.equal(f.invoke(), f.adopted);
  assert.deepEqual(f.calls, ['compile', 'construct', 'adopt']); assert.equal(f.state.preparing, false);
});

test('Model manager preserves a constructor refusal without reentering its compiler or adopter', () => {
  const primary = new Error('original-constructor'), f = managerFixture(primary);
  assert.throws(f.invoke, error => error === primary); assert.throws(f.invoke, error => error === primary);
  assert.deepEqual(f.calls, ['compile', 'construct']); assert.equal(f.state.preparing, false);
  assert.equal(f.state.preparationFailure, primary);
});

const hostSource = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const hostStart = hostSource.indexOf('    prepareManagedModelRun(runtime,');
const hostEnd = hostSource.indexOf('    prepareManagedComputeRun(runtime,', hostStart);
const retireStart = hostSource.indexOf('    retireManagedComputeRun(prepared) {');
const retireEnd = hostSource.indexOf('    isOriginalManagedComputePreparationRefusal(', retireStart);
assert(hostStart >= 0 && hostEnd > hostStart && retireStart >= 0 && retireEnd > retireStart);
function hostFixture({refuse, failAfterAdopt = false, retainedSelection = false, missingSelectionRetirement = false, nodeModel = false, onScopeFinish} = {}) {
  const prepared = {}, request = {}, sdkRequest = {}, original = {}, value = {}, parent = {}, input = {}, compilation = {};
  const scope = {}, calls = [], model = {compiled: {}, runDefinition: {}, graph: {}, scope: undefined};
  const record = {mockSourceProfile: {}}, originalInstallation = {releaseRequestDomainAliases() {}}, originals = {};
  if (missingSelectionRetirement) delete originalInstallation.releaseRequestDomainAliases;
  const primary = new Error('original-check-after-adopt');
  let finish = true, physicalDone = false, payloadSevered = false, severFailure;
  const selections = new WeakMap(), earlyPlans = new WeakMap();
  if (retainedSelection) {
    selections.set(prepared, {graph: model.graph, providerBinding: {}, account: {}});
    earlyPlans.set(prepared, {compiled: model.compiled, definition: model.runDefinition});
    originalInstallation.releaseRequestDomainAliases = p => {
      assert.equal(p, prepared); assert(physicalDone);
      selections.delete(p); earlyPlans.delete(p); calls.push('selection-aliases');
    };
  }
  const control = {
    finishCheckedClientInferOriginalReadScope(c, d, g, s, complete) {
      assert.deepEqual([c, d, g, s, complete], [model.compiled, model.runDefinition, model.graph, scope, true]);
      calls.push('scope'); onScopeFinish?.(); return finish;
    },
  };
  model.control = control;
  if (nodeModel) model.originalReadInstallation = {};
  model.releaseAliases = function() {
    assert.equal(this, model); calls.push('aliases');
    if (model.scopeFinished !== true || model.read !== undefined) throw new Error('OriginalChildrenPending');
    if (!refuse && !payloadSevered) assert.fail('Alias retirement must follow the original payload sever');
    physicalDone = true;
  };
  const moon = {
    clientProgramInstalledManagedRunRetire(v) {
      assert.equal(this, moon); assert.equal(v, value); calls.push('retire');
      payloadSevered = true;
    },
    clientProgramInstalledManagedRunCheck(v, p, r) {
      assert.equal(this, moon); assert.deepEqual([v, p, r], [value, prepared, request]);
      calls.push('check'); if (failAfterAdopt) throw primary;
    },
    clientProgramInstalledPreparationPayloadSevered: () => payloadSevered,
  };
  const manager = {
    prepareModelRun(p, r, i, actual, construct) {
      assert.deepEqual([p, r, i, actual], [prepared, sdkRequest, request, model]);
      assert.equal(record.computeRuns.get(prepared).model, model);
      assert.equal(originalInstallation.computeRuns, record.computeRuns);
      calls.push('manager'); construct(parent, input, compilation); model.scope = scope;
      if (refuse) throw refuse; return {original, value};
    },
    severPreparation(p, o) {
      assert.deepEqual([p, o], [prepared, original]); assert(payloadSevered); calls.push('sever');
      if (severFailure) {const failure = severFailure; severFailure = undefined; throw failure;}
    },
  };
  const construct = (o, run, actual, c, p, i) => {
    assert.deepEqual([o, actual, c, p, i], [originals, model, compilation, parent, input]);
    assert.equal(record.computeRuns.get(prepared), run); calls.push('construct');
    run.preparedSequences = {}; run.modelPlan = {};
    return run.modelPlan;
  };
  const ports = {sourceManaged: manager, moon, record, originalInstallation, originals, finishInstalledEffectModelScope,
    runtimeCore: () => ({publicationControl: control}),
    clientOperationError: code => Object.assign(new Error(code), {code}),
    assertSourceManagedInstallationCurrent(actual, o) {assert.equal(actual, manager); assert.equal(o, originals);},
    originalSourceManagedHostRequest(o, p) {assert.equal(o, originals); assert.equal(p, prepared); return sdkRequest;},
    prepareRequestMockModelPlan: construct, checked: value => value,
    managedPreparationRetirementContinuation(run) {
      assert(physicalDone); assert.equal(run.closed, true); return () => {calls.push('finish');};
    },
  };
  const object = Function(...Object.keys(ports), `return ({${hostSource.slice(hostStart, hostEnd)}
    ${hostSource.slice(retireStart, retireEnd).trim().replace(/,$/u, '')}});`)(...Object.values(ports));
  return {record, model, scope, calls, original, value, prepared, request, primary,
    begin: () => object.prepareManagedModelRun(moon, prepared, request, model),
    retire: () => object.retireManagedComputeRun(prepared),
    finishScope: () => {model.scopeFinished = true;}, setFinish: value => {finish = value;},
    failSever: failure => {severFailure = failure;},
    selectionHeld: () => selections.has(prepared) || earlyPlans.has(prepared)};
}

test('Host Model adoption uses its existing run bag and retains transient originals until actual adoption succeeds', () => {
  const f = hostFixture(); const run = f.begin();
  assert.equal(run.original, f.original); assert.equal(run.value, f.value); assert.equal(run.model, f.model);
  assert.equal(run.preparedSequences, undefined); assert.equal(run.modelAcquisitions, undefined);
  assert.equal(f.begin(), run); assert.equal(f.calls.filter(value => value === 'construct').length, 1);
  f.finishScope(); const finish = f.retire();
  assert.deepEqual(f.calls.slice(-3), ['retire', 'aliases', 'sever']); finish();
  assert.equal(run.prepared, undefined); assert.equal(run.closed, true);
  const g = hostFixture({failAfterAdopt: true});
  assert.throws(g.begin, error => error === g.primary);
  assert.equal(g.record.computeRuns.get(g.prepared).value, g.value);
  assert.throws(g.begin, error => error === g.primary);
});

test('Host Model retains the original alias receiver across a consumed preparation return failure', () => {
  const f = hostFixture(), run = f.begin(), primary = new Error('original consumed preparation return');
  f.finishScope(); f.failSever(primary);
  assert.throws(f.retire, cause => cause === primary);
  assert.equal(f.calls.filter(value => value === 'aliases').length, 1);
  assert.equal(run.model, undefined);
  const finish = f.retire(); finish();
  assert.equal(f.calls.filter(value => value === 'aliases').length, 1);
  assert.equal(run.closed, true);
});

test('Host Model failed construction retains its original Scope and partial module until the same Scope acknowledges cleanup', () => {
  const primary = new Error('original-model-completion'), f = hostFixture({refuse: primary});
  assert.throws(f.begin, error => error === primary); const run = f.record.computeRuns.get(f.prepared);
  assert(run.preparedSequences); assert.equal(run.modelAcquisitions, undefined);
  assert.equal(f.model.scope, f.scope); assert.throws(f.begin, error => error === primary);
  f.setFinish(false); assert.throws(f.retire, {code: 'InstalledMockModelCleanupPending'});
  assert.equal(f.record.computeRuns.get(f.prepared), run); assert(!f.calls.includes('aliases'));
  f.setFinish(true); f.retire();
  assert.equal(f.record.computeRuns.has(f.prepared), false); assert.equal(f.record.computeLiveRuns.size, 0);
  assert.equal(run.closed, true); assert(!f.calls.includes('retire')); assert(!f.calls.includes('sever'));
});

test('Host Model releases retained selection and early Plan before consumed parent return while keeping pending originals', () => {
  const f = hostFixture({retainedSelection: true}), run = f.begin();
  assert(f.selectionHeld());
  assert.throws(f.retire, {message: 'OriginalChildrenPending'});
  assert(f.selectionHeld());
  f.finishScope();
  const primary = new Error('original consumed parent return'); f.failSever(primary);
  assert.throws(f.retire, cause => cause === primary);
  assert.equal(f.selectionHeld(), false, 'Prepared is still held; its WeakMap values must be cut');
  assert.deepEqual(f.calls.slice(-3), ['aliases', 'selection-aliases', 'sever']);
  assert.equal(run.model, undefined);
  const finish = f.retire(); finish();
  assert.equal(f.calls.filter(value => value === 'selection-aliases').length, 1);
  const failure = new Error('original pre-adoption refusal'), partial = hostFixture({refuse: failure, retainedSelection: true});
  assert.throws(partial.begin, cause => cause === failure);
  partial.setFinish(false); assert.throws(partial.retire, {code: 'InstalledMockModelCleanupPending'});
  assert(partial.selectionHeld());
  partial.setFinish(true); partial.retire(); assert.equal(partial.selectionHeld(), false);
});

test('Host Model refuses missing original alias retirement before retaining a child or entering its constructor', () => {
  const f = hostFixture({missingSelectionRetirement: true});
  assert.throws(f.begin, {code: 'NodeManagedRunRuntimeUnavailable'});
  assert.equal(f.record.computeRuns, undefined);
  assert.deepEqual(f.calls, []);
});

test('Model fixed alias cut removes only the same Mock selection and early Plan and remains spent', () => {
  let declaration;
  const walk = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'FunctionDeclaration' && node.id.name === 'releaseRequestModelAliases') {
      assert.equal(declaration, undefined); declaration = node;
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk);
      else if (value && typeof value === 'object') walk(value);
    }
  };
  walk(parse(hostSource, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert(declaration);
  const inferSelections = new WeakMap(), earlyMockInferPlans = new WeakMap();
  const prepared = {}, other = {}, physical = {};
  for (const key of [prepared, other]) {
    inferSelections.set(key, {localMock: true, graph: {}, providerBinding: {}});
    earlyMockInferPlans.set(key, {plan: {compiled: {}, runDefinition: {}}});
  }
  inferSelections.set(physical, {localMock: false, provider: {}});
  const release = Function('inferSelections', 'earlyMockInferPlans',
    `return ${hostSource.slice(declaration.start, declaration.end)};`)(inferSelections, earlyMockInferPlans);
  release(prepared); release(prepared);
  assert.equal(inferSelections.has(prepared), false); assert.equal(earlyMockInferPlans.has(prepared), false);
  assert.equal(inferSelections.has(other), true); assert.equal(earlyMockInferPlans.has(other), true);
  release(physical); assert.equal(inferSelections.has(physical), true);
});

test('actual Model custody selector borrows original handler and dispatch tokens while Effect and Content stay unselected', () => {
  let selection;
  const walk = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && node.id?.name === 'localPreparationCustody') selection = node.init.arguments[0];
    for (const child of Object.values(node)) {
      if (Array.isArray(child)) child.forEach(walk);
      else if (child && typeof child === 'object') walk(child);
    }
  };
  walk(parse(hostSource, {ecmaVersion: 'latest', sourceType: 'module'})); assert(selection);
  const inventories = new WeakMap(), prepared = {}, holders = new Set(), handler = {};
  inventories.set(prepared, {kind: 'effect_free', infers: [{}], serializations: [], acquisitions: 2});
  holders.add(handler);
  const moon = {
    clientProgramSerializationOccurrences: p => inventories.get(p).serializations,
    clientProgramComposedInferOccurrences: p => ({$tag: 1, _0: inventories.get(p).infers}),
    clientProgramAcquisitionCount: p => inventories.get(p).acquisitions,
    clientProgramPreparationBorrowRead: token => {assert(holders.has(token)); return prepared;},
    clientProgramPreparationBorrowSibling(token) {
      assert.equal(token, handler); const child = {}; holders.add(child); return {$tag: 1, _0: child};
    },
    clientProgramPreparationBorrowReturn(token) {
      assert(holders.delete(token)); return {$tag: 1, _0: holders.size === 0};
    },
  };
  const selector = Function('preparation', 'prepareSubmit', 'moon', 'runtimeIsOk', 'runtimeField',
    `return (${hostSource.slice(selection.start, selection.end)});`)(
    {canRetireManagedPreparation: () => true, managesInstalledSources: () => true},
    {kindOf: p => inventories.get(p).kind}, moon, value => value.$tag === 1, (value, index) => value['_'+index]);
  for (const facts of [{kind: 'effectful', infers: [{}], serializations: [], acquisitions: 2},
    {kind: 'effect_free', infers: [{}], serializations: [{}], acquisitions: 0},
    {kind: 'effect_free', infers: [{}, {}], serializations: [], acquisitions: 2}]) {
    const foreign = {}; inventories.set(foreign, facts); assert.equal(selector(foreign), false);
  }
  let retired = 0;
  const registry = installLocalPreparationRegistry(selector, p => {
    assert.equal(p, prepared); retired++; return () => {if (holders.size) throw new Error('OriginalBorrowPending');};
  }, {runtime: moon, borrow: p => {assert.equal(p, prepared); return handler;}});
  const request = registry.capture({kind: 'program', input: {}, parameters: null});
  const handle = registry.adopt(prepared, request), submission = registry.attach(registry.copy(request), handle);
  const dispatch = registry.begin(submission); assert.equal(holders.size, 2);
  assert.throws(dispatch.retire, /OriginalBorrowPending/); assert.equal(holders.size, 1);
  assert.equal(submission.preparedProgram, prepared);
  registry.finishHandler(request); assert.equal(holders.size, 0);
  dispatch.retire(); assert.equal(retired, 1);
  assert.throws(() => submission.preparedProgram, /Retired/);
});

test('Model Source prepare forwards its original adopted Run and Request and rechecks current after the actual await', async () => {
  const push = outer.body.body.find(node => node.type === 'TryStatement').block.body
    .find(node => node.type === 'ForOfStatement').body.body
    .filter(node => node.type === 'ExpressionStatement')
    .find(node => node.expression?.callee?.object?.name === 'sources' && node.expression.callee.property.name === 'push');
  const object = push.expression.arguments[0].arguments[0];
  const method = object.properties.find(node => node.key?.name === 'prepare'); assert(method);
  for (const requestOwned of [true, false]) for (const expire of [true, false]) {
    const prepared = {}, result = {}, run = {requestOwned, value: {}, request: {}};
    const facts = {preparedProgram: prepared, occurrence: {stage: 1, input: 0, task: 1}};
    const primary = new Error('original-after-prepare-current'), preparedReads = new WeakMap();
    let resolve, forwarded, current = true;
    const adapter = {prepare(value) {forwarded = value; return new Promise(done => {resolve = done;});}};
    const holder = Function('adapter', 'sameRun', 'preparedReads', 'effectRuns', 'fail',
      `return ({${source.slice(method.start, method.end)}});`)(adapter,
      value => {assert.equal(value, prepared); if (!current) throw primary; return run;}, preparedReads, new WeakMap(),
      code => {throw Object.assign(new Error(code), {code});});
    const pending = holder.prepare(facts);
    if (requestOwned) {
      assert.notEqual(forwarded, facts); assert.equal(forwarded.managedRun, run.value);
      assert.equal(forwarded.requestIdentity, run.request); assert.equal(forwarded.occurrence, facts.occurrence);
      assert.equal(Object.hasOwn(facts, 'managedRun'), false);
    } else assert.equal(forwarded, facts);
    if (expire) current = false;
    resolve(result);
    if (expire) {
      await assert.rejects(pending, error => error === primary); assert.equal(preparedReads.has(result), false);
    } else {
      assert.equal(await pending, result); assert.equal(preparedReads.get(result), run);
    }
  }
});

test('Mock Effect reader consumes the same planned original and retires physical bytes separately', async () => {
  const properties = new Map();
  const walk = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && ['prepareSourceRead', 'readPages', 'closeSourceRead'].includes(node.key?.name)) {
      properties.set(node.key.name, node);
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk); else if (value && typeof value === 'object') walk(value);
    }
  };
  walk(outer); assert.equal(properties.size, 3);
  const prepared = {}, request = {}, parent = {}, nativeRead = {}, declaration = {}, raw = {},
    row = {}, acquisition = {}, charge = {}, bytes = Buffer.from('original document');
  const run = {preparationKind: 'effect-plan', prepared, request, value: parent};
  const originalReads = new WeakMap(), effectReads = new Set();
  let reads = 0, closes = 0, retires = 0, pending = true;
  raw.readOriginalBytes = () => {reads++; return bytes;};
  raw.close = () => {closes++; return {pending};};
  const moon = {clientProgramEffectAcquisitionCount: p => {assert.strictEqual(p, prepared); return 1;},
    clientProgramInstalledManagedRunSourceRead() {assert.fail('no second Source original');},
    clientProgramInstalledSourceReadRetire(value) {assert.strictEqual(value, nativeRead); retires++;},
    clientProgramMockChurnRiskAcceptChargedDocument(r, c, a, left, right, actualBytes, bound) {
      same([r, c, a, left, right, actualBytes, bound], [row, charge, acquisition, declaration, declaration, bytes, 2097152]);
    }};
  const sourceManaged = {assertCurrent() {}, prepareRead(p, d, original, occurrence) {
    same([p, d, original], [prepared, declaration, parent]); assert.equal(occurrence.stage, 0); return raw;
  }};
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const closeFunctions = outer.body.body.filter(node => node.type === 'FunctionDeclaration' &&
    ['closeRead', 'closePhysicalRead', 'releaseEffectSourceAliases'].includes(node.id.name)).map(node => source.slice(node.start, node.end)).join('\n');
  const same = (actual, expected) => actual.forEach((value, i) => assert.strictEqual(value, expected[i]));
  const ports = {moon, sourceManaged, originalReads, effectReads, effectRuns: new WeakMap([[prepared, new WeakRef(run)]]), declaration, index: 0,
    bundle: {sources: [{declaration}, {declaration}]}, checked: value => value, fail,
    sameRun(p) {assert.strictEqual(p, prepared); return run;}};
  const code = [...properties.values()].map(node => source.slice(node.start, node.end)).join(',');
  const api = Function(...Object.keys(ports), closeFunctions + ';return {callbacks:{' + code + '},closeRead};')(...Object.values(ports));
  assert.strictEqual(api.callbacks.prepareSourceRead({checkedOwner: prepared, effectful: true, declaration,
    occurrence: {stage: 0, input: 0}, managedRun: parent, originalRead: nativeRead}), nativeRead);
  assert.equal(effectReads.size, 1);
  await api.callbacks.readPages({rowRun: {originalRead: nativeRead, run: row, acquisition},
    chargePage: value => {assert.strictEqual(value, bytes); return charge;}, verifyRead: async () => {}});
  await assert.rejects(api.callbacks.closeSourceRead(nativeRead), {code: 'InstalledMockSourceCleanupPending'});
  assert.equal(retires, 0); assert.equal(reads, 1); assert.equal(run.mockSourceReads[0].closed, false);
  pending = false; assert.equal((await api.callbacks.closeSourceRead(nativeRead)).pending, false);
  assert.equal(retires, 0); await api.closeRead(run.mockSourceReads[0]);
  assert.equal(retires, 1); assert.equal(reads, 1); assert.equal(closes, 2);
  assert.equal(run.mockSourceReads[0].raw, undefined); assert.equal(run.mockSourceReads[0].observedBytes, undefined);
});

const graphMethodStart = managerSource.indexOf('    prepareModelGraph(');
const graphMethodEnd = managerSource.indexOf('    prepareModelCompilation(', graphMethodStart);
assert(graphMethodStart >= 0 && graphMethodEnd > graphMethodStart);
function requestGraphFixture({serialized = true, missingPort = false, replaceAfter = false, refuse} = {}) {
  const prepared = {}, request = {}, parent = {}, input = {}, holder = {}, occurrence = {}, execution = {};
  const component = serialized ? {} : undefined, graph = {}, admission = {}, calls = [];
  const state = {prepared, parent, holder, contentGraph: component, compilationFamily: 'model'};
  const producer = {preparation: state, receipt: input};
  let object;
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const moon = {
    clientProgramPreparationBorrowRead(value) {assert.equal(value, holder); return prepared;},
    clientProgramRequestProgramModuleIssueCode() {assert.fail('No issue reclassification on success');},
    clientProgramPrepareRequestModelGraph(...args) {
      assert.equal(this, moon); assert.equal(serialized, false);
      assert.deepEqual(args, [parent, input, occurrence, execution, admission]);
      calls.push('original Model'); return {value: graph};
    },
    clientProgramPrepareRequestSerializedModelGraph(...args) {
      assert.equal(this, moon); assert.equal(serialized, true);
      assert.deepEqual(args, [parent, input, occurrence, component, execution, admission]);
      assert.equal(state.preparing, true);
      assert.throws(() => object.prepareModelGraph(prepared, request, occurrence, execution, component),
        {code: 'ForeignInstalledSourceProducer'});
      calls.push('same Request Content Model');
      if (refuse) throw refuse;
      return {value: graph};
    },
  };
  if (missingPort) delete moon.clientProgramPrepareRequestSerializedModelGraph;
  state.context = {runtime: moon};
  const originals = {installation: {sequenceContractOriginal: {moon, admission}}};
  object = Function('current', 'producerForRequest', 'fail', 'originals', 'checkedRequestProgramPreparation',
    `const pendingRunRegistrations=new Set();${managerHelpers}return ({${managerSource.slice(graphMethodStart, graphMethodEnd).trim().replace(/,$/u, '')}});`)(
    () => {if (replaceAfter && state.modelGraph !== undefined) state.contentGraph = {};},
    value => {assert.equal(value, request); return producer;}, fail, originals,
    (actual, result, issue) => {assert.equal(actual, moon); assert.equal(issue, moon.clientProgramRequestProgramModuleIssueCode); return result.value;});
  const constructSerialized = missingPort ? undefined : (...args) =>
    Reflect.apply(moon.clientProgramPrepareRequestSerializedModelGraph, moon, args);
  return {state, calls, graph, invoke: () => object.prepareModelGraph(prepared, request, occurrence, execution, component, constructSerialized),
    foreign: () => object.prepareModelGraph(prepared, request, occurrence, execution, {}, constructSerialized)};
}

test('Request Model Graph forwards the same retained Content original to one typed parent constructor', () => {
  const original = requestGraphFixture();
  assert.equal(original.invoke(), original.graph);
  assert.equal(original.state.modelGraph, original.graph);
  assert.deepEqual(original.calls, ['same Request Content Model']);
  assert.equal(original.state.preparing, false);
  const plain = requestGraphFixture({serialized: false});
  assert.equal(plain.invoke(), plain.graph);
  assert.deepEqual(plain.calls, ['original Model']);
  const missing = requestGraphFixture({missingPort: true});
  assert.throws(missing.invoke, {code: 'NodeManagedRunRuntimeUnavailable'});
  assert.deepEqual(missing.calls, []);
  const foreign = requestGraphFixture();
  assert.throws(foreign.foreign, {code: 'ForeignInstalledSourceProducer'});
  assert.deepEqual(foreign.calls, []);
});

test('Request Model Graph keeps constructor failure or changed Content on the same Request cleanup', () => {
  const primary = new Error('original serialized Model constructor');
  const refused = requestGraphFixture({refuse: primary});
  assert.throws(refused.invoke, cause => cause === primary);
  assert.throws(refused.invoke, cause => cause === primary);
  assert.deepEqual(refused.calls, ['same Request Content Model']);
  const changed = requestGraphFixture({replaceAfter: true});
  assert.throws(changed.invoke, {code: 'ForeignInstalledSourceProducer'});
  assert.equal(changed.state.modelGraph, changed.graph, 'Keep returned constructor original for same Request abort');
  assert.equal(changed.state.preparationFailed, true);
  const retained = changed.state.preparationFailure;
  assert.throws(changed.invoke, cause => cause === retained);
  assert.deepEqual(changed.calls, ['same Request Content Model']);
});


function installedModelRequestFixture({serialized = false, refusePlan, refuseScope, acquisitions = 0} = {}) {
  let constructor;
  const walk = n => {
    if (!n || typeof n !== 'object') return;
    if (n.type === 'FunctionDeclaration' && n.id.name === 'prepareInstalledRequestModelRun') constructor = n;
    for (const v of Object.values(n)) {if (Array.isArray(v)) v.forEach(walk); else if (v && typeof v === 'object') walk(v);}
  };
  walk(parse(hostSource, {ecmaVersion: 'latest', sourceType: 'module'})); assert(constructor);
  const prepared = {}, request = {}, graph = {}, compilation = {}, definition = {}, scope = {}, queryTime = {}, calls = [];
  const selected = {graph, occurrence: {}, originalReadInstallation: {}, serializationGraph: serialized ? {} : undefined};
  const plan = {compiled: compilation, runDefinition: definition, inferGraph: graph,
    serializationGraph: selected.serializationGraph, queryTimePreparation: queryTime};
  const inferSelections = new WeakMap([[prepared, selected]]), earlyMockInferPlans = new WeakMap();
  const control = {}, moon = {clientProgramAcquisitionCount: () => acquisitions};
  let invoke, managed, saved = false;
  const clientOperationError = code => Object.assign(new Error(code), {code});
  const preparation = {admitResultPublicationRun(p) {assert.equal(p, prepared); calls.push('publication');},
    prepareManagedModelRun(runtime, p, r, model) {
    assert.deepEqual([runtime, p, r], [moon, prepared, request]);
    assert.equal(earlyMockInferPlans.get(prepared).model, model);
    assert.equal(model.compiled, compilation); assert.equal(model.runDefinition, definition);
    assert.equal(model.originalReadInstallation, selected.originalReadInstallation);
    assert.equal(model.queryTimePreparation, queryTime);
    if (managed !== undefined) {assert.equal(managed.model, model); calls.push('same adopted Run'); return managed;}
    assert.equal(Object.getOwnPropertyDescriptor(model, 'scope').writable, true);
    assert.equal(model.scope, undefined); calls.push('construct');
    managed = {model, value: {}}; model.scope = scope;
    if (refuseScope !== undefined) throw refuseScope;
    return managed;
  }};
  const runContent = {prepareModelRun({preparedProgram, plan: actual, request: original, model}) {
    assert.deepEqual([preparedProgram, actual, original], [prepared, plan, request]); calls.push('same prefix');
    model.contentPreparation = {managed: preparation.prepareManagedModelRun(moon, prepared, request, model)};
  }};
  const ports = {moon, control, preparation, inferSelections, earlyMockInferPlans, runContent, clientOperationError,
    planFor(submission, wire, original, keyed, early) {
      assert.equal(earlyMockInferPlans.get(prepared), early); assert.equal(early.model.prepared, prepared);
      assert.equal(early.selecting, true); assert.equal(early.plan, undefined);
      assert.deepEqual([submission.preparedProgram, wire, original, keyed], [prepared, undefined, request, undefined]);
      assert.throws(invoke, {code: 'InstalledModelPlanSelectionPending'}); calls.push('compile/Definition');
      if (refusePlan !== undefined) throw refusePlan; return plan;
    }};
  const construct = Function(...Object.keys(ports), 'return ' + hostSource.slice(constructor.start, constructor.end))(...Object.values(ports));
  const submission = {preparedProgram: prepared, requestId: 'original-request'};
  invoke = () => construct(submission, request, selected);
  let admission;
  const findAdmission = n => {
    if (!n || typeof n !== 'object') return;
    if (n.type === 'FunctionExpression' && n.params.length === 1 && n.params[0].name === 'submission' &&
        hostSource.slice(n.start, n.end).includes('prepareInstalledRequestModelRun')) {assert(!admission); admission = n;}
    for (const v of Object.values(n)) {if (Array.isArray(v)) v.forEach(findAdmission); else if (v && typeof v === 'object') findAdmission(v);}
  };
  findAdmission(parse(hostSource, {ecmaVersion: 'latest', sourceType: 'module'})); assert(admission);
  const failures = new WeakMap(), admissionPorts = {...ports,
    requestOf: () => ({requested: request, acquisitionCount: acquisitions, effectful: false}),
    journal: {resolveDefinition: () => saved ? {physicalStartReserved: true} : undefined}, namespaceId: 'fixture',
    prepareInstalledRequestModelRun: construct, admissionFailures: failures};
  const admit = Function(...Object.keys(admissionPorts), 'return (' + hostSource.slice(admission.start, admission.end) + ');')(...Object.values(admissionPorts));
  return {invoke, admit: () => admit(submission), saved: () => {saved = true;}, failures, submission,
    calls, scope, prepared, selected, plan, request, early: () => earlyMockInferPlans.get(prepared),
    foreignRequest: () => construct(submission, {}, selected),
    get managed() {return managed;}};
}

test('installed Model caller retains the same Request carrier before one compiler and Scope constructor', () => {
  for (const serialized of [false, true]) {
    const f = installedModelRequestFixture({serialized}); const model = f.invoke();
    assert.equal(f.early().model, model); assert.equal(model.scope, f.scope);
    assert.equal(f.early().managed, f.managed); assert.equal(f.invoke(), model);
    assert.equal(f.calls.filter(v => v === 'compile/Definition').length, 1);
    assert.equal(f.calls.filter(v => v === 'construct').length, 1);
    assert.equal(f.calls.filter(v => v === 'same prefix').length, serialized ? 1 : 0);
    assert.throws(f.foreignRequest, {code: 'ForeignInstalledModelPreparation'});
  }
});

test('installed Model caller retains original compiler or partial Scope failures without reissuing', () => {
  for (const phase of ['refusePlan', 'refuseScope']) {
    const primary = new Error('original installed Model ' + phase), f = installedModelRequestFixture({[phase]: primary});
    assert.throws(f.invoke, cause => cause === primary); assert.throws(f.invoke, cause => cause === primary);
    const early = f.early(); assert.equal(early.failure, primary); assert.equal(early.selecting, false);
    assert.equal(f.calls.filter(v => v === 'compile/Definition').length, 1);
    assert.equal(early.model.scope, phase === 'refuseScope' ? f.scope : undefined);
    if (phase === 'refuseScope') assert.throws(() => Reflect.apply(early.model.releaseAliases, early.model, []),
      {code: 'InstalledModelCleanupPending'});
  }
});

test('installed Model caller cuts its same managed aliases only after original read and Scope cleanup', () => {
  const f = installedModelRequestFixture({serialized: true}), model = f.invoke(), release = model.releaseAliases;
  assert.throws(() => Reflect.apply(release, {}, []), {code: 'ForeignInstalledModelPreparation'});
  assert.throws(() => Reflect.apply(release, model, []), {code: 'InstalledModelCleanupPending'});
  model.scopeFinished = true; model.read = {};
  assert.throws(() => Reflect.apply(release, model, []), {code: 'InstalledModelCleanupPending'});
  model.read = undefined; f.early().failure = {retainedOriginal: f.plan};
  Reflect.apply(release, model, []);
  assert.equal(f.early().failure, undefined); assert.equal(f.early().requestId, undefined);
  assert.equal(model.compiled, undefined); assert.equal(model.originalReadInstallation, undefined);
  assert.equal(f.early().plan, undefined); assert.equal(f.early().managed, undefined);
  assert.equal(f.early().requested, undefined); assert.equal(f.early().prepared, undefined); assert.equal(model.closed, true);
  Reflect.apply(release, model, []); assert.equal(f.early().aliasesReleased, true);
});


test('actual installed admission routes sourcefree Model and Content through the same original constructor before submission', () => {
  for (const serialized of [false, true]) {
    const f = installedModelRequestFixture({serialized});
    f.admit(); assert.equal(f.early().model.scope, f.scope); assert.equal(f.early().managed, f.managed);
    f.admit(); assert.equal(f.calls.filter(v => v === 'compile/Definition').length, 1);
    assert.equal(f.calls.filter(v => v === 'construct').length, 1);
    assert.equal(f.calls.filter(v => v === 'same prefix').length, serialized ? 1 : 0);
    assert.equal(f.failures.has(f.submission), false);
  }
});

test('actual installed admission observes saved physical work and preserves fresh partial failure without replacement Scope', () => {
  const saved = installedModelRequestFixture({serialized: true}); saved.saved(); saved.admit();
  assert.equal(saved.early(), undefined); assert.deepEqual(saved.calls, ['publication']);
  const primary = new Error('original fresh Model Scope completion'), failed = installedModelRequestFixture({refuseScope: primary});
  assert.throws(failed.admit, cause => cause === primary); assert.throws(failed.admit, cause => cause === primary);
  assert.equal(failed.failures.get(failed.submission).error, primary);
  assert.equal(failed.failures.get(failed.submission).requested, failed.request);
  assert.equal(failed.early().model.scope, failed.scope);
  assert.equal(failed.calls.filter(v => v === 'construct').length, 1);
});


test('Host Request Node Model retires an adopted unused Scope once before native Run and consumed borrow cleanup', () => {
  const f = hostFixture({nodeModel: true}), run = f.begin();
  f.setFinish(false); assert.throws(f.retire, {code: 'InstalledModelCleanupPending'});
  assert.equal(run.model, f.model); assert.equal(f.model.scope, f.scope);
  assert(!f.calls.includes('retire')); assert(!f.calls.includes('aliases'));
  f.setFinish(true); const primary = new Error('same consumed Request borrower'); f.failSever(primary);
  assert.throws(f.retire, cause => cause === primary); assert.equal(f.model.scopeFinished, true);
  assert.equal(run.model, undefined); assert.equal(f.calls.filter(v => v === 'scope').length, 2);
  const finish = f.retire(); finish();
  assert.equal(f.calls.filter(v => v === 'scope').length, 2);
  assert.equal(f.calls.filter(v => v === 'aliases').length, 1); assert.equal(run.closed, true);
});

test('Host Request Node Model Scope cleanup refuses same-record reentry and foreign post-callback carrier', () => {
  let f;
  f = hostFixture({nodeModel: true, onScopeFinish() {
    assert.throws(f.retire, {code: 'InstalledModelCleanupPending'});
  }});
  f.begin(); const finish = f.retire(); finish();
  assert.equal(f.calls.filter(v => v === 'scope').length, 1);
  let foreign;
  foreign = hostFixture({nodeModel: true, onScopeFinish() {
    foreign.record.computeRuns.get(foreign.prepared).model = {};
  }});
  const run = foreign.begin();
  assert.throws(foreign.retire, {code: 'ForeignInstalledModelPreparation'});
  assert.equal(foreign.model.scopeFinished, true); assert.equal(run.closed, false);
  assert(!foreign.calls.includes('retire')); assert(!foreign.calls.includes('aliases'));
});

test('Host unadopted Model Scope cleanup fences original carriers before alias or bag retirement', () => {
  for (const mutate of [
    f => {f.record.computeRuns.get(f.prepared).model = {};},
    f => {f.record.computeRuns.set(f.prepared, {});},
    f => {f.record.computeLiveRuns.delete(f.record.computeRuns.get(f.prepared));},
    f => {f.record.computeRuns.get(f.prepared).value = {};},
    f => {f.record.computeRuns.get(f.prepared).request = {};},
    f => {f.record.computeRuns.get(f.prepared).original = {};},
    f => {f.record.computeRuns.get(f.prepared).runtime = {};},
    f => {f.record.computeRuns.get(f.prepared).closed = true;},
    f => {f.record.computeRuns.get(f.prepared).releaseModelAliases = () => assert.fail('Foreign aliases');},
    f => {f.model.scope = {};},
  ]) {
    let f;
    const original = new Error('same failed original Model completion');
    f = hostFixture({refuse: original, retainedSelection: true, onScopeFinish() {
      assert.throws(f.retire, {code: 'InstalledModelCleanupPending'});
      mutate(f);
    }});
    assert.throws(f.begin, cause => cause === original);
    const run = f.record.computeRuns.get(f.prepared);
    assert.throws(f.retire, {code: 'ForeignInstalledModelPreparation'});
    assert.equal(f.calls.includes('aliases'), false);
    assert.equal(f.calls.includes('selection-aliases'), false);
    assert.equal(f.calls.includes('retire'), false);
    assert.equal(f.calls.includes('sever'), false);
    assert.equal(f.selectionHeld(), true);
    assert.equal(run.prepared, f.prepared);
    assert.equal(f.calls.filter(value => value === 'scope').length, 1);
  }
});

test('Host unadopted Model Scope cleanup keeps original thrown causes and pending Scope custody', () => {
  for (const primary of [new Error('original Scope finish'), null, undefined]) {
    const original = new Error('same failed Model constructor');
    const f = hostFixture({refuse: original, retainedSelection: true,
      onScopeFinish() {throw primary;}});
    assert.throws(f.begin, cause => cause === original);
    const run = f.record.computeRuns.get(f.prepared);
    let thrown = false, cause;
    try {f.retire();} catch (error) {thrown = true; cause = error;}
    assert.equal(thrown, true); assert.equal(cause, primary);
    assert.equal(f.record.computeRuns.get(f.prepared), run);
    assert.equal(run.model, f.model); assert.equal(f.model.scope, f.scope);
    assert.notEqual(f.model.scopeFinished, true);
    assert.equal(f.selectionHeld(), true); assert.equal(f.calls.includes('aliases'), false);
  }
});


test('actual acquired Model admission retains one Request compiler prefix and Scope and refuses a missing original read installation', () => {
  const f = installedModelRequestFixture({serialized: true, acquisitions: 1});
  f.admit(); f.admit();
  assert.equal(f.early().model.scope, f.scope); assert.equal(f.early().managed, f.managed);
  assert.equal(f.calls.filter(v => v === 'compile/Definition').length, 1);
  assert.equal(f.calls.filter(v => v === 'construct').length, 1);
  assert.equal(f.calls.filter(v => v === 'same prefix').length, 1);
  const plain = installedModelRequestFixture({acquisitions: 1});
  // Plain acquired Models are supported by the current constructor. An
  // actually missing physical original, rather than this fixture's inert
  // placeholder object, is the existing refusal boundary.
  plain.selected.originalReadInstallation = undefined;
  assert.throws(plain.invoke, {code: 'HostResultPublicationPurposeUnavailable'});
  assert.equal(plain.early(), undefined);
});

// Exercise the actual facade -> Host -> manager path. A facade carries no
// native owner; only the existing runtime-core WeakMap can supply that original.
const graphCoreSource = readFileSync(new URL('../host-common/runtime-core.mjs', import.meta.url), 'utf8');
const acquiredGraphStart = graphCoreSource.indexOf('  const prepareAcquiredSerializationGraph =');
const acquiredGraphEnd = graphCoreSource.indexOf('  const snapshotTokens =', acquiredGraphStart);
const graphCoreProperties = new Map();
function findGraphCoreMethods(node) {
  if (!node || typeof node !== 'object') return;
  if (node.type === 'Property' && node.method && ['prepareCheckedClientRequestAcquiredSerializationGraph',
    'prepareClientRequestSerializedInferGraph'].includes(node.key.name)) graphCoreProperties.set(node.key.name, node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(findGraphCoreMethods);
    else if (value && typeof value === 'object') findGraphCoreMethods(value);
  }
}
findGraphCoreMethods(parse(graphCoreSource, {ecmaVersion: 'latest', sourceType: 'module'}));
const requestGraphHostStart = hostSource.indexOf('    prepareManagedModelGraph(runtime,');
const requestGraphHostEnd = hostSource.indexOf('    prepareManagedModelCompilation(', requestGraphHostStart);
function originalFacadeGraphFixture() {
  const prepared = {}, request = {}, parent = {}, input = {}, holder = {}, occurrence = {}, execution = {};
  const rawContent = {owner: prepared}, modelGraph = {}, admission = {}, calls = [];
  let host;
  const moon = {
    clientProgramPreparationBorrowRead(value) {assert.strictEqual(value, holder); return prepared;},
    clientProgramRequestProgramModuleIssueCode() {assert.fail('No successful issue classification');},
    clientProgramPrepareRequestAcquiredSerializationGraph(...args) {
      assert.deepEqual(args, [parent, input, 0, 2, 1, 128, false, admission]);
      return {value: rawContent};
    },
    clientProgramSerializationPlanGraphWire(value) {assert.strictEqual(value, rawContent); return '{}';},
    clientProgramPrepareRequestSerializedModelGraph(...args) {
      assert.strictEqual(this, moon);
      assert.strictEqual(args[3], rawContent, 'Pass the SAME native Content Graph, never its public facade');
      assert.deepEqual(args, [parent, input, occurrence, rawContent, execution, admission]);
      calls.push('same native Content');
      assert.throws(() => host.prepareManagedModelGraph(moon, prepared, occurrence, execution, selected),
        {code: 'ForeignInstalledSourceProducer'});
      return {value: modelGraph};
    },
  };
  const properties = [...graphCoreProperties.values()].map(node => graphCoreSource.slice(node.start, node.end));
  const control = Function('moon', 'compiledRunResult',
    'const serializationPlanTokens=new WeakMap();' + graphCoreSource.slice(acquiredGraphStart, acquiredGraphEnd) +
    'return {' + properties.join(',') + '};')(moon, result => result.value);
  const selected = control.prepareCheckedClientRequestAcquiredSerializationGraph(parent, input,
    admission, prepared, {task: 0, step: 2, maxRows: 1, maxBytes: 128}, true);
  assert.notStrictEqual(selected, rawContent);
  assert.deepEqual(selected, {task: 0, step: 2, wire: '{}'});
  const state = {prepared, parent, holder, contentGraph: selected, compilationFamily: 'model', context: {runtime: moon}};
  const producer = {preparation: state, receipt: input};
  const originals = {installation: {sequenceContractOriginal: {moon, admission}}};
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const manager = Function('current', 'producerForRequest', 'fail', 'originals', 'checkedRequestProgramPreparation',
    `const pendingRunRegistrations=new Set();${managerHelpers}return ({${managerSource.slice(graphMethodStart, graphMethodEnd).trim().replace(/,$/u, '')}});`)(
    () => {}, value => {assert.strictEqual(value, request); return producer;}, fail, originals,
    (runtime, result) => {assert.strictEqual(runtime, moon); return result.value;});
  host = Function('moon', 'sourceManaged', 'computeManaged', 'originals', 'clientOperationError',
    'assertSourceManagedInstallationCurrent', 'assertManagedComputeInstallationCurrent',
    'originalSourceManagedHostRequest', 'runtimeCore',
    'return ({' + hostSource.slice(requestGraphHostStart, requestGraphHostEnd).trim().replace(/,$/u, '') + '});')(
    moon, manager, undefined, originals, code => Object.assign(new Error(code), {code}),
    () => {}, () => {}, () => request, runtime => {
      assert.strictEqual(runtime, moon); return {publicationControl: control};
    });
  return {invoke: () => host.prepareManagedModelGraph(moon, prepared, occurrence, execution, selected),
    calls, state, modelGraph, control, parent, input, occurrence, selected, execution, admission};
}

test('Request serialized Model preserves native Graph across actual facade Host and manager', () => {
  const f = originalFacadeGraphFixture();
  assert.strictEqual(f.invoke(), f.modelGraph);
  assert.strictEqual(f.state.modelGraph, f.modelGraph);
  assert.deepEqual(f.calls, ['same native Content']);
  assert.throws(() => f.control.prepareClientRequestSerializedInferGraph(f.parent, f.input,
    f.occurrence, {...f.selected}, f.execution, f.admission), /Foreign Content compilation graph/u);
  assert.deepEqual(f.calls, ['same native Content'], 'A copied facade never enters the Core constructor');
});
