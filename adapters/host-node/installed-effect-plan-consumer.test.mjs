import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {snapshotClientRequest} from '@actql/client-wire';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {prepareInstalledEffectManagedPlanRun, readInstalledEffectManagedPlanRun}
  from './installed-effect-managed-run.mjs';
import {bindInstalledManagedSources} from './installed-managed-source.mjs';
import {selectAcquiredEffectSources, selectAcquiredEffectPlanInputs} from './acquired-effect-sources.mjs';
import {openAcquiredEffectComputation} from './acquired-effect-computation.mjs';
import {prepareInstalledRowCaptureChild} from './installed-row-capture-cleanup.mjs';
import {retainUpdateTargetSelection, originalUpdateTargetSelectionsCid, updateTargetSelectionMatchesRun}
  from './update-target-original-shape.mjs';

// Original runtime/admission ports are explicit. These tests exercise the real
// Node owner/consumers, not actual Common funding, vendor work or normal support.
const ok = value => ({$tag: 1, _0: value});
const checked = result => {if (result.$tag !== 1) throw result._0; return result._0;};

test('Effect Plan source inputs follow original checked occurrence order without a second Query preparation', () => {
  const prepared = {}, request = {}, selections = [{}, {}], declarations = [{}, {}], providers = [{}, {}];
  const calls = [];
  const sources = [0, 1].map(index => Object.freeze({admitsSource: ref => ref === `source-${index}`,
    managedEffectPlanSelection() {
      assert.strictEqual(this, sources[index]); calls.push(`original-${index}`);
      return Object.freeze({declaration: declarations[index], provider: providers[index],
        transferBytes: BigInt(20 + index), executionBytes: BigInt(10 + index)});
    }}));
  const moon = {clientProgramEffectAcquisitionCount: () => 2,
    clientProgramSelectInstalledEffectSourceInput(p, identity, stage, input) {
      assert.strictEqual(this, moon); assert.strictEqual(p, prepared); assert.strictEqual(identity, request);
      assert.equal(input, 0); calls.push(`select-${stage}`); return ok(selections[stage]);
    }, clientProgramSelectedSourceInputKind: () => 'query',
    clientProgramSelectedSourceInputRef: selected => `source-${1 - selections.indexOf(selected)}`,
    clientProgramEffectPrepareLocalQueryRequirement() {assert.fail('the Plan constructs its requirement once');}};
  const input = selectAcquiredEffectPlanInputs({moon, preparedEffect: prepared, requestIdentity: request,
    sourceProfile: {sources}, queryContract: 'original-query', evidenceContract: 'original-evidence'});
  assert.deepEqual(calls, ['select-0', 'original-1', 'select-1', 'original-0']);
  assert.strictEqual(input.declarations[0], declarations[1]); assert.strictEqual(input.declarations[1], declarations[0]);
  assert.strictEqual(input.providers[0], providers[1]); assert.strictEqual(input.providers[1], providers[0]);
  assert.deepEqual(input.transferBytes, [21n, 20n]); assert.deepEqual(input.executionBytes, [11n, 10n]);
  assert(Object.isFrozen(input)); assert(Object.isFrozen(input.declarations)); assert(Object.isFrozen(input.providers));
});

test('Effect preadmission selects the checked Source without preparing its Query requirement', () => {
  const prepared = {}, request = {}, original = {}, adapter = {
    admitsSource: ref => ref === 'original-source', prepare() {}, open() {},
  };
  let selections = 0;
  const moon = {clientProgramEffectAcquisitionCount: () => 1,
    clientProgramSelectInstalledEffectSourceInput(p, identity, stage, input) {
      same([p, identity, stage, input], [prepared, request, 0, 0]); selections++; return ok(original);
    }, clientProgramSelectedSourceInputKind: value => {assert.strictEqual(value, original); return 'query';},
    clientProgramSelectedSourceInputRef: value => {assert.strictEqual(value, original); return 'original-source';},
    clientProgramEffectPrepareLocalQueryRequirement() {assert.fail('one retained Plan owns Query preparation');}};
  const same = (actual, expected) => actual.forEach((value, index) => assert.strictEqual(value, expected[index]));
  const selected = selectAcquiredEffectSources({moon, preparedEffect: prepared,
    requestIdentity: request, sourceProfile: adapter});
  assert.strictEqual(selected[0].adapter, adapter); assert.equal(selections, 1);
});

test('Effect native Source inputs retain complete physical bounds and each original mixed occurrence', () => {
  const prepared = {}, request = {}, declaration = {}, provider = {}, rowInput = {}, nativeInput = {};
  const contracts = Object.freeze(['original-query', 'original-evidence', 'original-two-receipt']);
  const native = Object.freeze({sourceRef: 'source:native', schema: 'main', table: 'records', contracts});
  const originals = [Object.freeze({nativeSource: native, transferBytes: 37n, executionBytes: 109n}),
    Object.freeze({declaration, provider, transferBytes: 19n, executionBytes: 23n})];
  const calls = [];
  const sources = originals.map((original, index) => Object.freeze({
    admitsSource: ref => ref === ['source:native', 'source:row'][index],
    managedEffectPlanSelection() {assert.strictEqual(this, sources[index]); return original;},
  }));
  const moon = {
    clientProgramEffectAcquisitionCount: () => 2,
    clientProgramSelectInstalledEffectSourceInput(p, r, task, input) {
      assert.strictEqual(p, prepared); assert.strictEqual(r, request); assert.equal(input, 0);
      calls.push(`select-${task}`); return ok(task);
    },
    clientProgramSelectedSourceInputKind: () => 'query',
    clientProgramSelectedSourceInputRef: task => ['source:row', 'source:native'][task],
    clientProgramInstalledEffectRowSourceInputPrepare(d, p) {
      assert.strictEqual(this, moon); assert.strictEqual(d, declaration); assert.strictEqual(p, provider);
      calls.push('row-input'); return ok(rowInput);
    },
    clientProgramInstalledEffectDuckDBSourceInputPrepare(ref, schema, table, ...bodies) {
      assert.strictEqual(this, moon); assert.deepEqual([ref, schema, table], [native.sourceRef, native.schema, native.table]);
      assert.deepEqual(bodies, contracts); calls.push('native-input'); return ok(nativeInput);
    },
    clientProgramEffectPrepareLocalQueryRequirement() {assert.fail('the same Plan constructs each Query once');},
    clientProgramPrepareDuckDBCaptureCapacity() {assert.fail('selecting inputs constructs no capture');},
  };
  const result = selectAcquiredEffectPlanInputs({moon, preparedEffect: prepared, requestIdentity: request,
    sourceProfile: {sources}, queryContract: 'row-query', evidenceContract: 'row-evidence'});
  assert.deepEqual(calls, ['select-0', 'select-1', 'row-input', 'native-input']);
  assert.strictEqual(result.inputs[0], rowInput); assert.strictEqual(result.inputs[1], nativeInput);
  assert.deepEqual(result.transferBytes, [19n, 37n]); assert.deepEqual(result.executionBytes, [23n, 109n]);
  assert.equal(result.declarations, undefined); assert.equal(result.providers, undefined);
  assert(Object.isFrozen(result)); assert(Object.isFrozen(result.inputs));
});

test('Effect native Source selection refuses foreign or incomplete originals without row fallback', () => {
  const contracts = Object.freeze(['query', 'evidence', 'two-receipt']);
  const native = Object.freeze({sourceRef: 'source:native', schema: 'main', table: 'records', contracts});
  let original = Object.freeze({nativeSource: native, transferBytes: 31n, executionBytes: 71n}), constructs = 0;
  const source = {admitsSource: ref => ref === 'source:native', managedEffectPlanSelection: () => original};
  const moon = {clientProgramEffectAcquisitionCount: () => 1,
    clientProgramSelectInstalledEffectSourceInput: () => ok({}), clientProgramSelectedSourceInputKind: () => 'query',
    clientProgramSelectedSourceInputRef: () => 'source:native',
    clientProgramInstalledEffectDuckDBSourceInputPrepare() {constructs++; throw refusal;},
    clientProgramInstalledEffectRowSourceInputPrepare() {assert.fail('no row declaration substitute');}};
  const options = {moon, preparedEffect: {}, requestIdentity: {}, sourceProfile: source};
  const refusal = new Error('original-native-input-refusal');
  assert.throws(() => selectAcquiredEffectPlanInputs(options), error => error === refusal);
  for (const change of [
    {nativeSource: Object.freeze({...native, sourceRef: 'source:foreign'})},
    {nativeSource: Object.freeze({...native, contracts: Object.freeze(contracts.slice(0, 2))})},
    {nativeSource: {...native}}, {declaration: {}}, {provider: {}}, {executionBytes: -1n},
  ]) {
    original = Object.freeze({nativeSource: native, transferBytes: 31n, executionBytes: 71n, ...change});
    assert.throws(() => selectAcquiredEffectPlanInputs(options), /InstalledSourceCapacityUnavailable/);
  }
  assert.equal(constructs, 1);
  original = Object.freeze({nativeSource: native, transferBytes: 31n, executionBytes: 71n});
  delete moon.clientProgramInstalledEffectDuckDBSourceInputPrepare;
  assert.throws(() => selectAcquiredEffectPlanInputs(options), /InstalledEffectPlanRuntimeUnavailable/);
});

