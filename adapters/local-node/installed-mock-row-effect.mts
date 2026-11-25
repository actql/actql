// The explicit Project Mock's real file writes, through the existing Row
// Effect owner. No live Salesforce request/credential, hidden mirror, automatic
// approval, replacement Run or permission derived from a profile is supplied.
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {authorizationDispatchFacts, assertAuthorizationAccountCurrent}
  from '../host-common/authorization-gate.mjs';
import {retainInstalledRowEffectAdapter, installedRowEffectConstructionLimits,
  prepareInstalledTargetPlanRecipes} from '../host-node/installed-row-effect.mjs';
import {prepareInstalledPhysicalWritePlanRecipe} from '../host-node/installed-effect-plan.mjs';
import {installedUpdateTargets, composeInstalledEffects} from '../host-node/installed-effect-inventory.mjs';
import {createMockFileTarget} from '../host-node/mock-file-target.mjs';
import {retainInstalledHostInitializationFailure} from '../host-node/installed-host-cleanup.mjs';
import {declaredProjectMockFootprintConstructionGeometry} from '../host-node/declared-project-catalog-construction.mjs';

import type {EffectOwner} from '../host-node/installed-effect-inventory.mjs';
import type {prepareInstalledProjectMock} from './installed-project-mock.mjs';

type Data = Record<string, unknown>;
type RecipeRuntime = Parameters<typeof prepareInstalledPhysicalWritePlanRecipe>[0]['moon'] & Readonly<{
  clientProgramSerializationCapacityBytes(original: unknown): unknown;
  clientProgramInstalledFileEffectConstructionCapacity(provider: unknown, bytes: number, nodes: number, depth: number): unknown;
}>;
type InventoryOptions = Parameters<typeof composeInstalledEffects>[1];
type Runtime = RecipeRuntime & InventoryOptions['moon'] & Readonly<{
  [Name in keyof CodecArguments as (typeof ports & typeof createPorts & typeof orderedPorts)[Name]]:
    (...args: CodecArguments[Name]) => CodecResults[Name];
}>;
type File = ReturnType<typeof createMockFileTarget>;
type FileOptions = Parameters<typeof createMockFileTarget>[0];
type Preparation = Awaited<ReturnType<typeof prepareInstalledProjectMock>>;
type Bundle = ReturnType<Preparation['originalsForRuntime']>;
type Source = Bundle['sources'][number];
type Target = Bundle['writables'][number];
type Physical = Target['physical'];
type Write = Target['write'];
type Mapping = NonNullable<Target['mapping']>;
type InstalledMapping = Extract<Mapping, {target: string}>;
type Effect = EffectOwner & Readonly<{close(): unknown}>;
type Authorization = Readonly<{configurationCid?: string}>;
type Resources = Readonly<{
  bindRunOriginal(facts: unknown): unknown;
  assertCurrent(original: unknown): unknown;
  limits(original: unknown): unknown;
}>;
type MockPreparation = Pick<Preparation, 'originalsForRuntime' | 'constructWritableRuntime'>;
type Recipe = ReturnType<typeof prepareInstalledPhysicalWritePlanRecipe>;
type TargetPlanRecipes = ReturnType<typeof prepareInstalledTargetPlanRecipes>;
type DriverInstance = ReturnType<typeof mockRowEffectDriver>;
type ConstructedDriver = DriverInstance & Readonly<{
  targets: readonly Target[]; managedPlanRecipe?: Recipe; managedTargetPlanRecipes?: TargetPlanRecipes;
}>;
type Installation = Readonly<{
  moon: Runtime; mockPreparation: MockPreparation;
  baseEnvironmentWire: InventoryOptions['baseEnvironmentWire'];
  authorizationFor(connection: string): Authorization | PromiseLike<Authorization>;
  principalId: string; runtimeBundleCid: string; bindingCid?: string; bindingFor?: (source: Source) => string | undefined;
  ledgerRoot: string; assertCurrent(): unknown; effectResources: unknown;
  installationServices: InventoryOptions['installationServices'];
  io?: FileOptions['io']; observeWrite?: FileOptions['observeWrite'];
}>;
type InsertCapacity = (size: number, requestUnits: number) => unknown;
type OrderedCapacity = Readonly<{workspace(size: number, keyUnits: number, mappedUnits?: number): unknown;
  canInsert: boolean}>;
type CodecArguments = {
  insertContract: [declaration: unknown, resource: string, primaryIdentity: string, bytes: number,
    nodes: number, depth: number, rows: number];
  insertCapacity: [contract: unknown, pathLength: number, size: number, requestUnits: number];
  insert: [original: unknown, contract: unknown, itemsPath: readonly string[], keyPath: readonly string[],
    key: string, wire: string];
  orderedInsert: [original: unknown, preparedKey: unknown, itemsPath: readonly string[], keyPath: readonly string[],
    key: string, wire: string];
  orderedCapacity: [preparedKey: unknown, itemsPathDepth: number, bytes: number, keyUnits: number,
    mappedUnits: number | undefined];
  createKey: [runDefinitionCid: string, sourceBindingCid: string, effectIdentityCid: string,
    contentCid: string, occurrence: number];
  admit: [bytes: Uint8Array, maxBytes: number, maxNodes: number, maxDepth: number, maxRows: number, maxWork: number];
  project: [original: unknown, declaration: unknown, resource: string, itemsPath: readonly string[],
    keyPath: readonly string[], identity: string | undefined, preparedKey: unknown, writableFields: readonly string[]];
  observe: [document: unknown, declaration: unknown, identity: string];
  findOrdered: [document: unknown, declaration: unknown, identity: string];
  before: [row: unknown];
  version: [row: unknown];
  update: [document: unknown, row: unknown, version: string, valueWire: string, maxWork: number];
  delete: [document: unknown, row: unknown, version: string, maxWork: number];
  construction: Parameters<RecipeRuntime['clientProgramInstalledSourceConstructionCapacity']>;
};
type CodecResults = Record<keyof CodecArguments, unknown> & Readonly<{before: string | undefined; version: string | undefined}>;
type CodecCall = <Name extends keyof CodecArguments>(name: Name, ...args: CodecArguments[Name]) => CodecResults[Name];
type Document = Readonly<{selected: unknown}>;
type RecordData = Readonly<{target: MockFileSelector; version?: string; value?: unknown; before?: Data}>;
type EffectRecord = RecordData & Readonly<{binding: string; mapping: string}>;
type AdmissionTarget = Readonly<{physical: Source['physical'][number];
  write: Pick<Write, 'writable_fields' | 'operation'> | Readonly<{operation: 'upsert'; writable_fields: readonly string[]}>}>;
type Charge = Readonly<{chargeBytes(bytes: bigint): unknown}>;
type Extent = Readonly<{nodes: bigint; text: bigint; wire: bigint}>;
type FileChild = ReturnType<File['updateChild']>;
type PhysicalOperation = Charge & Readonly<{retainPhysicalChild(child: FileChild): unknown;
  admitInput?: (size: number, requestUnits: number) => unknown}>;
type Member = Readonly<{resource: string; kind: string; mapping?: Pick<Mapping, 'mappingCid' | 'mappingRef'>}>;
type RunOriginal = object;
type Decision = Parameters<typeof assertAuthorizationAccountCurrent>[0];
type GrantKind = 'read' | 'write';
type Grant = Readonly<{
  operation: string; decision: Decision; runInvocationCid: string; dispatchRequestCid: string; subjectCid?: string;
}> & {used: boolean};
type GrantOptions = Readonly<{
  operation: string; decision: Decision; resource: string; runInvocationCid: string;
  dispatchRequestCid: string; subjectCid?: string; maxUses?: number;
}>;
type SuppliedUse = Readonly<{proof: object; useId: string}>;
type Description = Readonly<{runInvocationCid: string; dispatchRequestCid: string; runOriginal: RunOriginal; target?: Target}>;
type DescribeOptions = Omit<Description, 'target'> & Readonly<{
  member: Member;
  controlConstruction?: (token: undefined, construct: () => object, arguments_: readonly never[], capacity: unknown) => object;
}>;
type HeldRequest = Readonly<{
  record: EffectRecord; cid: string; runOriginal: RunOriginal; retainedWire: string; observedAt?: object;
}>;
type UsedGrant = Readonly<{grant: Grant; useCid: string}>;
type RequestOutput = Readonly<{request: object; requestCid: string}>;
type TargetObservation = Readonly<{identity: MockFileSelector}> &
  (Readonly<{state: 'absent'}> | Readonly<{versionCid: string; before: Data}>);
