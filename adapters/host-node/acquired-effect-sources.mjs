// Select the bounded checked acquisitions from an inert installation inventory.
// This owns no provider work, authorization or continuation identity.
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {installedSourceFor} from './installed-source.mjs';
import {prepareOriginalSourceQuery} from './original-query-preparation.mjs';

function effectSourceInputs(moon, preparedEffect) {
  const count = moon.clientProgramEffectAcquisitionCount(preparedEffect);
  if (![0, 1, 2].includes(count)) throw new TypeError('UnsupportedEffectSourceCount');
  if (count === 0) return [];
  const select = moon.clientProgramEffectDirectSourceCoordinates;
  if (typeof select !== 'function') throw new TypeError('InstalledEffectSourceCoordinatesUnavailable');
  const coordinates = checked(Reflect.apply(select, moon, [preparedEffect]));
  if (!Array.isArray(coordinates) || coordinates.length !== count || coordinates.some((value, index) =>
    !Array.isArray(value) || value.length !== 4 || value.some(number => !Number.isSafeInteger(number) || number < 0) ||
    value[2] !== index || coordinates.slice(0, index).some(previous => previous[0] === value[0] && previous[1] === value[1]))) {
    throw new TypeError('InvalidInstalledEffectSourceCoordinates');
  }
  return coordinates;
}

// Select original installation inputs from the checked Requests before the
// Plan constructs requirements/acquisitions. Repeated occurrences retain
// separate slots even when they borrow the same immutable Source.
export function selectAcquiredEffectPlanInputs({moon, preparedEffect, requestIdentity,
  sourceProfile, queryContract, evidenceContract}) {
  const coordinates = effectSourceInputs(moon, preparedEffect);
  const count = coordinates.length;
  if (count === 0) return undefined;
  const select = moon.clientProgramSelectInstalledEffectSourceInput;
  if (typeof select !== 'function') throw new TypeError('InstalledEffectPlanRuntimeUnavailable');
  const originals = [], declarations = [], providers = [], transferBytes = [], executionBytes = [];
  let wholeInput = false;
  for (let task = 0; task < count; task++) {
    const [stage, input] = coordinates[task];
    const selected = checked(Reflect.apply(select, moon, [preparedEffect, requestIdentity, stage, input]));
    const kind = moon.clientProgramSelectedSourceInputKind(selected);
    if (kind !== 'query' && kind !== 'whole-input') {
      throw new TypeError('UnsupportedEffectSourceRealization');
    }
    const sourceRef = moon.clientProgramSelectedSourceInputRef(selected);
    const adapter = installedSourceFor(sourceProfile, sourceRef);
    const prepare = Object.getOwnPropertyDescriptor(adapter, 'managedEffectPlanSelection')?.value;
    if (typeof prepare !== 'function') throw new TypeError('InstalledEffectPlanInputsUnavailable');
    const original = Reflect.apply(prepare, adapter, []);
    const native = original?.nativeSource;
    if (kind === 'whole-input' && native !== undefined) throw new TypeError('UnsupportedEffectSourceRealization');
    if (kind === 'whole-input') {
      if (original?.inputLimits === undefined) throw new TypeError('InstalledEffectSourcePolicyUnavailable');
      wholeInput = true;
    }
    if ((original?.declaration === undefined) === (native === undefined) ||
        typeof original.transferBytes !== 'bigint' ||
        typeof original.executionBytes !== 'bigint' || original.transferBytes < 0n || original.executionBytes < 0n) {
      throw new TypeError('InstalledSourceCapacityUnavailable');
    }
    if (native !== undefined && (native === null || !Object.isFrozen(native) ||
        native.sourceRef !== sourceRef || ![native.sourceRef, native.schema, native.table].every(
          value => typeof value === 'string' && value.length > 0) ||
        !Array.isArray(native.contracts) || !Object.isFrozen(native.contracts) || native.contracts.length !== 3 ||
        native.contracts.some(value => typeof value !== 'string' || value.length === 0) ||
        original.provider !== undefined)) throw new TypeError('InstalledSourceCapacityUnavailable');
    originals.push(original);
    declarations.push(original.declaration); providers.push(original.provider);
    transferBytes.push(original.transferBytes); executionBytes.push(original.executionBytes);
  }
  let inputs;
  if (wholeInput || originals.some(value => value.nativeSource !== undefined)) {
    // Nominal inert Source inputs preserve the original occurrence order.
    // Only the SAME Core Plan later prepares each Query/capture once.
    inputs = originals.map(original => {
      const native = original.nativeSource;
      const construct = native === undefined ? moon.clientProgramInstalledEffectRowSourceInputPrepare
        : moon.clientProgramInstalledEffectDuckDBSourceInputPrepare;
      if (typeof construct !== 'function') throw new TypeError('InstalledEffectPlanRuntimeUnavailable');
      return checked(Reflect.apply(construct, moon, native === undefined
        ? [original.declaration, original.provider,
          ...(original.inputLimits === undefined ? [] : [original.inputLimits])]
        : [native.sourceRef, native.schema, native.table, ...native.contracts]));
    });
  } else if (providers.some(value => value === undefined) && providers.some(value => value !== undefined)) {
    throw new TypeError('InstalledSourceCapacityUnavailable');
  }
  return Object.freeze({...(inputs === undefined ? {declarations: Object.freeze(declarations),
    ...(providers[0] === undefined ? {} : {providers: Object.freeze(providers)})}
    : {inputs: Object.freeze(inputs)}),
    queryContract, evidenceContract, transferBytes: Object.freeze(transferBytes),
    executionBytes: Object.freeze(executionBytes)});
}

