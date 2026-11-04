import assert from 'node:assert/strict';
import test from 'node:test';
import './effect-control-refusal.test.mjs';
import {types as nodeTypes} from 'node:util';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {captureInstalledEffectPlanRecipe, prepareInstalledEffectManagedPlan,
  captureInstalledStandardCreateLimits, prepareInstalledStandardCreatePlanRecipe, prepareInstalledEffectRequestChild, prepareInstalledEffectOwnedRequestChild,
  prepareInstalledEffectControlConstruction}
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
    const providerMoon={installedStandardCreateConstructionProfile(...geometry){assert.equal(this,providerMoon);assert.deepEqual(geometry,[128,16,4]);calls.push('profile');return profile;}};
    const extents=[];
    const moon={
      clientProgramInstalledStandardCreateRequestRecipeCapacities(...args){
        assert.equal(this,moon);calls.push('capacities');
        assert.deepEqual(args,[profile,512,32,8,128,16,4,128,64,32,16,beforeSend,23,httpsCredentialAuthorizationPrefix.length,
          httpsCredentialResponseHeaderByteLimit,
          Math.max(effectLedgerImplementationBounds.maxEntryBytes,effectLedgerImplementationBounds.maxResponseBytes),
          effectLedgerImplementationBounds.maxOutcomeNodes,effectLedgerImplementationBounds.maxOutcomeDepth,41n,16384]);
        return {$tag:1,_0:capacities};
      },
      clientProgramInstalledEffectHostInputCaptureRecipeExtentPrepare(operation,original,maxBytes,maxNodes,maxDepth){
        assert.equal(this,moon);assert.deepEqual([operation,original,maxBytes,maxNodes,maxDepth],
          ['write',[capacities[0],capacities[1]],512,32,8]);
        assert.strictEqual(original[0],capacities[0]);assert.strictEqual(original[1],capacities[1]);
        const extent={capture:true,hostInputLimits:[maxBytes,maxNodes,maxDepth]};extents.push(extent);return {$tag:1,_0:extent};
      },
      clientProgramInstalledEffectOperationExtentFromCapacityPrepare(operation,capacity,transfer,physical){
        assert.equal(this,moon);const extent={operation,capacity,transfer,physical};extents.push(extent);return {$tag:1,_0:extent};
      },
    };
    const recipe=prepareInstalledStandardCreatePlanRecipe({moon,providerMoon,construction,credentialSite,
      limits:{maxWireBytes:512,maxNodes:32,maxDepth:8},requestInput:{maxWireBytes:128,maxNodes:16,maxDepth:4},resourceTextUnits:7});
    assert.deepEqual(calls,['profile','capacities']);
    assert.equal(recipe.memberOperations.length,2);
    assert.strictEqual(recipe.memberOperations[1].extent,recipe.memberOperations[0].extent);
    assert.deepEqual(recipe.recoveryConstruction,{operationIndex:1});
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

