// Carry one installed, generation-bound query name publication into the
// in-process Frontend. MoonBit checks its members against the admitted
// Check Environment before lowering or preparing a Program.
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
  if (!exact(selected, ['environmentCid', 'aliases']) ||
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
  if (Buffer.byteLength(wire) > maxPublicationBytes) {
    throw new TypeError('InvalidPublicSourcePublication');
  }
  return wire;
}

export function installNodePublicSourcePreparation({moon, environment,
  publication, allowEffects = false, effectEvidence = []}) {
  if (moon === null || typeof moon !== 'object' ||
      typeof moon.clientProgramCheckingEnvironmentCid !== 'function' ||
      environment === undefined || typeof allowEffects !== 'boolean' ||
      !Array.isArray(effectEvidence) || effectEvidence.length > 1024) {
    throw new TypeError('InvalidPublicSourcePreparationInstallation');
  }
  const aliasesWire = checkedPublication(moon, environment, publication);
  const evidence = Object.freeze([...effectEvidence]);
  return Object.freeze({
    prepare({document, format, declarations, supplied}) {
      if (typeof moon.clientProgramPrepareSourceComputationWithParameters !== 'function' ||
          typeof moon.clientProgramSourceComputationPure !== 'function' ||
          typeof moon.clientProgramSourceComputationEffect !== 'function') {
        throw Object.assign(new Error('ClientProgramUnsupported'),
          {code: 'ClientProgramUnsupported'});
      }
      const outcome = moon.clientProgramPrepareSourceComputationWithParameters(
        document, format, environment, aliasesWire, declarations, supplied,
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
