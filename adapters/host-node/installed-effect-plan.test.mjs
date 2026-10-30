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