type Retirable = Pick<FileChild, 'release' | 'retry' | 'status'>;
type OwnedObservationChild = Retirable & Readonly<{
  retainedOutputWire(value: unknown): string;
  prepare(): Promise<TargetObservation>;
}>;
type RequestEntries = Readonly<{entries: readonly Readonly<{request: object}>[]}>;
type CurrentTarget = Readonly<{member: Member; current: object; runOriginal: RunOriginal}>;
type FileCreateIdentity = Readonly<{runDefinitionCid: unknown; sourceBindingCid: unknown; effectIdentityCid: unknown}>;
type ReadOptions = CurrentTarget & Readonly<{
  selector?: unknown; value: unknown; authorizationForRow?(): SuppliedUse | PromiseLike<SuppliedUse>; signal?: AbortSignal;
  createRowIdentity?: unknown; fileCreateIdentity?: FileCreateIdentity;
}>;
type ObserveOptions = CurrentTarget & RequestEntries & Readonly<{
  authorizationForRow(index: number): SuppliedUse | PromiseLike<SuppliedUse>; signal?: AbortSignal;
  ownedReadChild?(constructChild: () => OwnedObservationChild, index: number): TargetObservation | PromiseLike<TargetObservation>;
}>;
type SendOptions = CurrentTarget & Readonly<{
  request: object; authorization: SuppliedUse; signal?: AbortSignal; physicalOperation?: PhysicalOperation;
}>;
type Observation = Readonly<{useCid: string; statusCode: number; body: Uint8Array}>;
type RecoveryEntry = Readonly<{memberIndex: number; kind: string; wire: string; observationCid: string}>;
type RecoveryOptions = Readonly<{
  durable: unknown; recorded: unknown; body: Readonly<{run_identity_cid?: unknown;
    effects: readonly Readonly<{effect_kind?: unknown; resolved_mapping_contract_cid?: unknown;
      source_binding_cid?: unknown; effect_identity_cid?: unknown; changes: readonly unknown[]}>[]}>;
  memberIndexes?: readonly number[]; runOriginal: RunOriginal;
}>;

const fail: (code: string, cause?: unknown) => never = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const wire = (value: unknown) => canonicalJson(value, {dataKeys: true});
const hash = (value: unknown) => 'sha256:' + createHash('sha256').update(wire(value)).digest('hex');
const cid = (value: unknown): value is string => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const closed = (value: unknown, keys: readonly string[]): value is Data => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
// Canonical DATA snapshots must also seal nested arrays/objects. These carry
// no original capabilities; current grants and physical owners stay separate.
const snapshot = <Value,>(value: Value): Value => {
  const freeze = (entry: unknown): unknown => {
    if (entry !== null && typeof entry === 'object') {
      for (const child of Object.values(entry)) freeze(child);
      Object.freeze(entry);
    }
    return entry;
  };
  return freeze(JSON.parse(wire(value))) as Value;
};
const installations = new WeakMap<object, ReturnType<typeof mockRowEffectDriver>['resourceObservation']>();
const updateRequestKeys = Object.freeze(['binding', 'mapping', 'target', 'value', 'version', 'before']);
const deleteRequestKeys = Object.freeze(['binding', 'mapping', 'target', 'version', 'before']);
const createRequestKeys = Object.freeze(['binding', 'mapping', 'target', 'value']);
const noFields = Object.freeze([]);
const operationOf = (target: Readonly<{write: Pick<Write, 'operation'>}>) => target.write.operation ?? 'update';
const recoveryKind = (kind: string) => 'mock-file-row-' + kind;
const responseAction = Object.freeze({create: 'created', update: 'updated', delete: 'deleted'});
const targetLimits = Object.freeze({maxFileBytes: 1048576, maxRows: 100,
  maxNodes: 16384, maxDepth: 32, maxWork: 16777216, maxResponseBytes: 65536,
  maxEffects: 16});
const synchronous = (value: unknown) => {
  if (value === undefined) return;
  if (value instanceof Promise) void value.catch(() => {});
  fail('InvalidMockFileCurrentFence');
};
const targetWire = (target: MockFileSelector) => typeof target === 'string' ? target : wire(target);
const ports = Object.freeze({
  admit: 'clientProgramRelationAdmitDocument',
  project: 'clientProgramRelationProjectTargetDocument',
  observe: 'clientProgramRelationObserveTarget',
  before: 'clientProgramRelationTargetBefore',
  version: 'clientProgramRelationTargetVersion',
  update: 'clientProgramRelationPrepareTargetUpdate',
  delete: 'clientProgramRelationPrepareTargetDelete',
  construction: 'clientProgramInstalledSourceConstructionCapacity',
} as const);
const createPorts = Object.freeze({
  insertContract: 'clientProgramRelationPrepareInsertContract',
  insertCapacity: 'clientProgramRelationInsertWorkspaceCapacity',
  insert: 'clientProgramRelationPrepareTargetInsert',
  createKey: 'clientProgramEffectFileCreateStorageKey',
} as const);
const orderedPorts = Object.freeze({
  findOrdered: 'clientProgramRelationFindOrderedTarget',
  orderedInsert: 'clientProgramRelationPrepareOrderedTargetInsert',
  orderedCapacity: 'clientProgramRelationOrderedMutationWorkspaceCapacity',
} as const);

// Internal DATA codec, shared by the actual locked writer and its component
// controls. It borrows the original Catalog/Common; it owns no file, Account,
// request admission, dispatch claim or current/cleanup capability.
export function createMockFileRowCodec({bundle, original, call, createContracts}:
  Readonly<{bundle: Pick<Bundle, 'sources'>; original: Pick<Source, 'declaration'>; call: CodecCall;
    createContracts?: ReadonlyMap<AdmissionTarget, unknown>}>) {
  const admit = (bytes: Uint8Array, target: AdmissionTarget, includeTarget = true) => {
    if (!bundle.sources.some(source => source === original && source.physical.includes(target.physical))) {
      fail('InvalidInstalledMockEffect');
    }
    const originalDocument = checked(call('admit', bytes, targetLimits.maxFileBytes,
      targetLimits.maxNodes, targetLimits.maxDepth, targetLimits.maxRows, targetLimits.maxWork));
    const projections = new Map<Source['physical'][number], unknown>();
    for (const source of bundle.sources) for (const model of source.physical) {
      // The CREATE codec checks its selected original using the retained
      // constructor. Other collections are still checked against this file.
      if (!includeTarget && source === original && model === target.physical) continue;
      const writable = source === original && model === target.physical
        ? target.write.writable_fields ?? noFields : model.writableFields;
      projections.set(model, checked(call('project', originalDocument, model.declaration,
        model.resource, model.itemsPath, model.keyPath, typeof model.primaryIdentity === 'string' ? model.primaryIdentity : undefined,
        model.preparedKey, writable)));
    }
    const selected = projections.get(target.physical);
    if (includeTarget && selected === undefined) fail('InvalidInstalledMockEffect');
    return {originalDocument, projections, selected};
  };
  const snapshotRow = (row: unknown) => {
    const beforeWire = call('before', row), versionCid = call('version', row);
    if (typeof beforeWire !== 'string' || !cid(versionCid)) fail('InvalidMockTargetObservation');
    const before = snapshot(JSON.parse(beforeWire) as Data);
    return {row, before, versionCid, beforeWire};
  };
  const observe = (document: Document, target: MockFileSelector) => snapshotRow(checked(call('observe', document.selected,
    original.declaration, targetWire(target))));
  const findOrdered = (document: Document, target: MockFileSelector) => {
    const matches = checked(call('findOrdered', document.selected, original.declaration, targetWire(target)));
    if (!Array.isArray(matches) || matches.length > 1) fail('InvalidMockTargetObservation');
    return matches.length === 0 ? undefined : snapshotRow(matches[0]);
  };
  return Object.freeze({admit, observe, findOrdered,
    replace(operation: string, bytes: Uint8Array, target: AdmissionTarget, record: RecordData, physicalOperation?: Charge) {
      if (operation !== 'update' && operation !== 'delete' && operation !== 'create' && operation !== 'upsert') {
        fail('InvalidMockEffectRequest');
      }
      const upsert = operation === 'upsert';
      if (upsert && (target.write.operation !== 'upsert' || target.physical.preparedKey === undefined ||
          (record.version === undefined) !== (record.before === undefined))) fail('InvalidMockEffectRequest');
      const identity = captureFileSelector(target.physical.primaryIdentity, record.target);
      // Re-admit the latest WHOLE document supplied by the SAME locked file
      // owner, then replace only the original row's admitted spans.
      physicalOperation?.chargeBytes(BigInt(bytes.length));
      if (operation === 'create') {
        const prepared = createContracts?.get(target);
        if (target.write.operation !== 'create' || prepared === undefined) fail('InvalidMockEffectRequest');
        const {originalDocument} = admit(bytes, target, false);
        const {itemsPath, keyPath} = target.physical;
        const replacement = checked(call('insert', originalDocument, prepared, itemsPath, keyPath,
          targetWire(identity), wire(record.value))) as Uint8Array;
        physicalOperation?.chargeBytes(BigInt(replacement.length));
        return replacement;
      }
      if (upsert && record.version === undefined) {
        const {originalDocument} = admit(bytes, target, false);
        const {preparedKey, itemsPath, keyPath} = target.physical;
        const replacement = checked(call('orderedInsert', originalDocument, preparedKey, itemsPath, keyPath,
          targetWire(identity), wire(record.value))) as Uint8Array;
        physicalOperation?.chargeBytes(BigInt(replacement.length));
        return replacement;
      }
      const document = admit(bytes, target), observed = observe(document, identity);
      if (observed.versionCid !== record.version || wire(observed.before) !== wire(record.before)) {
        fail('MockTargetVersionConflict');
      }
      if (record.version === undefined) fail('InvalidMockEffectRequest');
      const replacement = checked(operation === 'delete'
        ? call('delete', document.selected, observed.row, record.version, targetLimits.maxWork)
        : call('update', document.selected, observed.row, record.version, wire(record.value), targetLimits.maxWork)) as Uint8Array;
      physicalOperation?.chargeBytes(BigInt(replacement.length));
      return replacement;
    },
  });
}

