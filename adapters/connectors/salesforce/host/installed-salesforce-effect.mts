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
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {types as nodeTypes} from 'node:util';
import {isAbsolute} from 'node:path';
import {checked} from '../../../host-common/runtime-result.mjs';
import {refusedEffectPreparation} from
  '../../../host-common/effect-preparation-result.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {installSalesforceAuthorization, installedSalesforceSiteBinding,
  loadInstalledSalesforceSite, releaseSalesforceSite,
  retainSalesforceSiteCleanup, DEFAULT_SALESFORCE_CATALOG_LIMITS} from
  './installed-salesforce-site.mjs';
import {describeSalesforceGeneration, readPublicationFile,
  replacePublicationFile, restoreSalesforceGeneration,
  salesforceCheckEnvironment} from './salesforce-publication.mjs';
import {retainInstalledRowEffectAdapter,
  validateInstalledUpdateOwnerSelections} from
  '../../../host-node/installed-row-effect.mjs';
import {assertUpdateTargetSelectionMembersCurrent} from
  '../../../host-node/update-target-original-shape.mjs';
import {salesforceExecutionMappingConstructionCapacity, salesforceDeclarationConstructionCapacity}
  from './salesforce-initialization-construction.mjs';
import {salesforceRowEffectSite, salesforceWriteDriver} from
  './salesforce-write-driver.mjs';
import {captureSalesforceEffectPlanRecipeBuilder} from './salesforce-effect-plan.mjs';
import {installedRowCredentialOperationSite} from '../../../host-node/installed-row-source.mjs';

import type {bindInstalledSourceConstruction} from '../../../host-node/installed-host-services.mjs';
import type {createInstalledRowEffect} from '../../../host-node/installed-row-effect.mjs';
import type {SalesforceDeclarationConstruction, SalesforceSiteDeclaration} from './installed-salesforce-site.mjs';

type Site = Awaited<ReturnType<typeof loadInstalledSalesforceSite>>;
type Authorization = Awaited<ReturnType<typeof installSalesforceAuthorization>>;
type SiteOptions = NonNullable<Parameters<typeof loadInstalledSalesforceSite>[1]>;
type MappingWrite = NonNullable<Parameters<Site['prepareExecutionMapping']>[0]>['write'];
type Write = Omit<MappingWrite, 'kind'> & Readonly<{
  kind: Exclude<MappingWrite['kind'], 'create'>; resource: string;
}>;
type ProfileInput = Readonly<{siteProfilePath?: unknown; publicationPath?: unknown;
  accountConfigurationWire?: unknown; connectorId?: unknown; version?: unknown; writes?: unknown}>;
type Profile = Readonly<{siteProfilePath: string; publicationPath: string;
  accountConfigurationWire: string; connectorId: string; version: typeof INSTALLED_SALESFORCE_EFFECT_VERSION;
  writes: readonly Write[]}>;
type Mapping = ReturnType<Site['prepareExecutionMapping']> & Readonly<{write: Write}>;
type Environment = ReturnType<typeof salesforceCheckEnvironment>;
type Source = Parameters<typeof restoreSalesforceGeneration>[0]['generation'];
type Record = Readonly<{source: Source; environment_cid: string; mappings: readonly unknown[]; version: unknown}>;
type Installed = Readonly<{generationCid: string; declared: SalesforceSiteDeclaration;
  mappings: readonly Mapping[]; environment: Environment}>;
type Runtime = Readonly<{
  clientProgramEffectMemberDescriptor(prepared: unknown, stageIndex: number, effectId: string, work: number): unknown;
  clientProgramEffectCompilationPlanWire(compilation: unknown): string;
}>;
type Provider = SiteOptions['salesforceMoon'] &
  Parameters<typeof salesforceWriteDriver>[0]['salesforceMoon'] & Readonly<{
    salesforceSourceEvidenceMembers(declaration: object): unknown;
  }>;
type EvidenceMembers = readonly [schemas: readonly string[], capabilities: readonly string[]];
type Host = ReturnType<typeof bindInstalledSourceConstruction>;
type Configuration = Readonly<{readText: NonNullable<Parameters<typeof readPublicationFile>[1]>;
  parseJsonText(text: string): unknown}>;
