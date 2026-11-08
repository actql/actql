// Standard installed UPDATE assembly. Existing initialization, row Effect,
// Account, Checkpoint, claim, Unknown and cleanup owners remain unchanged.
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
import {installedKintoneSourceIdentityParts, installedKintoneSiteBinding, prepareInstalledKintoneMaterials}
  from './installed-kintone-source.mjs';
import {captureKintoneEffectPlanRecipeBuilder} from './kintone-effect-plan.mjs';
import {kintoneUpdateDriver, KINTONE_UPDATE_TARGET_VERSION} from './kintone-update-driver.mjs';
import {KINTONE_TARGET_READ_OPERATION} from '../site/kintone-record-delete.mjs';

export const INSTALLED_KINTONE_EFFECT_VERSION = 'actql-installed-kintone-effect/0.1';
const fail = code => {throw Object.assign(new TypeError(code), {code});};
const text = value => typeof value === 'string' && value.length > 0 && value.isWellFormed() && !/[\u0000-\u001f\u007f]/u.test(value);
const encode = value => canonicalJson(value, {dataKeys: true});
const cid = value => 'sha256:' + createHash('sha256').update(encode(value)).digest('hex');
const closed = (value, names) => value !== null && typeof value === 'object' && !Array.isArray(value) &&
  !nodeTypes.isProxy(value) && Reflect.ownKeys(value).length === names.length && names.every(name =>
    Object.hasOwn(Object.getOwnPropertyDescriptor(value, name) ?? {}, 'value'));
const method = (receiver, name) => {
  const field = receiver && !nodeTypes.isProxy(receiver) ? Object.getOwnPropertyDescriptor(receiver, name) : undefined;
  if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function' ||
      nodeTypes.isProxy(field.value) || nodeTypes.isAsyncFunction(field.value)) fail('KintoneEffectConstructionUnavailable');
  return (...args) => Reflect.apply(field.value, receiver, args);
};
const maxMembers = 16, maxRecoveryBytes = 1000000;
const previewLimits = Object.freeze({maxWireBytes: 1000000, maxNodes: 100000, maxDepth: 64});

export function checkInstalledKintoneEffectProfile(profile) {
  if (!closed(profile, ['version', 'connectorId', 'sourceProfilePath', 'writes']) ||
      profile.version !== INSTALLED_KINTONE_EFFECT_VERSION || !text(profile.connectorId) ||
      !text(profile.sourceProfilePath) || !isAbsolute(profile.sourceProfilePath) || !Array.isArray(profile.writes) ||
      nodeTypes.isProxy(profile.writes) || profile.writes.length !== 1) fail('InvalidInstalledKintoneEffectProfile');
  const entry = Object.getOwnPropertyDescriptor(profile.writes, '0'), write = entry?.value;
  if (!entry || !Object.hasOwn(entry, 'value') || !closed(write, ['resource', 'fields']) || !text(write.resource) ||
      !Array.isArray(write.fields) || nodeTypes.isProxy(write.fields) || write.fields.length < 1 || write.fields.length > 998) {
    fail('InvalidInstalledKintoneEffectProfile');
  }
  const fields = [];
  for (let index = 0; index < write.fields.length; index++) {
    const field = Object.getOwnPropertyDescriptor(write.fields, String(index));
    if (!field || !Object.hasOwn(field, 'value') || !text(field.value) || field.value.length > 512 ||
        field.value === '$id' || field.value === '$revision') fail('InvalidInstalledKintoneEffectProfile');
    fields.push(field.value);
  }
  if (new Set(fields).size !== fields.length) fail('InvalidInstalledKintoneEffectProfile');
  return Object.freeze({version: profile.version, connectorId: profile.connectorId, sourceProfilePath: profile.sourceProfilePath,
    writes: Object.freeze([Object.freeze({resource: write.resource, fields: Object.freeze(fields)})])});
}

export async function installedKintoneEffectIdentityParts(profile, read, entry, {configurationReader} = {}) {
  const original = checkInstalledKintoneEffectProfile(profile);
  const readers = captureConfigurationReaders(configurationReader, read, () => fail('KintoneEffectConstructionUnavailable'));
  const source = await readers.readJson(original.sourceProfilePath);
  if (source?.connectorId !== original.connectorId) fail('KintoneEffectSourceIdentityMismatch');
  const {providerProfile, queryAliases} = splitSourceAliasProfile(source);
  const identity = {...providerProfile, ...(queryAliases.length ? {queryAliases} : {})};
  return [original, ...await installedKintoneSourceIdentityParts(identity, providerProfile, read, entry, {configurationReader})];
}

