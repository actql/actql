import assert from 'node:assert/strict';
import test from 'node:test';
import {captureInstalledEffectPlanRecipe, prepareInstalledEffectManagedPlan,
  captureInstalledStandardCreateLimits, prepareInstalledStandardCreatePlanRecipe, prepareInstalledEffectRequestChild}
  from './installed-effect-plan.mjs';
import {effectLedgerImplementationBounds} from './effect-ledger-implementation-bounds.mjs';
import {httpsCredentialAuthorizationPrefix, httpsCredentialResponseHeaderByteLimit}
  from '../site-node/https-credential-resource.mjs';

test('automatic standard recipe forwards original constructor capacities and keeps all physical phases distinct', () => {
  for (const beforeSend of [false,true]) {
    const profile={}, capacities=Array.from({length:6},()=>Object.freeze({})), calls=[];
    const write=Object.freeze({operation:'write',maxRequestBytes:128,maxResponseBytes:64});
    const check=Object.freeze({operation:'read',resource:'form',maxRequestBytes:32,maxResponseBytes:16,beforeSend});
    const construction=Object.freeze({write,check,metadataTextUnits:17});
    const credentialSite=Object.freeze({construction:Object.freeze({
      scope:Object.freeze({principal:'original',siteGeneration:1}),
      issuer:Object.freeze({authority:'issuer',keyId:'key'}),
      limits:Object.freeze({maxBindings:91,maxSecretBytes:23})})});
    const providerMoon={installedStandardCreateConstructionProfile(...geometry){assert.equal(this,providerMoon);assert.deepEqual(geometry,[512,32,8]);calls.push('profile');return profile;}};
    const extents=[];
    const moon={
      clientProgramInstalledStandardCreateRecipeCapacities(...args){
        assert.equal(this,moon);calls.push('capacities');
        assert.deepEqual(args,[profile,512,32,8,128,64,32,16,beforeSend,23,httpsCredentialAuthorizationPrefix.length,
          httpsCredentialResponseHeaderByteLimit,effectLedgerImplementationBounds.maxResponseBytes,
          effectLedgerImplementationBounds.maxNodes,effectLedgerImplementationBounds.maxDepth,41n]);
        return {$tag:1,_0:capacities};
      },
      clientProgramInstalledEffectCaptureExtentPrepare(operation,fixed,row){
        assert.equal(this,moon);assert.deepEqual([operation,fixed,row],['write',capacities[0],capacities[1]]);
        const extent={capture:true};extents.push(extent);return {$tag:1,_0:extent};
      },
      clientProgramInstalledEffectOperationExtentFromCapacityPrepare(operation,capacity,transfer,physical){
        assert.equal(this,moon);const extent={operation,capacity,transfer,physical};extents.push(extent);return {$tag:1,_0:extent};
      },
    };
    const recipe=prepareInstalledStandardCreatePlanRecipe({moon,providerMoon,construction,credentialSite,
      limits:{maxWireBytes:512,maxNodes:32,maxDepth:8},resourceTextUnits:7});
    assert.deepEqual(calls,['profile','capacities']);
    assert.equal(recipe.memberOperations.length,1);
    assert.equal(recipe.rowOperations.length,beforeSend?6:5);
    assert.strictEqual(recipe.controlsPerRow,capacities[4]);
    assert.deepEqual(recipe.credentialOperations.map(x=>x.phase),beforeSend
      ?['capture-check','apply-check','resume-check','write-check','write']
      :['capture-check','apply-check','resume-check','write']);
    assert.deepEqual(recipe.credentialOperations.map(x=>x.operationIndex),beforeSend?[1,2,3,4,5]:[1,2,3,4]);
    assert.equal(recipe.rowOperations[0].extent.physical,false);
    assert.equal(recipe.rowOperations[0].extent.transfer,0n);
    for(const entry of recipe.credentialOperations){
      const extent=recipe.rowOperations[entry.operationIndex].extent;
      assert.equal(extent.physical,true);
      assert.equal(extent.transfer,entry.phase==='write'?193n:49n);
      assert.strictEqual(extent.capacity,entry.phase==='write'?capacities[3]:capacities[5]);
    }
    assert.equal(new Set(extents).size,extents.length);
  }
});

