import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '@actql/sdk/host-port';
import {checked, rowSourceMapping, invokeScopedCredentialOperation}
  from '@actql/local-node/connector-installation';

const registration = 'external_effect';
const revision = 'external_effect/0.1';
const operation = 'external_effect:events:create';
const origin = 'https://external-effect.fixture.invalid';
const assets = new URL('../../../../src/connectors/external_effect/', import.meta.url);
const fail = code => { throw Object.assign(new Error(code), {code}); };
const text = value => typeof value === 'string' && value.length > 0;
const exact = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') ===
    [...keys].sort().join('\0');
const cid = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value)).digest('hex')}`;

export function checkProfile(profile) {
  if (!exact(profile, ['version', 'connectorId', 'accountConfigurationWire',
    'siteProfilePath']) || profile.version !== 'actql-installed-external-effect/0.1' ||
      !text(profile.connectorId) || !text(profile.accountConfigurationWire) ||
      !text(profile.siteProfilePath) || !isAbsolute(profile.siteProfilePath)) {
    fail('InvalidExternalEffectProfile');
  }
  return Object.freeze({...profile});
}

export async function identityParts(profile, read) {
  const selected = checkProfile(profile);
  return [{...selected, accountConfigurationWire:
    JSON.parse(selected.accountConfigurationWire)}, await read(selected.siteProfilePath)];
}

async function declarationOf(moon, connectorId) {
  const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
    connectorId, registration, revision,
    await readFile(new URL('catalog-views.json', assets), 'utf8'), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const mapping = rowSourceMapping(moon, declaration,
    await readFile(new URL('writes.json', assets), 'utf8'), 'events', [
      {target: 'key', field: 'key', null_behavior: 'reject'},
      {target: 'note', field: 'note', null_behavior: 'reject'},
    ]);
  return {declaration, declared, mapping};
}

export async function publish(profile, {moon}) {
  const {declared, mapping} = await declarationOf(moon, checkProfile(profile).connectorId);
  return Object.freeze({connectorId: profile.connectorId, catalogCid: declared.catalog_cid,
    mappings: [Object.freeze({resource: 'events', kind: 'create',
      target: mapping.target, mappingRef: mapping.mappingRef, mappingCid: mapping.mappingCid})]});
}

async function siteOf(path, readers) {
  const site = await readers.readJson(path, {maxBytes: 16384});
  if (!exact(site, ['resourceOrigin', 'namespaceId', 'environment', 'siteKey',
    'siteGeneration', 'credentialAuthorityId', 'credentialKeyId',
    'credentialPrivateKeyPath', 'journalRoot']) || site.resourceOrigin !== origin ||
      ![site.credentialPrivateKeyPath, site.journalRoot].every(value =>
        text(value) && isAbsolute(value))) fail('InvalidExternalEffectSite');
  return site;
}

export async function load(profile, {root, principalId, moon, providerMoon,
  baseEnvironmentWire, runtimeBundleCid, resolveSecret, ledgerRoot, installation, construction}) {
  if (typeof construction?.prepareAuthoredDeclaration !== 'function' ||
      typeof construction.prepareMappings !== 'function' ||
      typeof construction.openRowSite !== 'function' ||
      typeof construction.createRowEffect !== 'function' ||
      typeof construction.configurationReader?.readOriginalText !== 'function' ||
      typeof construction.configurationReader.readJson !== 'function') {
    fail('ExternalEffectConstructionUnavailable');
  }
  const selected = checkProfile(profile);
  if (typeof providerMoon?.externalEffectRequestJson !== 'function' ||
      typeof providerMoon?.externalEffectObservationJson !== 'function') {
    fail('ExternalEffectProviderMissing');
  }
  const readers = construction.configurationReader;
  const specification = await siteOf(selected.siteProfilePath, readers);
  construction.prepareAuthoredDeclaration(
    await readers.readOriginalText(new URL('catalog-views.json', assets)));
  construction.prepareMappings(await readers.readOriginalText(new URL('writes.json', assets)),
    Object.freeze([Object.freeze({resource: 'events', sources: Object.freeze([
      Object.freeze({target: 'key', field: 'key', null_behavior: 'reject'}),
      Object.freeze({target: 'note', field: 'note', null_behavior: 'reject'}),
    ])})]));
  const connection = 'external_effect:events';
  const {site, authorization} = await construction.openRowSite({profile: specification,
    accountConfiguration: selected.accountConfigurationWire, connection,
    resolveSecret: resolveSecret ?? (async () => fail('FixtureSecretUnavailable')),
    responseHeaders: installation?.responseHeaders ?? [], admitsApprovalTarget: () => false});
  return await construction.createRowEffect({connection, runtimeBundleCid,
    bindingCid: cid({version: 'actql-external-effect-binding/0.1',
      contextCid: authorization.context.contextCid, specification}),
    ledgerRoot, installation,
    driver: {
      kinds: ['create'], writeOperation: () => operation,
      requestFacts: request => ({value: JSON.parse(request.body)}),
      prepareRequest({member, value}) {
        if (member.resource !== 'events' || !exact(value, ['key', 'note']) ||
            typeof value.key !== 'string' || typeof value.note !== 'string') {
          fail('InvalidExternalEffectValue');
        }
        const prepared = JSON.parse(providerMoon.externalEffectRequestJson(value.key, value.note));
        if (prepared.refused) fail(prepared.refused);
        const request = Object.freeze({method: 'POST', path: '/events',
          body: prepared.body, key: value.key});
        // Exact request bytes retain data strings without normalization.
        const requestCid = `sha256:${createHash('sha256')
          .update('external_effect:POST:/events\0').update(request.body).digest('hex')}`;
        return {request, requestCid};
      },
      async send({request, authorization: grant, credential, callResource, signal}) {
        const response = await invokeScopedCredentialOperation({
          authorization: grant, credential, callResource, operation,
          method: request.method, path: request.path, body: request.body,
          responseHeaders: [], maxRequestBytes: 4096, maxResponseBytes: 4096, signal});
        return {observation: {useCid: response.useCid,
          statusCode: response.statusCode, body: response.body}, headers: response.headers};
      },
      project: ({request, observation}) => JSON.parse(
        providerMoon.externalEffectObservationJson(observation.statusCode,
          observation.body, request.key)),
      footprint: () => ({providerNamespace: registration, resourceKind: 'event',
        boundaryCid: cid({origin, namespace: specification.namespaceId})}),
    }});
}
