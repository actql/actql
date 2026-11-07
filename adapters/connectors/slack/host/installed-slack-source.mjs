// Installation metadata and physical adaptation only. Common retains the
// checked declaration, acquisition, planner, Ledger, RowRun and capture.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {createInstalledRowSource} from '../../../host-node/installed-row-source.mjs';
import {installedJsonSourceReaderLimitNames} from '../../../host-node/installed-credential-source-reader.mjs';
import {captureInstalledSourceServices} from '../../../host-node/installed-host-services.mjs';
import {prepareSlackSourceReadSequence} from '../site/slack-source-read.mjs';
import {SLACK_USER_LIST_OPERATION} from '../site/user-list-read.mjs';
import {SLACK_CHANNEL_LIST_OPERATION} from '../site/channel-list-read.mjs';
import {SLACK_MESSAGE_HISTORY_OPERATION} from '../site/message-history-read.mjs';

export const INSTALLED_SLACK_SOURCE_VERSION='actql-installed-slack-source/0.1';
export const INSTALLED_SLACK_SITE_VERSION='actql-installed-slack-site/0.1';
const registration='slack',revision='slack/0.1';
const profileKeys=['version','connectorId','workspaceId','siteProfilePath','accountConfigurationWire','limits'];
const siteKeys=['version','apiOrigin','credentialAuthorityId','credentialKeyId','credentialPrivateKeyPath',
  'environment','journalRoot','namespaceId','siteGeneration','siteKey'];
const readLimitKeys=['maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth',
  'maxRows','maxTotalRows','maxPages','pageSize','maxCursorBytes','maxIdentityBytes',
  'maxTargetBytes','maxValueNodes','maxValueTextBytes','maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'];
