import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Run the original Local caller and cleanup with explicit Host/Core ports.
// These observations are not a Common issuer, backing proof or physical ACK.
const source = readFileSync(new URL('../local-node/installed-project-mock.mjs', import.meta.url), 'utf8');
const outer = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .find(node => node.declaration?.id?.name === 'installPreparedProjectMockSources').declaration;
const names = ['sameRun', 'prepareManagedMockModelRun', 'modelPreparation', 'retireModelRead',
  'retireRunRecord', 'closeRead', 'closeSource', 'close'];
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
    'inferOriginalReadCleanupComplete', 'prepareRequestModel',
    `let closing=false;${slices};return {prepareManagedMockModelRun,modelPreparation,close};`)(
    current, records, fail, value => value, moon, sources, closedSources, () => false, prepareRequestModel);
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
  let finish = true, physicalDone = false, payloadSevered = false;
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
    },
  };
  const construct = (o, run, actual, c, p, i) => {
    assert.deepEqual([o, actual, c, p, i], [originals, model, compilation, parent, input]);
    assert.equal(record.computeRuns.get(prepared), run); calls.push('construct');
    run.preparedSequences = {}; run.modelPlan = {}; run.modelAcquisitions = [{}];
    return run.modelPlan;
  };
  const ports = {sourceManaged: manager, moon, record, originalInstallation, originals,
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
    finishScope: () => {model.scopeFinished = true;}, setFinish: value => {finish = value;}};
}

test('Host Model adoption uses its existing run bag and retains transient originals until actual adoption succeeds', () => {
  const f = hostFixture(); const run = f.begin();
  assert.equal(run.original, f.original); assert.equal(run.value, f.value); assert.equal(run.model, f.model);
  assert.equal(run.preparedSequences, undefined); assert.equal(run.modelAcquisitions, undefined);
  assert.equal(f.begin(), run); assert.equal(f.calls.filter(value => value === 'construct').length, 1);
  f.finishScope(); const finish = f.retire();
  assert.deepEqual(f.calls.slice(-3), ['retire', 'sever', 'aliases']); finish();
  assert.equal(run.prepared, undefined); assert.equal(run.closed, true);
  const g = hostFixture({failAfterAdopt: true});
  assert.throws(g.begin, error => error === g.primary);
  assert.equal(g.record.computeRuns.get(g.prepared).value, g.value);
  assert.throws(g.begin, error => error === g.primary);
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
