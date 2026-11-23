// Installation and transport adaptation. The existing Catalog and RowRun own
// declaration meaning, original acquisition, checked cells and capture.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {createInstalledRowSource} from '../../../host-node/installed-row-source.mjs';
import {captureInstalledSourceServices} from '../../../host-node/installed-host-services.mjs';
import {prepareCalendarListPages,CALENDAR_LIST_OPERATION} from '../site/calendar-list-read.mjs';
import type {CalendarListBindings, CalendarListLimits, CalendarListProjection} from '../site/calendar-list-read.mjs';
import type {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';

export const INSTALLED_CALENDAR_SOURCE_VERSION='actql-installed-calendar-source/0.1';
export const INSTALLED_CALENDAR_SITE_VERSION='actql-installed-calendar-site/0.1';
const registration='calendar',revision='calendar/0.1',resource='calendars';
const profileKeys=['version','connectorId','siteProfilePath','accountConfigurationWire','limits'];
const siteKeys=['version','apiOrigin','credentialAuthorityId','credentialKeyId','credentialPrivateKeyPath',
  'environment','journalRoot','namespaceId','siteGeneration','siteKey'] as const;
const limitKeys=['maxResponseBytes','maxNodes','maxDepth','maxPages','maxRows','maxRequests','perPage',
  'maxCursorUnits','maxValueNodes','maxValueTextBytes','maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth',
  'maxDeclarationBytes','maxDeclarationNodes','maxSecretBytes','maxCaBytes'] as const;
const providerNames=['calendarProjectCalendarList','calendarListRowsWire','calendarListMetadataJson',
  'calendarListColumnNames','calendarListSchemaWire','calendarListRelationFactsWire'] as const;
type Limits = CalendarListLimits & Readonly<Record<typeof limitKeys[number], number>>;
type Site = Readonly<Record<Exclude<typeof siteKeys[number], 'siteGeneration'>, string> &
  {siteGeneration: number; caPath?: string}>;
type Profile = Readonly<{version: typeof INSTALLED_CALENDAR_SOURCE_VERSION; connectorId: string;
  siteProfilePath: string; accountConfigurationWire: string; limits: Limits}>;
type Provider = CalendarListBindings & Readonly<{
  calendarListSchemaWire(maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  calendarListRelationFactsWire(): string;
}>;
type RowSourceInput = Parameters<typeof createInstalledRowSource>[0];
type ProviderReader = ReturnType<typeof createInstalledCredentialSourceReader>;
type Prepared = Readonly<{declaration: unknown; declared: RowSourceInput['declared'] &
  Readonly<{views: readonly Readonly<{fields: readonly string[]}>[]}>; environment: Readonly<{wire: string}>}>;
type ReaderPolicy = Readonly<Record<'pageSize' | 'maxTotalRows' | 'maxTotalResponseBytes' |
  'maxCursorBytes' | 'maxTargetBytes' | 'maxDeclarationBytes' | 'maxDeclarationNodes', number>>;
type Implementation = Readonly<{capacity: unknown; runAcquisitionLimits: unknown}>;
type Opened = Readonly<{site: RowSourceInput['site']; authorization: RowSourceInput['authorization'] &
  Readonly<{context: Readonly<{contextCid: string}>}>}>;
type Services = {
  (method: 'sourceReaderImplementationProfile', options: Readonly<Record<string, unknown>>): ReaderPolicy;
  (method: 'sourceReaderImplementation', options: Readonly<Record<string, unknown>>): Implementation;
  (method: 'openRowSite', options: Readonly<Record<string, unknown>>): Promise<Opened>;
  (method: 'createSourceReader', options: Readonly<Record<string, unknown>>): ProviderReader;
};
type LoadOptions = Readonly<{moon?: RowSourceInput['moon']; providerMoon?: Partial<Provider>;
  runtimeBundleCid?: string; resolveSecret?: unknown; configurationReader?: unknown;
  sourceInitialization?: unknown; installationServices?: unknown; installation?: unknown}>;
type PageSelection = Readonly<{resource: string; columns: readonly string[]}>;
type CandidateTarget = Readonly<{fields?: unknown}> | null | undefined;

const fail: (code: string) => never = code=>{throw Object.assign(new Error(code),{code});};
const text=(value: unknown): value is string=>typeof value==='string'&&value.length>0&&value.isWellFormed()&&!/[\u0000-\u001f\u007f]/u.test(value);
const absolute=(value: unknown): value is string=>text(value)&&isAbsolute(value);
const positive=(value: unknown): value is number=>Number.isSafeInteger(value)&&(value as number)>0&&(value as number)<2147483647;
const sha=(bytes: string | Buffer)=>`sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const cid=(value: unknown)=>sha(canonicalJson(value));
function closedData<Key extends string>(value: unknown,keys: readonly Key[],code: string){
  if(value===null||typeof value!=='object'||Array.isArray(value))fail(code);
  const descriptors=Object.getOwnPropertyDescriptors(value),names=Reflect.ownKeys(descriptors);
  if(names.length!==keys.length||names.some(name=>!(keys as readonly PropertyKey[]).includes(name)))fail(code);
  return Object.fromEntries(keys.map(name=>{
    const descriptor=descriptors[name];
    if(!descriptor?.enumerable||!Object.hasOwn(descriptor,'value'))fail(code);
    return[name,descriptor.value];
  })) as Record<Key, unknown>;
}

export function checkInstalledCalendarSourceProfile(profile: unknown){
  const code='InvalidInstalledCalendarSourceProfile',selected=closedData(profile,profileKeys,code);
  const limits=closedData(selected.limits,limitKeys,code);
  if(selected.version!==INSTALLED_CALENDAR_SOURCE_VERSION||!text(selected.connectorId)||
    !absolute(selected.siteProfilePath)||typeof selected.accountConfigurationWire!=='string'||
    !limitKeys.every(key=>positive(limits[key]))||(limits as Limits).perPage>250||(limits as Limits).maxPages>(limits as Limits).maxRequests)fail(code);
  return Object.freeze({...selected,limits:Object.freeze(limits)}) as Profile;
}

function checkSite(site: unknown){
  const code='InvalidInstalledCalendarSite',hasCa=Object.hasOwn(site??{},'caPath');
  const selected=closedData(site,[...siteKeys,...(hasCa?['caPath'] as const:[])],code);let origin;
  try{origin=new URL(selected.apiOrigin as string);}catch{/* Closed rejection below. */}
  if(selected.version!==INSTALLED_CALENDAR_SITE_VERSION||origin?.protocol!=='https:'||
    origin.origin!==selected.apiOrigin||
    !['credentialAuthorityId','credentialKeyId','environment','namespaceId','siteKey'].every(key=>text(selected[key as keyof Site]))||
    !absolute(selected.credentialPrivateKeyPath)||!absolute(selected.journalRoot)||
    !Number.isSafeInteger(selected.siteGeneration)||(selected.siteGeneration as number)<0||
    (hasCa&&!absolute(selected.caPath)))fail(code);
  return Object.freeze(selected) as Site;
}

async function readInputs(profile: unknown,configurationReader: unknown,readJson?: unknown){
  const installed=checkInstalledCalendarSourceProfile(profile);
  const reads=captureConfigurationReaders(configurationReader,readJson,
    ()=>fail('InstalledCalendarConfigurationReaderUnavailable'));
  const site=checkSite(await reads.readJson(installed.siteProfilePath));let ca;
  if(site.caPath!==undefined){
    const pem=await reads.readText(site.caPath,{maxBytes:installed.limits.maxCaBytes}) as string;
    if(/[^\x09\x0a\x0d\x20-\x7e]/u.test(pem)||!pem.includes('-----BEGIN CERTIFICATE-----')||
      !pem.includes('-----END CERTIFICATE-----'))fail('InvalidInstalledCalendarTlsAuthority');
    ca=Buffer.from(pem,'ascii');
  }
  return{installed,site,ca,binding:ca===undefined?{}:{caSha256:sha(ca)}};
}

export async function installedCalendarSourceIdentityParts(profile: {accountConfigurationWire: string},
  providerProfile: unknown,read?: unknown,_installation?: unknown,
  context?: Readonly<{configurationReader?: unknown}>){
  const{site,binding}=await readInputs(providerProfile,context?.configurationReader,read);
  return[{...profile,accountConfigurationWire:JSON.parse(profile.accountConfigurationWire)},site,binding];
}

function captureProvider(provider: Partial<Provider> | undefined){
  return Object.freeze(Object.fromEntries(providerNames.map(name=>{
    const method=provider?.[name];if(typeof method!=='function')fail('InstalledCalendarProviderUnavailable');
    return[name,(...args: unknown[])=>Reflect.apply(method,provider,args)];
  }))) as Provider;
}

// The selected connector owns its complete profile projection. These are the
// same original page/row/cursor bounds consumed by its page reader; the shared
// Host receives only its existing standard JSON recipe and original capacity.
function calendarReaderLimits(original: Limits, policy: ReaderPolicy){
  const total=BigInt(original.maxResponseBytes)*BigInt(original.maxPages);
  const cursor=4n*BigInt(original.maxCursorUnits);
  if(original.perPage>policy.pageSize||original.maxRows>policy.maxTotalRows||
    total>BigInt(policy.maxTotalResponseBytes)||cursor>BigInt(policy.maxCursorBytes)){
    fail('InstalledSourceReaderImplementationBoundsExceeded');
  }
  return Object.freeze({
    maxResponseBytes:original.maxResponseBytes,maxTotalResponseBytes:Number(total),
    maxNodes:original.maxNodes,maxDepth:original.maxDepth,
    maxRows:Math.min(original.perPage,original.maxRows),maxTotalRows:original.maxRows,
    maxPages:original.maxPages,pageSize:original.perPage,maxCursorBytes:Number(cursor),
    maxIdentityBytes:original.maxValueTextBytes,maxTargetBytes:policy.maxTargetBytes,
    maxValueNodes:original.maxValueNodes,maxValueTextBytes:original.maxValueTextBytes,
    maxRowsWireBytes:original.maxRowsWireBytes,maxRowsWireNodes:original.maxRowsWireNodes,
    maxRowsWireDepth:original.maxRowsWireDepth,maxSecretBytes:original.maxSecretBytes,
  });
}

export async function loadInstalledCalendarSource(profile: unknown,{moon,providerMoon,runtimeBundleCid,
  resolveSecret,configurationReader,sourceInitialization,installationServices,installation}: LoadOptions={}){
  if(!sourceInitialization||typeof sourceInitialization!=='object'||nodeTypes.isProxy(sourceInitialization)||
    installation===undefined)fail('CalendarSourceInitializationUnavailable');
  const constructor=Object.getOwnPropertyDescriptor(sourceInitialization,'prepareDeclaration');
  if(!constructor||!Object.hasOwn(constructor,'value')||typeof constructor.value!=='function'||
    nodeTypes.isAsyncFunction(constructor.value))fail('CalendarSourceInitializationUnavailable');
  const prepareDeclaration=constructor.value as
    (views: readonly unknown[], expectedCatalogCid: undefined) => Prepared;
  const services=captureInstalledSourceServices(installationServices,()=>Object.assign(
    new Error('InstalledCalendarSourceServicesUnavailable'),{code:'InstalledCalendarSourceServicesUnavailable'})) as Services;
  if(configurationReader===undefined||configurationReader===null)fail('InstalledCalendarConfigurationReaderUnavailable');
  if(typeof resolveSecret!=='function')fail('CalendarCredentialMaterialUnavailable');
  const provider=captureProvider(providerMoon);
  const{installed,site:siteProfile,ca,binding}=await readInputs(profile,configurationReader),{limits}=installed;
  const implementationProfile=services('sourceReaderImplementationProfile',{
    installation,sourceInitialization,metadataResponses:0,originUnits:siteProfile.apiOrigin.length});
  if(limits.maxDeclarationBytes>implementationProfile.maxDeclarationBytes||
    limits.maxDeclarationNodes>implementationProfile.maxDeclarationNodes)fail('InstalledCalendarImplementationBoundsExceeded');
  const implementation=services('sourceReaderImplementation',{
    installation,sourceInitialization,limits:calendarReaderLimits(limits,implementationProfile),
    columnCount:provider.calendarListColumnNames().length});
  const wire=checked(provider.calendarListSchemaWire(limits.maxDeclarationBytes,limits.maxDeclarationNodes,limits.maxDepth)) as string;
  const{declaration,declared,environment}=Reflect.apply(prepareDeclaration,sourceInitialization,
    [[{resource,resource_kind:'calendar_list',schema_wire:wire,schema_cid:sha(wire),
      facts_wire:provider.calendarListRelationFactsWire()}],undefined]);
  const connection=`calendar:${installed.connectorId}`;
  const target=(selected: string,fields: readonly string[])=>Object.freeze({version:'actql-installed-calendar-list-target/0.1',
    apiOrigin:siteProfile.apiOrigin,resource:selected,fields:Object.freeze([...fields])});
  const admitsApprovalTarget=(value: CandidateTarget,selected: string)=>selected===resource&&Array.isArray(value?.fields)&&
    new Set(value.fields).size===value.fields.length&&value.fields.every(name=>declared.views[0].fields.includes(name))&&
    canonicalJson(value)===canonicalJson(target(selected,value.fields));
  let opened: Opened | undefined,providerReader: ProviderReader | undefined;
  try{
    opened=await services('openRowSite',{installation,sourceInitialization,
      profile:Object.freeze({...siteProfile,resourceOrigin:siteProfile.apiOrigin}),
      accountConfiguration:installed.accountConfigurationWire,connection,ca,admitsApprovalTarget,
      responseHeaders:[],resolveSecret,runAcquisitionLimits:implementation.runAcquisitionLimits});
    const{authorization,site}=opened;
    providerReader=services('createSourceReader',{installation,sourceInitialization,implementation,site,
      operation:CALENDAR_LIST_OPERATION,
      preparePageReader({resource:selected,columns}: PageSelection,applySynchronousProjection: CalendarListProjection){
        if(selected!==resource)fail('UndeclaredCalendarResource');
        return prepareCalendarListPages({moon:provider,names:columns,limits},applySynchronousProjection);
      }});
    if(providerReader.capacity!==implementation.capacity)fail('InstalledCalendarReaderImplementationMismatch');
    return await createInstalledRowSource({moon: moon!,declaration,declared,environmentWire:environment.wire,environment,sourceInitialization,
      connectorId:installed.connectorId,connectorRegistration:registration,connectorRevision:revision,
      authorization,site,readOperation:CALENDAR_LIST_OPERATION,physicalTarget:target,
      bindingCid:cid({version:'actql-installed-calendar-list-binding/0.1',connectorId:installed.connectorId,
        connectorRegistration:registration,connectorRevision:revision,contextCid:authorization.context.contextCid,
        runtimeBundleCid,...binding,site:siteProfile}),
      limits:{maxPages:limits.maxPages,maxPageBytes:limits.maxResponseBytes,
        maxPageRows:Math.min(limits.perPage,limits.maxRows),maxCaptureRows:limits.maxRows},
      providerReader});
  }catch(cause){throw await retainInstalledHostInitializationFailure(cause,
    {sourceReader:providerReader,sourceProfile:opened?.site});}
}
