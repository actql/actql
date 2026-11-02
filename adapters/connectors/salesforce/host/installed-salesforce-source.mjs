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
import {checked} from '../../../host-common/runtime-result.mjs';
import {installedJsonSourceReaderLimitNames} from '../../../host-node/installed-credential-source-reader.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {salesforceInitializationConstructionCapacity} from './salesforce-initialization-construction.mjs';
import {installSalesforceAuthorization, installedSalesforceSiteBinding,
  loadInstalledSalesforceSite, releaseSalesforceSite,
  retainSalesforceSiteCleanup, DEFAULT_SALESFORCE_CATALOG_LIMITS} from
  './installed-salesforce-site.mjs';
import {restoreSalesforceGeneration, publishSalesforceGeneration, readPublicationFile} from './salesforce-publication.mjs';
import {installSalesforceResourceService} from
  './salesforce-resource-service.mjs';
import {prepareSalesforceSourceReadSequence} from '../site/salesforce-query-read.mjs';

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
  providerProfile, read, _entry, {configurationReader} = {}) {
  const checkedProfile = checkInstalledSalesforceSourceProfile(providerProfile);
  const readers = captureConfigurationReaders(configurationReader, read,
    () => fail('InstalledConfigurationReaderUnavailable'));
  const publication = await readPublicationFile(checkedProfile.publicationPath, readers.readText);
  return [
    {...profile, accountConfigurationWire: JSON.parse(
      profile.accountConfigurationWire)},
    await read(checkedProfile.siteProfilePath, {maxBytes: 8 * 1024 * 1024}),
    (readers.parseJsonText ?? JSON.parse)(publication.body),
  ];
}

async function openSite(profile, {root, principalId, moon,
  providerMoon: salesforceMoon, runtimeBundleCid, resolveSecret,
  openCredentialJournal}) {
  const authorization = await installSalesforceAuthorization({
    accountConfiguration: profile.accountConfigurationWire, principalId,
    root});
  const site = await loadInstalledSalesforceSite(profile.siteProfilePath, {
    commonMoon: moon, salesforceMoon, authorization, runtimeBundleCid,
    resolveSecret, openCredentialJournal});
  return {authorization, site};
}