const limitKeys=[...readLimitKeys,'maxDeclarationBytes','maxDeclarationNodes','maxSecretBytes','maxCaBytes'];
const fail=code=>{throw Object.assign(new Error(code),{code});};
const text=value=>typeof value==='string'&&value.length>0&&value.isWellFormed()&&!/[\u0000-\u001f\u007f]/u.test(value);
const absolute=value=>text(value)&&isAbsolute(value);
const positive=value=>Number.isSafeInteger(value)&&value>0&&value<=2147483647;
function snapshot(value,required,optional=[],code='InvalidInstalledSlackSourceProfile'){
  if(value===null||typeof value!=='object'||Array.isArray(value)||types.isProxy(value))fail(code);
  const keys=Reflect.ownKeys(value);
  if(required.some(key=>!keys.includes(key))||keys.some(key=>!required.includes(key)&&!optional.includes(key)))fail(code);
  const result={};
  for(const key of keys){
    const descriptor=Object.getOwnPropertyDescriptor(value,key);
    if(!descriptor?.enumerable||!Object.hasOwn(descriptor,'value'))fail(code);
    result[key]=descriptor.value;
  }
  return result;
}
const sha=bytes=>`sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const cid=value=>sha(canonicalJson(value));

export function checkInstalledSlackSourceProfile(value){
  const profile=snapshot(value,profileKeys),limits=snapshot(profile.limits,limitKeys);
  if(profile.version!==INSTALLED_SLACK_SOURCE_VERSION||!text(profile.connectorId)||!text(profile.workspaceId)||
      !absolute(profile.siteProfilePath)||typeof profile.accountConfigurationWire!=='string'||
      !limitKeys.every(key=>positive(limits[key]))||limits.pageSize>=1000||
      BigInt(limits.maxTotalResponseBytes)>BigInt(limits.maxPages)*BigInt(limits.maxResponseBytes)||
      Buffer.byteLength(profile.workspaceId)>limits.maxIdentityBytes)fail('InvalidInstalledSlackSourceProfile');
  return Object.freeze({...profile,limits:Object.freeze(limits)});
}

function checkSite(value){
  const site=snapshot(value,siteKeys,['caPath'],'InvalidInstalledSlackSite');let origin;
  try{origin=new URL(site.apiOrigin);}catch{/* Closed rejection below. */}
  if(site.version!==INSTALLED_SLACK_SITE_VERSION||origin?.protocol!=='https:'||origin.origin!==site.apiOrigin||
      !['credentialAuthorityId','credentialKeyId','environment','namespaceId','siteKey'].every(key=>text(site[key]))||
      !absolute(site.credentialPrivateKeyPath)||!absolute(site.journalRoot)||
      !Number.isSafeInteger(site.siteGeneration)||site.siteGeneration<0||
      (Object.hasOwn(site,'caPath')&&!absolute(site.caPath)))fail('InvalidInstalledSlackSite');
  return Object.freeze(site);
}

async function readInputs(profile,configurationReader,readJson){
  const installed=checkInstalledSlackSourceProfile(profile);
  const reads=captureConfigurationReaders(configurationReader,readJson,()=>fail('InstalledSlackConfigurationReaderUnavailable'));
  const site=checkSite(await reads.readJson(installed.siteProfilePath));
  let ca;
  if(site.caPath!==undefined){
    // This private Site accepts bounded PEM text, not an unbounded file read
    // or lenient UTF-8 identity. Non-ASCII/replacement input is refused rather
    // than re-encoding different authority bytes before hashing/native TLS.
    const pem=await reads.readText(site.caPath,{maxBytes:installed.limits.maxCaBytes});
    if(/[^\x09\x0a\x0d\x20-\x7e]/u.test(pem)||!pem.includes('-----BEGIN CERTIFICATE-----')||
        !pem.includes('-----END CERTIFICATE-----'))fail('InvalidInstalledSlackTlsAuthority');
    ca=Buffer.from(pem,'ascii');
  }
  // Configuration canonicalization must not collapse distinct original
  // workspaceId bytes or drop the selected TLS authority from this generation.
  const binding={workspaceBytesCid:sha(Buffer.from(installed.workspaceId)),
    ...(ca===undefined?{}:{caSha256:sha(ca)})};
  return{installed,site,ca,binding};
}

export async function installedSlackSourceIdentityParts(profile,providerProfile,read,_installation,context){
  const{site,binding}=await readInputs(providerProfile,context?.configurationReader,read);
  return[{...profile,accountConfigurationWire:JSON.parse(profile.accountConfigurationWire)},site,binding];
}

// Original Source profile and operation occurrences select the existing Core
// composition once. The shared Host keeps this exact result through cleanup.
function slackReaderSelection(original, columns, profile) {
  if (original.maxPages === 2147483647 || original.pageSize >= 1000 ||
      columns > profile.maxColumns || original.maxDeclarationBytes > profile.maxDeclarationBytes ||
      original.maxDeclarationNodes > profile.maxDeclarationNodes) fail('InstalledSourceReaderImplementationBoundsExceeded');
  const children = entries => Object.freeze(entries.map(([operation,maxUses]) => Object.freeze({operation,maxUses})));
  const sequence = (operation,maxUses,entries) => Object.freeze({operation,maxUses,children:children(entries)});
  return Object.freeze({original,limits:Object.freeze({...Object.fromEntries(
    installedJsonSourceReaderLimitNames.map(name => [name,original[name]])),
    maxPages:original.maxPages+1,maxSecretBytes:original.maxSecretBytes}),
    sequences:Object.freeze({
      users:sequence('slack:users:list',original.maxPages,[['slack:workspace:identity',1]]),
      channels:sequence('slack:channels:list',original.maxPages,[['slack:workspace:identity',1]]),
      messages:sequence('slack:messages:history',original.maxPages,[
        ['slack:workspace:identity',original.maxPages],['slack:channels:list',original.maxPages],
        ['slack:messages:replies',original.maxPages]]),
    })});
}

export async function loadInstalledSlackSource(profile,{moon,providerMoon:provider,
  runtimeBundleCid,resolveSecret,configurationReader,sourceInitialization,installationServices,installation}={}){
  if(!sourceInitialization||typeof sourceInitialization!=='object'||types.isProxy(sourceInitialization)||
      installation===undefined)fail('SlackSourceInitializationUnavailable');
  const constructor=Object.getOwnPropertyDescriptor(sourceInitialization,'prepareDeclaration');
  if(!constructor||!Object.hasOwn(constructor,'value')||typeof constructor.value!=='function'||
      types.isAsyncFunction(constructor.value))fail('SlackSourceInitializationUnavailable');
  const prepareDeclaration=constructor.value;
  const services=captureInstalledSourceServices(installationServices,()=>Object.assign(
    new Error('InstalledSlackSourceServicesUnavailable'),{code:'InstalledSlackSourceServicesUnavailable'}));
  if(typeof resolveSecret!=='function')fail('SlackCredentialMaterialUnavailable');
  const capacityPort=Object.getOwnPropertyDescriptor(moon??{},'clientProgramInstalledSlackSourceReaderCapacity')?.value;
  if(typeof capacityPort!=='function')fail('InstalledSourceReaderRuntimeUnavailable');
  const{installed,site:siteProfile,ca,binding}=await readInputs(profile,configurationReader);
  const{limits}=installed;
  if(provider===null||typeof provider!=='object'||types.isProxy(provider))fail('InvalidInstalledSlackProvider');
  const declarationPorts=Object.freeze(Object.fromEntries(['slackUserListSchemaWire',
    'slackUserListRelationFactsWire','slackChannelListSchemaWire','slackChannelListRelationFactsWire',
    'slackMessageSchemaWire','slackMessageRelationFactsWire','slackUserListColumnNames',
    'slackChannelListColumnNames','slackMessageColumnNames'].map(name=>{
    const descriptor=Object.getOwnPropertyDescriptor(provider,name);
    if(!descriptor||!Object.hasOwn(descriptor,'value')||typeof descriptor.value!=='function')fail('InvalidInstalledSlackProvider');
    return [name,descriptor.value];
  })));
  const policy=services('sourceReaderImplementationProfile',{installation,sourceInitialization,
    metadataResponses:1,originUnits:siteProfile.apiOrigin.length});
  if(limits.maxDeclarationBytes>policy.maxDeclarationBytes||limits.maxDeclarationNodes>policy.maxDeclarationNodes){
    fail('InstalledSlackImplementationBoundsExceeded');
  }
  const columnCount=Math.max(...['slackUserListColumnNames','slackChannelListColumnNames','slackMessageColumnNames']
    .map(name=>Reflect.apply(declarationPorts[name],provider,[]).length));
  const selected=slackReaderSelection(limits,columnCount,policy);
  const capacity=Reflect.apply(capacityPort,moon,[
    installedJsonSourceReaderLimitNames.map(name=>selected.limits[name]),columnCount,limits.maxSecretBytes,limits.maxPages]);
  if(capacity===undefined||capacity===null)fail('InstalledSourceReaderCapacityUnavailable');
  const readSequenceConstruction=Object.freeze({capacity,originalLimits:limits,sequences:selected.sequences,maxRequestBytes:2});
  const implementation=services('sourceReaderImplementation',{installation,sourceInitialization,
    limits:selected.limits,columnCount,readSequenceConstruction});
  const views=[['users','slack_users','slackUserListSchemaWire','slackUserListRelationFactsWire'],
    ['channels','slack_channels','slackChannelListSchemaWire','slackChannelListRelationFactsWire'],
    ['messages','slack_messages','slackMessageSchemaWire','slackMessageRelationFactsWire']].map(
    ([resource,resource_kind,schema,facts])=>{
      const wire=checked(Reflect.apply(declarationPorts[schema],provider,[limits.maxDeclarationBytes,
        limits.maxDeclarationNodes,limits.maxDepth]));
      return {resource,resource_kind,schema_wire:wire,schema_cid:sha(wire),
        facts_wire:Reflect.apply(declarationPorts[facts],provider,[])};
    });
  const{declaration,declared,environment}=Reflect.apply(prepareDeclaration,sourceInitialization,[views,undefined]);
  const connection=`slack:${installed.connectorId}`;
  const target=(selected,fields)=>Object.freeze({version:selected==='users'
    ?'actql-installed-slack-users-target/0.1':selected==='channels'
      ?'actql-installed-slack-channels-target/0.1':'actql-installed-slack-messages-target/0.1',
    apiOrigin:siteProfile.apiOrigin,workspaceId:installed.workspaceId,workspaceBytesCid:binding.workspaceBytesCid,
    resource:selected,fields:Object.freeze([...fields])});
  const admitsApprovalTarget=(value,selected)=>declared.views.some(view=>view.resource===selected)&&value?.workspaceId===installed.workspaceId&&
    Array.isArray(value?.fields)&&new Set(value.fields).size===value.fields.length&&
    value.fields.every(name=>declared.views.find(view=>view.resource===selected).fields.includes(name))&&
    canonicalJson(value)===canonicalJson(target(selected,value.fields));
  let opened,providerReader;
  try{
    opened=await services('openRowSite',{installation,sourceInitialization,
      profile:Object.freeze({...siteProfile,resourceOrigin:siteProfile.apiOrigin}),
      accountConfiguration:installed.accountConfigurationWire,connection,ca,
      admitsApprovalTarget,responseHeaders:[],resolveSecret,runAcquisitionLimits:implementation.runAcquisitionLimits});
    const{authorization,site}=opened;
    providerReader=services('createSourceReader',{installation,sourceInitialization,implementation,site,
      prepareReadSequence({resource,columns},applySynchronousProjection){
        return prepareSlackSourceReadSequence({moon:provider,workspaceId:installed.workspaceId,
          resource,names:columns,limits},applySynchronousProjection);
      }});
    if(providerReader.capacity!==implementation.capacity)fail('InstalledSlackReaderImplementationMismatch');
    return await createInstalledRowSource({moon,declaration,declared,environment,environmentWire:environment.wire,
      sourceInitialization,connectorId:installed.connectorId,connectorRegistration:registration,connectorRevision:revision,
      authorization,site,readOperation:{users:SLACK_USER_LIST_OPERATION,channels:SLACK_CHANNEL_LIST_OPERATION,
        messages:SLACK_MESSAGE_HISTORY_OPERATION},physicalTarget:target,
      bindingCid:cid({version:'actql-installed-slack-source-binding/0.1',connectorId:installed.connectorId,
        connectorRegistration:registration,connectorRevision:revision,contextCid:authorization.context.contextCid,
        runtimeBundleCid,workspaceId:installed.workspaceId,...binding,site:siteProfile}),
      limits:{maxPages:limits.maxPages+1,maxPageBytes:limits.maxResponseBytes,
        maxPageRows:limits.maxRows,maxCaptureRows:limits.maxTotalRows},providerReader});
  }catch(cause){throw await retainInstalledHostInitializationFailure(cause,
    {sourceReader:providerReader,sourceProfile:opened?.site});}
}
