import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
// Salesforce's source installation for the standard installed Host, entered
// in the Host's installed connector table by `src/connectors/salesforce/
// host-bundle.json` (`check`, `identityParts`, `publish`, `load`).
// The Host profile names the installed Site profile (which holds only secret
// references), the account configuration text, the connector id, the target
// Resources and the published generation. Loading performs no provider I/O:
// the published generation is restored and bound to the Site as installed
// now. Acquisition planning, capture and Source Evidence are owned by the
// standard runtime (`moon`); this adapter supplies only provider bytes,
// credential grants and the current read decision.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {retainInstalledSourceAdapter} from '../../../host-node/installed-host-services.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {createInstalledRowSource} from '../../../host-node/installed-row-source.mjs';
import {installSalesforceAuthorization, installedSalesforceSiteBinding,
  loadInstalledSalesforceSite, releaseSalesforceSite,
  retainSalesforceSiteCleanup} from
  './installed-salesforce-site.mjs';
import {loadSalesforceGeneration, publishSalesforceGeneration, readPublicationFile,
  salesforceCheckEnvironment,restoreSalesforceGenerationText} from './salesforce-publication.mjs';
import {installSalesforceResourceService} from
  './salesforce-resource-service.mjs';
import {readSalesforceQuery} from '../site/salesforce-query-read.mjs';

export const INSTALLED_SALESFORCE_SOURCE_VERSION =
  'actql-installed-salesforce-source/0.1';
const profileKeys = Object.freeze(['accountConfigurationWire', 'connectorId',
  'publicationPath', 'resources', 'siteProfilePath', 'version']);
// One acquisition reads at most this many rows (the standard Host's checked
// requirement bound) over at most `maxPages` query pages.
const readLimits = Object.freeze({maxBytes: 4_000_000, maxNodes: 400_000,
  maxDepth: 32, maxRows: 2000, maxLocatorUnits: 2048, maxPages: 10,
  maxTotalRows: 100});