// Complete logical row identities inside ONE unchanged physical boundary.
// The checked Catalog has already refused overlapping collection paths.
// Resource/Mapping aliases and values/versions are deliberately absent from
// the object identity: aliases cannot disguise the same physical row.
type MockFilePrimaryIdentity = string | Readonly<{kind: 'tuple'; fields: readonly string[]}>;
type MockFileFootprintTarget = Readonly<{
  physical: Pick<Physical, 'itemsPath' | 'keyPath'> & Readonly<{primaryIdentity: MockFilePrimaryIdentity}>;
  write: Pick<Write, 'resource'>;
  // Selected and checked by the Common Mapping consumer for an ordered key.
  resourceIdentityCid?: string;
}>;
type MockFileSelector = string | readonly string[];

function mockKeyComponents(value: unknown, min: number, max: number, allowEmpty: boolean,
  immutable: boolean): value is readonly string[] {
  if (!Array.isArray(value) || nodeTypes.isProxy(value) || (immutable && !Object.isFrozen(value)) ||
      Object.getPrototypeOf(value) !== Array.prototype || value.length < min || value.length > max ||
      Reflect.ownKeys(value).length !== value.length + 1) return false;
  let units = targetLimits.maxFileBytes;
  for (let index = 0; index < value.length; index++) {
    const component = Object.getOwnPropertyDescriptor(value, index);
    if (!component?.enumerable || typeof component.value !== 'string' ||
        component.value.length > units || !component.value.isWellFormed() || !allowEmpty && !component.value.length) return false;
    units -= component.value.length;
  }
  return true;
}

function captureFileSelector(primary: MockFilePrimaryIdentity, supplied: unknown): MockFileSelector {
  if (typeof primary === 'string') {
    if (typeof supplied !== 'string' || supplied.length > targetLimits.maxFileBytes || !supplied.isWellFormed()) {
      fail('InvalidMockEffectRequest');
    }
    return supplied;
  }
  const width = primary.fields.length;
  if (!mockKeyComponents(supplied, width, width, true, false)) fail('InvalidMockEffectRequest');
  const selected = Object.isFrozen(supplied) ? supplied : Object.freeze([...supplied]);
  if (Buffer.byteLength(wire(selected)) > targetLimits.maxFileBytes) fail('InvalidMockEffectRequest');
  return selected;
}

function sameFileSelector(original: MockFileSelector, other: unknown) {
  if (typeof original === 'string') return original === other;
  return mockKeyComponents(other, original.length, original.length, true, false) &&
    original.every((value, index) => value === other[index]);
}

type RequestTarget = Readonly<{
  physical: Readonly<{primaryIdentity: MockFilePrimaryIdentity}>;
  write: Readonly<{operation?: 'create' | 'delete' | 'update' | 'upsert'; writable_fields?: readonly string[];
    update_fields?: readonly string[]}>;
  mapping?: Readonly<{mappingCid?: string}>; beforeFields: readonly string[];
}>;

// The same exact DATA contract serves live capture and durable restoration.
export function prepareMockFileRequestRecord({bindingCid, target, record, preview}: Readonly<{
  bindingCid: string; target: RequestTarget; record: EffectRecord; preview?: unknown;
}>) {
  const {write, mapping, beforeFields, physical} = target;
  const kind = write.operation ?? 'update', creating = kind === 'create', deleting = kind === 'delete';
  const absent = kind === 'upsert' && record != null && !Object.hasOwn(record, 'before') && !Object.hasOwn(record, 'version');
  const unversioned = creating || absent;
  if (!closed(record, unversioned ? createRequestKeys : deleting ? deleteRequestKeys : updateRequestKeys) ||
      record.binding !== bindingCid || !cid(mapping?.mappingCid) || record.mapping !== mapping.mappingCid) {
    fail('InvalidMockEffectRequest');
  }
  const primary = physical.primaryIdentity;
  const selected = captureFileSelector(primary, record.target);
  const fields = write.update_fields ?? write.writable_fields;
  if ((!deleting && (record.value === null || typeof record.value !== 'object' || Array.isArray(record.value) ||
        Object.keys(record.value).length === 0 || !Object.keys(record.value).every(name => fields?.includes(name)))) ||
      (creating && (typeof selected !== 'string' || !/^[0-9a-f]{64}$/u.test(selected) ||
        !closed(record.value, write.writable_fields ?? noFields))) ||
      (!unversioned && (!cid(record.version) || !closed(record.before, beforeFields) ||
        (typeof primary === 'string' ? record.before[primary] !== selected :
          !primary.fields.every((name, index) => record.before![name] === selected[index]))))) {
    fail('InvalidMockEffectRequest');
  }
  if (typeof selected !== 'string' && preview !== undefined) {
    const change = preview as Readonly<{target_row_identity?: unknown; before?: Readonly<{state?: unknown; value?: unknown}>;
      target_guard?: Readonly<{state?: unknown; version_cid?: unknown}>}>;
    if (!sameFileSelector(selected, change?.target_row_identity) ||
        (absent ? change.before?.state !== 'absent' || change.target_guard?.state !== 'not_applicable' :
          change.before?.state !== 'present' || change.target_guard?.state !== 'version' ||
          change.target_guard.version_cid !== record.version || wire(change.before.value) !== wire(record.before))) {
      fail('InvalidMockEffectRecovery');
    }
  }
  const retainedWire = wire({...record, target: selected});
  if (Buffer.byteLength(retainedWire) > targetLimits.maxFileBytes) fail('InvalidMockEffectRequest');
  const original = Object.freeze({...record, target: selected,
    ...(deleting ? {} : {value: snapshot(record.value)}),
    ...(unversioned ? {} : {before: snapshot(record.before)})});
  return Object.freeze({record: original, retainedWire});
}

