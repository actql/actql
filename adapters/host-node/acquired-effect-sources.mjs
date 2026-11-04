// Select the bounded checked acquisitions from an inert installation inventory.
// This owns no provider work, authorization or continuation identity.
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {installedSourceFor} from './installed-source.mjs';
import {prepareOriginalSourceQuery} from './original-query-preparation.mjs';

// Select original installation inputs from the checked Requests before the
// Plan constructs requirements/acquisitions. Repeated occurrences retain
// separate slots even when they borrow the same immutable Source.
export function selectAcquiredEffectPlanInputs({moon, preparedEffect, requestIdentity,
  sourceProfile, queryContract, evidenceContract}) {
  const count = moon.clientProgramEffectAcquisitionCount(preparedEffect);
  if (![0, 1, 2].includes(count)) throw new TypeError('UnsupportedEffectSourceCount');
  if (count === 0) return undefined;
  const select = moon.clientProgramSelectInstalledEffectSourceInput;
  if (typeof select !== 'function') throw new TypeError('InstalledEffectPlanRuntimeUnavailable');
  const originals = [], declarations = [], providers = [], transferBytes = [], executionBytes = [];
  for (let task = 0; task < count; task++) {
    const selected = checked(Reflect.apply(select, moon, [preparedEffect, requestIdentity, task, 0]));
    if (moon.clientProgramSelectedSourceInputKind(selected) !== 'query') {
      throw new TypeError('UnsupportedEffectSourceRealization');
    }
    const sourceRef = moon.clientProgramSelectedSourceInputRef(selected);
    const adapter = installedSourceFor(sourceProfile, sourceRef);
    const prepare = Object.getOwnPropertyDescriptor(adapter, 'managedEffectPlanSelection')?.value;
    if (typeof prepare !== 'function') throw new TypeError('InstalledEffectPlanInputsUnavailable');
    const original = Reflect.apply(prepare, adapter, []);
    const native = original?.nativeSource;
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
  if (originals.some(value => value.nativeSource !== undefined)) {
    // Nominal inert Source inputs preserve the original occurrence order.
    // Only the SAME Core Plan later prepares each Query/capture once.
    inputs = originals.map(original => {
      const native = original.nativeSource;
      const construct = native === undefined ? moon.clientProgramInstalledEffectRowSourceInputPrepare
        : moon.clientProgramInstalledEffectDuckDBSourceInputPrepare;
      if (typeof construct !== 'function') throw new TypeError('InstalledEffectPlanRuntimeUnavailable');
      return checked(Reflect.apply(construct, moon, native === undefined
        ? [original.declaration, original.provider]
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
  registry, values, fragment, ordered, queryTimePreparation, requestIdentity, managedPlan}) {
  const count = moon.clientProgramEffectAcquisitionCount(preparedEffect);
  if (![0, 1, 2].includes(count)) {
    throw new TypeError('UnsupportedEffectSourceCount');
  }
  const selected = [];
  const owners = new Set();
  for (let task = 0; task < count; task++) {
    let sourceRef;
    if (managedPlan === undefined && requestIdentity !== undefined) {
      // Preadmission reads the original checked Requests. The Plan, not this
      // installation selection, later prepares the Query requirement once.
      const selection = checked(moon.clientProgramSelectInstalledEffectSourceInput(
        preparedEffect, requestIdentity, task, 0));
      if (moon.clientProgramSelectedSourceInputKind(selection) !== 'query') {
        throw new TypeError('UnsupportedEffectSourceRealization');
      }
      sourceRef = moon.clientProgramSelectedSourceInputRef(selection);
    } else {
      const requirement = managedPlan !== undefined
      ? runtimeField(checked(moon.clientProgramInstalledEffectManagedPlanSource(managedPlan, task)), 1)
      : queryTimePreparation === undefined
      ? checked(moon.clientProgramEffectPrepareLocalQueryRequirement(
        preparedEffect, task, 0, registry, values, fragment, ordered))
      : prepareOriginalSourceQuery({moon, preparedEffect, stage: task, input: 0,
        registry, values, fragment, ordered, queryTimePreparation, requestIdentity}).requirement;
      sourceRef = moon.clientProgramQueryRequirementSourceRef(requirement);
    }
    const adapter = installedSourceFor(sourceProfile, sourceRef);
    if (typeof adapter.prepare !== 'function' || typeof adapter.open !== 'function') {
      throw new TypeError('InvalidAcquiredEffectComputationPort');
    }
    if (count === 2 && !['duckdb-acquired', 'row-source-acquired'].includes(adapter.realizationKey)) {
      throw new TypeError('UnsupportedEffectSourceRealization');
    }
    if (owners.has(adapter)) throw new TypeError('DuplicateEffectSourceOwner');
    owners.add(adapter);
    selected.push(Object.freeze({adapter,
      occurrence: Object.freeze({stage: task, input: 0, task})}));
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
