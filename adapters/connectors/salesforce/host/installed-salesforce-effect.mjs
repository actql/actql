// Host-owned Salesforce Effect installation for the standard installed Host.
// The Host profile names the installed Site profile (which holds only secret
// references), the account configuration text, the connector id, the
// installed writes and the published generation. Loading performs no
// provider I/O: the published generation (declaration, execution Mappings and
// the Check Environment built from them) is restored and must reproduce
// itself against the Site as installed now.
//
// The factory projects one Values-origin Effect Unit onto the existing common
// owners: captured Results and inputs, the Effect Set Preview, the common
// apply/Ledger/Receipt/publication path and its recovery. It decides no row
// admission, retry, approval or completion. Each record write is granted only
// for the commit decision the common owner returned for the sealed Set.
import {createHash} from 'node:crypto';
import {mkdir} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {issueCompletedEffectfulComputationEvidence,
  releaseCompletedRunPreparedPayloads, storeCompletedRunResultSet} from
  '../../../host-common/completed-run-publication.mjs';
import {preparePinnedEffectSourceHoldings, preparePinnedEffectSourceSet} from
  '../../../host-node/effect-input-export.mjs';
import {verifyPinnedEffectPlan} from '../../../host-node/effect-plan-verify.mjs';
import {openEffectLedger} from '../../../host-node/effect-ledger.mjs';
import {installSalesforceAuthorization, installedSalesforceSiteBinding,
  loadInstalledSalesforceSite, releaseSalesforceSite,
  retainSalesforceSiteCleanup} from
  './installed-salesforce-site.mjs';
import {describeSalesforceGeneration, readPublicationFile,
  replacePublicationFile, restoreSalesforceGeneration,
  salesforceCheckEnvironment} from './salesforce-publication.mjs';
import {authorObservedSalesforceEffectPreview} from
  './salesforce-effect-preview.mjs';
import {installSalesforceEffectCurrentUse} from
  './salesforce-effect-current-use.mjs';
import {installSalesforceEffectDispatch} from
  './salesforce-effect-dispatch.mjs';
import {recoverCapturedSalesforceSingleRequests,
  reconcileStoredSalesforceSingleEffectWrite} from
  './salesforce-effect-write.mjs';
import {issueSalesforceEffectCapability} from
  '../site/salesforce-effect-capability.mjs';
import {observeSalesforceTargetSet} from
  '../site/salesforce-target-observation.mjs';

export const INSTALLED_SALESFORCE_EFFECT_VERSION =
  'actql-installed-salesforce-effect/0.1';
export const SALESFORCE_EFFECT_PUBLICATION_VERSION =
  'actql-salesforce-effect-publication/0.1';
const profileKeys = Object.freeze(['accountConfigurationWire', 'connectorId',
  'publicationPath', 'siteProfilePath', 'version', 'writes']);
const publicationKeys = Object.freeze(['environment_cid', 'mappings',
  'source', 'version']);
// The installed write kinds and their Effect kinds. Only Result-referencing
// writes are installed: a payload create names no Result.
const writeKinds = Object.freeze(new Map([
  ['createFromResult', 'create'], ['update', 'update'],
  ['upsert', 'upsert']]));
// The Salesforce write projection, request and capability operation codes of
// each Effect kind.
const projectionCodes = Object.freeze({create: 0, update: 1, upsert: 2});
const requestCodes = Object.freeze({create: 0, update: 1, upsert: 2});
const grantOperations = Object.freeze({create: 'salesforce:record:create',
  update: 'salesforce:record:update', upsert: 'salesforce:record:upsert'});
