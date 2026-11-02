// Installation metadata and physical adaptation only. Common retains the
// checked declaration, acquisition, planner, Ledger, RowRun and capture.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {createInstalledRowSource} from '../../../host-node/installed-row-source.mjs';
import {types as nodeTypes} from 'node:util';
import {installedJsonSourceReaderLimitNames} from '../../../host-node/installed-credential-source-reader.mjs';
import {captureInstalledSourceServices} from '../../../host-node/installed-host-services.mjs';
import {prepareGmailLabelListPages,GMAIL_LABEL_LIST_OPERATION} from '../site/gmail-label-list-read.mjs';
import {checkGmailThreadReaderLimits,gmailThreadReaderLimitNames} from '../site/gmail-thread-limits.mjs';
import {prepareGmailThreadReadSequence,GMAIL_THREAD_LIST_OPERATION} from '../site/gmail-thread-read.mjs';

export const INSTALLED_GMAIL_SOURCE_VERSION='actql-installed-gmail-source/0.1';
export const INSTALLED_GMAIL_SITE_VERSION='actql-installed-gmail-site/0.1';
const registration='gmail',revision='gmail/0.1';
const profileKeys=['version','connectorId','mailbox','siteProfilePath','accountConfigurationWire','limits'];
const siteKeys=['version','apiOrigin','credentialAuthorityId','credentialKeyId','credentialPrivateKeyPath',
  'environment','journalRoot','namespaceId','siteGeneration','siteKey'];
const readLimitKeys=['maxResponseBytes','maxNodes','maxDepth','maxRows','maxMailboxBytes','maxTargetBytes',
  'maxValueNodes','maxValueTextBytes','maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'];
const extraLimitKeys=['maxDeclarationBytes','maxDeclarationNodes','maxSecretBytes','maxCaBytes'];
const limitKeys=[...readLimitKeys,...extraLimitKeys];
const threadLimitKeys=[...gmailThreadReaderLimitNames,...extraLimitKeys];
const fail=code=>{throw Object.assign(new Error(code),{code});};
const text=value=>typeof value==='string'&&value.length>0&&value.isWellFormed()&&!/[\u0000-\u001f\u007f]/u.test(value);
const absolute=value=>text(value)&&isAbsolute(value);
const positive=value=>Number.isSafeInteger(value)&&value>0&&value<=2147483647;
const closed=(value,keys)=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&
  Object.keys(value).sort().join('\0')===[...keys].sort().join('\0');
