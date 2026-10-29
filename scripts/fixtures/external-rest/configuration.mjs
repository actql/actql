// Explicit ordinary application DATA over the existing physical family
// fixture. No grant, signer, capacity, profile limit or service is created.
import assert from 'node:assert/strict';
import {isAbsolute, join} from 'node:path';

export function externalRestConfiguration(family, {connectorId, profileVersion}) {
  assert(typeof connectorId === 'string' && connectorId.length > 0);
  assert(/^actql-installed-[a-z0-9-]+\/0\.1$/u.test(profileVersion));
  assert(typeof family.accountConfigurationWire === 'string' && family.accountConfigurationWire.length > 0);
  for (const path of [family.paths.project, family.paths.state, family.paths.credentialJournal,
    family.keys.credentialAuthority.privateKeyPath, family.resourceHttps.caPath]) assert(isAbsolute(path));
  const siteProfilePath = join(family.paths.project, 'rest-site.json');
  const sourceProfilePath = join(family.paths.project, 'rest-source.json');
  return Object.freeze({
    files: Object.freeze({
      'rest-site.json': Object.freeze({version: 'actql-installed-rest-site/0.1',
        apiOrigin: family.resourceHttps.origin, caPath: family.resourceHttps.caPath,
        credentialAuthorityId: 'rest-fixture-authority', credentialKeyId: 'rest-fixture-key',
        credentialPrivateKeyPath: family.keys.credentialAuthority.privateKeyPath,
        environment: 'test', journalRoot: family.paths.credentialJournal,
        namespaceId: family.scenario.id, siteGeneration: 0, siteKey: 'rest-fixture-source'}),
      'rest-source.json': Object.freeze({version: profileVersion, connectorId, siteProfilePath,
        accountConfigurationWire: family.accountConfigurationWire}),
    }),
    installation: Object.freeze({directory: family.paths.state, sourceProfilePath,
      authorization: Object.freeze({accountConfiguration: family.accountConfigurationWire})}),
  });
}