export function selectAcquiredEffectSources({moon, preparedEffect, sourceProfile,
  registry, values, fragment, ordered, queryTimePreparation, requestIdentity, managedPlan, managedRun,
  onUnsupportedSelection}) {
  const coordinates = effectSourceInputs(moon, preparedEffect);
  const count = coordinates.length;
  const selected = [];
  const owners = new Set();
  let firstRef;
  for (let task = 0; task < count; task++) {
    const [stage, input, sourceSlot, computeTask] = coordinates[task];
    let kind = 'query';
    let sourceRef;
    if (requestIdentity !== undefined) {
      // Select the adapter from the original checked Request. Its current
      // native/row getter below verifies the SAME retained Plan requirement.
      const selection = checked(moon.clientProgramSelectInstalledEffectSourceInput(
        preparedEffect, requestIdentity, stage, input));
      kind = moon.clientProgramSelectedSourceInputKind(selection);
      if (kind !== 'query' && kind !== 'whole-input') {
        throw new TypeError('UnsupportedEffectSourceRealization');
      }
      sourceRef = moon.clientProgramSelectedSourceInputRef(selection);
    } else {
      const requirement = managedPlan !== undefined
      ? runtimeField(checked(moon.clientProgramInstalledEffectManagedPlanSource(managedPlan, task)), 1)
      : queryTimePreparation === undefined
      ? checked(moon.clientProgramEffectPrepareLocalQueryRequirement(
        preparedEffect, stage, input, registry, values, fragment, ordered))
      : prepareOriginalSourceQuery({moon, preparedEffect, stage, input,
        registry, values, fragment, ordered, queryTimePreparation, requestIdentity}).requirement;
      sourceRef = moon.clientProgramQueryRequirementSourceRef(requirement);
    }
    const adapter = installedSourceFor(sourceProfile, sourceRef);
    if (kind === 'whole-input' && adapter.realizationKey !== 'row-source-acquired') {
      throw new TypeError('UnsupportedEffectSourceRealization');
    }
    if (managedPlan !== undefined && managedRun !== undefined) {
      // Native captures have no RowDeclaration/RowAcquisition. Borrow the
      // original nominal capture from this SAME current parent and Plan.
      const plan = checked(moon.clientProgramInstalledEffectManagedOperationPlan(
        managedRun, preparedEffect, requestIdentity));
      if (plan !== managedPlan) throw new TypeError('ForeignInstalledEffectManagedRun');
      const whole = kind === 'whole-input'
        ? checked(moon.clientProgramInstalledEffectManagedPlanWholeSource(managedPlan, task)) : undefined;
      const requirement = kind === 'whole-input' ? undefined : adapter.realizationKey === 'duckdb-acquired'
        ? runtimeField(checked(moon.clientProgramInstalledEffectManagedDuckDBCapture(
          managedRun, preparedEffect, requestIdentity, task)), 0)
        : runtimeField(checked(moon.clientProgramInstalledEffectManagedPlanSource(managedPlan, task)), 1);
      const actualRef = kind === 'whole-input' ? moon.clientProgramWholeSourceFacts(runtimeField(whole, 1))?.[0]
        : moon.clientProgramQueryRequirementSourceRef(requirement);
      if (actualRef !== sourceRef) {
        throw new TypeError('ForeignInstalledEffectManagedRun');
      }
    }
    if (typeof adapter.prepare !== 'function' || typeof adapter.open !== 'function') {
      throw new TypeError('InvalidAcquiredEffectComputationPort');
    }
    const realization = count === 2 ? adapter.realizationKey : undefined;
    if (count === 2 && !['duckdb-acquired', 'row-source-acquired'].includes(realization)) {
      const error = new TypeError('UnsupportedEffectSourceRealization');
      onUnsupportedSelection?.(error, Object.freeze({reason: 'unsupported-realization', count,
        sourceRef, adapter, realization, previousRef: firstRef, previousAdapter: selected[0]?.adapter}));
      throw error;
    }
    if (owners.has(adapter)) {
      const error = new TypeError('DuplicateEffectSourceOwner');
      onUnsupportedSelection?.(error, Object.freeze({reason: 'duplicate-owner', count,
        sourceRef, adapter, realization, previousRef: firstRef, previousAdapter: selected[0]?.adapter}));
      throw error;
    }
    if (selected.length === 0) firstRef = sourceRef;
    owners.add(adapter);
    selected.push(Object.freeze({adapter, sourceKind: kind,
      occurrence: Object.freeze({stage, input, task: sourceSlot,
        ...(computeTask === sourceSlot ? {} : {computeTask})})}));
  }
  return Object.freeze(selected);
}