// These are the actual installed Plan selector's ports. No native capacity,
// Run, Source I/O or Model permission is issued by these caller regressions.
for (const model of [false, true]) test(`Effect Plan forwards the same retained ${model ? 'Source and Model' : 'Source'} inputs before execution`, () => {
  const prepared = {}, identity = {}, declaration = {}, provider = {}, component = {},
    installedContracts = {}, demand = {}, plan = {}, modelDemand = {};
  const sourceInputs = Object.freeze({declarations: Object.freeze([declaration]),
    providers: Object.freeze([provider]), queryContract: 'original-query-contract',
    evidenceContract: 'original-evidence-contract', transferBytes: Object.freeze([37n]),
    executionBytes: Object.freeze([19n])});
  const calls = [], facts = Object.freeze({prepared, identity, queryTimePreparation: undefined});
  const originalArguments = (actual, expected) => {
    assert.equal(actual.length, expected.length);
    actual.forEach((value, index) => {
      if (!Array.isArray(expected[index])) assert.strictEqual(value, expected[index]);
      else {
        assert.equal(value.length, expected[index].length);
        value.forEach((entry, slot) => assert.strictEqual(entry, expected[index][slot]));
      }
    });
  };
  const moon = {
    clientProgramEffectAcquisitionCount: actual => {assert.equal(actual, prepared); return 1;},
    clientProgramInstalledEffectOperationDemandPrepare(p, stage, member, metadata, rows) {
      assert.equal(p, prepared); assert.deepEqual([stage, member, metadata, rows], [2, 'write', [], [provider]]);
      calls.push('demand'); return {$tag: 1, _0: demand};
    },
    clientProgramInstalledEffectManagedProviderPlanPrepare(...actual) {
      assert.equal(this, moon); assert.equal(model, false);
      originalArguments(actual, [prepared, identity, sourceInputs.declarations, sourceInputs.providers,
        sourceInputs.queryContract, sourceInputs.evidenceContract, sourceInputs.transferBytes,
        sourceInputs.executionBytes, installedContracts, 'values', 'fragment', 'ordered', [demand]]);
      calls.push('plan'); return {$tag: 1, _0: plan};
    },
    clientProgramInstalledEffectModelManagedProviderPlanPrepare(...actual) {
      assert.equal(this, moon); assert.equal(model, true);
      originalArguments(actual, [prepared, identity, sourceInputs.declarations, sourceInputs.providers,
        sourceInputs.queryContract, sourceInputs.evidenceContract, sourceInputs.transferBytes,
        sourceInputs.executionBytes, installedContracts, 'values', 'fragment', 'ordered', [demand],
        modelDemand, [component], undefined]);
      calls.push('plan'); return {$tag: 1, _0: plan};
    },
    clientProgramInstalledEffectManagedPlanPrepare() {assert.fail('no Source-free fallback');},
  };
  const recipe = {memberOperations: [], rowOperations: [{extent: provider}]};
  const inputs = {installedContracts, values: 'values', fragment: 'fragment', ordered: 'ordered',
    sourceInputs, ...(model ? {modelDemand, modelComponents: Object.freeze([component])} : {})};
  assert.equal(prepareInstalledEffectManagedPlan({moon, facts, inputs, unit: {stageIndex: 2},
    members: [{effectId: 'write'}], recipeFor: () => recipe}), plan);
  assert.deepEqual(calls, ['demand', 'plan']);
});

