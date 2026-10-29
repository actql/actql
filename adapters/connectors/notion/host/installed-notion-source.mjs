// Installation metadata and physical adaptation only. Common retains the
// checked declaration, acquisition, planner, Ledger, RowRun and capture.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {createInstalledRowSource,installRowSourceAuthorization,openRowSourceCredentialSite,
  rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';
import {prepareNotionUserListPages,NOTION_USER_LIST_OPERATION} from '../site/user-list-read.mjs';

export const INSTALLED_NOTION_SOURCE_VERSION='actql-installed-notion-source/0.1';
export const INSTALLED_NOTION_SITE_VERSION='actql-installed-notion-site/0.1';
const registration='notion',revision='notion/0.1',resource='users';
const profileKeys=['version','connectorId','siteProfilePath','accountConfigurationWire','limits'];
const siteKeys=['version','apiOrigin','credentialAuthorityId','credentialKeyId','credentialPrivateKeyPath',
  'environment','journalRoot','namespaceId','siteGeneration','siteKey'];
const readLimitKeys=['maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth','maxRows','maxTotalRows','maxPages','pageSize','maxCursorBytes','maxIdentityBytes','maxTargetBytes',
  'maxValueNodes','maxValueTextBytes','maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'];
const limitKeys=[...readLimitKeys,'maxDeclarationBytes','maxDeclarationNodes','maxSecretBytes','maxCaBytes'];
const fail=code=>{throw Object.assign(new Error(code),{code});};
const text=value=>typeof value==='string'&&value.length>0&&value.isWellFormed()&&!/[\u0000-\u001f\u007f]/u.test(value);
const absolute=value=>text(value)&&isAbsolute(value);
const positive=value=>Number.isSafeInteger(value)&&value>0&&value<=2147483647;
const closed=(value,keys)=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&
  Object.keys(value).sort().join('\0')===[...keys].sort().join('\0');
