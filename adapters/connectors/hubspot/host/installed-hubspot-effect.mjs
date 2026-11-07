// Standard installed UPDATE assembly. Common owns initialization, Account,
// Checkpoint, claims, dispatch, Unknown and retirement; this module connects
// the original HubSpot metadata/Catalogs, mappings, driver and managed recipe.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField, runtimeUnboxedReferenceOption} from '../../../host-common/compiler-binding.generated.mjs';
import {refusedEffectPreparation} from '../../../host-common/effect-preparation-result.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {splitSourceAliasProfile} from '../../../host-node/source-alias-publication.mjs';
import {installedRowCredentialOperationSite} from '../../../host-node/installed-row-source.mjs';
import {installedRowEffectUnit, retainInstalledRowEffectAdapter, validateInstalledUpdateOwnerSelections}
  from '../../../host-node/installed-row-effect.mjs';
import {assertUpdateTargetSelectionMembersCurrent} from '../../../host-node/update-target-original-shape.mjs';
import {installedHubSpotSourceIdentityParts, prepareInstalledHubSpotMaterials} from './installed-hubspot-source.mjs';
import {prepareInstalledHubSpotUpdateMappings} from './hubspot-effect-mappings.mjs';
import {captureHubSpotEffectPlanRecipeBuilder} from './hubspot-effect-plan.mjs';
import {hubspotUpdateDriver, HUBSPOT_UPDATE_TARGET_VERSION} from './hubspot-update-driver.mjs';
import {HUBSPOT_OBJECT_BATCH_READ_OPERATION} from '../site/hubspot-target-read.mjs';

export const INSTALLED_HUBSPOT_EFFECT_VERSION = 'actql-installed-hubspot-effect/0.1';
const fail = code => {throw Object.assign(new TypeError(code), {code});};
const text = value => typeof value === 'string' && value.length > 0 && value.isWellFormed() &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const encode = value => canonicalJson(value, {dataKeys: true});
const cid = value => 'sha256:' + createHash('sha256').update(encode(value)).digest('hex');
const closed = (value, names) => value !== null && typeof value === 'object' && !nodeTypes.isProxy(value) &&
  !Array.isArray(value) && Reflect.ownKeys(value).length === names.length && names.every(name =>
  Object.hasOwn(Object.getOwnPropertyDescriptor(value, name) ?? {}, 'value'));
const method = (receiver, name) => {
  if (!receiver || nodeTypes.isProxy(receiver)) fail('HubSpotEffectConstructionUnavailable');
  const field = Object.getOwnPropertyDescriptor(receiver, name);
  if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function' ||
      nodeTypes.isProxy(field.value) || nodeTypes.isAsyncFunction(field.value)) fail('HubSpotEffectConstructionUnavailable');
  return (...args) => Reflect.apply(field.value, receiver, args);
};
const mappingLimits = Object.freeze({maxProperties: 100, maxFields: 100, maxNameBytes: 256,
  maxBytes: 100000, maxNodes: 10000, maxDepth: 64});
const ownerLimits = Object.freeze({maxMembers: 16, maxRows: 100, maxFields: 100,
  preview: Object.freeze({maxWireBytes: 1000000, maxNodes: 100000, maxDepth: 64}),
  body: Object.freeze({maxBytes: 8192, maxNodes: 2000, maxDepth: 24})});
const bodyLimits = Object.freeze({maxInputBytes: 8192, maxNodes: 2000, maxDepth: 24,
  maxFields: 100, maxNameBytes: 256, maxValueNodes: 2000, maxValueTextBytes: 8192,
  maxComparisonWork: 20000, maxOutputBytes: 8192, maxOutputNodes: 2000, maxOutputDepth: 24});
const requestBounds = Object.freeze({maxRows: 100, maxProperties: 100, maxTraceBytes: 128,
  maxBodyBytes: 20000, maxBodyNodes: 3000, maxBodyDepth: 24});
const maxRecoveryBytes = 1000000;

