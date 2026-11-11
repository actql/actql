// Standard Connector installation. Physical GCS observations enter the same
// declaration, RowRun, ReferenceIssuer and lookup owners as other Sources.
// Loading reads only installed documents; it never resolves a token or lists.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {readSourceProfileJson} from '../../../host-node/source-profile-json.mjs';
import {checkInstalledGcsSourceProfile as checkProfile, prepareGcsSourceDeclarationInputs,
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

async function readSite(path, read = readSourceProfileJson) {
  try {
    return checkSite(await read(path, {maxBytes: 1048576}));
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
  providerMoon, baseEnvironmentWire, runtimeBundleCid, resolveSecret, installation, construction}) {
  if (typeof construction?.prepareDerivedDeclaredCommands !== 'function' ||
      typeof construction.prepareReadTargetWithMappings !== 'function' ||
      typeof construction.openRowSite !== 'function' || typeof construction.createRowSource !== 'function' ||
      typeof construction.configurationReader?.readJson !== 'function') fail('GcsSourceConstructionUnavailable');
  const installed = checkInstalledGcsSourceProfile(profile);
  if (installation?.providerBundle !== undefined && providerMoon === undefined) {
    fail('GcsCollectionProviderUnavailable');
  }
  const siteProfile = await readSite(installed.siteProfilePath, construction.configurationReader.readJson);
  const inputs = prepareGcsSourceDeclarationInputs(installed, {includeObjects: providerMoon !== undefined});
  const {scopeCid} = inputs;
  let declaredWire;
  const {declared} = construction.prepareDerivedDeclaredCommands(inputs.initialViews,
    Object.freeze({
      capacity(preliminary) {
        return moon.clientProgramGcsSourceFactsConstructionCapacity(inputs.initialViews.length,
          inputs.scopeCid, inputs.versionCid,
          preliminary.views.find(view => view.resource === 'files').carrier_schema_cid,
          preliminary.views.find(view => view.resource === 'contents').carrier_schema_cid,
          ['maxListingItems', 'maxExaminedItems', 'maxPages', 'maxAttempts',
            'maxListingBytes', 'maxDurationMs', 'maxPathBytes', 'maxPageBytes']
            .map(name => BigInt(installed.limits[name])));
      },
      project: inputs.deriveFinalViews,
    }), providerMoon === undefined ? undefined : Object.freeze({
      capacity(wire) {
        return moon.clientProgramGcsUploadCatalogConstructionCapacity(wire,
          installed.connectorId.length, declarationLimits.maxBytes,
          declarationLimits.maxNodes, declarationLimits.maxDepth);
      },
      project(wire) {
        declaredWire = gcsUploadCatalogDeclaration(providerMoon, wire,
          installed.connectorId, declarationLimits);
        const declared = JSON.parse(declaredWire);
        return Object.freeze({declared, commands: declared.command_bodies, wire: declaredWire});
      },
    }));
  const connection = `gcs:${installed.project}/${installed.bucket}`;
  const targetRef = `connector://${installed.connectorId}/objects`;
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
  const {site, authorization} = await construction.openRowSite({
    profile: {...siteProfile, resourceOrigin: origin}, connection,
    accountConfiguration: installed.accountConfigurationWire, admitsApprovalTarget,
    // Keep the selected GCS Site's exact separate Effect target-read rule.
    admitsEffectTargetRead: (binding, resource, operation) =>
      resource === 'objects' && operation === 'gcs:file:read' &&
      admitsApprovalTarget(binding, resource) === true,
    responseHeaders: installation?.responseHeaders ?? [],
    resolveSecret: resolveSecret ?? (async () => {
      const secret = process.env[siteProfile.tokenEnvironment];
      if (!text(secret)) fail('RemoteCredentialSecretUnavailable');
      return secret;
    })});
  const bindingCid = cid({version: 'actql-installed-gcs-binding/0.1', scopeCid,
    contextCid: authorization.context.contextCid, runtimeBundleCid,
    catalogCid: declared.catalog_cid, site: siteProfile});
  const collection = declaredWire === undefined ? undefined :
    construction.prepareReadTargetWithMappings(Object.freeze({
      capacity() {
        return moon.clientProgramGcsCollectionMappingConstructionCapacity(declaredWire,
          installed.project.length, installed.bucket.length, installed.prefix.length,
          targetRef.length, installed.connectorId.length, declarationLimits.maxBytes,
          declarationLimits.maxNodes, declarationLimits.maxDepth);
      },
      project() {
        const target = prepareGcsCollectionTarget(providerMoon, {project: installed.project,
          bucket: installed.bucket, prefix: installed.prefix, targetRef,
          resourceKind: 'file_collection', catalogCid: declared.catalog_cid,
          installationCid: bindingCid, ...declarationLimits});
        const mapping = gcsCollectionUploadMapping(target, declaredWire, installed.connectorId, declarationLimits);
        return Object.freeze({target, mappingWires: Object.freeze([mapping])});
      },
    })).target;
  // This SAME acquired Site invalidates referenceCurrent synchronously when
  // Common begins close, before any asynchronous physical cleanup can finish.
  const current = () => site.referenceCurrent();
  const providerIdentityCid = cid({version: 'actql-gcs-provider/0.1',
    project: installed.project, bucket: installed.bucket});
  const resourceBase = Object.freeze({$actql_ref: 'resource', version: 'actql-resource-ref/0.1',
    provider_namespace: GCS_REGISTRATION, resource_kind: 'file',
    provider_identity_cid: providerIdentityCid, authority_scope_cid: scopeCid,
    boundary_cid: declared.catalog_cid});
  const resourceFor = ({bucket, objectName}) => {
    if (!current() || bucket !== installed.bucket || typeof objectName !== 'string' ||
        !objectName.isWellFormed() || objectName.length === 0 || /[\r\n]/u.test(objectName) ||
        Buffer.byteLength(objectName) > installed.limits.maxPathBytes ||
        !objectName.startsWith(installed.prefix)) fail('GcsKeyedResourceUnavailable');
    return Object.freeze({...resourceBase, identity_cid: cid({
      version: 'actql-gcs-object-identity/0.1', provider_identity_cid: providerIdentityCid,
      object_name: objectName})});
  };
  const resourceValid = (kind, wire) => {
    if (!current() || kind !== 'file' || typeof wire !== 'string' || wire.length > 4096) return false;
    let value;
    try { value = JSON.parse(wire); } catch { return false; }
    return sameKeys(value, [...Object.keys(resourceBase), 'identity_cid']) &&
      Object.entries(resourceBase).every(([key, item]) => value[key] === item) &&
      /^sha256:[0-9a-f]{64}$/u.test(value.identity_cid);
  };
  const {limits} = installed;
  {
    const referenceIssuer = moon.clientProgramResourceReferenceIssuer(resourceValid, current);
    // The escaped reference keeps this actual Site (and its original journal,
    // context, credential generation and selected runtime) until its last
    // borrower retires. A failed close invalidates currentness but not custody.
    // Common bound construction retains the acquired Site and original
    // failure until its actual cleanup completes.
    const collectionIssuer = collection === undefined ? undefined
      : moon.clientProgramResourceReferenceIssuer(
        (kind, wire) => kind === 'file_collection' && wire === collection.resourceWire,
        wire => current() && wire === collection.resourceWire);
    return await construction.createRowSource({physicalTarget: target,
      publication: Object.freeze({requiresRunContentCapture: true,
        ...(collection === undefined ? {} : {
          publishedStoreTargets: Object.freeze([Object.freeze({targetRef,
            mappingRef: `mapping:${installed.connectorId}.gcs.objects.upload.v1`,
            commandRef: `command:${installed.connectorId}.gcs.upload.v1`})]),
          issueOriginalCollectionReference(pair, maxWork) {
            if (!current()) fail('GcsCollectionReferenceUnavailable');
            return issueGcsCollectionReference(collection, pair, declaredWire,
              installed.connectorId, collectionIssuer, {...declarationLimits, maxWork});
          },
        }),
      }),
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
  }
}
