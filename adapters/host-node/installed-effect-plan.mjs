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
  if (recipe === null || typeof recipe !== 'object' || nodeTypes.isProxy(recipe)) fail('InvalidInstalledEffectPlanRecipe');
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
  const fields = own(recipe, Object.hasOwn(recipe, 'requestConstruction')
    ? ['memberOperations', 'rowOperations', 'requestConstruction'] : ['memberOperations', 'rowOperations']);
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
  let requestConstruction;
  if (fields.requestConstruction !== undefined) {
    const selected = own(fields.requestConstruction.value, ['operationIndex']);
    const operationIndex = selected.operationIndex.value;
    if (!Number.isSafeInteger(operationIndex) || operationIndex < 0 || operationIndex >= rowOperations.length) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    requestConstruction = Object.freeze({operationIndex});
  }
  return Object.freeze({memberOperations, rowOperations,
    ...(requestConstruction === undefined ? {} : {requestConstruction})});
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

// An internal child of the EXISTING capture retainer, not a cleanup/permission
// Owner. The selected implementation's native occurrence is debited before the
// constructor. Its output stays charged until the enclosing original route and
// request aliases have actually retired, including failed constructor prefixes.
export function prepareInstalledEffectRequestChild({run, memberIndex, rowIndex,
  operationIndex, operation, construct: originalConstruct, requestsRetired}) {
  if (run === undefined || typeof originalConstruct !== 'function' ||
      typeof requestsRetired !== 'function') fail('InstalledEffectConstructorUnavailable');
  const {runtime, value: parent, prepared, request, operationPlan: plan, readPlan} = run;
  const borrow = runtime?.clientProgramInstalledEffectOperationBorrow;
  const retire = runtime?.clientProgramInstalledEffectOperationRetire;
  if (![borrow, retire, readPlan].every(method => typeof method === 'function')) {
    fail('InstalledEffectOperationRuntimeUnavailable');
  }
  const current = () => {
    if (Object.hasOwn(run, 'failure')) throw run.failure;
    if (run.closed || run.runtime !== runtime || run.value !== parent || run.prepared !== prepared ||
        run.request !== request || run.operationPlan !== plan || run.readPlan !== readPlan ||
        checked(Reflect.apply(readPlan, runtime, [parent, prepared, request])) !== plan) {
      fail('ForeignInstalledEffectManagedRun');
    }
    // The native current callback can invalidate its original Node record.
    if (Object.hasOwn(run, 'failure')) throw run.failure;
    if (run.closed || run.runtime !== runtime || run.value !== parent || run.prepared !== prepared ||
        run.request !== request || run.operationPlan !== plan || run.readPlan !== readPlan) {
      fail('ForeignInstalledEffectManagedRun');
    }
  };
  current();
  let token = checked(Reflect.apply(borrow, runtime,
    [parent, prepared, request, plan, memberIndex, true, operationIndex, rowIndex, operation]));
  let construct = originalConstruct;
  let state = 'fresh';
  let preparing = false;
  const drain = () => {
    if (state === 'retired') return true;
    if (preparing || requestsRetired() !== true) return false;
    // Clear this child's last input/callback references BEFORE the same native
    // body token may settle. The enclosing capture has already severed output.
    construct = undefined;
    if (checked(Reflect.apply(retire, runtime, [token, true])) !== true) return false;
    token = undefined;
    state = 'retired';
    return true;
  };
  return Object.freeze({
    prepare() {
      if (state === 'retired') fail('InstalledEffectRequestChildRetired');
      if (state !== 'fresh') fail('InstalledEffectRequestChildAlreadyPrepared');
      state = 'preparing';
      preparing = true;
      try {
        current();
        const value = construct();
        const then = value !== null && (typeof value === 'object' || typeof value === 'function')
          ? value.then : undefined;
        if (typeof then === 'function') {
          // Invalid async work remains joined to the SAME retained child until
          // settlement. A rejected/fulfilled Promise is still not a sync value.
          return new Promise((resolve, reject) => Reflect.apply(then, value, [resolve, reject]))
            .then(() => {fail('InstalledEffectConstructorNotSynchronous');},
              () => {fail('InstalledEffectConstructorNotSynchronous');})
            .finally(() => {preparing = false; state = 'failed';});
        }
        current();
        state = 'prepared';
        preparing = false;
        return value;
      } catch (error) {
        preparing = false;
        state = 'failed';
        throw error;
      }
    },
    release: drain, retry: drain,
    status: () => Object.freeze({pending: state !== 'retired'}),
  });
}
