import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';

// Execute the exact installed Host/custody bodies. Core/Journal/physical
// observations below are explicit original ports, not normal installation,
// new Common funding or a physical child ACK inferred from a Promise.
const source = name => readFileSync(new URL(name, import.meta.url), 'utf8');
function nodes(ast, select) {
  const found = [];
  const visit = value => {
    if (!value || typeof value !== 'object') return;
    if (typeof value.type === 'string' && select(value)) found.push(value);
    for (const child of Object.values(value)) {
      if (Array.isArray(child)) child.forEach(visit);
      else if (child && typeof child === 'object') visit(child);
    }
  };
  visit(ast); return found;
}
const embedded = source('./embedded-local.mjs');
const embeddedAst = parse(embedded, {ecmaVersion:'latest', sourceType:'module'});
const method = (text, ast, name) => {
  const selected = nodes(ast, node => node.type === 'Property' && node.method && node.key.name === name);
  assert.equal(selected.length, 1, name); return text.slice(selected[0].start, selected[0].end);
};
const declaration = (text, name) => {
  const selected = nodes(parse(text, {ecmaVersion:'latest', sourceType:'module'}),
    node => node.type === 'FunctionDeclaration' && node.id?.name === name);
  assert.equal(selected.length, 1, name); return text.slice(selected[0].start, selected[0].end);
};
const construct = (body, ports) => compileFunction(body, Object.keys(ports))(...Object.values(ports));
const error = code => Object.assign(new Error(code), {code});
const cid = value => 'sha256:' + value.repeat(64);

function rootPreparationFixture(managed) {
  let closing = false, retired = false;
  const runtime = {}, request = {}, definition = {identity:cid('1')}, originals = {};
  const liveRuns = new Set(managed === undefined ? [] : [managed]);
  const record = {computeLiveRuns:liveRuns, computeRuns:new WeakMap()};
  if (managed) {managed.runtime = runtime; record.computeRuns.set(managed.prepared, managed);}
  let originalCurrent = 0, constructed = 0, retained, factoryOptions;
  const view = {};
  runtime.clientRequestRelation = (actual, original) => actual === request && original === managed?.request ? 1 : 2;
  runtime.strategyPublicationContractIdentity = original => {
    assert.equal(original, managed.definitionOriginal.definition); return definition.identity;
  };
  const preparation = {effectManagedPlanRun(actual, prepared, original) {
    assert.equal(actual, runtime); assert.equal(prepared, managed.prepared); assert.equal(original, managed.request);
    return managed;
  }};
  const control = {};
  const ports = {moon:runtime, record, originals, preparation,
    assertInitialControlHostPreparation: actual => {assert.equal(actual, originals); if (closing || retired) throw error('InstalledHostPreparationChanged');},
    assertRetainedSourceManagedHost: actual => {assert.equal(actual, originals); if (retired) throw error('InstalledHostPreparationChanged');},
    clientOperationError:error, runtimeCore: actual => {assert.equal(actual, runtime); return {publicationControl:control};},
    prepareEffectCaptureResources(options) {
      factoryOptions = options; assert.equal(options.request, request); assert.equal(options.runDefinition, definition);
      assert.equal(options.managed, managed); assert.equal(options.control, control);
      options.retain(view); assert.equal(retained, view); // Before fallible constructor.
      options.assertCurrent(); constructed++; return view;
    }};
  ports.retireEffectCaptureResourceFrame = construct(
    `${declaration(embedded, 'retireEffectCaptureResourceFrame')}; return retireEffectCaptureResourceFrame;`,
    {clientOperationError:error});
  ports.prepareEffectCaptureFrame = construct(`${declaration(embedded, 'prepareEffectCaptureFrame')}; return prepareEffectCaptureFrame;`, ports);
  const prepare = construct(`return ({${method(embedded, embeddedAst, 'prepareEffectCaptureRecovery')}}).prepareEffectCaptureRecovery`, ports);
  const retire = construct(`return ({${method(embedded, embeddedAst, 'prepareEffectCaptureRetirement')}}).prepareEffectCaptureRetirement`, ports);
  return {runtime, request, definition, originals, record, view, liveRuns,
    open(actual = request) {return prepare(runtime, actual, definition, {}, managed,
      () => {originalCurrent++;}, original => {retained = original;});},
    seal() {closing = true;}, retireHost() {retired = true;},
    retire() {return retire(runtime, request, definition, {}, () => {originalCurrent++;}, original => {retained = original;});},
    get constructed() {return constructed;}, get options() {return factoryOptions;},
    get currents() {return originalCurrent;}};
}