// Mixed installed Sources contribute their own opaque checked capture budgets.
// No row-backed capacity can be passed to a nominal DuckDB configuration API.
export function prepareInstalledAcquiredEffectLedger({moon, preparedEffect, sources,
  registry, values, fragment, ordered, requestIdentity}) {
  if (!Array.isArray(sources) || sources.length !== 2) {
    throw new TypeError('InstalledMultiSourceCapacityUnavailable');
  }
  const capacities = sources.map(({adapter, preparedSource, occurrence}, index) => {
    if (!['duckdb-acquired', 'row-source-acquired'].includes(adapter?.realizationKey) ||
        adapter.supportsRetainedRelationOutput !== true ||
        typeof adapter.ledgerCapacity !== 'function' ||
        occurrence?.stage !== index || occurrence.input !== 0 || occurrence.task !== index) {
      throw new TypeError('InstalledMultiSourceCapacityUnavailable');
    }
    const capacity = adapter.ledgerCapacity(preparedSource);
    if (capacity?.capacity === undefined || typeof capacity.transferBytes !== 'bigint' ||
        typeof capacity.executionBytes !== 'bigint' || capacity.transferBytes < 0n ||
        capacity.executionBytes < 0n) {
      throw new TypeError('InstalledSourceCapacityUnavailable');
    }
    return capacity;
  });
  const managedRun = capacities[0].managedRun;
  if (capacities.some(value => value.managedRun !== undefined)) {
    if (managedRun === undefined || capacities.some(value => value.managedRun !== managedRun) ||
        requestIdentity === undefined ||
        typeof moon?.clientProgramInstalledEffectManagedRunPrepareLedger !== 'function') {
      throw new TypeError('InstalledEffectOriginalRunUnavailable');
    }
    // Both Source originals and the generated DAG borrow the same already
    // admitted Effect Run. A missing/foreign original cannot fall back to the
    // legacy scalar constructor, even when the reported byte limits match.
    return checked(moon.clientProgramInstalledEffectManagedRunPrepareLedger(
      managedRun, preparedEffect, requestIdentity,
      capacities.map(value => value.capacity), capacities.map(value => value.transferBytes),
      capacities.map(value => value.executionBytes), registry, values, fragment, ordered));
  }
  if (typeof moon?.clientProgramPrepareMultiCapturedEffectInstalledLedger !== 'function') {
    throw new TypeError('InstalledMultiSourceCapacityUnavailable');
  }
  const ledger = moon.clientProgramPrepareMultiCapturedEffectInstalledLedger(
    preparedEffect, capacities.map(value => value.capacity),
    capacities.map(value => value.transferBytes),
    capacities.map(value => value.executionBytes), registry, values, fragment, ordered);
  if (ledger === undefined) throw new Error('InstalledMultiSourceLedgerUnavailable');
  return ledger;
}