export function checkInstalledHubSpotEffectProfile(profile) {
  if (!closed(profile, ['version', 'connectorId', 'sourceProfilePath', 'writes']) ||
      profile.version !== INSTALLED_HUBSPOT_EFFECT_VERSION ||
      !text(profile.connectorId) ||
      !text(profile.sourceProfilePath) || !isAbsolute(profile.sourceProfilePath) ||
      !Array.isArray(profile.writes) || nodeTypes.isProxy(profile.writes) ||
      profile.writes.length < 1 || profile.writes.length > ownerLimits.maxMembers) fail('InvalidInstalledHubSpotEffectProfile');
  const writes = [];
  for (let index = 0; index < profile.writes.length; index++) {
    const field = Object.getOwnPropertyDescriptor(profile.writes, String(index)), write = field?.value;
    if (!field || !Object.hasOwn(field, 'value') || !closed(write, ['resource', 'fields', 'markerProperty']) ||
        !text(write.resource) || !text(write.markerProperty) || write.markerProperty === 'id' ||
        write.markerProperty.length > mappingLimits.maxNameBytes ||
        !Array.isArray(write.fields) || nodeTypes.isProxy(write.fields) ||
        write.fields.length < 1 || write.fields.length > mappingLimits.maxFields) fail('InvalidInstalledHubSpotEffectProfile');
    const fields = [];
    for (let i = 0; i < write.fields.length; i++) {
      const selected = Object.getOwnPropertyDescriptor(write.fields, String(i));
      if (!selected || !Object.hasOwn(selected, 'value') || !text(selected.value) ||
          selected.value.length > mappingLimits.maxNameBytes || selected.value === write.markerProperty) {
        fail('InvalidInstalledHubSpotEffectProfile');
      }
      fields.push(selected.value);
    }
    if (new Set(fields).size !== fields.length) fail('InvalidInstalledHubSpotEffectProfile');
    writes.push(Object.freeze({resource: write.resource, fields: Object.freeze(fields), markerProperty: write.markerProperty}));
  }
  if (new Set(writes.map(write => write.resource)).size !== writes.length) fail('InvalidInstalledHubSpotEffectProfile');
  return Object.freeze({version: profile.version, connectorId: profile.connectorId,
    sourceProfilePath: profile.sourceProfilePath, writes: Object.freeze(writes)});
}

export async function installedHubSpotEffectIdentityParts(profile, read, entry, {configurationReader} = {}) {
  const original = checkInstalledHubSpotEffectProfile(profile);
  const readers = captureConfigurationReaders(configurationReader, read, () => fail('HubSpotEffectConstructionUnavailable'));
  const source = await readers.readJson(original.sourceProfilePath);
  if (source?.connectorId !== original.connectorId) fail('HubSpotEffectSourceIdentityMismatch');
  // The existing JSON reader reserves the complete checked-profile/split and
  // identity envelope. Reuse the Host's bounded alias splitter; aliases remain
  // identity DATA and never enter the connector's closed provider profile.
  const {providerProfile, queryAliases} = splitSourceAliasProfile(source);
  const identityProfile = Object.freeze({...providerProfile,
    ...(queryAliases.length === 0 ? {} : {queryAliases})});
  const parts = await installedHubSpotSourceIdentityParts(identityProfile, providerProfile, read, entry, {configurationReader});
  return [original, ...parts];
}

function nativeLimits(limits) {
  const read = Object.freeze({maxResponseBytes: limits.maxResponseBytes, maxRequestBytes: 20000,
    maxNodes: limits.maxNodes, maxDepth: limits.maxDepth, maxProperties: limits.maxProperties,
    // Each physical request selects exactly one original record. This is
    // separate from the Effect owner's bounded number of serial row changes.
    // The actual decoder must match the one-row constructor quantity even
    // when a provider returns unexpected additional records.
    maxNameUnits: limits.maxNameUnits, maxRows: 1, maxColumns: limits.maxColumns,
    maxCursorUnits: limits.maxCursorUnits, maxValueNodes: limits.maxValueNodes,
    maxValueTextBytes: limits.maxValueTextBytes, maxOutputBytes: limits.maxRowsWireBytes,
    maxOutputNodes: limits.maxRowsWireNodes, maxOutputDepth: limits.maxRowsWireDepth,
    maxRequestNodes: 3000, maxRequestDepth: 24});
  const write = Object.freeze({maxRequestBytes: requestBounds.maxBodyBytes,
    maxResponseBytes: limits.maxResponseBytes, maxNodes: limits.maxNodes, maxDepth: limits.maxDepth, maxRows: 1});
  return Object.freeze({read, write, body: bodyLimits, request: requestBounds});
}