// JS passes only original DATA arrays. The selected Moon bridge, not this
// caller, constructs its own typed None/Some provider vector. Explicit ports
// below establish routing/argument identity, not a native Plan or its backing.
for (const sourceKind of ['source-free', 'base Source', 'provider Source']) {
  test(`Model Plan uses the typed ${sourceKind} bridge without a JS Option`, () => {
    const prepared = {}, request = {}, model = {}, component = {}, declaration = {}, provider = {}, plan = {};
    const count = sourceKind === 'source-free' ? 0 : 1;
    const providers = sourceKind === 'provider Source' ? Object.freeze([provider]) : undefined;
    const sources = Object.freeze({declarations: Object.freeze(count ? [declaration] : []),
      ...(providers === undefined ? {} : {providers}), queryContract: count ? 'query' : '',
      evidenceContract: count ? 'evidence' : '', transferBytes: Object.freeze(count ? [37n] : []),
      executionBytes: Object.freeze(count ? [19n] : [])});
    const inputs = {sourceInputs: sources, installedContracts: {}, values: 'values',
      fragment: undefined, ordered: undefined, modelDemand: model, modelComponents: Object.freeze([component])};
    let calls = 0;
    function accept(...actual) {
      assert.equal(this, moon); calls++;
      const expected = [prepared, request, sources.declarations,
        ...(providers === undefined ? [] : [providers]), sources.queryContract, sources.evidenceContract,
        sources.transferBytes, sources.executionBytes, inputs.installedContracts, inputs.values,
        undefined, undefined, [], model, inputs.modelComponents, undefined];
      assert.equal(actual.length, expected.length);
      actual.forEach((value, i) => {
        if (Array.isArray(expected[i]) && expected[i].length === 0) assert.deepEqual(value, []);
        else assert.strictEqual(value, expected[i]);
      });
      return {$tag: 1, _0: plan};
    }
    const moon = {clientProgramEffectAcquisitionCount: p => {assert.equal(p, prepared); return count;},
      clientProgramInstalledEffectOperationDemandPrepare() {assert.fail('No selected operation in this bridge counter');},
      clientProgramInstalledEffectModelManagedPlanPrepare: providers === undefined ? accept
        : () => assert.fail('Provider vector requires its typed Some bridge'),
      clientProgramInstalledEffectModelManagedProviderPlanPrepare: providers === undefined
        ? () => assert.fail('Base Source is not a zero-Source or invented provider') : accept};
    assert.equal(prepareInstalledEffectManagedPlan({moon, facts: {prepared, identity: request},
      inputs, unit: {stageIndex: 0}, members: [], recipeFor: () => assert.fail('No operation recipe needed')}), plan);
    assert.equal(calls, 1);
  });
}

// Explicit Core ports count calls only. This refusal case does not fabricate a
// successful native Plan, a Request parent, a source acquisition or capacity.
test('unavailable original Source or Model inputs refuse before constructing Effect demands', () => {
  const prepared = Object.freeze({}), identity = Object.freeze({});
  const extent = Object.freeze({});
  const recipe = captureInstalledEffectPlanRecipe(Object.freeze({
    memberOperations: Object.freeze([]),
    rowOperations: Object.freeze([Object.freeze({operation: 'write', extent})]),
  }), 1);
  for (const kind of ['source', 'model']) {
    let demands = 0, plans = 0;
    const moon = {
      clientProgramEffectAcquisitionCount: original => {
        assert.equal(original, prepared);
        return kind === 'source' ? 1 : 0;
      },
      clientProgramInstalledEffectOperationDemandPrepare() {
        demands++;
        throw new Error('UnexpectedEffectDemandConstruction');
      },
      clientProgramInstalledEffectManagedPlanPrepare() {plans++;},
    };
    assert.throws(() => prepareInstalledEffectManagedPlan({moon,
      facts: {prepared, identity}, inputs: {installedContracts: Object.freeze({}),
        values: '{}', ...(kind === 'model' ? {modelDemand: Object.freeze({})} : {})},
      unit: {stageIndex: 0}, members: [{effectId: 'write'}], recipeFor: () => recipe}),
    {code: 'InstalledEffectPlanInputsUnavailable'});
    assert.equal(demands, 0);
    assert.equal(plans, 0);
  }
});


// Native reservation/current ports are explicit here. This executes the actual
// shared child and capture retainer, not a physical child or a whole recipe.
test('constructor child debits the same original before work and retains it until request aliases retire', async () => {
  const {prepareInstalledEffectRequestChild: create} = await import('./installed-effect-plan.mjs');
  const {prepareInstalledRowCaptureChild: prepare} = await import('./installed-row-capture-cleanup.mjs');
  assert.equal(typeof create, 'function');
  const prepared = {}, identity = {}, parent = {}, plan = {}, token = {}, output = {};
  const calls = [], children = [];
  let aliasesRetired = false, cleanupConfirmed = false;
  const runtime = {
    clientProgramInstalledEffectManagedOperationPlan(owner, p, r) {
      assert.equal(this, runtime); assert.equal(owner, parent); assert.equal(p, prepared);
      assert.equal(r, identity); return {$tag: 1, _0: plan};
    },
    clientProgramInstalledEffectOperationBorrow(owner, p, r, originalPlan, member, perRow, operation, row, name) {
      assert.equal(this, runtime); assert.equal(owner, parent); assert.equal(p, prepared);
      assert.equal(r, identity); assert.equal(originalPlan, plan);
      assert.deepEqual([member, perRow, operation, row, name], [2, true, 3, 4, 'construct']);
      calls.push('debit'); return {$tag: 1, _0: token};
    },
    clientProgramInstalledEffectOperationRetire(original, ack) {
      assert.equal(this, runtime); assert.equal(original, token); assert.equal(ack, true);
      assert(aliasesRetired); calls.push('retire'); return {$tag: 1, _0: cleanupConfirmed};
    },
  };
  const run = {runtime, prepared, request: identity, value: parent, operationPlan: plan,
    readPlan: runtime.clientProgramInstalledEffectManagedOperationPlan, closed: false};
  const child = create({run, memberIndex: 2, rowIndex: 4, operationIndex: 3, operation: 'construct',
    requestsRetired: () => aliasesRetired, construct() {
      assert.equal(children.length, 1, 'the original capture retains before prepare');
      assert.deepEqual(calls, ['debit']); calls.push('construct'); return output;
    }});
  assert.deepEqual(calls, ['debit']);
  assert.equal(await prepare({children, create: () => child}), output);
  assert.equal(await child.release(), false, 'fulfilled construction still has route/request aliases');
  assert.deepEqual(calls, ['debit', 'construct']);
  aliasesRetired = true;
  assert.equal(await child.release(), false, 'false native ACK remains pending');
  assert.equal(child.status().pending, true);
  cleanupConfirmed = true;
  await children[0].prepared.retry();
  assert.equal(child.status().pending, false);
  assert.equal(children[0].prepared.status().pending, false);
  assert.throws(() => child.prepare(), {code: 'InstalledEffectRequestChildRetired'});
});


