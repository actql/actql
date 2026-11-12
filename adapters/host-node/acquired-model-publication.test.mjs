import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {runtimeField, runtimeOptionalField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {withOriginalInferModelObservation} from './infer-effect-observation.mjs';
import {preparePrivatePublicationHolding as originalPrivateHolding} from '../host-common/private-publication-holding.mjs';

// Actual publication functions with explicit typed Core/Store-plan ports.
// No runtime source overlay, installed package, real Model or authority claim.
const text=readFileSync(new URL('./local-values-plan.mjs',import.meta.url),'utf8');
const declarations=parse(text,{ecmaVersion:'latest',sourceType:'module'}).body;
const body=name=>{
  const node=declarations.find(node=>node.declaration?.id?.name===name)?.declaration;
  assert.ok(node);return text.slice(node.start,node.end);
};
const limits={maxWireBytes:16384,maxNodes:1024,maxDepth:20};

const groupText = readFileSync(new URL('./acquired-effect-computation.mjs', import.meta.url), 'utf8');
const groupNode = parse(groupText, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .find(node => node.id?.name === 'acquiredEffectModelGroup');
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => {resolve = yes; reject = no;});
  return {promise, resolve, reject};
};
const turn = () => new Promise(resolve => setImmediate(resolve));

// Actual group custody with explicit nominal publication/Store ports. The
// deferred preparation is not an installed Model, Core ABI or physical ACK.
function publicationGroupFixture({prepare, commit, faultInjection, releaseBinding, retireCapture,
  store, holdingFactory, originalNames = false, inferEvidence, project, unitPreparation} = {}) {
  const events = [], contexts = [], preparedOptions = [], funding = [], controller = new AbortController();
  const sourcePlan = {}, preparedProgram = {}, plan = {compiled: {}, runDefinition: {}}, issuance = {};
  const publication = {binding: {}, observation: {name: 'observation', wire: '{}', identity: 'observation'},
    invocation: {name: 'invocation', wire: '{}', identity: 'invocation'}, plan: {}};
  if (originalNames) {
    publication.observation.name = 'observation_set';
    publication.invocation.name = 'run_invocation';
  }
  let current = true;
  const selections = Object.freeze([0, 1].map(index => Object.freeze({graph: {index}, occurrence: {index},
    observeAccount: () => ({})})));
  const components = selections.map((selection, index) => ({bindOriginal(context) {contexts[index] = context;}, hasFailure: () => false, failure: () => undefined}));
  const originalPreparation = {components: selections.map((selection, index) => ({selection, component: components[index]}))};
  const operations = selections.map((_, index) => ({index, physicalStopped: () => true,
    evaluationRequest: () => ({_0: {index}, _1: '{}', _2: '{}'}),
    growOriginalPublicationCapacity(retained, execution) {funding.push({owner: index, retained, execution});},
    releaseOriginalPublicationCapacity() {events.push('release-capacity'); return true;}}));
  const acquired = {definition: {identity: 'same-definition', separatelyAdmitted: true}, compilation: {}, prepared: {}, control: {runDefinitionRunId: () => 'component',
    admitComposedInferSources: () => ({}), composedInferSourcesFor: () => undefined,
    modelPrivateHoldingCid: () => 'holding'}};
  const moon = {clientProgramAdvanceInferObservationIssuance: actual => {
    assert.strictEqual(actual, issuance); return {$tag: 1, _0: {_0: true}};
  }, clientProgramReleaseInferInvocationBinding(actual) {
    assert.strictEqual(actual, publication.binding);
    events.push('release-attempt');
    const released = releaseBinding === undefined ? true : releaseBinding(actual);
    if (released) events.push('release-binding');
    return released;
  }, clientProgramCancelInferObservationIssuance: () => false,
  clientProgramEffectComposedModelKeyedAcquisition: () => ({$tag: 1, _0: undefined})};
  moon.clientProgramCleanupInferObservationIssuance = () => ({$tag: 1, _0: true});
  moon.clientProgramInferPlanBoundary = graph => ({_0: graph.index});
  const host = {}, unit = {value: {}}, sourceUnits = {byUnit: new Map([[0, unit]])};
  moon.clientProgramInferOccurrenceCoordinates = occurrence => ({_0: occurrence.index, _1: occurrence.index + 1, _2: 0});
  moon.clientProgramInferOccurrenceResultImports = () => [{_0: 0, _1: 'joined'}];
  moon.clientProgramLocalEffectHostRun = actual => {assert.strictEqual(actual, host); return host;};
  moon.clientProgramRetireInstalledEffectCapturedConsumers = () => ({$tag: 1, _0: undefined});
  acquired.control.prepareOriginalEffectSourceUnitResults = async (...args) => {
    assert.strictEqual(args[6], plan.runDefinition, 'use the retained Plan definition view, not the separate Journal admission');
    const retained = args[8];
    retained.pins = {}; events.push('prepare-unit');
    await unitPreparation({retained, current: args[9]});
    retained.artifacts.push({name: 'joined', artifact: {}}); retained.manifest = {};
  };
  acquired.control.retireOriginalEffectUnitResults = retained => {
    events.push('retire-unit'); retained.pins = undefined; return true;
  };
  moon.clientProgramModelRequestInputFrameGeometry = (request, maximum) => {
    assert.equal(maximum, 65536);
    return {$tag: 1, _0: {request}};
  };
  moon.clientProgramEffectModelEvidenceCopyCapacity = (bytes, nodes, depth, shape, text, calls) => {
    assert.equal(bytes, 15); assert.equal(nodes, 2); assert.equal(depth, 1);
    assert.equal(text, 6); assert.equal(calls, 1);
    return {$tag: 1, _0: {_0: shape.request.index === 0 ? 100n : 50n,
      _1: shape.request.index === 0 ? 200n : 80n}};
  };
  const ports = {runtimeField, checked, localContractLimits: limits,
    prepareAcquiredEffectSourceUnits: () => sourceUnits,
    async projectInferEvidence(facts) {
      events.push('evidence-' + facts.operation.index);
      assert.strictEqual(facts.configuration, inferEvidence);
      assert.strictEqual(facts.preparedProgram, preparedProgram);
      assert.strictEqual(facts.plan, plan);
      assert.strictEqual(facts.control, acquired.control);
      assert.strictEqual(facts.selected, selections[facts.operation.index]);
      assert.equal(typeof facts.current, 'function'); facts.current();
      await project?.(facts);
    },
    startCompleteInferObservation({operations: originals}) {
      assert.deepEqual(originals, operations); return issuance;
    }, openNodeInferCaptureCustody({operation}) {
      return {retainCompleted: () => true, completedCallCount: () => 1, modelEvidence: () => [],
        async persist() {events.push('capture-' + operation.index);}, custody: {
          retirePublication: async () => retireCapture === undefined ? true : retireCapture(operation.index),
          close: async () => true, cleanupPending: () => false}};
    }, preparePrivatePublicationHolding(store, original) {
      events.push('holding-' + original.name);
      if (holdingFactory !== undefined) return holdingFactory(store, original);
      return {async commit() {events.push('commit-' + original.name); await commit?.(original);},
        async abort() {events.push('abort-' + original.name); return true;}};
    }, async acquiredInferEffectPublicationPlan(options) {
      events.push('prepare');
      preparedOptions.push(options);
      options.retainBinding(publication.binding);
      return prepare === undefined ? publication : prepare(publication);
    }};
  const create = new Function(...Object.keys(ports), `return (${groupText.slice(groupNode.start, groupNode.end)});`)(...Object.values(ports));
  const group = create({moon, acquired, infer: {components: selections}, originalModelComponents: components,
    preparedProgram, inferEvidence,
    originalModelSelection: {components: selections}, originalPreparation, plan, sourcePlan,
    signal: controller.signal, modelController: {}, faultInjection, store, originalHost: () => host,
    current() {if (!current) throw new Error('OriginalCurrentLost');}});
  group.bind({captures: unitPreparation === undefined ? [{}] : [{}, {}], evidence: unitPreparation === undefined ? [{}] : [{}, {}], captureStartedAt: 'start', captureCompletedAt: 'end'});
  for (const [index, context] of contexts.entries()) context.retainOperation(operations[index]);
  for (const context of contexts) assert.equal(context.retainCompleted(), true);
  return {group, moon, events, contexts, publication, preparedOptions, funding, sourcePlan, signal: controller.signal, operations, cancel: () => controller.abort(new Error('OriginalCancelled')),
    revoke() {current = false;}};
}