function membersOf(moon, prepared, unit, installed) {
  if (!text(unit?.programId) || !text(unit.stageId) || !Number.isSafeInteger(unit.stageIndex) || unit.stageIndex < 0 ||
      !Array.isArray(unit.effectIds) || unit.effectIds.length < 1 || unit.effectIds.length > ownerLimits.maxMembers ||
      new Set(unit.effectIds).size !== unit.effectIds.length) fail('HubSpotEffectUnitUnsupported');
  const members = unit.effectIds.map(effectId => {
    const original = checked(moon.clientProgramEffectMemberDescriptor(prepared, unit.stageIndex, effectId, 10000));
    const mapping = installed.find(value => value.mappingRef === runtimeField(original, 4) && value.mappingCid === runtimeField(original, 5));
    if (!mapping || runtimeField(original, 2) !== 'update' || runtimeField(original, 6) === undefined) {
      fail('HubSpotEffectMappingNotInstalled');
    }
    return Object.freeze({effectId: runtimeField(original, 1), memberIndex: runtimeField(original, 0),
      targetRef: runtimeField(original, 3), mapping});
  }).sort((a, b) => a.memberIndex - b.memberIndex);
  if (members.some((member, index) => member.memberIndex !== index)) fail('HubSpotEffectUnitUnsupported');
  return Object.freeze(members);
}

const physicalKeys = ['version', 'site_binding_cid', 'generation_cid', 'program_id', 'stage_id',
  'stage_index', 'effect_id', 'member_index', 'mapping_cid', 'mapping_ref', 'resource', 'effect_kind', 'key', 'fields'];
function bindingFor(member, unit, siteBindingCid, generationCid) {
  return Object.freeze({version: HUBSPOT_UPDATE_TARGET_VERSION, site_binding_cid: siteBindingCid,
    generation_cid: generationCid, program_id: unit.programId, stage_id: unit.stageId,
    stage_index: unit.stageIndex, effect_id: member.effectId, member_index: member.memberIndex,
    mapping_cid: member.mapping.mappingCid, mapping_ref: member.mapping.mappingRef,
    resource: member.mapping.resource, effect_kind: 'update', key: 'id', fields: member.mapping.fields});
}

// Bind the existing checked member/selection owners to this installation's
// physical inventory. This helper neither issues a selection nor supplies a
// current proof; copied selections still fail the original Common delegate.
export function installedHubSpotTargetReadInventory({moon, mappings, connection, siteBindingCid, generationCid, rowEffect}) {
  return ({moon: runMoon, prepared: runPrepared, compilation, unit: suppliedUnit,
    updateTargetSelections, assertUpdateSelectionCurrent}) => {
    if (runMoon !== moon) fail('ForeignHubSpotEffectRuntime');
    const unit = suppliedUnit ?? installedRowEffectUnit(moon, compilation);
    const members = membersOf(moon, runPrepared, unit, mappings);
    const selections = validateInstalledUpdateOwnerSelections(rowEffect, updateTargetSelections, runPrepared);
    if (selections !== undefined) {
      try {
        assertUpdateTargetSelectionMembersCurrent(selections, members.map(member => ({stage_index: unit.stageIndex,
          effect_id: member.effectId, target_ref: member.targetRef, mapping_ref: member.mapping.mappingRef,
          mapping_cid: member.mapping.mappingCid})), runPrepared);
        if (typeof assertUpdateSelectionCurrent !== 'function') fail('HubSpotOriginalCurrentUnavailable');
        const result = assertUpdateSelectionCurrent();
        if (result !== undefined) {
          if (typeof result?.then === 'function') void Promise.resolve(result).catch(() => {});
          fail('HubSpotOriginalCurrentUnavailable');
        }
      } catch (cause) {throw refusedEffectPreparation(cause);}
    }
    return Object.freeze(members.map(member => Object.freeze({readTuple: Object.freeze({connection,
      resource: member.mapping.resource, operation: 'read'}), physicalBinding: bindingFor(member, unit, siteBindingCid, generationCid)})));
  };
}

