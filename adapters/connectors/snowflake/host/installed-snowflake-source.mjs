// The standard Host selects this installation from the connector manifest.
// Metadata is an explicit installed snapshot, not permission or a fresh read.
// Original SQL/row/credential/capture meanings stay with their existing Owners.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {readFile} from 'node:fs/promises';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {readSourceProfileJson,captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {createInstalledRowSource} from '../../../host-node/installed-row-source.mjs';
import {readSnowflakeSqlApi, SNOWFLAKE_SQL_READ_OPERATION} from '../site/snowflake-sql-read.mjs';
import {checkSnowflakeKeyPairProfile, openSnowflakeKeyPairMaterial} from '../site/snowflake-key-pair.mjs';

export const INSTALLED_SNOWFLAKE_SOURCE_VERSION = 'actql-installed-snowflake-source/0.1';
export const INSTALLED_SNOWFLAKE_SITE_VERSION = 'actql-installed-snowflake-site/0.1';
const registration = 'snowflake', revision = 'snowflake/0.1';
const profileKeys = ['version', 'connectorId', 'resource', 'database', 'schema', 'table',
  'metadataPath', 'siteProfilePath', 'accountConfigurationWire', 'limits'];
const siteKeys = ['version', 'apiOrigin', 'warehouse', 'role', 'authenticationType',
  'credentialAuthorityId', 'credentialKeyId', 'credentialPrivateKeyPath', 'environment',
  'journalRoot', 'namespaceId', 'siteGeneration', 'siteKey', 'tokenEnvironment'];
const limitKeys = ['maxBytes', 'maxNodes', 'maxDepth', 'maxColumns', 'maxNameUnits',
  'maxHandleUnits', 'maxPartitions', 'maxRows', 'maxTotalRows', 'maxRequests',
  'maxRequestBytes', 'maxContractPairs', 'timeoutSeconds', 'maxSecretBytes', 'pollDelayMs',
  'maxDescriptionBytes', 'maxDeclarationBytes', 'maxDeclarationNodes'];
const fail = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const text = value => typeof value === 'string' && value.length > 0 && value.isWellFormed() &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const absolute = value => text(value) && isAbsolute(value);
const closed = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const canonical = value => canonicalJson(value, {dataKeys: true});
const cid = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;

export function checkInstalledSnowflakeSourceProfile(profile) {
  if (!closed(profile, profileKeys) || profile.version !== INSTALLED_SNOWFLAKE_SOURCE_VERSION ||
      !['connectorId', 'resource', 'database', 'schema', 'table'].every(key =>
        text(profile[key]) && Buffer.byteLength(profile[key]) <= 4096) ||
      !absolute(profile.metadataPath) || !absolute(profile.siteProfilePath) ||
      !text(profile.accountConfigurationWire) || !closed(profile.limits, limitKeys)) {
    fail('InvalidInstalledSnowflakeSourceProfile');
  }
  const limits = {...profile.limits};
  if (!limitKeys.every(key => Number.isSafeInteger(limits[key]) && limits[key] <= 2147483647 &&
      limits[key] >= (key === 'pollDelayMs' ? 0 : 1)) ||
      limits.maxRows > limits.maxTotalRows || limits.maxRequests > 10000) {
    fail('InvalidInstalledSnowflakeSourceProfile');
  }
  return Object.freeze({...profile, limits: Object.freeze(limits)});
}