test('plural publication shares the pending preparation and commits only resolved original values', async () => {
  const gate = deferred(), f = publicationGroupFixture({prepare: () => gate.promise});
  const first = f.group.persist(), second = f.group.persist();
  const outcomes = Promise.all([first, second]);
  outcomes.catch(() => {});
  await turn();
  assert.equal(f.events.filter(value => value === 'prepare').length, 1);
  assert.equal(f.events.some(value => value.startsWith('holding-')), false);
  assert.strictEqual(f.preparedOptions[0].sourcePlan, f.sourcePlan);
  assert.strictEqual(f.preparedOptions[0].signal, f.signal);
  assert.deepEqual(f.preparedOptions[0].operations, f.operations);
  gate.resolve(f.publication);
  assert.deepEqual(await outcomes, [f.publication.plan, f.publication.plan]);
  assert.deepEqual(f.events.filter(value => value.startsWith('commit-')), ['commit-observation', 'commit-invocation']);
  assert.equal(f.group.hasOutputPins(), true, 'final Effect evidence still borrows the original Model');
  await f.group.retirePublication(); await f.group.retirePublication();
  assert.equal(f.group.hasOutputPins(), false);
  assert.equal(f.events.filter(value => value === 'release-binding').length, 1);
});

test('plural configured Evidence projects each original child once before publication under the shared phase', async () => {
  const gate = deferred(), entered = deferred(), originals = [];
  const f = publicationGroupFixture({inferEvidence: {}, async project(facts) {
    originals.push(facts);
    if (facts.operation.index === 0) {entered.resolve(); await gate.promise;}
  }});
  const first = f.group.persist(), second = f.group.persist();
  await entered.promise;
  assert.equal(originals.length, 1);
  assert.equal(f.events.includes('prepare'), false);
  gate.resolve();
  assert.deepEqual(await Promise.all([first, second]), [f.publication.plan, f.publication.plan]);
  assert.equal(originals.length, 2);
  for (const [index, original] of originals.entries()) {
    assert.strictEqual(original.operation, f.operations[index]);
    assert(original.captureOwner);
    assert(f.events.indexOf('capture-' + index) < f.events.indexOf('evidence-' + index));
    assert(f.events.indexOf('evidence-' + index) < f.events.indexOf('prepare'));
  }
  await f.group.persist();
  assert.equal(originals.length, 2, 'Reentry must not export completed Model input again');
  assert.equal(await f.group.retirePublication(), true);
});

test('plural copy demands reuse one original publication window from actual bundle and input observations', async () => {
  const f = publicationGroupFixture({inferEvidence: {}, async project(facts) {
    facts.copyFunding({wire: '{"captures":[]}', count: 1, calls: [{callWire: '{}'}],
      usage: {_0: 15, _1: 2, _2: 1}});
  }});
  await f.group.persist();
  assert.deepEqual(f.funding, [
    {owner: 0, retained: 100n, execution: 200n},
    {owner: 0, retained: 50n, execution: 80n},
  ], 'The same original high-water owner receives per-phase demand, never cumulative ended copies');
  assert.equal(await f.group.retirePublication(), true);
});

test('plural pending Evidence copy reports Pending without awaiting itself and keeps its original child', async () => {
  const gate = deferred(), entered = deferred();
  let copying = true, copies = 0;
  const f = publicationGroupFixture({inferEvidence: {}, async project(facts) {
    copies++;
    facts.retainCopy({cleanupPending: () => copying,
      async close() {assert.equal(copying, false); return true;}, async cleanup() {assert.equal(copying, false); return true;}});
    entered.resolve();
    try {await gate.promise;} finally {copying = false;}
  }});
  const outcome = f.group.persist().then(value => ({value}), error => ({error}));
  await entered.promise; f.cancel();
  assert.equal(await f.group.retirePublication(), false);
  assert.equal(f.group.cleanupPending(), true);
  assert.equal(f.events.includes('release-capacity'), false);
  gate.resolve();
  assert.match((await outcome).error.message, /OriginalCancelled/);
  assert.equal(await f.group.retirePublication(), true);
  assert.equal(copies, 1, 'Cancellation must not project the later child');
  assert.equal(f.events.includes('prepare'), false);
});