function fixture() {
  const prepared = {}, request = {}, plan = {}, parent = {}, original = {};
  const facts = Object.freeze({prepared, identity: request, compilation: {}, allowed: {}, definition: {},
    queryTimePreparation: undefined, modelCompiled: undefined});
  const runs = new WeakMap(), liveRuns = new Set(), calls = [];
  const inputs = Object.freeze({}), sourceProfile = {};
  let current = true, checkCallback = () => {}, selected = plan;
  const failure = new Error('original-current');
  const runtime = {
    clientProgramInstalledEffectOperationControlConstructionBegin() {return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationControlConstructionComplete() {return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationControlsRetain() {return ok(plan);},
    clientProgramInstalledManagedRunRetire() {}, clientProgramNodeEffectManagedPlanCleanup() {},
    clientProgramInstalledEffectManagedRunCheck(value, p, r) {
      assert.strictEqual(this, runtime); assert.strictEqual(value, parent);
      assert.strictEqual(p, prepared); assert.strictEqual(r, request); return ok();
    },
    // The bound Core getter now owns currentness; keep the same original
    // callback fixture inside that port rather than a duplicate check call.
    clientProgramInstalledEffectManagedOperationPlan(value, p, r) {
      assert.strictEqual(this, runtime); assert.strictEqual(value, parent);
      assert.strictEqual(p, prepared); assert.strictEqual(r, request); checkCallback(); return ok(plan);
    },
  };
  const requestInput = {};
  const manager = {adoptEffectPreparation(p, input, identity, scope) {
    assert.strictEqual(this, manager); assert.strictEqual(p, prepared); assert.strictEqual(input, requestInput);
    assert.strictEqual(identity, request); assert.strictEqual(scope, plan);
    assert.strictEqual(runs.get(p).operationPlan, scope, 'retain before original completion/adoption');
    calls.push('adopt-request'); return {original, value: parent, operationPlan: plan};
  }};
  const selection = Object.freeze({prepareManagedPlan(f, i) {
    assert.strictEqual(this, selection); assert.strictEqual(f, facts); assert.strictEqual(i, inputs);
    assert(liveRuns.has(runs.get(prepared)), 'retain partial selection before callback');
    calls.push('select'); if (selected instanceof Error) throw selected; return selected;
  }});
  const options = {runs, liveRuns, runtime, manager, prepared, request, requestInput, selection, facts, inputs,
    sourceProfile, checked, assertCurrent() {if (!current) throw failure;}};
  return {options, calls, plan, parent, facts, runs, liveRuns, prepared, request, runtime,
    setCheck(fn) {checkCallback = fn;}, setSelected(value) {selected = value;},
    revoke() {current = false;}, failure};
}

test('Effect plan is retained before Request adoption and remains the same execution scope', () => {
  const f = fixture();
  assert.strictEqual(prepareInstalledEffectManagedPlanRun(f.options), f.parent);
  assert.strictEqual(prepareInstalledEffectManagedPlanRun(f.options), f.parent);
  assert.deepEqual(f.calls, ['select', 'adopt-request']);
  const run = readInstalledEffectManagedPlanRun(f.options);
  assert.strictEqual(run.operationPlan, f.plan); assert.strictEqual(run.value, f.parent);
  assert.throws(() => prepareInstalledEffectManagedPlanRun({...f.options, request: {}}),
    {code: 'ForeignInstalledEffectManagedRun'});
  assert.throws(() => prepareInstalledEffectManagedPlanRun({...f.options,
    facts: {...f.facts, definition: {}}}), {code: 'ForeignInstalledEffectManagedRun'});
});

test('Effect original callbacks cannot replace a parent, record a new failure or retire its live record', () => {
  for (const change of ['parent', 'failure', 'retired']) {
    const f = fixture(); prepareInstalledEffectManagedPlanRun(f.options);
    const failure = new Error('original-callback-failure');
    f.setCheck(() => {
      const run = f.runs.get(f.prepared);
      if (change === 'parent') run.value = {};
      if (change === 'failure') run.failure = failure;
      if (change === 'retired') f.liveRuns.delete(run);
    });
    assert.throws(() => readInstalledEffectManagedPlanRun(f.options), error =>
      change === 'failure' ? error === failure : error.code === 'ForeignInstalledEffectManagedRun');
  }
});

test('missing or failed selected Effect inventory cannot retry under a scalar quote or another original', () => {
  for (const missing of [false, true]) {
    const f = fixture(), failure = new Error('original-plan-construction');
    f.setSelected(failure);
    const options = missing ? {...f.options, selection: {}} : f.options;
    let first;
    assert.throws(() => prepareInstalledEffectManagedPlanRun(options), error => {
      first = error; return missing ? error.code === 'InstalledEffectOperationDemandUnavailable' : error === failure;
    });
    assert.throws(() => prepareInstalledEffectManagedPlanRun(options), error => error === first);
    assert.equal(f.calls.includes('quote'), false);
    assert.equal(f.calls.includes('admit'), false);
  }
});

test('Effect failed original Request adoption cannot retry through independent admission', () => {
  const f = fixture(), failure = new Error('original-begin-failed');
  f.options.manager.adoptEffectPreparation = () => {throw failure;};
  assert.throws(() => prepareInstalledEffectManagedPlanRun(f.options), error => error === failure);
  const run = f.runs.get(f.prepared);
  assert.equal(run.admission, undefined); assert.equal(run.cleanup, undefined);
  assert.throws(() => prepareInstalledEffectManagedPlanRun(f.options), error => error === failure);
  assert.deepEqual(f.calls, ['select']);
});

test('Source selection and preparation borrow the same retained Effect plan and managed parent', async () => {
  const prepared = {}, parent = {}, plan = {}, requirement = {}, sourcePrepared = {}, calls = [];
  const source = {realizationKey: 'row-source-acquired', admitsSource: ref => ref === 'source',
    managedCaptureCapacity() {}, ledgerCapacity() {return {capacity: {}, transferBytes: 1n, executionBytes: 1n};},
    async prepare(facts) {
      assert.strictEqual(this, source); assert.strictEqual(facts.preparedEffect, prepared);
      assert.strictEqual(facts.managedRun, parent); calls.push('prepare'); return sourcePrepared;
    }, open() {},
  };
  const profile = bindInstalledManagedSources(source, original => {
    assert.strictEqual(original, prepared); return parent;
  });
  const moon = {clientProgramEffectAcquisitionCount: () => 1,
    clientProgramInstalledEffectManagedPlanSource(original, slot) {
      assert.strictEqual(original, plan); assert.equal(slot, 0); calls.push('plan-source');
      return ok({_0: {}, _1: requirement, _2: {}, _3: {}});
    }, clientProgramQueryRequirementSourceRef(value) {assert.strictEqual(value, requirement); return 'source';},
    clientProgramEffectPrepareLocalQueryRequirement() {assert.fail('must not reconstruct the requirement');}};
  const selected = selectAcquiredEffectSources({moon, preparedEffect: prepared, sourceProfile: profile, managedPlan: plan});
  assert.equal(selected.length, 1);
  assert.strictEqual(await selected[0].adapter.prepare({preparedEffect: prepared}), sourcePrepared);
  assert.strictEqual(profile.ledgerCapacity(sourcePrepared).managedRun, parent);
  assert.deepEqual(calls, ['plan-source', 'prepare']);
});

const valuesSource = readFileSync(new URL('./local-values-plan.mjs', import.meta.url), 'utf8');
const valuesAst = parse(valuesSource, {ecmaVersion: 'latest', sourceType: 'module'});
const openNode = valuesAst.body.find(node => node.type === 'ExportNamedDeclaration' &&
  node.declaration?.id?.name === 'openSourceFreeEffectComputation').declaration;
const openSourceFree = new Function('checked', valuesSource.slice(openNode.start, openNode.end) +
  ';return openSourceFreeEffectComputation;')(checked);

test('source-free Effect open consumes its original planned parent without old Host constructors', () => {
  const managedRun = {}, prepared = {}, identity = {}, owner = {}, host = {}, calls = [];
  const moon = {clientProgramInstalledEffectManagedRunCheck(parent, p, request) {
    assert.strictEqual(parent, managedRun); assert.strictEqual(p, prepared); assert.strictEqual(request, identity);
    calls.push('current'); return ok();
  }, clientProgramInstalledEffectManagedHostOpen(parent, bound, sources) {
    assert.strictEqual(parent, managedRun); assert.strictEqual(bound, owner); assert.deepEqual(sources, []);
    calls.push('same-plan-open'); return ok(host);
  }};
  assert.strictEqual(openSourceFree({moon, managedRun, facts: {prepared, identity, owner}}), host);
  assert.deepEqual(calls, ['current', 'same-plan-open']);
  assert.throws(() => openSourceFree({moon, facts: {prepared, identity, owner}}), /InstalledEffectPlanUnavailable/);
});

test('an unadmitted acquired Effect refuses before Source selection, preparation or physical read', async () => {
  let custody, selected = 0;
  await assert.rejects(openAcquiredEffectComputation({
    moon: {clientProgramEffectAcquisitionCount: () => 1, clientProgramEffectSerializationOccurrences: () => []},
    acquired: {prepared: {}}, sourceProfile: {admitsSource() {selected++;}, prepare() {selected++;}, open() {selected++;}},
    retainComputationOwner(value) {custody = value;},
  }), /InstalledEffectPlanUnavailable/);
  assert.equal(selected, 0); assert.equal(custody.cleanupPending(), true);
  await custody.close(); assert.equal(await custody.cleanup(), true);
});

const rowSource = readFileSync(new URL('./installed-row-source.mjs', import.meta.url), 'utf8');
const rowAst = parse(rowSource, {ecmaVersion: 'latest', sourceType: 'module'});
function namedFunction(ast, name) {
  let selected;
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'FunctionDeclaration' && node.id.name === name) {
      assert.equal(selected, undefined); selected = node;
    }
    for (const child of Object.values(node)) {
      if (Array.isArray(child)) child.forEach(visit);
      else if (child && typeof child === 'object') visit(child);
    }
  };
  visit(ast); assert(selected); return selected;
}
const acquireNode = namedFunction(rowAst, 'acquire');
const makeAcquire = new Function('ports', `
  const {preparations,originalReader,captureCapacity,currentRead,site,moon,
    randomUUID,cid,maxTransferBytes,limits,startInstalledRowRun,operationBindings,
    readPages,grantBeforeBegin,fail,checked}=ports;
  const directReadIdentity=undefined,prepareRead=undefined,listingReportCapacity=undefined;
  const pageLimits=undefined,referenceIssuer=undefined,managedPageLimits=undefined;
  const preparingSourceReads=new Set(),closeSourceRead=undefined,readerDemand=undefined,originalOperationScope=undefined;
  const text=value=>typeof value==='string'&&value.length>0;
  ${rowSource.slice(acquireNode.start, acquireNode.end)}
  return acquire;
`);