type Construction = Omit<Host, 'prepareNativeInput'> & SalesforceDeclarationConstruction;
type RowEffect = Awaited<ReturnType<typeof createInstalledRowEffect>>;
type SiteSetup = Readonly<{salesforceMoon: Provider; runtimeBundleCid: string;
  resolveSecret?: SiteOptions['resolveSecret']; openCredentialJournal?: SiteOptions['openCredentialJournal']}>;
type PublicationSetup = SiteSetup & Readonly<{root: string; principalId: string; moon: unknown;
  baseEnvironmentWire: string; signal?: AbortSignal}>;
type Install = SiteSetup & Readonly<{moon: Runtime; ledgerRoot: string; construction: Construction}>;
type GenerationOptions = Readonly<{site: Site; salesforceMoon: Provider; declared: SalesforceSiteDeclaration;
  writes: readonly Write[]; baseEnvironmentWire: string}>;
type RestoreOptions = Readonly<{site: Site; salesforceMoon: Provider; moon: Runtime; profile: Profile;
  construction: Construction}>;
type Unit = ReturnType<typeof salesforceEffectUnit>;
type Stage = Readonly<{id: string; effects?: object}>;
type Inventory = Readonly<{moon: Runtime; prepared: unknown; unit: Unit;
  installed: Pick<Installed, 'mappings' | 'generationCid'>; site: Parameters<typeof installedSalesforceSiteBinding>[0];
  connectorId: string}>;
type Driver = ReturnType<typeof salesforceWriteDriver>;
type RecipeBuilder = ReturnType<typeof captureSalesforceEffectPlanRecipeBuilder>;
type Recipes = ReturnType<RecipeBuilder>;
type RunOperationSite = Extract<ReturnType<typeof installedRowCredentialOperationSite>, {construction: unknown}>;
type DriverOptions = Pick<RestoreOptions, 'construction' | 'moon' | 'salesforceMoon' | 'site'> &
  Readonly<{installed: Installed; nextOccurrence: (label: string) => string; siteBindingCid: string}>;
type EffectOptions = Pick<Install, 'moon' | 'salesforceMoon' | 'ledgerRoot' | 'runtimeBundleCid' | 'construction'> &
  Readonly<{site: Site; installed: Installed; connectorId: string; accountConfiguration: string}>;
type ReadInventory = Readonly<{moon: unknown; prepared: unknown; unit?: Unit; compilation?: unknown;
  updateTargetSelections?: unknown; assertUpdateSelectionCurrent?: () => unknown}>;

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

const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
const requiredEffectRuntime = Object.freeze([
  'salesforcePrepareExecutionWriteBody', 'salesforceWriteValueRefusal',
  'salesforceSingleWriteRequestValue'] as const);
const names = /^[A-Za-z_][A-Za-z0-9_]{0,254}$/u;

function checkWrite(write: Write): Write {
  if (write === null || typeof write !== 'object' || Array.isArray(write) ||
      !names.test(write.resource ?? '') || !writeKinds.has(write.kind) ||
      Object.keys(write).some(key => !['resource', 'kind', 'fields', 'key',
        'sources'].includes(key)) ||
      (write.fields !== undefined && (!Array.isArray(write.fields) ||
        write.fields.length === 0 || write.fields.length > limits.maxFields ||
        !write.fields.every((field: string) => names.test(field)))) ||
      (write.key !== undefined && !names.test(write.key)) ||
      (write.kind === 'upsert') !== (write.key !== undefined) ||
      (write.kind === 'createFromResult') !== (write.sources !== undefined) ||
      (write.kind === 'createFromResult') === (write.fields !== undefined) ||
      (write.sources !== undefined && (!Array.isArray(write.sources) ||
        write.sources.length === 0 ||
        write.sources.length > limits.maxFields ||
        !write.sources.every((source: NonNullable<Write['sources']>[number]) => source !== null &&
          typeof source === 'object' && names.test(source.target ?? '') &&
          text(source.field) &&
          ['reject', 'omit', 'null'].includes(source.nullBehavior))))) {
    fail('InvalidInstalledEffectProfile');
  }
  return Object.freeze({...write,
    ...(write.fields === undefined ? {} :
      {fields: Object.freeze([...write.fields])}),
    ...(write.sources === undefined ? {} : {sources: Object.freeze(
      write.sources.map((source: NonNullable<Write['sources']>[number]) => Object.freeze({...source})))})});
}

