// Carry one installed, generation-bound query name publication into the
// in-process Frontend. MoonBit checks its members against the admitted
// Check Environment before lowering or preparing a Program.
import {sourceAliasPublicationOriginal} from './source-alias-publication.mjs';
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const aliasKeys = ['name', 'schemaContractCid', 'sourceRef',
  'sourceViewContractCid'];
const maxAliases = 1024;
const maxPublicationBytes = 1024 * 1024;

const exact = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');

function checkedPublication(moon, environment, publication) {
  const environmentCid = moon.clientProgramCheckingEnvironmentCid(environment);
  if (!cidPattern.test(environmentCid)) {
    throw new TypeError('InvalidPublicSourceEnvironment');
  }
  const selected = publication ?? {environmentCid, aliases: []};
  const hasWrites = Object.hasOwn(selected, 'tableWrites');
  const hasUpdates = Object.hasOwn(selected, 'updateTargets');
  const hasStores = Object.hasOwn(selected, 'storeTargets');
  if (!exact(selected, ['environmentCid', 'aliases', ...(hasWrites ? ['tableWrites'] : []),
    ...(hasUpdates ? ['updateTargets'] : []), ...(hasStores ? ['storeTargets'] : [])]) ||
      selected.environmentCid !== environmentCid ||
      !Array.isArray(selected.aliases) ||
      selected.aliases.length > maxAliases ||
      !selected.aliases.every(alias => exact(alias, aliasKeys) &&
        typeof alias.name === 'string' && alias.name.length > 0 &&
        alias.name.length <= 1024 &&
        typeof alias.sourceRef === 'string' &&
        alias.sourceRef.length > 0 && alias.sourceRef.length <= 4096 &&
        cidPattern.test(alias.sourceViewContractCid) &&
        cidPattern.test(alias.schemaContractCid))) {
    throw new TypeError('InvalidPublicSourcePublication');
  }
  const wire = JSON.stringify(selected);
  if (Buffer.byteLength(wire) > maxPublicationBytes ||
      hasWrites && (!Array.isArray(selected.tableWrites) || selected.tableWrites.length > maxAliases) ||
      hasUpdates && (!Array.isArray(selected.updateTargets) || selected.updateTargets.length > maxAliases) ||
      hasStores && (!Array.isArray(selected.storeTargets) || selected.storeTargets.length > maxAliases)) {
    throw new TypeError('InvalidPublicSourcePublication');
  }
  return wire;
}

export function installNodePublicSourcePreparation({moon, environment,
  publication, allowEffects = false, effectEvidence = [], getPreparedSourceEnvironment}) {
  if (moon === null || typeof moon !== 'object' ||
      typeof moon.clientProgramCheckingEnvironmentCid !== 'function' ||
      environment === undefined || typeof allowEffects !== 'boolean' ||
      !Array.isArray(effectEvidence) || effectEvidence.length > 1024 ||
      (getPreparedSourceEnvironment !== undefined && typeof getPreparedSourceEnvironment !== 'function')) {
    throw new TypeError('InvalidPublicSourcePreparationInstallation');
  }
  const original = sourceAliasPublicationOriginal(moon, environment, publication);
  if (getPreparedSourceEnvironment !== undefined && original === undefined) {
    throw new TypeError('InvalidPublicSourcePublication');
  }
  const preparedEnvironment = original === undefined
    ? (typeof moon.clientProgramPreparePublicSourceEnvironment !== 'function' ? undefined
      : moon.clientProgramPreparePublicSourceEnvironment(environment,
        checkedPublication(moon, environment, publication)))
    : original.preparedEnvironment;
  if (preparedEnvironment === undefined ||
      typeof moon.clientProgramPublicSourceEnvironmentMatches !== 'function' ||
      !moon.clientProgramPublicSourceEnvironmentMatches(preparedEnvironment, environment) ||
      (getPreparedSourceEnvironment !== undefined &&
        getPreparedSourceEnvironment() !== preparedEnvironment)) {
    throw new TypeError('InvalidPublicSourcePublication');
  }
  const currentEnvironment = () => {
    if (getPreparedSourceEnvironment !== undefined &&
        getPreparedSourceEnvironment() !== preparedEnvironment) {
      throw new TypeError('InvalidPublicSourcePreparationEnvironment');
    }
    return preparedEnvironment;
  };
  const evidence = Object.isFrozen(effectEvidence) ? effectEvidence : Object.freeze([...effectEvidence]);
  return Object.freeze({
    // JSON has already selected its Program syntax; it must not be lowered as
    // text. Carry the same snapshotted installation into the existing Effect
    // preparation Owner instead of dropping its original target selections.
    prepareEffect({document, format, supplied}) {
      if (!allowEffects || typeof moon.clientProgramPrepareEffectComputationInPublicEnvironment !== 'function') {
        throw Object.assign(new Error('ClientProgramUnsupported'), {code: 'ClientProgramUnsupported'});
      }
      return moon.clientProgramPrepareEffectComputationInPublicEnvironment(
        document, format, environment, currentEnvironment(), supplied, evidence);
    },
    prepare({document, format, declarations, supplied}) {
      if (typeof moon.clientProgramPrepareSourceComputationInPublicEnvironment !== 'function' ||
          typeof moon.clientProgramSourceComputationPure !== 'function' ||
          typeof moon.clientProgramSourceComputationEffect !== 'function') {
        throw Object.assign(new Error('ClientProgramUnsupported'),
          {code: 'ClientProgramUnsupported'});
      }
      const outcome = moon.clientProgramPrepareSourceComputationInPublicEnvironment(
        document, format, environment, currentEnvironment(), declarations, supplied,
        allowEffects, evidence);
      const pure = moon.clientProgramSourceComputationPure(outcome);
      const effect = moon.clientProgramSourceComputationEffect(outcome);
      if ((pure === undefined) === (effect === undefined) ||
          (effect !== undefined && !allowEffects)) {
        throw new TypeError('InvalidClientSourceComputationOutcome');
      }
      return pure !== undefined ? {kind: 'effect_free', outcome: pure}
        : {kind: 'effectful', outcome: effect};
    },
  });
}
