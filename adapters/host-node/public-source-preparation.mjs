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
  const environmentCid = moon.clientProgramCheckEnvironmentCid(environment);
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
  publication}) {
  if (moon === null || typeof moon !== 'object' ||
      typeof moon.clientProgramCheckEnvironmentCid !== 'function' ||
      environment === undefined) {
    throw new TypeError('InvalidPublicSourcePreparationInstallation');
  }
  const aliasesWire = checkedPublication(moon, environment, publication);
  return Object.freeze({
    prepare({document, format, declarations, supplied}) {
      if (typeof moon.clientProgramPrepareSourceWithParameters !== 'function') {
        throw Object.assign(new Error('ClientProgramUnsupported'),
          {code: 'ClientProgramUnsupported'});
      }
      return moon.clientProgramPrepareSourceWithParameters(
        document, format, environment, aliasesWire, declarations, supplied);
    },
  });
}
