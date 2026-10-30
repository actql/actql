// Pure composition inside the existing installed Effect owner. Original
// Core extents/Plan are DATA until the SAME Request completes and adopts them.
import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
const fail = code => {throw Object.assign(new Error(code), {code});};
const text = value => typeof value === 'string' && value.length > 0;

// The selected Host supplies original typed extents from its actual implementation
// recipe. Names/limits alone cannot select a Plan. Preserve those same opaque
// Core values; this view creates no capacity, admission or permission.
export function captureInstalledEffectPlanRecipe(recipe, maxOperations) {
  if (recipe === undefined) return undefined;
  if (!Number.isSafeInteger(maxOperations) || maxOperations < 1) fail('InvalidInstalledEffectPlanRecipe');
  const own = (value, names) => {
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value) ||
        !Object.isFrozen(value)) fail('InvalidInstalledEffectPlanRecipe');
    const fields = Object.getOwnPropertyDescriptors(value);
    if (Reflect.ownKeys(fields).length !== names.length ||
        names.some(name => !Object.hasOwn(fields[name] ?? {}, 'value'))) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    return fields;
  };
  const fields = own(recipe, ['memberOperations', 'rowOperations']);
  const operations = name => {
    const values = fields[name].value;
    if (!Array.isArray(values) || values.length > maxOperations) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    const entries = own(values, ['length', ...Array.from({length: values.length}, (_, index) => String(index))]);
    return Object.freeze(Array.from({length: values.length}, (_, index) => {
      const entry = own(entries[String(index)].value, ['operation', 'extent']);
      const operation = entry.operation.value, extent = entry.extent.value;
      if (!text(operation) || extent === null || typeof extent !== 'object' ||
          nodeTypes.isProxy(extent)) fail('InvalidInstalledEffectPlanRecipe');
      return Object.freeze({operation, extent});
    }));
  };
  const memberOperations = operations('memberOperations'), rowOperations = operations('rowOperations');
  if (memberOperations.length + rowOperations.length === 0 ||
      memberOperations.length + rowOperations.length > maxOperations) fail('InvalidInstalledEffectPlanRecipe');
  return Object.freeze({memberOperations, rowOperations});
}

export function prepareInstalledEffectManagedPlan({moon, facts, inputs, unit, members, recipeFor}) {
  if (facts?.prepared === undefined || facts.identity === undefined ||
      inputs?.installedContracts === undefined ||
      typeof inputs.values !== 'string' ||
      typeof moon.clientProgramInstalledEffectOperationDemandPrepare !== 'function') {
    fail('InstalledEffectOperationDemandUnavailable');
  }
  // Source acquisition originals cannot be inferred from profile DATA or
  // prepared again under another parent. This first existing connection
  // selects a Source-free Effect; Source/Model supply keeps its own owner.
  if (moon.clientProgramEffectAcquisitionCount(facts.prepared) !== 0 ||
      inputs.modelDemand !== undefined) fail('InstalledEffectPlanInputsUnavailable');
  const demands = members.map(member => {
    const recipe = recipeFor(member);
    if (recipe === undefined) fail('InstalledEffectOperationDemandUnavailable');
    return checked(moon.clientProgramInstalledEffectOperationDemandPrepare(
      facts.prepared, unit.stageIndex, member.effectId,
      recipe.memberOperations.map(entry => entry.extent),
      recipe.rowOperations.map(entry => entry.extent)));
  });
  const construct = facts.queryTimePreparation === undefined
    ? moon.clientProgramInstalledEffectManagedPlanPrepare
    : moon.clientProgramInstalledEffectManagedPlanPrepareAtQueryTime;
  if (typeof construct !== 'function') fail('InstalledEffectPlanRuntimeUnavailable');
  const original = [facts.prepared, facts.identity,
    ...(facts.queryTimePreparation === undefined ? [] : [facts.queryTimePreparation]),
    [], '', '', [], [], inputs.installedContracts,
    inputs.values, inputs.fragment, inputs.ordered, demands];
  // Empty query/evidence strings are unused arguments only for zero Sources;
  // they issue no query contract. Existing Core validates the checked graph.
  return checked(Reflect.apply(construct, moon, original));
}
