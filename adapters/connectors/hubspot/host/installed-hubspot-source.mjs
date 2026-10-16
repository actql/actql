// A HubSpot installation supplies original metadata and physical reads only.
// The standard Host owns the declaration, Account gate, RowRun and capture.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {readFile} from 'node:fs/promises';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {readSourceProfileJson} from '../../../host-node/source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {createInstalledRowSource, installRowSourceAuthorization,
  openRowSourceCredentialSite, rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {openHttpsCredentialBinding, closeHttpsCredentialBinding} from
  '../../../site-node/https-credential-resource.mjs';
import {readHubSpotObjects, HUBSPOT_PROPERTIES_READ_OPERATION,
  HUBSPOT_OBJECT_LIST_OPERATION} from '../site/hubspot-object-read.mjs';
import {HUBSPOT_ACCOUNT_DETAILS_OPERATION} from '../site/hubspot-account-read.mjs';

export const INSTALLED_HUBSPOT_SOURCE_VERSION = 'actql-installed-hubspot-source/0.1';
export const INSTALLED_HUBSPOT_SITE_VERSION = 'actql-installed-hubspot-site/0.1';
const registration = 'hubspot', revision = 'hubspot/0.1';
const profileKeys = ['version', 'connectorId', 'portalId', 'resources', 'metadataPath',
  'siteProfilePath', 'metadataResources', 'accountConfigurationWire', 'limits'];
const siteKeys = ['version', 'apiOrigin', 'credentialAuthorityId', 'credentialKeyId',
  'credentialPrivateKeyPath', 'environment', 'journalRoot', 'namespaceId',
  'siteGeneration', 'siteKey', 'tokenEnvironment'];
const limitKeys = ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxProperties',
  'maxNameUnits', 'maxPages', 'maxRows', 'maxRequests', 'perPage', 'maxColumns',
  'maxCursorUnits', 'maxValueNodes', 'maxValueTextBytes', 'maxRowsWireBytes',
  'maxRowsWireNodes', 'maxRowsWireDepth', 'maxObjects', 'maxDeclarationBytes',
  'maxDeclarationNodes', 'maxSecretBytes'];
const fail = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const text = value => typeof value === 'string' && value.length > 0 && value.isWellFormed() &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const absolute = value => text(value) && isAbsolute(value);
const positive = value => Number.isSafeInteger(value) && value > 0 && value < 2147483647;
const closed = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const canonical = value => canonicalJson(value, {dataKeys: true});
const cid = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;

export function checkInstalledHubSpotSourceProfile(profile) {
  if (!closed(profile, profileKeys) || profile.version !== INSTALLED_HUBSPOT_SOURCE_VERSION ||
      !text(profile.connectorId) || typeof profile.portalId !== 'string' || !/^[1-9][0-9]{0,10}$/u.test(profile.portalId) ||
      !absolute(profile.metadataPath) || !absolute(profile.siteProfilePath) ||
      !text(profile.accountConfigurationWire) || !closed(profile.limits, limitKeys) ||
      !limitKeys.every(key => positive(profile.limits[key])) ||
      !closed(profile.metadataResources, ['account', 'properties']) ||
      !Object.values(profile.metadataResources).every(text) ||
      profile.metadataResources.account === profile.metadataResources.properties ||
      !Array.isArray(profile.resources) || profile.resources.length === 0 ||
      profile.resources.length > profile.limits.maxObjects ||
      !profile.resources.every(value => closed(value, ['resource', 'objectType']) &&
        text(value.resource) && text(value.objectType) &&
        value.objectType !== '.' && value.objectType !== '..') ||
      new Set(profile.resources.map(value => value.resource)).size !== profile.resources.length ||
      profile.resources.some(value => Object.values(profile.metadataResources).includes(value.resource)) ||
      profile.limits.maxPages > profile.limits.maxRequests ||
      profile.limits.perPage > profile.limits.maxRows) fail('InvalidInstalledHubSpotSourceProfile');
  return Object.freeze({...profile, resources: Object.freeze(profile.resources.map(value => Object.freeze({...value}))),
    limits: Object.freeze({...profile.limits}), metadataResources: Object.freeze({...profile.metadataResources})});
}

function checkSite(site) {
  const {caPath, ...rest} = site ?? {};
  let origin;
  try {origin = new URL(rest.apiOrigin);} catch { /* Closed rejection below. */ }
  if (!closed(rest, siteKeys) || rest.version !== INSTALLED_HUBSPOT_SITE_VERSION ||
      origin?.protocol !== 'https:' || origin.origin !== rest.apiOrigin ||
      !['credentialAuthorityId', 'credentialKeyId', 'environment', 'namespaceId', 'siteKey'].every(key => text(rest[key])) ||
      !absolute(rest.credentialPrivateKeyPath) || !absolute(rest.journalRoot) ||
      (caPath !== undefined && !absolute(caPath)) ||
      !Number.isSafeInteger(rest.siteGeneration) || rest.siteGeneration < 0 ||
      !/^[A-Z_][A-Z0-9_]{0,63}$/u.test(rest.tokenEnvironment)) fail('InvalidInstalledHubSpotSite');
  return Object.freeze({...rest, ...(caPath === undefined ? {} : {caPath})});
}