test('plural sink can reenter first close without circularly awaiting its own projection', async () => {
  const close = deferred(); let f, projects = 0;
  f = publicationGroupFixture({inferEvidence: {}, async project() {
    projects++;
    const retired = await f.group.retirePublication();
    close.resolve(retired);
    assert.equal(retired, false);
  }});
  const result = f.group.persist().then(value => ({value}), error => ({error}));
  assert.equal(await close.promise, false);
  assert.match((await result).error.message, /Retired/);
  assert.equal(projects, 1);
  assert.equal(f.events.includes('prepare'), false, 'A delayed Sink return cannot publish after close requested retirement');
  assert.equal(await f.group.retirePublication(), true);
});

test('plural failed Evidence copy cleanup retains the original phase and primary for one owner retry', async () => {
  for (const mode of ['false', 'throw']) {
    const primary = new Error('OriginalProjectionFailure'), cleanupFailure = new Error('OriginalCopyCleanupFailure');
    let pending = true, allow = false, closes = 0, retries = 0, projections = 0;
    const f = publicationGroupFixture({inferEvidence: {}, async project(facts) {
      projections++;
      facts.retainCopy({cleanupPending: () => pending, async close() {
        closes++; if (mode === 'throw') throw cleanupFailure; return false;
      }, async cleanup() {retries++; if (allow) pending = false; return !pending;}});
      throw primary;
    }});
    await assert.rejects(f.group.persist(), error => error === primary);
    if (mode === 'throw') await assert.rejects(f.group.retirePublication(), error => error === cleanupFailure);
    else assert.equal(await f.group.retirePublication(), false);
    assert.equal(f.group.cleanupPending(), true);
    assert.equal(f.events.includes('release-capacity'), false);
    await assert.rejects(f.group.persist(), error => error === primary);
    assert.equal(projections, 1);
    allow = true;
    assert.equal(await f.group.retirePublication(), true);
    assert.equal(closes, 1); assert.equal(retries, 1);
  }
});

test('plural cleanup waits for pending preparation and prevents publication after retirement', async () => {
  const gate = deferred(), f = publicationGroupFixture({prepare: () => gate.promise});
  const outcome = f.group.persist().then(value => ({value}), error => ({error}));
  await turn();
  let retired = false;
  const cleanup = f.group.retirePublication().then(value => {retired = true; return value;});
  await turn(); assert.equal(retired, false);
  gate.resolve(f.publication);
  const result = await outcome;
  assert.match(result.error.message, /Retired/);
  assert.equal(await cleanup, true);
  assert.equal(f.events.some(value => value.startsWith('holding-')), false);
  assert.equal(f.events.filter(value => value === 'release-binding').length, 1);
});

test('plural pending cancel and lost current prevent private publication and retain binding custody', async () => {
  for (const change of ['cancel', 'revoke']) {
    const gate = deferred(), f = publicationGroupFixture({prepare: () => gate.promise});
    const outcome = f.group.persist().then(value => ({value}), error => ({error}));
    await turn(); f[change](); gate.resolve(f.publication);
    assert.match((await outcome).error.message, /OriginalCancelled|OriginalCurrentLost/);
    assert.equal(f.events.some(value => value.startsWith('holding-')), false);
    await f.group.retirePublication();
    assert.equal(f.events.filter(value => value === 'release-binding').length, 1);
  }
});

test('plural cancellation before private commit never starts Store preparation during retirement', async () => {
  // Actual private holding Owner with explicit Store ports; no physical Store,
  // Core grant, installed Model or public cleanup acknowledgment is claimed.
  const calls = {prepare: 0, commit: 0}, prepared = {status: () => ({pending: false})};
  let stored, f;
  const store = {
    async confirmPrivateEvidence() {return stored;},
    async preparePrivateEvidence() {
      calls.prepare++;
      return {physicalCid: 'original-object', bytes: 2, prepared};
    },
    async commitPhysicalHolding(record) {calls.commit++; stored = record;},
  };
  f = publicationGroupFixture({store, originalNames: true, holdingFactory: originalPrivateHolding,
    faultInjection() {f.cancel();}});
  await assert.rejects(f.group.persist(), error => error === f.signal.reason);
  assert.deepEqual(calls, {prepare: 0, commit: 0});
  assert.equal(await f.group.retirePublication(), true);
  assert.deepEqual(calls, {prepare: 0, commit: 0});
  assert.equal(f.events.filter(value => value === 'release-binding').length, 1);
  await assert.rejects(f.group.persist(), error => error === f.signal.reason);
});

test('plural failed private write keeps original holding and primary through unknown and pending abort', async () => {
  const primary = new Error('OriginalPrivateWriteFailed'), unknown = new Error('OriginalStoreObservationUnknown');
  const calls = {prepare: 0, commit: 0, release: 0};
  let mode = 'absent', cleanupReady = false, pending = true;
  const prepared = {status: () => ({pending}), async release() {
    calls.release++;
    if (cleanupReady) pending = false;
    return cleanupReady;
  }};
  const store = {
    async confirmPrivateEvidence() {if (mode === 'unknown') throw unknown;},
    async preparePrivateEvidence() {calls.prepare++; return {physicalCid: 'original-object', bytes: 2, prepared};},
    async commitPhysicalHolding() {calls.commit++; throw primary;},
  };
  const f = publicationGroupFixture({store, originalNames: true, holdingFactory: originalPrivateHolding});
  await assert.rejects(f.group.persist(), error => error === primary);
  mode = 'unknown';
  await assert.rejects(f.group.retirePublication(), error => error === unknown);
  assert.equal(f.events.includes('release-binding'), false);
  assert.deepEqual(calls, {prepare: 1, commit: 1, release: 0});
  mode = 'absent';
  await assert.rejects(f.group.retirePublication(), {code: 'PrivatePublicationHoldingCleanupPending'});
  assert.equal(f.events.includes('release-binding'), false);
  assert.equal(pending, true);
  await assert.rejects(f.group.persist(), error => error === primary);
  cleanupReady = true;
  assert.equal(await f.group.retirePublication(), true);
  assert.equal(await f.group.retirePublication(), true);
  assert.equal(pending, false);
  assert.deepEqual(calls, {prepare: 1, commit: 1, release: 2});
  assert.equal(f.events.filter(value => value === 'release-binding').length, 1);
  await assert.rejects(f.group.persist(), error => error === primary);
});