function constructorControlFixture(construct) {
  const prepared = {}, request = {}, parent = {}, plan = {}, token = {};
  let retired = false, debits = 0, settlements = 0;
  const runtime = {
    clientProgramInstalledEffectManagedOperationPlan: () => ({$tag: 1, _0: plan}),
    clientProgramInstalledEffectOperationBorrow() {debits++; return {$tag: 1, _0: token};},
    clientProgramInstalledEffectOperationRetire(original) {
      assert.equal(original, token); settlements++; return {$tag: 1, _0: true};
    },
  };
  const run = {runtime, prepared, request, value: parent, operationPlan: plan,
    readPlan: runtime.clientProgramInstalledEffectManagedOperationPlan, closed: false};
  return {run, construct, requestsRetired: () => retired,
    memberIndex: 0, rowIndex: 0, operationIndex: 0, operation: 'construct',
    retireAliases() {retired = true;}, debits: () => debits, settlements: () => settlements};
}

test('invalid asynchronous constructor remains borrowed through both original settlements', async () => {
  const {prepareInstalledEffectRequestChild: create} = await import('./installed-effect-plan.mjs');
  for (const rejected of [false, true]) {
    let resolve, reject;
    const original = new Promise((yes, no) => {resolve = yes; reject = no;});
    const f = constructorControlFixture(() => original), child = create(f);
    const pending = child.prepare();
    const refused = assert.rejects(pending, {code: 'InstalledEffectConstructorNotSynchronous'});
    f.retireAliases();
    assert.equal(child.release(), false);
    assert.equal(f.settlements(), 0);
    if (rejected) reject(new Error('original async failure')); else resolve({original: true});
    await refused;
    assert.equal(child.retry(), true);
    assert.equal(f.debits(), 1); assert.equal(f.settlements(), 1);
  }
});

test('native constructor task ignores hostile public then until the original capture settles', async () => {
  const {prepareInstalledRowCaptureChild} = await import('./installed-row-capture-cleanup.mjs');
  for (const kind of ['getter', 'method']) {
    let finish, publicCalls = 0;
    const original = new Promise(resolve => {finish = resolve;});
    const hostile = () => {publicCalls++; throw new Error('replaceable then is not original settlement');};
    Object.defineProperty(original, 'then', kind === 'getter' ? {get: hostile} : {value: hostile});
    const f = constructorControlFixture(() => original), children = [];
    const child = prepareInstalledEffectRequestChild(f);
    const observed = prepareInstalledRowCaptureChild({children, create: () => child})
      .then(value => ({value}), error => ({error}));
    try {
      await new Promise(setImmediate);
      f.retireAliases();
      assert.equal(child.release(), false, kind);
      await children[0].prepared.release();
      assert.equal(children[0].prepared.status().pending, true);
      assert.equal(f.settlements(), 0);
      assert.equal(publicCalls, 0);
    } finally {finish(); await observed;}
    assert.equal((await observed).error?.code, 'InstalledEffectConstructorNotSynchronous');
    await children[0].prepared.retry();
    assert.equal(children[0].prepared.status().pending, false);
    assert.equal(f.debits(), 1); assert.equal(f.settlements(), 1);
  }
});