test('an original planned Resource read never substitutes for the provider Credential grant', async () => {
  for (const mode of ['planned-provider', 'ordinary-provider', 'local-original']) {
    const prepared = {}, preparedSource = {checkedSource: {requirementCid: 'original-requirement'}},
      acquisition = {}, access = {}, originalRead = {};
    const occurrence = {stage: 0, input: 0, task: 0}, state = {};
    const originalGrant = {}, scope = {}, decision = {action: 'dispatch'};
    const beforeRead = new Error('stop-before-any-page');
    let grants = 0, closed = 0, reads = 0;
    const provider = mode !== 'local-original';
    const owner = {checkedOwner: prepared, effectful: true, access, occurrence, acquisition,
      resource: 'records', originalRead: mode === 'ordinary-provider' ? undefined : originalRead,
      managedRun: mode === 'planned-provider' ? {} : undefined};
    const preparations = new WeakMap([[preparedSource, owner]]);
    const read = async options => {
      reads++;
      if (provider) {
        assert.equal(typeof options.authorizationFor, 'function');
        const authorized = await options.authorizationFor(0);
        assert.strictEqual(authorized.grant, originalGrant); assert.strictEqual(authorized.scope, scope);
        assert.equal(authorized.useId, 'nonce-read-0');
      } else assert.equal(options.authorizationFor, undefined);
      throw beforeRead;
    };
    const moon = {clientProgramRowSourceColumns: () => ['id'],
      clientProgramRowSourceRequestWire: () => ok('{}'), clientProgramRowSourceBegin: () => ok(),
      clientProgramRowSourceIsListing: () => false};
    const site = {connection: 'original-connection', issueReadGrant(options) {
      assert.equal(options.operation, 'original-read'); assert.strictEqual(options.decision, decision);
      assert.equal(options.resource, 'records'); grants++;
      return {grant: originalGrant, scope};
    }};
    const acquire = makeAcquire({preparations, originalReader: provider ? {capacity: {}, prepare() {}, receiver: {}} : undefined,
      captureCapacity: () => ({}), currentRead: async () => decision, site, moon,
      randomUUID: () => 'nonce', cid: () => 'original-binding', maxTransferBytes: 1n,
      limits: {maxPages: 1, maxPageBytes: 1, maxPageRows: 1, maxCaptureRows: 1},
      startInstalledRowRun: () => ({run: {}, readProvider: ({options}) => read(options),
        closeAfterFailure(actual) {assert.strictEqual(actual, state); closed++;}}),
      operationBindings: new Map([['records', 'original-read']]), readPages: read, grantBeforeBegin: false,
      fail: code => {throw Object.assign(new Error(code), {code});}, checked});
    await assert.rejects(acquire(state, {preparedEffect: prepared, preparedSource, sourceAccess: access,
      occurrence, ledger: {}}), error => error === beforeRead);
    assert.equal(grants, provider ? 1 : 0); assert.equal(reads, 1); assert.equal(closed, 1);
  }
});


// Execute the original recovered Row Effect and its actual physical-route
// guard/retirement. Credential/Core/provider ports are explicit, never a new
// Common Plan, Resource grant or ordinary Saved acceptance.
const recoveryRowSource = readFileSync(new URL('./installed-row-effect.mjs', import.meta.url), 'utf8');
const recoveryRowNodes = [];
(function walk(node) {
  if (!node || typeof node !== 'object') return;
  if (node.type === 'FunctionDeclaration' && node.id.name === 'prepareRecovered' ||
      node.type === 'VariableDeclarator' && node.id.name === 'physicalRoute') recoveryRowNodes.push(node);
  for (const child of Object.values(node)) if (Array.isArray(child)) child.forEach(walk);
  else if (child && typeof child === 'object') walk(child);
})(parse(recoveryRowSource, {ecmaVersion: 'latest', sourceType: 'module'}));
const recoveryNode = recoveryRowNodes.find(node => node.type === 'FunctionDeclaration');
const recoveryRouteNode = recoveryRowNodes.find(node => node.type === 'VariableDeclarator').init;

function recoveredPhysicalFixture({managed = true, pending = false, failPrepare = false, prepareFailure, reenter, closeDuringRetain = false, storedResponse} = {}) {
  const prepared = {}, request = {}, value = {}, operationPlan = {}, preview = {}, computation = {}, storedResults = {},
    definition = {identity: 'original-definition'};
  const events = [], child = {}, originalCurrent = {}, current = {}, entry = {request: {}}, member = {memberIndex: 0};
  const body = {invocation_cid: 'original-invocation', run_identity_cid: 'original-run',
    authoring_context: {authoring_context_cid: 'original-authoring'}, effects: [{capability_evidence_cid: 'original-capability', changes: [{}]}]};
  const owner = {managedPlanRecipe: {credentialOperations: [{}]}, owned: {}};
  const run = {prepared, request, value, operationPlan, definitionOriginal: {definition}, closed: false, controlConstruction: (receiver, method, args) => Reflect.apply(method, receiver, args)};
  let supplied, retained, stage, routeOptions, closed = false, allowClose = !pending;
  const ledger = {close() {events.push('ledger-close'); closed = true;},
    readClaimedResponse() {events.push('stored-read'); return {};},
    recoverClaimFacts() {return {members: [{claims: []}]};}};
  const moon = {clientRequestRelation: (left, right) => left === right ? 1 : 2,
    strategyPublicationContractIdentity: original => original.identity}; run.runtime = moon;
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const realRoute = new Function('ownerOf', 'fail', 'return (' +
    recoveryRowSource.slice(recoveryRouteNode.start, recoveryRouteNode.end) + ');')(() => owner, fail);
  const control = {effectComputationPreviewWire: () => JSON.stringify(body),
    effectComputationPreviewLedgerIdentity: () => originalCurrent,
    effectComputationPreviewSemanticCid: () => 'original-preview'};
  const limits = {preview: {}, key: {}, maxRows: 1, maxWork: 1, maxFrontierWork: 1};
  const ports = {moon, localContractLimits: {}, singular: undefined, ROUTING_VERSION: 'original-version',
    text: value => typeof value === 'string' && value.length > 0, selectionChanged: () => assert.fail('No target selection'),
    recoveredMembers: () => [member], bindRunResources() {}, selectionFence: () => () => {},
    memberDispatch: () => 'original-dispatch', limits,
    effect: {recoveredPreviewKeys: () => [], admitPreviewIdentity: () => ({})},
    openLedger() {events.push('ledger-open'); return ledger;},
    recoveredEntries: () => ({entries: [[entry]], currents: [current]}),
    admitCapability: () => ({identity: 'original-capability'}), orderedSourceIndexes: () => [0],
    physicalRoute(options) {routeOptions = options; return realRoute(options);},
    owners: [owner], scopes: () => [{}], canonicalJson: JSON.stringify, fail,
    admitRow: () => ({}), settle() {events.push('settle');},
    async recoverProjectedEffectResponse() {events.push('stored-await'); await storedResponse; return {recovered: {}};},
    prepareCredentialOperation(options) {
      supplied = options; events.push('operation');
      assert.strictEqual(options.managedEffect, run);
      assert.equal(options.phase, 'write'); assert.equal(options.rowIndex, 0);
      assert.strictEqual(options.member, member);
      let retired = false;
      const original = {async prepare() {events.push('prepare'); if (failPrepare) throw prepareFailure; return child;},
        async release() {
          events.push('release'); if (reenter) await reenter(retained);
          if (!allowClose || !options.retireRequestAliases()) return false;
          retired = true; return true;
        }, retry() {return this.release();}, status: () => ({pending: !retired})};
      return prepareInstalledRowCaptureChild({children: options.requestChildren,
        create: () => original, assertCurrent: () => {}, signal: undefined});
    }};
  const prepare = new Function(...Object.keys(ports), 'return ' +
    recoveryRowSource.slice(recoveryNode.start, recoveryNode.end))(...Object.values(ports));
  const facts = {moon, control, store: {}, recovered: {prepared, runDefinition: definition, requestIdentity: request, requestScope: {},
    computation: {computation, preview, storedResults}}, continuation: {version: 'original-version',
    program_id: 'original-program', stage_id: 'original-stage', members: [{dispatch_request_cid: 'original-dispatch'}]},
    managedEffect: managed ? run : undefined, retainRecoveryOwner(value) {retained = value; if (closeDuringRetain) void value.cleanup();}};
  return {facts, run, child, events, entry, current, ledger, get owner() {return retained;},
    get options() {return supplied;}, get closed() {return closed;},
    begin() {stage = prepare(facts); return stage;},
    operate() {return routeOptions.physicalOperations({member, rowIndex: 0, phase: 'write', operation: 'original-write', assertCurrent() {}});},
    allowClose() {allowClose = true;}, stage: () => stage};
}

test('recovered Effect physical route retains the same original operation child under its existing cleanup owner', async () => {
  const f = recoveredPhysicalFixture(); f.begin();
  assert.strictEqual(await f.operate(), f.child);
  assert.equal(f.owner.cleanupPending(), true);
  assert.equal(f.closed, false);
  assert.equal(await f.owner.cleanup(), true);
  assert.equal(f.closed, true);
  assert.deepEqual(f.events, ['ledger-open', 'operation', 'prepare', 'release', 'ledger-close']);
});


test('recovered Effect pending child keeps the Ledger and original retry until actual retirement', async () => {
  const f = recoveredPhysicalFixture({pending: true}); f.begin(); await f.operate();
  assert.equal(await f.owner.cleanup(), false); assert.equal(f.owner.cleanupPending(), true);
  assert.equal(f.closed, false); assert.equal(f.events.includes('ledger-close'), false);
  f.allowClose(); assert.equal(await f.stage().dispose(), true);
  assert.equal(f.owner.cleanupPending(), false);
  assert.deepEqual(f.events, ['ledger-open', 'operation', 'prepare', 'release', 'release', 'ledger-close']);
  assert.equal(await f.owner.cleanup(), true);
  assert.equal(f.events.filter(event => event === 'ledger-close').length, 1);
  await assert.rejects(async () => f.operate(), {code: 'InstalledRowEffectRouteRetired'});
});

test('recovered Effect cleanup observes reentry as pending instead of deadlocking or closing its parent early', async () => {
  const observations = [];
  const f = recoveredPhysicalFixture({reenter: async owner => observations.push(await owner.cleanup())});
  f.begin(); await f.operate();
  assert.equal(await f.owner.cleanup(), true); assert.deepEqual(observations, [false]);
  assert.deepEqual(f.events, ['ledger-open', 'operation', 'prepare', 'release', 'ledger-close']);
});

test('recovered Effect failed child preparation preserves undefined and retains its original cleanup', async () => {
  const f = recoveredPhysicalFixture({failPrepare: true, prepareFailure: undefined, pending: true}); f.begin();
  let thrown = false;
  try {await f.operate();} catch (error) {thrown = true; assert.strictEqual(error, undefined);}
  assert.equal(thrown, true); assert.equal(f.options.requestChildren.length, 1);
  assert.equal(await f.owner.cleanup(), false); assert.equal(f.closed, false);
  f.allowClose(); assert.equal(await f.owner.cleanup(), true);
  assert.equal(f.events.filter(event => event === 'operation').length, 1);
});