test('plural cancellation waits for the same actual private holding commit without reissuing it', async () => {
  const gate = deferred(), calls = {prepare: 0, commit: 0};
  let stored, pending = true;
  const prepared = {status: () => ({pending}), async release() {pending = false; return true;}};
  const store = {
    async confirmPrivateEvidence() {return stored;},
    async preparePrivateEvidence() {calls.prepare++; return {physicalCid: 'original-object', bytes: 2, prepared};},
    async commitPhysicalHolding(record) {calls.commit++; await gate.promise; stored = record;},
  };
  const f = publicationGroupFixture({store, originalNames: true, holdingFactory: originalPrivateHolding});
  const outcome = f.group.persist().then(value => ({value}), error => ({error}));
  await turn();
  assert.deepEqual(calls, {prepare: 1, commit: 1});
  f.cancel();
  let retired = false;
  const retiring = f.group.retirePublication().then(value => {retired = true; return value;});
  await turn(); assert.equal(retired, false);
  assert.equal(f.events.includes('release-binding'), false);
  gate.resolve();
  assert.strictEqual((await outcome).error, f.signal.reason);
  assert.equal(await retiring, true);
  assert.deepEqual(calls, {prepare: 1, commit: 1});
  assert.equal(pending, false);
  assert.equal(f.events.includes('holding-run_invocation'), false);
  assert.equal(f.events.filter(value => value === 'release-binding').length, 1);
});

test('plural publication retains the first preparation failure including thrown undefined', async () => {
  for (const primary of [undefined, new Error('OriginalPreparationFailed')]) {
    const f = publicationGroupFixture({prepare() {throw primary;}});
    for (let attempt = 0; attempt < 2; attempt++) {
      let rejected = false;
      try {await f.group.persist();} catch (error) {rejected = true; assert.strictEqual(error, primary);}
      assert.equal(rejected, true);
    }
    assert.equal(f.events.filter(value => value === 'prepare').length, 1);
    await f.group.retirePublication();
    assert.equal(f.events.filter(value => value === 'release-binding').length, 1, 'group retains partial bindings through failure');
  }
});
function fixture({inline=true,projectionFailure,sourceCount=2,upstreamWhole=false,unitFailure,modelUnits,projectionHook}={}) {
  const events=[],modelOriginal={unit:inline?0:sourceCount};
  const originals=(modelUnits??[modelOriginal.unit]).map(unit=>({unit}));
  originals[0]=modelUnits===undefined?modelOriginal:originals[0];
  const issuedModels=originals.map((_,index)=>({binding:{index}})), issued=issuedModels[0];
  const scans=originals.map(()=>({})),receipts=originals.map(()=>({}));
  const retention={wire:'{"effective_retention_policy_cid":"retention","effective_data_policy_cid":"combined"}'};
  const sourceObjects=Array.from({length:sourceCount},()=>({}));
  const sources=sourceObjects.map((original,index)=>({sourceEvidence:{original},captured:{
    ...(inline||upstreamWhole?{inputKind:'whole-input',wholeCapacity:{}}:{requirement:{}}),
    occurrence:{stage:inline?0:index,input:index,task:index},
    identity:{index},logicalInput:{},checkedSource:{sourceDataPolicyCid:'source-policy-'+index},
    capture:{source:()=>original},
  }}));
  const ok=_0=>({$tag:1,_0});
  const moon={
    clientProgramEffectPublicationDataPolicyCid:()=> 'combined',
    clientProgramEffectDefinitionCid:()=> 'program',
    clientProgramEffectCompilationResultNames:()=>['updates'],
    clientProgramCapturedSourceLogicalCid:identity=>'logical-'+identity.index,
    clientProgramCapturedSourceSchemaCid:identity=>'schema-'+identity.index,
    clientProgramCapturedSourceDependencyBodies:()=>({_0:'{"rows":[]}',_1:'{"fields":[]}'}),
    clientProgramEffectPublicationPolicyBodies:()=>ok([]),
    clientProgramReleaseInferInvocationBinding:binding=>{
      assert(issuedModels.some(original=>original.binding===binding));events.push('release-binding');
    },
    clientProgramInferModelIdentityStartCapacity:()=>({_0:3n,_1:4n}),
    clientProgramInferModelIdentityStart:binding=>{events.push('scan-start');return ok(scans[binding.index]);},
    clientProgramInferModelIdentityNextCapacity:()=>({_0:3n,_1:4n}),
    clientProgramInferModelIdentityAdvance:()=>ok({_0:true,_1:1}),
    clientProgramInferModelIdentityFinish:scan=>ok(receipts[scans.indexOf(scan)]),
    clientProgramInferModelIdentityCancel:original=>{
      assert(scans.includes(original));events.push('cancel-scan');return true;
    },
    clientProgramInferModelIdentityReceiptCancel:original=>{
      assert(receipts.includes(original));events.push('cancel-receipt');
    },
    clientProgramInferModelObservationCapacity:()=>({_0:5n,_1:6n}),
  };
  const control={
    checkedClientEffectInferInvocation(prepared,compilation,definition,actual) {
      assert.strictEqual(actual,issued);events.push('same-invocation');
      return {invocation:{},observation:{wire:'{"data_policy_cid":"combined","captured_input_artifact_cids":[]}'},owner:{}};
    },
    captureCheckedClientInferModelObservation(actual,originalScan,originalReceipt) {
      const index=issuedModels.indexOf(actual);assert(index>=0);
      assert.strictEqual(originalScan,scans[index]);
      assert.strictEqual(originalReceipt,receipts[index]);events.push('original-model');
      projectionHook?.(index);
      if(projectionFailure!==undefined)throw projectionFailure;
      return originals[index];
    },
    compiledInferSourceFreeResultPolicy:()=>({}),
    admitRunEvidence(){assert.fail('Transferred Source evidence is not readmitted');},
    seal(name,wire) {
      assert.equal(inline||upstreamWhole,false,'Whole input retention is issued by its typed Core owner');
      assert.equal(name,'result_retention_policy');events.push('source-retention');return {wire};
    },
    issueCheckedAcquiredEffectEvidence(...args) {
      assert.equal(inline,false,'Whole Model contributions never enter Query-only evidence');
      const unit=args[10];events.push('source-unit-'+unit);
      return {invocation:{},catalogBodies:[]};
    },
    issueCheckedWholeEffectSourceUnit(plan,prepared,request,slot,captured,identity,capacity,input,observation,scope,actualRetention,actualLimits) {
      assert.strictEqual(plan,sourcePlan);assert.strictEqual(prepared,acquired.prepared);
      assert.strictEqual(request,acquired.requestIdentity);
      const source=sources[slot];
      assert.strictEqual(captured,sourceObjects[slot]);assert.strictEqual(identity,source.captured.identity);
      assert.strictEqual(capacity,source.captured.wholeCapacity);assert.strictEqual(input,source.captured.logicalInput);
      assert.strictEqual(observation,source.sourceEvidence);assert.equal(scope,'authority');
      assert.strictEqual(actualRetention,retention);assert.strictEqual(actualLimits,limits);
      events.push('whole-unit-'+slot);
      if(unitFailure!==undefined)throw unitFailure;
      return {invocation:{},catalogBodies:[]};
    },
  };
  const sourcePlan={};
  const acquired={moon,control,prepared:{},requestIdentity:{},compilation:{},admission:{},
    definition:{},runDefinition:{wire:'{"created_at":"2026-11-11T00:00:00Z","valid_until":"2026-11-12T00:00:00Z"}'},
    compiledPlan:{identity:'compiled-plan'},authorityScopeCid:'authority',namespaceId:'namespace',
    storeAuthorityCid:'store',now:()=> '2026-11-11T00:00:00Z'};
  const growth=[];
  const operations=issuedModels.map((original,index)=>({
    bindIssuedInvocation(){events.push('bind');return original;},
    growOriginalPublicationCapacity(retained,execution){
      assert.equal(index,0,'all scans use the SAME original publication capacity');
      growth.push([retained,execution]);events.push('grow');
    },
  }));
  const operation=operations[0];
  const buildLocalPublicationPlan=()=>{
    events.push('plan');return {plan:{},retention,retentionDependencies:[]};
  };
  const create=new Function('runtimeField','runtimeOptionalField','checked','limits',
    'withOriginalInferModelObservation','buildLocalPublicationPlan',
    body('sourceFreeInferEffectPublicationPlan')+'\n'+body('acquiredMultiEffectPublicationPlan')+'\n'+body('acquiredInferEffectPublicationPlan')+
      '\nreturn {acquiredMultiEffectPublicationPlan,acquiredInferEffectPublicationPlan};');
  const functions=create(runtimeField,runtimeOptionalField,checked,limits,
    withOriginalInferModelObservation,buildLocalPublicationPlan);
  const invoke=()=>functions.acquiredInferEffectPublicationPlan({acquired,sources,
    compiled:{},operation,operations,issuance:{},modelEvidence:[],sourcePlan});
  return {events,issued,issuedModels,modelOriginal,originals,functions,acquired,sources,invoke,sourcePlan,operation,operations,growth};
}

