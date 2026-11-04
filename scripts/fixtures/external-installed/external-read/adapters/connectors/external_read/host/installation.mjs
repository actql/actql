import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '@actql/sdk/host-port';
import {checked, invokeScopedCredentialOperation}
  from '@actql/local-node/connector-installation';

const registration = 'external_read';
const revision = 'external_read/0.1';
const operation = 'external_read:records:read';
const origin = 'https://external-read.fixture.invalid';
const viewsUrl = new URL('../../../../src/connectors/external_read/source-views.json',
  import.meta.url);
const fail = code => { throw Object.assign(new Error(code), {code}); };
const text = value => typeof value === 'string' && value.length > 0;
const exact = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') ===
    [...keys].sort().join('\0');
const cid = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value)).digest('hex')}`;

export function checkProfile(profile) {
  if (!exact(profile, ['version', 'connectorId', 'accountConfigurationWire',
    'siteProfilePath']) ||
      profile.version !== 'actql-installed-external-read-source/0.1' ||
      !text(profile.connectorId) || !text(profile.accountConfigurationWire) ||
      !text(profile.siteProfilePath) || !isAbsolute(profile.siteProfilePath)) {
    fail('InvalidExternalReadProfile');
  }
  return Object.freeze({...profile});
}

export async function identityParts(profile, providerProfile, read) {
  const selected = checkProfile(providerProfile);
  return [{...profile, accountConfigurationWire:
    JSON.parse(profile.accountConfigurationWire)}, await read(selected.siteProfilePath)];
}

async function declarationOf(moon, connectorId) {
  const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
    connectorId, registration, revision, await readFile(viewsUrl, 'utf8'), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  return {declaration, declared};
}

export async function publish(profile, {moon}) {
  const {declared} = await declarationOf(moon, checkProfile(profile).connectorId);
  return Object.freeze({connectorId: profile.connectorId,
    catalogCid: declared.catalog_cid});
}

async function siteOf(path, readers) {
  const site = await readers.readJson(path, {maxBytes: 16384});
  if (!exact(site, ['resourceOrigin', 'namespaceId', 'environment', 'siteKey',
    'siteGeneration', 'credentialAuthorityId', 'credentialKeyId',
    'credentialPrivateKeyPath', 'journalRoot']) || site.resourceOrigin !== origin ||
      ![site.credentialPrivateKeyPath, site.journalRoot].every(value =>
        text(value) && isAbsolute(value))) fail('InvalidExternalReadSite');
  return site;
}

export async function load(profile, {root, principalId, moon, providerMoon,
  baseEnvironmentWire, runtimeBundleCid, resolveSecret, installation, construction}) {
  if (typeof construction?.prepareAuthoredDeclaration !== 'function' ||
      typeof construction.openRowSite !== 'function' ||
      typeof construction.createRowSource !== 'function' ||
      typeof construction.configurationReader?.readOriginalText !== 'function' ||
      typeof construction.configurationReader.readJson !== 'function') {
    fail('ExternalReadConstructionUnavailable');
  }
  const selected = checkProfile(profile);
  if (typeof providerMoon?.externalReadRequestJson !== 'function' ||
      typeof providerMoon?.externalReadPageJson !== 'function') {
    fail('ExternalReadProviderMissing');
  }
  const readers = construction.configurationReader;
  const specification = await siteOf(selected.siteProfilePath, readers);
  const {declared} = construction.prepareAuthoredDeclaration(
    await readers.readOriginalText(viewsUrl));
  const connection = 'external_read:records';
  const target = (resource, fields) => ({
    version: 'actql-external-read-target/0.1', resource, fields: [...fields],
    catalog_cid: declared.catalog_cid, namespace: specification.namespaceId});
  const {site, authorization} = await construction.openRowSite({profile: specification,
    accountConfiguration: selected.accountConfigurationWire, connection,
    resolveSecret: resolveSecret ?? (async () => fail('FixtureSecretUnavailable')),
    responseHeaders: installation?.responseHeaders ?? [],
    admitsApprovalTarget: (binding, resource) => binding?.version ===
      'actql-external-read-target/0.1' && binding.resource === resource &&
      binding.catalog_cid === declared.catalog_cid &&
      binding.namespace === specification.namespaceId && Array.isArray(binding.fields)});
  return await construction.createRowSource({readOperation: operation, physicalTarget: target,
    bindingCid: cid({version: 'actql-external-read-binding/0.1',
      contextCid: authorization.context.contextCid, specification}),
    limits: {maxPages: 2, maxPageBytes: 4096, maxPageRows: 2, maxCaptureRows: 4},
    async readPages({resource, authorizationFor, chargePage, consumePage, signal}) {
      if (resource !== 'records') fail('UndeclaredExternalReadResource');
      let page = 0;
      while (true) {
        signal?.throwIfAborted();
        const request = JSON.parse(providerMoon.externalReadRequestJson(page));
        if (request.refused) fail(request.refused);
        const response = await invokeScopedCredentialOperation({
          authorization: await authorizationFor(page), credential: site.credential,
          callResource: site.callResource, operation, method: 'GET',
          path: request.path, maxRequestBytes: 1024, maxResponseBytes: 4096,
          responseHeaders: [], signal});
        if (!response.accepted || response.statusCode !== 200) {
          fail('ExternalReadProviderRejected');
        }
        // The common acquisition charges the observed bytes before the
        // provider parses them, then admits only the provider's bounded rows.
        const charge = chargePage(response.body);
        const projected = JSON.parse(providerMoon.externalReadPageJson(response.body, page));
        if (projected.refused) fail(projected.refused);
        consumePage(projected.rows, {charge});
        if (projected.next === null) return;
        page = projected.next;
      }
    }});
}
