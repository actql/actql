// Host-owned Salesforce Effect installation for the standard installed Host.
// The Host profile names the installed Site profile (which holds only secret
// references), the account configuration text, the connector id, the
// installed writes and the published generation. Loading performs no
// provider I/O: the published generation (declaration, execution Mappings and
// the Check Environment built from them) is restored and must reproduce
// itself against the Site as installed now.
//
// Every Effect Set of this installation runs on the Host's provider-neutral
// installed row Effect (adapters/host-node/installed-row-effect.mjs) with
// Salesforce's write driver (salesforce-write-driver.mjs) and this
// connector's registered identity profile; this module keeps only the
// installation: its profile, publication, restore and target-read inventory.
import {mkdir} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {installSalesforceAuthorization, installedSalesforceSiteBinding,
  loadInstalledSalesforceSite, releaseSalesforceSite,
  retainSalesforceSiteCleanup} from
  './installed-salesforce-site.mjs';
import {describeSalesforceGeneration, readPublicationFile,
  replacePublicationFile, restoreSalesforceGeneration,
  salesforceCheckEnvironment} from './salesforce-publication.mjs';
import {createInstalledRowEffect} from
  '../../../host-node/installed-row-effect.mjs';
import {installedConnectors} from
  '../../../connectors-builtin/installations.generated.mjs';