// Check the Host profile's shape before anything is read or installed. It
// holds no secret value or private key: the Site profile names them.
export function checkInstalledSalesforceEffectProfile(profile: ProfileInput): Profile {
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
  const writes = (profile.writes as readonly Write[]).map(checkWrite);
  if (new Set(writes.map(write => canonicalJson(write))).size !==
      writes.length) {
    fail('InvalidInstalledEffectProfile');
  }
  return Object.freeze({...profile, writes: Object.freeze(writes)}) as Profile;
}

// The Resources the installed writes name, in first-write order.
const resourcesOf = (profile: Profile) => Object.freeze([...new Set(
  profile.writes.map(write => write.resource))]);

async function openSite(profile: Profile, {root, principalId, moon, salesforceMoon,
  runtimeBundleCid, resolveSecret, openCredentialJournal}: PublicationSetup) {
  const authorization = await installSalesforceAuthorization({
    accountConfiguration: profile.accountConfigurationWire, principalId,
    root});
  const site = await loadInstalledSalesforceSite(profile.siteProfilePath, {
    commonMoon: moon, salesforceMoon, authorization, runtimeBundleCid,
    resolveSecret, openCredentialJournal});
  return site;
}

const mappingInput = (write: Write): MappingWrite => ({kind: write.kind,
  ...(write.fields === undefined ? {} : {fields: [...write.fields]}),
  ...(write.key === undefined ? {} : {key: write.key}),
  ...(write.sources === undefined ? {} :
    {sources: write.sources.map(source => ({...source}))})});

// The execution Mappings of the installed writes and the Check Environment,
// all from one declaration.
function generationFacts({site, salesforceMoon, declared, writes,
  baseEnvironmentWire}: GenerationOptions) {
  const mappings = writes.map(write => {
    const prepared = site.prepareExecutionMapping({
      declaration: declared.declaration, resource: write.resource,
      write: mappingInput(write), limits: limits.mapping});
    return Object.freeze({write, ...prepared});
  });
  const [schemas, capabilities] = checked(
    salesforceMoon.salesforceSourceEvidenceMembers(declared.declaration)) as EvidenceMembers;
  const environment = salesforceCheckEnvironment(baseEnvironmentWire,
    declared, {schemas, capabilities},
    mappings.map(mapping => mapping.body));
  return {mappings, environment};
}