// The explicit publication step for an installed Host profile: describe the
// profile's target Resources under the current metadata read decisions and
// replace the published generation. It is never run by a Host start.
export async function publishInstalledSalesforceSource(profile, options) {
  const checkedProfile = checkInstalledSalesforceSourceProfile(profile);
  const {site} = await openSite(checkedProfile, options);
  let published;
  try {
    published = await publishSalesforceGeneration({site,
      path: checkedProfile.publicationPath,
      connectorId: checkedProfile.connectorId,
      resources: checkedProfile.resources, signal: options.signal});
  } catch (error) {
    throw retainSalesforceSiteCleanup(site, error);
  }
  releaseSalesforceSite(site);
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
export async function loadInstalledSalesforceSource(profile, {moon,
  providerMoon: salesforceMoon, runtimeBundleCid, resolveSecret,
  openCredentialJournal, construction}) {
  if (construction === undefined) fail('InstalledSourceInitializationUnavailable');
  const checkedProfile = checkInstalledSalesforceSourceProfile(profile);
  const queryMoon = queryRuntime(moon);
  const policyMethod = Object.getOwnPropertyDescriptor(moon, 'clientProgramInstalledSourceReaderPolicy');
  if (!policyMethod || !Object.hasOwn(policyMethod, 'value') || typeof policyMethod.value !== 'function') {
    fail('InstalledSourceReaderRuntimeUnavailable');
  }
  const policy = Reflect.apply(policyMethod.value, moon, []);
  if (!Array.isArray(policy) || policy.length !== 3 || policy.some(value =>
    !Number.isSafeInteger(value) || value < 1 || value > 2147483647)) fail('InstalledSourceReaderPolicyUnavailable');
  const readerPolicy = Object.freeze([...policy]);
  const runAcquisitionLimits = Object.freeze({maxBindings: readerPolicy[1], maxSecretBytes: readerPolicy[0]});
  const {authorization, site} = await construction.openSpecializedSite({
    authorizationConstructor: installSalesforceAuthorization,
    siteConstructor: loadInstalledSalesforceSite,
    siteArgument: checkedProfile.siteProfilePath,
    accountConfiguration: checkedProfile.accountConfigurationWire,
    siteOptions: {salesforceMoon, resolveSecret, openCredentialJournal, runAcquisitionLimits},
  });
  const readers = construction.configurationReader;
  const {body, generationCid} = await readPublicationFile(checkedProfile.publicationPath, readers.readText);
  const generation = readers.parseJsonText(body);
  if (JSON.stringify(generation) !== body) fail('InvalidSalesforcePublication');
  const capacity = () => salesforceInitializationConstructionCapacity(moon,
    {generation, siteBinding: site, declarationLimits});
  const loaded = construction.prepareNativeInput(Object.freeze({capacity,
    project: () => restoreSalesforceGeneration({site, generation,
      connectorId: checkedProfile.connectorId, resources: checkedProfile.resources})}));
  let declaration, recover;
  construction.prepareNativeDeclaration(Object.freeze({capacity, project() {
    // Preserve the two existing, distinct runtime restores; neither opaque
    // declaration is passed across its runtime's nominal boundary.
    const siteHandle = checked(moon.clientProgramSalesforceSite(
      site.namespaceId, site.principal, site.environment, site.connectionRevision,
      site.orgId, site.siteKey, site.siteGeneration, site.instanceOrigin));
    recover = (evidence, expectedRun) => checked(
      moon.clientProgramSalesforceRecoverObservation(siteHandle,
        ...recoveryArguments(evidence), expectedRun));
    declaration = checked(moon.clientProgramSalesforceRestoreDeclaration(
      siteHandle, recover(loaded.declared.evidence, undefined),
      checkedProfile.connectorId, loaded.declared.catalog_cid,
      declarationLimits.maxBytes, declarationLimits.maxNodes, declarationLimits.maxDepth));
    return Object.freeze({declaration: checked(moon.clientProgramSalesforceRowDeclaration(declaration))});
  }}));
  const discovery = installSalesforceResourceService({salesforceMoon, sites: [site]});
  discovery.installPublished(site.connection, loaded.declared);
  return installedSalesforceAdapter({moon, queryMoon, site, authorization,
    declaration, recover, discovery, construction, readerPolicy, resources: checkedProfile.resources, generationCid,
    catalogCid: loaded.declared.catalog_cid, connectorId: checkedProfile.connectorId});
}

// Compatibility installation only. Original Salesforce identities and typed
// Describe/query codecs stay here; the shared Row Source owns every checked
// preparation, original acquisition, RowRun, capture and failure cleanup.
async function installedSalesforceAdapter({moon, queryMoon, site, authorization,
  declaration, recover, discovery, construction, readerPolicy, resources, generationCid,
  catalogCid, connectorId}) {
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
  // These are the existing codec bounds and original installed identity
  // lengths. The quote supplies representation backing, never read authority.
  // All twelve responses (two independent Describe + ten query pages) remain
  // with the SAME Reader through completion or failed-child retirement.
  const bindingUnits = ['namespaceId', 'principal', 'environment', 'connectionRevision', 'orgId',
    'siteKey', 'instanceOrigin'].reduce((units, name) => units + site[name].length, 0) +
    'salesforce'.length + 'salesforce/0.1'.length + 2 * 71 + 36 + '-recheck'.length;
  const resourceUnits = Math.max(...resources.map(name => name.length));
  // The original bounded declaration contains all possible selected API names.
  // Its wire bounds their target spelling; add the original immutable Site
  // strings and fixed target/CID keys with the same worst-case JSON escaping.
  const maxTargetBytes = 1024 + 6 * (declarationLimits.maxBytes + bindingUnits + resourceUnits);
  const readerLimits = Object.freeze({maxResponseBytes: readLimits.maxBytes,
    maxTotalResponseBytes: (readLimits.maxPages + 2) * readLimits.maxBytes,
    maxNodes: readLimits.maxNodes, maxDepth: readLimits.maxDepth,
    maxRows: readLimits.maxRows, maxTotalRows: readLimits.maxTotalRows,
    maxPages: readLimits.maxPages + 2, pageSize: readLimits.maxRows,
    maxCursorBytes: readLimits.maxLocatorUnits, maxIdentityBytes: readLimits.maxBytes,
    maxTargetBytes, maxValueNodes: readLimits.maxNodes, maxValueTextBytes: readLimits.maxBytes,
    maxRowsWireBytes: readLimits.maxBytes, maxRowsWireNodes: readLimits.maxNodes,
    maxRowsWireDepth: readLimits.maxDepth, maxSecretBytes: readerPolicy[0]});
  const capacityMethod = Object.getOwnPropertyDescriptor(moon, 'clientProgramInstalledSalesforceSourceReaderCapacity');
  if (!capacityMethod || !Object.hasOwn(capacityMethod, 'value') || typeof capacityMethod.value !== 'function') {
    fail('InstalledSourceReaderRuntimeUnavailable');
  }
  const capacity = Reflect.apply(capacityMethod.value, moon, [
    installedJsonSourceReaderLimitNames.map(name => readerLimits[name]), readerPolicy[2], readerPolicy[0],
    ['maxBytes', 'maxNodes', 'maxDepth', 'maxFields', 'maxNameUnits'].map(
      name => DEFAULT_SALESFORCE_CATALOG_LIMITS.describe[name]),
    DEFAULT_SALESFORCE_CATALOG_LIMITS.maxObservationBytes, bindingUnits, resourceUnits,
    readLimits.maxPages, site.apiVersion.length, 4096]);
  if (capacity === undefined || capacity === null) fail('InstalledSourceReaderCapacityUnavailable');
  const sequence = Object.freeze({operation: 'salesforce:query:read', maxUses: readLimits.maxPages,
    children: Object.freeze([Object.freeze({operation: 'salesforce:catalog:describe', maxUses: 2})])});
  const implementation = construction.sourceReaderImplementation({limits: readerLimits,
    columnCount: readerPolicy[2], readSequenceConstruction: Object.freeze({capacity,
      originalLimits: readLimits, sequence})});
  const providerReader = construction.createSourceReader({implementation,
    prepareReadSequence(input) {
      return prepareSalesforceSourceReadSequence({moon, queryMoon, site, declaration, recover,
        preparedRead: input.preparedRead, originalAuthorization: input.originalAuthorization, limits: readLimits});
    }});
  const binding = installedSalesforceSiteBinding(site, connectorId);
  return construction.createRowSource({bindingCid: binding.bindingCid, providerReader,
    directReadIdentity, grantBeforeBegin: true,
    realizationKey: 'salesforce-acquired',
    publication: Object.freeze({generationCid, discovery: Object.freeze({resources: discovery.resources,
      inspectResource: discovery.inspectResource, peekResource: discovery.peekResource})}),
    publicationSurface: Object.freeze(['realizationKey', 'supportsRetainedRelationOutput',
      'connectorRegistration', 'connectorRevision', 'environmentWire', 'connectorBindings',
      'readAuthorization', 'sourceAccess', 'sourceReadAccesses', 'admitsSource',
      'ledgerCapacity', 'managedCaptureCapacity', 'managedWholeSourceCapacity',
      'managedEffectPlanSelection', 'prepare', 'open', 'close']),
    originalSourceAccess: Object.freeze({authorization, connection: site.connection}),
    // These functions retain this same original Salesforce Site. The alias
    // selects its existing issuer; it does not create a second grant Owner.
    projectSite: () => Object.freeze({connection: site.connection,
      referenceCurrent: site.referenceCurrent,
      issueReadGrant: request => site.issueGrant(request),
      admitCheckpointReadApproval: decision => site.admitCheckpointReadApproval(decision)}),
    readOperation: 'salesforce:query:read',
    physicalTarget: (resource, fields) => Object.freeze({
      version: 'actql-installed-salesforce-target/0.1',
      org_id: site.orgId, instance_origin: site.instanceOrigin,
      site_key: site.siteKey, site_generation: site.siteGeneration,
      connection_revision: site.connectionRevision, catalog_cid: catalogCid,
      resource, fields: Object.freeze([...fields])}),
    limits: Object.freeze({maxPages: readerLimits.maxPages,
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
      // Pure original facts only. The SAME admitted RowRun precedes this
      // callback; both metadata reads execute inside its original Reader.
      return Object.freeze({acquisition, approval, resource, nonce,
        runInvocationCid, dispatchRequestCid, signal});
    }});
}
