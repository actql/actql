// A HubSpot installation supplies original metadata and physical reads only.
// The standard Host owns the declaration, Account gate, RowRun and capture.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {readFile} from 'node:fs/promises';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {readSourceProfileJson,captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {createInstalledRowSource} from '../../../host-node/installed-row-source.mjs';
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

async function readInputs(profile,{readJson=readSourceProfileJson,construct}={}) {
  const installed=checkInstalledHubSpotSourceProfile(profile);
  const site=checkSite(await readJson(installed.siteProfilePath));
  const metadata=await readJson(installed.metadataPath);
  if(!closed(metadata,['version','connectorId','portalId','apiOrigin','accountBody','objects'])||
    metadata.version!=='actql-hubspot-read-metadata/0.1'||metadata.connectorId!==installed.connectorId||
    metadata.portalId!==installed.portalId||metadata.apiOrigin!==site.apiOrigin||!Array.isArray(metadata.objects)||
    metadata.objects.length!==installed.resources.length)fail('InvalidInstalledHubSpotMetadata');
  const encoded=body=>typeof body==='string'&&body.length<=Math.ceil(installed.limits.maxResponseBytes/3)*4;
  if(!encoded(metadata.accountBody))fail('InvalidInstalledHubSpotMetadata');
  for(let index=0;index<metadata.objects.length;index++){
    const object=metadata.objects[index];
    if(!closed(object,['resource','objectType','propertiesBody'])||!encoded(object.propertiesBody)||
      metadata.objects.some((other,i)=>i<index&&other.resource===object.resource)||
      !installed.resources.some(value=>value.resource===object.resource&&value.objectType===object.objectType)){
      fail('InvalidInstalledHubSpotMetadata');
    }
  }
  // Identity hashes original DATA only. Actual initialization reserves all
  // binary inputs and the returned Map together before constructing any of them.
  const binary=construct?.(metadata,installed.limits.maxResponseBytes);
  return {installed,site,metadata,...binary};
}

export async function installedHubSpotSourceIdentityParts(profile,providerProfile,read,_entry,{configurationReader}={}) {
  const readers=captureConfigurationReaders(configurationReader,read,()=>fail('InstalledHubSpotConfigurationReaderUnavailable'));
  const {site,metadata}=await readInputs(providerProfile,readers);
  if(configurationReader!==undefined&&site.caPath!==undefined&&readers.readOriginalBytes===undefined){
    fail('InstalledHubSpotConfigurationReaderUnavailable');
  }
  // Keep the standalone DATA-only identity utility separate from installation.
  const ca=site.caPath===undefined?undefined:readers.readOriginalBytes===undefined
    ?await readFile(site.caPath):await readers.readOriginalBytes(site.caPath);
  return [{...profile, accountConfigurationWire: JSON.parse(profile.accountConfigurationWire)}, site,
    {metadataCid: cid(metadata), ...(ca === undefined ? {} : {caSha256: createHash('sha256').update(ca).digest('hex')})}];
}