function checkSite(site) {
  const {caPath, keyPair, ...rest} = site ?? {};
  let origin;
  try {origin = new URL(rest.apiOrigin);} catch { /* Closed rejection below. */ }
  const materialKeys = Object.hasOwn(site ?? {}, 'keyPair')
    ? siteKeys.filter(key => key !== 'tokenEnvironment') : siteKeys;
  if (!closed(rest, materialKeys) || rest.version !== INSTALLED_SNOWFLAKE_SITE_VERSION ||
      origin?.protocol !== 'https:' || origin.origin !== rest.apiOrigin ||
      !['warehouse', 'role', 'credentialAuthorityId', 'credentialKeyId', 'environment',
        'namespaceId', 'siteKey'].every(key => text(rest[key]) && Buffer.byteLength(rest[key]) <= 4096) ||
      !['OAUTH', 'KEYPAIR_JWT'].includes(rest.authenticationType) ||
      !absolute(rest.credentialPrivateKeyPath) || !absolute(rest.journalRoot) ||
      (caPath !== undefined && !absolute(caPath)) ||
      !Number.isSafeInteger(rest.siteGeneration) || rest.siteGeneration < 0 ||
      (Object.hasOwn(site ?? {}, 'keyPair') ? rest.authenticationType !== 'KEYPAIR_JWT'
        : !/^[A-Z_][A-Z0-9_]{0,63}$/u.test(rest.tokenEnvironment))) fail('InvalidInstalledSnowflakeSite');
  const selected = Object.hasOwn(site ?? {}, 'keyPair') ? checkSnowflakeKeyPairProfile(keyPair) : undefined;
  return Object.freeze({...rest, ...(caPath === undefined ? {} : {caPath}),
    ...(selected === undefined ? {} : {keyPair: selected})});
}

async function readInputs(profile,{readJson=readSourceProfileJson,constructBodies}={}) {
  const installed = checkInstalledSnowflakeSourceProfile(profile);
  const site = checkSite(await readJson(installed.siteProfilePath));
  const metadata = await readJson(installed.metadataPath);
  const keys = ['version', 'connectorId', 'resource', 'database', 'schema', 'table', 'apiOrigin', 'bodies'];
  if (!closed(metadata, keys) || metadata.version !== 'actql-snowflake-read-metadata/0.1' ||
      !['connectorId', 'resource', 'database', 'schema', 'table'].every(key => metadata[key] === installed[key]) ||
      metadata.apiOrigin !== site.apiOrigin || !Array.isArray(metadata.bodies) ||
      metadata.bodies.length < 1 || metadata.bodies.length > installed.limits.maxPartitions) {
    fail('InvalidInstalledSnowflakeMetadata');
  }
  for(const body of metadata.bodies){
    if(typeof body!=='string'||body.length>Math.ceil(installed.limits.maxBytes/3)*4){
      fail('InvalidInstalledSnowflakeMetadata');
    }
  }
  // Identity hashes original DATA; only the actual pre-reserved loader builds
  // its binary Array. Metadata bytes are never reconstructed from JS values.
  const bodies=constructBodies?.(metadata.bodies,installed.limits.maxBytes);
  return {installed, site, metadata, bodies};
}

// All exact target strings are semantic data, including Unicode normalization.
// Their digest supplements the standard Host's configuration canonicalizer.
export async function installedSnowflakeSourceIdentityParts(profile,providerProfile,read,_entry,{configurationReader}={}) {
  const readers=captureConfigurationReaders(configurationReader,read,()=>fail('InstalledSnowflakeConfigurationReaderUnavailable'));
  const {installed,site,metadata}=await readInputs(providerProfile,readers);
  if(configurationReader!==undefined&&site.caPath!==undefined&&readers.readOriginalBytes===undefined){
    fail('InstalledSnowflakeConfigurationReaderUnavailable');
  }
  // Preserve the standalone DATA identity utility, not a raw installer path.
  const ca=site.caPath===undefined?undefined:readers.readOriginalBytes===undefined
    ?await readFile(site.caPath):await readers.readOriginalBytes(site.caPath);
  return [{...profile, accountConfigurationWire: JSON.parse(profile.accountConfigurationWire)},
    site, {exactTargetCid: cid({connectorId: installed.connectorId, resource: installed.resource,
      database: installed.database, schema: installed.schema, table: installed.table,
      warehouse: site.warehouse, role: site.role}), metadataCid: cid(metadata),
    ...(ca === undefined ? {} : {caSha256: createHash('sha256').update(ca).digest('hex')})}];
}