const sha=bytes=>`sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const cid=value=>sha(canonicalJson(value));

export function checkInstalledGmailSourceProfile(profile){
  const resource=profile?.resource??'labels';
  const keys=profile!==null&&typeof profile==='object'&&Object.hasOwn(profile,'resource')
    ?[...profileKeys,'resource']:profileKeys;
  let validLimits=false;
  if(resource==='threads'&&closed(profile?.limits,threadLimitKeys)){
    try{checkGmailThreadReaderLimits(profile.limits);
      validLimits=extraLimitKeys.every(key=>positive(profile.limits[key]))&&positive(profile.limits.maxThreads);
    }catch{/* Preserve the installed profile's closed refusal. */}
  }else if(resource==='labels')validLimits=closed(profile?.limits,limitKeys)&&limitKeys.every(key=>positive(profile.limits[key]));
  if(!closed(profile,keys)||(Object.hasOwn(profile,'resource')&&profile.resource!==resource)||
      !['labels','threads'].includes(resource)||profile.version!==INSTALLED_GMAIL_SOURCE_VERSION||
      !text(profile.connectorId)||!text(profile.mailbox)||!profile.mailbox.includes('@')||/\s/u.test(profile.mailbox)||
      !absolute(profile.siteProfilePath)||typeof profile.accountConfigurationWire!=='string'||
      !validLimits||
      Buffer.byteLength(profile.mailbox)>profile.limits.maxMailboxBytes)fail('InvalidInstalledGmailSourceProfile');
  return Object.freeze({...profile,limits:Object.freeze({...profile.limits})});
}

function checkSite(site){
  const {caPath,...rest}=site??{};let origin;
  try{origin=new URL(rest.apiOrigin);}catch{/* Closed rejection below. */}
  if(!closed(rest,siteKeys)||rest.version!==INSTALLED_GMAIL_SITE_VERSION||
      origin?.protocol!=='https:'||origin.origin!==rest.apiOrigin||
      !['credentialAuthorityId','credentialKeyId','environment','namespaceId','siteKey'].every(key=>text(rest[key]))||
      !absolute(rest.credentialPrivateKeyPath)||!absolute(rest.journalRoot)||
      !Number.isSafeInteger(rest.siteGeneration)||rest.siteGeneration<0||
      (caPath!==undefined&&!absolute(caPath)))fail('InvalidInstalledGmailSite');
  return Object.freeze({...rest,...(caPath===undefined?{}:{caPath})});
}

async function readInputs(profile,configurationReader,readJson){
  const installed=checkInstalledGmailSourceProfile(profile);
  const reads=captureConfigurationReaders(configurationReader,readJson,
    ()=>fail('InstalledGmailConfigurationReaderUnavailable'));
  const site=checkSite(await reads.readJson(installed.siteProfilePath));
  let ca;
  if(site.caPath!==undefined){
    // This private Site accepts bounded PEM text, not an unbounded file read
    // or lenient UTF-8 identity. Non-ASCII/replacement input is refused rather
    // than re-encoding different authority bytes before hashing/native TLS.
    const pem=await reads.readText(site.caPath,{maxBytes:installed.limits.maxCaBytes});
    if(/[^\x09\x0a\x0d\x20-\x7e]/u.test(pem)||!pem.includes('-----BEGIN CERTIFICATE-----')||
        !pem.includes('-----END CERTIFICATE-----'))fail('InvalidInstalledGmailTlsAuthority');
    ca=Buffer.from(pem,'ascii');
  }
  // Configuration canonicalization must not collapse distinct original
  // mailbox bytes or drop the selected TLS authority from this generation.
  const binding={mailboxBytesCid:sha(Buffer.from(installed.mailbox)),
    ...(ca===undefined?{}:{caSha256:sha(ca)})};
  return{installed,site,ca,binding};
}

export async function installedGmailSourceIdentityParts(profile,providerProfile,read,_installation,context){
  const{site,binding}=await readInputs(providerProfile,context?.configurationReader,read);
  return[{...profile,accountConfigurationWire:JSON.parse(profile.accountConfigurationWire)},site,binding];
}

// Same original list/get profile and complete Core recipe. The shared Host
// retains this result unchanged; it does not select or recompose Gmail work.
function gmailThreadReaderSelection(original, columns, profile) {
  if (columns !== 5) fail('InvalidInstalledGmailThreadReaderLimits');
  if (original.pageSize > 500 || original.maxPages > 2147483647 - original.maxThreads ||
      original.maxMailboxBytes > profile.maxIdentityBytes ||
      original.maxDeclarationBytes > profile.maxDeclarationBytes ||
      original.maxDeclarationNodes > profile.maxDeclarationNodes) fail('InstalledSourceReaderImplementationBoundsExceeded');
  const responses = original.maxPages + original.maxThreads;
  return Object.freeze({original,responses,limits:Object.freeze({
    maxResponseBytes:original.maxResponseBytes,maxTotalResponseBytes:original.maxTotalResponseBytes,
    maxNodes:original.maxNodes,maxDepth:original.maxDepth,maxRows:1,maxTotalRows:original.maxThreads,
    maxPages:responses,pageSize:original.pageSize,maxCursorBytes:original.maxTokenBytes,maxIdentityBytes:original.maxIdBytes,
    maxTargetBytes:original.maxTargetBytes,maxValueNodes:original.maxValueNodes,
    // The quote's positive slot does not replace Gmail's valid zero-text guard.
    maxValueTextBytes:original.maxValueTextBytes === 0 ? 1 : original.maxValueTextBytes,
    maxRowsWireBytes:original.maxRowsWireBytes,maxRowsWireNodes:original.maxRowsWireNodes,
    maxRowsWireDepth:original.maxRowsWireDepth,maxSecretBytes:original.maxSecretBytes,
  }),sequence:Object.freeze({operation:'gmail:threads:list',maxUses:original.maxPages,
    children:Object.freeze([Object.freeze({operation:'gmail:threads:get',maxUses:original.maxThreads})])})});
}

export async function loadInstalledGmailSource(profile,{root,principalId,moon,providerMoon:provider,
  baseEnvironmentWire,runtimeBundleCid,resolveSecret,configurationReader,
  sourceInitialization,installationServices,installation}={}){
  const resource=profile?.resource??'labels';
  if(resource==='labels')return loadInstalledGmailLabels(profile,{moon,providerMoon:provider,runtimeBundleCid,
    resolveSecret,configurationReader,sourceInitialization,installationServices,installation});
  if(!sourceInitialization||typeof sourceInitialization!=='object'||nodeTypes.isProxy(sourceInitialization)||
      installation===undefined)fail('GmailSourceInitializationUnavailable');
  const constructor=Object.getOwnPropertyDescriptor(sourceInitialization,'prepareDeclaration');
  if(!constructor||!Object.hasOwn(constructor,'value')||typeof constructor.value!=='function'||
      nodeTypes.isAsyncFunction(constructor.value))fail('GmailSourceInitializationUnavailable');
  const prepareDeclaration=constructor.value;
  const services=captureInstalledSourceServices(installationServices,()=>Object.assign(
    new Error('InstalledGmailSourceServicesUnavailable'),{code:'InstalledGmailSourceServicesUnavailable'}));
  if(typeof resolveSecret!=='function')fail('GmailCredentialMaterialUnavailable');
  if(provider===null||!['object','function'].includes(typeof provider)||nodeTypes.isProxy(provider))fail('InstalledGmailProviderUnavailable');
  const capacityPort=Object.getOwnPropertyDescriptor(moon??{},'clientProgramInstalledGmailThreadReaderCapacity')?.value;
  if(typeof capacityPort!=='function')fail('InstalledSourceReaderRuntimeUnavailable');
  const originalProvider=provider;
  provider=Object.freeze(Object.fromEntries(['gmailThreadSchemaWire','gmailThreadRelationFactsWire','gmailThreadColumnNames',
    'gmailPrepareThreadRead','gmailNextThreadRequest','gmailThreadRequestJson','gmailThreadRequestMatches',
    'gmailAcceptThreadList','gmailAcceptThread','gmailThreadProjectionMatchesRequest','gmailThreadReadCompleted',
    'gmailCloseThreadRead','gmailThreadRowsWire'].map(name=>{
      const field=Object.getOwnPropertyDescriptor(originalProvider,name);
      if(!field||!Object.hasOwn(field,'value')||typeof field.value!=='function')fail('InstalledGmailProviderUnavailable');
      return[name,(...args)=>Reflect.apply(field.value,originalProvider,args)];
    })));
  const{installed,site:siteProfile,ca,binding}=await readInputs(profile,configurationReader),{limits}=installed;
  // Dependent gets are existing protocol occurrences, not extra user knobs or
  // metadata permission. The profile accounts for both original operation arms.
  const policy=services('sourceReaderImplementationProfile',{installation,sourceInitialization,
    metadataResponses:limits.maxThreads,originUnits:siteProfile.apiOrigin.length});
  if(limits.maxDeclarationBytes>policy.maxDeclarationBytes||limits.maxDeclarationNodes>policy.maxDeclarationNodes){
    fail('InstalledGmailImplementationBoundsExceeded');
  }
  const columns=provider.gmailThreadColumnNames().length;
  const selected=gmailThreadReaderSelection(limits,columns,policy);
  const capacity=Reflect.apply(capacityPort,moon,[
    installedJsonSourceReaderLimitNames.map(name=>selected.limits[name]),columns,limits.maxSecretBytes,
    limits.maxPages,limits.maxMailboxBytes]);
  if(capacity===undefined||capacity===null)fail('InstalledSourceReaderCapacityUnavailable');
  const readSequenceConstruction=Object.freeze({capacity,originalLimits:limits,sequence:selected.sequence});
  const implementation=services('sourceReaderImplementation',{installation,sourceInitialization,
    limits:selected.limits,columnCount:columns,readSequenceConstruction});
  const wire=checked(provider.gmailThreadSchemaWire(limits.maxDeclarationBytes,limits.maxDeclarationNodes,limits.maxDepth));
  const{declaration,declared,environment}=Reflect.apply(prepareDeclaration,sourceInitialization,
    [[{resource:'threads',resource_kind:'gmail_threads',schema_wire:wire,schema_cid:sha(wire),
      facts_wire:provider.gmailThreadRelationFactsWire()}],undefined]);
  const target=(resource,fields)=>Object.freeze({version:'actql-installed-gmail-thread-target/0.1',
    apiOrigin:siteProfile.apiOrigin,mailbox:installed.mailbox,mailboxBytesCid:binding.mailboxBytesCid,
    resource,fields:Object.freeze([...fields])});
  const admitsApprovalTarget=(value,resource)=>resource==='threads'&&value?.mailbox===installed.mailbox&&
    Array.isArray(value?.fields)&&new Set(value.fields).size===value.fields.length&&
    value.fields.every(name=>declared.views[0].fields.includes(name))&&
    canonicalJson(value)===canonicalJson(target(resource,value.fields));
  let opened,providerReader;
  try{
    opened=await services('openRowSite',{installation,sourceInitialization,
      profile:Object.freeze({...siteProfile,resourceOrigin:siteProfile.apiOrigin}),
      accountConfiguration:installed.accountConfigurationWire,connection:`gmail:${installed.connectorId}`,ca,
      admitsApprovalTarget,responseHeaders:[],resolveSecret,runAcquisitionLimits:implementation.runAcquisitionLimits});
    const{authorization,site}=opened;
    providerReader=services('createSourceReader',{installation,sourceInitialization,implementation,site,
      prepareReadSequence({resource,columns},applySynchronousProjection){
        if(resource!=='threads')fail('UndeclaredGmailResource');
        return prepareGmailThreadReadSequence({moon:provider,mailbox:installed.mailbox,names:columns,limits},applySynchronousProjection);
      }});
    if(providerReader.capacity!==implementation.capacity)fail('InstalledGmailReaderImplementationMismatch');
    return await createInstalledRowSource({moon,declaration,declared,environment,environmentWire:environment.wire,
      sourceInitialization,connectorId:installed.connectorId,connectorRegistration:registration,connectorRevision:revision,
      authorization,site,readOperation:GMAIL_THREAD_LIST_OPERATION,physicalTarget:target,
      bindingCid:cid({version:'actql-installed-gmail-thread-binding/0.1',connectorId:installed.connectorId,
        connectorRegistration:registration,connectorRevision:revision,contextCid:authorization.context.contextCid,
        runtimeBundleCid,mailbox:installed.mailbox,...binding,site:siteProfile}),
      limits:{maxPages:limits.maxPages+limits.maxThreads,maxPageBytes:limits.maxResponseBytes,
        maxPageRows:1,maxCaptureRows:limits.maxThreads},providerReader});
  }catch(cause){throw await retainInstalledHostInitializationFailure(cause,
    {sourceReader:providerReader,sourceProfile:opened?.site});}
}


// The single-response labels reader uses the same original Source constructor,
// service implementation and managed reader as other standard JSON pages.
// Threads use their original list/get protocol under the same reader owner.
async function loadInstalledGmailLabels(profile,{moon,providerMoon,runtimeBundleCid,resolveSecret,
  configurationReader,sourceInitialization,installationServices,installation}){
  if(!sourceInitialization||typeof sourceInitialization!=='object'||nodeTypes.isProxy(sourceInitialization)||
      installation===undefined)fail('GmailSourceInitializationUnavailable');
  const constructor=Object.getOwnPropertyDescriptor(sourceInitialization,'prepareDeclaration');
  if(!constructor||!Object.hasOwn(constructor,'value')||typeof constructor.value!=='function'||
      nodeTypes.isAsyncFunction(constructor.value))fail('GmailSourceInitializationUnavailable');
  const prepareDeclaration=constructor.value;
  const services=captureInstalledSourceServices(installationServices,()=>Object.assign(
    new Error('InstalledGmailSourceServicesUnavailable'),{code:'InstalledGmailSourceServicesUnavailable'}));
  if(configurationReader===undefined||configurationReader===null)fail('InstalledGmailConfigurationReaderUnavailable');
  if(typeof resolveSecret!=='function')fail('GmailCredentialMaterialUnavailable');
  if(providerMoon===null||!['object','function'].includes(typeof providerMoon)||nodeTypes.isProxy(providerMoon)){
    fail('InstalledGmailProviderUnavailable');
  }
  const provider=Object.freeze(Object.fromEntries(['gmailLabelListSchemaWire','gmailLabelListRelationFactsWire',
    'gmailLabelListColumnNames','gmailProjectLabelList','gmailLabelListRowsWire','gmailLabelListMetadataJson'].map(name=>{
    const field=Object.getOwnPropertyDescriptor(providerMoon,name);
    if(!field||!Object.hasOwn(field,'value')||typeof field.value!=='function')fail('InstalledGmailProviderUnavailable');
    return[name,(...args)=>Reflect.apply(field.value,providerMoon,args)];
  })));
  const{installed,site:siteProfile,ca,binding}=await readInputs(profile,configurationReader),{limits}=installed;
  const policy=services('sourceReaderImplementationProfile',{installation,sourceInitialization,
    metadataResponses:0,originUnits:siteProfile.apiOrigin.length});
  if(limits.maxDeclarationBytes>policy.maxDeclarationBytes||limits.maxDeclarationNodes>policy.maxDeclarationNodes){
    fail('InstalledGmailImplementationBoundsExceeded');
  }
  // Exactly one complete response; no cursor is constructed. The positive
  // cursor sentinel occupies only the existing generic non-paginated field.
  // Original admitted value-text bounds include the label id's String.
  const implementation=services('sourceReaderImplementation',{installation,sourceInitialization,
    columnCount:provider.gmailLabelListColumnNames().length,limits:{
      maxResponseBytes:limits.maxResponseBytes,maxTotalResponseBytes:limits.maxResponseBytes,
      maxNodes:limits.maxNodes,maxDepth:limits.maxDepth,maxRows:limits.maxRows,maxTotalRows:limits.maxRows,
      maxPages:1,pageSize:limits.maxRows,maxCursorBytes:1,maxIdentityBytes:limits.maxValueTextBytes,
      maxTargetBytes:limits.maxTargetBytes,maxValueNodes:limits.maxValueNodes,maxValueTextBytes:limits.maxValueTextBytes,
      maxRowsWireBytes:limits.maxRowsWireBytes,maxRowsWireNodes:limits.maxRowsWireNodes,
      maxRowsWireDepth:limits.maxRowsWireDepth,maxSecretBytes:limits.maxSecretBytes}});
  const wire=checked(provider.gmailLabelListSchemaWire(limits.maxDeclarationBytes,limits.maxDeclarationNodes,limits.maxDepth));
  const{declaration,declared,environment}=Reflect.apply(prepareDeclaration,sourceInitialization,
    [[{resource:'labels',resource_kind:'gmail_labels',schema_wire:wire,schema_cid:sha(wire),
      facts_wire:provider.gmailLabelListRelationFactsWire()}],undefined]);
  const target=(resource,fields)=>Object.freeze({version:'actql-installed-gmail-label-target/0.1',
    apiOrigin:siteProfile.apiOrigin,mailbox:installed.mailbox,mailboxBytesCid:binding.mailboxBytesCid,
    resource,fields:Object.freeze([...fields])});
  const admitsApprovalTarget=(value,resource)=>resource==='labels'&&value?.mailbox===installed.mailbox&&
    Array.isArray(value?.fields)&&new Set(value.fields).size===value.fields.length&&
    value.fields.every(name=>declared.views[0].fields.includes(name))&&
    canonicalJson(value)===canonicalJson(target(resource,value.fields));
  let opened,providerReader;
  try{
    opened=await services('openRowSite',{installation,sourceInitialization,
      profile:Object.freeze({...siteProfile,resourceOrigin:siteProfile.apiOrigin}),
      accountConfiguration:installed.accountConfigurationWire,connection:`gmail:${installed.connectorId}`,ca,
      admitsApprovalTarget,responseHeaders:[],resolveSecret,runAcquisitionLimits:implementation.runAcquisitionLimits});
    const{authorization,site}=opened;
    providerReader=services('createSourceReader',{installation,sourceInitialization,implementation,site,
      operation:GMAIL_LABEL_LIST_OPERATION,preparePageReader({resource,columns},applySynchronousProjection){
        if(resource!=='labels')fail('UndeclaredGmailResource');
        return prepareGmailLabelListPages({moon:provider,mailbox:installed.mailbox,names:columns,limits},applySynchronousProjection);
      }});
    if(providerReader.capacity!==implementation.capacity)fail('InstalledGmailReaderImplementationMismatch');
    return await createInstalledRowSource({moon,declaration,declared,environment,environmentWire:environment.wire,
      sourceInitialization,connectorId:installed.connectorId,connectorRegistration:registration,connectorRevision:revision,
      authorization,site,readOperation:GMAIL_LABEL_LIST_OPERATION,physicalTarget:target,
      bindingCid:cid({version:'actql-installed-gmail-label-binding/0.1',connectorId:installed.connectorId,
        connectorRegistration:registration,connectorRevision:revision,contextCid:authorization.context.contextCid,
        runtimeBundleCid,mailbox:installed.mailbox,...binding,site:siteProfile}),
      limits:{maxPages:1,maxPageBytes:limits.maxResponseBytes,maxPageRows:limits.maxRows,maxCaptureRows:limits.maxRows},
      providerReader});
  }catch(cause){throw await retainInstalledHostInitializationFailure(cause,
    {sourceReader:providerReader,sourceProfile:opened?.site});}
}