test('recovered Effect refuses missing or foreign managed originals without a legacy physical substitute', async () => {
  const missing = recoveredPhysicalFixture({managed: false});
  assert.throws(() => missing.begin(), {code: 'InstalledEffectPhysicalPlanUnavailable'});
  assert.equal(missing.events.includes('operation'), false);
  assert.equal(await missing.owner.cleanup(), true);
  const foreign = recoveredPhysicalFixture(); foreign.run.request = {};
  assert.throws(() => foreign.begin(), {code: 'ForeignInstalledEffectManagedRun'});
  assert.deepEqual(foreign.events, []);
});

test('recovered Effect retains its Owner before a reentrant constructor cleanup and remains closeable', async () => {
  const f = recoveredPhysicalFixture({closeDuringRetain: true});
  assert.throws(() => f.begin(), {code: 'InstalledRowEffectRouteRetired'});
  assert.equal(f.closed, false); assert.equal(f.owner.cleanupPending(), true);
  assert.equal(await f.owner.cleanup(), true);
  assert.deepEqual(f.events, ['ledger-open', 'ledger-close']);
});


test('recovered Effect existing Site custody waits for the same operation child before capture resources', async () => {
  const site = readFileSync(new URL('./installed-effect-site.mjs', import.meta.url), 'utf8');
  const node = parse(site, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'cleanupCustody');
  assert(node);
  const make = new Function('fail', 'return ' + site.slice(node.start, node.end))(
    code => {throw Object.assign(new Error(code), {code});});
  const f = recoveredPhysicalFixture({pending: true}), stage = f.begin(); await f.operate();
  const custody = make(); let captureClose = 0;
  custody.attach(stage); custody.attachPhysical(f.owner);
  custody.retainRecoveryResources({close() {captureClose++; return true;}, status: () => ({pending: true})});
  await custody.close(); assert.equal(await custody.cleanup(), false);
  assert.equal(captureClose, 0); assert.equal(f.closed, false);
  f.allowClose(); assert.equal(await custody.cleanup(), true);
  assert.equal(captureClose, 1); assert.equal(custody.cleanupPending(), false);
  assert.equal(f.events.filter(event => event === 'ledger-close').length, 1);
});

test('recovered Effect stored-response projection holds its original Ledger until the same await settles', async () => {
  let finish;
  const gate = new Promise(resolve => {finish = resolve;}), f = recoveredPhysicalFixture({storedResponse: gate});
  const stage = f.begin(), work = stage.apply.reconcileStoredResponses({members: [{claims: [{}]}], preview: {}});
  assert.equal(f.events.includes('stored-await'), true);
  assert.equal(await f.owner.cleanup(), false); assert.equal(f.closed, false);
  finish(); await assert.rejects(work, {code: 'InstalledRowEffectRouteRetired'});
  assert.equal(f.events.includes('settle'), false);
  assert.equal(await f.owner.cleanup(), true); assert.equal(f.closed, true);
});


test('recovered Effect binds its existing managed Plan to the same saved Definition before opening its Ledger', async () => {
  for (const original of [undefined, {identity: 'foreign-definition'}]) {
    const f = recoveredPhysicalFixture(); f.run.definitionOriginal = {definition: original};
    assert.throws(() => f.begin(), {code: 'ForeignInstalledEffectManagedRun'});
    assert.deepEqual(f.events, []);
  }
  const f = recoveredPhysicalFixture(); f.begin();
  assert.equal(await f.owner.cleanup(), true);
  assert.deepEqual(f.events, ['ledger-open', 'ledger-close']);
});


// Actual installed original-material helper and normal validateRun caller.
// Native codec/selection/data ports are explicit; this proves JS handoff and
// no legacy compiler fallback, not an installation or capacity admission.
function installedOriginalCompilerFixture({available = true, refusal, forbidProjection = false} = {}) {
  const source = readFileSync(new URL('./installed-update-originals.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const found = new Map();
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'VariableDeclaration' && node.declarations.length === 1 &&
        ['admitWithCompilation', 'restoreEffectMaterials', 'restoreRun'].includes(node.declarations[0].id.name)) {
      const name = node.declarations[0].id.name; assert(!found.has(name)); found.set(name, node);
    }
    if (node.type === 'Property' && node.key?.name === 'validateRun') found.set('validateRun', node);
    for (const child of Object.values(node)) if (Array.isArray(child)) child.forEach(visit);
    else if (child && typeof child === 'object') visit(child);
  })(ast);
  assert.equal(found.size, 4);
  const prepared = {}, compilation = {}, allowed = {}, identity = {}, definition = {};
  const materials = {}, original = {materialsWire: 'original-materials', installations: []};
  const runDefinition = {identity: 'original-definition'}, calls = [], counts = {bindings: 0};
  const originalSelection = {}, foreignPrepared = {};
  let binding;
  const fail = () => {throw Object.assign(new Error('InstalledEffectOriginalSelectionChanged'),
    {code: 'InstalledEffectOriginalSelectionChanged'});};
  const moon = {clientProgramAdmitEffectRunMaterials(wire, run, ...args) {
    assert.deepEqual([wire, run], [original.materialsWire, runDefinition.identity]);
    assert.strictEqual(args.at(-1), identity); calls.push('wire-only'); return ok(materials);
  }, clientProgramEffectRunMaterialsPrepared: value => {assert.strictEqual(value, materials); return prepared;},
    clientProgramEffectRunMaterialsCompilation: value => {assert.strictEqual(value, materials); return compilation;},
    clientProgramEffectRunMaterialsAllowed: value => {assert.strictEqual(value, materials); return allowed;},
    clientProgramEffectRunMaterialsDefinition: value => {assert.strictEqual(value, materials); return definition;},
    clientProgramEffectRunMaterialsTargetSelections: value => {assert.strictEqual(value, materials); return ok([]);},
    clientProgramEffectTargetSelectionOriginal: () => [originalSelection],
    clientProgramEffectTargetSelectionMatchesPrepared(value, owner) {
      return value === originalSelection && (owner === prepared || owner === foreignPrepared);
    },
    clientProgramEffectTargetSelectionWire: () => '[]',
    clientProgramEffectTargetSelectionCid: () => 'original-selection',
    clientProgramEffectTargetSelectionMatchesRun(value, owner, run) {
      return value === originalSelection && owner === prepared && run === definition;
    }};
  if (available) moon.clientProgramAdmitEffectRunMaterialsWithCompilation = function(wire, run, original, request, ...flags) {
    assert.strictEqual(this, moon); assert.strictEqual(original, compilation); assert.strictEqual(request, identity);
    assert.equal(wire, 'original-materials'); assert.equal(run, runDefinition.identity);
    assert.deepEqual(flags, [false, true, true, true, true, false, false]);
    calls.push('same-original'); if (refusal !== undefined) throw refusal; return ok(materials);
  };
  const ports = {moon, features: [false, true, true, true, true, false, false], checked, fail,
    runUpdateSelectionCid: () => 'original-selection', updateTargetRunOriginalShape: () => true,
    // The actual conversion creates distinct DATA arrays borrowing the SAME
    // opaque selection. Equal wrapper identity must never stand in for it.
    selectionsOf: value => retainUpdateTargetSelection(moon, value),
    updateTargetSelectionsCid: originalUpdateTargetSelectionsCid,
    updateTargetSelectionMatchesRun,
    bind(selected) {counts.bindings++; binding = {updateTargetSelections: selected,
      assertUpdateSelectionCurrent() {}}; return binding;}, compilations: new WeakMap(),
    capturePrepared(value, original) {if (forbidProjection) assert.fail('Retained original must not be encoded again'); assert.strictEqual(value, prepared); assert.strictEqual(original, compilation); return binding;},
    same: (left, right) => left === right};
  const nodes = ['admitWithCompilation', 'restoreEffectMaterials', 'restoreRun'].map(name => found.get(name));
  const code = nodes.map(node => source.slice(node.start, node.end)).join('\n') +
    ';return {restoreEffectMaterials,validateRun:({' + source.slice(found.get('validateRun').start, found.get('validateRun').end) + '}).validateRun};';
  const owner = new Function(...Object.keys(ports), code)(...Object.values(ports));
  return {owner, moon, prepared, compilation, identity, original, runDefinition, get binding() {return binding;}, calls, counts, foreignPrepared,
    validate() {return owner.validateRun({prepared, compilation, evidence: {updateTargetRunOriginal: original}, runDefinition, identity});}};
}

test('installed original Run validation binds its same compiler once and never rechecks through the wire-only codec', () => {
  const f = installedOriginalCompilerFixture();
  f.moon.clientProgramAdmitEffectRunMaterialsWithCompilation = () => assert.fail('No changed implementation lookup');
  f.moon.clientProgramAdmitEffectRunMaterials = () => assert.fail('No duplicate check or compiler');
  assert.deepEqual(f.validate(), f.binding);
  assert.deepEqual(f.calls, ['same-original']);
});

test('installed original Run validation refuses a missing typed binding and preserves refusal without compiler fallback', () => {
  const missing = installedOriginalCompilerFixture({available: false});
  assert.throws(missing.validate, {code: 'InstalledEffectOriginalSelectionChanged'});
  assert.deepEqual(missing.calls, []);
  const refusal = new Error('OriginalBoundMaterialsRefused'), f = installedOriginalCompilerFixture({refusal});
  assert.throws(f.validate, error => error === refusal);
  assert.deepEqual(f.calls, ['same-original']);
});

test('independent wire-only material restoration remains on its existing declared codec', () => {
  const f = installedOriginalCompilerFixture({available: false});
  const restored = f.owner.restoreEffectMaterials('original-materials', f.runDefinition, f.identity);
  assert.strictEqual(restored.prepared, f.prepared); assert.strictEqual(restored.compilation, f.compilation);
  assert.deepEqual(f.calls, ['wire-only']);
});

// Core already admitted the complete wire against this original compiler.
// The caller must preserve the exact returned pair without encoding it twice.
test('bound original Effect validation does not re-encode its Prepared materials', () => {
  const f = installedOriginalCompilerFixture({forbidProjection: true});
  const validated = f.validate();
  assert.deepEqual(validated, f.binding);
  assert.strictEqual(validated.updateTargetSelections, f.binding.updateTargetSelections);
  assert.strictEqual(validated.assertUpdateSelectionCurrent, f.binding.assertUpdateSelectionCurrent);
  assert.deepEqual(f.calls, ['same-original']);
  assert.equal(f.counts.bindings, 1, 'one original selection/current binding at the same boundary');
});

