// Standard Connector installation. Physical GCS observations enter the same
// declaration, RowRun, ReferenceIssuer and lookup owners as other Sources.
// Loading reads only installed documents; it never resolves a token or lists.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {createInstalledRowSource, installRowSourceAuthorization,
  rowSourceCheckEnvironment} from
  '../../../host-node/installed-row-source.mjs';
import {openGcsCredentialSite} from '../site/gcs-credential-site.mjs';
import {retainInstalledHostInitializationFailure} from
  '../../../host-node/installed-host-cleanup.mjs';
import {readSourceProfileJson} from '../../../host-node/source-profile-json.mjs';
import {checkInstalledGcsSourceProfile as checkProfile, restoreGcsSourceDeclaration,
  GCS_REGISTRATION, GCS_REVISION} from './gcs-source-declaration.mjs';
import {readGcsFileListing, GCS_FILE_LIST_OPERATION} from '../site/gcs-file-listing.mjs';
import {readGcsObjects} from '../site/gcs-object-listing.mjs';
import {readGcsKeyedContent} from '../site/gcs-keyed-content.mjs';
import {gcsUploadCatalogDeclaration} from './gcs-upload-declaration.mjs';
import {prepareGcsCollectionTarget, gcsCollectionUploadMapping,
  issueGcsCollectionReference} from './gcs-collection-target.mjs';

export function checkInstalledGcsSourceProfile(profile) {
  return checkProfile(profile);
}
export const INSTALLED_GCS_SITE_VERSION = 'actql-installed-gcs-site/0.1';
const origin = 'https://storage.googleapis.com';
const targetVersion = 'actql-installed-gcs-target/0.1';
// The existing RowDeclaration Host's static representation clamps. These are
// not retained/workspace reservations or a numerical Model profile.
const declarationLimits = Object.freeze({maxBytes: 4000000, maxNodes: 400000, maxDepth: 64});
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
    return checkSite(await readSourceProfileJson(path, {maxBytes: 1048576}));
  } catch (cause) {
    if (cause?.cleanupHandle !== undefined || cause?.cleanupPending === true) {
      throw Object.assign(new Error('InvalidInstalledGcsSite', {cause}),
        {code: 'InvalidInstalledGcsSite', cleanupHandle: cause.cleanupHandle,
          cleanupPending: cause.cleanupPending});
    }
    if (cause?.code === 'InvalidInstalledGcsSite') throw cause;
    fail('InvalidInstalledGcsSite', cause);
  }
}

export async function installedGcsSourceIdentityParts(profile, providerProfile, read) {
  const installed = checkInstalledGcsSourceProfile(providerProfile);
  const site = checkSite(await read(installed.siteProfilePath, {maxBytes: 1048576}));
  // Installation configuration has its own canonicalization. Exact object
  // scope is data: commit its value CID so NFC never merges different prefixes.
  return [{...profile, accountConfigurationWire: JSON.parse(profile.accountConfigurationWire)},
    {exactScopeCid: cid({project: installed.project, bucket: installed.bucket,
      prefix: installed.prefix})}, site];
}

