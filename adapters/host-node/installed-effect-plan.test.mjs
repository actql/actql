import assert from 'node:assert/strict';
import test from 'node:test';
import {captureInstalledEffectPlanRecipe, prepareInstalledEffectManagedPlan}
  from './installed-effect-plan.mjs';

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
    clientProgramInstalledEffectModelManagedPlanPrepare(...actual) {
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
