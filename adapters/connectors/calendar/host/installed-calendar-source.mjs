// Installation and transport adaptation. The existing Catalog and RowRun own
// declaration meaning, original acquisition, checked cells and capture.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {createInstalledRowSource,installRowSourceAuthorization,openRowSourceCredentialSite,
  rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {openHttpsCredentialBinding,closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {createCalendarListReader,CALENDAR_LIST_OPERATION} from '../site/calendar-list-read.mjs';

export const INSTALLED_CALENDAR_SOURCE_VERSION='actql-installed-calendar-source/0.1';
export const INSTALLED_CALENDAR_SITE_VERSION='actql-installed-calendar-site/0.1';
const registration='calendar',revision='calendar/0.1',resource='calendars';
const profileKeys=['version','connectorId','siteProfilePath','accountConfigurationWire','limits'];
const siteKeys=['version','apiOrigin','credentialAuthorityId','credentialKeyId','credentialPrivateKeyPath',
  'environment','journalRoot','namespaceId','siteGeneration','siteKey'];
const limitKeys=['maxResponseBytes','maxNodes','maxDepth','maxPages','maxRows','maxRequests','perPage',
  'maxCursorUnits','maxValueNodes','maxValueTextBytes','maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth',
  'maxDeclarationBytes','maxDeclarationNodes','maxSecretBytes','maxCaBytes'];
const providerNames=['calendarProjectCalendarList','calendarListRowsWire','calendarListMetadataJson',
  'calendarListColumnNames','calendarListSchemaWire','calendarListRelationFactsWire'];
const fail=code=>{throw Object.assign(new Error(code),{code});};
const text=value=>typeof value==='string'&&value.length>0&&value.isWellFormed()&&!/[\u0000-\u001f\u007f]/u.test(value);
const absolute=value=>text(value)&&isAbsolute(value);
const positive=value=>Number.isSafeInteger(value)&&value>0&&value<2147483647;
const sha=bytes=>`sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const cid=value=>sha(canonicalJson(value));
function closedData(value,keys,code){
  if(value===null||typeof value!=='object'||Array.isArray(value))fail(code);
  const descriptors=Object.getOwnPropertyDescriptors(value),names=Reflect.ownKeys(descriptors);
  if(names.length!==keys.length||names.some(name=>!keys.includes(name)))fail(code);
  return Object.fromEntries(keys.map(name=>{
    const descriptor=descriptors[name];
    if(!descriptor?.enumerable||!Object.hasOwn(descriptor,'value'))fail(code);
    return[name,descriptor.value];
  }));
}

export function checkInstalledCalendarSourceProfile(profile){
  const code='InvalidInstalledCalendarSourceProfile',selected=closedData(profile,profileKeys,code);
  const limits=closedData(selected.limits,limitKeys,code);
  if(selected.version!==INSTALLED_CALENDAR_SOURCE_VERSION||!text(selected.connectorId)||
    !absolute(selected.siteProfilePath)||typeof selected.accountConfigurationWire!=='string'||
    !limitKeys.every(key=>positive(limits[key]))||limits.perPage>250||limits.maxPages>limits.maxRequests)fail(code);
  return Object.freeze({...selected,limits:Object.freeze(limits)});
}

function checkSite(site){
  const code='InvalidInstalledCalendarSite',hasCa=Object.hasOwn(site??{},'caPath');
  const selected=closedData(site,[...siteKeys,...(hasCa?['caPath']:[])],code);let origin;
  try{origin=new URL(selected.apiOrigin);}catch{/* Closed rejection below. */}
  if(selected.version!==INSTALLED_CALENDAR_SITE_VERSION||origin?.protocol!=='https:'||
    origin.origin!==selected.apiOrigin||
    !['credentialAuthorityId','credentialKeyId','environment','namespaceId','siteKey'].every(key=>text(selected[key]))||
    !absolute(selected.credentialPrivateKeyPath)||!absolute(selected.journalRoot)||
    !Number.isSafeInteger(selected.siteGeneration)||selected.siteGeneration<0||
    (hasCa&&!absolute(selected.caPath)))fail(code);
  return Object.freeze(selected);
}

async function readInputs(profile,configurationReader,readJson){
  const installed=checkInstalledCalendarSourceProfile(profile);
  const reads=captureConfigurationReaders(configurationReader,readJson,
    ()=>fail('InstalledCalendarConfigurationReaderUnavailable'));
  const site=checkSite(await reads.readJson(installed.siteProfilePath));let ca;
  if(site.caPath!==undefined){
    const pem=await reads.readText(site.caPath,{maxBytes:installed.limits.maxCaBytes});
    if(/[^\x09\x0a\x0d\x20-\x7e]/u.test(pem)||!pem.includes('-----BEGIN CERTIFICATE-----')||
      !pem.includes('-----END CERTIFICATE-----'))fail('InvalidInstalledCalendarTlsAuthority');
    ca=Buffer.from(pem,'ascii');
  }
  return{installed,site,ca,binding:ca===undefined?{}:{caSha256:sha(ca)}};
}

export async function installedCalendarSourceIdentityParts(profile,providerProfile,read,_installation,context){
  const{site,binding}=await readInputs(providerProfile,context?.configurationReader,read);
  return[{...profile,accountConfigurationWire:JSON.parse(profile.accountConfigurationWire)},site,binding];
}

function captureProvider(provider){
  return Object.freeze(Object.fromEntries(providerNames.map(name=>{
    const method=provider?.[name];if(typeof method!=='function')fail('InstalledCalendarProviderUnavailable');
    return[name,(...args)=>Reflect.apply(method,provider,args)];
  })));
}

// This factory owns the native binding it opens. The private list reader only
// borrows it. Copied JS rows/observations do not become native cleanup duties;
// their semantic ownership remains with the same original RowRun and caller.
function originalReaderFactory({provider,site,installed,capacity}){
  const credential=site.credential,callResource=site.callResource;
  return Object.freeze({capacity,prepare(options){
    const verify=options.verifyRead,authorize=options.authorizationFor,
      charge=options.chargePage,consume=options.consumePage;
    const columns=Object.freeze([...options.columns]),stop=new AbortController();
    const signal=options.signal===undefined?stop.signal:AbortSignal.any([options.signal,stop.signal]);
    let phase='ready',child,childStop,childObserve,binding,closed=false,originalFailure,transportFailure;
    const closeTransport=()=>{
      if(binding!==undefined&&!closed)closed=closeHttpsCredentialBinding(binding)==='closed';
    };
    const assertCurrent=async()=>{signal.throwIfAborted();await Reflect.apply(verify,options,[]);signal.throwIfAborted();};
    const handle=Object.freeze({
      async read(){
        if(this!==handle)fail('ForeignInstalledCalendarReader');
        if(phase!=='ready')fail('InstalledCalendarReaderAlreadyStarted');
        phase='reading';
        try{
          await assertCurrent();
          const original=await Reflect.apply(authorize,options,[0]);await assertCurrent();
          binding=openHttpsCredentialBinding({...credential,scope:original.scope,maxSecretBytes:installed.limits.maxSecretBytes});
          child=createCalendarListReader({moon:provider,names:columns,initialAuthorization:original,
            credential:{...credential,binding},authorizationFor:async({index})=>{
              if(index===0)return original;
              const next=await Reflect.apply(authorize,options,[index]);await assertCurrent();return next;
            },current:async operation=>{
              if(operation!==CALENDAR_LIST_OPERATION)fail('ForeignInstalledCalendarRead');return assertCurrent();
            },chargeResponse:body=>Reflect.apply(charge,options,[body]),
            consumePage:(rows,ticket)=>Reflect.apply(consume,options,[rows,ticket]),
            limits:installed.limits,signal,callResource:(...args)=>Reflect.apply(callResource,site,args)});
          const read=child.read;childStop=child.requestStop;childObserve=child.observe;
          const result=await Reflect.apply(read,child,[]);phase='succeeded';return result;
        }catch(cause){phase='failed';originalFailure=cause;throw cause;}
        finally{
          try{closeTransport();}catch(cause){transportFailure=cause;if(originalFailure===undefined)throw cause;}
        }
      },
      requestStop(reason){
        if(this!==handle)fail('ForeignInstalledCalendarReader');
        stop.abort(reason);if(childStop!==undefined)Reflect.apply(childStop,child,[reason]);closeTransport();
      },
      observe(){
        if(this!==handle)fail('ForeignInstalledCalendarReader');
        return Object.freeze({phase,transportClosed:binding===undefined||closed,
          transportFailure:transportFailure!==undefined,
          child:childObserve===undefined?undefined:Reflect.apply(childObserve,child,[]),
          // The common session separately waits for the original read/stop.
          // Only this acquired binding's actual close can acknowledge it.
          cleanupConfirmed:phase!=='reading'&&(binding===undefined||closed)});
      },
    });return handle;
  }});
}

export async function loadInstalledCalendarSource(profile,{root,principalId,moon,providerMoon,
  baseEnvironmentWire,runtimeBundleCid,resolveSecret,readerCapacity,configurationReader}={}){
  if(readerCapacity===undefined||readerCapacity===null)fail('CalendarReaderCapacityUnavailable');
  if(typeof resolveSecret!=='function')fail('CalendarCredentialMaterialUnavailable');
  const provider=captureProvider(providerMoon);
  const{installed,site:siteProfile,ca,binding}=await readInputs(profile,configurationReader),{limits}=installed;
  const wire=checked(provider.calendarListSchemaWire(limits.maxDeclarationBytes,limits.maxDeclarationNodes,limits.maxDepth));
  const declaration=checked(moon.clientProgramRowSourceRestoreRelationDeclaration(installed.connectorId,
    registration,revision,JSON.stringify({views:[{resource,resource_kind:'calendar_list',schema_wire:wire,
      schema_cid:sha(wire),facts_wire:provider.calendarListRelationFactsWire()}]}),undefined));
  const declared=JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment=rowSourceCheckEnvironment(baseEnvironmentWire,declared);
  const authorization=await installRowSourceAuthorization({root,principalId,connectorRegistration:registration,
    accountConfiguration:installed.accountConfigurationWire});
  const connection=`calendar:${installed.connectorId}`;
  const target=(selected,fields)=>Object.freeze({version:'actql-installed-calendar-list-target/0.1',
    apiOrigin:siteProfile.apiOrigin,resource:selected,fields:Object.freeze([...fields])});
  const admitsApprovalTarget=(value,selected)=>selected===resource&&Array.isArray(value?.fields)&&
    new Set(value.fields).size===value.fields.length&&value.fields.every(name=>declared.views[0].fields.includes(name))&&
    canonicalJson(value)===canonicalJson(target(selected,value.fields));
  const site=await openRowSourceCredentialSite({profile:{...siteProfile,resourceOrigin:siteProfile.apiOrigin},
    principalId,authorization,connection,connectorRegistration:registration,connectorRevision:revision,
    runtimeBundleCid,commonMoon:moon,ca,admitsApprovalTarget,responseHeaders:[],resolveSecret});
  try{
    return await createInstalledRowSource({moon,declaration,declared,environmentWire:environment.wire,
      connectorId:installed.connectorId,connectorRegistration:registration,connectorRevision:revision,
      authorization,site,readOperation:CALENDAR_LIST_OPERATION,physicalTarget:target,
      bindingCid:cid({version:'actql-installed-calendar-list-binding/0.1',connectorId:installed.connectorId,
        connectorRegistration:registration,connectorRevision:revision,contextCid:authorization.context.contextCid,
        runtimeBundleCid,...binding,site:siteProfile}),
      limits:{maxPages:limits.maxPages,maxPageBytes:limits.maxResponseBytes,
        maxPageRows:Math.min(limits.perPage,limits.maxRows),maxCaptureRows:limits.maxRows},
      providerReader:originalReaderFactory({provider,site,installed,capacity:readerCapacity}),
      readPages(){fail('InstalledCalendarLegacyReaderUnavailable');}});
  }catch(cause){throw await retainInstalledHostInitializationFailure(cause,{sourceProfile:site});}
}