const sha=bytes=>`sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const cid=value=>sha(canonicalJson(value));

export function checkInstalledNotionSourceProfile(profile){
  if(!closed(profile,profileKeys)||profile.version!==INSTALLED_NOTION_SOURCE_VERSION||
      !text(profile.connectorId)||
      !absolute(profile.siteProfilePath)||typeof profile.accountConfigurationWire!=='string'||
      !closed(profile.limits,limitKeys)||!limitKeys.every(key=>positive(profile.limits[key]))||profile.limits.pageSize>100)fail('InvalidInstalledNotionSourceProfile');
  return Object.freeze({...profile,limits:Object.freeze({...profile.limits})});
}

function checkSite(site){
  const {caPath,...rest}=site??{};let origin;
  try{origin=new URL(rest.apiOrigin);}catch{/* Closed rejection below. */}
  if(!closed(rest,siteKeys)||rest.version!==INSTALLED_NOTION_SITE_VERSION||
      origin?.protocol!=='https:'||origin.origin!==rest.apiOrigin||
      !['credentialAuthorityId','credentialKeyId','environment','namespaceId','siteKey'].every(key=>text(rest[key]))||
      !absolute(rest.credentialPrivateKeyPath)||!absolute(rest.journalRoot)||
      !Number.isSafeInteger(rest.siteGeneration)||rest.siteGeneration<0||
      (caPath!==undefined&&!absolute(caPath)))fail('InvalidInstalledNotionSite');
  return Object.freeze({...rest,...(caPath===undefined?{}:{caPath})});
}

async function readInputs(profile,configurationReader,readJson){
  const installed=checkInstalledNotionSourceProfile(profile);
  const reads=captureConfigurationReaders(configurationReader,readJson,()=>fail('InstalledNotionConfigurationReaderUnavailable'));
  const site=checkSite(await reads.readJson(installed.siteProfilePath));
  let ca;
  if(site.caPath!==undefined){
    // This private Site accepts bounded PEM text, not an unbounded file read
    // or lenient UTF-8 identity. Non-ASCII/replacement input is refused rather
    // than re-encoding different authority bytes before hashing/native TLS.
    const pem=await reads.readText(site.caPath,{maxBytes:installed.limits.maxCaBytes});
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

export async function installedNotionSourceIdentityParts(profile,providerProfile,read,_installation,context){
  const{site,binding}=await readInputs(providerProfile,context?.configurationReader,read);
  return[{...profile,accountConfigurationWire:JSON.parse(profile.accountConfigurationWire)},site,binding];
}

export async function loadInstalledNotionSource(profile,{root,principalId,moon,providerMoon:provider,
  baseEnvironmentWire,runtimeBundleCid,resolveSecret,readerCapacity,configurationReader}={}){
  const{installed,site:siteProfile,ca,binding}=await readInputs(profile,configurationReader);
  // The existing trusted installer must supply its same-runtime declaration.
  // Public profile amounts, page/transfer limits and fixed spare constants are
  // not a full reader retained/workspace supplier. Never choose legacy readPages.
  if(readerCapacity===undefined||readerCapacity===null)fail('NotionReaderCapacityUnavailable');
  if(typeof resolveSecret!=='function')fail('NotionCredentialMaterialUnavailable');
  const{limits}=installed;
  const wire=checked(provider.notionUserListSchemaWire(limits.maxDeclarationBytes,
    limits.maxDeclarationNodes,limits.maxDepth));
  const declaration=checked(moon.clientProgramRowSourceRestoreRelationDeclaration(installed.connectorId,
    registration,revision,JSON.stringify({views:[{resource,resource_kind:'notion_users',schema_wire:wire,
      schema_cid:sha(wire),facts_wire:provider.notionUserListRelationFactsWire()}]}),undefined));
  const declared=JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment=rowSourceCheckEnvironment(baseEnvironmentWire,declared);
  const authorization=await installRowSourceAuthorization({root,principalId,connectorRegistration:registration,
    accountConfiguration:installed.accountConfigurationWire});
  const connection=`notion:${installed.connectorId}`;
  const target=(selected,fields)=>Object.freeze({version:'actql-installed-notion-user-target/0.1',
    apiOrigin:siteProfile.apiOrigin,resource:selected,fields:Object.freeze([...fields])});
  const admitsApprovalTarget=(value,selected)=>selected===resource&&
    Array.isArray(value?.fields)&&new Set(value.fields).size===value.fields.length&&
    value.fields.every(name=>declared.views[0].fields.includes(name))&&
    canonicalJson(value)===canonicalJson(target(selected,value.fields));
  const site=await openRowSourceCredentialSite({profile:{...siteProfile,resourceOrigin:siteProfile.apiOrigin},
    principalId,authorization,connection,connectorRegistration:registration,connectorRevision:revision,
    runtimeBundleCid,commonMoon:moon,ca,admitsApprovalTarget,responseHeaders:[],resolveSecret});
  let providerReader;
  try{
    providerReader=createInstalledCredentialSourceReader({capacity:readerCapacity,site,
      operation:NOTION_USER_LIST_OPERATION,maxResponses:limits.maxPages,
      maxResponseBytes:limits.maxResponseBytes,maxSecretBytes:limits.maxSecretBytes,
      preparePageReader({resource:selected,columns},applySynchronousProjection){
        if(selected!==resource)fail('UndeclaredNotionResource');
        return prepareNotionUserListPages({moon:provider,names:columns,limits},applySynchronousProjection);
      }});
    return await createInstalledRowSource({moon,declaration,declared,environmentWire:environment.wire,
      connectorId:installed.connectorId,connectorRegistration:registration,connectorRevision:revision,
      authorization,site,readOperation:NOTION_USER_LIST_OPERATION,physicalTarget:target,
      bindingCid:cid({version:'actql-installed-notion-user-binding/0.1',connectorId:installed.connectorId,
        connectorRegistration:registration,connectorRevision:revision,contextCid:authorization.context.contextCid,
        runtimeBundleCid,...binding,site:siteProfile}),
      limits:{maxPages:limits.maxPages,maxPageBytes:limits.maxResponseBytes,maxPageRows:limits.maxRows,maxCaptureRows:limits.maxTotalRows},
      providerReader});
  }catch(cause){throw await retainInstalledHostInitializationFailure(cause,
    {sourceReader:providerReader,sourceProfile:site});}
}