export async function loadInstalledHubSpotSource(profile,{root,principalId,moon,
  providerMoon:provider,baseEnvironmentWire,runtimeBundleCid,resolveSecret,installation,
  sourceInitialization,configurationReader,installationServices}) {
  if(sourceInitialization===undefined||configurationReader===undefined||installationServices===undefined){
    fail('InstalledHubSpotInitializationUnavailable');
  }
  const method=(receiver,name,code)=>{
    if(!receiver||nodeTypes.isProxy(receiver))fail(code);
    const field=Object.getOwnPropertyDescriptor(receiver,name);
    if(!field||!Object.hasOwn(field,'value')||typeof field.value!=='function'||
      nodeTypes.isProxy(field.value)||nodeTypes.isAsyncFunction(field.value))fail(code);
    return field.value;
  };
  const input=method(sourceInitialization,'prepareInputConstruction','InstalledHubSpotInitializationUnavailable');
  const declare=method(sourceInitialization,'prepareNativeDeclaration','InstalledHubSpotInitializationUnavailable');
  const openSite=method(installationServices,'openRowSite','InstalledHubSpotInitializationUnavailable');
  const quote=method(moon,'clientProgramInstalledSourceConstructionCapacity','InstalledHubSpotInitializationUnavailable');
  const restore=method(moon,'clientProgramRowSourceRestoreRelationDeclaration','InstalledHubSpotInitializationUnavailable');
  const names=['hubspotRecheckAccountIdentityJson','hubspotProjectProperties','hubspotPropertyCatalogNames',
    'hubspotObjectSchemaWire','hubspotObjectRelationFactsWire'];
  const originals=Object.freeze(Object.fromEntries(names.map(name=>{
    const fn=method(provider,name,'InstalledHubSpotProviderUnavailable');
    return [name,(...args)=>Reflect.apply(fn,provider,args)];
  })));
  const readers=captureConfigurationReaders(configurationReader,undefined,
    ()=>fail('InstalledHubSpotConfigurationReaderUnavailable'));
  let bodyBytes=0n;
  const {installed,site:siteProfile,metadata,account,objects}=await readInputs(profile,{...readers,
    construct(metadata,maximum){
      let text=BigInt(metadata.accountBody.length);
      let wire=BigInt(Math.floor(metadata.accountBody.length*3/4));
      for(const value of metadata.objects){text+=BigInt(value.propertiesBody.length);wire+=BigInt(Math.floor(value.propertiesBody.length*3/4));}
      bodyBytes=wire;
      return Reflect.apply(input,sourceInitialization,[Object.freeze({
        capacity(){return checked(Reflect.apply(quote,moon,[4n*BigInt(metadata.objects.length+1),2n*text,wire,0n,0n,0n]));},
        project(){
          const decode=encoded=>{
            const bytes=Buffer.from(encoded,'base64');
            if(bytes.byteLength>maximum||bytes.toString('base64')!==encoded)fail('InvalidInstalledHubSpotMetadata');
            return bytes;
          };
          const account=decode(metadata.accountBody),objects=new Map();
          for(const value of metadata.objects)objects.set(value.resource,{objectType:value.objectType,body:decode(value.propertiesBody)});
          return Object.freeze({account,objects});
        },
      })]);
    },
  });
  const {limits}=installed,count=BigInt(installed.resources.length);
  // Keep node counts independent of byte/text writer bounds. All catalogs,
  // selected schema Strings, declaration outputs and failed prefixes coexist
  // with the original binary inputs on the SAME conservative Source parent.
  const nodes=BigInt(limits.maxNodes)+count*(BigInt(limits.maxNodes)+BigInt(limits.maxValueNodes)+
    BigInt(limits.maxDeclarationNodes)+BigInt(limits.maxProperties)+BigInt(limits.maxColumns));
  const textUnits=bodyBytes+count*(BigInt(limits.maxNameUnits)+BigInt(limits.maxValueTextBytes)+BigInt(limits.maxDeclarationBytes));
  const wireBytes=bodyBytes+count*BigInt(limits.maxDeclarationBytes);
  const prepared=Reflect.apply(declare,sourceInitialization,[Object.freeze({
    capacity(){return checked(Reflect.apply(quote,moon,[4n*nodes,8n*textUnits,8n*wireBytes,4n*nodes,8n*textUnits,8n*wireBytes]));},
    project(){
      const identity=JSON.parse(originals.hubspotRecheckAccountIdentityJson(account,installed.portalId,
        limits.maxResponseBytes,limits.maxNodes,limits.maxDepth));
      if(identity.refused!==undefined||identity.account?.portalId!==installed.portalId)fail('InvalidInstalledHubSpotAccount');
      const catalogs=new Map(),views=[];
      for(const {resource,objectType}of installed.resources){
        const catalog=checked(originals.hubspotProjectProperties(objects.get(resource).body,objectType,
          limits.maxResponseBytes,limits.maxNodes,limits.maxDepth,limits.maxProperties,limits.maxNameUnits));
        const names=originals.hubspotPropertyCatalogNames(catalog);
        const wire=checked(originals.hubspotObjectSchemaWire(catalog,names,limits.maxColumns,limits.maxNameUnits,
          limits.maxDeclarationBytes,limits.maxDeclarationNodes,limits.maxDepth));
        catalogs.set(resource,catalog);
        views.push({resource,resource_kind:'object',schema_wire:wire,facts_wire:originals.hubspotObjectRelationFactsWire(),
          schema_cid:`sha256:${createHash('sha256').update(wire).digest('hex')}`});
      }
      const declaration=checked(Reflect.apply(restore,moon,[installed.connectorId,registration,revision,JSON.stringify({views}),undefined]));
      return Object.freeze({declaration,material:Object.freeze({catalogs,identity,metadataCid:cid(metadata)})});
    },
  })]);
  const {declaration,declared,environment,material:{catalogs,metadataCid}}=prepared;
  const connection = `hubspot:${installed.connectorId}`;
  const target = (resource, fields) => Object.freeze({version: 'actql-installed-hubspot-target/0.1',
    apiOrigin: siteProfile.apiOrigin, portalId: installed.portalId, resource,
    objectType: objects.get(resource)?.objectType, metadataCid, fields: Object.freeze([...fields])});
  const admitsApprovalTarget = (binding, resource) => {
    const view = declared.views.find(value => value.resource === resource);
    return view !== undefined && Array.isArray(binding?.fields) &&
      new Set(binding.fields).size === binding.fields.length && binding.fields.every(field => view.fields.includes(field)) &&
      canonical(binding) === canonical(target(resource, binding.fields));
  };
  if(siteProfile.caPath!==undefined&&readers.readOriginalBytes===undefined)fail('InstalledHubSpotConfigurationReaderUnavailable');
  const ca=siteProfile.caPath===undefined?undefined:await readers.readOriginalBytes(siteProfile.caPath);
  const {site,authorization}=await Reflect.apply(openSite,installationServices,[{
    installation,sourceInitialization,accountConfiguration:installed.accountConfigurationWire,
    profile:Object.freeze({...siteProfile,resourceOrigin:siteProfile.apiOrigin}),connection,ca,admitsApprovalTarget,
    responseHeaders:[],resolveSecret:resolveSecret??(async()=>{
      const secret = process.env[siteProfile.tokenEnvironment];
      if (!text(secret)) fail('RemoteCredentialSecretUnavailable');
      return secret;
    }),
  }]);
  try {
    return await createInstalledRowSource({moon, declaration, declared,environment,sourceInitialization, environmentWire: environment.wire,
      connectorId: installed.connectorId, connectorRegistration: registration,
      connectorRevision: revision, site, authorization, readOperation: HUBSPOT_OBJECT_LIST_OPERATION,
      physicalTarget: target, bindingCid: cid({version: 'actql-installed-hubspot-binding/0.1',
        contextCid: authorization.context.contextCid, runtimeBundleCid, metadataCid, site: siteProfile}),
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
