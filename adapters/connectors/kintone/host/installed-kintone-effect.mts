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
import {kintoneDeleteDriver, kintoneUpdateDriver, KINTONE_UPDATE_TARGET_VERSION} from './kintone-update-driver.mjs';
import {KINTONE_TARGET_READ_OPERATION} from '../site/kintone-record-delete.mjs';

import type {createInstalledRowEffect} from '../../../host-node/installed-row-effect.mjs';
import type {KintoneMaterialsConstruction} from './installed-kintone-source.mjs';

type Unit = ReturnType<typeof installedRowEffectUnit>;
type MaterialOptions = Parameters<typeof prepareInstalledKintoneMaterials>[1];
type EffectCommon = MaterialOptions['moon'] & Parameters<typeof installedRowEffectUnit>[0] & Readonly<{
  clientProgramEffectMemberDescriptor(prepared: unknown, stage: number, effectId: string, work: number): unknown;
}>;
type Kind = 'update' | 'delete' | 'upsert';
type ProfileWrite =
  | Readonly<{resource: string; kind?: never; fields: readonly string[]; key?: never}>
  | Readonly<{resource: string; kind: 'delete'; fields?: never; key?: never}>
  | Readonly<{resource: string; kind: 'upsert'; fields: readonly string[]; key: string}>;
type EffectProfile = Readonly<{version: typeof INSTALLED_KINTONE_EFFECT_VERSION; connectorId: string;
  sourceProfilePath: string; writes: readonly ProfileWrite[]}>;
type WriteInput = Readonly<{resource?: unknown; kind?: unknown; fields?: unknown; key?: unknown}>;
type Mapping = Readonly<{kind: Kind; resource: string; beforeFields: readonly string[]; mapping: unknown;
  targetRef: string; body: string; mappingRef: string; mappingCid: string}>;
type Member = Readonly<{effectId: string; memberIndex: number; targetRef: string; mapping: Mapping}>;
type RowEffect = Awaited<ReturnType<typeof createInstalledRowEffect>>;
type Driver = ReturnType<typeof kintoneUpdateDriver>;
type Recipe = ReturnType<ReturnType<typeof captureKintoneEffectPlanRecipeBuilder>>;
type Constructed = Readonly<{write?: Driver; driver?: Driver; managedPlanRecipes: Readonly<Partial<Record<Kind, Recipe>>>}>;
type ConstructionInput<Value> = Readonly<{capacity(): unknown; project(): Value}>;
type Prepared = Readonly<{environment: Readonly<{wire: string; evidenceCid: string}>}>;
type OpenedSite = Readonly<{site: Readonly<{credential: unknown}>;
  authorization: Readonly<{context: Readonly<{contextCid: string}>}>}>;
type Construction = KintoneMaterialsConstruction & Readonly<{
  configurationReader: KintoneMaterialsConstruction['configurationReader'] & Readonly<{readOriginalBytes(path: string): unknown}>;
  openRowSite(options: Readonly<Record<string, unknown>>): PromiseLike<OpenedSite>;
  createRowEffect(options: Readonly<Record<string, unknown>>): RowEffect | PromiseLike<RowEffect>;
}>;
type LoadOptions = Readonly<{moon: EffectCommon; construction: Construction; ledgerRoot: string;
  runtimeBundleCid: string; resolveSecret?: unknown; installation?: Readonly<{responseHeaders?: readonly string[]}>}>;
type RunInputs = Readonly<{moon: unknown; prepared: unknown; compilation: unknown; unit?: Unit;
  updateTargetSelections?: unknown; assertUpdateSelectionCurrent?(): unknown}>;
type IdentityProfile = Readonly<Record<string, unknown> & {accountConfigurationWire: string}>;
type IdentityOptions = Readonly<{configurationReader?: KintoneMaterialsConstruction['configurationReader']}>;
type TargetBindingInput = Readonly<{fields?: unknown}>;
type View = Readonly<{resource?: unknown; fields: readonly string[]}>;
type MapBody = Readonly<{mapping_ref: string; mapping_contract_cid: string}>;