test('bound original Effect validation rejects a foreign Prepared despite equal selection DATA', () => {
  const f = installedOriginalCompilerFixture({forbidProjection: true});
  assert.throws(() => f.owner.validateRun({prepared: f.foreignPrepared, compilation: f.compilation,
    evidence: {updateTargetRunOriginal: f.original}, runDefinition: f.runDefinition, identity: f.identity}),
    {code: 'InstalledEffectOriginalSelectionChanged'});
  assert.equal(f.counts.bindings, 1);
});

// The existing embedded Host closure is extracted unchanged. Journal, codec
// and current/resource services are explicit ports, not ordinary admission.
function installedCaptureOriginalFixture({marked = true, live = true, bound = false, stop = true} = {}) {
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  let entry;
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'VariableDeclaration' && node.declarations.length === 1 &&
        node.declarations[0].id.name === 'recoverEffectCapture') {assert.equal(entry, undefined); entry = node;}
    for (const child of Object.values(node)) if (Array.isArray(child)) child.forEach(visit);
    else if (child && typeof child === 'object') visit(child);
  })(ast);
  assert(entry);
  const compilation = {}, requestIdentity = {}, runDefinition = {identity: 'original-run'}, ref = {runDefinitionCid: 'original-run'};
  const managed = live ? {definitionOriginal: {compilation}} : undefined, calls = [];
  const original = {}, allowed = {}, preparedEvidence = {}, authorizationEvidence = {};
  const evidence = {effectOriginalRunWire: 'original-wire', prepared: preparedEvidence, authorization: authorizationEvidence,
    ...(marked ? {updateTargetRunOriginal: original} : {})};
  const saved = {runDefinition, runAdmissionEvidence: evidence};
  const restored = {materials: {}, allowed};
  const moon = {clientSubmittedIntentRequestsCommitStop: () => stop,
    strategyRunEvidenceJson: value => value,
    clientProgramAllowedEffectRunPrepared: value => value === allowed ? preparedEvidence : undefined,
    clientProgramAllowedEffectRunAuthorization: value => value === allowed ? authorizationEvidence : undefined,
    strategyPublicationContractIdentity: value => value === definition ? runDefinition.identity : undefined,
    clientRequestRelation: (left, right) => left === requestIdentity && right === requestIdentity ? 1 : 0};
  const intent = {intent: {}, assertCurrent() {calls.push('intent-current');}};
  const prepared = {}, definition = {};
  if (managed !== undefined) {managed.prepared = prepared; Object.assign(managed.definitionOriginal,
    {prepared, identity: requestIdentity, allowed, definition});}
  const boundOriginal = {prepared, compilation, allowed, definition, runDefinition, identity: requestIdentity,
    materials: restored.materials, originalSubmittedIntent: intent};
  const ports = {moon, control: {}, namespaceId: 'scope', authorityScopeCid: 'authority', principalId: 'principal',
    localContractLimits: {}, journal: {
      lookupRunDefinition: () => ({requestId: 'original-request'}),
      originalSubmittedIntent(value) {assert.strictEqual(value, requestIdentity); return intent;}},
    store: {}, updateTargetOriginals: {
      restoreRun(value, definition, request, compiler) {
        assert.strictEqual(value, original); assert.strictEqual(definition, runDefinition);
        assert.strictEqual(request, requestIdentity); assert.strictEqual(compiler, live ? compilation : undefined);
        calls.push('target-original'); return restored;
      }, restoreEffectMaterials(wire, definition, request, compiler) {
        assert.equal(wire, 'original-wire'); assert.strictEqual(definition, runDefinition);
        assert.strictEqual(request, requestIdentity); assert.strictEqual(compiler, live ? compilation : undefined);
        calls.push('stop-original'); return restored;
      }},
    clientOperationError: code => Object.assign(new Error(code), {code}),
    preparation: {}, hostConnection: () => true, storeAuthorityCid: 'store',
    recoverAdmittedEffectRun(options) {return options.restoreOriginal(saved, requestIdentity);}};
  const recover = new Function(...Object.keys(ports), source.slice(entry.start, entry.end) + ';return recoverEffectCapture;')(...Object.values(ports));
  return {recover: () => recover(ref, undefined, managed, undefined, bound ? boundOriginal : undefined), managed, calls, restored, boundOriginal};
}

test('existing live capture recovery forwards its same retained compiler for target and stopped originals', () => {
  for (const marked of [true, false]) {
    const f = installedCaptureOriginalFixture({marked});
    assert.strictEqual(f.recover().allowed, f.restored.allowed);
    assert.deepEqual(f.calls, [marked ? 'target-original' : 'stop-original', 'intent-current']);
  }
});

test('existing capture recovery rejects missing live compiler instead of selecting wire-only restoration', () => {
  const f = installedCaptureOriginalFixture();
  delete f.managed.definitionOriginal.compilation;
  assert.throws(f.recover, {code: 'ForeignInstalledEffectManagedRun'});
  assert.deepEqual(f.calls, []);
});

test('independent cold capture original keeps its explicit wire-only qualification', () => {
  const f = installedCaptureOriginalFixture({live: false});
  assert.strictEqual(f.recover().allowed, f.restored.allowed);
  assert.deepEqual(f.calls, ['target-original', 'intent-current']);
});

test('ordinary hot Effect recovery borrows its same admitted tuple without a second material decoder', () => {
  const f = installedCaptureOriginalFixture({marked: false, stop: false});
  const result = f.recover();
  assert.strictEqual(result.allowed, f.managed.definitionOriginal.allowed);
  assert.strictEqual(result.prepared, f.managed.prepared);
  assert.strictEqual(result.compilation, f.managed.definitionOriginal.compilation);
  assert.strictEqual(result.definition, f.managed.definitionOriginal.definition);
  assert.deepEqual(f.calls, ['intent-current']);
});

test('ordinary hot Effect recovery refuses foreign original fields before Store recovery', () => {
  for (const field of ['prepared', 'identity', 'allowed', 'definition']) {
    const f = installedCaptureOriginalFixture({marked: false, stop: false});
    f.managed.definitionOriginal[field] = {};
    assert.throws(f.recover, {code: 'EffectRecoveryOriginalSelectionUnavailable'});
    assert.deepEqual(f.calls, []);
  }
});

function retainedRequestSourceMember(path, name, kind = 'Property') {
  const source = readFileSync(new URL(path, import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  let found;
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === kind && (node.key?.name ?? node.id?.name) === name) {
      assert.equal(found, undefined); found = node;
    }
    for (const child of Object.values(node)) if (Array.isArray(child)) child.forEach(visit);
    else if (child && typeof child === 'object') visit(child);
  })(tree);
  assert(found, name); return source.slice(found.start, found.end);
}

// Actual manager functions, with explicit Core/resource/current ports. No
// synthetic port here certifies native backing or an ordinary installation.
function retainedRequestManagerFixture({throwOnRetain = false, failure, missing = false, reentry = false,
  document, materialWire, missingMaterial = false, materialFailure = false, materialReentry = false} = {}) {
  const parent = {}, intent = {}, request = {}, originals = {}, receipts = new WeakMap(), producers = new Set();
  const requestProducers = new WeakMap(), calls = [], liveRuns = new Set(), counts = {current: 0};
  let reserved = false, materialReserved = false;
  const wire = document ?? JSON.stringify({kind: 'aql', input: {format: 'sql', text: "SELECT 'e\u0301😀'"}, parameters: null});
  const moon = {clientProgramRetainRequestSubmittedIntent(p, receipt, original) {
    assert.strictEqual(this, moon); assert.strictEqual(p, parent); assert.strictEqual(original, intent);
    assert.strictEqual(receipts.get(receipt).preparation.parent, parent);
    calls.push('retain-original');
    if (throwOnRetain) throw failure;
    reserved = true;
    if (reentry) receipts.get(receipt).finished = true;
    return ok(undefined);
  }, clientSubmittedIntentWire(original) {assert.strictEqual(this, moon); assert.strictEqual(original, intent); return wire;},
  clientProgramReserveRequestRetainedProgramMaterial(p, receipt, originalWire) {
    assert.strictEqual(this, moon); assert.strictEqual(p, parent);
    assert.strictEqual(receipts.get(receipt).preparation.parent, parent);
    assert.strictEqual(originalWire, materialWire); calls.push('reserve-material');
    if (materialFailure) throw failure;
    materialReserved = true;
    if (materialReentry) receipts.get(receipt).finished = true;
    return ok(undefined);
  }, clientProgramReserveRequestSnapshot(actualParent, receipt, units, values) {
    assert.strictEqual(this, moon);assert.strictEqual(actualParent,parent);
    assert.strictEqual(receipts.get(receipt).preparation.parent,parent);
    assert.equal(typeof units,'bigint');assert.equal(typeof values,'bigint');
    calls.push('reserve-snapshot');reserved=true;return ok();
  }};
  if (missing) delete moon.clientProgramRetainRequestSubmittedIntent;
  if (missingMaterial) delete moon.clientProgramReserveRequestRetainedProgramMaterial;
  const context = {runtime: moon}, ports = {closing: false, closed: false, originals, receipts, producers, liveRuns, snapshotClientRequest,
    requestProducers, callbacks: {preparationContext: () => context, validator() {}, retainedValidator() {}},
    current() {counts.current++;}, requestPreparationAvailable: () => true, assertRequestPreparationControl() {},
    retainSourceInitializationMaterial() {}, retireInitialPreparation() {},
    openRequestPreparation(state) {
      calls.push('open-parent'); state.parent = parent; state.original = {};
      // The actual selected method was captured before this original callback.
      moon.clientProgramRetainRequestSubmittedIntent = () => assert.fail('No late method lookup');
      moon.clientProgramReserveRequestRetainedProgramMaterial = () => assert.fail('No late material method lookup');
    },
    cleanupRequestInput(state) {assert.strictEqual(state.parent, parent); assert.equal(state.preparing, false);
      state.parent = state.original = undefined; calls.push('original-cleanup');},
    releaseFinishedProducer(producer) {assert.equal(producer.preparation, undefined); producers.delete(producer); calls.push('producer-return');},
    fail: code => {throw Object.assign(new Error(code), {code});}, checked, canonicalValueJson,
    JSON: {parse(value) {assert(reserved, 'same Request reservation BEFORE native decoding');
      if (value !== wire) assert(materialReserved, 'same Request material reservation BEFORE decoded originals');
      calls.push('decode'); return JSON.parse(value);}},
    freezeInput(value) {return Object.freeze(value);}};
  const code = 'const ' + retainedRequestSourceMember('./ordinary-source-managed.mjs', 'producerFor', 'VariableDeclarator') + ';' +
    retainedRequestSourceMember('./ordinary-source-managed.mjs', 'beginProducer', 'FunctionDeclaration') +
    ';const view = ({' + ['retainRequestInput','captureSourceSnapshot','bindSourceSnapshot','bindSourceRequest']
      .map(name => retainedRequestSourceMember('./ordinary-source-managed.mjs',name)).join(',') + '});return view;';
  const view = new Function(...Object.keys(ports), code)(...Object.values(ports));
  return {view, parent, intent, request, calls, receipts, producers, requestProducers, wire, counts};
}