export function mockFileRowFootprint({bindingCid, target, selectors}: Readonly<{
  bindingCid: string; target: MockFileFootprintTarget; selectors: readonly MockFileSelector[];
}>) {
  if (!cid(bindingCid) || !Array.isArray(selectors) || nodeTypes.isProxy(selectors) ||
      selectors.length > targetLimits.maxRows) fail('InvalidMockEffectFootprint');
  const physical = target.physical, primary = physical.primaryIdentity;
  let schemeCid: string;
  const identities: string[] = [];
  if (typeof primary === 'string') {
    const scheme = {kind: 'mock-file-row-update',
      identity_fields: ['items_path', 'key_path', 'primary_identity', 'identity']};
    schemeCid = hash(scheme);
  } else {
    if (!primary || nodeTypes.isProxy(primary) || !Object.isFrozen(primary) ||
        Object.getPrototypeOf(primary) !== Object.prototype || Reflect.ownKeys(primary).length !== 2) {
      fail('InvalidMockEffectFootprint');
    }
    const kind = Object.getOwnPropertyDescriptor(primary, 'kind'), fields = Object.getOwnPropertyDescriptor(primary, 'fields');
    if (!kind?.enumerable || kind.value !== 'tuple' || !fields?.enumerable ||
        !mockKeyComponents(fields.value, 2, 128, false, true) || !cid(target.resourceIdentityCid)) {
      fail('InvalidMockEffectFootprint');
    }
    schemeCid = target.resourceIdentityCid;
  }
  for (let index = 0; index < selectors.length; index++) {
    const identity = Object.getOwnPropertyDescriptor(selectors, index)?.value as MockFileSelector | undefined;
    if (typeof primary === 'string') {
      if (typeof identity !== 'string' || !identity.isWellFormed()) fail('InvalidMockEffectFootprint');
    } else if (!mockKeyComponents(identity, primary.fields.length, primary.fields.length, true, true)) {
      // Common checks component types, including canonical decimal Strings for Signed64.
      fail('InvalidMockEffectFootprint');
    }
    identities.push(hash({items_path: physical.itemsPath, key_path: physical.keyPath,
      primary_identity: primary, identity}));
  }
  return Object.freeze({kind: 'exact_targets' as const, provider_namespace: 'local-mock-file',
    provider_boundary_cid: bindingCid, resource_kind: target.write.resource,
    resource_identity_scheme_cid: schemeCid,
    provider_object_identity_cids: Object.freeze(identities),
  });
}

export async function installPreparedProjectMockEffects({moon, mockPreparation,
  baseEnvironmentWire, authorizationFor, principalId, runtimeBundleCid, bindingCid, bindingFor,
  ledgerRoot, assertCurrent, effectResources, installationServices, io, observeWrite}: Installation) {
  if (typeof mockPreparation?.originalsForRuntime !== 'function' ||
      typeof mockPreparation.constructWritableRuntime !== 'function' ||
      typeof authorizationFor !== 'function' || typeof assertCurrent !== 'function' ||
      typeof principalId !== 'string' || !cid(runtimeBundleCid) ||
      (typeof bindingFor !== 'function' && !cid(bindingCid))) fail('InvalidInstalledMockEffect');
  const resourceMethods = Object.fromEntries(['bindRunOriginal', 'assertCurrent', 'limits'].map(name => {
    const field = effectResources === null || typeof effectResources !== 'object'
      ? undefined : Object.getOwnPropertyDescriptor(effectResources, name);
    if (field === undefined || !Object.hasOwn(field, 'value') ||
        typeof field.value !== 'function') fail('InstalledMockEffectResourcesUnavailable');
    return [name, field.value];
  }));
  const resources = Object.freeze(Object.fromEntries(Object.entries(resourceMethods)
    .map(([name, method]) => [name, (...args: unknown[]) => Reflect.apply(method, effectResources, args)]))) as Resources;
  const bundle = mockPreparation.originalsForRuntime(moon);
  if (!Array.isArray(bundle.writables) || bundle.writables.length === 0) fail('InstalledMockWritableTargetUnavailable');
  function current() {
    synchronous(assertCurrent());
    if (mockPreparation.originalsForRuntime(moon) !== bundle) fail('ForeignInstalledMockPreparation');
  }
  current();
  const create = bundle.writables.some(target => operationOf(target) === 'create');
  const ordered = bundle.sources.some(source => source.physical.some(model => model.preparedKey !== undefined));
  const methods = Object.fromEntries(Object.entries({...ports, ...(create ? createPorts : {}), ...(ordered ? orderedPorts : {})})
    .map(([name, port]) => [name, moon?.[port]]));
  if (!Object.values(methods).every(value => typeof value === 'function')) fail('InstalledMockTargetRuntimeUnavailable');
  const call: CodecCall = (name, ...args) => Reflect.apply(methods[name]!, moon, args);
  // The complete metadata implementation is held before the first file owner,
  // source-driver registry or source/alias vector is constructed.
  const implementation = await mockPreparation.constructWritableRuntime(moon, 'root', undefined, () => {
    const file = createMockFileTarget({dataPath: bundle.dataPath, maxBytes: targetLimits.maxFileBytes,
      assertCurrent: current, observeWrite, ...(io === undefined ? {} : {io})});
    return {file, sources: bundle.sources.filter(source => source.writes.length !== 0)};
  });
  const {file, sources} = implementation;
  let resourceObservation: ReturnType<typeof mockRowEffectDriver>['resourceObservation'] | undefined;
  try {
    const installed = await composeInstalledEffects(sources,
      {moon, baseEnvironmentWire, installationServices}, async (original, _options, retain) => {
        const prepared = original.effectPrepared, catalogue = original.catalogue;
        if (typeof original.effectMember?.load !== 'function' || prepared?.declaration !== original.declaration ||
            prepared!.environment === undefined) fail('InstalledSourceInitializationUnavailable');
        const selectedBinding = bindingFor === undefined ? sources.length === 1 ? bindingCid : undefined
          : bindingFor(original);
        if (!cid(selectedBinding)) fail('ForeignInstalledMockSourceBinding');
        const authorization = await authorizationFor(catalogue.connection);
        current();
        const constructed = await mockPreparation.constructWritableRuntime<ConstructedDriver>(moon, 'source', original, () => {
          const targets = bundle.writables.filter(target => target.source === original);
          if (targets.some(target => target.mapping === undefined || target.mapping.body !== target.write.mappingWire ||
              target.physical.declaration !== original.declaration ||
              typeof target.physical.primaryIdentity !== 'string' &&
                !cid(target.mapping.resourceIdentityCid))) fail('InvalidInstalledMockEffect');
          const spec = targets[0].write;
          let createContracts: Map<AdmissionTarget, unknown> | undefined;
          for (const target of targets) {
            if (operationOf(target) !== 'create') continue;
            const {declaration, resource, primaryIdentity} = target.physical;
            if (typeof primaryIdentity !== 'string') fail('InvalidInstalledMockEffect');
            (createContracts ??= new Map()).set(target, checked(call('insertContract', declaration, resource,
              primaryIdentity, targetLimits.maxFileBytes, targetLimits.maxNodes, targetLimits.maxDepth,
              targetLimits.maxRows)));
          }
          const constructed = mockRowEffectDriver({bundle, original, targets,
            bindingCid: selectedBinding, principalId, authorization, current, call, resources, file, createContracts});
          if (createContracts === undefined && targets.every(target => target.physical.preparedKey === undefined &&
              target.write.permission === spec.permission &&
              target.write.observe_permission === spec.observe_permission)) {
            return {...constructed, targets,
              managedPlanRecipe: mockFileEffectPlanRecipe(moon, bundle, spec.permission, spec.observe_permission)};
          }
          const recipes: Record<string, Readonly<{targetReadOperation: string | undefined; recipe: Recipe}>> = Object.create(null);
          for (const target of targets) {
            const {mapping, write, physical} = target;
            const insert = createContracts?.get(target);
            const targetReadOperation = insert === undefined ? write.observe_permission : undefined;
            const insertion = insert === undefined ? undefined : (size: number, units: number) =>
              checked(call('insertCapacity', insert, physical.itemsPath.length, size, units));
            const orderedCapacity = physical.preparedKey === undefined ? undefined : Object.freeze({
              canInsert: write.operation === 'upsert',
              workspace: (size: number, keyUnits: number, mappedUnits?: number) => checked(call('orderedCapacity',
                physical.preparedKey, physical.itemsPath.length, size, keyUnits, mappedUnits)),
            });
            recipes[mapping!.mappingCid] = Object.freeze({targetReadOperation,
              recipe: mockFileEffectPlanRecipe(moon, bundle, write.permission, targetReadOperation, insertion, orderedCapacity)});
          }
          return {...constructed, targets,
            managedTargetPlanRecipes: prepareInstalledTargetPlanRecipes(prepared!.mappings, Object.freeze(recipes))};
        });
        const {driver, site, targets, managedPlanRecipe, managedTargetPlanRecipes} = constructed;
        // Every driver observes this SAME physical file. Reuse an existing
        // original observer for whole-project custody instead of allocating
        // another Run registry. This selects no grant or dispatch authority.
        resourceObservation ??= constructed.resourceObservation;
        try {
          // A member is consumed ONCE with ALL of its original prepared
          // mappings. Logical routing happens inside this same installed driver.
          const effect = await original.effectMember.load({moon, mappings: prepared!.mappings,
            environmentWire: prepared!.environment.wire, connectorId: catalogue.connectorId,
            connectorRegistration: catalogue.registration, connectorRevision: catalogue.revision,
            connection: catalogue.connection, site, authorization, runtimeBundleCid,
            bindingCid: selectedBinding, ledgerRoot, driver, managedPlanRecipe,
            ...(managedTargetPlanRecipes === undefined ? {} : {managedTargetPlanRecipes}), effectResources: resources,
            limits: {maxRows: targetLimits.maxRows}}) as Effect;
          retain(effect);
          current();
          const projection = await mockPreparation.constructWritableRuntime(moon, 'aliases', original, () => {
            const aliases = targets.flatMap(target => target.write.aliases.map(name =>
              Object.freeze({name, targetRef: (target.mapping as InstalledMapping).target})));
            return retainInstalledRowEffectAdapter(effect, Object.freeze({...effect,
              queryUpdateTargets: installedUpdateTargets(effect, aliases)}));
          });
          installations.set(projection, constructed.resourceObservation);
          return projection;
        } catch (cause) {
          try {await site.close();} catch (cleanup) {
            throw Object.assign(new Error('InstalledMockEffectCleanupPending', {cause}),
              {code: 'InstalledMockEffectCleanupPending', cleanupPending: true,
                cleanupHandle: Object.freeze({status: site.status, retry: site.close}), cleanup});
          }
          throw cause;
        }
      });
    if (resourceObservation === undefined) fail('InstalledMockWritableTargetUnavailable');
    installations.set(installed, resourceObservation);
    return installed;
  } catch (cause) {
    // Existing aggregate custody drains the original failure and this shared
    // physical owner independently. Unknown/missing ACKs stay pending.
    throw await retainInstalledHostInitializationFailure(cause, {sourceProfile: {close: file.close}});
  }
}

