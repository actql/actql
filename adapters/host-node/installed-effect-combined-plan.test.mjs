import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareInstalledEffectManagedPlan} from './installed-effect-plan.mjs';

// The actual Host selector forwards original Content/Model/provider handles.
// Core ports are explicit here; the companion Core test checks real ownership.
for (const model of [false, true]) {
  test(`Content Effect Plan retains the original Source${model ? ' and Model' : ''} inputs`, () => {
    const prepared = {}, identity = {}, content = {}, modelDemand = {},
      component = {}, provider = {}, declaration = {}, queryTimePreparation = {};
    const facts = Object.freeze({prepared, identity, queryTimePreparation});
    const sources = Object.freeze({declarations: Object.freeze([declaration]),
      providers: Object.freeze([provider]), transferBytes: Object.freeze([17n]),
      executionBytes: Object.freeze([23n]), queryContract: 'query', evidenceContract: 'evidence'});
    const inputs = Object.freeze({installedContracts: {}, values: 'values', fragment: 'fragment',
      ordered: 'ordered', sourceInputs: sources, contentPreparation: content,
      ...(model ? {modelDemand, modelComponents: Object.freeze([component])} : {})});
    const demand = {}, extent = {}, plan = {};
    let calls = 0;
    const construct = function (...args) {
      assert.strictEqual(this, moon);
      const expected = [prepared, identity, sources.declarations, sources.providers,
        'query', 'evidence', sources.transferBytes, sources.executionBytes,
        inputs.installedContracts, 'values', 'fragment', 'ordered'];
      for (const [index, value] of expected.entries()) assert.strictEqual(args[index], value);
      assert.deepEqual(args[12], [demand]);
      assert.deepEqual(args.slice(13), model
        ? [modelDemand, inputs.modelComponents, queryTimePreparation, content]
        : [content, queryTimePreparation]);
      calls++;
      return {$tag: 1, _0: plan};
    };
    const moon = {
      clientProgramEffectAcquisitionCount: value => {assert.strictEqual(value, prepared); return 1;},
      clientProgramInstalledEffectOperationDemandPrepare(value, stage, id, members, rows) {
        assert.strictEqual(value, prepared); assert.equal(stage, 0); assert.equal(id, 'save');
        assert.deepEqual(members, [extent]); assert.deepEqual(rows, [extent]);
        return {$tag: 1, _0: demand};
      },
      [model ? 'clientProgramInstalledEffectContentModelManagedPlanPrepare'
        : 'clientProgramInstalledEffectContentManagedPlanPrepare']: construct,
      clientProgramInstalledEffectManagedPlanPrepare() {assert.fail('no replacement ordinary Plan');},
    };
    assert.strictEqual(prepareInstalledEffectManagedPlan({moon, facts, inputs,
      unit: {stageIndex: 0}, members: [{effectId: 'save'}],
      recipeFor: () => ({memberOperations: [{extent}], rowOperations: [{extent}]})}), plan);
    assert.equal(calls, 1);
  });
}