const declarationLimits = Object.freeze({maxBytes: 4_000_000,
  maxNodes: 400_000, maxDepth: 64});

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const cid = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(value)).digest('hex')}`;
const names = /^[A-Za-z_][A-Za-z0-9_]{0,254}$/u;

// Check the Host profile's shape before anything is read or installed.
export function checkInstalledSalesforceSourceProfile(profile) {
  if (profile === null || typeof profile !== 'object' ||
      Array.isArray(profile) ||
      Object.keys(profile).sort().join('\0') !== profileKeys.join('\0') ||
      profile.version !== INSTALLED_SALESFORCE_SOURCE_VERSION ||
      !text(profile.siteProfilePath) || !isAbsolute(profile.siteProfilePath) ||
      !text(profile.publicationPath) || !isAbsolute(profile.publicationPath) ||
      !text(profile.connectorId) || !text(profile.accountConfigurationWire) ||
      !Array.isArray(profile.resources) || profile.resources.length === 0 ||
      profile.resources.length > 200 ||
      !profile.resources.every(name => typeof name === 'string' &&
        names.test(name)) ||
      new Set(profile.resources).size !== profile.resources.length) {
    fail('InvalidInstalledSourceProfile');
  }
  return Object.freeze({...profile,
    resources: Object.freeze([...profile.resources])});
}

// The parts of this installation's identity: the Host profile with its
// account configuration as a document, the installed Site profile and the
// published generation. No credential value and no provider I/O.
export async function installedSalesforceSourceIdentityParts(profile,
  providerProfile, read,_entry,{configurationReader}={}) {
  const checkedProfile = checkInstalledSalesforceSourceProfile(providerProfile);
  const readers=captureConfigurationReaders(configurationReader,read,()=>fail('InstalledSalesforceConfigurationReaderUnavailable'));
  return [
    {...profile, accountConfigurationWire: JSON.parse(
      profile.accountConfigurationWire)},
    await readers.readJson(checkedProfile.siteProfilePath, {maxBytes: 8 * 1024 * 1024}),
    JSON.parse((await readPublicationFile(checkedProfile.publicationPath,{readText:readers.readText})).body),
  ];
}

async function openSite(profile, {root, principalId, moon,
  providerMoon: salesforceMoon, runtimeBundleCid, resolveSecret,
  openCredentialJournal,configurationReader}) {
  const authorization=await installSalesforceAuthorization({
    accountConfiguration:profile.accountConfigurationWire,principalId,root,gateOptions:{runtime:moon}});
  let site;
  try{
    site=await loadInstalledSalesforceSite(profile.siteProfilePath,{commonMoon:moon,salesforceMoon,
      authorization,runtimeBundleCid,resolveSecret,openCredentialJournal,configurationReader});
    const closeSite=site.close,closeAccount=authorization.close;
    let siteClosed=false,accountClosed=false,closing=false,siteResult;
    return Object.freeze({authorization,site,close(){
      if(closing)fail('SalesforceAuthorizationCleanupPending');
      closing=true;
      try{
        if(!siteClosed){siteResult=Reflect.apply(closeSite,site,[]);siteClosed=true;}
        // The original Account outlives its Site and retires only on its own
        // acknowledgement. A retry does not close the released Site again.
        if(!accountClosed){
          if(Reflect.apply(closeAccount,authorization,[])!==true)fail('SalesforceAuthorizationCleanupPending');
          accountClosed=true;
        }
        return siteResult;
      }finally{closing=false;}
    },cleanupPending(){return !siteClosed||!accountClosed;}});
  }catch(error){throw await retainInstalledHostInitializationFailure(error,
    site===undefined?{authorization}:{sourceProfile:site,authorization});}
}

// The explicit publication step for an installed Host profile: describe the
// profile's target Resources under the current metadata read decisions and
// replace the published generation. It is never run by a Host start.
export async function publishInstalledSalesforceSource(profile, options) {
  const checkedProfile = checkInstalledSalesforceSourceProfile(profile);
  const original = await openSite(checkedProfile, options);
  const {site} = original;
  let published;
  try {
    published = await publishSalesforceGeneration({site,
      path: checkedProfile.publicationPath,
      connectorId: checkedProfile.connectorId,
      resources: checkedProfile.resources, signal: options.signal});
  } catch (error) {
    throw retainSalesforceSiteCleanup(original, error);
  }
  releaseSalesforceSite(original);
  return published;
}

// The standard runtime's arguments reprojecting retained describe evidence.
function recoveryArguments(evidence) {
  const binding = JSON.parse(evidence.observationJson).binding;
  const limits = evidence.describeLimits;
  return [evidence.observationJson, binding.run_invocation_cid,
    binding.dispatch_request_cid, binding.sync_occurrence, [...evidence.names],
    evidence.describeBodyBase64.map(value => value === null ? undefined
      : Buffer.from(value, 'base64')),
    [...evidence.outcomes],
    evidence.describeUseCids.map(value => value ?? undefined),
    evidence.describeResponseSha256.map(value => value ?? undefined),
    limits.maxBytes, limits.maxNodes, limits.maxDepth, limits.maxFields,
    limits.maxNameUnits, evidence.maxObservationBytes];
}

// Provider codecs run in the checked Program's runtime. Only their typed
// page values are handed to the neutral row owner; no provider execution
// or capture state crosses runtimes.
function queryRuntime(moon) {
  const runtime = {
    salesforceBeginQueryRead: moon.clientProgramSalesforceBeginQueryRead,
    salesforceQueryReadNextPath: moon.clientProgramSalesforceQueryReadNextPath,
    salesforceQueryReadAcceptPage: moon.clientProgramSalesforceQueryReadAcceptPage,
    salesforceQueryReadAcknowledgePage: moon.clientProgramSalesforceQueryReadAcknowledgePage,
    salesforceQueryReadInterrupt: moon.clientProgramSalesforceQueryReadInterrupt,
    salesforceQueryReadComplete: moon.clientProgramSalesforceQueryReadComplete,
    salesforceQueryReadRowCount: moon.clientProgramSalesforceQueryReadRowCount,
    salesforceQueryPageResponseSha256: moon.clientProgramSalesforceQueryPageResponseSha256,
    salesforceQueryPageRowCount: moon.clientProgramSalesforceQueryPageRowCount,
    salesforceRecheckReadProjection: moon.clientProgramSalesforceRecheckReadProjection,
    salesforceReadProjectionScopeMatches: moon.clientProgramSalesforceReadProjectionScopeMatches,
    salesforceQueryReadValueViolation: moon.clientProgramSalesforceQueryReadValueViolation,
  };
  if (Object.values(runtime).some(entry => typeof entry !== 'function')) {
    fail('InvalidSalesforceSourceRuntime');
  }
  return Object.freeze(runtime);
}

// Load one installed Salesforce source. `baseEnvironmentWire` is the Host's
// base Check Environment; the published declaration and its evidence
// members are added to it.
export async function loadInstalledSalesforceSource(profile,{root,principalId,moon,
  providerMoon:salesforceMoon,baseEnvironmentWire,runtimeBundleCid,resolveSecret,openCredentialJournal,
  sourceInitialization,configurationReader,installationServices}) {
  if(sourceInitialization===undefined||configurationReader===undefined||installationServices===undefined){
    fail('InstalledSalesforceInitializationUnavailable');
  }
  const method=(receiver,name)=>{
    if(!receiver||nodeTypes.isProxy(receiver))fail('InstalledSalesforceInitializationUnavailable');
    const field=Object.getOwnPropertyDescriptor(receiver,name);
    if(!field||!Object.hasOwn(field,'value')||typeof field.value!=='function'||
      nodeTypes.isProxy(field.value)||nodeTypes.isAsyncFunction(field.value))fail('InstalledSalesforceInitializationUnavailable');
    return field.value;
  };
  const prepareInput=method(sourceInitialization,'prepareInputConstruction');
  const prepareNative=method(sourceInitialization,'prepareNativeDeclaration');
  const quote=method(moon,'clientProgramInstalledSourceConstructionCapacity');
  const readers=captureConfigurationReaders(configurationReader,undefined,()=>fail('InstalledSalesforceConfigurationReaderUnavailable'));
  const checkedProfile=checkInstalledSalesforceSourceProfile(profile),queryMoon=queryRuntime(moon);
  const accountUnits=BigInt(checkedProfile.accountConfigurationWire.length),contextUnits=BigInt(root.length+principalId.length);
  // The original Account/context constructor follows this initial admission.
  // Its variable configuration tree and exact legacy context text are not a
  // manifest grant or another Request/Root. Physical key/CA input remains with
  // the same managed configuration reader below.
  Reflect.apply(prepareInput,sourceInitialization,[Object.freeze({
    capacity(){return checked(Reflect.apply(quote,moon,[4n*accountUnits+4n,
      12n*accountUnits+8n*contextUnits,8n*accountUnits,0n,0n,0n]));},
    project(){return Object.freeze({profile:checkedProfile});},
  })]);
  const original=await openSite(checkedProfile,{root,principalId,moon,providerMoon:salesforceMoon,
    runtimeBundleCid,resolveSecret,openCredentialJournal,configurationReader});
  const {authorization,site}=original;
  let adapter;
  try{
    const publication=await readPublicationFile(checkedProfile.publicationPath,{readText:readers.readText});
    const inputUnits=BigInt(publication.body.length),nodes=3n*BigInt(declarationLimits.maxNodes)+4n*inputUnits;
    const textUnits=3n*BigInt(declarationLimits.maxBytes)+12n*inputUnits;
    const prepared=Reflect.apply(prepareNative,sourceInitialization,[Object.freeze({
      capacity(){return checked(Reflect.apply(quote,moon,[0n,0n,0n,nodes,textUnits,textUnits]));},
      project(){
        const loaded=restoreSalesforceGenerationText({site,...publication,
          connectorId:checkedProfile.connectorId,resources:checkedProfile.resources});
        const siteHandle=checked(moon.clientProgramSalesforceSite(site.namespaceId,site.principal,site.environment,
          site.connectionRevision,site.orgId,site.siteKey,site.siteGeneration,site.instanceOrigin));
        const recover=(evidence,expectedRun)=>checked(moon.clientProgramSalesforceRecoverObservation(siteHandle,
          ...recoveryArguments(evidence),expectedRun));
        const declaration=checked(moon.clientProgramSalesforceRestoreDeclaration(siteHandle,
          recover(loaded.declared.evidence,undefined),checkedProfile.connectorId,loaded.declared.catalog_cid,
          declarationLimits.maxBytes,declarationLimits.maxNodes,declarationLimits.maxDepth));
        const rowDeclaration=checked(moon.clientProgramSalesforceRowDeclaration(declaration));
        // This is the original Common row projection of the same Salesforce
        // Catalog, never a provider-neutral Catalog regeneration. Its sole
        // serializer supplies the shared evidence members as well.
        const wire=moon.clientProgramRowSourceDeclarationJson(rowDeclaration),declared=JSON.parse(wire);
        const environment=salesforceCheckEnvironment(baseEnvironmentWire,loaded.declared,
          {schemas:declared.evidence_schemas,capabilities:declared.evidence_capabilities});
        const discovery=installSalesforceResourceService({salesforceMoon,sites:[site]});
        discovery.installPublished(site.connection,loaded.declared);
        // Generation DATA, two observation runtimes, provider/Common Catalog
        // holders and the returned JS projection coexist. Complete original
        // texts bound each representation without another semantic pass.
        const units=inputUnits+BigInt(wire.length);
        const retainedCapacity=checked(Reflect.apply(quote,moon,[6n*units,18n*units,2n*inputUnits,0n,0n,0n]));
        return Object.freeze({declaration:rowDeclaration,declared,wire,environment,retainedCapacity,
          material:Object.freeze({loaded,declaration,recover,discovery})});
      },
    })]);
    const {loaded,declaration,recover,discovery}=prepared.material;
    adapter=await installedSalesforceAdapter({moon,queryMoon,site,authorization,
      declaration,rowDeclaration:prepared.declaration,declared:prepared.declared,sourceInitialization,
      recover,discovery,close:original.close,environment:prepared.environment,generationCid:loaded.generationCid,
      catalogCid:loaded.declared.catalog_cid,connectorId:checkedProfile.connectorId});
    return adapter;
  }catch(error){throw await retainInstalledHostInitializationFailure(error,{sourceProfile:adapter??original});}
}

// Compatibility installation only. Original Salesforce identities and typed
// Describe/query codecs stay here; the shared Row Source owns every checked
// preparation, original acquisition, RowRun, capture and failure cleanup.
async function installedSalesforceAdapter({moon, queryMoon, site, authorization,
  declaration,rowDeclaration,declared,recover,discovery,environment,generationCid,
  catalogCid,connectorId,sourceInitialization,close}) {
  const directReadIdentity = Object.freeze({
    input: 0,
    subject: prepared => cid({version: 'actql-salesforce-acquisition-read/0.1',
      requirementCid: prepared.checkedSource.requirementCid,
      physicalBinding: prepared.physicalBinding}),
    attempt: (prepared, nonce) => {
      const runInvocationCid = cid({version: 'actql-salesforce-acquisition/0.1',
        requirementCid: prepared.checkedSource.requirementCid, nonce});
      return Object.freeze({runInvocationCid, dispatchRequestCid: cid({
        version: 'actql-salesforce-acquisition-dispatch/0.1', runInvocationCid})});
    },
    useId: (nonce, index) => `${nonce}-query-${index}`,
  });
  const binding = installedSalesforceSiteBinding(site, connectorId);
  const source = await createInstalledRowSource({moon,
    declaration:rowDeclaration,declared,environment,sourceInitialization,environmentWire:environment.wire,
    connectorId, connectorRegistration: site.connectorRegistration,
    connectorRevision: site.connectorRevision, bindingCid: binding.bindingCid,
    authorization, directReadIdentity, grantBeforeBegin: true,
    originalSourceAccess: Object.freeze({authorization, connection: site.connection}),
    // These functions retain this same original Salesforce Site. The alias
    // selects its existing issuer; it does not create a second grant Owner.
    site: Object.freeze({connection: site.connection,
      issueReadGrant: request => site.issueGrant(request),
      admitCheckpointReadApproval: decision => site.admitCheckpointReadApproval(decision),
      close}),
    readOperation: 'salesforce:query:read',
    physicalTarget: (resource, fields) => Object.freeze({
      version: 'actql-installed-salesforce-target/0.1',
      org_id: site.orgId, instance_origin: site.instanceOrigin,
      site_key: site.siteKey, site_generation: site.siteGeneration,
      connection_revision: site.connectionRevision, catalog_cid: catalogCid,
      resource, fields: Object.freeze([...fields])}),
    limits: Object.freeze({maxPages: readLimits.maxPages,
      maxPageBytes: readLimits.maxBytes, maxPageRows: readLimits.maxRows,
      maxCaptureRows: readLimits.maxTotalRows}),
    prepareRead: async ({prepared, acquisition, decision, granted, resource,
      nonce, runInvocationCid, dispatchRequestCid, signal}) => {
      const approval = decision.basis === 'resumed_approval' ? granted : undefined;
      if (approval !== undefined && (approval.resource !== resource ||
          approval.catalogCid !== prepared.physicalBinding.catalog_cid ||
          JSON.stringify(approval.fields) !==
            JSON.stringify(prepared.physicalBinding.fields))) {
        fail('SalesforceReadApprovalNotAdmitted');
      }
      const describe = async suffix => {
        const described = await site.describeForAcquisition({resource,
          runInvocationCid, dispatchRequestCid, occurrence: `${nonce}-${suffix}`,
          approval, signal});
        return Object.freeze({status: 'observed',
          observation: recover(described.evidence, runInvocationCid),
          observationCid: described.observationCid,
          observationJson: described.evidence.observationJson});
      };
      const current = await describe('plan');
      const plan = checked(moon.clientProgramRecheckSalesforceRowProjection(
        declaration, acquisition, current.observation, 4096));
      return Object.freeze({plan, describe});
    },
    readPages: async ({preparedRead, authorizationFor, chargePage, rowRun, signal}) => {
      await readSalesforceQuery({moon: queryMoon, plan: preparedRead.plan,
        apiVersion: site.apiVersion, limits: readLimits, chargePage,
        consumePage: (page, {charge}) => {
          const values = moon.clientProgramSalesforceQueryPageValues(page);
          // Borrow this shared Host's original accounted RowRun. Typed values
          // are admitted directly; never stringify decimal/presence values.
          checked(moon.clientProgramRowSourceAcceptChargedValues(
            rowRun.run, charge, runtimeField(values, 0), runtimeField(values, 1)));
        },
        initialAuthorization: await authorizationFor(0),
        authorizationForPage: async (_path, index) => authorizationFor(index),
        credential: site.credential,
        refreshCatalog: () => preparedRead.describe('recheck'), signal});
    }});
  // Keep the established compatibility entry shape. It delegates to the one
  // shared execution implementation and does not expose new keyed/listing or
  // retained-recovery profiles merely because the shared Owner supports them.
  return retainInstalledSourceAdapter(sourceInitialization,source,Object.freeze({realizationKey:'salesforce-acquired',
    supportsRetainedRelationOutput: true,
    connectorRegistration: source.connectorRegistration,
    connectorRevision: source.connectorRevision,
    environmentWire: source.environmentWire, generationCid,
    connectorBindings: Object.freeze([binding]),
    readAuthorization: source.readAuthorization,
    sourceAccess: source.sourceAccess, sourceReadAccesses: source.sourceReadAccesses,
    admitsSource: source.admitsSource,
    ledgerCapacity: source.ledgerCapacity, prepare: source.prepare,
    open: source.open, close: source.close,
    discovery: Object.freeze({resources: discovery.resources,
      inspectResource: discovery.inspectResource,
      peekResource:discovery.peekResource})}));
}