function membersOf(moon, prepared, unit, mapping) {
  if (!text(unit?.programId) || !text(unit.stageId) || !Number.isSafeInteger(unit.stageIndex) || unit.stageIndex < 0 ||
      !Array.isArray(unit.effectIds) || !unit.effectIds.length || unit.effectIds.length > maxMembers ||
      new Set(unit.effectIds).size !== unit.effectIds.length) fail('KintoneEffectUnitUnsupported');
  const members = unit.effectIds.map(effectId => {
    const original = checked(moon.clientProgramEffectMemberDescriptor(prepared, unit.stageIndex, effectId, 10000));
    if (runtimeField(original, 4) !== mapping.mappingRef || runtimeField(original, 5) !== mapping.mappingCid ||
        runtimeField(original, 2) !== 'update' || runtimeField(original, 6) === undefined) fail('KintoneEffectMappingNotInstalled');
    return Object.freeze({effectId: runtimeField(original, 1), memberIndex: runtimeField(original, 0),
      targetRef: runtimeField(original, 3), mapping});
  }).sort((a,b) => a.memberIndex - b.memberIndex);
  if (members.some((member, index) => member.memberIndex !== index)) fail('KintoneEffectUnitUnsupported');
  return Object.freeze(members);
}
const physicalKeys = ['version', 'site_binding_cid', 'generation_cid', 'program_id', 'stage_id', 'stage_index',
  'effect_id', 'member_index', 'mapping_cid', 'mapping_ref', 'resource', 'effect_kind', 'key', 'fields'];
function bindingFor(member, unit, siteBindingCid, generationCid) {
  return Object.freeze({version: KINTONE_UPDATE_TARGET_VERSION, site_binding_cid: siteBindingCid,
    generation_cid: generationCid, program_id: unit.programId, stage_id: unit.stageId, stage_index: unit.stageIndex,
    effect_id: member.effectId, member_index: member.memberIndex, mapping_cid: member.mapping.mappingCid,
    mapping_ref: member.mapping.mappingRef, resource: member.mapping.resource, effect_kind: 'update',
    key: '$id', fields: member.mapping.beforeFields});
}