export const INSTALLED_KINTONE_EFFECT_VERSION = 'actql-installed-kintone-effect/0.1';
const fail: (code: string) => never = code => {throw Object.assign(new TypeError(code), {code});};
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0 && value.isWellFormed() && !/[\u0000-\u001f\u007f]/u.test(value);
const encode = (value: unknown) => canonicalJson(value, {dataKeys: true});
const cid = (value: unknown) => 'sha256:' + createHash('sha256').update(encode(value)).digest('hex');
const closed = <Name extends string,>(value: unknown, names: readonly Name[]): value is Record<Name, unknown> => value !== null && typeof value === 'object' && !Array.isArray(value) &&
  !nodeTypes.isProxy(value) && Reflect.ownKeys(value).length === names.length && names.every(name =>
    Object.hasOwn(Object.getOwnPropertyDescriptor(value, name) ?? {}, 'value'));
const method = <Args extends readonly unknown[], Value>(receiver: unknown, name: string) => {
  const field = receiver && !nodeTypes.isProxy(receiver) ? Object.getOwnPropertyDescriptor(receiver, name) : undefined;
  if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function' ||
      nodeTypes.isProxy(field.value) || nodeTypes.isAsyncFunction(field.value)) fail('KintoneEffectConstructionUnavailable');
  return (...args: Args): Value => Reflect.apply(field.value, receiver, args);
};
const maxMembers = 16, maxRecoveryBytes = 1000000;
const previewLimits = Object.freeze({maxWireBytes: 1000000, maxNodes: 100000, maxDepth: 64});

export function checkInstalledKintoneEffectProfile(profile: unknown): EffectProfile {
  if (!closed(profile, ['version', 'connectorId', 'sourceProfilePath', 'writes']) ||
      profile.version !== INSTALLED_KINTONE_EFFECT_VERSION || !text(profile.connectorId) ||
      !text(profile.sourceProfilePath) || !isAbsolute(profile.sourceProfilePath) || !Array.isArray(profile.writes) ||
      nodeTypes.isProxy(profile.writes) || profile.writes.length !== 1) fail('InvalidInstalledKintoneEffectProfile');
  const entry = Object.getOwnPropertyDescriptor(profile.writes, '0'), write = entry?.value as WriteInput;
  if (entry && Object.hasOwn(entry, 'value') && closed(write, ['resource', 'kind']) &&
      write.kind === 'delete' && text(write.resource)) {
    return Object.freeze({version: profile.version, connectorId: profile.connectorId, sourceProfilePath: profile.sourceProfilePath,
      writes: Object.freeze([Object.freeze({resource: write.resource, kind: 'delete' as const})])});
  }
  const keyed = closed(write, ['resource', 'kind', 'key', 'fields']) && write.kind === 'upsert';
  if (!entry || !Object.hasOwn(entry, 'value') || (!keyed && !closed(write, ['resource', 'fields'])) || !text(write.resource) ||
      !Array.isArray(write.fields) || nodeTypes.isProxy(write.fields) || write.fields!.length < 1 || write.fields!.length > 998) {
    fail('InvalidInstalledKintoneEffectProfile');
  }
  if (keyed && (!text(write.key) || write.key.length > 512 || write.key === '$id' || write.key === '$revision')) {
    fail('InvalidInstalledKintoneEffectProfile');
  }
  const fields = [];
  for (let index = 0; index < write.fields!.length; index++) {
    const field = Object.getOwnPropertyDescriptor(write.fields, String(index));
    if (!field || !Object.hasOwn(field, 'value') || !text(field.value) || field.value.length > 512 ||
        field.value === '$id' || field.value === '$revision' || keyed && field.value === write.key) {
      fail('InvalidInstalledKintoneEffectProfile');
    }
    fields.push(field.value);
  }
  if (new Set(fields).size !== fields.length) fail('InvalidInstalledKintoneEffectProfile');
  return Object.freeze({version: profile.version, connectorId: profile.connectorId, sourceProfilePath: profile.sourceProfilePath,
    writes: Object.freeze([Object.freeze({resource: write.resource,
      ...(keyed ? {kind: 'upsert', key: write.key} : {}), fields: Object.freeze(fields)}) as ProfileWrite])});
}

