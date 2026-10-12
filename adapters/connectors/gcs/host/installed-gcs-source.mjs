// Standard Connector installation. Physical GCS observations enter the same
// declaration, RowRun, ReferenceIssuer and lookup owners as other Sources.
// Loading reads only installed documents; it never resolves a token or lists.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {createInstalledRowSource, installRowSourceAuthorization,
  openRowSourceCredentialSite, rowSourceCheckEnvironment} from
  '../../../host-node/installed-row-source.mjs';
import {retainInstalledHostInitializationFailure} from
  '../../../host-node/installed-host-cleanup.mjs';
import {checkInstalledGcsSourceProfile as checkProfile, restoreGcsSourceDeclaration,
  GCS_REGISTRATION, GCS_REVISION} from './gcs-source-declaration.mjs';
import {readGcsFileListing, GCS_FILE_LIST_OPERATION} from '../site/gcs-file-listing.mjs';
import {readGcsKeyedContent} from '../site/gcs-keyed-content.mjs';

export function checkInstalledGcsSourceProfile(profile) {
  return checkProfile(profile);
}
export const INSTALLED_GCS_SITE_VERSION = 'actql-installed-gcs-site/0.1';
const origin = 'https://storage.googleapis.com';
const targetVersion = 'actql-installed-gcs-target/0.1';
const siteKeys = ['version', 'credentialAuthorityId', 'credentialKeyId',
  'credentialPrivateKeyPath', 'environment', 'journalRoot', 'namespaceId',
  'siteGeneration', 'siteKey', 'tokenEnvironment'];
const fail = (code, cause) => { throw Object.assign(new Error(code, {cause}), {code}); };
const text = value => typeof value === 'string' && value.length > 0 &&
  value.isWellFormed() && !/[\u0000-\u001f\u007f]/u.test(value);
const absolute = value => text(value) && isAbsolute(value);
const canonical = value => canonicalJson(value, {dataKeys: true});
const cid = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;
const sameKeys = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');

function checkSite(site) {
  if (!sameKeys(site, siteKeys) || site.version !== INSTALLED_GCS_SITE_VERSION ||
      !['credentialAuthorityId', 'credentialKeyId', 'environment', 'namespaceId',
        'siteKey'].every(key => text(site[key]) && Buffer.byteLength(site[key]) <= 256) ||
      !absolute(site.credentialPrivateKeyPath) || !absolute(site.journalRoot) ||
      !Number.isSafeInteger(site.siteGeneration) || site.siteGeneration < 0 ||
      !/^[A-Z_][A-Z0-9_]{0,63}$/u.test(site.tokenEnvironment)) {
    fail('InvalidInstalledGcsSite');
  }
  return Object.freeze({...site});
}

async function readSite(path) {
  try {
    const body = await readFile(path);
    if (body.byteLength > 1048576) fail('InvalidInstalledGcsSite');
    return checkSite(JSON.parse(body.toString('utf8')));
  } catch (cause) {
    if (cause?.code === 'InvalidInstalledGcsSite') throw cause;
    fail('InvalidInstalledGcsSite', cause);
  }
}

export async function installedGcsSourceIdentityParts(profile, providerProfile, read) {
  const installed = checkInstalledGcsSourceProfile(providerProfile);
  const site = checkSite(await read(installed.siteProfilePath));
  // Installation configuration has its own canonicalization. Exact object
  // scope is data: commit its value CID so NFC never merges different prefixes.
  return [{...profile, accountConfigurationWire: JSON.parse(profile.accountConfigurationWire)},
    {exactScopeCid: cid({project: installed.project, bucket: installed.bucket,
      prefix: installed.prefix})}, site];
}