test('unobservable native constructor task keeps original unjoined custody after observation failure', async () => {
  let finish;
  const original = new Promise(resolve => {finish = resolve;});
  const primary = new Error('original Promise species is unavailable');
  Object.defineProperty(original, 'constructor', {get() {throw primary;}});
  const f = constructorControlFixture(() => original), child = prepareInstalledEffectRequestChild(f);
  const observed = Promise.resolve().then(() => child.prepare()).then(value => ({value}), error => ({error}));
  try {
    assert.strictEqual((await observed).error, primary);
    f.retireAliases(); assert.equal(child.release(), false);
    assert.equal(f.settlements(), 0);
  } finally {finish(); await observed;}
  await new Promise(setImmediate);
  assert.equal(child.retry(), false, 'settlement was not observed by this original child');
  assert.equal(child.status().pending, true); assert.equal(f.settlements(), 0);
});

test('foreign constructor thenable cannot manufacture retirement through its method or throwing accessor', () => {
  for (const kind of ['getter', 'method']) {
    let calls = 0;
    const primary = new Error('unknown original task');
    const original = kind === 'getter' ? {get then() {calls++; throw primary;}}
      : {then(resolve) {calls++; resolve();}};
    const f = constructorControlFixture(() => original), child = prepareInstalledEffectRequestChild(f);
    assert.throws(() => child.prepare(), error => kind === 'getter'
      ? error === primary : error.code === 'InstalledEffectConstructorNotSynchronous');
    f.retireAliases();
    assert.equal(child.release(), false); assert.equal(child.retry(), false);
    assert.equal(child.status().pending, true); assert.equal(f.settlements(), 0);
    assert.equal(calls, kind === 'getter' ? 1 : 0);
  }
});

test('constructor failure and original Plan replacement never retry or release a live alias', async () => {
  const {prepareInstalledEffectRequestChild: create} = await import('./installed-effect-plan.mjs');
  const primary = new Error('original constructor prefix');
  const f = constructorControlFixture(() => {throw primary;}), child = create(f);
  assert.throws(() => child.prepare(), error => error === primary);
  assert.throws(() => child.prepare(), {code: 'InstalledEffectRequestChildAlreadyPrepared'});
  assert.equal(child.release(), false); assert.equal(f.settlements(), 0);
  f.retireAliases(); assert.equal(child.release(), true);
  const foreign = constructorControlFixture(() => assert.fail('must not construct'));
  const retained = create(foreign);
  foreign.run.operationPlan = {};
  assert.throws(() => retained.prepare(), {code: 'ForeignInstalledEffectManagedRun'});
  foreign.retireAliases(); assert.equal(retained.release(), true);
});


test('constructor selection stays on its exact declared original row occurrence',()=>{
  const row=Object.freeze({operation:'construct',extent:{}});
  const base={memberOperations:Object.freeze([]),rowOperations:Object.freeze([row])};
  const plain=captureInstalledEffectPlanRecipe(Object.freeze(base),1);
  assert.equal(Object.hasOwn(plain,'requestConstruction'),false);
  let callbacks=0;
  const accessor=Object.freeze({...base,get requestConstruction(){callbacks++;return {operationIndex:0};}});
  assert.throws(()=>captureInstalledEffectPlanRecipe(accessor,1),{code:'InvalidInstalledEffectPlanRecipe'});
  const proxy=new Proxy(Object.freeze({...base}),{getOwnPropertyDescriptor(){callbacks++;throw new Error('proxy must not run');}});
  assert.throws(()=>captureInstalledEffectPlanRecipe(proxy,1),{code:'InvalidInstalledEffectPlanRecipe'});
  assert.equal(callbacks,0);
  for(const operationIndex of [-1,1,0.5])assert.throws(()=>captureInstalledEffectPlanRecipe(
    Object.freeze({...base,requestConstruction:Object.freeze({operationIndex})}),1),{code:'InvalidInstalledEffectPlanRecipe'});
  const selected=captureInstalledEffectPlanRecipe(Object.freeze({...base,requestConstruction:Object.freeze({operationIndex:0})}),1);
  assert.equal(selected.rowOperations[0].extent,row.extent);assert.equal(selected.requestConstruction.operationIndex,0);
});