export async function installedKintoneEffectIdentityParts(profile: unknown, read: (path: string) => unknown, entry: unknown, {configurationReader}: IdentityOptions = {}) {
  const original = checkInstalledKintoneEffectProfile(profile);
  const readers = captureConfigurationReaders(configurationReader, read, () => fail('KintoneEffectConstructionUnavailable')) as
    unknown as KintoneMaterialsConstruction['configurationReader'];
  const source = await readers.readJson(original.sourceProfilePath) as {connectorId?: unknown} | null | undefined;
  if (source?.connectorId !== original.connectorId) fail('KintoneEffectSourceIdentityMismatch');
  const {providerProfile, queryAliases} = splitSourceAliasProfile(source);
  const identity = {...providerProfile, ...(queryAliases.length ? {queryAliases} : {})};
  return [original, ...await installedKintoneSourceIdentityParts(identity as IdentityProfile, providerProfile, read, entry, {configurationReader})];
}

function membersOf(moon: EffectCommon, prepared: unknown, unit: Unit, mapping: Mapping, kind: Kind) {
  if (!text(unit?.programId) || !text(unit.stageId) || !Number.isSafeInteger(unit.stageIndex) || unit.stageIndex < 0 ||
      !Array.isArray(unit.effectIds) || !unit.effectIds.length || unit.effectIds.length > maxMembers ||
      new Set(unit.effectIds).size !== unit.effectIds.length) fail('KintoneEffectUnitUnsupported');
  const members = unit.effectIds.map(effectId => {
    const original = checked(moon.clientProgramEffectMemberDescriptor(prepared, unit.stageIndex, effectId, 10000));
    if (runtimeField(original, 4) !== mapping.mappingRef || runtimeField(original, 5) !== mapping.mappingCid ||
        runtimeField(original, 2) !== kind || runtimeField(original, 6) === undefined) fail('KintoneEffectMappingNotInstalled');
    return Object.freeze({effectId: runtimeField(original, 1) as string, memberIndex: runtimeField(original, 0) as number,
      targetRef: runtimeField(original, 3) as string, mapping});
  }).sort((a,b) => a.memberIndex - b.memberIndex);
  if (members.some((member, index) => member.memberIndex !== index)) fail('KintoneEffectUnitUnsupported');
  return Object.freeze(members);
}
const physicalKeys = ['version', 'site_binding_cid', 'generation_cid', 'program_id', 'stage_id', 'stage_index',
  'effect_id', 'member_index', 'mapping_cid', 'mapping_ref', 'resource', 'effect_kind', 'key', 'fields'] as const;
function bindingFor(member: Pick<Member, 'effectId' | 'memberIndex' | 'mapping'>,
  unit: Pick<Unit, 'programId' | 'stageId' | 'stageIndex'>, siteBindingCid: string, generationCid: string, kind: Kind, key: string) {
  return Object.freeze({version: KINTONE_UPDATE_TARGET_VERSION, site_binding_cid: siteBindingCid,
    generation_cid: generationCid, program_id: unit.programId, stage_id: unit.stageId, stage_index: unit.stageIndex,
    effect_id: member.effectId, member_index: member.memberIndex, mapping_cid: member.mapping.mappingCid,
    mapping_ref: member.mapping.mappingRef, resource: member.mapping.resource, effect_kind: kind,
    key, fields: member.mapping.beforeFields});
}