test('actual Host retains capture frame in SAME live inventory before constructor and retires exact frame once', () => {
  const f = rootPreparationFixture(); assert.equal(f.open(), f.view);
  assert.equal(f.constructed, 1); assert.equal(f.currents, 1); assert.equal(f.liveRuns.size, 1);
  const entry = [...f.liveRuns][0]; assert.equal(entry.resources, f.view); assert.equal(entry.selecting, false);
  assert.throws(() => f.options.retired({}), {code:'ForeignEffectCaptureResources'});
  assert.equal(f.liveRuns.size, 1);
  f.options.retired(f.view); assert.equal(f.liveRuns.size, 0); assert.equal(entry.resources, undefined);
  assert.throws(() => f.options.retired(f.view), {code:'ForeignEffectCaptureResources'});
});

test('terminal capture cleanup retains same closing Host while new recovery stays fenced', () => {
  const f = rootPreparationFixture(); f.seal();
  assert.throws(() => f.open(), {code:'InstalledHostPreparationChanged'});
  assert.equal(f.constructed, 0);
  assert.equal(f.retire(), f.view); assert.equal(f.constructed, 1);
  f.options.assertCurrent();
  const entry = [...f.liveRuns][0];
  entry.closed = true;
  assert.throws(() => f.options.assertCurrent(), {code:'ForeignEffectCaptureResources'});
  entry.closed = false; f.retireHost();
  assert.throws(() => f.options.assertCurrent(), {code:'InstalledHostPreparationChanged'});
  assert.throws(() => f.retire(), {code:'InstalledHostPreparationChanged'});
});

test('actual Host live recovery requires SAME installed Run plus original Request relation and Definition', () => {
  const managed = {prepared:{}, request:{}, value:{}, definitionOriginal:{definition:{}}, closed:false};
  const f = rootPreparationFixture(managed); assert.equal(f.open(), f.view);
  assert.equal(f.constructed, 1); assert.equal(f.liveRuns.size, 2);
  const originalDefinition = managed.definitionOriginal;
  managed.definitionOriginal = {definition:{}};
  assert.throws(() => f.options.assertCurrent(), {code:'ForeignInstalledEffectManagedRun'});
  managed.definitionOriginal = originalDefinition;
  f.options.retired(f.view); assert.equal(f.liveRuns.size, 1); assert.equal(f.liveRuns.has(managed), true);
  assert.throws(() => f.open({}), {code:'ForeignInstalledEffectManagedRun'});
  assert.equal(f.constructed, 1);
});

test('actual initial close keeps original Store open until capture cleanup, then retires SAME Run', async () => {
  const initial = nodes(embeddedAst, node => node.type === 'VariableDeclarator' && node.id?.name === 'initialControl')
    .filter(node => node.init?.type === 'CallExpression' && node.init.arguments[0]?.type === 'ObjectExpression');
  assert.equal(initial.length, 1);
  const close = initial[0].init.arguments[0].properties.find(node => node.key.name === 'close');
  const events = []; let pending = true;
  const capture = {preparationKind:'effect-capture-recovery', selecting:false, closed:false,
    resources:{async close() {events.push('capture'); return !pending;}}};
  const run = {preparationKind:'effect-plan', preparationFunded:true, prepared:{}, closed:false};
  const record = {computeLiveRuns:new Set([run,capture])};
  const ports = {record, clientOperationError:error,
    preparation:{retireManagedComputeRun(actual) {assert.equal(actual, run.prepared); events.push('parent'); return () => events.push('finish');}},
    retirePreparationReferences() {events.push('aliases');},
    finishInstalledEffectModelScope() {assert.fail('No legacy retirement');}, checked:assert.fail,
    profiles:{retirePreparation() {events.push('registry');}}, host:{}, originalInstallation:{}};
  const body = `let observedClose, sourceManaged, sourceManagedClose, computeManaged, computeManagedClose,
    computeManagedFlight, resultReadWorkspace, resultPublicationClose, resultPublicationFlight, hostJournal, hostJournalClose,
    hostJournalOpen, hostJournalOwnership, hostJournalAdmitRootFormat, hostJournalFlight,
    hostInitialization, sourceInitializationServices, sourceInitializationSelection, duty, originals;
    let control = {}, controlClose = async () => {events.push('control'); return {pending:false};};
    const adopted = false;
    let resultPublication = {async close() {events.push('store'); return {pending:false};}};
    return ({${embedded.slice(close.start, close.end)}}).close;`;
  const closeActual = construct(body, {...ports, events});
  await assert.rejects(closeActual(), {code:'EffectCaptureResourceCleanupPending'});
  assert.deepEqual(events, ['capture']);
  pending = false; await closeActual();
  assert.deepEqual(events, ['capture','capture','parent','finish','store','aliases','control','registry']);
});