test('upstream Whole Units use the same Plan and original capture tuple without Query conversion',async()=>{
  const f=fixture({inline:false,upstreamWhole:true}),publication=await f.invoke();
  const context=publication.plan.localEvidenceContext;
  assert.strictEqual(context.modelOriginalByUnit[2],f.modelOriginal);
  assert.equal(context.acquiredEvidenceByUnit.length,2);
  assert.deepEqual(f.events.filter(value=>value.startsWith('whole-unit-')),['whole-unit-0','whole-unit-1']);
  assert.equal(f.events.filter(value=>value==='source-retention').length,0);
  assert.equal(f.events.filter(value=>value.startsWith('source-unit-')).length,0);
  assert.equal(f.events.includes('release-binding'),false);
});

test('a missing original Whole Plan cannot fall back to the Query-only issuer',async()=>{
  const f=fixture({inline:false,upstreamWhole:true});
  await assert.rejects(f.functions.acquiredInferEffectPublicationPlan({acquired:f.acquired,sources:f.sources,
    compiled:{},operation:f.operation,issuance:{},modelEvidence:[]}),/WholeEffectProducerUnitOriginalRequired/);
  assert.equal(f.events.filter(value=>value==='release-binding').length,1);
  assert.equal(f.events.filter(value=>value.startsWith('whole-unit-')||value.startsWith('source-unit-')).length,0);
});

test('Whole producer refusal preserves the exact checked cause and releases only its Model binding',async()=>{
  const failure=new Error('OriginalWholeCaptureForeign'),f=fixture({inline:false,upstreamWhole:true,unitFailure:failure});
  await assert.rejects(f.invoke(),error=>error===failure);
  assert.deepEqual(f.events.filter(value=>value.startsWith('whole-unit-')),['whole-unit-0']);
  assert.equal(f.events.filter(value=>value==='release-binding').length,1);
  assert.equal(f.events.filter(value=>value.startsWith('source-unit-')).length,0);
});

test('two Whole contributions without original Unit custody cannot become separate complete upstream evidence',async()=>{
  const f=fixture({inline:false,upstreamWhole:true});f.sources[1].captured.occurrence.stage=0;
  // The current combined-Unit entry first requires the original managed Run;
  // two individual Source contributions cannot substitute for that custody.
  await assert.rejects(f.invoke(),error=>error instanceof TypeError && error.message==='WholeEffectProducerUnitOriginalRequired');
  assert.deepEqual(f.events.filter(value=>value.startsWith('whole-unit-')),[]);
  assert.equal(f.events.filter(value=>value==='release-binding').length,1);
});

test('inline Whole sources retain same issued Model and bypass Query-only evidence or duplicate retention issuance',async()=>{
  const f=fixture(),publication=await f.invoke();
  assert.strictEqual(publication.binding,f.issued.binding);
  const context=publication.plan.localEvidenceContext;
  assert.strictEqual(context.modelOriginalByUnit[0],f.modelOriginal);
  assert.deepEqual(context.acquiredEvidenceByUnit,[]);
  assert.equal(context.acquisitionDependencies.length,4);
  assert.equal(f.events.filter(value=>value==='bind').length,1);
  assert.equal(f.events.filter(value=>value==='original-model').length,1);
  assert.equal(f.events.includes('release-binding'),false,'capture custody retains successful binding');
});

test('upstream Query Units remain distinct while original Model Unit waits for its checked import closure',async()=>{
  const f=fixture({inline:false}),publication=await f.invoke();
  const context=publication.plan.localEvidenceContext;
  assert.strictEqual(context.modelOriginalByUnit[2],f.modelOriginal);
  assert.equal(context.acquiredEvidenceByUnit.length,2);
  assert.deepEqual(f.events.filter(value=>value.startsWith('source-unit-')),['source-unit-0','source-unit-1']);
  assert.equal(f.events.filter(value=>value==='source-retention').length,2);
});