test('retained manager decodes only after its same parent and keeps exact intent input aliases', () => {
  const f = retainedRequestManagerFixture(), result = f.view.retainRequestInput(f.request, f.intent);
  const producer = f.receipts.get(result.receipt);
  assert.deepEqual(f.calls, ['open-parent', 'retain-original', 'decode']);
  assert.equal(f.counts.current, 1, 'one current check at the shared producer entrance');
  assert.equal(result.body.input.text, "SELECT 'e\u0301😀'");
  assert.equal(Object.hasOwn(result.body, 'parameters'), true);
  assert.strictEqual(result.body.parameters, null, 'the actual native bridge recognizes literal null as absent, not undefined');
  assert.strictEqual(producer.body, result.body); assert.strictEqual(producer.preparation.snapshot, result.body);
  assert.equal(producer.preparation.snapshotDocument, f.wire); assert.equal(producer.preparation.preparing, false);
  assert.strictEqual(f.requestProducers.get(f.request).deref(), producer);
  assert.throws(() => f.view.retainRequestInput(f.request, f.intent), {code: 'ForeignInstalledSourceProducer'});
});

test('retained Program material keeps complete original field order after one same-parent quote', () => {
  const program = {version: 'actql/0.1', id: 'original', meta: {z: 'e\u0301\r\n😀', a: 'kept'}, stages: []};
  const parameters = {z: 'e\u0301\r\n😀', a: 1};
  const document = canonicalValueJson({kind: 'program', input: program, parameters}, {dataKeys: true});
  const materialWire = JSON.stringify({program_format: 'json', program: JSON.stringify(program),
    parameters: JSON.stringify(parameters)});
  const f = retainedRequestManagerFixture({document, materialWire});
  const retained = f.view.retainRequestInput(f.request, f.intent, undefined, materialWire);
  assert.deepEqual(Object.keys(retained.body.input), Object.keys(program));
  assert.deepEqual(Object.keys(retained.body.input.meta), ['z', 'a']);
  assert.deepEqual(Object.keys(retained.body.parameters), ['z', 'a']);
  assert.deepEqual(retained.body.input, program);
  assert.deepEqual(retained.body.parameters, parameters);
  assert.deepEqual(f.calls, ['open-parent', 'retain-original', 'decode', 'reserve-material', 'decode', 'decode', 'decode']);
  assert.equal(f.receipts.get(retained.receipt).preparation.snapshotDocument, document);
});

test('retained Program material cannot replace metadata Strings arrays or Parameters of the original intent', () => {
  const program = {version: 'actql/0.1', id: 'original', meta: {note: 'e\u0301\r\n'}, stages: [1, 2]};
  const parameters = {note: 'e\u0301\r\n'};
  const document = canonicalValueJson({kind: 'program', input: program, parameters}, {dataKeys: true});
  for (const [changedProgram, changedParameters] of [
    [{...program, meta: {note: 'é\n'}}, parameters],
    [{...program, meta: {}}, parameters],
    [{...program, stages: [2, 1]}, parameters],
    [program, {note: 'é\n'}],
  ]) {
    const materialWire = JSON.stringify({program_format: 'json', program: JSON.stringify(changedProgram),
      parameters: JSON.stringify(changedParameters)});
    const f = retainedRequestManagerFixture({document, materialWire});
    assert.throws(() => f.view.retainRequestInput(f.request, f.intent, undefined, materialWire),
      {code: 'ForeignInstalledSourceProducer'});
    assert.equal(f.requestProducers.has(f.request), false);
    assert.equal(f.producers.size, 0);
    assert.deepEqual(f.calls.slice(-2), ['original-cleanup', 'producer-return']);
  }
});

test('retained Program material preserves missing backing and thrown undefined before its original decoder', () => {
  const document = canonicalValueJson({kind: 'program', input: {id: 'p'}, parameters: null}, {dataKeys: true});
  const materialWire = JSON.stringify({program_format: 'json', program: '{"id":"p"}', parameters: null});
  const missing = retainedRequestManagerFixture({document, materialWire, missingMaterial: true});
  assert.throws(() => missing.view.retainRequestInput(missing.request, missing.intent, undefined, materialWire),
    {code: 'NodeManagedRunRuntimeUnavailable'});
  assert.equal(missing.calls.filter(value => value === 'decode').length, 1);
  const f = retainedRequestManagerFixture({document, materialWire, materialFailure: true, failure: undefined});
  let threw = false;
  try {f.view.retainRequestInput(f.request, f.intent, undefined, materialWire);}
  catch (cause) {threw = true; assert.strictEqual(cause, undefined);}
  assert.equal(threw, true);
  assert.equal(f.calls.filter(value => value === 'decode').length, 1);
  assert.deepEqual(f.calls.slice(-2), ['original-cleanup', 'producer-return']);
});

test('retained Program material fences original retirement during its capacity callback before decoding', () => {
  const document = canonicalValueJson({kind: 'program', input: {id: 'p'}, parameters: null}, {dataKeys: true});
  const materialWire = JSON.stringify({program_format: 'json', program: '{"id":"p"}', parameters: null});
  const f = retainedRequestManagerFixture({document, materialWire, materialReentry: true});
  assert.throws(() => f.view.retainRequestInput(f.request, f.intent, undefined, materialWire),
    {code: 'ForeignInstalledSourceProducer'});
  assert.equal(f.calls.filter(value => value === 'decode').length, 1);
  assert.deepEqual(f.calls, ['open-parent', 'retain-original', 'decode', 'reserve-material',
    'original-cleanup', 'producer-return']);
  assert.equal(f.requestProducers.has(f.request), false);
  assert.equal(f.producers.size, 0);
});

test('retained textual Source keeps its original frontend and never decodes the lowered Program material', () => {
  const f = retainedRequestManagerFixture({materialWire: 'not decoded', missingMaterial: true});
  const retained = f.view.retainRequestInput(f.request, f.intent, undefined, 'not decoded');
  assert.equal(retained.body.kind, 'aql');
  assert.deepEqual(f.calls, ['open-parent', 'retain-original', 'decode']);
});

test('retained manager preserves thrown undefined and returns the original failed constructor', () => {
  const f = retainedRequestManagerFixture({throwOnRetain: true, failure: undefined});
  let threw = false;
  try {f.view.retainRequestInput(f.request, f.intent);} catch (cause) {threw = true; assert.strictEqual(cause, undefined);}
  assert(threw); assert.deepEqual(f.calls, ['open-parent', 'retain-original', 'original-cleanup', 'producer-return']);
  assert.equal(f.producers.size, 0); assert.equal(f.requestProducers.has(f.request), false);
});

test('retained manager fences same-original retirement before native decode', () => {
  const f = retainedRequestManagerFixture({reentry: true});
  assert.throws(() => f.view.retainRequestInput(f.request, f.intent), {code: 'ForeignInstalledSourceProducer'});
  assert.deepEqual(f.calls, ['open-parent', 'retain-original', 'original-cleanup', 'producer-return']);
});

function retainedEffectPreparationFixture({marked = true, constructorFailure = false, failure} = {}) {
  const prepared = {}, compilation = {}, identity = {}, allowed = {}, definition = {}, intent = {};
  const ref = {runDefinitionCid: 'original-run'}, runDefinition = {identity: ref.runDefinitionCid};
  const preparedEvidence = {}, authorization = {}, calls = [], original = {};
  const evidence = {prepared: preparedEvidence, authorization,
    ...(marked ? {updateTargetRunOriginal: original} : {effectOriginalRunWire: 'original-wire'})};
  const restored = {prepared, compilation, allowed, definition,
    assertUpdateSelectionCurrent() {calls.push('selection-current');}};
  const retained = {ref, runDefinition, runAdmissionEvidence: evidence,
    physicalStartReserved: true, cancellationRequested: true, observedTerminalOutcome: 'failed'};
  const originalSubmittedIntent = {intent, assertCurrent() {calls.push('intent-current');}};
  const ports = {journal: {resolveDefinition(request, scope) {assert.strictEqual(request, identity);
    assert.deepEqual(scope, {namespaceId: 'original-namespace'}); calls.push('original-journal'); return retained;}},
    moon: {clientSubmittedIntentEffectCompatible(i, p) {assert.strictEqual(i, intent); return p === prepared;},
      strategyRunEvidenceJson: value => value,
      clientProgramAllowedEffectRunPrepared: () => preparedEvidence,
      clientProgramAllowedEffectRunAuthorization: () => authorization}, control: {},
    compile(p) {assert.strictEqual(p, prepared); calls.push('compile-once'); return compilation;},
    queryTimeRequired: () => false, restoreQueryTime: () => ({}), inferPlanFor: () => undefined,
    updateTargetOriginals: {restoreRun(value, d, r, c) {
      assert.strictEqual(value, original); assert.strictEqual(d, runDefinition);
      assert.strictEqual(r, identity); assert.strictEqual(c, compilation); calls.push('same-original'); return restored;
    }, restoreEffectMaterials(wire, d, r, c) {
      assert.equal(wire, 'original-wire'); assert.strictEqual(d, runDefinition);
      assert.strictEqual(r, identity); assert.strictEqual(c, compilation); calls.push('same-stop-original'); return restored;
    }},
    prepareDefinition(facts) {assert(Object.isFrozen(facts));
      for (const key of ['prepared', 'identity', 'compilation', 'allowed', 'definition', 'queryTimePreparation', 'modelCompiled']) assert(Object.hasOwn(facts, key), key);
      assert.strictEqual(facts.prepared, prepared); assert.strictEqual(facts.compilation, compilation);
      assert.strictEqual(facts.identity, identity); calls.push('original-constructor');
      if (constructorFailure) throw failure;},
    denied: () => Object.assign(new Error('ClientEffectRunDenied'), {code: 'ClientEffectRunDenied'})};
  const owner = new Function(...Object.keys(ports), 'return ({' + retainedRequestSourceMember('./client-effect-run.mjs', 'restoreRetainedPreparation') + '});')(...Object.values(ports));
  return {owner, calls, prepared, compilation, identity, ref, originalSubmittedIntent,
    restore() {return owner.restoreRetainedPreparation({prepared, identity, namespaceId: 'original-namespace', ref, originalSubmittedIntent});}};
}

