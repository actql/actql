// Select the bounded checked acquisitions from an inert installation inventory.
// This owns no provider work, authorization or continuation identity.
import {checked} from '../host-common/runtime-result.mjs';
import {installedSourceFor} from './installed-source.mjs';
import {prepareOriginalSourceQuery} from './original-query-preparation.mjs';

export function selectAcquiredEffectSources({moon, preparedEffect, sourceProfile,
  registry, values, fragment, ordered, queryTimePreparation, requestIdentity}) {
  const count = moon.clientProgramEffectAcquisitionCount(preparedEffect);
  if (![0, 1, 2].includes(count)) {
    throw new TypeError('UnsupportedEffectSourceCount');
  }
  const selected = [];
  const owners = new Set();
  for (let task = 0; task < count; task++) {
    const requirement = queryTimePreparation === undefined
      ? checked(moon.clientProgramEffectPrepareLocalQueryRequirement(
        preparedEffect, task, 0, registry, values, fragment, ordered))
      : prepareOriginalSourceQuery({moon, preparedEffect, stage: task, input: 0,
        registry, values, fragment, ordered, queryTimePreparation, requestIdentity}).requirement;
    const adapter = installedSourceFor(sourceProfile,
      moon.clientProgramQueryRequirementSourceRef(requirement));
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
  registry, values, fragment, ordered}) {
  if (!Array.isArray(sources) || sources.length !== 2 ||
      typeof moon?.clientProgramPrepareMultiCapturedEffectInstalledLedger !== 'function') {
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
  const ledger = moon.clientProgramPrepareMultiCapturedEffectInstalledLedger(
    preparedEffect, capacities.map(value => value.capacity),
    capacities.map(value => value.transferBytes),
    capacities.map(value => value.executionBytes), registry, values, fragment, ordered);
  if (ledger === undefined) throw new Error('InstalledMultiSourceLedgerUnavailable');
  return ledger;
}
