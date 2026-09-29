// Installation metadata only. Client requests never supply this publication.
export function splitSourceAliasProfile(profile) {
  if (profile === null || typeof profile !== 'object' || Array.isArray(profile)) {
    throw new TypeError('InvalidInstalledSourceProfile');
  }
  const {queryAliases = [], ...providerProfile} = profile;
  if (!Array.isArray(queryAliases) || queryAliases.length > 1024 ||
      Buffer.byteLength(JSON.stringify(queryAliases)) > 1024 * 1024) {
    throw new TypeError('InvalidPublicSourcePublication');
  }
  // The profile was parsed by this loader; copy and freeze each metadata row
  // before it becomes shared with the installed Host's preparation closure.
  const aliases = Object.freeze(queryAliases.map(entry => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry) ||
        Object.keys(entry).sort().join('\0') !==
          ['name', 'schemaContractCid', 'sourceRef', 'sourceViewContractCid'].join('\0') ||
        !Object.values(entry).every(value => typeof value === 'string') ||
        entry.name.length === 0 || entry.name.length > 1024 ||
        entry.sourceRef.length === 0 || entry.sourceRef.length > 4096 ||
        ![entry.schemaContractCid, entry.sourceViewContractCid]
          .every(value => /^sha256:[0-9a-f]{64}$/u.test(value))) {
      throw new TypeError('InvalidPublicSourcePublication');
    }
    return Object.freeze({...entry});
  }));
  return {providerProfile, queryAliases: aliases};
}

export function sourceAliasPublication(moon, environment, aliases = []) {
  const publication = Object.freeze({
    environmentCid: moon.clientProgramCheckingEnvironmentCid(environment),
    aliases});
  if (typeof moon.clientProgramSourcePublicationValid !== 'function' ||
      !moon.clientProgramSourcePublicationValid(environment,
        JSON.stringify(publication))) {
    throw new TypeError('InvalidPublicSourcePublication');
  }
  return publication;
}