test('three inline Whole occurrences retain the same original Model context without Query conversion',async()=>{
  const f=fixture({sourceCount:3}),publication=await f.invoke();
  const context=publication.plan.localEvidenceContext;
  assert.strictEqual(context.modelOriginalByUnit[0],f.modelOriginal);
  assert.deepEqual(context.acquiredEvidenceByUnit,[]);
  assert.equal(context.acquisitionDependencies.length,6);
  assert.equal(f.events.filter(value=>value==='original-model').length,1);
  assert.equal(f.events.filter(value=>value==='same-invocation').length,1);
});

test('three Query producer Units preserve their exact coordinates before Model Unit three',async()=>{
  const f=fixture({inline:false,sourceCount:3}),publication=await f.invoke();
  const context=publication.plan.localEvidenceContext;
  assert.strictEqual(context.modelOriginalByUnit[3],f.modelOriginal);
  assert.equal(context.acquiredEvidenceByUnit.length,3);
  assert.deepEqual(f.events.filter(value=>value.startsWith('source-unit-')),
    ['source-unit-0','source-unit-1','source-unit-2']);
  assert.equal(f.events.filter(value=>value==='source-retention').length,3);
});

test('Model projection refusal keeps original cause and releases same binding after original scan cleanup',async()=>{
  const failure=Object.freeze(new Error('OriginalProjectionRefused'));
  const f=fixture({projectionFailure:failure});
  await assert.rejects(f.invoke(),error=>error===failure);
  assert.deepEqual(f.events.slice(-3),['cancel-receipt','cancel-scan','release-binding']);
  assert.equal(f.events.includes('plan'),false);
});

test('Whole Source Unit runtime facade forwards the original typed tuple and registers only the issued dependency',()=>{
  const text=readFileSync(new URL('../host-common/runtime-core.mjs',import.meta.url),'utf8');
  let method;
  (function walk(node){
    if(!node||typeof node!=='object')return;
    if(node.type==='Property'&&node.key?.name==='issueCheckedWholeEffectSourceUnit'){
      assert.equal(method,undefined);method=node;
    }
    for(const value of Object.values(node))for(const child of Array.isArray(value)?value:[value])walk(child);
  })(parse(text,{ecmaVersion:'latest',sourceType:'module'}));
  assert(method);
  const plan={},prepared={},request={},captured={},identity={},capacity={},input={},observation={},retention={};
  const rawObservation={},rawRetention={},issued={},projected={},tokens=new WeakMap(),calls=[];
  const ports={issuanceLimits(actual,label){assert.strictEqual(actual,limits);assert.equal(label,'Whole Effect Source Unit');},
    checked,evidenceToken(actual){assert.strictEqual(actual,observation);return rawObservation;},
    token(actual){assert.strictEqual(actual,retention);return rawRetention;},
    inspectAcquiredEffectEvidence(actual,original,bounds){
      assert.strictEqual(actual,issued);assert.strictEqual(original,retention);assert.strictEqual(bounds,limits);return projected;
    },localEffectDependencyTokens:tokens,
    moon:{clientProgramIssueInstalledWholeEffectSourceUnit(...args){calls.push(args);return {$tag:1,_0:issued};}}};
  const invoke=new Function(...Object.keys(ports),`return ({${text.slice(method.start,method.end)}}).issueCheckedWholeEffectSourceUnit;`)(...Object.values(ports));
  assert.strictEqual(invoke(plan,prepared,request,2,captured,identity,capacity,input,observation,'authority',retention,limits),projected);
  assert.deepEqual(calls,[[plan,prepared,request,2,captured,identity,capacity,input,rawObservation,'authority',rawRetention,16384,1024,20]]);
  assert.deepEqual(tokens.get(projected),{kind:'acquired',issued});
  assert.throws(()=>invoke(plan,prepared,request,-1,captured,identity,capacity,input,observation,'authority',retention,limits),/Invalid acquired Effect Source slot/);
  assert.equal(calls.length,1);
});


test('all checked Model Units retain distinct original observations beside a separate Whole Unit',async()=>{
  const f=fixture({inline:false,sourceCount:1,upstreamWhole:true,modelUnits:[2,5]});
  const publication=await f.invoke(),context=publication.plan.localEvidenceContext;
  assert.strictEqual(context.modelOriginalByUnit[2],f.originals[0]);
  assert.strictEqual(context.modelOriginalByUnit[5],f.originals[1]);
  assert.equal(context.modelOriginalByUnit[0],undefined);
  assert.equal(context.acquiredEvidenceByUnit.length,1);
  assert.deepEqual(publication.bindings,f.issuedModels.map(original=>original.binding));
  assert.equal(f.events.filter(event=>event==='bind').length,2);
  assert.equal(f.events.filter(event=>event==='original-model').length,2);
  assert.deepEqual(f.events.filter(event=>event.startsWith('whole-unit-')),['whole-unit-0']);
  assert.deepEqual(f.growth,[[3n,4n],[3n,4n],[8n,10n],[11n,14n],[11n,14n],[16n,20n]],
    'the same original publication owner backs all simultaneously retained projections');
});

test('duplicate checked Model Units refuse rather than replace an original with an equal coordinate',async()=>{
  const f=fixture({modelUnits:[0,0]});
  await assert.rejects(f.invoke(),/OriginalEffectModelUnitInventoryRequired/);
  assert.equal(f.events.filter(event=>event==='release-binding').length,2);
  assert.equal(f.events.includes('plan'),false);
});

test('failure at the later Model preserves the primary and retires each actual binding once',async()=>{
  for(const primary of [undefined,new Error('SecondOriginalModelFailed')]) {
    const f=fixture({modelUnits:[0,3],projectionHook(index){if(index===1)throw primary;}});
    let rejected=false;
    try {await f.invoke();} catch(error) {rejected=true;assert.strictEqual(error,primary);}
    assert.equal(rejected,true);
    assert.equal(f.events.filter(event=>event==='release-binding').length,2);
    assert.equal(f.events.includes('plan'),false);
  }
});

test('lost current after an observation await prevents the next Model binding and publication',async()=>{
  let current=true;
  const f=fixture({modelUnits:[0,3],projectionHook(){current=false;}});
  await assert.rejects(f.functions.acquiredInferEffectPublicationPlan({acquired:f.acquired,sources:f.sources,
    compiled:{},operation:f.operation,operations:f.operations,issuance:{},modelEvidence:[],sourcePlan:f.sourcePlan,
    current(){if(!current)throw new Error('OriginalCurrentLost');}}),/OriginalCurrentLost/);
  assert.equal(f.events.filter(event=>event==='bind').length,1);
  assert.equal(f.events.filter(event=>event==='release-binding').length,1);
  assert.equal(f.events.includes('plan'),false);
});