export async function loadInstalledSnowflakeSource(profile,{root,principalId,moon,
  baseEnvironmentWire,runtimeBundleCid,resolveSecret,installation,
  sourceInitialization,configurationReader,installationServices}) {
  if(sourceInitialization===undefined||configurationReader===undefined||installationServices===undefined){
    fail('InstalledSnowflakeInitializationUnavailable');
  }
  const method=(receiver,name,code)=>{
    if(!receiver||nodeTypes.isProxy(receiver))fail(code);
    const field=Object.getOwnPropertyDescriptor(receiver,name);
    if(!field||!Object.hasOwn(field,'value')||typeof field.value!=='function'||
      nodeTypes.isProxy(field.value)||nodeTypes.isAsyncFunction(field.value))fail(code);
    return field.value;
  };
  const input=method(sourceInitialization,'prepareInputConstruction','InstalledSnowflakeInitializationUnavailable');
  const declare=method(sourceInitialization,'prepareNativeDeclaration','InstalledSnowflakeInitializationUnavailable');
  const openSite=method(installationServices,'openRowSite','InstalledSnowflakeInitializationUnavailable');
  const quote=method(moon,'clientProgramInstalledSourceConstructionCapacity','SnowflakeOriginalReadUnavailable');
  const names=['ResponseLimits','DescriptionLimits','DeclarationLimits','DescribeTable','GenerateReadDeclaration',
    'PrepareRead','ReadAcquisition'];
  const originals=Object.freeze(Object.fromEntries(names.map(name=>{
    const fn=method(moon,`clientProgramSnowflake${name}`,'SnowflakeOriginalReadUnavailable');
    return [name,(...args)=>Reflect.apply(fn,moon,args)];
  })));
  const readers=captureConfigurationReaders(configurationReader,undefined,
    ()=>fail('InstalledSnowflakeConfigurationReaderUnavailable'));
  let inputBytes=0n;
  const {installed,site:siteProfile,metadata,bodies}=await readInputs(profile,{...readers,
    constructBodies(encoded,maximum){
      let text=0n,wire=0n;for(const body of encoded){text+=BigInt(body.length);wire+=BigInt(Math.floor(body.length*3/4));}
      inputBytes=wire;
      return Reflect.apply(input,sourceInitialization,[Object.freeze({
        capacity(){return checked(Reflect.apply(quote,moon,[4n*BigInt(encoded.length)+1n,2n*text,wire,0n,0n,0n]));},
        project(){return encoded.map(body=>{
          const bytes=Buffer.from(body,'base64');
          if(bytes.byteLength>maximum||bytes.toString('base64')!==body)fail('InvalidInstalledSnowflakeMetadata');
          return bytes;
        });},
      })]);
    },
  });
  const {limits}=installed;
  const nodes=BigInt(limits.maxNodes)*BigInt(bodies.length)+BigInt(limits.maxDeclarationNodes)+
    BigInt(limits.maxColumns)+BigInt(limits.maxPartitions);
  const textUnits=inputBytes+BigInt(limits.maxNameUnits)+BigInt(limits.maxDescriptionBytes)+BigInt(limits.maxDeclarationBytes);
  const wireBytes=inputBytes+BigInt(limits.maxDescriptionBytes)+BigInt(limits.maxDeclarationBytes);
  const prepared=Reflect.apply(declare,sourceInitialization,[Object.freeze({
    capacity(){return checked(Reflect.apply(quote,moon,[4n*nodes,8n*textUnits,8n*wireBytes,4n*nodes,8n*textUnits,8n*wireBytes]));},
    project(){
      const responseLimits=originals.ResponseLimits(limits.maxBytes,limits.maxNodes,limits.maxDepth,
        limits.maxColumns,limits.maxNameUnits,limits.maxHandleUnits,limits.maxPartitions,limits.maxRows,BigInt(limits.maxTotalRows));
      const descriptionLimits=originals.DescriptionLimits(limits.maxColumns,limits.maxNameUnits,
        limits.maxDescriptionBytes,limits.maxNodes,limits.maxDepth);
      const declarationLimits=originals.DeclarationLimits(limits.maxDeclarationBytes,limits.maxDeclarationNodes,limits.maxDepth,1,limits.maxColumns);
      const description=checked(originals.DescribeTable(installed.database,installed.schema,installed.table,bodies,responseLimits,descriptionLimits));
      const declaration=checked(originals.GenerateReadDeclaration(description,installed.resource,installed.connectorId,revision,descriptionLimits,declarationLimits));
      const keyMaterial=siteProfile.keyPair===undefined?undefined:openSnowflakeKeyPairMaterial(siteProfile.keyPair,
        {maxSecretBytes:limits.maxSecretBytes,resolveMaterial:resolveSecret});
      return Object.freeze({declaration,material:Object.freeze({description,responseLimits,descriptionLimits,
        declarationLimits,keyMaterial,metadataCid:cid(metadata)})});
    },
  })]);
  const {declaration,declared,environment,material:{description,descriptionLimits,declarationLimits,keyMaterial:material,metadataCid}}=prepared;
  const connection = `snowflake:${installed.connectorId}`;
  const target = (resource, fields) => Object.freeze({version: 'actql-installed-snowflake-target/0.1',
    apiOrigin: siteProfile.apiOrigin, database: installed.database, schema: installed.schema,
    table: installed.table, resource, warehouse: siteProfile.warehouse, role: siteProfile.role,
    metadataCid, catalogCid: declared.catalog_cid, fields: Object.freeze([...fields])});
  const allFields = declared.views[0].fields;
  const admitsApprovalTarget = (binding, resource) =>
    resource === installed.resource && binding !== null && typeof binding === 'object' &&
    Array.isArray(binding.fields) && new Set(binding.fields).size === binding.fields.length &&
    binding.fields.every(field => allFields.includes(field)) &&
    canonical(binding) === canonical(target(resource, binding.fields));
  if(siteProfile.caPath!==undefined&&readers.readOriginalBytes===undefined)fail('InstalledSnowflakeConfigurationReaderUnavailable');
  let originalSite,authorization;
  try {
    const ca=siteProfile.caPath===undefined?undefined:await readers.readOriginalBytes(siteProfile.caPath);
    ({site:originalSite,authorization}=await Reflect.apply(openSite,installationServices,[{
    installation,sourceInitialization,accountConfiguration:installed.accountConfigurationWire,
    profile:Object.freeze({...siteProfile,resourceOrigin:siteProfile.apiOrigin}),connection,ca,admitsApprovalTarget,
    responseHeaders: installation?.responseHeaders ?? ['content-encoding'],
    resolveSecret: material?.resolveSecret ?? resolveSecret ?? (async () => {
      const secret = process.env[siteProfile.tokenEnvironment];
      if (!text(secret)) fail('RemoteCredentialSecretUnavailable');
      return secret;
    }),
    }]));
  } catch (cause) {
    material?.close();
    throw cause;
  }
  const closeSite=originalSite.close;
  const site = material === undefined ? originalSite : Object.freeze({...originalSite,
    close() {
      const result = Reflect.apply(closeSite,originalSite,[]);
      material.close();
      return result;
    }});
  try {
    const preparedReads = new WeakMap();
    return await createInstalledRowSource({moon, declaration, declared,environment,sourceInitialization,
      environmentWire: environment.wire, connectorId: installed.connectorId,
      connectorRegistration: registration, connectorRevision: revision, site, authorization,
      readOperation: SNOWFLAKE_SQL_READ_OPERATION, physicalTarget: target,
      bindingCid: cid({version: 'actql-installed-snowflake-binding/0.1',
        contextCid: authorization.context.contextCid, runtimeBundleCid,
        metadataCid, site: siteProfile}),
      limits: {maxPages: limits.maxRequests, maxPageBytes: limits.maxBytes,
        maxPageRows: limits.maxRows, maxCaptureRows: limits.maxTotalRows},
      prepareAcquisition: options => {
        const prepared = checked(originals.PrepareRead(description,
          options.declaration, options.requirement, options.queryContract, options.evidenceContract,
          descriptionLimits, declarationLimits));
        const acquisition = originals.ReadAcquisition(prepared);
        preparedReads.set(acquisition, prepared);
        return acquisition;
      },
      readPages: async options => {
        const prepared = preparedReads.get(options.rowRun?.acquisition);
        if (prepared === undefined) fail('ForeignSnowflakeReadPreparation');
        // The standard Host passes the original nominal acquisition/run/frame.
        // No replacement reservation, Run or transport permission is issued.
        await readSnowflakeSqlApi({...options, moon, prepared, limits,
          warehouse: siteProfile.warehouse, role: siteProfile.role,
          authenticationType: siteProfile.authenticationType,
          credential: site.credential, callResource: site.callResource});
      }});
  } catch (cause) {
    throw await retainInstalledHostInitializationFailure(cause, {sourceProfile: site});
  }
}
