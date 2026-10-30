import assert from 'node:assert/strict';
import test from 'node:test';
import {captureInstalledEffectPlanRecipe, prepareInstalledEffectManagedPlan}
  from './installed-effect-plan.mjs';

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