test('retained Effect restores only the original resource constructor for target and stop material', async () => {
  for (const marked of [true, false]) {
    const f = retainedEffectPreparationFixture({marked}), facts = await f.restore();
    assert.strictEqual(facts.prepared, f.prepared); assert.strictEqual(facts.compilation, f.compilation);
    assert.strictEqual(facts.identity, f.identity); assert.equal(Object.hasOwn(facts, 'owner'), false, 'no execution Owner');
    assert.deepEqual(f.calls, ['original-journal', 'intent-current', 'compile-once',
      marked ? 'same-original' : 'same-stop-original', 'original-constructor', 'intent-current', 'selection-current']);
  }
});

test('retained Effect constructor failure stays original without a fresh Run or fallback', async () => {
  const f = retainedEffectPreparationFixture({constructorFailure: true, failure: undefined});
  let threw = false;
  try {await f.restore();} catch (cause) {threw = true; assert.strictEqual(cause, undefined);}
  assert(threw); assert.deepEqual(f.calls, ['original-journal', 'intent-current', 'compile-once', 'same-original', 'original-constructor']);
});

function retainedHostPreparationFixture({reuse = false, failPrepare = false, cleanupFailure = false, material = true, target = true} = {}) {
  const ref = {runDefinitionCid: 'original-ref'}, identity = {}, prepared = {}, managed = {}, intent = {}, originalBinding = {};
  const runDefinition = {identity: ref.runDefinitionCid}, calls = [];
  const materialWire = 'same Journal-retained complete material';
  const originalSubmittedIntent = {intent, assertCurrent() {calls.push('intent-current');}};
  let request;
  const prepareSubmit = async value => {assert.strictEqual(value, request); calls.push('same-request-check'); if (failPrepare) throw undefined; return prepared;};
  prepareSubmit.assertSubmittedIntent = (p, i) => {assert.strictEqual(p, prepared); assert.strictEqual(i, intent);};
  prepareSubmit.kindOf = p => {assert.strictEqual(p, prepared); return 'effectful';};
  const ports = {moon: {clientProgramEffectInferOccurrence: () => undefined}, control: {}, namespaceId: 'namespace',
    authorityScopeCid: 'authority', journal: {
      lookupRunDefinition: value => {assert.strictEqual(value, ref); return {requestId: 'original-request'};},
      lookupOwnedDefinition: key => {assert.equal(key.requestId, 'original-request'); return {requestIdentity: identity,
        runDefinition, runAdmissionEvidence: material ? target
          ? {updateTargetRunOriginal: {materialsWire: materialWire}} : {effectOriginalRunWire: materialWire} : {}};},
      originalSubmittedIntent: value => {assert.strictEqual(value, identity); calls.push('original-intent'); return originalSubmittedIntent;}},
    preparation: {retainedEffectManagedPlan: () => reuse ? managed : undefined,
      retainEffectRequestInput(runtime, value, original, captured, wire) {
        assert.strictEqual(runtime, ports.moon); assert.strictEqual(original, intent); request = value;
        assert.strictEqual(captured, undefined); assert.strictEqual(wire, materialWire);
        assert.equal(request.requestId, 'original-request'); calls.push('same-parent-input');
        return {finish(terminal) {calls.push(`finish-${terminal}`); if (cleanupFailure) throw new Error('OriginalCleanupPending');}};
      }, bindSourceRequest(parent, child) {assert.strictEqual(parent, request); assert.strictEqual(child, prepared); calls.push('bind-original-alias');},
      effectManagedPlanRun(runtime, p, original) {assert.strictEqual(runtime, ports.moon); assert.strictEqual(p, prepared);
        assert.strictEqual(original, identity); calls.push('same-adopted-plan'); return managed;}},
    prepareSubmit,
    effectRun: {async restoreRetainedPreparation(facts) {
      assert.strictEqual(facts.prepared, prepared); assert.strictEqual(facts.identity, identity);
      assert.strictEqual(facts.ref, ref); assert.strictEqual(facts.originalSubmittedIntent, originalSubmittedIntent);
      calls.push('same-original-constructor'); return originalBinding;
    }},
    clientOperationError: code => Object.assign(new Error(code), {code})};
  const source = retainedRequestSourceMember('./embedded-local.mjs', 'restoreEffectManagedPreparation', 'VariableDeclarator');
  const restore = new Function(...Object.keys(ports), 'const ' + source + ';return restoreEffectManagedPreparation;')(...Object.values(ports));
  return {restore: () => restore(ref), calls, managed, originalBinding};
}

test('retained Host binds the Journal Request directly through one checked preparation and original Plan', async () => {
  for (const target of [true, false]) {
    const f = retainedHostPreparationFixture({target}), result = await f.restore();
    assert.strictEqual(result.managedEffect, f.managed); assert.strictEqual(result.original, f.originalBinding);
    assert.deepEqual(f.calls, ['original-intent', 'intent-current', 'same-parent-input', 'same-request-check',
      'bind-original-alias', 'same-original-constructor', 'same-adopted-plan', 'finish-returned']);
  }
  const reused = retainedHostPreparationFixture({reuse: true});
  assert.strictEqual((await reused.restore()).managedEffect, reused.managed); assert.deepEqual(reused.calls, []);
});

test('retained Host preserves primary undefined and leaves failed cleanup with the original input', async () => {
  const f = retainedHostPreparationFixture({failPrepare: true, cleanupFailure: true});
  let threw = false; try {await f.restore();} catch (cause) {threw = true; assert.strictEqual(cause, undefined);}
  assert(threw); assert.deepEqual(f.calls, ['original-intent', 'intent-current', 'same-parent-input', 'same-request-check', 'finish-failed']);
});

test('retained Host reuses its live Plan without cold material and refuses missing cold evidence before construction', async () => {
  const live = retainedHostPreparationFixture({reuse: true, material: false});
  assert.strictEqual((await live.restore()).managedEffect, live.managed);
  assert.deepEqual(live.calls, []);
  const cold = retainedHostPreparationFixture({material: false});
  await assert.rejects(cold.restore(), {code: 'EffectRecoveryOriginalSelectionUnavailable'});
  assert.deepEqual(cold.calls, []);
});

function ordinaryEffectDefinitionFixture({target = false, stop = false} = {}) {
  const prepared = {}, identity = {}, compilation = {}, allowed = {}, definition = {}, targetOriginal = {};
  const calls = [], runDefinition = {identity: 'original-definition'}, wire = 'original-full-materials';
  const moon = {
    clientProgramIssueAllowedEffectRun(c) {assert.strictEqual(c, compilation); return ok(allowed);},
    clientProgramIssueEffectRunDefinition(a) {assert.strictEqual(a, allowed); return ok(definition);},
    clientProgramEffectRunStartCurrent(a, d) {assert.strictEqual(a, allowed); assert.strictEqual(d, definition); return true;},
    strategyPublicationContractJson: d => {assert.strictEqual(d, definition); return 'original-definition-wire';},
    clientProgramEffectCompilationResultNames: c => {assert.strictEqual(c, compilation); return ['answer'];},
    clientProgramAllowedEffectRunPrepared: a => {assert.strictEqual(a, allowed); return 'prepared-evidence';},
    clientProgramAllowedEffectRunAuthorization: a => {assert.strictEqual(a, allowed); return 'authorization-evidence';},
    strategyRunEvidenceJson: value => value,
  };
  const ports = {moon, checked, prepared, identity, limits: {}, requiresQueryTime: false, requestedStop: stop,
    assertRequestedStopAvailable() {calls.push('requested-stop');},
    policy: {createdAt: 'original-time', expiresAt: 'original-expiry'}, namespaceId: 'original-scope',
    randomUUID: () => 'original-run', now: () => 'current-time', expired: () => new Error('expired'),
    compiled: () => compilation, contentPolicies: new WeakMap(), resultPolicyOriginalFor: undefined,
    inferPlanFor: undefined, control: {admit(kind, original) {
      assert.equal(kind, 'run_definition'); assert.equal(original, 'original-definition-wire'); return runDefinition;
    }}, updateTargetOriginals: {captureRun(facts) {
      assert.strictEqual(facts.prepared, prepared); assert.strictEqual(facts.allowed, allowed);
      assert.strictEqual(facts.definition, definition); assert.strictEqual(facts.identity, identity);
      calls.push('capture-target'); return target ? targetOriginal : undefined;
    }, captureEffectMaterials(facts) {
      assert.strictEqual(facts.allowed, allowed); assert.strictEqual(facts.definition, definition);
      assert.strictEqual(facts.identity, identity); calls.push('capture-full-original'); return wire;
    }}, prepareDefinition(facts) {
      assert.strictEqual(facts.prepared, prepared); assert.strictEqual(facts.compilation, compilation);
      assert.strictEqual(facts.identity, identity); calls.push('same-parent-constructor');
    }};
  const body = retainedRequestSourceMember('./client-effect-run.mjs', 'issueDefinition');
  const owner = new Function(...Object.keys(ports), 'return ({' + body + '});')(...Object.values(ports));
  return {issue: () => owner.issueDefinition(), wire, targetOriginal, runDefinition, calls};
}

test('ordinary Effect approval retains full original materials without an explicit commit stop', async () => {
  const f = ordinaryEffectDefinitionFixture(), issued = await f.issue();
  assert.strictEqual(issued.runDefinition, f.runDefinition);
  assert.equal(issued.runAdmissionEvidence.effectOriginalRunWire, f.wire);
  assert.deepEqual(f.calls, ['capture-target', 'capture-full-original', 'same-parent-constructor']);
});

test('ordinary Effect target custody keeps its one original codec and requested stop still retains its materials', async () => {
  const target = ordinaryEffectDefinitionFixture({target: true}), targeted = await target.issue();
  assert.strictEqual(targeted.runAdmissionEvidence.updateTargetRunOriginal, target.targetOriginal);
  assert.equal(Object.hasOwn(targeted.runAdmissionEvidence, 'effectOriginalRunWire'), false);
  assert.deepEqual(target.calls, ['capture-target', 'same-parent-constructor']);
  const stop = ordinaryEffectDefinitionFixture({stop: true}), stopped = await stop.issue();
  assert.equal(stopped.runAdmissionEvidence.effectOriginalRunWire, stop.wire);
  assert.deepEqual(stop.calls, ['requested-stop', 'capture-target', 'capture-full-original', 'same-parent-constructor']);
});

