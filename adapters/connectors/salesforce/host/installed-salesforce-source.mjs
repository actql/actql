// Host-owned Salesforce source installation for the standard installed Host.
// The Host profile names the installed Site profile (which holds only secret
// references), the account configuration text, the connector id, the target
// Resources and the published generation. Loading performs no provider I/O:
// the published generation is restored and bound to the Site as installed
// now. Acquisition planning, capture and Source Evidence are owned by the
// standard runtime (`moon`); this adapter supplies only provider bytes,
// credential grants and the current read decision.
import {createHash, randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {checked} from '../../../host-common/runtime-result.mjs';
import {acquisitionFailure} from '../../../host-common/acquisition-outcome.mjs';
import {authorizationRuntimeCode} from
  '../../../host-common/authorization-gate.mjs';
import {installSalesforceAuthorization, installedSalesforceSiteBinding,
  loadInstalledSalesforceSite, releaseSalesforceSite,
  retainSalesforceSiteCleanup} from
  './installed-salesforce-site.mjs';
import {loadSalesforceGeneration, publishSalesforceGeneration,
  salesforceCheckEnvironment} from './salesforce-publication.mjs';
import {installSalesforceResourceService} from
  './salesforce-resource-service.mjs';
import {readSalesforceIssuedBroad} from '../site/salesforce-query-read.mjs';

export const INSTALLED_SALESFORCE_SOURCE_VERSION =
  'actql-installed-salesforce-source/0.1';
const profileKeys = Object.freeze(['accountConfigurationWire', 'connectorId',
  'publicationPath', 'resources', 'siteProfilePath', 'version']);
const contractRoot = new URL('../../../../spec/contracts/', import.meta.url);
// One acquisition reads at most this many rows (the standard Host's checked
// requirement bound) over at most `maxPages` query pages.
const readLimits = Object.freeze({maxBytes: 4_000_000, maxNodes: 400_000,
  maxDepth: 32, maxRows: 2000, maxLocatorUnits: 2048, maxPages: 10,
  maxTotalRows: 100});
// One acquisition captures at most 500 KB of text: what the standard Host's
// Local compute evaluates at once. Larger reads are refused while capturing.
const captureLimits = Object.freeze({maxNodes: 100_000,
  maxTextBytes: 500_000, maxDepth: 100, maxWork: 20_000_000});
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

async function openSite(profile, {root, principalId, moon, salesforceMoon,
  runtimeBundleCid, resolveSecret, openCredentialJournal}) {
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

// Load one installed Salesforce source. `baseEnvironmentWire` is the Host's
// base Check Environment; the published declaration and its evidence
// members are added to it.
export async function loadInstalledSalesforceSource(profile, {root,
  principalId, moon, salesforceMoon, baseEnvironmentWire, runtimeBundleCid,
  resolveSecret, openCredentialJournal}) {
  const checkedProfile = checkInstalledSalesforceSourceProfile(profile);
  const {authorization, site} = await openSite(checkedProfile, {root,
    principalId, moon, salesforceMoon, runtimeBundleCid, resolveSecret,
    openCredentialJournal});
  try {
    const loaded = await loadSalesforceGeneration({site,
      path: checkedProfile.publicationPath,
      connectorId: checkedProfile.connectorId,
      resources: checkedProfile.resources});
    const [schemas, capabilities] = checked(
      salesforceMoon.salesforceSourceEvidenceMembers(
        loaded.declared.declaration));
    const environment = salesforceCheckEnvironment(baseEnvironmentWire,
      loaded.declared, {schemas, capabilities});
    // The standard runtime restores the same declaration from the same
    // published bytes, bound to this Site, and must reproduce its Catalog.
    const siteHandle = checked(moon.clientProgramSalesforceSite(
      site.tenant, site.principal, site.environment, site.connectionRevision,
      site.orgId, site.siteKey, site.siteGeneration, site.instanceOrigin));
    const recover = (evidence, expectedRun) => checked(
      moon.clientProgramSalesforceRecoverObservation(siteHandle,
        ...recoveryArguments(evidence), expectedRun));
    const declaration = checked(moon.clientProgramSalesforceRestoreDeclaration(
      siteHandle, recover(loaded.declared.evidence, undefined),
      checkedProfile.connectorId, loaded.declared.catalog_cid,
      declarationLimits.maxBytes, declarationLimits.maxNodes,
      declarationLimits.maxDepth));
    const discovery = installSalesforceResourceService({salesforceMoon,
      sites: [site]});
    discovery.installPublished(site.connection, loaded.declared);
    const [queryContract, evidenceContract] = await Promise.all([
      'actql-query-acquisition.json', 'actql-query-process-evidence.json',
    ].map(name => readFile(new URL(name, contractRoot), 'utf8')));
    return installedSalesforceAdapter({moon, site, authorization,
      declaration, recover, discovery, queryContract, evidenceContract,
      environment, generationCid: loaded.generationCid,
      catalogCid: loaded.declared.catalog_cid,
      connectorId: checkedProfile.connectorId,
      sourceRefs: new Set(loaded.declared.views.map(view =>
        view.source_ref))});
  } catch (error) {
    // The load's own failure stays primary; an incomplete Site release
    // travels with it to the caller.
    throw retainSalesforceSiteCleanup(site, error);
  }
}

function installedSalesforceAdapter({moon, site, authorization, declaration,
  recover, discovery, queryContract, evidenceContract, environment,
  generationCid, catalogCid, connectorId, sourceRefs}) {
  // Checked preparations this adapter issued; only these can be opened.
  const preparations = new WeakMap();
  const broadMoon = Object.freeze({
    salesforceBroadHostAttempt: moon.clientProgramSalesforceBroadAttempt,
    salesforceIssuedBroadPlan: moon.clientProgramSalesforceBroadPlan,
    salesforceIssuedBroadBegin: moon.clientProgramSalesforceBroadBegin,
    salesforceIssuedBroadNextPath: moon.clientProgramSalesforceBroadNextPath,
    salesforceIssuedBroadAcceptPage:
      moon.clientProgramSalesforceBroadAcceptPage,
    salesforceIssuedBroadComplete: moon.clientProgramSalesforceBroadComplete,
    salesforceIssuedBroadRowCount: moon.clientProgramSalesforceBroadRowCount,
    salesforceIssuedBroadFinish: moon.clientProgramSalesforceBroadFinish,
    salesforceBroadHostAbort: moon.clientProgramSalesforceBroadAbort,
    salesforceQueryPageResponseSha256:
      moon.clientProgramSalesforceQueryPageResponseSha256,
    salesforceQueryPageRowCount: moon.clientProgramSalesforceQueryPageRowCount,
    salesforceRecheckReadProjection:
      moon.clientProgramSalesforceRecheckReadProjection,
    salesforceReadProjectionScopeMatches:
      moon.clientProgramSalesforceReadProjectionScopeMatches,
  });
  const sourceAccess = Object.freeze({authorization,
    connection: site.connection});

  const decideRead = (prepared, access, signal) =>
    access.authorization.authorize('acquisition', prepared.readTuple, {
      subjectCid: cid({version: 'actql-salesforce-acquisition-read/0.1',
        requirementCid: prepared.checkedSource.requirementCid,
        physicalBinding: prepared.physicalBinding}), signal});
  // The current read decision for the prepared read. A held or denied
  // decision reads nothing.
  const currentRead = async (prepared, access, signal) => {
    const decision = await decideRead(prepared, access, signal);
    if (decision?.action !== 'dispatch') {
      throw Object.assign(new Error('ExecutionAuthorizationDenied'),
        {code: 'ExecutionAuthorizationDenied', decision});
    }
    return decision;
  };

  // Checked preparation for the Host's acquisition Checkpoint: the checked
  // source, its read tuple and the physical target an approval covers. It
  // performs no provider I/O and grants nothing.
  async function prepare({preparedProgram, registry, values, fragment,
    ordered, sourceAccess: access = sourceAccess}) {
    checked(moon.clientProgramPrepareQueryAcquisition(preparedProgram, 0, 0));
    const requirement = checked(
      moon.clientProgramPrepareLocalQueryRequirement(preparedProgram, 0, 0,
        registry, values, fragment, ordered));
    const facts = checked(
      moon.clientProgramQueryRequirementSourceEvidenceFacts(requirement));
    if (!Array.isArray(facts) || facts.length !== 6 ||
        !facts.every(value => typeof value === 'string')) {
      fail('InstalledSourceEvidenceFactsUnavailable');
    }
    const [sourceRef, sourceContractCid, carrierSchemaContractCid,
      sourceDataPolicyCid, dataClassification, sourceViewContractCid] = facts;
    if (!sourceRefs.has(sourceRef)) fail('InstalledSourceProgramMismatch');
    const [resource, ...fields] = checked(
      moon.clientProgramSalesforceSourceTarget(declaration, requirement));
    const prepared = Object.freeze({
      checkedSource: Object.freeze({
        requirementCid: moon.clientProgramQueryRequirementCid(requirement),
        sourceRef, sourceContractCid, carrierSchemaContractCid,
        sourceDataPolicyCid, dataClassification, sourceViewContractCid,
        inputContractCid:
          moon.clientProgramQueryRequirementInputContractCid(requirement),
        outputContractCid:
          moon.clientProgramQueryRequirementOutputContractCid(requirement),
      }),
      readTuple: Object.freeze({connection: site.connection, resource,
        operation: 'read'}),
      // What an approval covers: this org, connection revision, Site
      // generation, published Catalog, Resource and fields. The same checked
      // source read through another installation is another read.
      physicalBinding: Object.freeze({
        version: 'actql-installed-salesforce-target/0.1',
        org_id: site.orgId, instance_origin: site.instanceOrigin,
        site_key: site.siteKey, site_generation: site.siteGeneration,
        connection_revision: site.connectionRevision,
        catalog_cid: catalogCid, resource,
        fields: Object.freeze([...fields])}),
    });
    // A read the account denies is refused here, before any Run exists; a
    // delegated read is left to the Host's Checkpoint, or refused at
    // dispatch when none can answer it.
    const decision = await decideRead(prepared, access);
    const refused = decision?.action === 'deny'
      ? authorizationRuntimeCode(decision) : undefined;
    if (refused !== undefined) {
      throw Object.assign(new Error(refused), {code: refused,
        authorization: decision});
    }
    preparations.set(prepared, Object.freeze({preparedProgram, requirement,
      resource, access}));
    return prepared;
  }

  // Acquire the prepared read: describe the Resource under this dispatch,
  // plan and start the selected attempt in the standard runtime, read its
  // pages under one query grant, recheck the Resource, then capture. The
  // returned capture owns the live source until `close`. A failure states
  // how the acquisition ended: nothing before the first provider request
  // (the preparation check and the current read decision) starts it; after
  // it, every provider request was awaited and the attempt closed, so it
  // has stopped, unless closing the attempt itself failed.
  async function open(options) {
    const state = {started: false, closeFailed: false};
    try {
      return await acquire(state, options);
    } catch (error) {
      throw acquisitionFailure(error, !state.started ? 'not_started'
        : state.closeFailed ? 'unknown' : 'stopped');
    }
  }

  async function acquire(state, {preparedProgram, registry, values, fragment,
    ordered, sourceAccess: access = sourceAccess, signal, preparedSource}) {
    const prepared = preparedSource ?? await prepare({preparedProgram,
      registry, values, fragment, ordered, sourceAccess: access});
    const owner = preparations.get(prepared);
    if (owner === undefined || owner.preparedProgram !== preparedProgram ||
        owner.access !== access) {
      fail('InstalledSourcePreparationMismatch');
    }
    const decision = await currentRead(prepared, access, signal);
    // A read approved at the Host's Checkpoint is admitted by the Site only
    // for this installation, and must be the approval of this exact read.
    const approval = decision.basis === 'resumed_approval'
      ? site.admitCheckpointReadApproval(decision) : undefined;
    if (approval !== undefined && (approval.resource !== owner.resource ||
        approval.catalogCid !== prepared.physicalBinding.catalog_cid ||
        JSON.stringify(approval.fields) !==
          JSON.stringify(prepared.physicalBinding.fields))) {
      fail('SalesforceReadApprovalNotAdmitted');
    }
    const nonce = randomUUID();
    const runInvocationCid = cid({
      version: 'actql-salesforce-acquisition/0.1',
      requirementCid: prepared.checkedSource.requirementCid, nonce});
    const dispatchRequestCid = cid({
      version: 'actql-salesforce-acquisition-dispatch/0.1', runInvocationCid});
    const describe = async suffix => {
      const described = await site.describeForAcquisition({
        resource: owner.resource, runInvocationCid, dispatchRequestCid,
        occurrence: `${nonce}-${suffix}`, approval, signal});
      return Object.freeze({status: 'observed',
        observation: recover(described.evidence, runInvocationCid),
        observationCid: described.observationCid,
        observationJson: described.evidence.observationJson});
    };
    state.started = true;
    const current = await describe('plan');
    const acquisition = checked(moon.clientProgramPrepareSalesforceAcquisition(
      declaration, owner.requirement, current.observation, queryContract,
      evidenceContract, 4096));
    const settled = new Set();
    const run = checked(moon.clientProgramSalesforceAcquisitionStart(
      acquisition, nonce, attempt => settled.has(attempt)));
    let closed = false;
    const close = () => {
      if (closed) return;
      closed = true;
      moon.clientProgramSalesforceBroadClose(run);
    };
    try {
      const grant = site.issueGrant({operation: 'salesforce:query:read',
        decision: approval ?? decision, resource: owner.resource,
        runInvocationCid,
        dispatchRequestCid, maxUses: readLimits.maxPages});
      await readSalesforceIssuedBroad({moon: broadMoon, hostRun: run,
        apiVersion: site.apiVersion, limits: readLimits,
        maxCaptureRows: readLimits.maxTotalRows, captureLimits,
        initialAuthorization: {...grant, useId: `${nonce}-query-0`},
        authorizationForPage: async (_path, index) => ({...grant,
          useId: `${nonce}-query-${index}`}),
        credential: site.credential, refreshCatalog: () => describe('recheck'),
        signal});
      // The Site transport for this attempt has returned: its physical
      // read is settled.
      settled.add(moon.clientProgramSalesforceBroadAttempt(run));
      const capture = checked(moon.clientProgramSalesforceCapture(run));
      const source = () => checked(
        moon.clientProgramSalesforceCaptureSource(capture));
      if (moon.clientProgramCapturedSourceMatches(preparedProgram,
        source()) !== true) {
        fail('InstalledSourceProgramMismatch');
      }
      const identity = checked(
        moon.clientProgramIdentifyCapturedSourceRelation(source()));
      const logicalInput = checked(
        moon.clientProgramIssueCapturedSourceLogical(preparedProgram,
          source(), identity, owner.requirement));
      const setup = moon.clientProgramOpenCapturedLocalHost(preparedProgram,
        source(), registry, values, 1n, 0n, 0n, 0n, fragment, ordered);
      if (setup === undefined) fail('InstalledSourceHostUnavailable');
      return Object.freeze({checkedSource: prepared.checkedSource, identity,
        logicalInput, setup, capture: Object.freeze({source}),
        // Evidence is issued only while the read is still currently
        // authorized.
        issueSourceEvidence: async ({authorityScopeCid,
          effectiveDataPolicyCid}) => {
          await currentRead(prepared, access, signal);
          return checked(moon.clientProgramSalesforceIssueSourceEvidence(
            acquisition, capture, identity, logicalInput, authorityScopeCid,
            effectiveDataPolicyCid, new Date().toISOString()));
        },
        close});
    } catch (error) {
      try { close(); }
      catch { state.closeFailed = true; }
      throw error;
    }
  }

  return Object.freeze({
    realizationKey: 'salesforce-acquired',
    environmentWire: environment.wire, generationCid,
    connectorBindings: Object.freeze([
      installedSalesforceSiteBinding(site, connectorId)]),
    // The source's own read authorization for the Host's pre-acquisition
    // Checkpoint decision: the same configuration and context as the Site's.
    readAuthorization: Object.freeze({
      accountConfiguration: authorization.accountConfiguration,
      context: authorization.context}),
    sourceAccess,
    admitsSource: sourceRef => sourceRefs.has(sourceRef),
    prepare, open,
    discovery: Object.freeze({resources: discovery.resources,
      inspectResource: discovery.inspectResource,
      peekResource: discovery.peekResource}),
    close: () => site.close(),
  });
}
