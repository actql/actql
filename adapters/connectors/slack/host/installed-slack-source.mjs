// Installation metadata and physical adaptation only. Common retains the
// checked declaration, acquisition, planner, Ledger, RowRun and capture.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {readSourceProfileJson,readBoundedConfigurationText} from '../../../host-node/source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {createInstalledRowSource,installRowSourceAuthorization,openRowSourceCredentialSite,
  rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {SLACK_USER_LIST_OPERATION} from '../site/user-list-read.mjs';
import {createSlackUserSourceReaderFactory} from './user-source-reader.mjs';
import {SLACK_CHANNEL_LIST_OPERATION} from '../site/channel-list-read.mjs';
import {createSlackChannelSourceReaderFactory} from './channel-source-reader.mjs';
import {SLACK_MESSAGE_HISTORY_OPERATION} from '../site/message-history-read.mjs';
import {createSlackMessageSourceReaderFactory} from './message-source-reader.mjs';

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

async function readInputs(profile){
  const installed=checkInstalledSlackSourceProfile(profile);
  const site=checkSite(await readSourceProfileJson(installed.siteProfilePath));
  let ca;
  if(site.caPath!==undefined){
    // This private Site accepts bounded PEM text, not an unbounded file read
    // or lenient UTF-8 identity. Non-ASCII/replacement input is refused rather
    // than re-encoding different authority bytes before hashing/native TLS.
    const pem=await readBoundedConfigurationText(site.caPath,{maxBytes:installed.limits.maxCaBytes});
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

export async function installedSlackSourceIdentityParts(profile,providerProfile){
  const{site,binding}=await readInputs(providerProfile);
  return[{...profile,accountConfigurationWire:JSON.parse(profile.accountConfigurationWire)},site,binding];
}

export async function loadInstalledSlackSource(profile,{root,principalId,moon,providerMoon:provider,
  baseEnvironmentWire,runtimeBundleCid,resolveSecret,readerCapacity}={}){
  // The existing trusted installer must supply its same-runtime declaration.
  // Public profile amounts, page/transfer limits and fixed spare constants are
  // not a full reader retained/workspace supplier. Never choose legacy readPages.
  if(readerCapacity===undefined||readerCapacity===null)fail('SlackReaderCapacityUnavailable');
  if(typeof resolveSecret!=='function')fail('SlackCredentialMaterialUnavailable');
  const{installed,site:siteProfile,ca,binding}=await readInputs(profile);
  const{limits}=installed;
  if(provider===null||typeof provider!=='object'||types.isProxy(provider))fail('InvalidInstalledSlackProvider');
  const declarationPorts=Object.freeze(Object.fromEntries(['slackUserListSchemaWire',
    'slackUserListRelationFactsWire','slackChannelListSchemaWire','slackChannelListRelationFactsWire',
    'slackMessageSchemaWire','slackMessageRelationFactsWire'].map(name=>{
    const descriptor=Object.getOwnPropertyDescriptor(provider,name);
    if(!descriptor||!Object.hasOwn(descriptor,'value')||typeof descriptor.value!=='function')fail('InvalidInstalledSlackProvider');
    return [name,descriptor.value];
  })));
  const views=[['users','slack_users','slackUserListSchemaWire','slackUserListRelationFactsWire'],
    ['channels','slack_channels','slackChannelListSchemaWire','slackChannelListRelationFactsWire'],
    ['messages','slack_messages','slackMessageSchemaWire','slackMessageRelationFactsWire']].map(
    ([resource,resource_kind,schema,facts])=>{
      const wire=checked(Reflect.apply(declarationPorts[schema],provider,[limits.maxDeclarationBytes,
        limits.maxDeclarationNodes,limits.maxDepth]));
      return {resource,resource_kind,schema_wire:wire,schema_cid:sha(wire),
        facts_wire:Reflect.apply(declarationPorts[facts],provider,[])};
    });
  const declaration=checked(moon.clientProgramRowSourceRestoreRelationDeclaration(installed.connectorId,
    registration,revision,JSON.stringify({views}),undefined));
  const declared=JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment=rowSourceCheckEnvironment(baseEnvironmentWire,declared);
  const authorization=await installRowSourceAuthorization({root,principalId,connectorRegistration:registration,
    accountConfiguration:installed.accountConfigurationWire});
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
  const site=await openRowSourceCredentialSite({profile:{...siteProfile,resourceOrigin:siteProfile.apiOrigin},
    principalId,authorization,connection,connectorRegistration:registration,connectorRevision:revision,
    runtimeBundleCid,commonMoon:moon,ca,admitsApprovalTarget,responseHeaders:[],resolveSecret});
  try{
    return await createInstalledRowSource({moon,declaration,declared,environmentWire:environment.wire,
      connectorId:installed.connectorId,connectorRegistration:registration,connectorRevision:revision,
      authorization,site,readOperation:{users:SLACK_USER_LIST_OPERATION,channels:SLACK_CHANNEL_LIST_OPERATION,
        messages:SLACK_MESSAGE_HISTORY_OPERATION},physicalTarget:target,
      bindingCid:cid({version:'actql-installed-slack-source-binding/0.1',connectorId:installed.connectorId,
        connectorRegistration:registration,connectorRevision:revision,contextCid:authorization.context.contextCid,
        runtimeBundleCid,workspaceId:installed.workspaceId,...binding,site:siteProfile}),
      limits:{maxPages:limits.maxPages,maxPageBytes:limits.maxResponseBytes,maxPageRows:limits.maxRows,maxCaptureRows:limits.maxTotalRows},
      providerReader:(()=>{
        const selected=new Map([
          ['users',createSlackUserSourceReaderFactory],['channels',createSlackChannelSourceReaderFactory],
          ['messages',createSlackMessageSourceReaderFactory],
        ].map(([name,factory])=>[name,factory({provider,site,capacity:readerCapacity,
          workspaceId:installed.workspaceId,limits,maxSecretBytes:limits.maxSecretBytes})]));
        const reader=Object.freeze({capacity:readerCapacity,prepare(options){
          if(this!==reader)fail('ForeignInstalledSlackReaderFactory');
          if(options===null||typeof options!=='object'||types.isProxy(options))fail('ForeignInstalledSlackRead');
          const descriptor=Object.getOwnPropertyDescriptor(options,'resource');
          if(!descriptor||!Object.hasOwn(descriptor,'value'))fail('ForeignInstalledSlackRead');
          const factory=selected.get(descriptor.value);if(factory===undefined)fail('ForeignInstalledSlackRead');
          return Reflect.apply(factory.prepare,factory,[options]);
        }});
        return reader;
      })(),
      readPages(){fail('InstalledSlackLegacyReaderUnavailable');}});
  }catch(cause){throw await retainInstalledHostInitializationFailure(cause,{sourceProfile:site});}
}
