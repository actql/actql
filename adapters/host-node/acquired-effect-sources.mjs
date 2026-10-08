// Select the bounded checked acquisitions from an inert installation inventory.
// This owns no provider work, authorization or continuation identity.
import {checked} from '../host-common/runtime-result.mjs';
import {installedSourceFor} from './installed-source.mjs';

export function selectAcquiredEffectSources({moon, preparedEffect, sourceProfile,
  registry, values, fragment, ordered}) {
  const count = moon.clientProgramEffectAcquisitionCount(preparedEffect);
  if (![0, 1, 2].includes(count)) {
    throw new TypeError('UnsupportedEffectSourceCount');
  }
  const selected = [];
  const owners = new Set();
  for (let task = 0; task < count; task++) {
    const requirement = checked(moon.clientProgramEffectPrepareLocalQueryRequirement(
      preparedEffect, task, 0, registry, values, fragment, ordered));
    const adapter = installedSourceFor(sourceProfile,
      moon.clientProgramQueryRequirementSourceRef(requirement));
    if (typeof adapter.prepare !== 'function' || typeof adapter.open !== 'function') {
      throw new TypeError('InvalidAcquiredEffectComputationPort');
    }
    if (count === 2 && adapter.realizationKey !== 'duckdb-acquired') {
      throw new TypeError('UnsupportedEffectSourceRealization');
    }
    if (owners.has(adapter)) throw new TypeError('DuplicateEffectSourceOwner');
    owners.add(adapter);
    selected.push(Object.freeze({adapter,
      occurrence: Object.freeze({stage: task, input: 0, task})}));
  }
  return Object.freeze(selected);
}