test('physical recipe snapshots distinct phase occurrences without sharing the constructor or write slot',()=>{
  const rows=Object.freeze(Array.from({length:5},()=>Object.freeze({operation:'same read name',extent:{}})));
  const phases=['capture-check','apply-check','resume-check','write'];
  const entries=Object.freeze(phases.map((phase,index)=>Object.freeze({phase,operationIndex:index+1,maxRequestBytes:64,maxResponseBytes:128})));
  const original=Object.freeze({memberOperations:Object.freeze([]),rowOperations:rows,
    requestConstruction:Object.freeze({operationIndex:0}),credentialOperations:entries});
  const selected=captureInstalledEffectPlanRecipe(original,5);
  assert.notEqual(selected.credentialOperations,entries);assert(Object.isFrozen(selected.credentialOperations));
  assert.deepEqual(selected.credentialOperations.map(value=>value.operationIndex),[1,2,3,4]);
  for(const changes of [
    [entries[0],entries[0],entries[3]],
    [entries[0],Object.freeze({...entries[3],operationIndex:1})],
    [Object.freeze({...entries[3],operationIndex:0})],
    [entries[0]],
    [Object.freeze({...entries[3],maxRequestBytes:0})],
  ])assert.throws(()=>captureInstalledEffectPlanRecipe(Object.freeze({...original,credentialOperations:Object.freeze(changes)}),5),
    {code:'InvalidInstalledEffectPlanRecipe'});
});

test('fresh pre-write check keeps its fifth physical slot distinct from capture apply resume and send',()=>{
  const phases=['capture-check','apply-check','resume-check','write-check','write'];
  const selected=captureInstalledEffectPlanRecipe(Object.freeze({memberOperations:Object.freeze([]),
    rowOperations:Object.freeze(phases.map(phase=>Object.freeze({operation:phase==='write'?'create':'same Form read',extent:{}}))),
    credentialOperations:Object.freeze(phases.map((phase,operationIndex)=>Object.freeze({phase,operationIndex,maxRequestBytes:64,maxResponseBytes:128})))}),5);
  assert.deepEqual(selected.credentialOperations.map(row=>row.operationIndex),[0,1,2,3,4]);
  assert.equal(selected.rowOperations[3].operation,selected.rowOperations[0].operation);
});

test('capture construction selects its original member extent without consuming a per-row slot',()=>{
  const extent={},member=Object.freeze({operation:'capture-prefix',extent}),row=Object.freeze({operation:'construct',extent:{}});
  const base={memberOperations:Object.freeze([member]),rowOperations:Object.freeze([row]),
    requestConstruction:Object.freeze({operationIndex:0})};
  const selected=captureInstalledEffectPlanRecipe(Object.freeze({...base,captureConstruction:Object.freeze({operationIndex:0})}),2);
  assert.equal(selected.memberOperations[0].extent,extent);
  assert.deepEqual(selected.captureConstruction,{operationIndex:0});
  assert.deepEqual(selected.requestConstruction,{operationIndex:0});
  assert(Object.isFrozen(selected.captureConstruction));
  for(const operationIndex of [-1,1,0.5])assert.throws(()=>captureInstalledEffectPlanRecipe(
    Object.freeze({...base,captureConstruction:Object.freeze({operationIndex})}),2),{code:'InvalidInstalledEffectPlanRecipe'});
  let getters=0;
  assert.throws(()=>captureInstalledEffectPlanRecipe(Object.freeze({...base,get captureConstruction(){getters++;return {};}}),2),
    {code:'InvalidInstalledEffectPlanRecipe'});
  assert.equal(getters,0);
});


// Only the fixed native DATA method is explicit. Original request, Plan,
// Account and physical owners remain separate; no Resource is issued here.
test('standard CREATE snapshots original native implementation limits once without a JS default table', () => {
  let calls = 0;
  const values = [31, 37, 13, 5];
  const native = {installedStandardCreateHttpLimits() {
    assert.equal(this, native);calls++;return values;
  }};
  const limits = captureInstalledStandardCreateLimits(native);
  assert.deepEqual(limits, {maxRequestBytes: 31, maxResponseBytes: 37, maxNodes: 13, maxDepth: 5});
  assert(Object.isFrozen(limits));assert.equal(calls, 1);
  values[0] = 1;assert.equal(limits.maxRequestBytes, 31);
  const failure = {};
  assert.throws(() => captureInstalledStandardCreateLimits({installedStandardCreateHttpLimits() {throw failure;}}),
    error => error === failure);
});

