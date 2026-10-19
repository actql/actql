// Installation metadata and physical adaptation only. Common retains the
// checked declaration, acquisition, planner, Ledger, RowRun and capture.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {readSourceProfileJson,readBoundedConfigurationText} from '../../../host-node/source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {createInstalledRowSource,installRowSourceAuthorization,openRowSourceCredentialSite,
  rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {openHttpsCredentialBinding,closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {createGmailLabelListReader,GMAIL_LABEL_LIST_OPERATION} from '../site/gmail-label-list-read.mjs';
import {createGmailThreadReaderFactory,checkGmailThreadReaderLimits} from './thread-reader.mjs';
import {GMAIL_THREAD_LIST_OPERATION} from '../site/gmail-thread-read.mjs';

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
const threadLimitKeys=['maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth','pageSize','maxPages',
  'maxThreads','maxMailboxBytes','maxTargetBytes','maxIdBytes','maxTokenBytes','maxMessages','maxLabels',
  'maxHeaders','maxHeaderUnits','maxCommentDepth','maxValueNodes','maxValueTextBytes',
  'maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth',...extraLimitKeys];
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

async function readInputs(profile){
  const installed=checkInstalledGmailSourceProfile(profile);
  const site=checkSite(await readSourceProfileJson(installed.siteProfilePath));
  let ca;
  if(site.caPath!==undefined){
    // This private Site accepts bounded PEM text, not an unbounded file read
    // or lenient UTF-8 identity. Non-ASCII/replacement input is refused rather
    // than re-encoding different authority bytes before hashing/native TLS.
    const pem=await readBoundedConfigurationText(site.caPath,{maxBytes:installed.limits.maxCaBytes});
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

export async function installedGmailSourceIdentityParts(profile,providerProfile){
  const{site,binding}=await readInputs(providerProfile);
  return[{...profile,accountConfigurationWire:JSON.parse(profile.accountConfigurationWire)},site,binding];
}

// A synchronous, I/O-free factory is required by the original RowRun caller.
// Its read obtains the already selected grant before constructing one child;
// every failure retains that same child/binding/Promise graph for recovery.
function originalReaderFactory({provider,site,installed,capacity}){
  return Object.freeze({capacity,prepare(options){
    const stop=new AbortController();
    const signal=options.signal===undefined?stop.signal:AbortSignal.any([options.signal,stop.signal]);
    let phase='ready',child,binding,closed=false,originalFailure,transportFailure;
    const closeTransport=()=>{if(binding!==undefined&&!closed)closed=closeHttpsCredentialBinding(binding)==='closed';};
    const handle=Object.freeze({
      async read(){
        if(this!==handle)fail('ForeignInstalledGmailReader');
        if(phase!=='ready')fail('InstalledGmailReaderAlreadyStarted');
        phase='reading';
        try{
          signal.throwIfAborted();await options.verifyRead();signal.throwIfAborted();
          const original=await options.authorizationFor(0);
          signal.throwIfAborted();await options.verifyRead();signal.throwIfAborted();
          binding=openHttpsCredentialBinding({...site.credential,scope:original.scope,
            maxSecretBytes:installed.limits.maxSecretBytes});
          child=createGmailLabelListReader({moon:provider,mailbox:installed.mailbox,names:options.columns,
            initialAuthorization:original,credential:{...site.credential,binding},
            authorizationFor:async({index})=>{if(index!==0)fail('ForeignInstalledGmailRead');return original;},
            current:async operation=>{if(operation!==GMAIL_LABEL_LIST_OPERATION)fail('ForeignInstalledGmailRead');
              return options.verifyRead();},
            chargeResponse:options.chargePage,consumePage:options.consumePage,
            limits:installed.limits,signal,callResource:site.callResource});
          const result=await child.read();phase='succeeded';return result;
        }catch(cause){phase='failed';originalFailure=cause;throw cause;}
        finally{
          try{closeTransport();}
          catch(cause){transportFailure=cause;if(originalFailure===undefined)throw cause;}
        }
      },
      requestStop(reason){
        if(this!==handle)fail('ForeignInstalledGmailReader');
        stop.abort(reason);child?.requestStop(reason);closeTransport();
      },
      observe(){
        if(this!==handle)fail('ForeignInstalledGmailReader');
        // Closing transport does not retire raw, row, callback, error or
        // Promise aliases. No transfer/retirement receipt is currently issued.
        return Object.freeze({phase,transportClosed:closed,transportFailure:transportFailure!==undefined,
          child:child?.observe(),cleanupConfirmed:false});
      },
    });
    return handle;
  }});
}

export async function loadInstalledGmailSource(profile,{root,principalId,moon,providerMoon:provider,
  baseEnvironmentWire,runtimeBundleCid,resolveSecret,readerCapacity}={}){
  const{installed,site:siteProfile,ca,binding}=await readInputs(profile);
  // The existing trusted installer must supply its same-runtime declaration.
  // Public profile amounts, page/transfer limits and fixed spare constants are
  // not a full reader retained/workspace supplier. Never choose legacy readPages.
  if(readerCapacity===undefined||readerCapacity===null)fail('GmailReaderCapacityUnavailable');
  if(typeof resolveSecret!=='function')fail('GmailCredentialMaterialUnavailable');
  const{limits}=installed,resource=installed.resource??'labels',threads=resource==='threads';
  const wire=checked(threads?provider.gmailThreadSchemaWire(limits.maxDeclarationBytes,
    limits.maxDeclarationNodes,limits.maxDepth):provider.gmailLabelListSchemaWire(limits.maxDeclarationBytes,
    limits.maxDeclarationNodes,limits.maxDepth));
  const declaration=checked(moon.clientProgramRowSourceRestoreRelationDeclaration(installed.connectorId,
    registration,revision,JSON.stringify({views:[{resource,resource_kind:threads?'gmail_threads':'gmail_labels',schema_wire:wire,
      schema_cid:sha(wire),facts_wire:threads?provider.gmailThreadRelationFactsWire():provider.gmailLabelListRelationFactsWire()}]}),undefined));
  const declared=JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment=rowSourceCheckEnvironment(baseEnvironmentWire,declared);
  const authorization=await installRowSourceAuthorization({root,principalId,connectorRegistration:registration,
    accountConfiguration:installed.accountConfigurationWire});
  const connection=`gmail:${installed.connectorId}`;
  const target=(selected,fields)=>Object.freeze({version:threads?'actql-installed-gmail-thread-target/0.1':'actql-installed-gmail-label-target/0.1',
    apiOrigin:siteProfile.apiOrigin,mailbox:installed.mailbox,mailboxBytesCid:binding.mailboxBytesCid,
    resource:selected,fields:Object.freeze([...fields])});
  const admitsApprovalTarget=(value,selected)=>selected===resource&&value?.mailbox===installed.mailbox&&
    Array.isArray(value?.fields)&&new Set(value.fields).size===value.fields.length&&
    value.fields.every(name=>declared.views[0].fields.includes(name))&&
    canonicalJson(value)===canonicalJson(target(selected,value.fields));
  const site=await openRowSourceCredentialSite({profile:{...siteProfile,resourceOrigin:siteProfile.apiOrigin},
    principalId,authorization,connection,connectorRegistration:registration,connectorRevision:revision,
    runtimeBundleCid,commonMoon:moon,ca,admitsApprovalTarget,responseHeaders:[],resolveSecret});
  try{
    // Every list and dependent get response is charged under the same RowRun.
    // The list grant remains bounded by the selected list-page limit, while
    // the existing factory obtains a separate operation grant for original gets.
    const maxExchanges=threads?limits.maxPages+limits.maxThreads:1;
    const originalIssueReadGrant=site.issueReadGrant;
    const readerSite=threads?Object.freeze({...site,issueReadGrant(input){
      if(input.operation!==GMAIL_THREAD_LIST_OPERATION)return Reflect.apply(originalIssueReadGrant,site,[input]);
      if(input.maxUses!==maxExchanges)fail('ForeignInstalledGmailThreadGrant');
      return Reflect.apply(originalIssueReadGrant,site,[{...input,maxUses:limits.maxPages}]);
    }}):site;
    return await createInstalledRowSource({moon,declaration,declared,environmentWire:environment.wire,
      connectorId:installed.connectorId,connectorRegistration:registration,connectorRevision:revision,
      authorization,site:readerSite,readOperation:threads?GMAIL_THREAD_LIST_OPERATION:GMAIL_LABEL_LIST_OPERATION,physicalTarget:target,
      bindingCid:cid({version:threads?'actql-installed-gmail-thread-binding/0.1':'actql-installed-gmail-label-binding/0.1',connectorId:installed.connectorId,
        connectorRegistration:registration,connectorRevision:revision,contextCid:authorization.context.contextCid,
        runtimeBundleCid,mailbox:installed.mailbox,...binding,site:siteProfile}),
      limits:{maxPages:maxExchanges,maxPageBytes:limits.maxResponseBytes,
        maxPageRows:threads?1:limits.maxRows,maxCaptureRows:threads?limits.maxThreads:limits.maxRows},
      providerReader:threads?createGmailThreadReaderFactory({moon:provider,site:readerSite,capacity:readerCapacity,
        mailbox:installed.mailbox,limits,maxSecretBytes:limits.maxSecretBytes})
        :originalReaderFactory({provider,site,installed,capacity:readerCapacity}),
      readPages(){fail('InstalledGmailLegacyReaderUnavailable');}});
  }catch(cause){throw await retainInstalledHostInitializationFailure(cause,{sourceProfile:site});}
}
