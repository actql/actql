import {checked} from '../host-common/runtime-result.mjs';

// Select existing Common preparation ports, never evaluate or rewrite an
// authored expression in JavaScript. Common owns nominal request/Run checks.
export function prepareOriginalSourceQuery({moon, preparedProgram, preparedEffect,
  stage, input, registry, values, fragment, ordered,
  queryTimePreparation, requestIdentity}) {
  const effectful = preparedEffect !== undefined;
  if ((preparedProgram === undefined) === (preparedEffect === undefined)) {
    throw new TypeError('InvalidOriginalQueryOwner');
  }
  const owner = preparedEffect ?? preparedProgram;
  let acquisition, requirement;
  if (queryTimePreparation !== undefined) {
    const acquire = effectful ? moon.clientProgramEffectPrepareQueryAcquisitionAtQueryTime
      : moon.clientProgramPrepareQueryAcquisitionAtQueryTime;
    const require = effectful ? moon.clientProgramEffectPrepareLocalQueryRequirementAtQueryTime
      : moon.clientProgramPrepareLocalQueryRequirementAtQueryTime;
    if (requestIdentity === undefined || typeof acquire !== 'function' ||
        typeof require !== 'function') throw new Error('OriginalQueryTimeUnavailable');
    acquisition = checked(Reflect.apply(acquire, moon,
      [owner, stage, input, queryTimePreparation, requestIdentity]));
    requirement = checked(Reflect.apply(require, moon,
      [owner, stage, input, queryTimePreparation, requestIdentity,
        registry, values, fragment, ordered]));
  } else {
    acquisition = checked(effectful
      ? moon.clientProgramEffectPrepareQueryAcquisition(owner, stage, input)
      : moon.clientProgramPrepareQueryAcquisition(owner, stage, input));
    requirement = checked(effectful
      ? moon.clientProgramEffectPrepareLocalQueryRequirement(owner,
        stage, input, registry, values, fragment, ordered)
      : moon.clientProgramPrepareLocalQueryRequirement(owner,
        stage, input, registry, values, fragment, ordered));
  }
  return Object.freeze({acquisition, requirement});
}