test('confirmed CREATE forwards the original seven-role Native profile and owns separate finalization and read occurrences', () => {
  const profile = {}, capacities = Array.from({length: 8}, () => Object.freeze({}));
  const construction = Object.freeze({
    write: Object.freeze({operation: 'comment-write', maxRequestBytes: 128, maxResponseBytes: 64}),
    check: Object.freeze({operation: 'subject-read', maxRequestBytes: 32, maxResponseBytes: 16}),
    confirmation: Object.freeze({operation: 'comment-read', maxRequestBytes: 32, maxResponseBytes: 16}),
    finalization: Object.freeze({}), metadataTextUnits: 17,
  });
  const credentialSite = Object.freeze({construction: Object.freeze({
    scope: Object.freeze({principal: 'original', siteGeneration: 1}),
    issuer: Object.freeze({authority: 'issuer', keyId: 'key'}),
    limits: Object.freeze({maxBindings: 91, maxSecretBytes: 23}),
  })});
  const providerMoon = {
    installedStandardCreateConfirmedConstructionProfile() {assert.equal(this, providerMoon); return profile;},
    installedStandardCreateConstructionProfile() {assert.fail('no legacy profile substitution');},
  };
  const moon = {
    clientProgramInstalledStandardCreateRequestRecipeCapacities(original) {
      assert.equal(this, moon); assert.strictEqual(original, profile); return {$tag: 1, _0: capacities};
    },
    clientProgramInstalledEffectHostInputCaptureRecipeExtentPrepare(operation, original, maxBytes, maxNodes, maxDepth) {
      assert.equal(this, moon);
      assert.deepEqual([operation, original, maxBytes, maxNodes, maxDepth],
        ['comment-write', [capacities[0], capacities[1]], 512, 32, 8]);
      assert.strictEqual(original[0], capacities[0]); assert.strictEqual(original[1], capacities[1]);
      return {$tag: 1, _0: {capture: true, hostInputLimits: [maxBytes, maxNodes, maxDepth]}};
    },
    clientProgramInstalledEffectOperationExtentFromCapacityPrepare(operation, capacity, transfer, physical) {
      return {$tag: 1, _0: {operation, capacity, transfer, physical}};
    },
  };
  const recipe = prepareInstalledStandardCreatePlanRecipe({moon, providerMoon, construction, credentialSite,
    limits: {maxWireBytes: 512, maxNodes: 32, maxDepth: 8},
    requestInput: {maxWireBytes: 128, maxNodes: 16, maxDepth: 4}, resourceTextUnits: 7});
  assert.equal(recipe.requestConstruction.operationIndex, 0);
  assert.equal(recipe.requestFinalization.operationIndex, 1);
  assert.equal(recipe.rowOperations.length, 8);
  assert.strictEqual(recipe.rowOperations[1].extent.capacity, capacities[6]);
  assert.equal(recipe.rowOperations[1].extent.physical, false);
  assert.equal(recipe.rowOperations[1].extent.transfer, 0n);
  assert.deepEqual(recipe.credentialOperations.map(value => value.phase),
    ['capture-check', 'apply-check', 'resume-check', 'write', 'apply-confirm', 'resume-confirm']);
  assert.deepEqual(recipe.credentialOperations.map(value => value.operationIndex), [2, 3, 4, 5, 6, 7]);
  for (const phase of ['apply-confirm', 'resume-confirm']) {
    const slot = recipe.credentialOperations.find(value => value.phase === phase);
    assert.strictEqual(recipe.rowOperations[slot.operationIndex].extent.capacity, capacities[7]);
    assert.equal(recipe.rowOperations[slot.operationIndex].extent.physical, true);
    assert.equal(recipe.rowOperations[slot.operationIndex].extent.transfer, 49n);
  }
  assert.strictEqual(recipe.controlsPerRow, capacities[4]);
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

for (const model of [false, true]) for (const content of [false, true]) {
  test(`Effect native Plan forwards original Source inputs with Model=${model} Content=${content}`, () => {
    const prepared = {}, identity = {}, queryTime = {}, source = {}, installedContracts = {}, demand = {}, plan = {};
    const modelDemand = model ? {} : undefined, components = model ? Object.freeze([{}]) : undefined;
    const contentPreparation = content ? {} : undefined;
    const sources = Object.freeze({inputs: Object.freeze([source]), queryContract: 'original-query',
      evidenceContract: 'original-evidence', transferBytes: Object.freeze([37n]), executionBytes: Object.freeze([109n])});
    const facts = {prepared, identity, queryTimePreparation: queryTime};
    const inputs = {sourceInputs: sources, installedContracts, values: 'values', fragment: 'fragment', ordered: 'ordered',
      ...(model ? {modelDemand, modelComponents: components} : {}), ...(content ? {contentPreparation} : {})};
    const extent = {}, recipe = captureInstalledEffectPlanRecipe(Object.freeze({memberOperations: Object.freeze([]),
      rowOperations: Object.freeze([Object.freeze({operation: 'write', extent})])}), 1);
    let demands = 0, plans = 0;
    const moon = {clientProgramEffectAcquisitionCount: () => 1,
      clientProgramInstalledEffectOperationDemandPrepare(p, stage, effectId, memberExtents, rowExtents) {
        assert.strictEqual(p, prepared); assert.deepEqual([stage, effectId, memberExtents, rowExtents], [2, 'write', [], [extent]]);
        demands++; return {$tag: 1, _0: demand};
      },
      clientProgramInstalledEffectManagedSourcePlanPrepare(...actual) {
        assert.strictEqual(this, moon); plans++;
        const expected = [prepared, identity, sources.inputs, sources.queryContract, sources.evidenceContract,
          sources.transferBytes, sources.executionBytes, installedContracts, 'values', 'fragment', 'ordered',
          [demand], queryTime, modelDemand, components ?? [], contentPreparation];
        assert.equal(actual.length, expected.length);
        actual.forEach((value, index) => index === 11 || index === 14 && !model
          ? assert.deepEqual(value, expected[index]) : assert.strictEqual(value, expected[index]));
        return {$tag: 1, _0: plan};
      },
      clientProgramInstalledEffectManagedPlanPrepare() {assert.fail('no row-only fallback for a native input');},
    };
    assert.strictEqual(prepareInstalledEffectManagedPlan({moon, facts, inputs,
      unit: {stageIndex: 2}, members: [{effectId: 'write'}], recipeFor: () => recipe}), plan);
    assert.deepEqual([demands, plans], [1, 1]);
    for (const change of [{inputs: Object.freeze([])}, {declarations: Object.freeze([{}])}, {providers: Object.freeze([{}])}]) {
      assert.throws(() => prepareInstalledEffectManagedPlan({moon, facts,
        inputs: {...inputs, sourceInputs: Object.freeze({...sources, ...change})},
        unit: {stageIndex: 2}, members: [{effectId: 'write'}], recipeFor: () => recipe}),
      {code: 'InstalledEffectPlanInputsUnavailable'});
    }
    assert.deepEqual([demands, plans], [1, 1], 'invalid Source originals refuse before any operation constructor');
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
    clientProgramInstalledEffectOperationConstructionRetain(owner, p, r, originalPlan, member, perRow, operation, row, name) {
      assert.equal(this, runtime); assert.equal(owner, parent); assert.equal(p, prepared);
      assert.equal(r, identity); assert.equal(originalPlan, plan);
      assert.deepEqual([member, perRow, operation, row, name], [2, true, 3, 4, 'construct']);
      calls.push('debit'); return {$tag: 1, _0: token};
    },
    clientProgramInstalledEffectOperationConstructionBegin(original) {
      assert.equal(original,token);return {$tag:1,_0:undefined};
    },
    clientProgramInstalledEffectOperationConstructionComplete(original) {
      assert.equal(original, token); return {$tag: 1, _0: undefined};
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
  let retired = false, debits = 0, settlements = 0, entries = 0;
  const runtime = {
    clientProgramInstalledEffectManagedOperationPlan: () => ({$tag: 1, _0: plan}),
    clientProgramInstalledEffectOperationConstructionRetain() {debits++; return {$tag: 1, _0: token};},
    clientProgramInstalledEffectOperationConstructionBegin(original) {
      assert.equal(original,token); entries++; return {$tag:1,_0:undefined};
    },
    clientProgramInstalledEffectOperationConstructionComplete(original) {
      assert.equal(original, token); return {$tag: 1, _0: undefined};
    },
    clientProgramInstalledEffectOperationRetire(original) {
      assert.equal(original, token); settlements++; return {$tag: 1, _0: true};
    },
  };
  const run = {runtime, prepared, request, value: parent, operationPlan: plan,
    readPlan: runtime.clientProgramInstalledEffectManagedOperationPlan, closed: false};
  return {run, construct, requestsRetired: () => retired,
    memberIndex: 0, rowIndex: 0, operationIndex: 0, operation: 'construct', originalToken: token,
    retireAliases() {retired = true;}, debits: () => debits, settlements: () => settlements, entries: () => entries};
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
    clientProgramInstalledEffectOperationConstructionRetain(p, source, intent, selected) {
      assert.deepEqual([p, source, intent, selected], [parent, prepared, request, plan]);
      borrows++; return {$tag: 1, _0: token};
    },
    clientProgramInstalledEffectOperationConstructionBegin(original) {
      assert.strictEqual(original,token); return {$tag:1,_0:undefined};
    },
    clientProgramInstalledEffectOperationConstructionComplete(original) {
      assert.strictEqual(original,token); return {$tag:1,_0:undefined};
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
    const borrow = f.run.runtime.clientProgramInstalledEffectOperationConstructionRetain;
    f.run.runtime.clientProgramInstalledEffectOperationConstructionRetain = function(...args) {
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
    assert.equal(args.at(-1),16384);
    assert.deepEqual(args.slice(-5,-2),[1_000_000,512,16]);
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


test('successful row constructor returns temporary workspace while original request aliases remain held', () => {
  const output = Object.freeze({original: true});
  const f = constructorControlFixture(() => output);
  let completed = 0;
  f.run.runtime.clientProgramInstalledEffectOperationConstructionComplete = function(original) {
    assert.equal(this, f.run.runtime); assert.equal(original, f.originalToken);
    completed++; return {$tag: 1, _0: undefined};
  };
  const child = prepareInstalledEffectRequestChild(f);
  assert.equal(child.prepare(), output);
  assert.equal(completed, 1);
  assert.equal(child.release(), false);
  assert.equal(f.settlements(), 0, 'returned material remains with its original token');
  f.retireAliases(); assert.equal(child.retry(), true);
  assert.equal(f.settlements(), 1);
  assert.equal(completed, 1);
  const member = constructorControlFixture(() => []);
  let premature = 0;
  member.run.runtime.clientProgramInstalledEffectOperationConstructionComplete = () => {
    premature++; return {$tag: 1, _0: undefined};
  };
  const enclosing = prepareInstalledEffectRequestChild({...member, perRow: false});
  enclosing.prepare();
  assert.equal(premature, 1, 'prepare is now the actual member constructor, not a placeholder');
});


test('constructor completion keeps original post-current reentry fences without a second Plan getter', () => {
  for (const mode of ['same', 'replaced Plan', 'thrown undefined']) {
    const output = {};
    const f = constructorControlFixture(() => output);
    let reads = 0, completions = 0;
    f.run.readPlan = f.run.runtime.clientProgramInstalledEffectManagedOperationPlan = () => {
      reads++; return {$tag: 1, _0: f.run.operationPlan};
    };
    f.run.runtime.clientProgramInstalledEffectOperationConstructionComplete = original => {
      assert.equal(original, f.originalToken); completions++;
      if (mode === 'replaced Plan') f.run.operationPlan = {};
      if (mode === 'thrown undefined') f.run.failure = undefined;
      return {$tag: 1, _0: undefined};
    };
    const child = prepareInstalledEffectRequestChild(f);
    if (mode === 'same') assert.equal(child.prepare(), output);
    else {
      let caught = false;
      try {child.prepare();} catch (cause) {
        caught = true;
        if (mode === 'thrown undefined') assert.strictEqual(cause, undefined);
        else assert.equal(cause.code, 'ForeignInstalledEffectManagedRun');
      }
      assert.equal(caught, true);
    }
    assert.equal(reads, 0, 'typed Begin/Complete own current, with callback-free Node post-fences');
    assert.equal(completions, 1);
    assert.equal(child.status().pending, true);
    assert.equal(child.release(), false);
    f.retireAliases(); assert.equal(child.retry(), true);
  }
});


test('member capture retains its original constructor before Source work and prepares actual recovery exactly once later', async () => {
  const cleanup = await import('./installed-row-capture-cleanup.mjs');
  assert.equal(typeof cleanup.retainInstalledRowCaptureChild, 'function');
  const calls = [], children = [], recovery = {wire: 'original'};
  const f = constructorControlFixture(() => {calls.push('native recovery'); return recovery;});
  f.perRow = false;
  f.run.runtime.clientProgramInstalledEffectOperationConstructionComplete = original => {
    assert.equal(original, f.originalToken); calls.push('workspace returned');
    return {$tag: 1, _0: undefined};
  };
  const original = prepareInstalledEffectRequestChild(f);
  const held = cleanup.retainInstalledRowCaptureChild({children, create: () => original});
  original.checkOriginal();
  assert.equal(children.length, 1);
  assert.deepEqual(calls, [], 'no placeholder constructor or premature workspace return');
  calls.push('Source and Preview');
  assert.equal(await held.prepare(), recovery);
  assert.deepEqual(calls, ['Source and Preview', 'native recovery', 'workspace returned']);
  assert.equal(await original.release(), false);
  assert.equal(f.settlements(), 0);
  await assert.rejects(held.prepare(), {code: 'InstalledEffectRequestChildAlreadyPrepared'});
  f.retireAliases(); await children[0].prepared.release();
  assert.equal(f.settlements(), 1);
});


test('deferred member constructor keeps the original asynchronous body until settlement and never completes it', async () => {
  const {retainInstalledRowCaptureChild} = await import('./installed-row-capture-cleanup.mjs');
  let resolve; const original = new Promise(yes=>{resolve=yes;});
  const f=constructorControlFixture(()=>original);f.perRow=false;
  let completes=0;f.run.runtime.clientProgramInstalledEffectOperationConstructionComplete=()=>{completes++;return {$tag:1,_0:undefined};};
  const children=[],child=prepareInstalledEffectRequestChild(f);
  const retained=retainInstalledRowCaptureChild({children,create:()=>child});
  const pending=assert.rejects(retained.prepare(),{code:'InstalledEffectConstructorNotSynchronous'});
  f.retireAliases();await children[0].prepared.release();
  assert.equal(f.settlements(),0);assert.equal(children[0].prepared.status().pending,true);
  resolve({original:true});await pending;
  assert.equal(completes,0);await children[0].prepared.retry();assert.equal(f.settlements(),1);
});


test('retained constructor keeps original inputs before Source and acquires workspace only at actual entry',async()=>{
  const {retainInstalledRowCaptureChild}=await import('./installed-row-capture-cleanup.mjs');
  const events=[],output={original:true},f=constructorControlFixture(()=>{events.push('construct');return output;});
  const originalRetain=f.run.runtime.clientProgramInstalledEffectOperationConstructionRetain;
  const originalBegin=f.run.runtime.clientProgramInstalledEffectOperationConstructionBegin;
  f.run.runtime.clientProgramInstalledEffectOperationConstructionRetain=function(...args){
    events.push('retain inputs');return Reflect.apply(originalRetain,this,args);
  };
  f.run.runtime.clientProgramInstalledEffectOperationConstructionBegin=function(...args){
    events.push('acquire workspace');return Reflect.apply(originalBegin,this,args);
  };
  f.run.runtime.clientProgramInstalledEffectOperationBorrow=()=>assert.fail('no full-body fallback');
  const children=[],child=prepareInstalledEffectRequestChild(f);
  const retained=retainInstalledRowCaptureChild({children,create:()=>child});
  assert.equal(children.length,1);assert.equal(f.debits(),1);assert.equal(f.entries(),0);
  assert.deepEqual(events,['retain inputs']);events.push('Source and Preview');
  assert.strictEqual(await retained.prepare(),output);
  assert.deepEqual(events,['retain inputs','Source and Preview','acquire workspace','construct']);
  assert.equal(f.entries(),1);assert.equal(child.release(),false);
  f.retireAliases();await children[0].prepared.release();assert.equal(f.settlements(),1);
});

test('constructor entry refusal and reentry retain the same original backing without work or retry',()=>{
  for(const mode of ['refusal','replaced Plan','thrown undefined']){
    const f=constructorControlFixture(()=>assert.fail('refused entry must not construct'));
    f.run.runtime.clientProgramInstalledEffectOperationConstructionBegin=function(original){
      assert.strictEqual(original,f.originalToken);
      if(mode==='refusal')throw undefined;
      if(mode==='replaced Plan')f.run.operationPlan={};else f.run.failure=undefined;
      return {$tag:1,_0:undefined};
    };
    const child=prepareInstalledEffectRequestChild(f);let caught=false;
    try{child.prepare();}catch(cause){caught=true;
      if(mode==='replaced Plan')assert.equal(cause.code,'ForeignInstalledEffectManagedRun');
      else assert.strictEqual(cause,undefined);
    }
    assert.equal(caught,true);assert.equal(f.debits(),1);assert.equal(f.settlements(),0);
    assert.throws(()=>child.prepare(),{code:'InstalledEffectRequestChildAlreadyPrepared'});
    assert.equal(child.release(),false);f.retireAliases();assert.equal(child.retry(),true);
    assert.equal(f.settlements(),1);
  }
});


function controlWorkFixture(overrides = {}) {
  const parent={},prepared={},request={},plan={},events=[];
  const runtime={clientProgramInstalledEffectManagedOperationPlan:()=>({$tag:1,_0:plan}),
    clientProgramInstalledEffectOperationControlConstructionBegin(owner,p,r,selected){
      assert.deepEqual([owner,p,r,selected],[parent,prepared,request,plan]);events.push('begin');return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationControlConstructionComplete(owner,p,r,selected){
      assert.deepEqual([owner,p,r,selected],[parent,prepared,request,plan]);events.push('complete');return {$tag:1,_0:undefined};},
    ...overrides};
  const run={runtime,value:parent,prepared,request,operationPlan:plan,readPlan:runtime.clientProgramInstalledEffectManagedOperationPlan,
    closed:false,selecting:false};
  const work=prepareInstalledEffectControlConstruction(run);run.controlConstruction=work;run.retireControlConstruction=work.retire;
  return {run,work,events,runtime};
}

test('captured Effect inventory uses the captured method and same parent before any constructor', () => {
  const inputs = {}, events = [];
  let f;
  f = controlWorkFixture({clientProgramInstalledEffectCapturedInputInventoryRetain(parent, prepared, request, plan, original) {
    assert.strictEqual(this, f.runtime);
    assert.strictEqual(parent, f.run.value);
    assert.strictEqual(prepared, f.run.prepared);
    assert.strictEqual(request, f.run.request);
    assert.strictEqual(plan, f.run.operationPlan);
    assert.strictEqual(original, inputs);
    assert.throws(() => f.work.retainInputs(inputs), {code: 'InstalledEffectControlConstructionPending'});
    events.push('inventory');
    return {$tag: 1, _0: undefined};
  }});
  f.runtime.clientProgramInstalledEffectCapturedInputInventoryRetain = () => assert.fail('replaced method');
  f.work.retainInputs(inputs);
  assert.deepEqual(events, ['inventory']);
  assert.deepEqual(f.events, []);
  assert.equal(f.run.selecting, false);
});

test('captured Effect inventory preserves the original refusal and fences post-current replacement', () => {
  let calls = 0;
  const f = controlWorkFixture({clientProgramInstalledEffectCapturedInputInventoryRetain() {
    calls++;
    throw undefined;
  }});
  for (let index = 0; index < 2; index++) {
    let caught = false;
    try {f.work.retainInputs({});} catch (cause) {caught = true; assert.strictEqual(cause, undefined);}
    assert.equal(caught, true);
  }
  assert.equal(calls, 1);
  assert.equal(f.run.selecting, false);
  let changed;
  changed = controlWorkFixture({clientProgramInstalledEffectCapturedInputInventoryRetain() {
    changed.run.value = {};
    return {$tag: 1, _0: undefined};
  }});
  assert.throws(() => changed.work.retainInputs({}), {code: 'ForeignInstalledEffectManagedRun'});
  assert.deepEqual(changed.events, []);
});

test('control construction enters once before the same original callback and keeps its original receiver and returned DATA', () => {
  const f=controlWorkFixture(),receiver={},input={},output={};
  const method=function(value){assert.equal(this,receiver);assert.equal(value,input);assert.equal(f.run.selecting,true);f.events.push('work');return output;};
  assert.equal(f.work(receiver,method,[input]),output);
  assert.deepEqual(f.events,['begin','work','complete']);assert.equal(f.run.selecting,false);
  f.work(receiver,()=>{f.events.push('second');},[]);
  assert.deepEqual(f.events,['begin','work','complete','begin','second','complete']);
});

test('Host Preview input refines the same control before parsing and retains the original parser', () => {
  const wire = '{"same":"original"}', events = [];
  const spent = new Error('original input already selected');
  let selected = false;
  const parse = JSON.parse;
  let f;
  try {
    JSON.parse = function (input) {
      assert.equal(this, JSON);assert.equal(input, wire);events.push('parse');
      return Reflect.apply(parse, JSON, [input]);
    };
    f = controlWorkFixture({
      clientProgramInstalledEffectManagedPlanHasHostInput: () => true,
      clientProgramInstalledEffectOperationControlInputBegin(owner, prepared, request, plan, input) {
        assert.deepEqual([owner, prepared, request, plan],
          [f.run.value, f.run.prepared, f.run.request, f.run.operationPlan]);
        if (selected) throw spent;
        selected = true;
        assert.equal(input, wire);events.push('input');return {$tag: 1, _0: undefined};
      },
    });
  } finally { JSON.parse = parse; }
  assert.deepEqual(f.work.parsePreview(wire), {same: 'original'});
  assert.deepEqual(events, ['input', 'parse']);
  assert.deepEqual(f.events, ['complete']);
  assert.equal(f.run.selecting, false);
  assert.throws(() => f.work.parsePreview(wire), error => error === spent);
  assert.deepEqual(events, ['input', 'parse']);
  assert.deepEqual(f.events, ['complete']);
});

test('Host Preview capacity refusal preserves its original failure before parsing or another attempt', () => {
  const original = new Error('original input capacity refusal');let entries = 0;
  const f = controlWorkFixture({
    clientProgramInstalledEffectManagedPlanHasHostInput: () => true,
    clientProgramInstalledEffectOperationControlInputBegin() {entries++;throw original;},
  });
  assert.throws(() => f.work.parsePreview('{'), error => error === original);
  assert.throws(() => f.work.parsePreview('{}'), error => error === original);
  assert.equal(entries, 1);assert.deepEqual(f.events, []);
  assert.equal(f.run.selecting, false);assert.equal(f.work.retire(), true);
});

test('Host Preview parse failure keeps the same active prefix and rejects a foreign Run before refinement', () => {
  let entries = 0;
  const f = controlWorkFixture({
    clientProgramInstalledEffectManagedPlanHasHostInput: () => true,
    clientProgramInstalledEffectOperationControlInputBegin() {entries++;return {$tag: 1, _0: undefined};},
  });
  let primary;
  assert.throws(() => f.work.parsePreview('{'), error => {
    primary = error;return error instanceof SyntaxError;
  });
  assert.throws(() => f.work.parsePreview('{}'), error => error === primary);
  assert.equal(entries, 1);assert.deepEqual(f.events, []);
  const foreign = controlWorkFixture({
    clientProgramInstalledEffectManagedPlanHasHostInput: () => true,
    clientProgramInstalledEffectOperationControlInputBegin() {assert.fail('foreign input');},
  });
  foreign.run.value = {};
  assert.throws(() => foreign.work.parsePreview('{}'), {code: 'ForeignInstalledEffectManagedRun'});
});

function retainedPreviewFixture() {
  let parses = 0, begins = 0, currentReads = 0, currentFailure, afterCurrent;
  const spent = new Error('original Preview constructor already selected');
  const parse = JSON.parse;
  let f;
  try {
    JSON.parse = function (...args) {parses++; return Reflect.apply(parse, this, args);};
    f = controlWorkFixture({
      clientProgramInstalledEffectManagedPlanHasHostInput: () => true,
      clientProgramInstalledEffectManagedOperationPlan(parent, prepared, request) {
        assert.strictEqual(this, f.runtime);
        assert.deepEqual([parent, prepared, request], [f.run.value, f.run.prepared, f.run.request]);
        currentReads++;
        if (currentFailure) throw currentFailure;
        const original = f.run.operationPlan;
        afterCurrent?.();
        return {$tag: 1, _0: original};
      },
      clientProgramInstalledEffectOperationControlInputBegin() {
        if (begins++) throw spent;
        return {$tag: 1, _0: undefined};
      },
    });
  } finally {JSON.parse = parse;}
  return {...f, spent, counts: () => ({parses, begins, currentReads}),
    refuseCurrent: error => {currentFailure = error;}, onCurrent: callback => {afterCurrent = callback;}};
}

test('hot Preview recovery borrows the same forest through the original current Plan without another constructor', () => {
  const f = retainedPreviewFixture(), wire = '{"rows":[{"id":"original"}]}';
  const body = f.work.parsePreview(wire);
  f.onCurrent(() => {
    assert.equal(f.work.retire(), false, 'the original current callback cannot cut the borrowed forest');
    assert.throws(() => f.work.parsePreview(wire, true), {code: 'InstalledEffectControlConstructionPending'});
  });
  assert.strictEqual(f.work.parsePreview(wire, true), body);
  assert.strictEqual(f.work.parsePreview(wire, true), body);
  assert.deepEqual(f.counts(), {parses: 1, begins: 1, currentReads: 2});
  assert.deepEqual(f.events, ['complete']);
  f.run.selecting = true;
  assert.equal(f.work.retire(), false);
  assert.throws(() => f.work.parsePreview(wire, true), {code: 'InstalledEffectControlConstructionPending'});
  f.run.selecting = false;
  assert.strictEqual(f.work.parsePreview(wire, true), body);
  assert.equal(f.work.retire(), true);
  assert.throws(() => f.work.parsePreview(wire, true), {code: 'InstalledEffectControlConstructionRetired'});
});

test('cold Preview recovery enters its first constructor while strict repeated parsing remains refused', () => {
  const f = retainedPreviewFixture(), wire = '{"cold":true}';
  const body = f.work.parsePreview(wire, true);
  assert.deepEqual(body, {cold: true});
  assert.deepEqual(f.counts(), {parses: 1, begins: 1, currentReads: 0});
  assert.strictEqual(f.work.parsePreview(wire, true), body);
  assert.throws(() => f.work.parsePreview(wire), error => error === f.spent);
  assert.throws(() => f.work.parsePreview(wire, true), error => error === f.spent);
  assert.deepEqual(f.counts(), {parses: 1, begins: 2, currentReads: 1});
});

test('Preview original borrow refuses foreign wire, stale current and reentrant record replacement', () => {
  const wire = '{"same":true}', f = retainedPreviewFixture();
  f.work.parsePreview(wire);
  assert.throws(() => f.work.parsePreview('{"different":true}', true), {code: 'ForeignInstalledEffectManagedRun'});
  const current = new Error('OriginalPreviewCurrentRefused');
  f.refuseCurrent(current);
  assert.throws(() => f.work.parsePreview(wire, true), error => error === current);
  const changed = retainedPreviewFixture(); changed.work.parsePreview(wire);
  changed.onCurrent(() => {changed.run.operationPlan = {};});
  assert.throws(() => changed.work.parsePreview(wire, true), {code: 'ForeignInstalledEffectManagedRun'});
  assert.deepEqual(changed.counts(), {parses: 1, begins: 1, currentReads: 1});
  f.run.prepared = {};
  assert.throws(() => f.work.parsePreview(wire, true), {code: 'ForeignInstalledEffectManagedRun'});
  assert.deepEqual(f.counts(), {parses: 1, begins: 1, currentReads: 1});
});

test('Preview original borrow preserves failed parser prefix and original thrown undefined', () => {
  const f = retainedPreviewFixture(); let primary;
  assert.throws(() => f.work.parsePreview('{', true), error => {primary = error; return error instanceof SyntaxError;});
  assert.throws(() => f.work.parsePreview('{}', true), error => error === primary);
  assert.deepEqual(f.counts(), {parses: 1, begins: 1, currentReads: 0});
  let calls = 0;
  const missing = controlWorkFixture({clientProgramInstalledEffectManagedPlanHasHostInput: () => true,
    clientProgramInstalledEffectOperationControlInputBegin() {calls++; throw undefined;}});
  for (let index = 0; index < 2; index++) {
    let caught = false;
    try {missing.work.parsePreview('{}', true);} catch (error) {caught = true; assert.strictEqual(error, undefined);}
    assert.equal(caught, true);
  }
  assert.equal(calls, 1);
});

test('Preview original borrow retains an invalid current task until its real settlement', async () => {
  let finish;
  const task = new Promise(resolve => {finish = resolve;});
  const f = controlWorkFixture({clientProgramInstalledEffectManagedPlanHasHostInput: () => true,
    clientProgramInstalledEffectOperationControlInputBegin: () => ({$tag: 1, _0: undefined}),
    clientProgramInstalledEffectManagedOperationPlan: () => task});
  f.work.parsePreview('{}');
  let primary;
  assert.throws(() => f.work.parsePreview('{}', true), error => {
    primary = error;return error.code === 'InvalidInstalledEffectControlConstruction';
  });
  assert.equal(f.run.selecting, true);
  assert.equal(f.work.retire(), false);
  assert.throws(() => f.work.parsePreview('{}', true), error => error === primary);
  finish(); await new Promise(setImmediate);
  assert.equal(f.run.selecting, false);
  assert.equal(f.work.retire(), true);
});

test('control construction retains same thrown undefined and performs no completion or later callback', () => {
  const f=controlWorkFixture();let calls=0;
  assert.throws(()=>f.work({},()=>{calls++;throw undefined;},[]),cause=>cause===undefined);
  assert.throws(()=>f.work({},()=>{calls++;},[]),cause=>cause===undefined);
  assert.equal(calls,1);assert.deepEqual(f.events,['begin']);assert.equal(f.run.selecting,false);
});

test('control construction rejects local reentry before another native debit and preserves original pending frame', () => {
  const f=controlWorkFixture();
  f.work({},()=>{assert.throws(()=>f.work({},()=>assert.fail('reentry'),[]),{code:'InstalledEffectControlConstructionPending'});},[]);
  assert.deepEqual(f.events,['begin','complete']);
});

test('control construction refuses replaced original record before invoking provider', () => {
  const f=controlWorkFixture();
  f.runtime.clientProgramInstalledEffectOperationControlConstructionBegin=()=>assert.fail('captured original method');
  f.run.value={};
  assert.throws(()=>f.work({},()=>assert.fail('foreign'),[]),{code:'ForeignInstalledEffectManagedRun'});
  assert.equal(f.run.selecting,false);
});

test('control construction retains an invalid original native task until its actual settlement', async () => {
  const f=controlWorkFixture();let settle;const original=new Promise(resolve=>{settle=resolve;});
  Object.defineProperty(original,'then',{get(){throw new Error('public then must not replace native original');}});
  assert.throws(()=>f.work({},()=>original,[]),{code:'InvalidInstalledEffectControlConstruction'});
  assert.equal(f.run.selecting,true);assert.deepEqual(f.events,['begin']);
  settle();await new Promise(setImmediate);assert.equal(f.run.selecting,false);
});

test('control construction keeps an unobservable original native task under the same retirement latch', async () => {
  const f=controlWorkFixture();let settle;const original=new Promise(resolve=>{settle=resolve;}),primary=new Error('original species refusal');
  Object.defineProperty(original,'constructor',{get(){throw primary;}});
  assert.throws(()=>f.work({},()=>original,[]),cause=>cause===primary);
  assert.equal(f.run.selecting,true);settle();await new Promise(setImmediate);
  assert.equal(f.run.selecting,true);assert.deepEqual(f.events,['begin']);
});

test('control construction retires its same failed-prefix aliases before parent backing returns', () => {
  const f=controlWorkFixture(),primary=new Error('original prefix');
  assert.throws(()=>f.work({},()=>{throw primary;},[]),cause=>cause===primary);
  assert.equal(f.work.retire(),true);assert.equal(f.work.retire(),true);
  assert.throws(()=>f.work({},()=>assert.fail('retired'),[]),{code:'InstalledEffectControlConstructionRetired'});
});


function originalLedgerControlView(ledger, construction) {
  const source=readFileSync(new URL('./effect-ledger.mjs',import.meta.url),'utf8');
  const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'});
  let open;
  const walk=node=>{if(!node||typeof node!=='object')return;if(node.type==='FunctionDeclaration'&&node.id?.name==='openEffectLedger')open=node;
    for(const value of Object.values(node))if(Array.isArray(value))value.forEach(walk);else if(value&&typeof value==='object')walk(value);};walk(tree);
  const start=open.body.body.find(node=>node.type==='IfStatement'&&source.slice(node.start,node.end).includes('controlConstruction === undefined')&&source.slice(node.start,node.end).includes('return ledger'));
  assert(start);
  return Function('ledger','controlConstruction',source.slice(start.start,open.body.end-1))(ledger,construction);
}

test('original Ledger control view preserves original nested receivers and permits close after the same failure', () => {
  const f=controlWorkFixture(),events=[],primary=new Error('original ledger failure');
  const original=Object.freeze({scopeCid:'scope',inner(){assert.equal(this,original);events.push('inner');return 7;},
    outer(){assert.equal(this,original);events.push('outer');return original.inner();},
    refuse(){throw primary;},close(){assert.equal(this,original);events.push('close');}});
  const view=originalLedgerControlView(original,f.work);
  assert.equal(view.scopeCid,original.scopeCid);assert(Object.isFrozen(view));
  assert.equal(view.outer(),7);assert.deepEqual(f.events,['begin','complete']);
  assert.deepEqual(events,['outer','inner']);
  assert.throws(()=>view.refuse(),cause=>cause===primary);
  assert.throws(()=>view.outer(),cause=>cause===primary);
  view.close();assert.deepEqual(events,['outer','inner','close']);
  assert.equal(f.work.retire(),true);
});

test('original Ledger control view fixed inventory follows its actual thirty-one methods and one DATA field', () => {
  const source=readFileSync(new URL('./effect-ledger.mjs',import.meta.url),'utf8');
  const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'});let ledger;
  const walk=node=>{if(!node||typeof node!=='object')return;if(node.type==='VariableDeclarator'&&node.id?.name==='ledger')ledger=node.init.arguments[0];
    for(const value of Object.values(node))if(Array.isArray(value))value.forEach(walk);else if(value&&typeof value==='object')walk(value);};walk(tree);
  const names=ledger.properties.map(property=>property.key.name);
  assert.equal(names.length,32);assert.equal(new Set(names).size,32);
  assert.equal(names.filter(name=>name!=='scopeCid').length,31);
  assert.equal(names.includes('close'),true);assert.equal(names.includes('append'),true);
});


function originalStoredProjection(read) {
  const source = readFileSync(new URL('./effect-response-recovery.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion:'latest', sourceType:'module'});
  const declaration = tree.body.find(node => node.type === 'ExportNamedDeclaration' &&
    node.declaration?.id?.name === 'recoverProjectedEffectResponse')?.declaration;
  assert(declaration);
  return Function('readAuthorizedEffectResponse', 'fail', 'return ' + source.slice(declaration.start, declaration.end))(
    read, code => {throw Object.assign(new Error(code), {code});});
}

// Exact original recovery caller and actual Run control frame, with explicit
// read/Core ports. This proves call order and alias/failure behavior only; no
// actual Ledger, response admission, Resource, permission or cold Run is issued.
test('original stored caller completes Ledger control scratch before the same provider projector', async () => {
  const f = controlWorkFixture(), stored = Object.freeze({original:true}), ledger = {}, provider = {};
  const outputs = [], calls = [];
  const readMethod = function() {assert.equal(this, ledger);calls.push('read');outputs.push(stored);return stored;};
  const projectMethod = function(value) {assert.equal(this, provider);assert.equal(value, stored);calls.push('project');
    assert.deepEqual(f.events, ['begin','complete','begin']);assert.deepEqual(outputs, [stored]);return 19;};
  const recover = originalStoredProjection(async () => ({stored:f.work(ledger,readMethod,[])}));
  assert.deepEqual(await recover({projectStored:value => f.work(provider,projectMethod,[value])}), {recovered:19});
  assert.deepEqual(calls, ['read','project']);assert.deepEqual(f.events, ['begin','complete','begin','complete']);
  assert.deepEqual(outputs, [stored]);assert.equal(f.work.retire(), true);
});

test('original stored projector failure keeps its same unfinished control prefix without another read', async () => {
  const f = controlWorkFixture(), stored = {}, outputs = [];let reads = 0, threw = false;
  const recover = originalStoredProjection(async () => ({stored:f.work(undefined,() => {reads++;outputs.push(stored);return stored;},[])}));
  try {await recover({projectStored:value => f.work(undefined,() => {assert.equal(value,stored);throw undefined;},[])});}
  catch (cause) {threw = true;assert.equal(cause,undefined);}
  assert.equal(threw,true);assert.equal(reads,1);assert.deepEqual(outputs,[stored]);
  assert.deepEqual(f.events,['begin','complete','begin']);
  assert.throws(() => f.work(undefined,() => 1,[]),cause => cause === undefined);
  assert.equal(f.work.retire(),true);
});


// Actual installed Sheets projection with explicit Native original ports,
// not a provider/Common/normal admission or allocator measurement.
test('standard native JSON projection returns before Host parsing and keeps its original handle', async () => {
  const {projectOwnedSheetsRequest,ownedSheetsRequestCid}=await import('../connectors/sheets/site/sheets-owned-request.mjs');
  const events=[],binding={},handle={};
  const body='original body e\u0301😀';
  const factsWire=JSON.stringify({value:{rows:[{text:'e\u0301😀',flag:false}]},target:{resource:'book'}});
  let nativeActive=false;
  const moon={
    sheetsRangeRequestJson(b,h){assert.equal(this,moon);assert.equal(b,binding);assert.equal(h,handle);
      nativeActive=true;events.push('native.enter');nativeActive=false;events.push('native.return');
      return {$tag:1,_0:factsWire};},
    sheetsRangeRequestBody(b,h){assert.equal(this,moon);assert.equal(b,binding);assert.equal(h,handle);
      events.push('native.body');return {$tag:1,_0:body};},
    sheetsRangeRequestCid(b,h){assert.equal(this,moon);assert.equal(b,binding);assert.equal(h,handle);
      events.push('native.cid');return {$tag:1,_0:'original-request-cid'};},
  };
  const parse=JSON.parse;
  let projected;
  try {
    JSON.parse=function(wire,...rest){assert.equal(nativeActive,false);assert.equal(wire,factsWire);
      events.push('host.parse');return Reflect.apply(parse,this,[wire,...rest]);};
    projected=projectOwnedSheetsRequest(moon,binding,handle);
  } finally {JSON.parse=parse;}
  assert.deepEqual(events,['native.enter','native.return','host.parse','native.body']);
  assert.equal(projected.body,body);assert.equal(projected.value.rows[0].text,'e\u0301😀');
  assert(Object.isFrozen(projected));assert(Object.isFrozen(projected.value.rows));
  assert.equal(ownedSheetsRequestCid(projected,binding),'original-request-cid');
  assert.deepEqual(events,['native.enter','native.return','host.parse','native.body','native.cid']);
  assert.throws(()=>ownedSheetsRequestCid({...projected},binding),{code:'ForeignSheetsRangeRequest'});
});


test('owned Content request child keeps one constructor token until its exact physical cleanup ACK', async () => {
  const f = constructorControlFixture(undefined), output = {}, calls = [];
  let cleanup = false;
  const original = {prepare() {assert.strictEqual(this, original); calls.push('prepare'); return output;},
    release() {assert.strictEqual(this, original); calls.push('release'); return cleanup;},
    retry() {assert.strictEqual(this, original); calls.push('retry'); return cleanup;},
    status() {assert.strictEqual(this, original); return {pending: !cleanup};}};
  const child = prepareInstalledEffectOwnedRequestChild({...f, constructChild() {
    assert.equal(f.entries(), 1, 'actual child factory follows same constructor entry');
    calls.push('factory'); return original;
  }});
  assert.equal(f.debits(), 1); assert.deepEqual(calls, []);
  assert.strictEqual(child.prepare(), output);
  assert.deepEqual(calls, ['factory', 'prepare']);
  f.retireAliases();
  assert.equal(await child.release(), false); assert.equal(f.settlements(), 0);
  assert.equal(child.status().pending, true);
  // Method replacement cannot replace the original pending child's cleanup.
  original.retry = () => assert.fail('replacement cleanup');
  cleanup = true; assert.equal(await child.retry(), true);
  assert.equal(f.settlements(), 1); assert.equal(child.status().pending, false);
  assert.deepEqual(calls, ['factory', 'prepare', 'release', 'retry']);
  assert.throws(() => child.prepare(), {code: 'InstalledEffectRequestChildRetired'});
});

test('owned request failure and reentrant close preserve the same child without repeating its factory', async () => {
  for (const mode of ['undefined failure', 'reentrant close']) {
    const f = constructorControlFixture(undefined); let child, factories = 0, closes = 0;
    const original = {prepare() {if (mode === 'undefined failure') throw undefined; return {};},
      release() {closes++; return true;}, retry() {closes++; return true;}, status: () => ({pending: closes === 0})};
    child = prepareInstalledEffectOwnedRequestChild({...f, constructChild() {
      factories++; if (mode === 'reentrant close') assert.equal(child.release(), false);
      return original;
    }});
    let caught = false;
    try {child.prepare();} catch (error) {caught = true;
      if (mode === 'undefined failure') assert.equal(error, undefined);
      else assert.equal(error.code, 'InstalledEffectRequestChildRetired');}
    assert(caught); assert.equal(f.settlements(), 0);
    f.retireAliases(); await child.release();
    assert.equal(factories, 1); assert.equal(closes, 1); assert.equal(f.settlements(), 1);
  }
});

test('owned request cleanup retains native backing on rejected or pending original release', async () => {
  const f = constructorControlFixture(undefined), failure = new Error('original physical close');
  let ack = false, resolve;
  const pending = new Promise(yes => {resolve = yes;});
  const original = {prepare: () => ({}), release: () => pending,
    retry() {if (!ack) throw failure; return true;}, status: () => ({pending: !ack})};
  const child = prepareInstalledEffectOwnedRequestChild({...f, constructChild: () => original});
  child.prepare(); f.retireAliases();
  const release = child.release(); assert.equal(child.retry(), release);
  assert.equal(f.settlements(), 0); resolve(false); assert.equal(await release, false);
  await assert.rejects(child.retry(), error => error === failure); assert.equal(f.settlements(), 0);
  ack = true; await child.retry(); assert.equal(f.settlements(), 1);
});


test('owned request retries only unread cleanup methods on the same failed child', async () => {
  const f = constructorControlFixture(undefined), failure = new Error('original status observation');
  let observes = 0, closed = false, releases = 0;
  const original = {prepare: () => assert.fail('failed observation precedes preparation'),
    release() {releases++; closed = true; return true;}, retry() {closed = true; return true;},
    get status() {if (++observes === 1) throw failure; return () => ({pending: !closed});}};
  const child = prepareInstalledEffectOwnedRequestChild({...f, constructChild: () => original});
  assert.throws(() => child.prepare(), error => error === failure);
  original.release = () => assert.fail('captured successful method must not be reread');
  f.retireAliases(); await child.release();
  assert.equal(observes, 2); assert.equal(releases, 1); assert.equal(f.settlements(), 1);
});

test('nested owned prepare cannot clear the outer physical cleanup fence', async () => {
  for (const point of ['factory', 'getter', 'status', 'prepare']) {
    const f = constructorControlFixture(undefined); let child, closed = false, closes = 0, nested = false;
    const reenter = () => {
      if (nested) return;
      nested = true;
      assert.throws(() => child.prepare(), {code: 'InstalledEffectRequestChildReentrantPrepare'});
      assert.equal(child.release(), false, 'outer construction still owns the physical child');
      assert.equal(closes, 0);
    };
    const original = {
      get prepare() {if (point === 'getter') reenter(); return () => {
        if (point === 'prepare') reenter(); return {};
      };},
      release() {closes++; closed = true; return true;},
      retry() {closes++; closed = true; return true;},
      status() {if (point === 'status') reenter(); return {pending: !closed};},
    };
    child = prepareInstalledEffectOwnedRequestChild({...f, constructChild() {
      if (point === 'factory') reenter(); return original;
    }});
    assert.throws(() => child.prepare(), {code: 'InstalledEffectRequestChildRetired'});
    assert.equal(closes, 0); assert.equal(f.settlements(), 0);
    f.retireAliases(); assert.equal(await child.release(), true);
    assert.equal(closes, 1); assert.equal(f.settlements(), 1);
  }
});

test('installed recipe keeps member Describe and row target occurrences distinct even at equal indexes', () => {
  const operation = name => Object.freeze({operation: name, extent: {}});
  const memberOperations = Object.freeze([operation('capture'), operation('describe')]);
  const rowOperations = Object.freeze([operation('request'), operation('observe'), operation('write')]);
  const occurrence = (phase, perRow, operationIndex) => Object.freeze({phase, perRow, operationIndex,
    maxRequestBytes: 128, maxResponseBytes: 64});
  const recipe = Object.freeze({memberOperations, rowOperations,
    captureConstruction: Object.freeze({operationIndex: 0}),
    requestConstruction: Object.freeze({operationIndex: 0}),
    credentialOperations: Object.freeze([occurrence('capture-describe', false, 1),
      occurrence('capture-target', true, 1), occurrence('write', true, 2)])});
  const selected = captureInstalledEffectPlanRecipe(recipe, 5);
  assert.deepEqual(selected.credentialOperations.map(value => [value.phase, value.perRow, value.operationIndex]),
    [['capture-describe', false, 1], ['capture-target', true, 1], ['write', true, 2]]);
  for (const entries of [
    [occurrence('capture-describe', false, 0), occurrence('write', true, 2)],
    [occurrence('capture-target', false, 1), occurrence('write', true, 2)],
    [occurrence('capture-describe', true, 1), occurrence('write', true, 2)],
    [occurrence('capture-describe', false, 1), occurrence('apply-describe', false, 1), occurrence('write', true, 2)],
    [occurrence('write', false, 1)],
  ]) assert.throws(() => captureInstalledEffectPlanRecipe(Object.freeze({...recipe,
    credentialOperations: Object.freeze(entries)}), 5), {code: 'InvalidInstalledEffectPlanRecipe'});
});

test('same installed driver keeps create update and upsert recipes tied to their original checked kind', () => {
  const source = readFileSync(new URL('./installed-row-effect.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const declaration = tree.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'captureManagedPlanRecipes');
  assert(declaration);
  const capture = Function('nodeTypes', 'captureInstalledEffectPlanRecipe', 'fail',
    `return (${source.slice(declaration.start, declaration.end)});`)(nodeTypes, captureInstalledEffectPlanRecipe,
      code => {throw Object.assign(new Error(code), {code});});
  const kinds = Object.freeze(['create', 'update', 'upsert']);
  const extents = kinds.map(() => ({}));
  const recipes = Object.freeze(Object.fromEntries(kinds.map((kind, index) => [kind, Object.freeze({
    memberOperations: Object.freeze([]), rowOperations: Object.freeze([
      Object.freeze({operation: `salesforce:record:${kind}`, extent: extents[index]})])})])));
  const selected = capture(recipes, {kinds}, 1);
  assert(Object.isFrozen(selected));
  for (const [index, kind] of kinds.entries()) {
    assert.equal(selected[kind].rowOperations[0].operation, `salesforce:record:${kind}`);
    assert.strictEqual(selected[kind].rowOperations[0].extent, extents[index]);
  }
  let getters = 0;
  for (const invalid of [recipes.create, Object.freeze({...recipes, delete: recipes.create}),
    Object.freeze({create: recipes.create, update: recipes.update}),
    Object.freeze({...recipes, get upsert() {getters++; return recipes.upsert;}})]) {
    assert.throws(() => capture(invalid, {kinds}, 1), {code: 'InvalidInstalledEffectPlanRecipe'});
  }
  assert.equal(getters, 0);
});

test('original recovery input grows the retained constructor before its only work and preserves failure cleanup', () => {
  for (const refused of [false,true]) {
    const events=[], extent={}, output={}, failure=new Error('same input capacity refused');
    const f=constructorControlFixture(()=>{events.push('construct');return output;});
    f.run.runtime.clientProgramInstalledEffectOperationInputBegin=function(token,input){
      assert.equal(this,f.run.runtime);assert.equal(token,f.originalToken);assert.equal(input,extent);
      events.push('grow');if(refused)throw failure;return {$tag:1,_0:undefined};
    };
    const child=prepareInstalledEffectRequestChild({...f,inputExtent(){events.push('input');return extent;}});
    if(refused)assert.throws(()=>child.prepare(),error=>error===failure);
    else assert.equal(child.prepare(),output);
    assert.deepEqual(events,refused?['input','grow']:['input','grow','construct']);
    assert.equal(f.entries(),0,'input entry replaces the old begin instead of repeating its current');
    assert.equal(child.release(),false);f.retireAliases();assert.equal(child.release(),true);
    assert.equal(f.settlements(),1);assert.equal(f.debits(),1);
  }
});


test('saved Ledger codec grows the same active frame before each original wire and returns only its local workspace', () => {
  let f;const receiver={},first={},second={};
  f=controlWorkFixture({
    clientProgramInstalledEffectOperationLedgerCodecBegin(owner,p,r,plan,wire) {
      assert.deepEqual([owner,p,r,plan],[f.run.value,f.run.prepared,f.run.request,f.run.operationPlan]);
      assert.equal(f.run.selecting,true);f.events.push(['codec-begin',wire]);return {$tag:1};
    },
    clientProgramInstalledEffectOperationLedgerCodecComplete() {f.events.push('codec-complete');return {$tag:1};},
  });
  f.work(receiver,function () {
    assert.equal(f.work.ledgerCodec(receiver,function(value){assert.equal(this,receiver);return value;},[first],'first'),first);
    assert.equal(f.work.ledgerCodec(receiver,value=>value,[second],'second'),second);
  },[]);
  assert.deepEqual(f.events,['begin',['codec-begin','first'],'codec-complete',['codec-begin','second'],'codec-complete','complete']);
  assert.equal(f.run.selecting,false);
  assert.throws(()=>f.work.ledgerCodec(receiver,()=>{},[],'outside'),{code:'InstalledEffectControlConstructionPending'});
});

test('saved Ledger codec preserves failed undefined, current and asynchronous prefixes without successful completion', async () => {
  for (const mode of ['undefined','foreign','async','reentry']) {
    let f,settle;const promise=new Promise(resolve=>{settle=resolve;});
    f=controlWorkFixture({
      clientProgramInstalledEffectOperationLedgerCodecBegin(){f.events.push('codec-begin');return {$tag:1};},
      clientProgramInstalledEffectOperationLedgerCodecComplete(){f.events.push('codec-complete');return {$tag:1};},
    });
    let primary;
    assert.throws(()=>f.work({},()=>f.work.ledgerCodec({},()=>{
      if(mode==='undefined')throw undefined;
      if(mode==='foreign'){f.run.request={};return 1;}
      if(mode==='async')return promise;
      return f.work.ledgerCodec({},()=>assert.fail('nested codec'),[],'second');
    },[],'first'),[]),cause=>{primary=cause;return mode==='undefined'?cause===undefined:!!cause.code;});
    assert.deepEqual(f.events,['begin','codec-begin']);
    assert.throws(()=>f.work({},()=>assert.fail('retry after failure'),[]),cause=>cause===primary);
    if(mode==='async'){assert.equal(f.run.selecting,true);settle();await new Promise(setImmediate);assert.equal(f.run.selecting,false);}
    else {settle();assert.equal(f.run.selecting,false);}
  }
});


test('saved Ledger codec binds all original normalizing entries while retaining Receipt controls and same arguments', () => {
  const source=readFileSync(new URL('./effect-ledger.mjs',import.meta.url),'utf8');
  const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'});
  const declaration=tree.body.find(node=>node.type==='FunctionDeclaration'&&node.id?.name==='bindEffectLedgerCodecs');
  assert(declaration);
  const bind=Function('fail',source.slice(declaration.start,declaration.end)+';return bindEffectLedgerCodecs;')(
    code=>{throw Object.assign(new Error(code),{code});});
  const calls=[],wire='original Ledger wire',arg={},result={};
  const names=['admitLedgerEntry','issuePreparedLedgerEntry','issueNextLedgerEntry',
    'issueRowReceiptTerminalEntry','issueRowReceiptTerminalEntryFromResponse'];
  const original=Object.freeze(Object.fromEntries([...names,'issueRowOutcomeReceipt','issueMemberReceiptFromRowPartition'].map(name=>[
    name,function(...args){assert.equal(this,original);calls.push([name,args]);return result;},
  ])));
  const construction=Object.assign(()=>{}, {ledgerCodec(receiver,method,args,input,nodes,depth) {
    assert.equal(receiver,original);assert.equal(method,original[names[calls.length]]);
    assert.equal(input,calls.length===0?wire:undefined);assert.equal(nodes,512);assert.equal(depth,16);return Reflect.apply(method,receiver,args);
  }});
  const selected=bind(original,construction);
  for(const name of names)assert.equal(selected[name](wire,arg,512,16),result);
  assert.equal(selected.issueRowOutcomeReceipt,original.issueRowOutcomeReceipt);
  assert.equal(selected.issueMemberReceiptFromRowPartition,original.issueMemberReceiptFromRowPartition);
  assert(calls.every(([,args])=>args[0]===wire&&args[1]===arg));
  assert.equal(bind(original,undefined),original);
});

test('capture and recovery constructors keep distinct original member slots and the same retained extent', () => {
  const extent = {}, inputExtent = () => extent;
  const original = Object.freeze({
    memberOperations: Object.freeze([0, 1].map(() => Object.freeze({operation: 'capture', extent}))),
    rowOperations: Object.freeze([]), captureConstruction: Object.freeze({operationIndex: 0}),
    recoveryConstruction: Object.freeze({operationIndex: 1, inputExtent}),
  });
  const recipe = captureInstalledEffectPlanRecipe(original, 2);
  assert.notStrictEqual(recipe.captureConstruction, recipe.recoveryConstruction);
  assert.strictEqual(recipe.recoveryConstruction.inputExtent, inputExtent);
  assert.strictEqual(recipe.memberOperations[0].extent, extent);
  assert.strictEqual(recipe.memberOperations[1].extent, extent);
  assert.ok(Object.isFrozen(recipe.recoveryConstruction));
  for (const operationIndex of [-1, 0, 2, 0.5]) {
    assert.throws(() => captureInstalledEffectPlanRecipe(Object.freeze({...original,
      recoveryConstruction: Object.freeze({operationIndex})}), 2), {code: 'InvalidInstalledEffectPlanRecipe'});
  }
  let calls = 0;
  const changed = Object.freeze({...original, get recoveryConstruction() {calls++; return {};}});
  assert.throws(() => captureInstalledEffectPlanRecipe(changed, 2), {code: 'InvalidInstalledEffectPlanRecipe'});
  assert.equal(calls, 0);
});