test('plural private holding failure preserves its primary and retires the same partial publication once',async()=>{
  const primary=new Error('OriginalPrivateHoldingFailed');
  const f=publicationGroupFixture({faultInjection(){throw primary;}});
  await assert.rejects(f.group.persist(),error=>error===primary);
  await assert.rejects(f.group.persist(),error=>error===primary);
  assert.equal(f.events.filter(value=>value==='prepare').length,1);
  assert.equal(f.events.some(value=>value.startsWith('commit-')),false);
  assert.equal(await f.group.retirePublication(),true);
  assert.equal(f.events.filter(value=>value==='commit-observation').length,0);
  assert.equal(f.events.filter(value=>value==='abort-observation').length,1);
  assert.equal(f.events.includes('commit-invocation'),false);
  assert.equal(f.events.filter(value=>value==='release-binding').length,1);
});


test('source-free plural Model publication retains every original Unit under the same complete issuer',async()=>{
  const f=fixture({inline:false,sourceCount:0,modelUnits:[2,5]});
  const publication=await f.invoke(),context=publication.plan.localEvidenceContext;
  assert.strictEqual(context.modelOriginalByUnit[2],f.originals[0]);
  assert.strictEqual(context.modelOriginalByUnit[5],f.originals[1]);
  assert.equal(context.sourceFreeDependencyClosure,true);
  assert.equal(publication.bindings.length,2);
  assert.equal(f.events.filter(event=>event==='bind').length,2);
  assert.equal(f.events.includes('release-binding'),false);
});

test('plural cancellation during private commit waits for that original write without starting the next holding',async()=>{
  const gate=deferred(),f=publicationGroupFixture({commit:()=>gate.promise});
  const outcome=f.group.persist().then(value=>({value}),error=>({error}));
  await turn();
  assert.deepEqual(f.events.filter(value=>value.startsWith('commit-')),['commit-observation']);
  f.cancel();
  const first=f.group.retirePublication(),second=f.group.retirePublication();
  gate.resolve();
  assert.match((await outcome).error.message,/OriginalCancelled/);
  assert.deepEqual(await Promise.all([first,second]),[true,true]);
  assert.equal(f.events.filter(value=>value==='commit-observation').length,1);
  assert.equal(f.events.includes('holding-invocation'),false);
  assert.equal(f.events.filter(value=>value==='release-binding').length,1);
});


test('plural binding retirement retains false and throwing releases for the same owner retry',async()=>{
  for(const mode of ['false','throw']) {
    let ready=false;
    const primary=new Error('OriginalPublicationFailed'),cleanupFailure=new Error('OriginalBindingReleaseFailed');
    const f=publicationGroupFixture({prepare(){throw primary;},releaseBinding(){
      if(ready)return true;
      if(mode==='throw')throw cleanupFailure;
      return false;
    }});
    await assert.rejects(f.group.persist(),error=>error===primary);
    if(mode==='throw')await assert.rejects(f.group.retirePublication(),error=>error===cleanupFailure);
    else assert.equal(await f.group.retirePublication(),false);
    assert.equal(f.group.hasOutputPins(),true);
    assert.equal(f.events.filter(value=>value==='release-binding').length,0);
    await assert.rejects(f.group.persist(),error=>error===primary);
    ready=true;
    assert.equal(await f.group.retirePublication(),true);
    assert.equal(f.group.hasOutputPins(),false);
    assert.equal(f.events.filter(value=>value==='release-attempt').length,2);
    assert.equal(f.events.filter(value=>value==='release-binding').length,1);
    assert.equal(await f.group.retirePublication(),true);
    assert.equal(f.events.filter(value=>value==='release-attempt').length,2);
  }
});


test('plural retirement installs retry phase before reentrant original child cleanup',async()=>{
  const gate=deferred();
  let initial=true,reentered=false,nested,entries=0;
  const f=publicationGroupFixture({async retireCapture(index){
    if(index!==0)return true;
    entries++;
    if(initial){initial=false;return false;}
    if(!reentered){reentered=true;nested=f.group.retirePublication();nested.catch(()=>{});}
    await gate.promise;
    return true;
  }});
  await f.group.persist();
  assert.equal(await f.group.retirePublication(),false);
  const outer=f.group.retirePublication();outer.catch(()=>{});
  await turn();
  const observedEntries=entries;
  gate.resolve();
  const outcomes=await Promise.allSettled([outer,nested]);
  assert.equal(observedEntries,2,'one original child call in each phase, including reentry');
  assert.deepEqual(outcomes,[{status:'fulfilled',value:true},{status:'fulfilled',value:true}]);
  assert.equal(f.events.filter(value=>value==='release-binding').length,1);
  assert.equal(f.events.filter(value=>value==='release-capacity').length,1);
});


test('plural existing input path requires no replacement Result API without an original Unit cache', () => {
  const f = publicationGroupFixture();
  for (const context of f.contexts) {
    assert.equal(context.prepareOriginalResults(), undefined);
  }
  assert.equal(f.events.includes('prepare'), false);
});