test('standard CREATE refuses missing async inherited or accessor native metadata before use', () => {
  let observed = 0;
  for (const native of [{}, Object.create({installedStandardCreateHttpLimits() {observed++;}}),
    {get installedStandardCreateHttpLimits() {observed++;}},
    {async installedStandardCreateHttpLimits() {observed++;}}]) {
    assert.throws(() => captureInstalledStandardCreateLimits(native), {code: 'InstalledStandardCreateRuntimeUnavailable'});
  }
  for (const values of [[1, 2, 3], [1, 2, 3, 4, 5], [0, 2, 3, 4], [1, 2, 3, 2147483648]]) {
    assert.throws(() => captureInstalledStandardCreateLimits({installedStandardCreateHttpLimits: () => values}),
      {code: 'InvalidInstalledStandardCreateLimits'});
  }
  const values = [1, 2, 3, 4];Object.defineProperty(values, '0', {get() {observed++;return 1;}});
  assert.throws(() => captureInstalledStandardCreateLimits({installedStandardCreateHttpLimits: () => values}),
    {code: 'InvalidInstalledStandardCreateLimits'});
  assert.equal(observed, 0);
});

test('Effect Plan forwards original per-row control material through the one selected typed demand constructor', () => {
  const prepared = {}, identity = {}, extent = {}, controls = {}, installedContracts = {}, demand = {}, plan = {};
  const recipe = captureInstalledEffectPlanRecipe(Object.freeze({
    memberOperations: Object.freeze([]),
    rowOperations: Object.freeze([Object.freeze({operation: 'write', extent})]), controlsPerRow: controls}), 1);
  assert.strictEqual(recipe.controlsPerRow, controls);
  let called = 0;
  const moon = {clientProgramEffectAcquisitionCount: value => {assert.strictEqual(value, prepared); return 0;},
    clientProgramInstalledEffectOperationDemandWithControlsPrepare(p, stage, member, fixed, rows, original) {
      assert.strictEqual(this, moon); assert.strictEqual(p, prepared); assert.deepEqual([stage, member, fixed], [2, 'save', []]);
      assert.strictEqual(rows[0], extent); assert.strictEqual(original, controls); called++;
      return {$tag: 1, _0: demand};
    },
    clientProgramInstalledEffectManagedPlanPrepare(...args) {
      assert.strictEqual(args[0], prepared); assert.strictEqual(args[1], identity);
      assert.strictEqual(args[7], installedContracts); assert.deepEqual(args.at(-1), [demand]);
      return {$tag: 1, _0: plan};
    }};
  const inputs = {installedContracts, values: 'values', fragment: undefined, ordered: undefined};
  assert.strictEqual(prepareInstalledEffectManagedPlan({moon, facts: {prepared, identity}, inputs,
    unit: {stageIndex: 2}, members: [{effectId: 'save'}], recipeFor: () => recipe}), plan);
  assert.equal(called, 1);
  // Missing new support cannot select a legacy demand and discard the material.
  delete moon.clientProgramInstalledEffectOperationDemandWithControlsPrepare;
  moon.clientProgramInstalledEffectOperationDemandPrepare = () => assert.fail('No unfunded fallback');
  assert.throws(() => prepareInstalledEffectManagedPlan({moon, facts: {prepared, identity}, inputs,
    unit: {stageIndex: 2}, members: [{effectId: 'save'}], recipeFor: () => recipe}),
  {code: 'InstalledEffectOperationDemandUnavailable'});
});

test('constructor atomic borrow owns its current boundary without a preceding callbackful Plan getter', () => {
  const parent = {}, prepared = {}, request = {}, plan = {}, token = {};
  let reads = 0, borrows = 0, retired = false;
  const runtime = {
    clientProgramInstalledEffectManagedOperationPlan(p, source, intent) {
      assert.strictEqual(p, parent); assert.strictEqual(source, prepared); assert.strictEqual(intent, request);
      reads++; return {$tag: 1, _0: plan};
    },
    clientProgramInstalledEffectOperationBorrow(p, source, intent, selected) {
      assert.deepEqual([p, source, intent, selected], [parent, prepared, request, plan]);
      borrows++; return {$tag: 1, _0: token};
    },
    clientProgramInstalledEffectOperationRetire(original, done) {
      assert.strictEqual(original, token); assert.equal(done, true); retired = true; return {$tag: 1, _0: true};
    }};
  const run = {runtime, value: parent, prepared, request, operationPlan: plan,
    readPlan: runtime.clientProgramInstalledEffectManagedOperationPlan};
  const child = prepareInstalledEffectRequestChild({run, memberIndex: 0, rowIndex: 0,
    operationIndex: 0, operation: 'construct', construct: () => assert.fail('No constructor selected'), requestsRetired: () => true});
  assert.equal(reads, 0); assert.equal(borrows, 1);
  assert.equal(child.release(), true); assert.equal(retired, true);
});