export async function loadInstalledKintoneEffect(profile: unknown, {moon, construction, ledgerRoot, runtimeBundleCid,
  resolveSecret, installation}: LoadOptions) {
  const selected = checkInstalledKintoneEffectProfile(profile);
  if (!text(ledgerRoot) || !isAbsolute(ledgerRoot) || !/^sha256:[0-9a-f]{64}$/u.test(runtimeBundleCid ?? '')) {
    fail('InvalidInstalledKintoneEffectOptions');
  }
  const write = selected.writes[0], kind = write.kind ?? 'update', keyed = kind === 'upsert', deleting = kind === 'delete';
  const key = keyed ? write.key! : '$id';
  const prepareDriver = method<[ConstructionInput<Constructed>], Constructed>(construction, 'prepareEffectDriverConstruction');
  const prepareInput = method<[ConstructionInput<Mapping>], Mapping>(construction, 'prepareNativeInput'),
    prepareMappings = method<[unknown, readonly Mapping[]], Prepared>(construction, 'prepareNativeMappings');
  const mappingPorts = keyed
    ? ['KeyUpsertMappingConstructionCapacity', 'PrepareKeyUpsertMapping', 'KeyUpsertMappingMaterial']
    : deleting ? ['DeleteMappingConstructionCapacity', 'PrepareDeleteMapping', 'DeleteMappingBody']
      : ['UpdateMappingConstructionCapacity', 'PrepareUpdateMapping', 'UpdateMappingBody', 'UpdateMappingRef', 'UpdateMappingCid'];
  const installationPort = keyed ? 'KeyUpsertInstallationConstructionCapacity' : 'UpdateInstallationConstructionCapacity';
  const native = Object.freeze(Object.fromEntries([installationPort, ...mappingPorts].map(name =>
    [name, method(moon, 'clientProgramKintone' + name)])));
  const sourceProfile = await construction.configurationReader.readJson(selected.sourceProfilePath) as {connectorId?: unknown} | null | undefined;
  if (sourceProfile?.connectorId !== selected.connectorId) fail('KintoneEffectSourceIdentityMismatch');
  const {providerProfile} = splitSourceAliasProfile(sourceProfile);
  const material = await prepareInstalledKintoneMaterials(providerProfile, {moon, construction});
  const {installed: source, siteProfile, metadataCid, original, declared, declarationLimits} = material;
  if (write.resource !== source.resource || !deleting && write.fields!.length > source.limits.maxFields) fail('KintoneEffectResourceNotInstalled');
  const view = (declared.views as readonly View[]).find(view => view.resource === source.resource);
  if (!view || !Array.isArray(view.fields)) fail('KintoneEffectResourceNotInstalled');
  let beforeFields: readonly string[];
  const inputUnits = BigInt(source.connectorId.length + write.resource.length +
    (deleting ? 0 : write.fields!.reduce((n,s) => n + 2 * s.length + (keyed ? 'reject'.length : 0), 0)));
  const mapped = prepareInput(Object.freeze({
    capacity() {
      const capacity = keyed
        ? native.KeyUpsertMappingConstructionCapacity(original, key, write.fields!.length, inputUnits, declarationLimits)
        : deleting ? native.DeleteMappingConstructionCapacity(original, inputUnits, declarationLimits)
          : native.UpdateMappingConstructionCapacity(original, write.fields!.length, inputUnits, declarationLimits);
      const value = runtimeUnboxedReferenceOption(capacity);
      if (!value) fail('KintoneMappingConstructionUnavailable');
      return value;
    },
    project() {
      const sources = deleting ? undefined : write.fields!.map(name => ({target: name, field: name, null_behavior: 'reject'}));
      const mapping = checked(deleting ? native.PrepareDeleteMapping(original, write.resource, 'required', declarationLimits)
        : keyed ? native.PrepareKeyUpsertMapping(original, write.resource, key, sources, declarationLimits)
          : native.PrepareUpdateMapping(original, write.resource, sources, 'required', declarationLimits));
      beforeFields = Object.freeze(view.fields.filter(name => name !== '$id').sort());
      const base: Pick<Mapping, 'kind' | 'resource' | 'beforeFields' | 'targetRef'> = {kind, resource: write.resource, beforeFields, targetRef: 'connector://' + source.connectorId + '/' + write.resource};
      if (deleting) {
        const body = native.DeleteMappingBody(mapping) as string, identity = JSON.parse(body) as MapBody;
        return Object.freeze({...base, mapping, body,
          mappingRef: identity.mapping_ref, mappingCid: identity.mapping_contract_cid});
      }
      if (keyed) {
        const material = checked(native.KeyUpsertMappingMaterial(mapping, original));
        return Object.freeze({...base, mapping, body: runtimeField(material, 0) as string,
          mappingRef: runtimeField(material, 1) as string, mappingCid: runtimeField(material, 2) as string});
      }
      return Object.freeze({...base, mapping, body: checked(native.UpdateMappingBody(mapping)) as string,
        mappingRef: checked(native.UpdateMappingRef(mapping)) as string, mappingCid: checked(native.UpdateMappingCid(mapping)) as string});
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
  let siteBindingCid: string | undefined, generationCid: string | undefined;
  const admitsApprovalTarget = (binding: TargetBindingInput | null | undefined, resource: string) => resource === source.resource && Array.isArray(binding?.fields) &&
    new Set(binding.fields).size === binding.fields.length && binding.fields.every(name => view.fields.includes(name)) &&
    encode(binding) === encode({version: 'actql-installed-kintone-target/0.1', apiOrigin: siteProfile.apiOrigin,
      appId: source.appId, ...(siteProfile.guestSpaceId === undefined ? {} : {guestSpaceId: siteProfile.guestSpaceId}),
      resource, metadataCid, fields: binding.fields});
  const admitsEffectTargetRead = (binding: unknown, resource: string, operation: string) => {
    if (!siteBindingCid || !generationCid || resource !== mapped.resource || operation !== KINTONE_TARGET_READ_OPERATION ||
        !closed(binding, physicalKeys) || !text(binding.program_id) || !text(binding.stage_id) || !text(binding.effect_id) ||
        !Number.isSafeInteger(binding.stage_index) || (binding.stage_index as number) < 0 || !Number.isSafeInteger(binding.member_index) ||
        (binding.member_index as number) < 0 || (binding.member_index as number) >= maxMembers) return false;
    const expected = bindingFor({effectId: binding.effect_id, memberIndex: binding.member_index as number, mapping: mapped},
      {programId: binding.program_id, stageId: binding.stage_id, stageIndex: binding.stage_index as number}, siteBindingCid, generationCid,
      kind, key);
    return physicalKeys.every(name => name === 'fields'
      ? Array.isArray(binding.fields) && !nodeTypes.isProxy(binding.fields) && binding.fields.length === expected.fields.length &&
        expected.fields.every((field, index) => (binding.fields as readonly unknown[])[index] === field)
      : binding[name] === expected[name]);
  };
  const ca = siteProfile.caPath === undefined ? undefined : await construction.configurationReader.readOriginalBytes(siteProfile.caPath);
  const {site, authorization} = await construction.openRowSite({profile: Object.freeze({...siteProfile, resourceOrigin: siteProfile.apiOrigin}),
    accountConfiguration: source.accountConfigurationWire, connection, ca, responseHeaders: installation?.responseHeaders ?? [],
    admitsApprovalTarget, admitsEffectTargetRead, secretPresentation: 'kintone-api-token',
    resolveSecret: resolveSecret ?? (async () => {const token = process.env[siteProfile.tokenEnvironment];
      if (!text(token)) fail('RemoteCredentialSecretUnavailable'); return token;})});
  const textUnits = 4096 + Object.values(siteProfile).reduce<number>((n,s) => n + (typeof s === 'string' ? s.length : 0), 0) +
    connection.length + beforeFields!.reduce((n,s) => n + s.length, 0) + mapped.mappingRef.length + mapped.mappingCid.length +
    (keyed ? key.length : 0);
  const prefix = siteProfile.guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${siteProfile.guestSpaceId}/v1/`;
  const retainedText = connection.length + 2 * prefix.length + 'records.json'.length + 2 * 71;
  if (![textUnits, retainedText].every(n => Number.isSafeInteger(n) && n > 0 && n <= 2147483647)) fail('KintoneEffectConstructionUnavailable');
  const installedCapacity = native[installationPort];
  const built = prepareDriver(Object.freeze({
    capacity() {const value = runtimeUnboxedReferenceOption(installedCapacity(beforeFields!.length,
      textUnits, retainedText)); if (!value) fail('KintoneEffectConstructionUnavailable'); return value;},
    project() {
      siteBindingCid = installedKintoneSiteBinding({contextCid: authorization.context.contextCid, runtimeBundleCid, metadataCid, site: siteProfile});
      generationCid = cid({version: 'actql-installed-kintone-effect-generation/0.1', siteBindingCid,
        environmentCid: prepared.environment.evidenceCid, mappingRef: mapped.mappingRef, mappingCid: mapped.mappingCid});
      const driverFactory = deleting ? kintoneDeleteDriver : kintoneUpdateDriver;
      const {maxInputBytes: _updateOnly, ...deleteLimits} = policy;
      const driver = driverFactory({moon, site, authorization, connection, origin: siteProfile.apiOrigin,
        appId: source.appId, connectorId: source.connectorId, resource: source.resource, formResource: source.formResource,
        fields: beforeFields!, mapping: mapped.mapping, declaration: original, siteBindingCid, generationCid,
        guestSpaceId: siteProfile.guestSpaceId, limits: deleting ? deleteLimits : policy, maxMembers, maxRecoveryBytes, kind});
      const recipe = captureKintoneEffectPlanRecipeBuilder({moon, kind})({mapping: mapped.mapping, fields: beforeFields!, formResource: source.formResource,
        bindingUnits: textUnits, credentialSite: installedRowCredentialOperationSite(site.credential), limits: policy,
        inputLimits: ownerLimits, maxRecoveryBytes, maxTargetBytes: prefix.length + 'records.json'.length});
      return Object.freeze({[kind === 'update' ? 'write' : 'driver']: driver, managedPlanRecipes: Object.freeze({[kind]: recipe})});
    },
  }));
  const rowEffect = await construction.createRowEffect({connection, runtimeBundleCid, bindingCid: siteBindingCid,
    continuationBinding: generationCid, ledgerRoot, ...built, limits: ownerLimits});
  const targetReadInventory = ({moon: runMoon, prepared: runPrepared, compilation, unit: suppliedUnit,
    updateTargetSelections, assertUpdateSelectionCurrent}: RunInputs) => {
    if (runMoon !== moon) fail('ForeignKintoneEffectRuntime');
    const unit = suppliedUnit ?? installedRowEffectUnit(moon, compilation), members = membersOf(moon, runPrepared, unit, mapped, kind);
    const selections = validateInstalledUpdateOwnerSelections(rowEffect, updateTargetSelections, runPrepared);
    if (selections !== undefined) {
      try {
        assertUpdateTargetSelectionMembersCurrent(selections, members.map(member => ({stage_index: unit.stageIndex,
          effect_id: member.effectId, target_ref: member.targetRef, mapping_ref: mapped.mappingRef, mapping_cid: mapped.mappingCid})), runPrepared);
        if (typeof assertUpdateSelectionCurrent !== 'function') fail('KintoneOriginalCurrentUnavailable');
        const result = assertUpdateSelectionCurrent();
        if (result !== undefined) {if (typeof (result as {then?: unknown} | null)?.then === 'function') void Promise.resolve(result).catch(() => {});
          fail('KintoneOriginalCurrentUnavailable');}
      } catch (cause) {throw refusedEffectPreparation(cause);}
    }
    return Object.freeze(members.map(member => Object.freeze({readTuple: Object.freeze({connection,
      resource: mapped.resource, operation: 'read'}), physicalBinding: bindingFor(member, unit, siteBindingCid!, generationCid!, kind, key)})));
  };
  return retainInstalledRowEffectAdapter(rowEffect, Object.freeze({environmentWire: prepared.environment.wire, generationCid,
    targetReadAuthorization: Object.freeze({accountConfiguration: source.accountConfigurationWire, context: authorization.context}),
    connectorBindings: Object.freeze([Object.freeze({connectorId: source.connectorId, bindingCid: siteBindingCid})]),
    connectorRegistration: 'kintone', connectorRevision: 'kintone/0.1', connection,
    mappings: Object.freeze([Object.freeze({resource: mapped.resource, kind, target: mapped.targetRef,
      mappingRef: mapped.mappingRef, mappingCid: mapped.mappingCid})]), effectSelectors: rowEffect.effectSelectors,
    targetReadInventory, prepareManagedPlan: rowEffect.prepareManagedPlan, prepareCaptured: rowEffect.prepareCaptured,
    prepareRecovered: rowEffect.prepareRecovered, close: rowEffect.close}));
}