export async function loadInstalledGcsSource(profile, {root, principalId, moon,
  baseEnvironmentWire, runtimeBundleCid, resolveSecret, installation}) {
  const installed = checkInstalledGcsSourceProfile(profile);
  const siteProfile = await readSite(installed.siteProfilePath);
  const {declaration, declared, scopeCid} = restoreGcsSourceDeclaration(moon, installed);
  const environment = rowSourceCheckEnvironment(baseEnvironmentWire, declared);
  const connection = `gcs:${installed.project}/${installed.bucket}`;
  const authorization = await installRowSourceAuthorization({root, principalId,
    connectorRegistration: GCS_REGISTRATION,
    accountConfiguration: installed.accountConfigurationWire});
  const target = (resource, fields) => Object.freeze({version: targetVersion,
    project: installed.project, bucket: installed.bucket, prefix: installed.prefix,
    scope_cid: scopeCid, catalog_cid: declared.catalog_cid, resource,
    fields: Object.freeze([...fields])});
  const fieldLists = new Map(declared.views.map(view => [view.resource, view.fields]));
  // Approval checks exact installed scope and Resource, not an arbitrary URL.
  const admitsApprovalTarget = (binding, resource) =>
    sameKeys(binding, ['version', 'project', 'bucket', 'prefix', 'scope_cid',
      'catalog_cid', 'resource', 'fields']) &&
    binding.version === targetVersion && binding.project === installed.project &&
    binding.bucket === installed.bucket && binding.prefix === installed.prefix &&
    binding.scope_cid === scopeCid && binding.catalog_cid === declared.catalog_cid &&
    binding.resource === resource && fieldLists.has(resource) &&
    Array.isArray(binding.fields) && new Set(binding.fields).size === binding.fields.length &&
    binding.fields.every(field => fieldLists.get(resource).includes(field));
  const site = await openRowSourceCredentialSite({
    profile: {...siteProfile, resourceOrigin: origin}, principalId, authorization,
    connection, connectorRegistration: GCS_REGISTRATION, connectorRevision: GCS_REVISION,
    runtimeBundleCid, commonMoon: moon, admitsApprovalTarget,
    responseHeaders: installation?.responseHeaders ?? [],
    resolveSecret: resolveSecret ?? (async () => {
      const secret = process.env[siteProfile.tokenEnvironment];
      if (!text(secret)) fail('RemoteCredentialSecretUnavailable');
      return secret;
    })});
  let closed = false;
  const providerIdentityCid = cid({version: 'actql-gcs-provider/0.1',
    project: installed.project, bucket: installed.bucket});
  const resourceBase = Object.freeze({$actql_ref: 'resource', version: 'actql-resource-ref/0.1',
    provider_namespace: GCS_REGISTRATION, resource_kind: 'file',
    provider_identity_cid: providerIdentityCid, authority_scope_cid: scopeCid,
    boundary_cid: declared.catalog_cid});
  const resourceFor = ({bucket, objectName}) => {
    if (closed || bucket !== installed.bucket || !text(objectName) ||
        Buffer.byteLength(objectName) > installed.limits.maxPathBytes ||
        !objectName.startsWith(installed.prefix)) fail('GcsKeyedResourceUnavailable');
    return Object.freeze({...resourceBase, identity_cid: cid({
      version: 'actql-gcs-object-identity/0.1', provider_identity_cid: providerIdentityCid,
      object_name: objectName})});
  };
  const resourceValid = (kind, wire) => {
    if (closed || kind !== 'file' || typeof wire !== 'string' || wire.length > 4096) return false;
    let value;
    try { value = JSON.parse(wire); } catch { return false; }
    return sameKeys(value, [...Object.keys(resourceBase), 'identity_cid']) &&
      Object.entries(resourceBase).every(([key, item]) => value[key] === item) &&
      /^sha256:[0-9a-f]{64}$/u.test(value.identity_cid);
  };
  const {limits} = installed;
  try {
    const adapter = await createInstalledRowSource({moon, declaration, declared,
      environmentWire: environment.wire, connectorId: installed.connectorId,
      connectorRegistration: GCS_REGISTRATION, connectorRevision: GCS_REVISION,
      authorization, site, physicalTarget: target,
      readOperation: {files: GCS_FILE_LIST_OPERATION, contents: 'gcs:file:read'},
      referenceIssuer: moon.clientProgramResourceReferenceIssuer(resourceValid, () => !closed),
      bindingCid: cid({version: 'actql-installed-gcs-binding/0.1', scopeCid,
        contextCid: authorization.context.contextCid, runtimeBundleCid,
        catalogCid: declared.catalog_cid, site: siteProfile}),
      limits: {maxPages: limits.maxPages, maxPageBytes: limits.maxPageBytes,
        maxPageRows: limits.maxPageItems, maxCaptureRows: limits.maxListingItems},
      readPages: async options => {
        if (options.resource === 'files') return readGcsFileListing({
          target: {bucket: installed.bucket, prefix: installed.prefix},
          limits: {maxPageBytes: limits.maxPageBytes, maxPageItems: limits.maxPageItems,
            maxRequestBytes: limits.maxRequestBytes, maxTimeMs: limits.maxDurationMs},
          credential: site.credential, callResource: site.callResource, resourceFor,
          listing: options.listing, authorizationFor: options.authorizationFor,
          chargePage: options.chargePage, signal: options.signal});
        if (options.resource !== 'contents' || typeof options.capturedResourcePath !== 'function' ||
            typeof options.captureContent !== 'function') fail('InstalledContentCaptureUnavailable');
        return readGcsKeyedContent({...options, credential: site.credential,
          callResource: site.callResource,
          limits: {maxMetadataBytes: limits.maxPageBytes, maxContentBytes: limits.maxContentBytes,
            maxRequestBytes: limits.maxRequestBytes, maxTimeMs: limits.maxDurationMs,
            maxAttempts: 2, mediaType: installed.mediaType},
          resolveResource: async resource => {
            const objectName = await options.capturedResourcePath();
            if (canonical(resourceFor({bucket: installed.bucket, objectName})) !== canonical(resource)) {
              fail('GcsKeyedResourceUnavailable');
            }
            return {bucket: installed.bucket, prefix: installed.prefix, objectName};
          }});
      }});
    return Object.freeze({...adapter, requiresRunContentCapture: true,
      close() { closed = true; adapter.close(); }});
  } catch (cause) {
    closed = true;
    throw await retainInstalledHostInitializationFailure(cause, {sourceProfile: site});
  }
}