const publicationRecord = (source: Source, mappings: readonly Mapping[], environment: Environment) => ({
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
export async function publishInstalledSalesforceEffect(profile: ProfileInput, options: PublicationSetup) {
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
async function restoreGeneration({site, salesforceMoon, moon, profile, construction}: RestoreOptions): Promise<Installed> {
  const readers = construction.configurationReader as Configuration;
  const {body, generationCid} = await readPublicationFile(profile.publicationPath, readers.readText);
  let record: Record;
  try { record = readers.parseJsonText(body) as Record; }
  catch (error) { fail('InvalidSalesforceEffectPublication', error); }
  if (record === null || typeof record !== 'object' || Array.isArray(record) ||
      JSON.stringify(record) !== body || Object.keys(record).join('\0') !== publicationKeys.join('\0') ||
      record.version !== SALESFORCE_EFFECT_PUBLICATION_VERSION || !Array.isArray(record.mappings)) {
    fail('InvalidSalesforceEffectPublication');
  }
  const {declared} = restoreSalesforceGeneration({site, generation: record.source,
    connectorId: profile.connectorId, resources: resourcesOf(profile), construction});
  const dimensions = Object.freeze([...salesforceMoon.salesforceObservationConstructionDimensions(
    declared.observed.observation)]);
  // This original provider wrapper is a distinct fixed constructor output.
  // Retain it through the existing native-input owner, not a copied wrapper
  // assembled outside that owner's correspondence. The complete declaration
  // envelope conservatively covers its row/evidence projection as before.
  const provider = construction.prepareNativeInput(Object.freeze({
    capacity: () => salesforceDeclarationConstructionCapacity(moon,
      {generation: record.source, siteBinding: site, dimensions, declarationLimits: limits.declaration}),
    project() {
      const [schemas, capabilities] = checked(
        salesforceMoon.salesforceSourceEvidenceMembers(declared.declaration)) as EvidenceMembers;
      return Object.freeze({declared, schemas, capabilities});
    },
  }));
  const mappings = Object.freeze(profile.writes.map(write => construction.prepareNativeInput(Object.freeze({
    capacity: () => salesforceExecutionMappingConstructionCapacity(moon,
      {generation: record.source, write, mappingLimits: limits.mapping}),
    project: () => Object.freeze({write, ...site.prepareExecutionMapping({
      declaration: provider.declared.declaration, resource: write.resource,
      write: mappingInput(write), limits: limits.mapping})}),
  }))));
  const {environment} = construction.prepareProviderEffect(provider, mappings) as {environment: Environment};
  if (canonicalJson(record.mappings) !== canonicalJson(
    publicationRecord(record.source, mappings, environment).mappings) ||
      record.environment_cid !== environment.evidenceCid) {
    fail('SalesforceEffectPublicationMismatch');
  }
  return Object.freeze({generationCid, declared: provider.declared, mappings, environment});
}

// One member of the installed Effect Unit: its Program descriptor and the
// installed write whose Mapping the Program resolved. Refused before any
// provider I/O when the Program's Mapping is not an installed one.
function resolveMember(moon: Runtime, prepared: unknown, installed: Pick<Installed, 'mappings'>,
  {stageIndex, effectId}: Readonly<{stageIndex: number; effectId: string}>) {
  const descriptor = checked(moon.clientProgramEffectMemberDescriptor(
    prepared, stageIndex, effectId, limits.planWork));
  const kind = runtimeField(descriptor, 2) as ReturnType<typeof writeKinds.get>;
  const mapping = installed.mappings.find(candidate =>
    candidate.mappingCid === runtimeField(descriptor, 5) &&
    candidate.mappingRef === runtimeField(descriptor, 4));
  if (mapping === undefined || writeKinds.get(mapping.write.kind) !== kind ||
      runtimeField(descriptor, 6) === undefined) {
    fail('SalesforceEffectMappingNotInstalled');
  }
  return Object.freeze({stageIndex, effectId: runtimeField(descriptor, 1) as string,
    memberIndex: runtimeField(descriptor, 0) as number, kind, mapping,
    resource: mapping.write.resource,
    fields: Object.freeze(mapping.write.fields ??
      mapping.write.sources!.map(source => source.target)),
    key: mapping.write.key ?? ''});
}

// The one Effect Unit of a compiled Values Program: its Program id, the stage
// id and index, and its Effect ids in declaration order, as compiled. A
// Program with Effects in more than one stage is not this scope.
export function salesforceEffectUnit(moon: Runtime, compilation: unknown) {
  let program: Readonly<{id: string; stages: readonly Stage[]}> | undefined;
  try {
    program = JSON.parse(moon.clientProgramEffectCompilationPlanWire(
      compilation)).execution_material?.program;
  } catch (error) { fail('SalesforceEffectUnitUnsupported', error); }
  const stages: readonly Stage[] = Array.isArray(program?.stages) ? program.stages : [];
  const units = stages.flatMap((stage, stageIndex) =>
    stage?.effects === undefined ? [] : [{stage, stageIndex}]);
  if (!text(program?.id) || units.length !== 1 || !text(units[0].stage.id)) {
    fail('SalesforceEffectUnitUnsupported');
  }
  const {stage, stageIndex} = units[0];
  return Object.freeze({programId: program.id, stageId: stage.id, stageIndex,
    effectIds: Object.freeze(Object.keys(stage.effects!))});
}

// The members of the one Effect Unit (`unit`: the Program id, the stage id
// and index, and its Effect ids). The Program and stage ids name the logical
// items of every claim; recovery uses the same pair.
function membersOf(moon: Runtime, prepared: unknown, installed: Pick<Installed, 'mappings'>, unit: Unit) {
  const effectIds = unit?.effectIds;
  if (!text(unit?.programId) || !text(unit.stageId) ||
      !Number.isSafeInteger(unit.stageIndex) || unit.stageIndex < 0 ||
      !Array.isArray(effectIds) || effectIds.length === 0 ||
      effectIds.length > limits.maxMembers ||
      new Set(effectIds).size !== effectIds.length) {
    fail('SalesforceEffectUnitUnsupported');
  }
  const members = effectIds.map((effectId: string) => resolveMember(moon, prepared,
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
  installed, site, connectorId}: Inventory) {
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
export async function loadInstalledSalesforceEffect(profile: ProfileInput, {moon, salesforceMoon,
  runtimeBundleCid, resolveSecret, ledgerRoot, openCredentialJournal, construction}: Install) {
  if (construction === undefined) fail('InstalledSourceInitializationUnavailable');
  const checkedProfile = checkInstalledSalesforceEffectProfile(profile);
  if (!text(ledgerRoot) || !isAbsolute(ledgerRoot)) fail('InvalidInstalledEffectOptions');
  if (requiredEffectRuntime.some(name => typeof salesforceMoon?.[name] !== 'function')) {
    fail('InvalidSalesforceEffectRuntime');
  }
  // The SAME Core implementation policy used by the installed Salesforce
  // Source selects immutable Credential rejection bounds. Actual operation
  // extents and original Account/claim still fund and authorize each use.
  const policyMethod = Object.getOwnPropertyDescriptor(moon, 'clientProgramInstalledSourceReaderPolicy');
  if (!policyMethod || !Object.hasOwn(policyMethod, 'value') || typeof policyMethod.value !== 'function') {
    fail('InstalledEffectCredentialPolicyUnavailable');
  }
  const policy = Reflect.apply(policyMethod.value, moon, []);
  if (!Array.isArray(policy) || policy.length !== 3 || policy.some(value =>
    !Number.isSafeInteger(value) || value < 1 || value > 2147483647)) fail('InstalledEffectCredentialPolicyUnavailable');
  const runAcquisitionLimits = Object.freeze({maxBindings: policy[1], maxSecretBytes: policy[0]});
  const {site} = await construction.openSpecializedSite({
    authorizationConstructor: installSalesforceAuthorization,
    siteConstructor: loadInstalledSalesforceSite,
    siteArgument: checkedProfile.siteProfilePath,
    accountConfiguration: checkedProfile.accountConfigurationWire,
    siteOptions: {salesforceMoon, resolveSecret, openCredentialJournal, runAcquisitionLimits},
  }) as Readonly<{site: Site; authorization: Authorization}>;
  const installed = await restoreGeneration({site, salesforceMoon, moon,
    profile: checkedProfile, construction});
  return installedSalesforceEffect({moon, salesforceMoon, site, installed, ledgerRoot,
    connectorId: checkedProfile.connectorId,
    accountConfiguration: checkedProfile.accountConfigurationWire,
    runtimeBundleCid, construction});
}

// Use the actual initializer before creating the provider's original method
// closures. The same parent keeps their native quantity, projection and driver
// through failed initialization and its existing retirement; no Run or grant
// is issued here. Both methods/receivers are captured before reserve can reenter.
function prepareInstalledSalesforceEffectDriver({construction, moon, salesforceMoon,
  site, installed, nextOccurrence, siteBindingCid}: DriverOptions) {
  const method = (receiver: unknown, name: string) => {
    if (receiver === null || !['object', 'function'].includes(typeof receiver) ||
        nodeTypes.isProxy(receiver)) fail('InstalledSalesforceDriverConstructionUnavailable');
    const field = Object.getOwnPropertyDescriptor(receiver as object, name);
    if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function' ||
        nodeTypes.isProxy(field.value) || nodeTypes.isAsyncFunction(field.value)) {
      fail('InstalledSalesforceDriverConstructionUnavailable');
    }
    return field.value;
  };
  const construct = method(construction, 'prepareEffectDriverConstruction');
  const capacity = method(salesforceMoon, 'salesforceEffectDriverConstructionCapacity');
  const prepareRecipes = captureSalesforceEffectPlanRecipeBuilder({moon, salesforceMoon});
  return Reflect.apply(construct, construction, [Object.freeze({
    capacity() {return Reflect.apply(capacity, salesforceMoon, []);},
    project() {
      const originalSite = installedRowCredentialOperationSite(site.credential) as RunOperationSite;
      const managedPlanRecipes = prepareRecipes({installed, site, credentialConstruction: originalSite.construction!,
        catalogLimits: DEFAULT_SALESFORCE_CATALOG_LIMITS, limits});
      const driver = salesforceWriteDriver({salesforceMoon, site,
        mappingOf: (mappingCid: string) => installed.mappings.find(mapping =>
          mapping.mappingCid === mappingCid),
        nextOccurrence, siteBindingCid, generationCid: installed.generationCid, limits});
      return Object.freeze({driver, managedPlanRecipes});
    },
  })]) as Readonly<{driver: Driver; managedPlanRecipes: Recipes}>;
}

async function installedSalesforceEffect({moon, salesforceMoon, site,
  installed, ledgerRoot, connectorId, accountConfiguration,
  runtimeBundleCid, construction}: EffectOptions) {
  let occurrence = 0;
  const nextOccurrence = (label: string) => `effect-${label}-${Date.now()}-${
    occurrence++}`;
  const siteBindingCid = installedSalesforceSiteBinding(site, connectorId)
    .bindingCid;
  const {driver, managedPlanRecipes} = prepareInstalledSalesforceEffectDriver({construction, moon,
    salesforceMoon, site, installed, nextOccurrence, siteBindingCid});
  // Every Set runs on the Host's provider-neutral installed row Effect,
  // under this connector's registered identity profile, so a Run captured
  // before the move to it keeps its identities.
  const rowEffect = await construction.createRowEffect({
    connection: site.connection, projectSite: salesforceRowEffectSite,
    runtimeBundleCid, bindingCid: siteBindingCid,
    continuationBinding: installed.generationCid,
    ledgerRoot, driver, managedPlanRecipes}) as RowEffect;
  const targetReadInventory = ({moon: runMoon, prepared, unit: providedUnit, compilation,
    updateTargetSelections, assertUpdateSelectionCurrent}: ReadInventory) => {
    if (runMoon !== moon) fail('InvalidInstalledEffectTargetInventory');
    const unit = providedUnit ?? salesforceEffectUnit(moon, compilation);
    const selections = validateInstalledUpdateOwnerSelections(rowEffect,
      updateTargetSelections, prepared);
    if (selections !== undefined) {
      const updates = membersOf(moon, prepared, installed, unit)
        .filter(member => member.kind === 'update');
      try {
        if (typeof assertUpdateSelectionCurrent !== 'function') throw new TypeError('MissingOriginalCurrent');
        assertUpdateTargetSelectionMembersCurrent(selections, updates.map(member => {
          const descriptor = checked(moon.clientProgramEffectMemberDescriptor(
            prepared, unit.stageIndex, member.effectId, limits.planWork));
          return {stage_index: unit.stageIndex, effect_id: runtimeField(descriptor, 1),
            target_ref: runtimeField(descriptor, 3), mapping_ref: runtimeField(descriptor, 4),
            mapping_cid: runtimeField(descriptor, 5)};
        }), prepared);
      } catch {
        throw refusedEffectPreparation(Object.assign(
          new Error('InstalledRowEffectInstallationChanged'),
          {code: 'InstalledRowEffectInstallationChanged'}));
      }
      const result = assertUpdateSelectionCurrent();
      if (typeof (result as {then?: unknown} | null)?.then === 'function') {
        void Promise.resolve(result).catch(() => {});
        throw refusedEffectPreparation(Object.assign(
          new Error('InstalledRowEffectInstallationChanged'),
          {code: 'InstalledRowEffectInstallationChanged'}));
      }
    }
    return salesforceEffectTargetReadInventory({moon, prepared, unit,
      installed, site, connectorId});
  };

  return retainInstalledRowEffectAdapter(rowEffect, Object.freeze({
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
    effectSelectors: rowEffect.effectSelectors,
    targetReadInventory,
    prepareManagedPlan: rowEffect.prepareManagedPlan,
    prepareCaptured: rowEffect.prepareCaptured,
    prepareRecovered: rowEffect.prepareRecovered,
    close: rowEffect.close,
  }));
}
