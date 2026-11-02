// Standard Connector installation. Physical GCS observations enter the same
// declaration, RowRun, ReferenceIssuer and lookup owners as other Sources.
// Loading reads only installed documents; it never resolves a token or lists.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {createInstalledRowSource,installedRowSourceContext} from
  '../../../host-node/installed-row-source.mjs';
import {gcsEffectTargetRead} from '../site/gcs-credential-site.mjs';
import {retainInstalledSourceAdapter} from '../../../host-node/installed-host-services.mjs';
import {retainInstalledHostInitializationFailure} from
  '../../../host-node/installed-host-cleanup.mjs';
import {readSourceProfileJson,captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
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

async function readSite(path,read=readSourceProfileJson) {
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

export async function installedGcsSourceIdentityParts(profile,providerProfile,read,_entry,{configurationReader}={}) {
  const installed=checkInstalledGcsSourceProfile(providerProfile);
  const readers=captureConfigurationReaders(configurationReader,read,()=>fail('InstalledGcsConfigurationReaderUnavailable'));
  const site=checkSite(await readers.readJson(installed.siteProfilePath,{maxBytes:1048576}));
  // Installation configuration has its own canonicalization. Exact object
  // scope is data: commit its value CID so NFC never merges different prefixes.
  return [{...profile, accountConfigurationWire: JSON.parse(profile.accountConfigurationWire)},
    {exactScopeCid: cid({project: installed.project, bucket: installed.bucket,
      prefix: installed.prefix})}, site];
}

export async function loadInstalledGcsSource(profile,{root,principalId,moon,
  providerMoon,baseEnvironmentWire,runtimeBundleCid,resolveSecret,installation,
  sourceInitialization,configurationReader,installationServices}) {
  if(sourceInitialization===undefined||configurationReader===undefined||installationServices===undefined){
    fail('InstalledGcsInitializationUnavailable');
  }
  const method=(receiver,name,code)=>{
    if(!receiver||nodeTypes.isProxy(receiver))fail(code);
    const field=Object.getOwnPropertyDescriptor(receiver,name);
    if(!field||!Object.hasOwn(field,'value')||typeof field.value!=='function'||
      nodeTypes.isProxy(field.value)||nodeTypes.isAsyncFunction(field.value))fail(code);
    return field.value;
  };
  const prepareInput=method(sourceInitialization,'prepareInputConstruction','InstalledGcsInitializationUnavailable');
  const prepareDeclaration=method(sourceInitialization,'prepareNativeDeclaration','InstalledGcsInitializationUnavailable');
  const openSite=method(installationServices,'openRowSite','InstalledGcsInitializationUnavailable');
  const quote=method(moon,'clientProgramInstalledSourceConstructionCapacity','InstalledGcsInitializationUnavailable');
  const readers=captureConfigurationReaders(configurationReader,undefined,()=>fail('InstalledGcsConfigurationReaderUnavailable'));
  const installed=checkInstalledGcsSourceProfile(profile);
  if(installation?.providerBundle!==undefined&&providerMoon===undefined)fail('GcsCollectionProviderUnavailable');
  const siteProfile=await readSite(installed.siteProfilePath,readers.readJson);
  const contextUnits=BigInt(root.length+principalId.length+GCS_REGISTRATION.length);
  const originalContext=Reflect.apply(prepareInput,sourceInitialization,[Object.freeze({
    capacity(){return checked(Reflect.apply(quote,moon,[4n,8n*contextUnits,8n*contextUnits,4n,8n*contextUnits,8n*contextUnits]));},
    project(){return installedRowSourceContext({root,principalId,connectorRegistration:GCS_REGISTRATION});},
  })]);
  const connection=`gcs:${installed.project}/${installed.bucket}`;
  const targetRef=`connector://${installed.connectorId}/objects`;
  // This closed declaration has at most three views (8/5/12 fields), one
  // fixed upload Command and one four-field Mapping. There is no supplied
  // schema/contract array. The three aggregate envelopes below cover the two
  // relation phases, Command/Catalog projection and collection/Mapping phase,
  // including their original inputs, returned values and failed scratch.
  // Identifier/media/scope strings retain their checked profile bounds; only
  // scope CIDs enter relation facts and collection binding enters the Mapping.
  // One envelope retains the bounded fixed output bundle; two more cover the
  // original parser/identity/writer scratch. The shared native completion keeps
  // that output only AFTER successful synchronous return. Failed constructors
  // keep the full peak. These are logical quantities, not VM/RSS or a new limit.
  // Text enters the shared tariff once, rather than pre-multiplying it by it.
  const nodes=BigInt(declarationLimits.maxNodes);
  const units=BigInt(declarationLimits.maxBytes);
  const prepared=Reflect.apply(prepareDeclaration,sourceInitialization,[Object.freeze({
    capacity(){return checked(Reflect.apply(quote,moon,[nodes,units,units,2n*nodes,2n*units,2n*units]));},
    project(){
      const original=restoreGcsSourceDeclaration(moon,installed,undefined,{includeObjects:providerMoon!==undefined});
      const wire=providerMoon===undefined?original.wire:gcsUploadCatalogDeclaration(providerMoon,original.wire,
        installed.connectorId,declarationLimits);
      const declared=providerMoon===undefined?original.declared:JSON.parse(wire);
      const bindingCid=cid({version:'actql-installed-gcs-binding/0.1',scopeCid:original.scopeCid,
        contextCid:originalContext.contextCid,runtimeBundleCid,catalogCid:declared.catalog_cid,site:siteProfile});
      const collection=providerMoon===undefined?undefined:prepareGcsCollectionTarget(providerMoon,
        {project:installed.project,bucket:installed.bucket,prefix:installed.prefix,targetRef,resourceKind:'file_collection',
          catalogCid:declared.catalog_cid,installationCid:bindingCid,...declarationLimits});
      const mapping=collection===undefined?undefined:gcsCollectionUploadMapping(collection,wire,installed.connectorId,declarationLimits);
      return Object.freeze({declaration:original.declaration,wire,declared,mappings:Object.freeze(mapping===undefined?[]:[mapping]),
        material:Object.freeze({scopeCid:original.scopeCid,bindingCid,collection,declaredWire:providerMoon===undefined?undefined:wire})});
    },
  })]);
  const {declaration,declared,environment,material:{scopeCid,bindingCid,collection,declaredWire}}=prepared;
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
  const {site,authorization}=await Reflect.apply(openSite,installationServices,[{
    installation,sourceInitialization,accountConfiguration:installed.accountConfigurationWire,originalContext,
    profile:Object.freeze({...siteProfile,resourceOrigin:origin}),connection,admitsApprovalTarget,
    admitsEffectTargetRead:gcsEffectTargetRead(admitsApprovalTarget),
    responseHeaders: installation?.responseHeaders ?? [],
    resolveSecret: resolveSecret ?? (async () => {
      const secret = process.env[siteProfile.tokenEnvironment];
      if (!text(secret)) fail('RemoteCredentialSecretUnavailable');
      return secret;
    }),
  }]);
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
  let adapter;
  try {
    if(authorization.context!==originalContext)fail('ForeignInstalledGcsContext');
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
    adapter = await createInstalledRowSource({moon, declaration, declared,environment,sourceInitialization,
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
    return retainInstalledSourceAdapter(sourceInitialization,adapter,Object.freeze({...adapter, requiresRunContentCapture: true,
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
      close() {closed=true;return adapter.close();}}));
  } catch (cause) {
    closed = true;
    throw await retainInstalledHostInitializationFailure(cause,{sourceProfile:adapter??site});
  }
}
