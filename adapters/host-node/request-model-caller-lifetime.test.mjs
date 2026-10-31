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
    `return ({${managerSource.slice(methodStart, methodEnd).trim().replace(/,$/u, '')}});`)(
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
function hostFixture({refuse, failAfterAdopt = false} = {}) {
  const prepared = {}, request = {}, sdkRequest = {}, original = {}, value = {}, parent = {}, input = {}, compilation = {};
  const scope = {}, calls = [], model = {compiled: {}, runDefinition: {}, graph: {}, scope: undefined};
  const record = {mockSourceProfile: {}}, originalInstallation = {}, originals = {};
  const primary = new Error('original-check-after-adopt');
  let finish = true, physicalDone = false, payloadSevered = false, severFailure;
  const control = {
    finishCheckedClientInferOriginalReadScope(c, d, g, s, complete) {
      assert.deepEqual([c, d, g, s, complete], [model.compiled, model.runDefinition, model.graph, scope, true]);
      calls.push('scope'); return finish;
    },
  };
  model.control = control;
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
    run.preparedSequences = {}; run.modelPlan = {}; run.modelAcquisitions = [{}];
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
    failSever: failure => {severFailure = failure;}};
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
  assert(run.preparedSequences); assert(run.modelAcquisitions);
  assert.equal(f.model.scope, f.scope); assert.throws(f.begin, error => error === primary);
  f.setFinish(false); assert.throws(f.retire, {code: 'InstalledMockModelCleanupPending'});
  assert.equal(f.record.computeRuns.get(f.prepared), run); assert(!f.calls.includes('aliases'));
  f.setFinish(true); f.retire();
  assert.equal(f.record.computeRuns.has(f.prepared), false); assert.equal(f.record.computeLiveRuns.size, 0);
  assert.equal(run.closed, true); assert(!f.calls.includes('retire')); assert(!f.calls.includes('sever'));
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
    const holder = Function('adapter', 'sameRun', 'preparedReads', 'fail',
      `return ({${source.slice(method.start, method.end)}});`)(adapter,
      value => {assert.equal(value, prepared); if (!current) throw primary; return run;}, preparedReads,
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
    ['closeRead', 'closePhysicalRead'].includes(node.id.name)).map(node => source.slice(node.start, node.end)).join('\n');
  const same = (actual, expected) => actual.forEach((value, i) => assert.strictEqual(value, expected[i]));
  const ports = {moon, sourceManaged, originalReads, effectReads, declaration, index: 0,
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