export async function loadInstalledHubSpotEffect(profile, {moon, providerMoon, construction,
  ledgerRoot, runtimeBundleCid, resolveSecret, installation}) {
  const selected = checkInstalledHubSpotEffectProfile(profile);
  if (!text(ledgerRoot) || !isAbsolute(ledgerRoot) || !/^sha256:[0-9a-f]{64}$/u.test(runtimeBundleCid ?? '')) {
    fail('InvalidInstalledHubSpotEffectOptions');
  }
  const prepareDriver = method(construction, 'prepareEffectDriverConstruction');
  const quantity = method(moon, 'clientProgramHubSpotEffectConstructorCapacity');
  const policy = method(moon, 'clientProgramInstalledSourceReaderPolicy')();
  if (!Array.isArray(policy) || policy.length !== 3 || policy.some(value => !Number.isSafeInteger(value) || value < 1)) {
    fail('HubSpotEffectCredentialPolicyUnavailable');
  }
  const sourceProfile = await construction.configurationReader.readJson(selected.sourceProfilePath);
  if (sourceProfile?.connectorId !== selected.connectorId) fail('HubSpotEffectSourceIdentityMismatch');
  const {providerProfile} = splitSourceAliasProfile(sourceProfile);
  const material = await prepareInstalledHubSpotMaterials(providerProfile, {moon, providerMoon, construction});
  const {installed: source, siteProfile, metadata, objects, catalogs, declared} = material;
  if (selected.writes.some(write => !catalogs.has(write.resource))) fail('HubSpotEffectResourceNotInstalled');
  const {originals, prepared} = prepareInstalledHubSpotUpdateMappings({construction, moon, providerMoon,
    connectorId: source.connectorId, declared, catalogFor: resource => catalogs.get(resource),
    writes: selected.writes, limits: mappingLimits});
  const limits = nativeLimits(source.limits), connection = 'hubspot:' + source.connectorId;
  let mappings, siteBindingCid, generationCid;
  const admitsApprovalTarget = (binding, resource) => {
    const view = declared.views.find(value => value.resource === resource);
    return view !== undefined && Array.isArray(binding?.fields) && new Set(binding.fields).size === binding.fields.length &&
      binding.fields.every(name => view.fields.includes(name)) && encode(binding) === encode({
        version: 'actql-installed-hubspot-target/0.1', apiOrigin: siteProfile.apiOrigin, portalId: source.portalId,
        resource, objectType: objects.get(resource)?.objectType, metadataCid: cid(metadata), fields: binding.fields});
  };
  const admitsEffectTargetRead = (binding, resource, operation) => {
    if (!siteBindingCid || !generationCid || operation !== HUBSPOT_OBJECT_BATCH_READ_OPERATION ||
        !closed(binding, physicalKeys) || !text(binding.program_id) || !text(binding.stage_id) || !text(binding.effect_id) ||
        !Number.isSafeInteger(binding.stage_index) || binding.stage_index < 0 ||
        !Number.isSafeInteger(binding.member_index) || binding.member_index < 0 || binding.member_index >= ownerLimits.maxMembers) return false;
    const mapping = mappings.find(value => value.resource === resource && value.mappingRef === binding.mapping_ref &&
      value.mappingCid === binding.mapping_cid);
    return mapping !== undefined && encode(binding) === encode(bindingFor({effectId: binding.effect_id,
      memberIndex: binding.member_index, mapping}, {programId: binding.program_id, stageId: binding.stage_id,
      stageIndex: binding.stage_index}, siteBindingCid, generationCid));
  };
  const ca = siteProfile.caPath === undefined ? undefined : await construction.configurationReader.readOriginalBytes(siteProfile.caPath);
  const {site, authorization} = await construction.openRowSite({profile: Object.freeze({...siteProfile,
    resourceOrigin: siteProfile.apiOrigin}), accountConfiguration: source.accountConfigurationWire, connection,
    ca, responseHeaders: installation?.responseHeaders ?? [], admitsApprovalTarget, admitsEffectTargetRead,
    runAcquisitionLimits: Object.freeze({maxSecretBytes: policy[0], maxBindings: policy[1]}),
    resolveSecret: resolveSecret ?? (async () => {
      const secret = process.env[siteProfile.tokenEnvironment];
      if (!text(secret)) fail('RemoteCredentialSecretUnavailable'); return secret;
    })});
  // Count borrowed immutable inputs without serializing another metadata
  // document before the constructor reservation. Canonical preimages are
  // built only inside project, where the quote owns their complete workspace.
  const textUnits = 4096 + Object.values(siteProfile).reduce((sum, value) =>
    sum + (typeof value === 'string' ? value.length : 0), 0) + metadata.accountBody.length +
    metadata.objects.reduce((sum, value) => sum + value.resource.length + value.objectType.length + value.propertiesBody.length, 0) +
    selected.writes.reduce((sum, value) => sum + value.resource.length + value.markerProperty.length +
      value.fields.reduce((total, field) => total + field.length, 0) + 2 * 71, 0);
  if (!Number.isSafeInteger(textUnits) || textUnits > 2147483647) fail('HubSpotEffectConstructionUnavailable');
  const prepareRecipe = captureHubSpotEffectPlanRecipeBuilder({moon});
  const constructed = prepareDriver(Object.freeze({
    capacity() {
      const value = runtimeUnboxedReferenceOption(quantity(7, [], [], [originals.length,
        originals.reduce((sum, value) => sum + value.fields.length, 0), metadata.objects.length, textUnits]));
      if (!value) fail('HubSpotEffectConstructionUnavailable'); return value;
    },
    project() {
      mappings = Object.freeze(originals.map(original => Object.freeze({...original,
        catalog: catalogs.get(original.resource), markerProperty: selected.writes.find(write => write.resource === original.resource).markerProperty})));
      siteBindingCid = cid({version: 'actql-installed-hubspot-effect-site-binding/0.1',
        contextCid: authorization.context.contextCid, runtimeBundleCid, site: siteProfile, metadataCid: cid(metadata)});
      generationCid = cid({version: 'actql-installed-hubspot-effect-generation/0.1', siteBindingCid,
        environmentCid: prepared.environment.evidenceCid, writes: mappings.map(value => ({resource: value.resource,
          mappingRef: value.mappingRef, mappingCid: value.mappingCid, markerProperty: value.markerProperty}))});
      const installedFor = member => mappings.find(value => value.resource === member?.resource &&
        value.mappingRef === member.mapping?.mappingRef && value.mappingCid === member.mapping?.mappingCid);
      const originalSite = installedRowCredentialOperationSite(site.credential);
      const recipe = prepareRecipe({mappings, portalId: source.portalId,
        objectTypeUnits: Math.max(...source.resources.map(value => value.objectType.length)),
        metadataResources: source.metadataResources, credentialSite: originalSite, limits,
        inputLimits: {body: ownerLimits.body, preview: ownerLimits.preview}, maxRecoveryBytes});
      const driver = hubspotUpdateDriver({moon: providerMoon, site, authorization, connection,
        origin: siteProfile.apiOrigin, portalId: source.portalId, connectorId: source.connectorId,
        siteBindingCid, generationCid, installedFor, metadataResources: source.metadataResources,
        requestLimits: Object.freeze({maxProperties: mappingLimits.maxProperties, body: bodyLimits,
          request: requestBounds, maxRecoveryBytes}), readLimits: limits.read, writeLimits: limits.write,
        maxRows: ownerLimits.maxRows, maxMembers: ownerLimits.maxMembers, maxRecoveryBytes});
      return Object.freeze({driver, managedPlanRecipes: Object.freeze({update: recipe})});
    },
  }));
  const rowEffect = await construction.createRowEffect({connection, runtimeBundleCid, bindingCid: siteBindingCid,
    continuationBinding: generationCid, ledgerRoot, driver: constructed.driver,
    managedPlanRecipes: constructed.managedPlanRecipes, limits: ownerLimits});
  const targetReadInventory = installedHubSpotTargetReadInventory({moon, mappings, connection,
    siteBindingCid, generationCid, rowEffect});
  return retainInstalledRowEffectAdapter(rowEffect, Object.freeze({environmentWire: prepared.environment.wire,
    generationCid, targetReadAuthorization: Object.freeze({accountConfiguration: source.accountConfigurationWire,
      context: authorization.context}), connectorBindings: Object.freeze([Object.freeze({connectorId: source.connectorId,
      bindingCid: siteBindingCid})]), connectorRegistration: 'hubspot', connectorRevision: 'hubspot/0.1',
    connection, mappings: Object.freeze(mappings.map(value => Object.freeze({resource: value.resource, kind: 'update',
      target: JSON.parse(value.body).target_ref, mappingRef: value.mappingRef, mappingCid: value.mappingCid}))),
    effectSelectors: rowEffect.effectSelectors, targetReadInventory, prepareManagedPlan: rowEffect.prepareManagedPlan,
    prepareCaptured: rowEffect.prepareCaptured, prepareRecovered: rowEffect.prepareRecovered, close: rowEffect.close}));
}