test('atomic borrow reentry keeps the returned original child before the constructor current fence', async () => {
  const {prepareInstalledRowCaptureChild} = await import('./installed-row-capture-cleanup.mjs');
  for (const failure of ['changed Plan', 'thrown undefined']) {
    const f = constructorControlFixture(() => assert.fail('Reentry cannot reach the constructor'));
    const borrow = f.run.runtime.clientProgramInstalledEffectOperationBorrow;
    f.run.runtime.clientProgramInstalledEffectOperationBorrow = function(...args) {
      const result = Reflect.apply(borrow, this, args);
      if (failure === 'changed Plan') f.run.operationPlan = {};
      else f.run.failure = undefined;
      return result;
    };
    const children = [];
    let caught = false;
    try {await prepareInstalledRowCaptureChild({children, create: () => prepareInstalledEffectRequestChild(f)});}
    catch (cause) {
      caught = true;
      if (failure === 'changed Plan') assert.equal(cause.code, 'ForeignInstalledEffectManagedRun');
      else assert.strictEqual(cause, undefined);
    }
    assert.equal(caught, true); assert.equal(children.length, 1);
    assert.equal(children[0].prepared.status().pending, true);
    assert.equal(f.debits(), 1); assert.equal(f.settlements(), 0);
    f.retireAliases(); await children[0].prepared.release();
    assert.equal(children[0].prepared.status().pending, false); assert.equal(f.settlements(), 1);
  }
});


test('automatic Command recipe forwards opaque native capture originals and separate checked input bounds once',()=>{
  const profile={},capture={},capacities=Array.from({length:6},()=>Object.freeze({})),calls=[];
  const providerMoon={installedStandardCreateConstructionProfile(...args){assert.equal(this,providerMoon);
    assert.deepEqual(args,[128,16,4]);calls.push('request');return profile;},
    installedStandardDriverCaptureConstructionCapacity(...args){assert.equal(this,providerMoon);
      assert.deepEqual(args,[1024,64,8,128,16,4]);calls.push('capture');return capture;}};
  const construction=Object.freeze({write:Object.freeze({operation:'write',maxRequestBytes:256,maxResponseBytes:64}),check:undefined,metadataTextUnits:0});
  const moon={clientProgramInstalledStandardDriverRecipeCapacities(...args){assert.equal(this,moon);
    assert.equal(args[0],profile);assert.equal(args[1],capture);assert.deepEqual(args.slice(2,13),[1024,64,8,128,16,4,256,64,0,0,false]);
    calls.push('fold');return {$tag:1,_0:capacities};},
    clientProgramInstalledStandardCreateRecipeCapacities(){assert.fail('No old fold dropping native capture');},
    clientProgramInstalledEffectCaptureRecipeExtentPrepare(operation,original){assert.equal(this,moon);assert.equal(operation,'write');assert.strictEqual(original,capacities);return {$tag:1,_0:{}};},
    clientProgramInstalledEffectCaptureExtentPrepare(){assert.fail('Do not drop original checked-name term');},
    clientProgramInstalledEffectOperationExtentFromCapacityPrepare(operation,capacity,transfer,physical){return {$tag:1,_0:{operation,capacity,transfer,physical}};}};
  const recipe=prepareInstalledStandardCreatePlanRecipe({moon,providerMoon,construction,
    credentialSite:{construction:{scope:{},issuer:{},limits:{maxSecretBytes:17}}},
    limits:{maxWireBytes:1024,maxNodes:64,maxDepth:8},requestInput:{maxWireBytes:128,maxNodes:16,maxDepth:4},resourceTextUnits:0});
  assert.deepEqual(calls,['request','capture','fold']);assert.equal(recipe.rowOperations.length,2);
  assert.deepEqual(recipe.credentialOperations.map(x=>x.phase),['write']);assert.equal(recipe.rowOperations[0].extent.physical,false);
  assert.equal(recipe.rowOperations[1].extent.physical,true);assert.equal(recipe.controlsPerRow,capacities[4]);
});