// One finite file operation window. Common supplies parser/control tariffs;
// only the actual declared projections and file/replacement buffers vary here.
// Returned request/response DATA has the existing JSON recipe and output guard.
export function mockFileEffectPlanRecipe(moon: RecipeRuntime, bundle: Pick<Bundle, 'sources' | 'writables'>,
  operation: string, targetReadOperation: string | undefined, insertion?: InsertCapacity,
  ordered?: OrderedCapacity): Recipe {
  const bytes = BigInt(targetLimits.maxFileBytes), nodes = BigInt(targetLimits.maxNodes);
  const projections = BigInt(bundle.sources.reduce((sum, source) => sum + source.physical.length, 0));
  const workspace = Object.freeze({nodes: 4n * nodes * projections,
    text: bytes * projections, wire: bytes});
  const zero = Object.freeze({nodes: 0n, text: 0n, wire: 0n});
  const capacity = (value: Extent) => checked(moon.clientProgramInstalledSourceConstructionCapacity(
    0n, 0n, 0n, value.nodes, value.text, value.wire));
  const decode = checked(moon.clientProgramInstalledFileEffectConstructionCapacity(
    capacity(zero), targetLimits.maxFileBytes, targetLimits.maxNodes, targetLimits.maxDepth));
  const executionBytes = (original: unknown) =>
    runtimeField(moon.clientProgramSerializationCapacityBytes(original), 1) as bigint;
  // The guarded request child drops the parser and document when the original
  // file read closes. Keep the complete simultaneous peak, while the row's
  // immutable request uses the separate retained request envelope.
  const requestConstruction = insertion === undefined
    ? checked(moon.clientProgramInstalledFileEffectConstructionCapacity(
      capacity(ordered === undefined ? workspace : {...workspace, wire: workspace.wire +
        executionBytes(ordered.workspace(1, targetLimits.maxFileBytes))}),
      targetLimits.maxFileBytes, targetLimits.maxNodes, targetLimits.maxDepth))
    : checked(moon.clientProgramInstalledFileEffectConstructionCapacity(
      capacity(zero), 512, 7, 1));
  // Projection owns checked values, admitted wrappers and row/cell indexes;
  // the file decoder is separate. Replacement Bytes coexist with original
  // file backing. Write additionally copies replacement Bytes into its Buffer.
  let construction: Readonly<{retained: Extent; workspace: Extent}>;
  let physicalInput: Parameters<typeof prepareInstalledPhysicalWritePlanRecipe>[0]['physicalInput'];
  if (insertion === undefined && ordered === undefined) {
    construction = Object.freeze({retained: zero,
      workspace: Object.freeze({...workspace, wire: 2n * bytes})});
  } else {
    // The locked child drops its original document, row decoder and complete
    // replacement before returning. Retain only the child/response controls
    // and bounded JSON observation; keep both full native peaks in live E.
    // The insertion already funds its replacement Bytes, and the writer
    // still needs a separate copy of those Bytes in its Buffer.
    const retained = Object.freeze({nodes: 40n, text: 512n, wire: BigInt(targetLimits.maxResponseBytes)});
    // The largest insertion output room is at the smallest admitted file.
    // For ordered mutations the immutable request includes the entire key.
    const extra = (size: number, units: number) => insertion !== undefined
      ? executionBytes(insertion(size, units))
      : executionBytes(ordered!.workspace(size, units,
        ordered!.canInsert && size < targetLimits.maxFileBytes ? units : undefined));
    const outputBytes = insertion === undefined ? 2n * bytes : bytes;
    construction = Object.freeze({retained, workspace: Object.freeze({...workspace,
      wire: outputBytes + executionBytes(decode) + extra(1, targetLimits.maxFileBytes)})});
    const exactCapacity = (work: Extent) => checked(moon.clientProgramInstalledSourceConstructionCapacity(
      retained.nodes, retained.text, retained.wire, work.nodes, work.text, work.wire));
    physicalInput = Object.freeze({
      // The held child can open and check its FD and lock plus construct
      // the bounded extent. File buffers are allocated after selection.
      initialCapacity: exactCapacity({nodes: 64n, text: 0n, wire: 0n}),
      capacity(size, requestUnits) {
        if (!Number.isSafeInteger(size) || size < 1 || size > targetLimits.maxFileBytes ||
            insertion !== undefined && size === targetLimits.maxFileBytes ||
            !Number.isSafeInteger(requestUnits) || requestUnits < 1 || requestUnits > targetLimits.maxFileBytes) {
          fail('InvalidMockEffectRequest');
        }
        const fileNodes = Math.min(size, targetLimits.maxNodes);
        const fileDecoder = checked(moon.clientProgramInstalledFileEffectConstructionCapacity(capacity(zero),
          size, fileNodes, Math.min(fileNodes, targetLimits.maxDepth)));
        return exactCapacity({nodes: 4n * BigInt(fileNodes) * projections, text: BigInt(size) * projections,
          wire: outputBytes + executionBytes(fileDecoder) + extra(size, requestUnits)});
      },
    });
  }
  const inputLimits = installedRowEffectConstructionLimits({maxRows: targetLimits.maxRows});
  let footprintCapacity;
  if (bundle.writables.length > 1 || insertion !== undefined || ordered !== undefined) {
    const geometry = declaredProjectMockFootprintConstructionGeometry(bundle.writables,
      targetLimits.maxRows, targetLimits.maxFileBytes);
    footprintCapacity = capacity(geometry.workspace);
  }
  return prepareInstalledPhysicalWritePlanRecipe({moon, operation, inputLimits,
    construction, ...(insertion === undefined && ordered === undefined ? {physicalConstruction: decode} : {}),
    requestConstruction, targetReadOperation, physicalInput,
    ...(footprintCapacity === undefined ? {} : {footprintCapacity}),
    limits: Object.freeze({maxRequestBytes: targetLimits.maxFileBytes,
      maxRecoveryBytes: targetLimits.maxFileBytes, maxResponseBytes: targetLimits.maxResponseBytes,
      maxOutcomeBytes: targetLimits.maxResponseBytes, maxTransferBytes: 2 * targetLimits.maxFileBytes})});
}