test('actual Effect custody releases original stage and payload aliases before returning recovery reservation', async () => {
  const text = source('./installed-effect-site.mjs');
  const cleanupCustody = construct(`${declaration(text, 'cleanupCustody')}; return cleanupCustody;`,
    {fail:code => {throw error(code);}});
  const events = []; let pending = true;
  const resource = {async close() {events.push('resource'); return !pending;}, status:() => ({pending})};
  const custody = cleanupCustody(undefined);
  custody.retainRecoveryResources(resource); custody.retainRecoveryResources(resource);
  custody.attach({releaseInputs() {events.push('inputs');}, dispose() {events.push('dispose');}});
  custody.requireRelease(() => {events.push('payloads');});
  assert.equal(await custody.cleanup(), false); assert.equal(custody.cleanupPending(), true);
  assert.deepEqual(events, ['inputs','payloads','dispose','resource']);
  pending = false; assert.equal(await custody.cleanup(), true); assert.equal(custody.cleanupPending(), false);
  assert.deepEqual(events, ['inputs','payloads','dispose','resource','resource']);
});

test('released physical child stays released while SAME resource cleanup remains pending', async () => {
  const text = source('./installed-effect-site.mjs');
  const cleanupCustody = construct(`${declaration(text, 'cleanupCustody')}; return cleanupCustody;`,
    {fail:code => {throw error(code);}});
  let physicalPending = true, resourcePending = true, physicalCleanups = 0, resourceCloses = 0;
  const physical = {close() {}, cleanup() {physicalCleanups++; physicalPending = false; return true;},
    cleanupPending:() => physicalPending};
  const custody = cleanupCustody(undefined, true);
  custody.attachPhysical(physical);
  custody.retainRecoveryResources({close() {resourceCloses++; return !resourcePending;},
    status:() => ({pending:resourcePending})});
  assert.equal(await custody.cleanup(), false);
  assert.equal(custody.cleanupPending(), true); assert.equal(physicalCleanups, 1); assert.equal(resourceCloses, 1);
  resourcePending = false;
  assert.equal(await custody.cleanup(), true); assert.equal(custody.cleanupPending(), false);
  assert.equal(await custody.cleanup(), true);
  assert.equal(physicalCleanups, 1); assert.equal(resourceCloses, 2);
  const neverAcquired = cleanupCustody(undefined, true);
  assert.equal(await neverAcquired.cleanup(), false); assert.equal(neverAcquired.cleanupPending(), true);
});

function recoveryFixture() {
  const text = source('./effect-run-recovery.mjs'), request = {}, definition = {identity:cid('3')};
  const retained = {runDefinition:definition, requestIdentity:request};
  const moon = {clientRequestAuthorityScopeCid:() => cid('2'), clientRequestCallerId:() => 'request',
    clientRequestLogicalScope:() => ({})};
  let recovered = 0, completed = false;
  const control = {}, captureRefusals = new WeakSet();
  class PublicationStoreError extends Error {}
  const ports = {runtimeCore:() => ({publicationControl:control}), runUpdateSelectionCid:() => undefined,
    originalUpdateTargetSelectionsCid:assert.fail, captureRefusals, PublicationStoreError,
    recoverCompletedEffectfulComputation:async (_options, resource) => {
      assert.ok(resource); recovered++; completed = true; return {};
    }, cid:value => /^sha256:[0-9a-f]{64}$/.test(value),
    text:value => typeof value === 'string' && value.length > 0, fail:code => {throw error(code);}};
  const recover = construct(`${declaration(text, 'recoverAdmittedEffectRun')}; return recoverAdmittedEffectRun;`, ports);
  const options = {requests:{lookupOwnedDefinition:() => retained}, store:{storeAuthorityCid:cid('4')},
    key:{namespaceId:'local', authorityScopeCid:cid('2'), requestId:'request', runDefinitionCid:cid('3')},
    principalId:'owner', authorizeEvidenceRead:() => true,
    contractLimits:{maxWireBytes:1000,maxNodes:100,maxDepth:32}};
  return {options, request, definition, recover:overrides => recover({...options,...overrides}, async () => moon),
    get recovered() {return recovered;}, get completed() {return completed;}};
}

test('actual admitted recovery transfers reservation before failed constructor and preserves original failure', async () => {
  const f = recoveryFixture(), primary = new Error('original constructor'); let transferred, closes = 0;
  const resource = {async close() {closes++; return false;}};
  await assert.rejects(f.recover({retainRecoveryResources: original => {transferred = original;},
    prepareRecoveryResources(options) {
      assert.equal(options.requestIdentity, f.request); assert.equal(options.runDefinition, f.definition);
      options.retain(resource); assert.equal(transferred, resource); throw primary;
    }}), cause => cause === primary);
  assert.equal(f.recovered, 0); assert.equal(closes, 1);
});

test('actual admitted recovery post-construction current refusal closes SAME resource and keeps primary', async () => {
  const f = recoveryFixture(), primary = new Error('original current changed'); let closes = 0;
  const resource = {begin() {}, reserve() {}, finish() {}, retainCleanup() {}, async close() {closes++; return false;}};
  await assert.rejects(f.recover({restoreOriginal:() => ({assertUpdateSelectionCurrent() {if (f.completed) throw primary;}}),
    prepareRecoveryResources(options) {options.retain(resource); return resource;}}), cause => cause === primary);
  assert.equal(f.recovered, 1); assert.equal(closes, 1);
});