export async function loadInstalledGcsSource(profile, {root, principalId, moon,
  providerMoon, baseEnvironmentWire, runtimeBundleCid, resolveSecret, installation}) {
  const installed = checkInstalledGcsSourceProfile(profile);
  if (installation?.providerBundle !== undefined && providerMoon === undefined) {
    fail('GcsCollectionProviderUnavailable');
  }
  const siteProfile = await readSite(installed.siteProfilePath);
  const original = restoreGcsSourceDeclaration(moon, installed, undefined,
    {includeObjects: providerMoon !== undefined});
  const {declaration, scopeCid} = original;
  // A legacy explicitly supplied source-only installation has no collection
  // supplier. The ordinary declared provider selects the complete Command
  // extension; neither branch invents a Source/Values field for its target.
  const declaredWire = providerMoon === undefined ? undefined
    : gcsUploadCatalogDeclaration(providerMoon, JSON.stringify(original.declared),
      installed.connectorId, declarationLimits);
  const declared = declaredWire === undefined ? original.declared : JSON.parse(declaredWire);
  const connection = `gcs:${installed.project}/${installed.bucket}`;
  const authorization = await installRowSourceAuthorization({root, principalId,
    connectorRegistration: GCS_REGISTRATION,
    accountConfiguration: installed.accountConfigurationWire});
  const bindingCid = cid({version: 'actql-installed-gcs-binding/0.1', scopeCid,
    contextCid: authorization.context.contextCid, runtimeBundleCid,
    catalogCid: declared.catalog_cid, site: siteProfile});
  const targetRef = `connector://${installed.connectorId}/objects`;
  const collection = declaredWire === undefined ? undefined
    : prepareGcsCollectionTarget(providerMoon, {project: installed.project,
      bucket: installed.bucket, prefix: installed.prefix, targetRef,
      resourceKind: 'file_collection', catalogCid: declared.catalog_cid,
      installationCid: bindingCid, ...declarationLimits});
  const mapping = collection === undefined ? undefined : gcsCollectionUploadMapping(
    collection, declaredWire, installed.connectorId, declarationLimits);
  const environment = rowSourceCheckEnvironment(baseEnvironmentWire, declared,
    mapping === undefined ? [] : [mapping]);
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
  const site = await openGcsCredentialSite({
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
    if (closed || bucket !== installed.bucket || typeof objectName !== 'string' ||
        !objectName.isWellFormed() || objectName.length === 0 || /[\r\n]/u.test(objectName) ||
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
    const referenceIssuer = moon.clientProgramResourceReferenceIssuer(resourceValid, () => !closed);
    // The escaped reference keeps this actual Site (and its original journal,
    // context, credential generation and selected runtime) until its last
    // borrower retires. A failed close invalidates currentness but not custody.
    // Constructors can also fail: the acquired Site remains under this same
    // initialization catch until the completed adapter is returned.
    const collectionIssuer = collection === undefined ? undefined
      : moon.clientProgramResourceReferenceIssuer(
        (kind, wire) => kind === 'file_collection' && wire === collection.resourceWire,
        wire => !closed && site.referenceCurrent() && wire === collection.resourceWire);
    const adapter = await createInstalledRowSource({moon, declaration, declared,
      environmentWire: environment.wire, connectorId: installed.connectorId,
      connectorRegistration: GCS_REGISTRATION, connectorRevision: GCS_REVISION,
      authorization, site, physicalTarget: target,
      readOperation: {files: GCS_FILE_LIST_OPERATION, contents: 'gcs:file:read',
        ...(providerMoon === undefined ? {} : {objects: GCS_FILE_LIST_OPERATION})},
      referenceIssuer, bindingCid,
      limits: {maxPages: limits.maxPages, maxPageBytes: limits.maxPageBytes,
        maxPageRows: limits.maxPageItems, maxCaptureRows: limits.maxListingItems},
      readPages: async options => {
        if (options.resource === 'objects') return readGcsObjects({...options,
          moon: providerMoon, target: {bucket: installed.bucket, prefix: installed.prefix},
          limits: {maxPageBytes: limits.maxPageBytes, maxPageItems: limits.maxPageItems,
            maxRequestBytes: limits.maxRequestBytes, maxTimeMs: limits.maxDurationMs,
            maxPages: limits.maxPages, maxRows: limits.maxListingItems},
          credential: site.credential, callResource: site.callResource, resourceFor});
        if (options.resource === 'files') return readGcsFileListing({moon: providerMoon,
          target: {bucket: installed.bucket, prefix: installed.prefix},
          limits: {maxPageBytes: limits.maxPageBytes, maxPageItems: limits.maxPageItems,
            maxRequestBytes: limits.maxRequestBytes, maxTimeMs: limits.maxDurationMs},
          credential: site.credential, callResource: site.callResource, resourceFor,
          listing: options.listing, authorizationFor: options.authorizationFor,
          chargePage: options.chargePage, signal: options.signal});
        if (options.resource !== 'contents' || typeof options.capturedResourcePath !== 'function' ||
            typeof options.captureContent !== 'function') fail('InstalledContentCaptureUnavailable');
        return readGcsKeyedContent({...options, moon: providerMoon, credential: site.credential,
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
      ...(collection === undefined ? {} : {
        publishedStoreTargets: Object.freeze([Object.freeze({targetRef,
          mappingRef: `mapping:${installed.connectorId}.gcs.objects.upload.v1`,
          commandRef: `command:${installed.connectorId}.gcs.upload.v1`})]),
        // This synchronous hook borrows the actual Site/installation issuer.
        // Its original checked value remains available only in this lifetime.
        // Account approval and the final physical send gate remain separate.
        issueOriginalCollectionReference(pair, maxWork) {
          if (closed) fail('GcsCollectionReferenceUnavailable');
          return issueGcsCollectionReference(collection, pair, declaredWire,
            installed.connectorId, collectionIssuer, {...declarationLimits, maxWork});
        },
      }),
      close() { closed = true; adapter.close(); }});
  } catch (cause) {
    closed = true;
    throw await retainInstalledHostInitializationFailure(cause, {sourceProfile: site});
  }
}