async function readInputs(profile) {
  const installed = checkInstalledHubSpotSourceProfile(profile);
  const site = checkSite(await readSourceProfileJson(installed.siteProfilePath));
  const metadata = await readSourceProfileJson(installed.metadataPath);
  if (!closed(metadata, ['version', 'connectorId', 'portalId', 'apiOrigin', 'accountBody', 'objects']) ||
      metadata.version !== 'actql-hubspot-read-metadata/0.1' ||
      metadata.connectorId !== installed.connectorId || metadata.portalId !== installed.portalId ||
      metadata.apiOrigin !== site.apiOrigin || !Array.isArray(metadata.objects) ||
      metadata.objects.length !== installed.resources.length) fail('InvalidInstalledHubSpotMetadata');
  const decode = body => {
    if (typeof body !== 'string' || body.length > Math.ceil(installed.limits.maxResponseBytes / 3) * 4) {
      fail('InvalidInstalledHubSpotMetadata');
    }
    const bytes = Buffer.from(body, 'base64');
    if (bytes.byteLength > installed.limits.maxResponseBytes || bytes.toString('base64') !== body) {
      fail('InvalidInstalledHubSpotMetadata');
    }
    return bytes;
  };
  const account = decode(metadata.accountBody), objects = new Map();
  for (const object of metadata.objects) {
    if (!closed(object, ['resource', 'objectType', 'propertiesBody']) ||
        objects.has(object.resource) || !installed.resources.some(value =>
          value.resource === object.resource && value.objectType === object.objectType)) {
      fail('InvalidInstalledHubSpotMetadata');
    }
    objects.set(object.resource, {objectType: object.objectType, body: decode(object.propertiesBody)});
  }
  return {installed, site, metadata, account, objects};
}

export async function installedHubSpotSourceIdentityParts(profile, providerProfile) {
  const {site, metadata} = await readInputs(providerProfile);
  const ca = site.caPath === undefined ? undefined : await readFile(site.caPath);
  return [{...profile, accountConfigurationWire: JSON.parse(profile.accountConfigurationWire)}, site,
    {metadataCid: cid(metadata), ...(ca === undefined ? {} : {caSha256: createHash('sha256').update(ca).digest('hex')})}];
}