const limits = Object.freeze({
  maxMembers: 16, maxRows: 200, maxWork: 10_000, maxFrontierWork: 1000,
  maxFields: 100,
  preview: Object.freeze({maxWireBytes: 1_000_000, maxNodes: 100_000,
    maxDepth: 64}),
  planWork: 10_000,
  key: Object.freeze({maxBytes: 4096, maxNodes: 64, maxDepth: 8}),
  locator: Object.freeze({maxBytes: 4096, maxNodes: 64, maxDepth: 8}),
  body: Object.freeze({maxBytes: 100_000, maxNodes: 10_000, maxDepth: 16}),
  request: Object.freeze({maxPathBytes: 2048, maxTargetBytes: 1024,
    maxBodyBytes: 100_000}),
  maxIdentityBytes: 4096,
  // A single-record write reply is a few nodes; the Site admits at most 1000.
  write: Object.freeze({maxRequestBytes: 100_000, maxResponseBytes: 100_000,
    maxNodes: 1000, maxDepth: 16}),
  target: Object.freeze({maxResponseBytes: 100_000, maxNodes: 10_000,
    maxDepth: 16, maxIdentityBytes: 4096}),
  maxTotalResponseBytes: 20_000_000,
  maxRetainedBytes: 8_000_000,
  mapping: Object.freeze({maxBytes: 400_000, maxNodes: 40_000,
    maxDepth: 64}),
  declaration: Object.freeze({maxBytes: 4_000_000, maxNodes: 400_000,
    maxDepth: 64}),
});

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
// A row body, or its typed refusal when a written value is outside its
// declared type: the Resource, field, type and kind, never the value. It is
// refused before any provider I/O for the row, and nothing is rounded.
function writeBody(salesforceMoon, result, projection) {
  const refusal = result?.$tag === 0
    ? salesforceMoon.salesforceWriteValueRefusal(projection, result._0)
    : undefined;
  if (typeof refusal === 'string') {
    throw Object.assign(new Error('SalesforceWriteValueRefused'), {
      code: 'SalesforceWriteValueRefused',
      refusal: Object.freeze(JSON.parse(refusal))});
  }
  return checked(result);
}
const cid = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value)).digest('hex')}`;
const names = /^[A-Za-z_][A-Za-z0-9_]{0,254}$/u;

function checkWrite(write) {
  if (write === null || typeof write !== 'object' || Array.isArray(write) ||
      !names.test(write.resource ?? '') || !writeKinds.has(write.kind) ||
      Object.keys(write).some(key => !['resource', 'kind', 'fields', 'key',
        'sources'].includes(key)) ||
      (write.fields !== undefined && (!Array.isArray(write.fields) ||
        write.fields.length === 0 || write.fields.length > limits.maxFields ||
        !write.fields.every(field => names.test(field)))) ||
      (write.key !== undefined && !names.test(write.key)) ||
      (write.kind === 'upsert') !== (write.key !== undefined) ||
      (write.kind === 'createFromResult') !== (write.sources !== undefined) ||
      (write.kind === 'createFromResult') === (write.fields !== undefined) ||
      (write.sources !== undefined && (!Array.isArray(write.sources) ||
        write.sources.length === 0 ||
        write.sources.length > limits.maxFields ||
        !write.sources.every(source => source !== null &&
          typeof source === 'object' && names.test(source.target ?? '') &&
          text(source.field) &&
          ['reject', 'omit', 'null'].includes(source.nullBehavior))))) {
    fail('InvalidInstalledEffectProfile');
  }
  return Object.freeze({...write,
    ...(write.fields === undefined ? {} :
      {fields: Object.freeze([...write.fields])}),
    ...(write.sources === undefined ? {} : {sources: Object.freeze(
      write.sources.map(source => Object.freeze({...source})))})});
}

// Check the Host profile's shape before anything is read or installed. It
// holds no secret value or private key: the Site profile names them.
export function checkInstalledSalesforceEffectProfile(profile) {
  if (profile === null || typeof profile !== 'object' ||
      Array.isArray(profile) ||
      Object.keys(profile).sort().join('\0') !== profileKeys.join('\0') ||
      profile.version !== INSTALLED_SALESFORCE_EFFECT_VERSION ||
      !text(profile.siteProfilePath) || !isAbsolute(profile.siteProfilePath) ||
      !text(profile.publicationPath) || !isAbsolute(profile.publicationPath) ||
      !text(profile.connectorId) || !text(profile.accountConfigurationWire) ||
      !Array.isArray(profile.writes) || profile.writes.length === 0 ||
      profile.writes.length > limits.maxMembers) {
    fail('InvalidInstalledEffectProfile');
  }
  const writes = profile.writes.map(checkWrite);
  if (new Set(writes.map(write => canonicalJson(write))).size !==
      writes.length) {
    fail('InvalidInstalledEffectProfile');
  }
  return Object.freeze({...profile, writes: Object.freeze(writes)});
}

// The Resources the installed writes name, in first-write order.
const resourcesOf = profile => Object.freeze([...new Set(
  profile.writes.map(write => write.resource))]);

async function openSite(profile, {root, principalId, moon, salesforceMoon,
  runtimeBundleCid, resolveSecret, openCredentialJournal}) {
  const authorization = await installSalesforceAuthorization({
    accountConfiguration: profile.accountConfigurationWire, principalId,
    root});
  const site = await loadInstalledSalesforceSite(profile.siteProfilePath, {
    commonMoon: moon, salesforceMoon, authorization, runtimeBundleCid,
    resolveSecret, openCredentialJournal});
  return site;
}

const mappingInput = write => ({kind: write.kind,
  ...(write.fields === undefined ? {} : {fields: [...write.fields]}),
  ...(write.key === undefined ? {} : {key: write.key}),
  ...(write.sources === undefined ? {} :
    {sources: write.sources.map(source => ({...source}))})});

// The execution Mappings of the installed writes and the Check Environment,
// all from one declaration.
function generationFacts({site, salesforceMoon, declared, writes,
  baseEnvironmentWire}) {
  const mappings = writes.map(write => {
    const prepared = site.prepareExecutionMapping({
      declaration: declared.declaration, resource: write.resource,
      write: mappingInput(write), limits: limits.mapping});
    return Object.freeze({write, ...prepared});
  });
  const [schemas, capabilities] = checked(
    salesforceMoon.salesforceSourceEvidenceMembers(declared.declaration));
  const environment = salesforceCheckEnvironment(baseEnvironmentWire,
    declared, {schemas, capabilities},
    mappings.map(mapping => mapping.body));
  return {mappings, environment};
}

const publicationRecord = (source, mappings, environment) => ({
  environment_cid: environment.evidenceCid,
  mappings: mappings.map(mapping => ({mapping_cid: mapping.mappingCid,
    mapping_ref: mapping.mappingRef, write: mapping.write})),
  source,
  version: SALESFORCE_EFFECT_PUBLICATION_VERSION,
});

// The explicit publication step: describe the installed writes' Resources
// under the current metadata read decisions, generate their execution
// Mappings and the Check Environment from that one declaration, and replace
// the published generation atomically. A Host start never runs it.
export async function publishInstalledSalesforceEffect(profile, options) {
  const checkedProfile = checkInstalledSalesforceEffectProfile(profile);
  if (!text(options?.baseEnvironmentWire)) {
    fail('InvalidInstalledEffectOptions');
  }
  const site = await openSite(checkedProfile, options);
  let published;
  try {
    const {generation, declared} = await describeSalesforceGeneration({site,
      connectorId: checkedProfile.connectorId,
      resources: resourcesOf(checkedProfile), signal: options.signal});
    const {mappings, environment} = generationFacts({site,
      salesforceMoon: options.salesforceMoon, declared,
      writes: checkedProfile.writes,
      baseEnvironmentWire: options.baseEnvironmentWire});
    const body = JSON.stringify(publicationRecord(generation, mappings,
      environment));
    await replacePublicationFile(checkedProfile.publicationPath, body);
    published = Object.freeze({generationCid: (await readPublicationFile(
      checkedProfile.publicationPath)).generationCid,
    environmentCid: environment.evidenceCid,
    mappings: Object.freeze(mappings.map(mapping => Object.freeze({
      resource: mapping.write.resource, kind: mapping.write.kind,
      mappingRef: mapping.mappingRef, mappingCid: mapping.mappingCid})))});
  } catch (error) {
    throw retainSalesforceSiteCleanup(site, error);
  }
  releaseSalesforceSite(site);
  return published;
}

// Restore the published generation into `site` without provider I/O. The
// Mappings and the Check Environment must regenerate exactly from the
// restored declaration for the installed writes; any other generation, or a
// partially replaced one, is refused.
async function restoreGeneration({site, salesforceMoon, profile,
  baseEnvironmentWire}) {
  const {body, generationCid} = await readPublicationFile(
    profile.publicationPath);
  let record;
  try { record = JSON.parse(body); }
  catch (error) { fail('InvalidSalesforceEffectPublication', error); }
  if (record === null || typeof record !== 'object' ||
      Array.isArray(record) || JSON.stringify(record) !== body ||
      Object.keys(record).join('\0') !== publicationKeys.join('\0') ||
      record.version !== SALESFORCE_EFFECT_PUBLICATION_VERSION ||
      !Array.isArray(record.mappings)) {
    fail('InvalidSalesforceEffectPublication');
  }
  const {declared} = restoreSalesforceGeneration({site,
    generation: record.source, connectorId: profile.connectorId,
    resources: resourcesOf(profile)});
  const {mappings, environment} = generationFacts({site, salesforceMoon,
    declared, writes: profile.writes, baseEnvironmentWire});
  if (canonicalJson(record.mappings) !== canonicalJson(
    publicationRecord(record.source, mappings, environment).mappings) ||
      record.environment_cid !== environment.evidenceCid) {
    fail('SalesforceEffectPublicationMismatch');
  }
  return {generationCid, declared, mappings, environment};
}

// One member of the installed Effect Unit: its Program descriptor and the
// installed write whose Mapping the Program resolved. Refused before any
// provider I/O when the Program's Mapping is not an installed one.
function resolveMember(moon, prepared, installed, {stageIndex, effectId}) {
  const descriptor = checked(moon.clientProgramEffectMemberDescriptor(
    prepared, stageIndex, effectId, limits.planWork));
  const kind = descriptor._2;
  const mapping = installed.mappings.find(candidate =>
    candidate.mappingCid === descriptor._5 &&
    candidate.mappingRef === descriptor._4);
  if (mapping === undefined || writeKinds.get(mapping.write.kind) !== kind ||
      descriptor._6 === undefined) {
    fail('SalesforceEffectMappingNotInstalled');
  }
  return Object.freeze({stageIndex, effectId: descriptor._1,
    memberIndex: descriptor._0, kind, mapping,
    resource: mapping.write.resource,
    fields: Object.freeze(mapping.write.fields ??
      mapping.write.sources.map(source => source.target)),
    key: mapping.write.key ?? ''});
}

// The one Effect Unit of a compiled Values Program: its Program id, the stage
// id and index, and its Effect ids in declaration order, as compiled. A
// Program with Effects in more than one stage is not this scope.
export function salesforceEffectUnit(moon, compilation) {
  let program;
  try {
    program = JSON.parse(moon.clientProgramEffectCompilationPlanWire(
      compilation)).execution_material?.program;
  } catch (error) { fail('SalesforceEffectUnitUnsupported', error); }
  const stages = Array.isArray(program?.stages) ? program.stages : [];
  const units = stages.flatMap((stage, stageIndex) =>
    stage?.effects === undefined ? [] : [{stage, stageIndex}]);
  if (!text(program?.id) || units.length !== 1 || !text(units[0].stage.id)) {
    fail('SalesforceEffectUnitUnsupported');
  }
  const {stage, stageIndex} = units[0];
  return Object.freeze({programId: program.id, stageId: stage.id, stageIndex,
    effectIds: Object.freeze(Object.keys(stage.effects))});
}

// The members of the one Effect Unit (`unit`: the Program id, the stage id
// and index, and its Effect ids). The Program and stage ids name the logical
// items of every claim; recovery uses the same pair.
function membersOf(moon, prepared, installed, unit) {
  const effectIds = unit?.effectIds;
  if (!text(unit?.programId) || !text(unit.stageId) ||
      !Number.isSafeInteger(unit.stageIndex) || unit.stageIndex < 0 ||
      !Array.isArray(effectIds) || effectIds.length === 0 ||
      effectIds.length > limits.maxMembers ||
      new Set(effectIds).size !== effectIds.length) {
    fail('SalesforceEffectUnitUnsupported');
  }
  const members = effectIds.map(effectId => resolveMember(moon, prepared,
    installed, {stageIndex: unit.stageIndex, effectId}));
  members.sort((a, b) => a.memberIndex - b.memberIndex);
  if (members.some((member, index) => member.memberIndex !== index)) {
    fail('SalesforceEffectUnitUnsupported');
  }
  return Object.freeze(members);
}

// Every member's physical binding is fixed by the Run and its Program member:
// the dispatch its Catalog, capability and grants are bound to.
const memberDispatch = (runInvocationCid, member) => cid({
  version: 'actql-installed-salesforce-effect-dispatch/0.1',
  run_invocation_cid: runInvocationCid, effect_id: member.effectId});

function projection(salesforceMoon, observation, member) {
  const binding = JSON.parse(
    salesforceMoon.salesforceCatalogObservationJson(observation)).binding;
  return checked(salesforceMoon.salesforcePrepareWriteProjection(
    observation, binding.tenant, binding.principal, binding.environment,
    binding.connection_revision, binding.org_id, binding.site_key,
    binding.site_generation, binding.connector_registration,
    binding.connector_revision, binding.resource_origin,
    binding.run_invocation_cid, binding.dispatch_request_cid,
    binding.sync_occurrence, member.resource, projectionCodes[member.kind],
    member.key, [...member.fields], member.fields.length));
}

function mappingPolicy(member) {
  const body = JSON.parse(member.mapping.body);
  const rule = body.permission_rules?.find(item =>
    item.effect_kind === member.kind);
  if (!Array.isArray(rule?.permissions) || !text(body.minimum_approval)) {
    fail('SalesforceEffectMappingNotInstalled');
  }
  return {requiredPermissions: [...rule.permissions],
    approval: body.minimum_approval};
}

// The installed Salesforce Effect: its Check Environment and the provider
// projections of one Run over the common owners.
export async function loadInstalledSalesforceEffect(profile, {root,
  principalId, moon, salesforceMoon, baseEnvironmentWire, runtimeBundleCid,
  resolveSecret, ledgerRoot, openCredentialJournal}) {
  const checkedProfile = checkInstalledSalesforceEffectProfile(profile);
  if (!text(baseEnvironmentWire) || !text(ledgerRoot) ||
      !isAbsolute(ledgerRoot)) {
    fail('InvalidInstalledEffectOptions');
  }
  await mkdir(ledgerRoot, {recursive: true, mode: 0o700});
  const site = await openSite(checkedProfile, {root, principalId, moon,
    salesforceMoon, runtimeBundleCid, resolveSecret, openCredentialJournal});
  try {
    const installed = await restoreGeneration({site, salesforceMoon,
      profile: checkedProfile, baseEnvironmentWire});
    return installedSalesforceEffect({moon, salesforceMoon, site,
      installed, ledgerRoot, connectorId: checkedProfile.connectorId});
  } catch (error) {
    // The load's own failure stays primary; an incomplete Site release
    // travels with it to the caller.
    throw retainSalesforceSiteCleanup(site, error);
  }
}

function installedSalesforceEffect({moon, salesforceMoon, site, installed,
  ledgerRoot, connectorId}) {
  const effect = runtimeCore(moon).effectApplicationControl;
  let occurrence = 0;
  const nextOccurrence = label => `effect-${label}-${Date.now()}-${
    occurrence++}`;
  const openLedger = identity => openEffectLedger({moon, root: ledgerRoot,
    authorityScopeCid: moon.clientRequestAuthorityScopeCid(identity),
    callerRequestId: moon.clientRequestCallerId(identity),
    maxEntryBytes: 1_000_000});
  const scopes = members => Object.freeze(members.map(member =>
    Object.freeze({connection: site.connection, resource: member.resource})));

  // A current check read of each guarded member's targets: its own read
  // decision on the Site gate under `subjectCid`, then one-use grants.
  const checkReadAuthority = async (member, runInvocationCid,
    dispatchRequestCid, subjectCid, signal) => {
    const decision = await site.authorization.authorize('acquisition', {
      connection: site.connection, resource: member.resource,
      operation: 'read'}, {subjectCid, signal});
    if (decision?.action !== 'dispatch') {
      throw Object.assign(new Error('SalesforceEffectTargetReadNotAuthorized'),
        {code: 'SalesforceEffectTargetReadNotAuthorized',
          action: decision?.action});
    }
    let use = 0;
    return async rowIndex => ({...site.issueGrant({
      operation: 'salesforce:record:observe', decision,
      resource: member.resource, runInvocationCid, dispatchRequestCid}),
    useId: `${dispatchRequestCid}-check-${subjectCid}-${rowIndex}-${use++}`});
  };

  // One member's current Catalog: a describe of exactly its Resource bound
  // to its dispatch.
  const describe = (member, runInvocationCid, dispatchRequestCid, label,
    signal) => site.describeEffectCatalog({resources: [member.resource],
    runInvocationCid, dispatchRequestCid,
    occurrence: nextOccurrence(label), signal});

  // The capability of a member's requests: the Site's attestation of its
  // installed runtime and connection for the dispatch, and the member's
  // current execution Mapping.
  const capabilityOf = (member, requests, observation, runInvocationCid,
    dispatchRequestCid) => issueSalesforceEffectCapability({
    moon: salesforceMoon, requests, currentObservation: observation,
    authority: site.attestEffectCapability({
      operation: grantOperations[member.kind], runInvocationCid,
      dispatchRequestCid}),
    credential: site.credential, mapping: member.mapping.mapping,
    maxRows: limits.maxRows, maxBytes: limits.preview.maxWireBytes});

  // The whole-set commit decisions of one claim generation, by Host tuple.
  // Only a dispatch for the sealed Set, at the Effect commit boundary, for
  // exactly this installation's connection admits that tuple's writes.
  const commitDecisions = (decisions, subjectCid, members) => {
    const byResource = new Map();
    for (const decision of decisions ?? []) {
      if (decision?.action !== 'dispatch' ||
          decision.boundary !== 'effect_commit' ||
          decision.subjectCid !== subjectCid ||
          decision.tuple?.connection !== site.connection ||
          decision.tuple?.operation !== 'effect' ||
          byResource.has(decision.tuple.resource)) {
        fail('SalesforceEffectCommitNotAuthorized');
      }
      byResource.set(decision.tuple.resource, decision);
    }
    for (const member of members) {
      if (!byResource.has(member.resource)) {
        fail('SalesforceEffectCommitNotAuthorized');
      }
    }
    return byResource;
  };

  // Current use and physical dispatch over one set of members. The check
  // reads are decided on the Site gate under the sealed Set; every write
  // grant follows the claim generation's commit decision for its tuple.
  const physicalRoute = ({members, requests, runInvocationCid, dispatches,
    subjectCid, observedRows, applyPreview, ledger}) => {
    let currentUse;
    const current = async ({signal, preflight}) => {
      const capabilities = [];
      const targets = [];
      const catalogs = [];
      for (const [index, member] of members.entries()) {
        // The installed Mapping of this member must still be the one the
        // Preview resolved.
        const now = installed.mappings.find(mapping =>
          mapping.mappingCid === member.mapping.mappingCid);
        if (now === undefined) fail('SalesforceEffectMappingNotInstalled');
        // Check reads are decided before this refresh's provider I/O.
        targets.push(member.kind === 'create' ? undefined : {
          authorizationForRow: await checkReadAuthority(member,
            runInvocationCid, dispatches[index], subjectCid, signal),
          credential: site.credential, limits: limits.target});
      }
      for (const [index, member] of members.entries()) {
        // One describe per member serves this refresh's capability and
        // current-use recheck.
        const catalog = await describe(member, runInvocationCid,
          dispatches[index], `apply-${index}`, signal);
        catalogs.push(catalog);
        capabilities.push(capabilityOf(member, requests[index],
          catalog.observation, runInvocationCid, dispatches[index]));
      }
      currentUse = installSalesforceEffectCurrentUse({moon: salesforceMoon,
        commonMoon: moon, observedRows,
        members: members.map((member, index) => ({
          requests: requests[index], capability: capabilities[index],
          refreshCatalog: async () => catalogs[index],
          target: targets[index]})),
        maxMembers: limits.maxMembers, maxRows: limits.maxRows,
        maxTotalResponseBytes: limits.maxTotalResponseBytes});
      return currentUse.refreshPreflight({signal, preflight});
    };
    const bindDispatch = ({members: claims, subjectCid: active, signal,
      decisions}) => {
      if (active !== subjectCid || currentUse === undefined) {
        fail('InvalidSalesforceEffectRoute');
      }
      const commits = commitDecisions(decisions, subjectCid, members);
      return installSalesforceEffectDispatch({commonMoon: moon,
        moon: salesforceMoon, ledger, admittedPreview: applyPreview,
        currentUse, signal,
        members: members.map((member, index) => ({
          requests: requests[index], claims: claims[index].claims,
          authorizationForRow: rowIndex => ({...site.issueGrant({
            operation: grantOperations[member.kind],
            decision: commits.get(member.resource),
            resource: member.resource, runInvocationCid,
            dispatchRequestCid: dispatches[index], subjectCid}),
          useId: `${dispatches[index]}-write-${subjectCid}-${rowIndex}`}),
          credential: site.credential, limits: limits.write}))});
    };
    return {current, bindDispatch};
  };

  const basePreflight = ({effects, members, requestScope, keys}) => ({
    sources: effects.map(member => member.source_binding_cid),
    // The installed Mapping of each member now, as rechecked by `current`.
    contracts: members.map(member => member.mapping.mappingCid),
    capabilities: effects.map(member => member.capability_evidence_cid),
    authorities: effects.map(() => moon.clientProgramEffectRequestAuthority(
      requestScope)),
    observedRows: [], guardVersions: [], routes: [],
    // No risk acceptance is held in this scope (halt on item failure, or
    // the Program's declared continue); these fields are read only with a
    // risk body.
    risk: undefined, reviewProjectionCid: '', authorityScopeCid: '',
    policyCid: '', validityCid: '', issuerCid: '', authenticationCid: '',
    issuerKind: '', decision: '',
    requestScope, ...(keys === undefined ? {} : {keys}),
    maxMembers: members.length, maxRows: limits.maxRows,
    maxFootprintWork: limits.maxRows, maxWork: limits.maxWork,
  });

  const continuationOf = (plan, unit, members, dispatches) => canonicalJson({
    version: 'actql-installed-salesforce-effect-continuation/0.1',
    publication_generation_cid: installed.generationCid,
    program_id: unit.programId, stage_id: unit.stageId,
    request: plan.request, attempt: plan.attempt,
    members: members.map((member, index) => ({
      effect_id: member.effectId, mapping_cid: member.mapping.mappingCid,
      dispatch_request_cid: dispatches[index]}))});

  // Capture a completed Values computation as one Effect Unit: store its
  // Results and pinned inputs, author the Salesforce Preview from the
  // current Catalog and target check reads, and return the provider stage
  // the common owner applies after the whole-set commit decision.
  async function prepareCaptured({moon: runMoon, control, store, execution,
    checkedHost, prepared, identity, plan, previewContext, unit,
    authorizeEvidenceRead, signal}) {
    if (runMoon !== moon || !plan || !previewContext || !execution ||
        !checkedHost || !prepared || !identity) {
      fail('InvalidInstalledEffectCapture');
    }
    signal?.throwIfAborted();
    // Members and their installed Mappings, before any Store or provider
    // I/O.
    const members = membersOf(moon, prepared, installed, unit);
    const runInvocationCid = plan.invocation.identity;
    const dispatches = members.map(member =>
      memberDispatch(runInvocationCid, member));
    const requestScope = moon.clientProgramEffectRequestScope(prepared,
      identity);
    const storedResults = await storeCompletedRunResultSet({execution,
      store, control, runDefinition: plan.runDefinition,
      invocation: plan.invocation, results: plan.results,
      outputLimits: plan.outputLimits, contractLimits: plan.contractLimits});
    // Until the stage is returned, this capture owns the unpublished
    // payloads it prepared. A failure releases them and keeps its own cause;
    // a failed release is attached, never substituted.
    let sourceSet;
    try {
      return await captureStage({control, store, execution, checkedHost,
        prepared, identity, plan, previewContext, unit, members,
        runInvocationCid, dispatches, requestScope, storedResults,
        authorizeEvidenceRead, signal, own: value => { sourceSet = value; }});
    } catch (error) {
      try {
        for (const payload of sourceSet?.payloads ?? []) {
          if (payload.prepared.status().pending) {
            await payload.prepared.release();
          }
        }
        await releaseCompletedRunPreparedPayloads(storedResults, control);
      } catch (cleanupError) {
        if (error !== null && typeof error === 'object') {
          error.cleanupFailure ??= cleanupError;
        }
      }
      throw error;
    }
  }

  async function captureStage({control, store, execution, checkedHost,
    prepared, identity, plan, previewContext, unit, members,
    runInvocationCid, dispatches, requestScope, storedResults,
    authorizeEvidenceRead, signal, own}) {
    const inputs = checked(moon.clientProgramPinEffectSources(checkedHost,
      members.length));
    const proposals = members.map(() => []);
    const sourceSet = await preparePinnedEffectSourceSet({moon,
      checkedOwner: prepared, execution, inputs,
      maxMembers: members.length, maxGroupingWork: members.length * 2,
      limits: moon.clientProgramEffectInputExportLimits(
        ...exportLimits(plan.outputLimits)),
      store, maxBytes: plan.outputLimits.maxWireBytes, control,
      invocation: plan.invocation, retention: plan.results[0].retention,
      sourceBindingCid: cid({
        version: 'actql-installed-salesforce-effect-source/0.1',
        run_invocation_cid: runInvocationCid,
        store_authority_cid: store.storeAuthorityCid}),
      contractLimits: plan.contractLimits,
      localEvidenceContext: plan.localEvidenceContext,
      proposalLimits: {maxFields: limits.maxFields, maxWork: limits.maxWork,
        maxBytes: limits.body.maxBytes, maxNodes: limits.body.maxNodes,
        maxDepth: limits.body.maxDepth,
        maxUtf16Units: limits.body.maxBytes},
      onProposalRow(memberIndex, rowIndex, proposal) {
        if (rowIndex !== proposals[memberIndex]?.length ||
            rowIndex >= limits.maxRows) {
          fail('SalesforceEffectRowLimit');
        }
        proposals[memberIndex].push(proposal);
      },
      signal});
    own(sourceSet);
    // Target check reads are decided before any provider I/O: a held or
    // denied read authors no Preview.
    const checkSubject = member => cid({
      version: 'actql-salesforce-effect-target-check/0.1',
      run_invocation_cid: runInvocationCid, effect_id: member.effectId});
    const checkReads = [];
    for (const [index, member] of members.entries()) {
      checkReads.push(member.kind === 'create' ? undefined :
        await checkReadAuthority(member, runInvocationCid, dispatches[index],
          checkSubject(member), signal));
    }
    const catalogs = [];
    let requests = [];
    const capabilities = [];
    const observations = [];
    for (const [index, member] of members.entries()) {
      const catalog = await describe(member, runInvocationCid,
        dispatches[index], `preview-${index}`, signal);
      catalogs.push(catalog);
      const project = projection(salesforceMoon, catalog.observation, member);
      const memberRequests = proposals[index].map(proposal => {
        const body = writeBody(salesforceMoon,
          salesforceMoon.salesforcePrepareExecutionWriteBody(
          member.mapping.mapping, project, Buffer.from(JSON.stringify(
            JSON.parse(proposal.changesWire).value)),
          limits.body.maxBytes, limits.body.maxNodes, limits.body.maxDepth),
        project);
        return checked(salesforceMoon.salesforcePrepareSingleWriteRequest(
          body, site.apiVersion, requestCodes[member.kind],
          member.kind === 'create' ? '' : JSON.parse(proposal.selectorWire),
          0, limits.request.maxPathBytes, limits.request.maxTargetBytes,
          limits.request.maxBodyBytes));
      });
      if (memberRequests.length === 0) fail('SalesforceEffectEmptyMember');
      requests.push(memberRequests);
      capabilities.push(capabilityOf(member, memberRequests,
        catalog.observation, runInvocationCid, dispatches[index]));
      observations.push(member.kind === 'create' ? undefined :
        (await observeSalesforceTargetSet({moon: salesforceMoon, members: [{
          requests: memberRequests, currentCatalog: catalog.observation,
          authorizationForRow: checkReads[index], credential: site.credential,
          limits: limits.target}], maxMembers: 1, maxRows: limits.maxRows,
        maxTotalResponseBytes: limits.maxTotalResponseBytes, signal}))[0]);
    }
    const payloads = sourceSet.members.map(member => member.payload);
    const preview = authorObservedSalesforceEffectPreview({moon,
      salesforceMoon, control, prepared, inputs,
      context: {runDefinition: previewContext.runDefinition,
        runInvocation: previewContext.runInvocation,
        compiledPlan: previewContext.compiledPlan,
        storeAuthorityCid: store.storeAuthorityCid, modelDerived: false},
      requestScope,
      members: members.map((member, index) => ({
        stageIndex: member.stageIndex, effectId: member.effectId,
        requests: requests[index], observations: observations[index],
        localResultArtifact: payloads[index].localResultArtifact,
        sourceArtifact: payloads[index].summary.artifact,
        capability: capabilities[index], ...mappingPolicy(member),
        maxItems: requests[index].length, previewStrength: 'full_diff'})),
      maxWireBytes: limits.preview.maxWireBytes,
      maxNodes: limits.preview.maxNodes, maxDepth: limits.preview.maxDepth,
      maxRows: limits.maxRows, maxIdentityBytes: limits.maxIdentityBytes,
      maxKeyBytes: limits.key.maxBytes, maxKeyNodes: limits.key.maxNodes,
      maxKeyDepth: limits.key.maxDepth,
      planLimits: {maxFields: limits.maxFields, maxWork: limits.planWork,
        maxBytes: limits.preview.maxWireBytes,
        maxNodes: limits.preview.maxNodes,
        maxDepth: limits.preview.maxDepth}});
    // Created rows are applied in the Preview's canonical row order.
    requests = requests.map((memberRequests, index) =>
      preview.requestOrder[index].map(row => memberRequests[row]));
    const body = JSON.parse(preview.wire);
    const authoringContext = control.admitRunEvidence('authoring_context',
      canonicalJson(body.authoring_context), plan.contractLimits);
    const admittedPreview = control.admitEffectComputationPreview(
      preview.wire, plan.runDefinition, authoringContext,
      plan.contractLimits);
    const holdings = await preparePinnedEffectSourceHoldings({
      sources: sourceSet, store, control, preview: admittedPreview,
      invocation: plan.invocation}).commit();
    const previewInputs = checked(moon.clientProgramBindEffectPreviewInputs(
      checkedHost, inputs, previewContext.runInvocation, 0, preview.wire,
      preview.authoringCid, moon.clientProgramEffectPreviewInputLimits(
        limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth, limits.maxWork, limits.maxFields,
        limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth, members.length, limits.maxRows,
        limits.maxWork, limits.maxWork)));
    const plans = [];
    for (const member of members) {
      if (member.kind === 'create') continue;
      const chunks = [];
      const verified = await verifyPinnedEffectPlan({moon, execution,
        previewInputs, previewIndex: member.memberIndex,
        limits: moon.clientProgramEffectInputExportLimits(
          ...exportLimits(plan.outputLimits)),
        planLimits: {maxFields: limits.maxFields, maxWork: limits.planWork,
          maxBytes: limits.preview.maxWireBytes,
          maxNodes: limits.preview.maxNodes,
          maxDepth: limits.preview.maxDepth,
          maxUtf16Units: limits.preview.maxWireBytes},
        onChunk: chunk => { chunks.push(chunk); }, signal});
      plans.push({name: member.effectId, wire: chunks.join(''),
        proof: verified.proof});
    }
    const computation = await issueCompletedEffectfulComputationEvidence({
      execution, store, storedResults, control, admission: plan.admission,
      runDefinition: plan.runDefinition, invocation: plan.invocation,
      observation: plan.observation,
      normalizationJournal: plan.normalizationJournal, authoringContext,
      receiptEvidence: plan.receiptEvidence,
      captureEvidence: plan.captureEvidence, preview: admittedPreview,
      plans: plans.map(({name, wire}) => ({name, wire})),
      effectSourceHoldings: holdings,
      connectorRecovery: members.map((member, index) => ({
        memberIndex: index, kind: 'salesforce-named-catalog',
        observationCid: catalogs[index].observationCid,
        wire: JSON.stringify({evidence: catalogs[index].evidence,
          apiVersion: site.apiVersion, resourceName: member.resource,
          operation: member.kind, externalTargetField: member.key,
          fieldNames: [...member.fields],
          resourceOrigin: site.instanceOrigin})})),
      contractLimits: plan.contractLimits});
    for (const payload of sourceSet.payloads) {
      if (payload.prepared.status().pending) await payload.prepared.release();
    }
    const ledger = openLedger(identity);
    try {
      const applyPreview = effect.admitPreviewIdentity(preview.wire,
        body.run_identity_cid, preview.authoringCid, requestScope,
        preview.keys, limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth);
      const unitCid = cid({version: 'actql-installed-salesforce-effect-unit/0.1',
        run_definition_cid: plan.runDefinition.identity,
        stage_index: members[0].stageIndex});
      const claims = body.effects.map((member, memberIndex) => ({
        claims: member.changes.map((change, rowIndex) => {
          const key = preview.keys[memberIndex][rowIndex];
          const locator = effect.logicalItemLocator(requestScope,
            unit.programId, unit.stageId, member.effect_id,
            canonicalJson(change.target_row_identity),
            limits.locator.maxBytes, limits.key.maxBytes,
            limits.key.maxNodes, limits.key.maxDepth);
          const canonicalRequestCid = checked(
            salesforceMoon.salesforceSingleWriteRequestCid(
              requests[memberIndex][rowIndex], site.instanceOrigin,
              limits.maxIdentityBytes));
          const basis = effect.ledgerBasis(requestScope, locator, key,
            unitCid, member.effect_member_preview_cid,
            change.row_preview_cid, canonicalRequestCid,
            cid({version: 'actql-installed-salesforce-effect-recovery/0.1',
              dispatch_request_cid: dispatches[memberIndex]}),
            // A Salesforce single-record write carries no provider
            // idempotency key.
            'unavailable', member.capability_evidence_cid,
            plan.results[0].retention.identity);
          return {scope: requestScope, locator, key, basis,
            intentFingerprintCid: change.row_preview_cid,
            canonicalRequestCid};
        })}));
      const observedRows = body.effects.flatMap(member =>
        member.effect_kind === 'create' ? [] : member.row_order);
      const route = physicalRoute({members, requests, runInvocationCid,
        dispatches, subjectCid: moon.clientProgramEffectApplySubjectCid(
          previewInputs), observedRows, applyPreview, ledger});
      const preflight = {proofs: plans.map(item => item.proof),
        ...basePreflight({effects: body.effects, members, requestScope,
          keys: preview.keys})};
      return Object.freeze({preview: admittedPreview, computation,
        storedResults,
        apply: {moon, capturedInputs: previewInputs, preflight, ledger,
          members: claims, maxFrontierWork: limits.maxFrontierWork,
          refreshPreflight: route.current, bindDispatch: route.bindDispatch,
          authorization: {gate: site.authorization, scopes: scopes(members)}},
        receipt: {ledger, preview: applyPreview, commonMoon: moon,
          publicationPreview: admittedPreview,
          authorizeEvidenceRead: authorizeEvidenceRead ?? (async () => true),
          members: claims.map(member => ({rowOwners: member.claims.map(
            claim => ({claim})), replayed: false})),
          limits: plan.contractLimits},
        publication: {execution, store, storedResults, control, computation,
          preview: admittedPreview, ledger, request: plan.request,
          attempt: plan.attempt, contractLimits: plan.contractLimits,
          now: plan.now},
        scopes: scopes(members),
        continuationWire: continuationOf(plan, unit, members, dispatches),
        dispose: () => ledger.close()});
    } catch (error) {
      ledger.close();
      throw error;
    }
  }

  // Continue a recovered capture: the exact saved Preview, requests rebuilt
  // from its rows and the retained describes, and the Ledger's durable
  // claims. The installation must still be the one the Preview was authored
  // against: a changed Mapping, Site generation, connection or runtime is
  // refused before any provider I/O.
  // Recovery acquires one local resource, its Effect Ledger handle. The
  // handle's owner is given to `retainRecoveryOwner` (the Host's recovery
  // custody) before any step that can fail, and is the stage's
  // `cleanupOwner`; the Host, not this function, closes it on failure.
  function prepareRecovered({moon: runMoon, control, store, recovered,
    continuation, authorizeEvidenceRead, contractLimits, signal,
    retainRecoveryOwner}) {
    if (runMoon !== moon || !recovered?.computation || !continuation ||
        !contractLimits) {
      fail('InvalidInstalledEffectRecovery');
    }
    signal?.throwIfAborted();
    const provider = continuation.provider ?? continuation;
    if (provider?.version !==
          'actql-installed-salesforce-effect-continuation/0.1' ||
        !Array.isArray(provider.members) || !text(provider.program_id) ||
        !text(provider.stage_id)) {
      fail('InstalledEffectContinuationMismatch');
    }
    const {requestIdentity, requestScope, computation: durable} = recovered;
    const {computation, preview, storedResults} = durable;
    const previewWire = control.effectComputationPreviewWire(preview);
    const body = JSON.parse(previewWire);
    if (body.effects.length !== provider.members.length) {
      fail('InstalledEffectContinuationMismatch');
    }
    const members = Object.freeze(body.effects.map((member, index) => {
      const saved = provider.members[index];
      const mapping = installed.mappings.find(candidate =>
        candidate.mappingCid === member.resolved_mapping_contract_cid);
      if (saved?.effect_id !== member.effect_id ||
          saved.mapping_cid !== member.resolved_mapping_contract_cid) {
        fail('InstalledEffectContinuationMismatch');
      }
      if (mapping === undefined ||
          writeKinds.get(mapping.write.kind) !== member.effect_kind) {
        fail('SalesforceEffectMappingNotInstalled');
      }
      return Object.freeze({effectId: member.effect_id,
        memberIndex: index, kind: member.effect_kind, mapping,
        resource: mapping.write.resource,
        fields: Object.freeze(mapping.write.fields ??
          mapping.write.sources.map(source => source.target)),
        key: mapping.write.key ?? ''});
    }));
    const runInvocationCid = body.invocation_cid;
    const dispatches = members.map(member =>
      memberDispatch(runInvocationCid, member));
    if (dispatches.some((dispatch, index) =>
      dispatch !== provider.members[index].dispatch_request_cid)) {
      fail('InstalledEffectContinuationMismatch');
    }
    const admitted = control.effectComputationPreviewLedgerIdentity(preview);
    const keys = effect.recoveredPreviewKeys(admitted, requestScope,
      members.length, limits.maxRows, limits.maxWork, limits.key.maxBytes,
      limits.key.maxNodes, limits.key.maxDepth);
    const applyPreview = effect.admitPreviewIdentity(previewWire,
      body.run_identity_cid, body.authoring_context.authoring_context_cid,
      requestScope, keys, limits.preview.maxWireBytes,
      limits.preview.maxNodes, limits.preview.maxDepth);
    const ledger = openLedger(requestIdentity);
    let closed = false;
    const ledgerOwner = Object.freeze({
      async close() { closed = true; ledger.close(); },
      async cleanup() { closed = true; ledger.close(); return true; },
      cleanupPending: () => !closed});
    if (retainRecoveryOwner !== undefined) {
      try { retainRecoveryOwner(ledgerOwner); }
      catch (error) { ledger.close(); throw error; }
    }
    try {
      const recorded = ledger.recoverClaimFacts({preview: admitted,
        scope: requestScope, programId: provider.program_id,
        nodeId: provider.stage_id, maxRows: limits.maxRows,
        maxWork: limits.maxWork});
      const rebuilt = recoverCapturedSalesforceSingleRequests({
        moon: salesforceMoon, recovered: durable, recorded, previewWire,
        runIdentityCid: body.run_identity_cid,
        authoringContextCid: body.authoring_context.authoring_context_cid,
        previewLimits: limits.preview, bodyLimits: limits.body,
        requestLimits: limits.request, maxMembers: limits.maxMembers,
        maxRows: limits.maxRows, maxRetainedBytes: limits.maxRetainedBytes});
      // The Site as installed now must attest the same capability the
      // Preview carries, for the same requests, before any provider I/O.
      members.forEach((member, index) => {
        let capability;
        try {
          capability = capabilityOf(member, rebuilt.requests[index],
            rebuilt.catalogs[index], runInvocationCid, dispatches[index]);
        } catch (error) {
          fail('SalesforceEffectInstallationChanged', error);
        }
        if (capability.identity !== body.effects[index]
          .capability_evidence_cid) {
          fail('SalesforceEffectInstallationChanged');
        }
      });
      const observedRows = body.effects.flatMap(member =>
        member.effect_kind === 'create' ? [] : member.row_order);
      const route = physicalRoute({members, requests: rebuilt.requests,
        runInvocationCid, dispatches,
        subjectCid: control.effectComputationPreviewSemanticCid(preview),
        observedRows, applyPreview, ledger});
      const evidenceRead = authorizeEvidenceRead ?? (async () => true);
      const reconcileStoredResponses = async ({members: claims,
        preview: ledgerPreview}) => {
        for (const [memberIndex, member] of claims.entries()) {
          for (const [rowIndex, claim] of member.claims.entries()) {
            const stored = ledger.readClaimedResponse(claim);
            if (stored === undefined) continue;
            await reconcileStoredSalesforceSingleEffectWrite({ledger,
              commonMoon: moon, admittedPreview: ledgerPreview, memberIndex,
              rowIndex, rowPreviewCid:
                body.effects[memberIndex].changes[rowIndex].row_preview_cid,
              claim, moon: salesforceMoon,
              request: rebuilt.requests[memberIndex][rowIndex],
              resourceOrigin: site.instanceOrigin,
              authorizeEvidenceRead: evidenceRead, limits: limits.write,
              maxRequestIdentityBytes: limits.maxIdentityBytes});
          }
        }
      };
      return Object.freeze({preview, computation, storedResults,
        apply: {moon, store, publicationControl: control, computation,
          preview, ledger, requestScope, programId: provider.program_id,
          nodeId: provider.stage_id, maxRows: limits.maxRows,
          maxFrontierWork: limits.maxFrontierWork,
          maxRecoveryWork: limits.maxWork,
          keyLimits: {...limits.key, maxWork: limits.maxWork},
          reconcileStoredResponses,
          refreshPreflight: ({signal: refreshSignal} = {}) => route.current({
            signal: refreshSignal, preflight: basePreflight({
              effects: body.effects, members, requestScope})}),
          bindDispatch: route.bindDispatch,
          authorization: {gate: site.authorization, scopes: scopes(members)}},
        receipt: {ledger, preview: applyPreview, commonMoon: moon,
          publicationPreview: preview,
          authorizeEvidenceRead: evidenceRead,
          members: recorded.members.map(member => ({rowOwners:
            member.claims.map(claim => ({claim})), replayed: true})),
          limits: contractLimits},
        publication: {execution: null, store, storedResults, control,
          computation, preview, ledger, request: provider.request,
          // The saved attempt omits an absent idempotency key; the
          // publication owner reads it as a present field.
          attempt: {...provider.attempt, externalIdempotencyKey:
            provider.attempt?.externalIdempotencyKey}, contractLimits,
          now: () => new Date().toISOString()},
        scopes: scopes(members),
        continuationWire: canonicalJson(provider),
        cleanupOwner: ledgerOwner,
        dispose: () => { closed = true; ledger.close(); }});
    } catch (error) {
      // Without a Host custody the handle is this function's to release.
      if (retainRecoveryOwner === undefined) ledger.close();
      throw error;
    }
  }

  return Object.freeze({
    environmentWire: installed.environment.wire,
    generationCid: installed.generationCid,
    connectorBindings: Object.freeze([
      installedSalesforceSiteBinding(site, connectorId)]),
    connection: site.connection,
    mappings: Object.freeze(installed.mappings.map(mapping => Object.freeze({
      resource: mapping.write.resource, kind: mapping.write.kind,
      target: JSON.parse(mapping.body).target_ref,
      mappingRef: mapping.mappingRef, mappingCid: mapping.mappingCid}))),
    prepareCaptured, prepareRecovered,
    close: () => site.close(),
  });
}

const exportLimits = output => [output.maxResultFields,
  output.maxResultMappingWork, output.maxResultOrderWork,
  output.maxResultWorkspaceEntries, output.maxRows, output.maxValueNodes,
  output.maxValueTextBytes, output.maxValueDepth, output.maxValueWork,
  output.maxWireBytes, output.maxWireNodes, output.maxWireDepth,
  output.maxColumns, output.maxOrderWork, output.maxLogicalWireBytes,
  output.maxLogicalWireNodes, output.maxLogicalWireDepth,
  output.maxSchemaFields, output.maxSchemaBytes, output.maxSchemaNodes,
  output.maxSchemaDepth, output.maxBatchBytes];