test('existing whole Effect resume forwards the same restored Plan before recovering its capture', async () => {
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  let entry;
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key?.name === 'run' &&
        source.slice(node.start, node.end).includes('restored = await restoreEffectManagedPreparation(ref, signal)')) {
      assert.equal(entry, undefined); entry = node.value;
    }
    for (const child of Object.values(node)) if (Array.isArray(child)) child.forEach(visit);
    else if (child && typeof child === 'object') visit(child);
  })(tree);
  assert(entry);
  const ref = {}, managed = {}, signal = {}, original = {}, retainer = () => {}, calls = [];
  const ports = {ref, view: {}, observation: undefined, observing: false, continuation: {}, retained: {}, moon: {}, control: {},
    store: {}, principalId: 'principal', storeAuthorityCid: 'store', authorityScopeCid: 'authority', runContent: {},
    checkpoints: {journal: {}, binding: {}, effectAuthorization: {}},
    restoreEffectManagedPreparation: async (r, s) => {assert.strictEqual(r, ref); assert.strictEqual(s, signal); calls.push('prepare'); return {managedEffect: managed, original};},
    effectInstallation: {async resume(facts) {assert.strictEqual(facts.managedEffect, managed); calls.push('resume');
      return facts.recoverCapture({signal, retainRecoveryResources: retainer});}},
    recoverEffectCapture(r, s, parent, retain, binding) {assert.strictEqual(r, ref); assert.strictEqual(s, signal);
      assert.strictEqual(parent, managed); assert.strictEqual(binding, original); assert.strictEqual(retain, retainer); calls.push('same-parent-capture'); return 'original-capture';},
    effectRun: {}, journal: {}};
  const run = new Function(...Object.keys(ports), 'return (' + source.slice(entry.start, entry.end) + ');')(...Object.values(ports));
  assert.equal(await run({signal, retainExecution() {}, beginPhysicalWork() {}}), 'original-capture');
  assert.deepEqual(calls, ['prepare', 'resume', 'same-parent-capture']);
});

test('bound recovery original is carried once without a second material codec or compiler', () => {
  const f = installedCaptureOriginalFixture({bound: true});
  assert.strictEqual(f.recover(), f.boundOriginal);
  assert.deepEqual(f.calls, ['intent-current']);
});

test('bound recovery original cannot replace the same managed Request or compiler', () => {
  for (const field of ['identity', 'compilation']) {
    const f = installedCaptureOriginalFixture({bound: true}); f.boundOriginal[field] = {};
    assert.throws(f.recover, {code: 'EffectRecoveryOriginalSelectionUnavailable'});
    assert.deepEqual(f.calls, []);
  }
});

test('retained Plan lookup keeps partial failure and fences original retirement without a new selection', () => {
  const request = {}, definition = {identity: 'original-run'}, originalDefinition = {};
  const run = {preparationKind: 'effect-plan', runtime: undefined, request,
    definitionOriginal: {definition: originalDefinition}, closed: false};
  const record = {computeLiveRuns: new Set([run])};
  const runtime = {clientRequestRelation: (left, right) => left === right ? 1 : 0,
    strategyPublicationContractIdentity: value => {assert.strictEqual(value, originalDefinition); return definition.identity;}};
  run.runtime = runtime;
  let retireDuringRead = false, reads = 0;
  const ports = {moon: runtime, record, preparation: {effectManagedPlanRun() {
    reads++; if (retireDuringRead) {run.closed = true; record.computeLiveRuns.delete(run);} return run;
  }}, clientOperationError: code => Object.assign(new Error(code), {code})};
  const owner = new Function(...Object.keys(ports), 'return ({' + retainedRequestSourceMember('./embedded-local.mjs', 'retainedEffectManagedPlan') + '});')(...Object.values(ports));
  assert.strictEqual(owner.retainedEffectManagedPlan(runtime, request, definition), run); assert.equal(reads, 1);
  run.failure = undefined;
  let threw = false; try {owner.retainedEffectManagedPlan(runtime, request, definition);} catch (cause) {threw = true; assert.strictEqual(cause, undefined);}
  assert(threw); assert.equal(reads, 1);
  delete run.failure; retireDuringRead = true;
  assert.throws(() => owner.retainedEffectManagedPlan(runtime, request, definition), {code: 'ForeignInstalledEffectManagedRun'});
  assert.equal(reads, 2);
});

test('Local signing original uses the same restored parent and keeps its borrow through consumption', async () => {
  const source = retainedRequestSourceMember('./embedded-local.mjs', 'loadRunOriginal');
  const managed = {}, original = {}, materials = {}, requestIdentity = {}, invocation = {}, preview = {};
  const runDefinition = {wire: 'original-definition'}, retained = {runDefinition, revision: 2, cancellationRequested: false};
  const recovered = {materials, requestIdentity, originalSubmittedIntent: {referenceWire: 'original-reference', assertCurrent() {}},
    computation: {preview, invocation}, assertUpdateSelectionCurrent() {}};
  const calls = [], recoveries = new Set(); let consuming = false, stale;
  const ports = {namespaceId: 'namespace', authorityScopeCid: 'authority', moon: {}, control: {
    effectComputationPreviewSemanticCid: value => {assert.strictEqual(value, preview); return 'preview-cid';}},
    journal: {lookupRunDefinition: () => retained},
    restoreEffectManagedPreparation: async () => {calls.push('same-parent'); return {managedEffect: managed, original};},
    recoverEffectCapture(ref, signal, parent, retain, binding) {assert.strictEqual(parent, managed); assert.strictEqual(binding, original); calls.push('capture'); return recovered;},
    localSigningRecoveries: recoveries, assertProjectRuntime() {}, preparation: {assertResultPublicationCurrent() {}},
    clientOperationError: code => Object.assign(new Error(code), {code}),
    async releaseLocalSigningRecovery(value) {assert.strictEqual(value, recovered); assert.equal(consuming, false); calls.push('release-original'); recoveries.delete(value);}};
  const owner = new Function(...Object.keys(ports), 'return ({' + source + '});')(...Object.values(ports));
  const result = await owner.loadRunOriginal({runDefinitionCid: 'original-run', requiredArtifact: {cid: 'preview-cid'}}, undefined, async frame => {
    assert(recoveries.has(recovered)); assert.strictEqual(frame.materials, materials); assert.strictEqual(frame.requestIdentity, requestIdentity);
    assert.strictEqual(frame.invocation, invocation); stale = frame.assertCurrent; frame.assertCurrent();
    consuming = true; await Promise.resolve(); assert(recoveries.has(recovered)); consuming = false; calls.push('consume'); return 'signed';
  });
  assert.equal(result, 'signed'); assert.deepEqual(calls, ['same-parent', 'capture', 'consume', 'release-original']);
  assert.equal(recoveries.size, 0); assert.throws(stale, {code: 'LocalSigningOriginalConflict'});
});

test('whole Effect target refresh validates the captured Prepared against its existing Plan without reprepare', async () => {
  const source = retainedRequestSourceMember('./embedded-local.mjs', 'prepareTargetReads');
  const prepared = {}, compilation = {}, identity = {}, originalPrepared = {}, ref = {};
  const facts = {prepared, compilation, identity}, reads = {}, calls = [], effectSubmissions = new WeakMap();
  const managedEffect = {definitionOriginal: {prepared, compilation, identity}};
  const submission = {requestId: 'original-request', kind: 'program', input: {}, updateTargetPreparedOriginal: originalPrepared};
  const ports = {view: {runId: 'original-run'}, ref, signal: undefined, continuation: {}, managedEffect,
    retained: {requestId: 'original-request'}, restored: {original: facts}, effectSubmissions,
    checkpoints: {inspectEffectTargetApprovals: async () => [{continuation: {submission}}], journal: {admitResume() {return true;}}},
    updateTargetOriginals: {validatePreparedOriginal(p, c, value) {assert.strictEqual(p, prepared); assert.strictEqual(c, compilation);
      assert.strictEqual(value, originalPrepared); calls.push('same-static-original');}},
    assertEffectTargetReadBinding() {assert.fail('No copied binding is invented');},
    openEffectTargetReads: async (value, options) => {assert.strictEqual(value, facts); assert.equal(options.allowDefer, false);
      calls.push('same-plan-reads'); return reads;}};
  const owner = new Function(...Object.keys(ports), 'return ({' + source + '});')(...Object.values(ports));
  assert.strictEqual(await owner.prepareTargetReads({claim: {}}), reads);
  assert.deepEqual(calls, ['same-static-original', 'same-plan-reads']);
  assert.equal(effectSubmissions.get(prepared).requestId, 'original-request');
  assert.equal(Object.hasOwn(effectSubmissions.get(prepared), 'preparedProgram'), false);
});

test('retained manager captures held input through the same funded snapshot without issuing an intent', () => {
  const f=retainedRequestManagerFixture(),captured=Object.freeze({kind:'program',
    input:Object.freeze({version:'actql/0.1',id:'e\u0301😀'}),requestId:'same-held-request'});
  const retained=f.view.retainRequestInput(f.request,undefined,captured);
  const producer=f.receipts.get(retained.receipt);
  assert.equal(f.calls[0],'open-parent');assert(f.calls.includes('reserve-snapshot'));
  assert.equal(f.calls.includes('retain-original'),false);assert.equal(f.calls.includes('decode'),false);
  assert.notEqual(retained.body,captured);assert.equal(retained.body.input.id,'e\u0301😀');
  assert.equal(Object.isFrozen(retained.body),true);assert.equal(Object.hasOwn(retained.body,'parameters'),false);
  assert.equal(producer.body,retained.body);assert.equal(producer.preparation.snapshot,retained.body);
  assert.equal(f.requestProducers.get(f.request).deref(),producer);
  assert.throws(()=>f.view.retainRequestInput(f.request,undefined,captured),{code:'ForeignInstalledSourceProducer'});
});

test('retained manager refuses ambiguous captured and typed intent inputs before opening a parent', () => {
  for(const missing of [false,true]){
    const f=retainedRequestManagerFixture();
    assert.throws(()=>f.view.retainRequestInput(f.request,missing?undefined:f.intent,
      missing?undefined:Object.freeze({kind:'program',input:{}})),{code:'ForeignInstalledSourceProducer'});
    assert.deepEqual(f.calls,[]);
  }
});