export async function loadInstalledHubSpotSource(profile, {root, principalId, moon,
  providerMoon: provider, baseEnvironmentWire, runtimeBundleCid, resolveSecret}) {
  const {installed, site: siteProfile, metadata, account, objects} = await readInputs(profile);
  const {limits} = installed;
  const identity = JSON.parse(provider.hubspotRecheckAccountIdentityJson(account, installed.portalId,
    limits.maxResponseBytes, limits.maxNodes, limits.maxDepth));
  if (identity.refused !== undefined || identity.account?.portalId !== installed.portalId) {
    fail('InvalidInstalledHubSpotAccount');
  }
  const catalogs = new Map(), views = [];
  for (const {resource, objectType} of installed.resources) {
    const catalog = checked(provider.hubspotProjectProperties(objects.get(resource).body, objectType,
      limits.maxResponseBytes, limits.maxNodes, limits.maxDepth, limits.maxProperties, limits.maxNameUnits));
    const names = provider.hubspotPropertyCatalogNames(catalog);
    const wire = checked(provider.hubspotObjectSchemaWire(catalog, names, limits.maxColumns,
      limits.maxNameUnits, limits.maxDeclarationBytes, limits.maxDeclarationNodes, limits.maxDepth));
    catalogs.set(resource, catalog);
    views.push({resource, resource_kind: 'object', schema_wire: wire,
      facts_wire: provider.hubspotObjectRelationFactsWire(),
      schema_cid: `sha256:${createHash('sha256').update(wire).digest('hex')}`});
  }
  const declaration = checked(moon.clientProgramRowSourceRestoreRelationDeclaration(installed.connectorId,
    registration, revision, JSON.stringify({views}), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment(baseEnvironmentWire, declared);
  const authorization = await installRowSourceAuthorization({root, principalId,
    connectorRegistration: registration, accountConfiguration: installed.accountConfigurationWire});
  const connection = `hubspot:${installed.connectorId}`;
  const target = (resource, fields) => Object.freeze({version: 'actql-installed-hubspot-target/0.1',
    apiOrigin: siteProfile.apiOrigin, portalId: installed.portalId, resource,
    objectType: objects.get(resource)?.objectType, metadataCid: cid(metadata), fields: Object.freeze([...fields])});
  const admitsApprovalTarget = (binding, resource) => {
    const view = declared.views.find(value => value.resource === resource);
    return view !== undefined && Array.isArray(binding?.fields) &&
      new Set(binding.fields).size === binding.fields.length && binding.fields.every(field => view.fields.includes(field)) &&
      canonical(binding) === canonical(target(resource, binding.fields));
  };
  const ca = siteProfile.caPath === undefined ? undefined : await readFile(siteProfile.caPath);
  const site = await openRowSourceCredentialSite({profile: {...siteProfile, resourceOrigin: siteProfile.apiOrigin},
    principalId, authorization, connection, connectorRegistration: registration,
    connectorRevision: revision, runtimeBundleCid, commonMoon: moon, ca, admitsApprovalTarget,
    responseHeaders: [], resolveSecret: resolveSecret ?? (async () => {
      const secret = process.env[siteProfile.tokenEnvironment];
      if (!text(secret)) fail('RemoteCredentialSecretUnavailable');
      return secret;
    })});
  try {
    return await createInstalledRowSource({moon, declaration, declared, environmentWire: environment.wire,
      connectorId: installed.connectorId, connectorRegistration: registration,
      connectorRevision: revision, site, authorization, readOperation: HUBSPOT_OBJECT_LIST_OPERATION,
      physicalTarget: target, bindingCid: cid({version: 'actql-installed-hubspot-binding/0.1',
        contextCid: authorization.context.contextCid, runtimeBundleCid, metadataCid: cid(metadata), site: siteProfile}),
      limits: {maxPages: limits.maxRequests, maxPageBytes: limits.maxResponseBytes,
        maxPageRows: limits.perPage, maxCaptureRows: limits.maxRows},
      readPages: async options => {
        const {resource, rowRun: frame} = options;
        const catalog = catalogs.get(resource);
        if (catalog === undefined || !frame?.run || !frame.acquisition) fail('ForeignHubSpotReadPreparation');
        const current = async operation => {
          options.signal?.throwIfAborted();
          const data = await options.verifyRead();
          if (operation === HUBSPOT_OBJECT_LIST_OPERATION) return data;
          const metadataResource = operation === HUBSPOT_ACCOUNT_DETAILS_OPERATION
            ? installed.metadataResources.account : operation === HUBSPOT_PROPERTIES_READ_OPERATION
            ? installed.metadataResources.properties : fail('ForeignHubSpotReadOperation');
          // Metadata access has its own actual Account read decision. The data
          // read's approval and identity observation cannot supply this grant.
          const decision = await authorization.authorize('acquisition',
            {connection, resource: metadataResource, operation: 'read'},
            {subjectCid: cid({binding: target(resource, options.columns), operation}), signal: options.signal});
          await options.verifyRead();
          if (decision?.action !== 'dispatch') fail('HubSpotMetadataReadDenied');
          return decision;
        };
        const grants = new Map();
        const authorize = async ({operation, index}) => {
          const decision = await current(operation);
          if (operation === HUBSPOT_OBJECT_LIST_OPERATION) return await options.authorizationFor(index);
          if (!grants.has(operation)) grants.set(operation, site.issueReadGrant({operation, decision,
            resource: operation === HUBSPOT_ACCOUNT_DETAILS_OPERATION
              ? installed.metadataResources.account : installed.metadataResources.properties,
            runInvocationCid: frame.runInvocationCid, dispatchRequestCid: frame.dispatchRequestCid,
            maxUses: limits.maxRequests}));
          return {...grants.get(operation), useId: `${frame.requestId}-metadata-${index}`};
        };
        const initial = await authorize({operation: HUBSPOT_ACCOUNT_DETAILS_OPERATION, index: 0});
        let binding, processing = true, originalFailure;
        const borrowed = checked(moon.clientProgramRowSourceBorrowResponses(frame.run, frame.acquisition));
        try {
          binding = openHttpsCredentialBinding({...site.credential, scope: initial.scope,
            maxSecretBytes: limits.maxSecretBytes});
          checked(moon.clientProgramRowSourceBindResponseCleanup(borrowed, () =>
            closeHttpsCredentialBinding(binding) === 'closed' && !processing));
          await readHubSpotObjects({moon: provider, originalPortalId: installed.portalId,
            originalCatalog: catalog, objectType: objects.get(resource).objectType,
            properties: options.columns.filter(name => name !== 'id'), initialAuthorization: initial,
            credential: {...site.credential, binding}, authorizationFor: authorize,
            limits, current, chargeResponse: options.chargePage,
            consumeObservation: options.consumeObservation, consumePage: options.consumePage,
            signal: options.signal, callResource: site.callResource});
        } catch (cause) {
          originalFailure = cause;
          throw cause;
        } finally {
          processing = false;
          if (binding !== undefined && closeHttpsCredentialBinding(binding) !== 'closed' && originalFailure === undefined) {
            fail('HubSpotReadCleanupPending');
          }
        }
      }});
  } catch (cause) {
    throw await retainInstalledHostInitializationFailure(cause, {sourceProfile: site});
  }
}