import {salesforceRowEffectSite, salesforceWriteDriver} from
  './salesforce-write-driver.mjs';

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
const limits = Object.freeze({
  maxMembers: 16, maxRows: 200, maxWork: 10_000, maxFrontierWork: 1000,
  // Result outputs pinned for one Effect Unit: its members' sources plus
  // the upstream Stage Results they import (an acquired Program computes
  // in a Stage after its acquisition). A ceiling, not a reservation.
  maxPinnedResults: 64,
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
const requiredEffectRuntime = Object.freeze([
  'salesforcePrepareExecutionWriteBody', 'salesforceWriteValueRefusal',
  'salesforceSingleWriteRequestValue']);
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

// Resolve target reads from the checked Program and restored installation
// before computation or provider I/O. Preserve every member binding even
// when several members share an authorization tuple.
export function salesforceEffectTargetReadInventory({moon, prepared, unit,
  installed, site, connectorId}) {
  const members = membersOf(moon, prepared, installed, unit);
  const siteBinding = installedSalesforceSiteBinding(site, connectorId);
  return Object.freeze(members.map(member => Object.freeze({
    readTuple: Object.freeze({connection: site.connection,
      resource: member.resource, operation: 'read'}),
    physicalBinding: Object.freeze({
      version: 'actql-installed-salesforce-effect-target-read/0.1',
      site_binding_cid: siteBinding.bindingCid,
      generation_cid: installed.generationCid,
      program_id: unit.programId, stage_id: unit.stageId,
      stage_index: member.stageIndex, effect_id: member.effectId,
      member_index: member.memberIndex, mapping_cid: member.mapping.mappingCid,
      mapping_ref: member.mapping.mappingRef, resource: member.resource,
      effect_kind: member.kind, key: member.key,
      fields: Object.freeze([...member.fields]),
    }),
  })));
}

// The installed Salesforce Effect: its Check Environment and the provider
// projections of one Run over the common owners.
export async function loadInstalledSalesforceEffect(profile, {root,
  principalId, moon, salesforceMoon, baseEnvironmentWire, runtimeBundleCid,
  resolveSecret, ledgerRoot, openCredentialJournal, openRowEffectLedger}) {
  const checkedProfile = checkInstalledSalesforceEffectProfile(profile);
  if (!text(baseEnvironmentWire) || !text(ledgerRoot) ||
      !isAbsolute(ledgerRoot)) {
    fail('InvalidInstalledEffectOptions');
  }
  // The row body, its value refusal and the Preview's row value are part of
  // this Effect's runtime; a runtime without any of them is refused before
  // any provider I/O. The Preview never falls back to the provider body.
  if (requiredEffectRuntime.some(name =>
    typeof salesforceMoon?.[name] !== 'function')) {
    fail('InvalidSalesforceEffectRuntime');
  }
  await mkdir(ledgerRoot, {recursive: true, mode: 0o700});
  const site = await openSite(checkedProfile, {root, principalId, moon,
    salesforceMoon, runtimeBundleCid, resolveSecret, openCredentialJournal});
  try {
    const installed = await restoreGeneration({site, salesforceMoon,
      profile: checkedProfile, baseEnvironmentWire});
    return await installedSalesforceEffect({moon, salesforceMoon, site,
      installed, ledgerRoot, connectorId: checkedProfile.connectorId,
      accountConfiguration: checkedProfile.accountConfigurationWire,
      runtimeBundleCid, openRowEffectLedger});
  } catch (error) {
    // The load's own failure stays primary; an incomplete Site release
    // travels with it to the caller.
    throw retainSalesforceSiteCleanup(site, error);
  }
}

async function installedSalesforceEffect({moon, salesforceMoon, site,
  installed, ledgerRoot, connectorId, accountConfiguration,
  runtimeBundleCid, openRowEffectLedger: openRowLedger}) {
  let occurrence = 0;
  const nextOccurrence = label => `effect-${label}-${Date.now()}-${
    occurrence++}`;
  const siteBindingCid = installedSalesforceSiteBinding(site, connectorId)
    .bindingCid;
  // Every Set runs on the Host's provider-neutral installed row Effect,
  // under this connector's registered identity profile, so a Run captured
  // before the move to it keeps its identities.
  const rowEffect = await createInstalledRowEffect({moon,
    mappings: installed.mappings.map(mapping => ({
      resource: mapping.write.resource, mappingRef: mapping.mappingRef,
      mappingCid: mapping.mappingCid, body: mapping.body})),
    environmentWire: installed.environment.wire, connectorId,
    connectorRegistration: site.connectorRegistration,
    connectorRevision: site.connectorRevision, connection: site.connection,
    site: salesforceRowEffectSite(site), authorization: site.authorization,
    runtimeBundleCid, bindingCid: siteBindingCid,
    continuationBinding: installed.generationCid,
    installation: installedConnectors.find(entry =>
      entry.registration === site.connectorRegistration),
    ledgerRoot, ...(openRowLedger === undefined ? {} :
      {openLedger: openRowLedger}),
    driver: salesforceWriteDriver({salesforceMoon, site,
      mappingOf: mappingCid => installed.mappings.find(mapping =>
        mapping.mappingCid === mappingCid),
      nextOccurrence, siteBindingCid,
      generationCid: installed.generationCid, limits})});
  const targetReadInventory = ({moon: runMoon, prepared, unit}) => {
    if (runMoon !== moon) fail('InvalidInstalledEffectTargetInventory');
    return salesforceEffectTargetReadInventory({moon, prepared, unit,
      installed, site, connectorId});
  };

  return Object.freeze({
    environmentWire: installed.environment.wire,
    generationCid: installed.generationCid,
    targetReadAuthorization: Object.freeze({accountConfiguration,
      context: site.context}),
    connectorBindings: Object.freeze([
      installedSalesforceSiteBinding(site, connectorId)]),
    // The installed implementation's own identification; the Host refuses
    // the installation when its declared registration differs.
    connectorRegistration: site.connectorRegistration,
    connectorRevision: site.connectorRevision,
    connection: site.connection,
    mappings: Object.freeze(installed.mappings.map(mapping => Object.freeze({
      resource: mapping.write.resource, kind: mapping.write.kind,
      target: JSON.parse(mapping.body).target_ref,
      mappingRef: mapping.mappingRef, mappingCid: mapping.mappingCid}))),
    targetReadInventory,
    prepareCaptured: input => rowEffect.prepareCaptured(input),
    prepareRecovered: input => rowEffect.prepareRecovered(input),
    close: () => site.close(),
  });
}