// Only this actual factory result retains the physical file owner. A copied
// adapter, limits object or status shape cannot supply its cleanup receipts.
export function observeInstalledMockEffectResources(effect: object) {
  const original = installations.get(effect);
  if (original === undefined) fail('ForeignInstalledMockEffect');
  return original;
}

// Local physical use has no remote Credential. The private use identity below
// records the original current Account/Checkpoint decision; it grants nothing.
// The generic Row Effect still admits the same Preview and durable row claim
// before calling send, and persists the observed bytes before settlement.
function mockRowEffectDriver({bundle, original, targets, bindingCid, principalId,
  authorization, current, call, resources, file, createContracts}: Readonly<{
  bundle: Bundle; original: Source; targets: readonly Target[]; bindingCid: string; principalId: string;
  authorization: Authorization; current(): void; call: CodecCall; resources: Resources; file: File; createContracts?: ReadonlyMap<AdmissionTarget, unknown>;
}>) {
  const maximum = targetLimits.maxFileBytes, work = targetLimits.maxWork;
  const catalogue = original.catalogue, profile = targets[0].write;
  const requests = new WeakMap<object, HeldRequest>(), descriptions = new WeakMap<object, Description>(),
    grants = new WeakMap<object, Grant>();
  const codec = createMockFileRowCodec({bundle, original, call, createContracts});
  const {admit, observe, findOrdered} = codec;
  const retainedRuns = new WeakSet<RunOriginal>();
  // A plural member description adds ONE borrowed target link. The existing
  // same-Run control constructor admits its explicit logical allowance before
  // that field exists. This is not global inventory funding or authority.
  const targetDescriptionCapacity = targets.length === 1 ? undefined
    : checked(call('construction', 1n, 0n, 0n, 1n, 0n, 0n));
  function targetForRecord(record: Readonly<{mapping?: unknown}> | null | undefined) {
    const target = targets.find(value => value.mapping!.mappingCid === record?.mapping);
    if (target === undefined) fail('InvalidMockEffectRequest');
    return target;
  }
  function runCurrent(runOriginal: RunOriginal) {
    current();
    if (runOriginal === null || typeof runOriginal !== 'object') fail('ForeignMockEffectRun');
    synchronous(resources.assertCurrent(runOriginal));
    retainedRuns.add(runOriginal);
  }
  function retainRun(runOriginal: RunOriginal) {
    // Cleanup of a known original remains reachable after authority/currentness
    // changes. A previously unseen object still requires the nominal owner.
    if (runOriginal === null || typeof runOriginal !== 'object' ||
        !retainedRuns.has(runOriginal)) runCurrent(runOriginal);
    return runOriginal;
  }
  const resourceObservation = Object.freeze({
    limits(runOriginal: RunOriginal) {runCurrent(runOriginal); return targetLimits;},
    statusFor(runOriginal: RunOriginal) {return file.statusFor(retainRun(runOriginal));},
    closeFor(runOriginal: RunOriginal) {return file.closeFor(retainRun(runOriginal));},
  });
  function memberCurrent(member: Member): Target {
    current();
    if (member === null || typeof member !== 'object') fail('ForeignMockEffectMember');
    const target = targets.find(value => member.resource === value.write.resource &&
      member.kind === operationOf(value) && member.mapping?.mappingCid === value.mapping!.mappingCid &&
      member.mapping?.mappingRef === value.mapping!.mappingRef);
    if (target === undefined) fail('ForeignMockEffectMember');
    return target;
  }
  function description(value: object, runOriginal: RunOriginal | undefined, target: Target | undefined) {
    current();
    const original = descriptions.get(value);
    if (original === undefined || runOriginal !== undefined &&
        original.runOriginal !== runOriginal) fail('ForeignMockTargetDescription');
    if (target !== undefined && (original.target ?? targets[0]) !== target) fail('ForeignMockTargetDescription');
    runCurrent(original.runOriginal);
    return original;
  }
  function describe({member, runInvocationCid, dispatchRequestCid, runOriginal, controlConstruction}: DescribeOptions) {
    const target = memberCurrent(member);
    runCurrent(runOriginal);
    const limits = resources.limits(runOriginal);
    if (!closed(limits, Object.keys(targetLimits)) || Object.entries(targetLimits)
      .some(([name, maximum]) => !Number.isSafeInteger(limits[name]) || (limits[name] as number) < maximum)) {
      fail('InstalledMockEffectLimitsUnavailable');
    }
    if (!cid(runInvocationCid) || !cid(dispatchRequestCid)) fail('ForeignMockTargetDescription');
    const construct = () => {
      const value = Object.freeze({});
      descriptions.set(value, Object.freeze({runInvocationCid, dispatchRequestCid, runOriginal,
        ...(targets.length === 1 ? {} : {target})}));
      return value;
    };
    if (targetDescriptionCapacity === undefined) return construct();
    if (typeof controlConstruction !== 'function') fail('InstalledMockTargetConstructionUnavailable');
    return controlConstruction(undefined, construct, [], targetDescriptionCapacity);
  }
  function decisionCurrent(decision: Decision, kind: GrantKind, resource: string) {
    current();
    const facts = authorizationDispatchFacts(decision);
    if (facts?.principal !== principalId || facts!.configurationCid !== authorization.configurationCid ||
        decision.action !== 'dispatch' || decision.tuple?.connection !== catalogue.connection ||
        decision.tuple?.resource !== resource ||
        decision.tuple?.operation !== (kind === 'read' ? 'read' : 'effect') ||
        decision.boundary !== (kind === 'read' ? 'acquisition' : 'effect_commit') ||
        (kind === 'write' && (decision.basis !== 'resumed' ||
          !cid(decision.checkpointCid) || !cid(decision.resolutionCid)))) {
      fail('MockTargetNotAuthorized');
    }
    assertAuthorizationAccountCurrent(decision);
    current();
  }
  function issue(kind: GrantKind, {operation, decision, resource, runInvocationCid,
    dispatchRequestCid, subjectCid, maxUses}: GrantOptions) {
    if (!targets.some(target => target.write.resource === resource &&
        operation === (kind === 'read' ? target.write.observe_permission : target.write.permission)) ||
        !cid(runInvocationCid) ||
        !cid(dispatchRequestCid) || (kind === 'read' && maxUses !== 1) ||
        (kind === 'write' && (!cid(subjectCid) || decision?.subjectCid !== subjectCid))) {
      fail('MockTargetNotAuthorized');
    }
    decisionCurrent(decision, kind, resource);
    const proof = Object.freeze({});
    grants.set(proof, {operation, decision, runInvocationCid, dispatchRequestCid, subjectCid, used: false});
    return Object.freeze({proof});
  }
  function consume(kind: GrantKind, supplied: SuppliedUse, selected: object, target: Target) {
    const grant = grants.get(supplied?.proof!), original = description(selected, undefined, target);
    if (grant === undefined || grant.used ||
        grant.operation !== (kind === 'read' ? target.write.observe_permission : target.write.permission) ||
        grant.runInvocationCid !== original.runInvocationCid ||
        grant.dispatchRequestCid !== original.dispatchRequestCid ||
        grant.decision.tuple.resource !== target.write.resource ||
        typeof supplied.useId !== 'string' || Buffer.byteLength(supplied.useId) > 4096) {
      fail('ForeignMockTargetUse');
    }
    decisionCurrent(grant.decision, kind, target.write.resource);
    grant.used = true;
    return Object.freeze({grant,
      useCid: hash({kind: 'mock-file-' + kind, binding_cid: bindingCid,
        invocation_cid: grant.runInvocationCid, dispatch_request_cid: grant.dispatchRequestCid,
        subject_cid: grant.subjectCid ?? null, use_id: supplied.useId,
        configuration_cid: authorizationDispatchFacts(grant.decision)!.configurationCid,
        checkpoint_cid: grant.decision.checkpointCid ?? null,
        resolution_cid: grant.decision.resolutionCid ?? null})});
  }
  const useCurrent = (use: UsedGrant | undefined, kind: GrantKind, target: Target) => {
    if (use !== undefined) decisionCurrent(use.grant.decision, kind, target.write.resource);
  };
  function own(request: object, runOriginal?: RunOriginal) {
    current();
    const record = requests.get(request);
    if (record === undefined || runOriginal !== undefined &&
        record.runOriginal !== runOriginal) fail('ForeignMockEffectRequest');
    return record;
  }
  function requestFrom(record: EffectRecord, runOriginal: RunOriginal, preview?: unknown) {
    runCurrent(runOriginal);
    const target = targetForRecord(record);
    const {record: original, retainedWire} = prepareMockFileRequestRecord({bindingCid, target, record, preview});
    const request = Object.freeze({});
    requests.set(request, Object.freeze({record: original,
      cid: 'sha256:' + createHash('sha256').update(retainedWire).digest('hex'),
      runOriginal, retainedWire}));
    return request;
  }
  function fileCreateKey(original: FileCreateIdentity | undefined, row: unknown) {
    if (!closed(row, ['content_cid', 'occurrence']) || !cid(row.content_cid) ||
        typeof row.occurrence !== 'number' || !Number.isSafeInteger(row.occurrence) || row.occurrence < 0 || row.occurrence > 2147483647 ||
        !cid(original?.runDefinitionCid) || !cid(original.sourceBindingCid) || !cid(original.effectIdentityCid)) {
      fail('InvalidMockEffectRequest');
    }
    const key = checked(call('createKey', original.runDefinitionCid, original.sourceBindingCid,
      original.effectIdentityCid, row.content_cid, row.occurrence));
    if (typeof key !== 'string') fail('InvalidMockEffectRequest');
    return key;
  }
  function requestChild({member, selector, value, current: selected, authorizationForRow, signal,
    runOriginal, createRowIdentity, fileCreateIdentity}: ReadOptions) {
    const target = memberCurrent(member), mapping = target.mapping;
    description(selected, runOriginal, target);
    runCurrent(runOriginal);
    if (member.kind === 'create') {
      let open = true, output: RequestOutput | undefined;
      const release = () => {open = false; output = undefined;};
      return Object.freeze({release, retry:release, status:() => ({pending:open}),
        prepare() {
          if (!open || output !== undefined) fail('ForeignMockEffectRequest');
          signal?.throwIfAborted();
          description(selected, runOriginal, target);
          const request = requestFrom({binding:bindingCid, mapping:mapping!.mappingCid,
            target:fileCreateKey(fileCreateIdentity, createRowIdentity), value}, runOriginal);
          output = Object.freeze({request, requestCid:own(request, runOriginal).cid});
          return output;
        }});
    }
    if (typeof authorizationForRow !== 'function') fail('InvalidMockEffectRequest');
    const identity = captureFileSelector(target.physical.primaryIdentity, selector);
    let use: UsedGrant | undefined, output: RequestOutput | undefined;
    const child = file.readChild({signal, runOriginal,
      assertCurrent: () => {runCurrent(runOriginal); useCurrent(use, 'read', target);},
      async authorize() {use = consume('read', await authorizationForRow(), selected, target);},
      consume(bytes) {
        const document = admit(bytes, target);
        const observed = member.kind === 'upsert' ? findOrdered(document, identity) : observe(document, identity);
        const deleting = member.kind === 'delete';
        if (deleting) {
          if (value !== undefined) fail('InvalidMockEffectRequest');
        } else if (observed !== undefined) {
          checked(call('update', document.selected, observed.row, observed.versionCid, wire(value), work));
        }
        const request = requestFrom({binding: bindingCid, mapping: mapping!.mappingCid,
          target: identity, ...(deleting ? {} : {value}),
          ...(observed === undefined ? {} : {version: observed.versionCid, before: observed.before})}, runOriginal);
        const original = requests.get(request)!;
        requests.set(request, Object.freeze({...original, observedAt: selected}));
        output = Object.freeze({request, requestCid: original.cid});
        return output;
      }});
    return Object.freeze({prepare: child.prepare, release: child.release, retry: child.retry, status: child.status,
      retainedOutputWire(value: unknown) {
        if (value !== output || output === undefined || child.status().pending !== false) {
          fail('ForeignMockEffectRequest');
        }
        return own(output.request, runOriginal).retainedWire;
      }});
  }
  async function retireChild(child: Retirable, failed: boolean, primary: unknown) {
    let cleanup: unknown, cleanupFailed = false;
    try {
      const result = await child.release();
      if (result?.pending !== false || child.status().pending !== false) fail('MockFileCleanupPending');
    } catch (cause) {cleanup = cause; cleanupFailed = true;}
    if (cleanupFailed) throw Object.assign(new Error('MockFileCleanupPending',
      {cause: failed ? primary : cleanup}), {code: 'MockFileCleanupPending', cleanupPending: true,
      cleanupHandle: Object.freeze({status: child.status, retry: child.retry})});
    if (failed) throw primary;
  }
  const recover = ({durable, recorded, body, memberIndexes, runOriginal}: RecoveryOptions) => {
    current();
    runCurrent(runOriginal);
    if (!Array.isArray(body?.effects)) fail('InvalidMockEffectRecovery');
    const selected = memberIndexes ?? body.effects.map((_, index) => index);
    if (!Array.isArray((durable as {connectorRecovery?: unknown} | null)?.connectorRecovery) || !Array.isArray((recorded as {members?: unknown} | null)?.members) ||
        body.effects.length > targetLimits.maxEffects || !Array.isArray(selected) ||
        selected.length > targetLimits.maxEffects) {
      fail('InvalidMockEffectRecovery');
    }
    const restored: object[][] = [], currents: undefined[] = [];
    let previous = -1;
    for (const index of selected) {
      if (!Number.isSafeInteger(index) || index <= previous || index >= body.effects.length) {
        fail('InvalidMockEffectRecovery');
      }
      previous = index;
      const member = body.effects[index];
      if (member.effect_kind !== 'update' && member.effect_kind !== 'delete' &&
          member.effect_kind !== 'create' && member.effect_kind !== 'upsert') {
        fail('InvalidMockEffectRecovery');
      }
      const target = targetForRecord({mapping: member.resolved_mapping_contract_cid});
      const entries = (durable as {connectorRecovery: readonly RecoveryEntry[]}).connectorRecovery.filter(entry => entry.memberIndex === index);
      if (operationOf(target) !== member.effect_kind || entries.length !== 1 || entries[0].kind !== recoveryKind(member.effect_kind) ||
          typeof entries[0].wire !== 'string' || Buffer.byteLength(entries[0].wire) > maximum) {
        fail('InvalidMockEffectRecovery');
      }
      const data = JSON.parse(entries[0].wire) as {binding: unknown; requests: EffectRecord[]};
      if (!closed(data, ['binding', 'requests']) || data.binding !== bindingCid ||
          hash(data) !== entries[0].observationCid || !Array.isArray(data.requests) ||
          data.requests.length > targetLimits.maxRows ||
          data.requests.length !== body.effects[index]?.changes.length) {
        fail('InvalidMockEffectRecovery');
      }
      const original = member.effect_kind !== 'create' ? undefined : {
        runDefinitionCid:body.run_identity_cid, sourceBindingCid:member.source_binding_cid,
        effectIdentityCid:member.effect_identity_cid,
      };
      const requests = data.requests.map((record, row) => {
        if (record?.mapping !== target.mapping!.mappingCid) fail('InvalidMockEffectRecovery');
        const change = member.changes[row] as Readonly<{target_row_identity?: unknown}> | undefined;
        if (change === undefined || original !== undefined && record.target !== fileCreateKey(original, change.target_row_identity)) {
          fail('InvalidMockEffectRecovery');
        }
        return requestFrom(record, runOriginal, change);
      });
      // The common owner separately matches every rebuilt CID/target/value to
      // its original sealed Preview and durable row claim; this is DATA only.
      restored.push(requests);
      currents.push(undefined);
    }
    return {requests: restored, currents};
  };
  const supportedKinds = Object.freeze(['create', 'update', 'delete', 'upsert']
    .filter(kind => targets.some(target => operationOf(target) === kind)));
  const driver = Object.freeze({
    kinds: supportedKinds, targetRead: Object.freeze({operation: profile.observe_permission}),
    writeOperation: (member: Member) => memberCurrent(member).write.permission, describe,
    prepareRequest() {fail('MockOriginalTargetObservationRequired');},
    prepareRequestChild: requestChild,
    requestFacts(request: object) {
      const {record} = own(request);
      return operationOf(targetForRecord(record)) === 'create' ? {value:record.value} :
        {value:record.value, target:record.target};
    },
    requestCid: (request: object) => own(request).cid,
    recheckRequests({member, entries, current: selected, runOriginal}: CurrentTarget & RequestEntries) {
      const target = memberCurrent(member);description(selected, runOriginal, target);runCurrent(runOriginal);
      for (const entry of entries) {
        if (targetForRecord(own(entry.request, runOriginal).record) !== target) fail('ForeignMockEffectRequest');
      }
    },
    async observeTargets({member, entries, current: selected, authorizationForRow, signal, runOriginal, ownedReadChild}: ObserveOptions) {
      const target = memberCurrent(member);description(selected, runOriginal, target);runCurrent(runOriginal);
      const result = [];
      for (const [index, entry] of entries.entries()) {
        const original = own(entry.request, runOriginal), {record} = original;
        if (targetForRecord(record) !== target) fail('ForeignMockEffectRequest');
        if (original.observedAt === selected) {
          result.push(record.version === undefined ? {identity: record.target, state: 'absent'}
            : {identity: record.target, versionCid: record.version, before: record.before});
          continue;
        }
        let use: UsedGrant | undefined, primary: unknown, observed: TargetObservation | undefined, retainedWire: string | undefined, failed = false;
        const constructChild = () => {
          const child = file.readChild({signal, runOriginal,
          assertCurrent: () => {runCurrent(runOriginal); useCurrent(use, 'read', target);},
          async authorize() {use = consume('read', await authorizationForRow(index), selected, target);},
          consume(bytes) {
            const document = admit(bytes, target);
            const value = member.kind === 'upsert' ? findOrdered(document, record.target) : observe(document, record.target);
            if (value === undefined) {
              const observation = Object.freeze({identity: record.target, state: 'absent'} as const);
              retainedWire = wire(observation);
              return observation;
            }
            // Reuse the already emitted canonical before wire from Common.
            retainedWire = '{"before":' + value.beforeWire + ',"identity":' + wire(record.target) +
              ',"versionCid":' + wire(value.versionCid) + '}';
            return Object.freeze({identity: record.target, versionCid: value.versionCid, before: value.before});}});
          return Object.freeze({status: child.status, release: child.release, retry: child.retry,
            retainedOutputWire(value: unknown) {
              if (value !== observed || failed || observed === undefined || child.status().pending !== false) {
                fail('ForeignMockTargetObservation');
              }
              return retainedWire!;
            },
            async prepare() {
              try {observed = await child.prepare();} catch (cause) {primary = cause; failed = true;}
              // The detached before/version DATA cannot retain the file's
              // parser. Observe its real close ACK before this window ends.
              await retireChild(child, failed, primary);
              return observed!;
            }});
        };
        observed = ownedReadChild === undefined ? await constructChild().prepare()
          : await ownedReadChild(constructChild, index);
        result.push(observed);
      }
      return result;
    },
    footprint({member, entries}: Readonly<{member: Member}> & RequestEntries) {
      const target = memberCurrent(member);
      if (bundle.writables.length === 1 && member.kind !== 'create' &&
          typeof target.physical.primaryIdentity === 'string') return {providerNamespace: 'local-mock-file',
        resourceKind: target.write.resource, boundaryCid: bindingCid};
      const selectors = entries.map(entry => {
        const {record} = own(entry.request);
        if (targetForRecord(record) !== target) fail('ForeignMockEffectRequest');
        return record.target;
      });
      return mockFileRowFootprint({bindingCid, target: {
        physical: target.physical, write: target.write, resourceIdentityCid: target.mapping!.resourceIdentityCid,
      }, selectors});
    },
    recoveryEntry({member, entries}: RequestEntries & Readonly<{member: Member}>) {
      const data = {binding: bindingCid, requests: entries.map(entry => own(entry.request).record)};
      const body = wire(data);
      if (Buffer.byteLength(body) > maximum) fail('MockEffectRecoveryLimit');
      return {kind: recoveryKind(member.kind), observationCid: hash(data), wire: body};
    },
    recoverRequests: recover, recoverMemberRequests: recover,
    async send({member, request, current: selected, authorization: supplied, signal, runOriginal, physicalOperation}: SendOptions) {
      const target = memberCurrent(member);description(selected, runOriginal, target);runCurrent(runOriginal);
      const stagedInput = member.kind === 'create' || target.physical.preparedKey !== undefined;
      if (stagedInput && typeof physicalOperation?.admitInput !== 'function') fail('InstalledEffectPhysicalPlanUnavailable');
      const {record, cid: requestCid, retainedWire} = own(request, runOriginal);
      if (targetForRecord(record) !== target) fail('ForeignMockEffectRequest');
      let use: UsedGrant | undefined, primary: unknown, failed = false;
      const child = file.updateChild({signal, runOriginal,
        assertCurrent: () => {runCurrent(runOriginal); useCurrent(use, 'write', target);},
        authorize() {use = consume('write', supplied, selected, target);},
        ...(stagedInput ? {fundRead: (size: number) => physicalOperation!.admitInput!(size, retainedWire.length)} : {}),
        replace(bytes) {
          return codec.replace(member.kind, bytes, target, record, physicalOperation);
        }});
      try {
        physicalOperation?.retainPhysicalChild(child);
        await child.prepare();
      } catch (cause) {primary = cause; failed = true;}
      await retireChild(child, failed, primary);
      current();
      return Object.freeze({observation: Object.freeze({useCid: use!.useCid, statusCode: 200,
        body: Buffer.from(wire({request_cid: requestCid, target: record.target,
          action: member.kind === 'upsert' ? record.version === undefined ? 'created' : 'updated' :
            responseAction[member.kind as keyof typeof responseAction]}))})});
    },
    project({request, observation}: Readonly<{request: object; observation?: Observation}>) {
      const {record, cid: requestCid} = own(request);
      const kind = operationOf(targetForRecord(record));
      const action = kind === 'upsert' ? record.version === undefined ? 'created' : 'updated' : responseAction[kind];
      if (!cid(observation?.useCid) || observation.statusCode !== 200 ||
          !(observation.body instanceof Uint8Array) ||
          observation.body.length > targetLimits.maxResponseBytes) {
        return {kind: 'unknown'};
      }
      let response: unknown;
      try {response = JSON.parse(Buffer.from(observation.body).toString('utf8'));}
      catch {return {kind: 'unknown'};}
      if (!closed(response, ['request_cid', 'target', 'action']) ||
          response.request_cid !== requestCid || !sameFileSelector(record.target, response.target) || response.action !== action) {
        return {kind: 'unknown'};
      }
      // The private physical receipt distinguishes DELETE, while the admitted
      // applied outcome's optional action describes only create/update.
      return {kind: 'typed-success-response', outcome: {state: 'applied',
        ...(action === 'deleted' ? {} : {action}),
        result: typeof record.target === 'string' ? {id: record.target} : {key: record.target}}};
    },
  });
  const site = Object.freeze({issueReadGrant: (options: GrantOptions) => issue('read', options),
    issueEffectGrant: (options: GrantOptions) => issue('write', options), status: file.status, close: file.close});
  return {driver, site, resourceObservation};
}