export async function loadInstalledKintoneEffect(profile, {moon, construction, ledgerRoot, runtimeBundleCid,
  resolveSecret, installation}) {
  const selected = checkInstalledKintoneEffectProfile(profile);
  if (!text(ledgerRoot) || !isAbsolute(ledgerRoot) || !/^sha256:[0-9a-f]{64}$/u.test(runtimeBundleCid ?? '')) {
    fail('InvalidInstalledKintoneEffectOptions');
  }
  const prepareDriver = method(construction, 'prepareEffectDriverConstruction');
  const prepareInput = method(construction, 'prepareNativeInput'), prepareMappings = method(construction, 'prepareNativeMappings');
  const native = Object.freeze(Object.fromEntries(['UpdateMappingConstructionCapacity', 'UpdateInstallationConstructionCapacity',
    'PrepareUpdateMapping', 'UpdateMappingBody', 'UpdateMappingRef', 'UpdateMappingCid'].map(name =>
    [name, method(moon, 'clientProgramKintone' + name)])));
  const sourceProfile = await construction.configurationReader.readJson(selected.sourceProfilePath);
  if (sourceProfile?.connectorId !== selected.connectorId) fail('KintoneEffectSourceIdentityMismatch');
  const {providerProfile} = splitSourceAliasProfile(sourceProfile);
  const material = await prepareInstalledKintoneMaterials(providerProfile, {moon, construction});
  const {installed: source, siteProfile, metadataCid, original, declared, declarationLimits} = material;
  const write = selected.writes[0];
  if (write.resource !== source.resource || write.fields.length > source.limits.maxFields) fail('KintoneEffectResourceNotInstalled');
  const view = declared.views.find(view => view.resource === source.resource);
  if (!view || !Array.isArray(view.fields)) fail('KintoneEffectResourceNotInstalled');
  let beforeFields;
  const inputUnits = BigInt(source.connectorId.length + write.resource.length + write.fields.reduce((n,s) => n + 2 * s.length, 0));
  const mapped = prepareInput(Object.freeze({
    capacity() {const value = runtimeUnboxedReferenceOption(native.UpdateMappingConstructionCapacity(
      original, write.fields.length, inputUnits, declarationLimits)); if (!value) fail('KintoneMappingConstructionUnavailable'); return value;},
    project() {
      const mapping = checked(native.PrepareUpdateMapping(original, write.resource, write.fields.map(name =>
        ({target: name, field: name, null_behavior: 'reject'})), 'required', declarationLimits));
      beforeFields = Object.freeze(view.fields.filter(name => name !== '$id').sort());
      return Object.freeze({resource: write.resource, beforeFields, mapping, targetRef: 'connector://' + source.connectorId + '/' + write.resource,
        body: checked(native.UpdateMappingBody(mapping)),
        mappingRef: checked(native.UpdateMappingRef(mapping)), mappingCid: checked(native.UpdateMappingCid(mapping))});
    },
  }));
  const prepared = prepareMappings(declared, Object.freeze([mapped]));
  const connection = 'kintone:' + source.connectorId;
  const policy = Object.freeze({maxInputBytes: source.limits.maxRequestBytes, maxRequestBytes: source.limits.maxRequestBytes,
    maxResponseBytes: source.limits.maxResponseBytes, maxNodes: source.limits.maxNodes, maxDepth: source.limits.maxDepth,
    maxFields: source.limits.maxFields, maxNameUnits: source.limits.maxNameUnits, maxColumns: source.limits.maxColumns,
    maxCells: source.limits.maxCells, maxTableRows: source.limits.maxTableRows, maxValueNodes: source.limits.maxValueNodes,
    maxValueDepth: source.limits.maxValueDepth, maxValueTextBytes: source.limits.maxValueTextBytes,
    maxIdentityBytes: source.limits.maxResponseBytes, maxComparisonWork: 20000, maxRecoveryBytes});
  const ownerLimits = Object.freeze({maxMembers, maxFields: source.limits.maxFields, preview: previewLimits,
    body: Object.freeze({maxBytes: policy.maxInputBytes, maxNodes: policy.maxValueNodes, maxDepth: policy.maxValueDepth})});
  let siteBindingCid, generationCid;
  const admitsApprovalTarget = (binding, resource) => resource === source.resource && Array.isArray(binding?.fields) &&
    new Set(binding.fields).size === binding.fields.length && binding.fields.every(name => view.fields.includes(name)) &&
    encode(binding) === encode({version: 'actql-installed-kintone-target/0.1', apiOrigin: siteProfile.apiOrigin,
      appId: source.appId, ...(siteProfile.guestSpaceId === undefined ? {} : {guestSpaceId: siteProfile.guestSpaceId}),
      resource, metadataCid, fields: binding.fields});
  const admitsEffectTargetRead = (binding, resource, operation) => {
    if (!siteBindingCid || !generationCid || resource !== mapped.resource || operation !== KINTONE_TARGET_READ_OPERATION ||
        !closed(binding, physicalKeys) || !text(binding.program_id) || !text(binding.stage_id) || !text(binding.effect_id) ||
        !Number.isSafeInteger(binding.stage_index) || binding.stage_index < 0 || !Number.isSafeInteger(binding.member_index) ||
        binding.member_index < 0 || binding.member_index >= maxMembers) return false;
    const expected = bindingFor({effectId: binding.effect_id, memberIndex: binding.member_index, mapping: mapped},
      {programId: binding.program_id, stageId: binding.stage_id, stageIndex: binding.stage_index}, siteBindingCid, generationCid);
    return physicalKeys.every(name => name === 'fields'
      ? Array.isArray(binding.fields) && !nodeTypes.isProxy(binding.fields) && binding.fields.length === expected.fields.length &&
        expected.fields.every((field, index) => binding.fields[index] === field)
      : binding[name] === expected[name]);
  };
  const ca = siteProfile.caPath === undefined ? undefined : await construction.configurationReader.readOriginalBytes(siteProfile.caPath);
  const {site, authorization} = await construction.openRowSite({profile: Object.freeze({...siteProfile, resourceOrigin: siteProfile.apiOrigin}),
    accountConfiguration: source.accountConfigurationWire, connection, ca, responseHeaders: installation?.responseHeaders ?? [],
    admitsApprovalTarget, admitsEffectTargetRead, secretPresentation: 'kintone-api-token',
    resolveSecret: resolveSecret ?? (async () => {const token = process.env[siteProfile.tokenEnvironment];
      if (!text(token)) fail('RemoteCredentialSecretUnavailable'); return token;})});
  const textUnits = 4096 + Object.values(siteProfile).reduce((n,s) => n + (typeof s === 'string' ? s.length : 0), 0) +
    connection.length + beforeFields.reduce((n,s) => n + s.length, 0) + mapped.mappingRef.length + mapped.mappingCid.length;
  const prefix = siteProfile.guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${siteProfile.guestSpaceId}/v1/`;
  const retainedText = connection.length + 2 * prefix.length + 'records.json'.length + 2 * 71;
  if (![textUnits, retainedText].every(n => Number.isSafeInteger(n) && n > 0 && n <= 2147483647)) fail('KintoneEffectConstructionUnavailable');
  const built = prepareDriver(Object.freeze({
    capacity() {const value = runtimeUnboxedReferenceOption(native.UpdateInstallationConstructionCapacity(beforeFields.length,
      textUnits, retainedText)); if (!value) fail('KintoneEffectConstructionUnavailable'); return value;},
    project() {
      siteBindingCid = installedKintoneSiteBinding({contextCid: authorization.context.contextCid, runtimeBundleCid, metadataCid, site: siteProfile});
      generationCid = cid({version: 'actql-installed-kintone-effect-generation/0.1', siteBindingCid,
        environmentCid: prepared.environment.evidenceCid, mappingRef: mapped.mappingRef, mappingCid: mapped.mappingCid});
      const driver = kintoneUpdateDriver({moon, site, authorization, connection, origin: siteProfile.apiOrigin,
        appId: source.appId, connectorId: source.connectorId, resource: source.resource, formResource: source.formResource,
        fields: beforeFields, mapping: mapped.mapping, declaration: original, siteBindingCid, generationCid,
        guestSpaceId: siteProfile.guestSpaceId, limits: policy, maxMembers, maxRecoveryBytes});
      const recipe = captureKintoneEffectPlanRecipeBuilder({moon})({mapping: mapped.mapping, fields: beforeFields, formResource: source.formResource,
        bindingUnits: textUnits, credentialSite: installedRowCredentialOperationSite(site.credential), limits: policy,
        inputLimits: ownerLimits, maxRecoveryBytes});
      return Object.freeze({driver, managedPlanRecipes: Object.freeze({update: recipe})});
    },
  }));
  const rowEffect = await construction.createRowEffect({connection, runtimeBundleCid, bindingCid: siteBindingCid,
    continuationBinding: generationCid, ledgerRoot, driver: built.driver, managedPlanRecipes: built.managedPlanRecipes, limits: ownerLimits});
  const targetReadInventory = ({moon: runMoon, prepared: runPrepared, compilation, unit: suppliedUnit,
    updateTargetSelections, assertUpdateSelectionCurrent}) => {
    if (runMoon !== moon) fail('ForeignKintoneEffectRuntime');
    const unit = suppliedUnit ?? installedRowEffectUnit(moon, compilation), members = membersOf(moon, runPrepared, unit, mapped);
    const selections = validateInstalledUpdateOwnerSelections(rowEffect, updateTargetSelections, runPrepared);
    if (selections !== undefined) {
      try {
        assertUpdateTargetSelectionMembersCurrent(selections, members.map(member => ({stage_index: unit.stageIndex,
          effect_id: member.effectId, target_ref: member.targetRef, mapping_ref: mapped.mappingRef, mapping_cid: mapped.mappingCid})), runPrepared);
        if (typeof assertUpdateSelectionCurrent !== 'function') fail('KintoneOriginalCurrentUnavailable');
        const result = assertUpdateSelectionCurrent();
        if (result !== undefined) {if (typeof result?.then === 'function') void Promise.resolve(result).catch(() => {});
          fail('KintoneOriginalCurrentUnavailable');}
      } catch (cause) {throw refusedEffectPreparation(cause);}
    }
    return Object.freeze(members.map(member => Object.freeze({readTuple: Object.freeze({connection,
      resource: mapped.resource, operation: 'read'}), physicalBinding: bindingFor(member, unit, siteBindingCid, generationCid)})));
  };
  return retainInstalledRowEffectAdapter(rowEffect, Object.freeze({environmentWire: prepared.environment.wire, generationCid,
    targetReadAuthorization: Object.freeze({accountConfiguration: source.accountConfigurationWire, context: authorization.context}),
    connectorBindings: Object.freeze([Object.freeze({connectorId: source.connectorId, bindingCid: siteBindingCid})]),
    connectorRegistration: 'kintone', connectorRevision: 'kintone/0.1', connection,
    mappings: Object.freeze([Object.freeze({resource: mapped.resource, kind: 'update', target: mapped.targetRef,
      mappingRef: mapped.mappingRef, mappingCid: mapped.mappingCid})]), effectSelectors: rowEffect.effectSelectors,
    targetReadInventory, prepareManagedPlan: rowEffect.prepareManagedPlan, prepareCaptured: rowEffect.prepareCaptured,
    prepareRecovered: rowEffect.prepareRecovered, close: rowEffect.close}));
}
