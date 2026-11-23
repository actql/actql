// Installation metadata and physical adaptation only. Common retains the
// checked declaration, acquisition, planner, Ledger, RowRun and capture.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {installFinitePageSource} from '../../../host-node/installed-finite-page-source.mjs';
import {createInstalledRowSource} from '../../../host-node/installed-row-source.mjs';
import {captureInstalledSourceServices} from '../../../host-node/installed-host-services.mjs';
import {prepareNotionUserListPages,NOTION_USER_LIST_OPERATION,NOTION_USER_LIST_REQUEST} from '../site/user-list-read.mjs';
import {captureRestReadOriginals,restReadOriginalControlUnits,restReadTransportConstructionUnits}
  from '../../../host-node/rest-read-original.mjs';
import {notionUserListReadWire} from '../site/user-list-read-wire.generated.mjs';
import type {RestReadOriginal} from '../../../host-node/rest-read-original.mjs';
import type {NotionCursorBindings, NotionPageLimits, NotionSynchronousProjection, NotionUserListBindings} from '../site/user-list-read.mjs';
import type {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';

export const INSTALLED_NOTION_SOURCE_VERSION='actql-installed-notion-source/0.1';
export const INSTALLED_NOTION_SITE_VERSION='actql-installed-notion-site/0.1';
const registration='notion',revision='notion/0.1',resource='users';
const profileKeys=['version','connectorId','siteProfilePath','accountConfigurationWire','limits'] as const;
const siteKeys=['version','apiOrigin','credentialAuthorityId','credentialKeyId','credentialPrivateKeyPath',
  'environment','journalRoot','namespaceId','siteGeneration','siteKey'] as const;
const readLimitKeys=['maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth','maxRows','maxTotalRows','maxPages','pageSize','maxCursorBytes','maxIdentityBytes','maxTargetBytes',
  'maxValueNodes','maxValueTextBytes','maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'] as const;
const limitKeys=[...readLimitKeys,'maxDeclarationBytes','maxDeclarationNodes','maxSecretBytes','maxCaBytes'] as const;
const providerNames=['notionUserListSchemaWire','notionUserListRelationFactsWire','notionUserListColumnNames',
  'notionUserListRowsWire','notionUserListMetadata','notionProjectUserList',
  'notionUserListPrepareIdentityProgress','notionUserListTrackPageIdentities'] as const;
type Limits = NotionPageLimits & Readonly<Record<typeof limitKeys[number], number>>;
type Site = Readonly<Record<Exclude<typeof siteKeys[number], 'siteGeneration'>, string> &
  {siteGeneration: number; caPath?: string}>;
type Profile = Readonly<{version: typeof INSTALLED_NOTION_SOURCE_VERSION; connectorId: string;
  siteProfilePath: string; accountConfigurationWire: string; limits: Limits}>;
type Provider = NotionUserListBindings & Readonly<{
  notionUserListSchemaWire(maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  notionUserListRelationFactsWire(): string;
}>;
type RowSourceInput = Parameters<typeof createInstalledRowSource>[0];
type Prepared = Readonly<{declaration: unknown; declared: RowSourceInput['declared'] &
  Readonly<{views: readonly Readonly<{fields: readonly string[]}>[]}>; environment: Readonly<{wire: string}>}>;
type Opened = Readonly<{site: RowSourceInput['site']; authorization: RowSourceInput['authorization'] &
  Readonly<{context: Readonly<{contextCid: string}>}>}>;
type Reader = ReturnType<typeof createInstalledCredentialSourceReader>;
type Implementation = Readonly<{capacity: unknown; runAcquisitionLimits: unknown}>;
type Services = {
  (method: 'sourceReaderImplementationProfile', input: Readonly<Record<string, unknown>>):
    Readonly<{maxDeclarationBytes: number; maxDeclarationNodes: number}>;
  (method: 'sourceReaderImplementation', input: Readonly<Record<string, unknown>>): Implementation;
  (method: 'openRowSite', input: Readonly<Record<string, unknown>>): Promise<Opened>;
  (method: 'createSourceReader', input: Readonly<Record<string, unknown>>): Reader;
};
type LoadOptions = Readonly<{moon?: RowSourceInput['moon'] & NotionCursorBindings; providerMoon?: Partial<Provider>;
  runtimeBundleCid?: string; resolveSecret?: unknown; configurationReader?: unknown;
  sourceInitialization?: unknown; installationServices?: unknown; installation?: unknown}>;
type Selection = Readonly<{resource: string; columns: readonly string[]}>;

const fail: (code: string) => never = code=>{throw Object.assign(new Error(code),{code});};
const text=(value: unknown): value is string=>typeof value==='string'&&value.length>0&&value.isWellFormed()&&!/[\u0000-\u001f\u007f]/u.test(value);
const absolute=(value: unknown): value is string=>text(value)&&isAbsolute(value);
const positive=(value: unknown): value is number=>Number.isSafeInteger(value)&&(value as number)>0&&(value as number)<=2147483647;
const closed=<Key extends string>(value: unknown,keys: readonly Key[]): value is Record<Key, unknown>=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&
  Object.keys(value).sort().join('\0')===[...keys].sort().join('\0');
const sha=(bytes: string | Buffer)=>`sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const cid=(value: unknown)=>sha(canonicalJson(value));

export function checkInstalledNotionSourceProfile(profile: unknown){
  if(!closed(profile,profileKeys)||profile.version!==INSTALLED_NOTION_SOURCE_VERSION||
      !text(profile.connectorId)||
      !absolute(profile.siteProfilePath)||typeof profile.accountConfigurationWire!=='string'||
      !closed(profile.limits,limitKeys)||!limitKeys.every(key=>positive((profile.limits as Limits)[key]))||(profile.limits as Limits).pageSize>100)fail('InvalidInstalledNotionSourceProfile');
  return Object.freeze({...profile,limits:Object.freeze({...profile.limits})}) as Profile;
}

function checkSite(site: Partial<Record<keyof Site, unknown>> | null | undefined){
  const {caPath,...rest}=site??{};let origin;
  try{origin=new URL(rest.apiOrigin as string);}catch{/* Closed rejection below. */}
  if(!closed(rest,siteKeys)||rest.version!==INSTALLED_NOTION_SITE_VERSION||
      origin?.protocol!=='https:'||origin.origin!==rest.apiOrigin||
      !['credentialAuthorityId','credentialKeyId','environment','namespaceId','siteKey'].every(key=>text(rest[key as keyof typeof rest]))||
      !absolute(rest.credentialPrivateKeyPath)||!absolute(rest.journalRoot)||
      !Number.isSafeInteger(rest.siteGeneration)||(rest.siteGeneration as number)<0||
      (caPath!==undefined&&!absolute(caPath)))fail('InvalidInstalledNotionSite');
  return Object.freeze({...rest,...(caPath===undefined?{}:{caPath})}) as Site;
}

async function readInputs(profile: unknown,configurationReader: unknown,readJson?: unknown){
  const installed=checkInstalledNotionSourceProfile(profile);
  const reads=captureConfigurationReaders(configurationReader,readJson,()=>fail('InstalledNotionConfigurationReaderUnavailable'));
  const site=checkSite(await reads.readJson(installed.siteProfilePath) as Parameters<typeof checkSite>[0]);
  let ca;
  if(site.caPath!==undefined){
    // This private Site accepts bounded PEM text, not an unbounded file read
    // or lenient UTF-8 identity. Non-ASCII/replacement input is refused rather
    // than re-encoding different authority bytes before hashing/native TLS.
    const pem=await reads.readText(site.caPath,{maxBytes:installed.limits.maxCaBytes}) as string;
    if(/[^\x09\x0a\x0d\x20-\x7e]/u.test(pem)||!pem.includes('-----BEGIN CERTIFICATE-----')||
        !pem.includes('-----END CERTIFICATE-----'))fail('InvalidInstalledNotionTlsAuthority');
    ca=Buffer.from(pem,'ascii');
  }
  // Retain exact selected String bytes outside configuration NFC canonicalization.
  // These hashes identify original DATA; they are not a Site or read grant.
  const binding={originalStringsCid:sha(JSON.stringify([installed.connectorId,
    installed.siteProfilePath,installed.accountConfigurationWire,
    ...siteKeys.map(name=>site[name]),...(site.caPath===undefined?[]:[site.caPath])])),
    ...(ca===undefined?{}:{caSha256:sha(ca)})};
  return{installed,site,ca,binding};
}

export async function installedNotionSourceIdentityParts(profile: {accountConfigurationWire: string},
  providerProfile: unknown,read?: unknown,_installation?: unknown,context?: Readonly<{configurationReader?: unknown}>){
  const{site,binding}=await readInputs(providerProfile,context?.configurationReader,read);
  return[{...profile,accountConfigurationWire:JSON.parse(profile.accountConfigurationWire)},site,binding];
}

function captureProvider(provider: Partial<Provider> | undefined){
  return Object.freeze(Object.fromEntries(providerNames.map(name=>{
    const method=provider?.[name];if(typeof method!=='function')fail('InstalledNotionProviderUnavailable');
    return[name,(...args: unknown[])=>Reflect.apply(method,provider,args)];
  }))) as Provider;
}

export async function loadInstalledNotionSource(profile: unknown,{moon,providerMoon,runtimeBundleCid,
  resolveSecret,configurationReader,sourceInitialization,installationServices,installation}: LoadOptions={}){
  if(!sourceInitialization||typeof sourceInitialization!=='object'||nodeTypes.isProxy(sourceInitialization)||
    !moon||typeof moon!=='object'||nodeTypes.isProxy(moon)||
    installation===undefined)fail('NotionSourceInitializationUnavailable');
  const constructor=Object.getOwnPropertyDescriptor(sourceInitialization,'prepareDeclaration');
  if(!constructor||!Object.hasOwn(constructor,'value')||typeof constructor.value!=='function'||
    nodeTypes.isAsyncFunction(constructor.value))fail('NotionSourceInitializationUnavailable');
  const prepareDeclaration=constructor.value as
    (views: readonly unknown[], expectedCatalogCid: undefined) => Prepared;
  const originals=captureRestReadOriginals(moon);
  const targetConstructor=Object.getOwnPropertyDescriptor(sourceInitialization,'prepareReadTarget');
  if(!targetConstructor||!Object.hasOwn(targetConstructor,'value')||typeof targetConstructor.value!=='function'||
      nodeTypes.isAsyncFunction(targetConstructor.value)) {
    fail('NotionSourceInitializationUnavailable');
  }
  const services=captureInstalledSourceServices(installationServices,()=>Object.assign(
    new Error('InstalledNotionSourceServicesUnavailable'),{code:'InstalledNotionSourceServicesUnavailable'})) as Services;
  if(configurationReader===undefined||configurationReader===null)fail('InstalledNotionConfigurationReaderUnavailable');
  if(typeof resolveSecret!=='function')fail('NotionCredentialMaterialUnavailable');
  const provider=captureProvider(providerMoon);
  const{installed,site:siteProfile,ca,binding}=await readInputs(profile,configurationReader);
  const{limits}=installed;
  const implementationProfile=services('sourceReaderImplementationProfile',{
    installation,sourceInitialization,metadataResponses:0,originUnits:siteProfile.apiOrigin.length});
  if(limits.maxDeclarationBytes>implementationProfile.maxDeclarationBytes||
    limits.maxDeclarationNodes>implementationProfile.maxDeclarationNodes)fail('InstalledNotionImplementationBoundsExceeded');
  const wire=checked(provider.notionUserListSchemaWire(limits.maxDeclarationBytes,
    limits.maxDeclarationNodes,limits.maxDepth)) as string;
  const{declaration,declared,environment}=Reflect.apply(prepareDeclaration,sourceInitialization,
    [[{resource,resource_kind:'notion_users',schema_wire:wire,schema_cid:sha(wire),
      facts_wire:provider.notionUserListRelationFactsWire()}],undefined]);
  const request=Reflect.apply(targetConstructor.value,sourceInitialization,[Object.freeze({
    capacity(){return originals.composeConstruction(restReadOriginalControlUnits(1),1,()=>originals.quote(
      notionUserListReadWire,NOTION_USER_LIST_REQUEST.pagination.parameter,limits));},
    project(){return originals.project(notionUserListReadWire,NOTION_USER_LIST_REQUEST.pagination.parameter,limits);},
  })]) as RestReadOriginal;
  const transportUnits=restReadTransportConstructionUnits(request);
  // Six captured Common methods and their namespace reference live alongside
  // the reader's existing fields. Cover the method capture vector, original
  // call vector, and result observation in the same request workspace.
  const cursorBindings=7n, captureVector=1n+6n, advanceCallVector=1n+6n;
  transportUnits[0]+=cursorBindings;
  transportUnits[3]+=cursorBindings+captureVector+advanceCallVector;
  const requestConstruction=Object.freeze({capacity:originals.requestCapacity(
    transportUnits,[request]),maxRequestBytes:limits.maxTargetBytes});
  const implementation=services('sourceReaderImplementation',{installation,sourceInitialization,
    limits:Object.fromEntries(([...readLimitKeys,'maxSecretBytes'] as const).map(name=>[name,limits[name]])),
    columnCount:provider.notionUserListColumnNames().length,cursorProgress:'codec-identities',requestConstruction});
  const connection=`notion:${installed.connectorId}`;
  const target=(selected: string,fields: readonly string[])=>Object.freeze({version:'actql-installed-notion-user-target/0.1',
    apiOrigin:siteProfile.apiOrigin,resource:selected,fields:Object.freeze([...fields])});
  const admitsApprovalTarget=(value: Readonly<{fields?: unknown}> | null | undefined,selected: string)=>selected===resource&&
    Array.isArray(value?.fields)&&new Set(value.fields).size===value.fields.length&&
    value.fields.every(name=>declared.views[0].fields.includes(name))&&
    canonicalJson(value)===canonicalJson(target(selected,value.fields));
  return installFinitePageSource(services,{installation,sourceInitialization,
      profile:Object.freeze({...siteProfile,resourceOrigin:siteProfile.apiOrigin}),
      accountConfiguration:installed.accountConfigurationWire,connection,ca,admitsApprovalTarget,
      responseHeaders:[],resolveSecret,runAcquisitionLimits:implementation.runAcquisitionLimits},
    implementation,NOTION_USER_LIST_OPERATION,
    function preparePageReader({resource:selected,columns}: Selection,applySynchronousProjection: NotionSynchronousProjection){
      if(selected!==resource)fail('UndeclaredNotionResource');
      return prepareNotionUserListPages({moon:provider,common:moon,names:columns,limits,request},applySynchronousProjection);
    },
    'InstalledNotionReaderImplementationMismatch',
    function publish({authorization,site}: Opened,providerReader: Reader){
      return createInstalledRowSource({moon,declaration,declared,environmentWire:environment.wire,environment,sourceInitialization,
      connectorId:installed.connectorId,connectorRegistration:registration,connectorRevision:revision,
      authorization,site,readOperation:NOTION_USER_LIST_OPERATION,physicalTarget:target,
      bindingCid:cid({version:'actql-installed-notion-user-binding/0.1',connectorId:installed.connectorId,
        connectorRegistration:registration,connectorRevision:revision,contextCid:authorization.context.contextCid,
        runtimeBundleCid,...binding,site:siteProfile}),
      limits:{maxPages:limits.maxPages,maxPageBytes:limits.maxResponseBytes,maxPageRows:limits.maxRows,maxCaptureRows:limits.maxTotalRows},
      providerReader});
    });
}