test('final plural publication reuses an earlier Model original scan and body under the actual final binding', async () => {
  const operations = [{}, {}], issued = [{binding: {}}, {binding: {}}], originals = [{unit: 1}, {unit: 2}];
  const scan = {}, receipt = {}, dependency = {}, proof = {}, events = [];
  operations.forEach((operation, index) => {operation.bindIssuedInvocation = () => issued[index];});
  const sourceUnitsOriginal = {byUnit: new Map([[1, {modelOperation: operations[0], value: dependency,
    results: {modelOriginal: proof, modelScan: scan, modelReceipt: receipt,
      identityRetainedBytes: 12n, identityExecutionBytes: 14n}}]])};
  const final = {};
  const acquired = {moon: {}, runDefinition: {}, control: {
    captureCheckedClientInferModelObservation(actual, actualScan, actualReceipt, actualLimits, earlier) {
      if (actual === issued[0]) {
        assert.strictEqual(actualScan, scan); assert.strictEqual(actualReceipt, receipt); assert.strictEqual(earlier, dependency);
        events.push('reuse'); return originals[0];
      }
      assert.strictEqual(actual, issued[1]); assert.equal(earlier, undefined); events.push('later'); return originals[1];
    },
  }};
  const ports = {limits, async withOriginalInferModelObservation(facts) {
    assert.strictEqual(facts.binding, issued[1].binding);
    assert.equal(facts.retainedBase, 12n); assert.equal(facts.executionBase, 14n); events.push('scan-later');
    return facts.consume({scan: {}, receipt: {}, retainedBytes: 3n, executionBytes: 4n});
  }, acquiredMultiEffectPublicationPlan(facts) {
    assert.deepEqual(facts.modelOriginals, originals); assert.strictEqual(facts.sourceUnitsOriginal, sourceUnitsOriginal);
    return final;
  }};
  const prepare = new Function(...Object.keys(ports), `return (${body('acquiredInferEffectPublicationPlan')});`)(...Object.values(ports));
  const bindings = [];
  const publication = await prepare({acquired, sources: [{}], compiled: {}, operations, operation: operations[0],
    sourceUnitsOriginal, retainBinding: binding => bindings.push(binding)});
  assert.deepEqual(events, ['reuse', 'scan-later', 'later']);
  assert.deepEqual(bindings, issued.map(value => value.binding)); assert.strictEqual(publication.plan, final);
  assert.strictEqual(sourceUnitsOriginal.byUnit.get(1).results.modelReceipt, receipt,
    'the existing group still owns its original receipt until retirement');
});


test('plural preconsumer boundary preserves the existing no-Unit path and original selected Model task', async () => {
  const f = publicationGroupFixture();
  // The actual fixture has one captured input and no replacement Unit cache.
  // Its original Model graph task still selects the existing beforeNext path.
  for (const context of f.contexts) assert.equal(context.prepareOriginalResults(), undefined);
  await f.group.prepareNext(0, () => {throw new Error('unexpected physical reader');});
  await f.group.prepareNext(0, () => {throw new Error('unexpected duplicate reader');});
  assert.equal(f.contexts[0].prepareOriginalResults(), undefined);
  assert.equal(f.events.includes('prepare'), false);
});


test('plural preconsumer pending phase is shared and reentrant retirement cannot release its original bridge', async () => {
  const entered = deferred(), finish = deferred();
  const f = publicationGroupFixture({async unitPreparation() {entered.resolve(); await finish.promise;}});
  const first = f.group.prepareNext(0, () => {}), second = f.group.prepareNext(0, () => {});
  const outcome = Promise.allSettled([first, second]);
  await Promise.race([entered.promise, first.then(() => {throw new Error('OriginalUnitPreparationDidNotEnter');})]);
  assert.equal(f.group.cleanupPending(), true);
  assert.equal(await f.group.retirePublication(), false);
  assert.equal(f.group.releaseUnitOutputs(), false);
  finish.resolve();
  const results = await outcome;
  assert(results.every(value => value.status === 'rejected' && /Retired/.test(value.reason.message)));
  assert.equal(f.events.filter(value => value === 'prepare-unit').length, 1);
  assert.equal(f.group.releaseUnitOutputs(), true);
  assert.equal(f.events.filter(value => value === 'retire-unit').length, 1);
});

test('plural preconsumer first undefined failure is sticky without issuing another original preparation', async () => {
  const f = publicationGroupFixture({async unitPreparation() {throw undefined;}});
  for (let index = 0; index < 2; index++) {
    let failed = false, primary;
    try {await f.group.prepareNext(0, () => {});} catch (cause) {failed = true; primary = cause;}
    assert.equal(failed, true); assert.strictEqual(primary, undefined);
  }
  assert.equal(f.group.hasFailure(), true);
  assert.strictEqual(f.group.failure(), undefined);
  assert.equal(f.events.filter(value => value === 'prepare-unit').length, 1);
  assert.equal(f.group.releaseUnitOutputs(), true);
  assert.throws(() => f.contexts[0].prepareOriginalResults(), /Retired/);
  await assert.rejects(f.group.prepareNext(0, () => {}), /Retired/);
});


test('plural Source artifact preparation forwards the original Model Plan definition across Journal admission', async () => {
  const f = publicationGroupFixture({async unitPreparation() {}});
  await f.group.prepareNext(0, () => {});
  assert.equal(f.events.filter(value => value === 'prepare-unit').length, 1);
  assert.equal(f.contexts[0].prepareOriginalResults().length, 1);
});

test('plural typed-input funding measures same logical originals without physical prompt or new Ledger', async () => {
  const f = publicationGroupFixture({inferEvidence: {}, async project(facts) {
    facts.copyFunding({wire: '{"captures":[]}', count: 1, calls: [{callWire: '{}'}],
      usage: {_0: 15, _1: 2, _2: 1}}, 'typed-input');
  }});
  for (const operation of f.operations) {
    operation.evaluationRequest = () => assert.fail('No physical Mock evidence exists');
    operation.evaluationInput = slot => {
      assert.equal(slot, 0);return {request: {index: operation.index}, callWire: '{}'};
    };
  }
  // The existing pure quote receives the actual call wire only for this mode.
  // This explicit port checks demand plumbing, not Core arithmetic or runtime.
  f.moon.clientProgramEffectModelEvidenceCopyCapacity = (bytes, nodes, depth, shape, text, calls) => {
    assert.deepEqual([bytes, nodes, depth, text, calls], [15, 2, 1, 2, 1]);
    return {$tag: 1, _0: {_0: BigInt(10 + shape.request.index), _1: 20n}};
  };
  await f.group.persist();
  assert.deepEqual(f.funding, [{owner: 0, retained: 10n, execution: 20n}, {owner: 0, retained: 11n, execution: 20n}]);
  assert.equal(await f.group.retirePublication(), true);
});

test('plural typed-input funding preserves exact missing-original error codes', async () => {
  for (const mode of ['missing-usage', 'missing-original']) {
    const f = publicationGroupFixture({inferEvidence: {}, async project(facts) {
      assert.throws(() => facts.copyFunding({wire: '{"captures":[]}', count: 1,
        calls: [{callWire: '{}'}], ...(mode === 'missing-usage' ? {} : {usage: {_0: 15, _1: 2, _2: 1}})},
      'typed-input'), {code: 'RequiredEvidenceUnavailable'});
    }});
    for (const operation of f.operations) operation.evaluationInput = () => undefined;
    await f.group.persist();
    assert.deepEqual(f.funding, []);
    assert.equal(await f.group.retirePublication(), true);
  }
});
