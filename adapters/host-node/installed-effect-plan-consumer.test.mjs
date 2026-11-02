import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {prepareInstalledEffectManagedPlanRun, readInstalledEffectManagedPlanRun}
  from './installed-effect-managed-run.mjs';
import {bindInstalledManagedSources} from './installed-managed-source.mjs';
import {selectAcquiredEffectSources, selectAcquiredEffectPlanInputs} from './acquired-effect-sources.mjs';
import {openAcquiredEffectComputation} from './acquired-effect-computation.mjs';
import {prepareInstalledRowCaptureChild} from './installed-row-capture-cleanup.mjs';

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
