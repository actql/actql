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
import type {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';

type SourceSequence = Parameters<typeof prepareSlackSourceReadSequence>;
type Resource = SourceSequence[0]['resource'];
type Reader = ReturnType<typeof createInstalledCredentialSourceReader>;
type RowSourceInput = Parameters<typeof createInstalledRowSource>[0];
type DeclaredView = RowSourceInput['declared']['views'][number] & Readonly<{fields: readonly string[]}>;
type Prepared = Readonly<{declaration: unknown; declared: Omit<RowSourceInput['declared'], 'views'> &
  Readonly<{views: readonly DeclaredView[]}>; environment: Readonly<{wire: string}>}>;
type Site = Readonly<Record<Exclude<typeof siteKeys[number], 'siteGeneration'>, string> &
  {siteGeneration: number; caPath?: string}>;
type Limits = Readonly<Record<typeof limitKeys[number], number>>;
type Profile = Readonly<{version: string; connectorId: string; workspaceId: string; siteProfilePath: string;
  limits: Limits; accountConfigurationWire: string}>;
type ReaderProfile = Readonly<{maxColumns: number; maxDeclarationBytes: number; maxDeclarationNodes: number}>;
type Implementation = Readonly<{capacity: unknown; runAcquisitionLimits: unknown}>;
type Opened = Readonly<{site: RowSourceInput['site']; authorization: RowSourceInput['authorization'] &
  Readonly<{context: Readonly<{contextCid: string}>}>}>;
type Services = {
  (method: 'sourceReaderImplementationProfile', input: Readonly<Record<string, unknown>>): ReaderProfile;
  (method: 'sourceReaderImplementation', input: Readonly<Record<string, unknown>>): Implementation;
  (method: 'openRowSite', input: Readonly<Record<string, unknown>>): Promise<Opened>;
  (method: 'createSourceReader', input: Readonly<Record<string, unknown>>): Reader;
};
type LoadOptions = Readonly<{moon?: RowSourceInput['moon']; providerMoon?: unknown; runtimeBundleCid?: string;
  resolveSecret?: unknown; configurationReader?: unknown; sourceInitialization?: unknown;
  installationServices?: unknown; installation?: unknown}>;
type Selection = Readonly<{resource: Resource; columns: readonly string[]}>;
type DeclarationFamily = 'UserList' | 'ChannelList' | 'Message';
type DeclarationPorts =
  Readonly<Record<`slack${DeclarationFamily}SchemaWire`, (bytes: number, nodes: number, depth: number) => unknown>> &
  Readonly<Record<`slack${DeclarationFamily}RelationFactsWire`, () => string>> &
  Readonly<Record<`slack${DeclarationFamily}ColumnNames`, () => readonly string[]>>;

export const INSTALLED_SLACK_SOURCE_VERSION='actql-installed-slack-source/0.1';
export const INSTALLED_SLACK_SITE_VERSION='actql-installed-slack-site/0.1';
const registration='slack',revision='slack/0.1';
const profileKeys=['version','connectorId','workspaceId','siteProfilePath','accountConfigurationWire','limits'];
const siteKeys=['version','apiOrigin','credentialAuthorityId','credentialKeyId','credentialPrivateKeyPath',
  'environment','journalRoot','namespaceId','siteGeneration','siteKey'] as const;
const readLimitKeys=['maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth',
  'maxRows','maxTotalRows','maxPages','pageSize','maxCursorBytes','maxIdentityBytes',
  'maxTargetBytes','maxValueNodes','maxValueTextBytes','maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'] as const;
const limitKeys=[...readLimitKeys,'maxDeclarationBytes','maxDeclarationNodes','maxSecretBytes','maxCaBytes'] as const;
const fail: (code: string) => never = code=>{throw Object.assign(new Error(code),{code});};
const text=(value: unknown): value is string=>typeof value==='string'&&value.length>0&&value.isWellFormed()&&!/[\u0000-\u001f\u007f]/u.test(value);
const absolute=(value: unknown): value is string=>text(value)&&isAbsolute(value);
const positive=(value: number)=>Number.isSafeInteger(value)&&value>0&&value<=2147483647;
function snapshot(value: unknown, required: readonly (string | symbol)[],
  optional: readonly (string | symbol)[]=[], code='InvalidInstalledSlackSourceProfile'){
  if(value===null||typeof value!=='object'||Array.isArray(value)||types.isProxy(value))fail(code);
  const keys=Reflect.ownKeys(value);
  if(required.some(key=>!keys.includes(key))||keys.some(key=>!required.includes(key)&&!optional.includes(key)))fail(code);
  const result: Record<PropertyKey, unknown> = {};
  for(const key of keys){
    const descriptor=Object.getOwnPropertyDescriptor(value,key);
    if(!descriptor?.enumerable||!Object.hasOwn(descriptor,'value'))fail(code);
    result[key]=descriptor.value;
  }
  return result;
}
const sha=(bytes: string | Buffer)=>`sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const cid=(value: unknown)=>sha(canonicalJson(value));

export function checkInstalledSlackSourceProfile(value: unknown){
  const profile=snapshot(value,profileKeys) as Profile,limits=snapshot(profile.limits,limitKeys) as Limits;
  if(profile.version!==INSTALLED_SLACK_SOURCE_VERSION||!text(profile.connectorId)||!text(profile.workspaceId)||
      !absolute(profile.siteProfilePath)||typeof profile.accountConfigurationWire!=='string'||
      !limitKeys.every(key=>positive(limits[key]))||limits.pageSize>=1000||
      BigInt(limits.maxTotalResponseBytes)>BigInt(limits.maxPages)*BigInt(limits.maxResponseBytes)||
      Buffer.byteLength(profile.workspaceId)>limits.maxIdentityBytes)fail('InvalidInstalledSlackSourceProfile');
  return Object.freeze({...profile,limits:Object.freeze(limits)});
}

function checkSite(value: unknown){
  const site=snapshot(value,siteKeys,['caPath'],'InvalidInstalledSlackSite') as Site;let origin: URL | undefined;
  try{origin=new URL(site.apiOrigin);}catch{/* Closed rejection below. */}
  if(site.version!==INSTALLED_SLACK_SITE_VERSION||origin?.protocol!=='https:'||origin.origin!==site.apiOrigin||
      !(['credentialAuthorityId','credentialKeyId','environment','namespaceId','siteKey'] as const).every(key=>text(site[key]))||
      !absolute(site.credentialPrivateKeyPath)||!absolute(site.journalRoot)||
      !Number.isSafeInteger(site.siteGeneration)||site.siteGeneration<0||
      (Object.hasOwn(site,'caPath')&&!absolute(site.caPath)))fail('InvalidInstalledSlackSite');
  return Object.freeze(site);
}

async function readInputs(profile: unknown, configurationReader: unknown, readJson?: unknown){
  const installed=checkInstalledSlackSourceProfile(profile);
  const reads=captureConfigurationReaders(configurationReader,readJson,()=>fail('InstalledSlackConfigurationReaderUnavailable'));
  const site=checkSite(await reads.readJson(installed.siteProfilePath));
  let ca;
  if(site.caPath!==undefined){
    // This private Site accepts bounded PEM text, not an unbounded file read
    // or lenient UTF-8 identity. Non-ASCII/replacement input is refused rather
    // than re-encoding different authority bytes before hashing/native TLS.
    const pem=await reads.readText(site.caPath,{maxBytes:installed.limits.maxCaBytes}) as string;
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

export async function installedSlackSourceIdentityParts(profile: Readonly<{accountConfigurationWire: string}>,
  providerProfile: unknown, read?: unknown, _installation?: unknown, context?: Readonly<{configurationReader?: unknown}>){
  const{site,binding}=await readInputs(providerProfile,context?.configurationReader,read);
  return[{...profile,accountConfigurationWire:JSON.parse(profile.accountConfigurationWire)},site,binding];
}

// Original Source profile and operation occurrences select the existing Core
// composition once. The shared Host keeps this exact result through cleanup.
function slackReaderSelection(original: Limits, columns: number, profile: ReaderProfile) {
  if (original.maxPages === 2147483647 || original.pageSize >= 1000 ||
      columns > profile.maxColumns || original.maxDeclarationBytes > profile.maxDeclarationBytes ||
      original.maxDeclarationNodes > profile.maxDeclarationNodes) fail('InstalledSourceReaderImplementationBoundsExceeded');
  const children = (entries: readonly (readonly [string, number])[]) => Object.freeze(entries.map(([operation,maxUses]) => Object.freeze({operation,maxUses})));
  const sequence = (operation: string, maxUses: number, entries: Parameters<typeof children>[0]) => Object.freeze({operation,maxUses,children:children(entries)});
  return Object.freeze({original,limits:Object.freeze({...Object.fromEntries(
    installedJsonSourceReaderLimitNames.map(name => [name,original[name]])),
    maxPages:original.maxPages+1,maxSecretBytes:original.maxSecretBytes}) as SourceSequence[0]['limits'] & Readonly<{maxSecretBytes: number}>,
    sequences:Object.freeze({
      users:sequence('slack:users:list',original.maxPages,[['slack:workspace:identity',1]]),
      channels:sequence('slack:channels:list',original.maxPages,[['slack:workspace:identity',1]]),
      messages:sequence('slack:messages:history',original.maxPages,[
        ['slack:workspace:identity',original.maxPages],['slack:channels:list',original.maxPages],
        ['slack:messages:replies',original.maxPages]]),
    })});
}

export async function loadInstalledSlackSource(profile: unknown,{moon,providerMoon:provider,
  runtimeBundleCid,resolveSecret,configurationReader,sourceInitialization,installationServices,installation}: LoadOptions={}){
  if(!sourceInitialization||typeof sourceInitialization!=='object'||types.isProxy(sourceInitialization)||
      installation===undefined)fail('SlackSourceInitializationUnavailable');
  const constructor=Object.getOwnPropertyDescriptor(sourceInitialization,'prepareDeclaration');
  if(!constructor||!Object.hasOwn(constructor,'value')||typeof constructor.value!=='function'||
      types.isAsyncFunction(constructor.value))fail('SlackSourceInitializationUnavailable');
  const prepareDeclaration=constructor.value as (views: readonly unknown[], expectedCatalogCid: undefined) => Prepared;
  const services=captureInstalledSourceServices(installationServices,()=>Object.assign(
    new Error('InstalledSlackSourceServicesUnavailable'),{code:'InstalledSlackSourceServicesUnavailable'})) as Services;
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
  }))) as DeclarationPorts;
  const policy=services('sourceReaderImplementationProfile',{installation,sourceInitialization,
    metadataResponses:1,originUnits:siteProfile.apiOrigin.length});
  if(limits.maxDeclarationBytes>policy.maxDeclarationBytes||limits.maxDeclarationNodes>policy.maxDeclarationNodes){
    fail('InstalledSlackImplementationBoundsExceeded');
  }
  const columnCount=Math.max(...(['slackUserListColumnNames','slackChannelListColumnNames','slackMessageColumnNames'] as const)
    .map(name=>Reflect.apply(declarationPorts[name],provider,[]).length));
  const selected=slackReaderSelection(limits,columnCount,policy);
  const capacity=Reflect.apply(capacityPort,moon,[
    installedJsonSourceReaderLimitNames.map(name=>selected.limits[name]),columnCount,limits.maxSecretBytes,limits.maxPages]);
  if(capacity===undefined||capacity===null)fail('InstalledSourceReaderCapacityUnavailable');
  const readSequenceConstruction=Object.freeze({capacity,originalLimits:limits,sequences:selected.sequences,maxRequestBytes:2});
  const implementation=services('sourceReaderImplementation',{installation,sourceInitialization,
    limits:selected.limits,columnCount,readSequenceConstruction});
  const views=([['users','slack_users','slackUserListSchemaWire','slackUserListRelationFactsWire'],
    ['channels','slack_channels','slackChannelListSchemaWire','slackChannelListRelationFactsWire'],
    ['messages','slack_messages','slackMessageSchemaWire','slackMessageRelationFactsWire']] as const).map(
    ([resource,resource_kind,schema,facts])=>{
      const wire=checked(Reflect.apply(declarationPorts[schema],provider,[limits.maxDeclarationBytes,
        limits.maxDeclarationNodes,limits.maxDepth])) as string;
      return {resource,resource_kind,schema_wire:wire,schema_cid:sha(wire),
        facts_wire:Reflect.apply(declarationPorts[facts],provider,[])};
    });
  const{declaration,declared,environment}=Reflect.apply(prepareDeclaration,sourceInitialization,[views,undefined]);
  const connection=`slack:${installed.connectorId}`;
  const target=(selected: string, fields: readonly string[])=>Object.freeze({version:selected==='users'
    ?'actql-installed-slack-users-target/0.1':selected==='channels'
      ?'actql-installed-slack-channels-target/0.1':'actql-installed-slack-messages-target/0.1',
    apiOrigin:siteProfile.apiOrigin,workspaceId:installed.workspaceId,workspaceBytesCid:binding.workspaceBytesCid,
    resource:selected,fields:Object.freeze([...fields])});
  const admitsApprovalTarget=(value: Readonly<{workspaceId?: unknown; fields?: unknown}> | null | undefined, selected: string)=>declared.views.some(view=>view.resource===selected)&&value?.workspaceId===installed.workspaceId&&
    Array.isArray(value?.fields)&&new Set(value.fields).size===value.fields.length&&
    value.fields.every(name=>declared.views.find(view=>view.resource===selected)!.fields.includes(name))&&
    canonicalJson(value)===canonicalJson(target(selected,value.fields));
  let opened: Opened | undefined,providerReader: Reader | undefined;
  try{
    opened=await services('openRowSite',{installation,sourceInitialization,
      profile:Object.freeze({...siteProfile,resourceOrigin:siteProfile.apiOrigin}),
      accountConfiguration:installed.accountConfigurationWire,connection,ca,
      admitsApprovalTarget,responseHeaders:[],resolveSecret,runAcquisitionLimits:implementation.runAcquisitionLimits});
    const{authorization,site}=opened;
    providerReader=services('createSourceReader',{installation,sourceInitialization,implementation,site,
      prepareReadSequence({resource,columns}: Selection,applySynchronousProjection: SourceSequence[1]){
        return prepareSlackSourceReadSequence({moon:provider,workspaceId:installed.workspaceId,
          resource,names:columns,limits},applySynchronousProjection);
      }});
    if(providerReader.capacity!==implementation.capacity)fail('InstalledSlackReaderImplementationMismatch');
    return await createInstalledRowSource({moon:moon!,declaration,declared,environment,environmentWire:environment.wire,
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
