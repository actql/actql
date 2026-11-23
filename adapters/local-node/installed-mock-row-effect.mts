// The explicit Project Mock's real file UPDATE, through the existing Row
// Effect owner. No live Salesforce request/credential, hidden mirror, automatic
// approval, replacement Run or permission derived from a profile is supplied.
import {createHash} from 'node:crypto';
import {checked} from '../host-common/runtime-result.mjs';
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
  clientProgramInstalledFileEffectConstructionCapacity(provider: unknown, bytes: number, nodes: number, depth: number): unknown;
}>;
type InventoryOptions = Parameters<typeof composeInstalledEffects>[1];
type Runtime = RecipeRuntime & InventoryOptions['moon'] & Readonly<{
  [Name in keyof CodecArguments as (typeof ports)[Name]]: (...args: CodecArguments[Name]) => CodecResults[Name];
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
type CodecArguments = {
  admit: [bytes: Uint8Array, maxBytes: number, maxNodes: number, maxDepth: number, maxRows: number, maxWork: number];
  project: [original: unknown, declaration: unknown, resource: string, itemsPath: readonly string[],
    keyPath: readonly string[], primaryIdentity: string, writableFields: readonly string[]];
  observe: [document: unknown, declaration: unknown, identity: string];
  before: [row: unknown];
  version: [row: unknown];
  update: [document: unknown, row: unknown, version: string, valueWire: string, maxWork: number];
  construction: Parameters<RecipeRuntime['clientProgramInstalledSourceConstructionCapacity']>;
};
type CodecResults = Record<keyof CodecArguments, unknown> & Readonly<{before: string | undefined; version: string | undefined}>;
type CodecCall = <Name extends keyof CodecArguments>(name: Name, ...args: CodecArguments[Name]) => CodecResults[Name];
type Document = Readonly<{selected: unknown}>;
type RecordData = Readonly<{target: string; version: string; value: unknown; before: Data}>;
type EffectRecord = RecordData & Readonly<{binding: string; mapping: string}>;
type AdmissionTarget = Pick<Target, 'physical'> & Readonly<{write: Pick<Write, 'writable_fields'>}>;
type Charge = Readonly<{chargeBytes(bytes: bigint): unknown}>;
type Extent = Readonly<{nodes: bigint; text: bigint; wire: bigint}>;
type FileChild = ReturnType<File['updateChild']>;
type PhysicalOperation = Charge & Readonly<{retainPhysicalChild(child: FileChild): unknown}>;
type Member = Readonly<{resource: string; kind: string; mapping?: Pick<Mapping, 'mappingCid' | 'mappingRef'>}>;
type RunOriginal = object;
type Decision = Parameters<typeof assertAuthorizationAccountCurrent>[0];
type GrantKind = 'read' | 'write';
type Grant = Readonly<{
  kind: GrantKind; decision: Decision; runInvocationCid: string; dispatchRequestCid: string; subjectCid?: string;
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
type TargetObservation = Readonly<{identity: string; versionCid: string; before: Data}>;
type Retirable = Pick<FileChild, 'release' | 'retry' | 'status'>;
type OwnedObservationChild = Retirable & Readonly<{
  retainedOutputWire(value: unknown): string;
  prepare(): Promise<TargetObservation>;
}>;
type RequestEntries = Readonly<{entries: readonly Readonly<{request: object}>[]}>;
type CurrentTarget = Readonly<{member: Member; current: object; runOriginal: RunOriginal}>;
type ReadOptions = CurrentTarget & Readonly<{
  selector: string; value: unknown; authorizationForRow(): SuppliedUse | PromiseLike<SuppliedUse>; signal?: AbortSignal;
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
  durable: unknown; recorded: unknown; body: Readonly<{effects: readonly Readonly<{changes: readonly unknown[]}>[]}>;
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
const targetLimits = Object.freeze({maxFileBytes: 1048576, maxRows: 100,
  maxNodes: 16384, maxDepth: 32, maxWork: 16777216, maxResponseBytes: 65536,
  maxEffects: 16});
const synchronous = (value: unknown) => {
  if (value === undefined) return;
  if (value instanceof Promise) void value.catch(() => {});
  fail('InvalidMockFileCurrentFence');
};
const ports = Object.freeze({
  admit: 'clientProgramRelationAdmitDocument',
  project: 'clientProgramRelationProjectTargetDocument',
  observe: 'clientProgramRelationObserveTarget',
  before: 'clientProgramRelationTargetBefore',
  version: 'clientProgramRelationTargetVersion',
  update: 'clientProgramRelationPrepareTargetUpdate',
  construction: 'clientProgramInstalledSourceConstructionCapacity',
} as const);

// Internal DATA codec, shared by the actual locked writer and its component
// controls. It borrows the original Catalog/Common; it owns no file, Account,
// request admission, dispatch claim or current/cleanup capability.
export function createMockFileRowCodec({bundle, original, call}:
  Readonly<{bundle: Pick<Bundle, 'sources'>; original: Pick<Source, 'declaration'>; call: CodecCall}>) {
  const admit = (bytes: Uint8Array, target: AdmissionTarget) => {
    const originalDocument = checked(call('admit', bytes, targetLimits.maxFileBytes,
      targetLimits.maxNodes, targetLimits.maxDepth, targetLimits.maxRows, targetLimits.maxWork));
    const projections = new Map<Physical, unknown>();
    for (const source of bundle.sources) for (const model of source.physical) {
      const writable = source === original && model === target.physical ? target.write.writable_fields : model.writableFields;
      projections.set(model, checked(call('project', originalDocument, model.declaration,
        model.resource, model.itemsPath, model.keyPath, model.primaryIdentity, writable)));
    }
    const selected = projections.get(target.physical);
    if (selected === undefined) fail('InvalidInstalledMockEffect');
    return {originalDocument, projections, selected};
  };
  const observe = (document: Document, target: string) => {
    const row = checked(call('observe', document.selected, original.declaration, target));
    const beforeWire = call('before', row), versionCid = call('version', row);
    if (typeof beforeWire !== 'string' || !cid(versionCid)) fail('InvalidMockTargetObservation');
    const before = snapshot(JSON.parse(beforeWire) as Data);
    return {row, before, versionCid, beforeWire};
  };
  return Object.freeze({admit, observe,
    update(bytes: Uint8Array, target: AdmissionTarget, record: RecordData, physicalOperation?: Charge) {
      // Re-admit the latest WHOLE document supplied by the SAME locked file
      // owner, then replace only the original row's admitted Mapping spans.
      physicalOperation?.chargeBytes(BigInt(bytes.length));
      const document = admit(bytes, target), observed = observe(document, record.target);
      if (observed.versionCid !== record.version || wire(observed.before) !== wire(record.before)) {
        fail('MockTargetVersionConflict');
      }
      const replacement = checked(call('update', document.selected, observed.row,
        record.version, wire(record.value), targetLimits.maxWork)) as Uint8Array;
      physicalOperation?.chargeBytes(BigInt(replacement.length));
      return replacement;
    },
  });
}

// Complete logical row identities inside ONE unchanged physical boundary.
// The checked Catalog has already refused overlapping collection paths.
// Resource/Mapping aliases and values/versions are deliberately absent from
// the object identity: aliases cannot disguise the same physical row.
export function mockFileRowFootprint({bindingCid, target, selectors}: Readonly<{
  bindingCid: string; target: Readonly<{physical: Physical; write: Pick<Write, 'resource'>}>; selectors: readonly string[];
}>) {
  if (!cid(bindingCid) || !Array.isArray(selectors) || selectors.length > targetLimits.maxRows ||
      selectors.some(value => typeof value !== 'string' || !value.isWellFormed())) {
    fail('InvalidMockEffectFootprint');
  }
  const physical = target.physical;
  const scheme = {kind: 'mock-file-row-update',
    identity_fields: ['items_path', 'key_path', 'primary_identity', 'identity']};
  return Object.freeze({kind: 'exact_targets' as const, provider_namespace: 'local-mock-file',
    provider_boundary_cid: bindingCid, resource_kind: target.write.resource,
    resource_identity_scheme_cid: hash(scheme),
    provider_object_identity_cids: Object.freeze(selectors.map(identity => hash({
      items_path: physical.itemsPath, key_path: physical.keyPath,
      primary_identity: physical.primaryIdentity, identity}))),
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
  const methods = Object.fromEntries(Object.entries(ports).map(([name, port]) => [name, moon?.[port]]));
  if (!Object.values(methods).every(value => typeof value === 'function')) fail('InstalledMockTargetRuntimeUnavailable');
  const call: CodecCall = (name, ...args) => Reflect.apply(methods[name], moon, args);
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
              target.physical.declaration !== original.declaration)) fail('InvalidInstalledMockEffect');
          const spec = targets[0].write;
          const constructed = mockRowEffectDriver({bundle, original, targets,
            bindingCid: selectedBinding, principalId, authorization, current, call, resources, file});
          if (targets.every(target => target.write.permission === spec.permission &&
              target.write.observe_permission === spec.observe_permission)) {
            return {...constructed, targets,
              managedPlanRecipe: mockFileEffectPlanRecipe(moon, bundle, spec.permission, spec.observe_permission)};
          }
          const recipes: Record<string, Readonly<{targetReadOperation: string; recipe: Recipe}>> = Object.create(null);
          for (const {mapping, write} of targets) {
            const targetReadOperation = write.observe_permission;
            recipes[mapping!.mappingCid] = Object.freeze({targetReadOperation,
              recipe: mockFileEffectPlanRecipe(moon, bundle, write.permission, targetReadOperation)});
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
  operation: string, targetReadOperation: string): Recipe {
  const bytes = BigInt(targetLimits.maxFileBytes), nodes = BigInt(targetLimits.maxNodes);
  const projections = BigInt(bundle.sources.reduce((sum, source) => sum + source.physical.length, 0));
  const workspace = Object.freeze({nodes: 4n * nodes * projections,
    text: bytes * projections, wire: bytes});
  const zero = Object.freeze({nodes: 0n, text: 0n, wire: 0n});
  const capacity = (value: Extent) => checked(moon.clientProgramInstalledSourceConstructionCapacity(
    0n, 0n, 0n, value.nodes, value.text, value.wire));
  const decode = checked(moon.clientProgramInstalledFileEffectConstructionCapacity(
    capacity(zero), targetLimits.maxFileBytes, targetLimits.maxNodes, targetLimits.maxDepth));
  // The guarded request child drops the parser and document when the original
  // file read closes. Keep the complete simultaneous peak, while the row's
  // immutable request uses the separate retained request envelope.
  const requestConstruction = checked(moon.clientProgramInstalledFileEffectConstructionCapacity(
    capacity(workspace), targetLimits.maxFileBytes, targetLimits.maxNodes, targetLimits.maxDepth));
  // Projection owns checked values, admitted wrappers and row/cell indexes;
  // the file decoder is separate. Replacement Bytes coexist with original
  // file backing. Write additionally copies replacement Bytes into its Buffer.
  const construction = Object.freeze({retained: zero,
    workspace: Object.freeze({...workspace, wire: 2n * bytes})});
  const inputLimits = installedRowEffectConstructionLimits({maxRows: targetLimits.maxRows});
  let footprintCapacity;
  if (bundle.writables.length > 1) {
    const geometry = declaredProjectMockFootprintConstructionGeometry(bundle.writables,
      targetLimits.maxRows, targetLimits.maxFileBytes);
    footprintCapacity = capacity(geometry.workspace);
  }
  return prepareInstalledPhysicalWritePlanRecipe({moon, operation, inputLimits,
    construction, physicalConstruction: decode, requestConstruction, targetReadOperation,
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
  authorization, current, call, resources, file}: Readonly<{
  bundle: Bundle; original: Source; targets: readonly Target[]; bindingCid: string; principalId: string;
  authorization: Authorization; current(): void; call: CodecCall; resources: Resources; file: File;
}>) {
  const maximum = targetLimits.maxFileBytes, work = targetLimits.maxWork;
  const catalogue = original.catalogue, profile = targets[0].write;
  const changes = (value: unknown, target: Target) => value !== null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).length > 0 &&
    Object.keys(value).every(name => (target.write.update_fields ?? target.write.writable_fields).includes(name));
  const requests = new WeakMap<object, HeldRequest>(), descriptions = new WeakMap<object, Description>(),
    grants = new WeakMap<object, Grant>();
  const codec = createMockFileRowCodec({bundle, original, call});
  const {admit, observe} = codec;
  const retainedRuns = new WeakSet<RunOriginal>();
  // A plural member description adds ONE borrowed target link. The existing
  // same-Run control constructor admits its explicit logical allowance before
  // that field exists. This is not global inventory funding or authority.
  const targetDescriptionCapacity = targets.length === 1 ? undefined
    : checked(call('construction', 1n, 0n, 0n, 1n, 0n, 0n));
  function targetForResource(resource: string): Target {
    const target = targets.find(value => value.write.resource === resource);
    if (target === undefined) fail('ForeignMockEffectMember');
    return target;
  }
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
    const target = targetForResource(member.resource);
    if (member.kind !== 'update' || member.mapping?.mappingCid !== target.mapping!.mappingCid ||
        member.mapping?.mappingRef !== target.mapping!.mappingRef) fail('ForeignMockEffectMember');
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
  function decisionCurrent(decision: Decision, kind: GrantKind, target: Target) {
    current();
    const facts = authorizationDispatchFacts(decision);
    if (facts?.principal !== principalId || facts!.configurationCid !== authorization.configurationCid ||
        decision.action !== 'dispatch' || decision.tuple?.connection !== catalogue.connection ||
        decision.tuple?.resource !== target.write.resource ||
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
    const target = targetForResource(resource);
    const expected = kind === 'read' ? target.write.observe_permission : target.write.permission;
    if (operation !== expected || !cid(runInvocationCid) ||
        !cid(dispatchRequestCid) || (kind === 'read' && maxUses !== 1) ||
        (kind === 'write' && (!cid(subjectCid) || decision?.subjectCid !== subjectCid))) {
      fail('MockTargetNotAuthorized');
    }
    decisionCurrent(decision, kind, target);
    const proof = Object.freeze({});
    grants.set(proof, {kind, decision, runInvocationCid, dispatchRequestCid, subjectCid, used: false});
    return Object.freeze({proof});
  }
  function consume(kind: GrantKind, supplied: SuppliedUse, selected: object, target: Target) {
    const grant = grants.get(supplied?.proof!), original = description(selected, undefined, target);
    if (grant === undefined || grant.kind !== kind || grant.used ||
        grant.runInvocationCid !== original.runInvocationCid ||
        grant.dispatchRequestCid !== original.dispatchRequestCid ||
        grant.decision.tuple.resource !== target.write.resource ||
        typeof supplied.useId !== 'string' || Buffer.byteLength(supplied.useId) > 4096) {
      fail('ForeignMockTargetUse');
    }
    decisionCurrent(grant.decision, kind, target);
    grant.used = true;
    return Object.freeze({grant,
      useCid: hash({kind: 'mock-file-' + kind, binding_cid: bindingCid,
        invocation_cid: grant.runInvocationCid, dispatch_request_cid: grant.dispatchRequestCid,
        subject_cid: grant.subjectCid ?? null, use_id: supplied.useId,
        configuration_cid: authorizationDispatchFacts(grant.decision)!.configurationCid,
        checkpoint_cid: grant.decision.checkpointCid ?? null,
        resolution_cid: grant.decision.resolutionCid ?? null})});
  }
  const useCurrent = (use: UsedGrant | undefined) => {if (use !== undefined) decisionCurrent(use.grant.decision,
    use.grant.kind, targetForResource(use.grant.decision.tuple.resource));};
  function own(request: object, runOriginal?: RunOriginal) {
    current();
    const record = requests.get(request);
    if (record === undefined || runOriginal !== undefined &&
        record.runOriginal !== runOriginal) fail('ForeignMockEffectRequest');
    return record;
  }
  function requestFrom(record: EffectRecord, runOriginal: RunOriginal) {
    runCurrent(runOriginal);
    const target = targetForRecord(record), {write: spec, mapping, beforeFields} = target;
    if (!closed(record, ['binding', 'mapping', 'target', 'value', 'version', 'before']) ||
        record.binding !== bindingCid || record.mapping !== mapping!.mappingCid ||
        typeof record.target !== 'string' || !record.target.isWellFormed() ||
        !changes(record.value, target) || !cid(record.version) || !closed(record.before, beforeFields) ||
        record.before[spec.primary_identity] !== record.target || Buffer.byteLength(wire(record)) > maximum) {
      fail('InvalidMockEffectRequest');
    }
    const value = snapshot(record.value), before = snapshot(record.before);
    const original = Object.freeze({...record, value, before});
    // This is the canonical wire already needed for the original request CID.
    // Retain it for SAME-child output geometry instead of serializing again.
    const retainedWire = wire(original);
    const request = Object.freeze({});
    requests.set(request, Object.freeze({record: original,
      cid: 'sha256:' + createHash('sha256').update(retainedWire).digest('hex'),
      runOriginal, retainedWire}));
    return request;
  }
  function readChild({member, selector, value, current: selected, authorizationForRow, signal,
    runOriginal}: ReadOptions) {
    const target = memberCurrent(member), mapping = target.mapping;
    description(selected, runOriginal, target);
    runCurrent(runOriginal);
    let use: UsedGrant | undefined, output: RequestOutput | undefined;
    const child = file.readChild({signal, runOriginal,
      assertCurrent: () => {runCurrent(runOriginal); useCurrent(use);},
      async authorize() {use = consume('read', await authorizationForRow(), selected, target);},
      consume(bytes) {
        const document = admit(bytes, target), observed = observe(document, selector);
        // Validate the Mapping body with Common before sealing the request.
        checked(call('update', document.selected, observed.row, observed.versionCid, wire(value), work));
        const request = requestFrom({binding: bindingCid, mapping: mapping!.mappingCid,
          target: selector, value, version: observed.versionCid, before: observed.before}, runOriginal);
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
      const entries = (durable as {connectorRecovery: readonly RecoveryEntry[]}).connectorRecovery.filter(entry => entry.memberIndex === index);
      if (entries.length !== 1 || entries[0].kind !== 'mock-file-row-update' ||
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
      const requests = data.requests.map(record => requestFrom(record, runOriginal));
      // The common owner separately matches every rebuilt CID/target/value to
      // its original sealed Preview and durable row claim; this is DATA only.
      restored.push(requests);
      currents.push(undefined);
    }
    return {requests: restored, currents};
  };
  const driver = Object.freeze({
    kinds: Object.freeze(['update'] as const), targetRead: Object.freeze({operation: profile.observe_permission}),
    writeOperation: (member: Member) => memberCurrent(member).write.permission, describe,
    prepareRequest() {fail('MockOriginalTargetObservationRequired');},
    prepareRequestChild: readChild,
    requestFacts(request: object) {const {record} = own(request); return {value: record.value, target: record.target};},
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
          result.push({identity: record.target, versionCid: record.version, before: record.before});
          continue;
        }
        let use: UsedGrant | undefined, primary: unknown, observed: TargetObservation | undefined, retainedWire: string | undefined, failed = false;
        const constructChild = () => {
          const child = file.readChild({signal, runOriginal,
          assertCurrent: () => {runCurrent(runOriginal); useCurrent(use);},
          async authorize() {use = consume('read', await authorizationForRow(index), selected, target);},
          consume(bytes) {const value = observe(admit(bytes, target), record.target);
            // Reuse the already emitted native before wire. Only the two
            // original scalar fields need their ordinary JSON string quoting.
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
      if (bundle.writables.length === 1) return {providerNamespace: 'local-mock-file',
        resourceKind: target.write.resource, boundaryCid: bindingCid};
      const selectors = entries.map(entry => {
        const {record} = own(entry.request);
        if (targetForRecord(record) !== target) fail('ForeignMockEffectRequest');
        return record.target;
      });
      return mockFileRowFootprint({bindingCid, target, selectors});
    },
    recoveryEntry({entries}: RequestEntries) {
      const data = {binding: bindingCid, requests: entries.map(entry => own(entry.request).record)};
      const body = wire(data);
      if (Buffer.byteLength(body) > maximum) fail('MockEffectRecoveryLimit');
      return {kind: 'mock-file-row-update' as const, observationCid: hash(data), wire: body};
    },
    recoverRequests: recover, recoverMemberRequests: recover,
    async send({member, request, current: selected, authorization: supplied, signal, runOriginal, physicalOperation}: SendOptions) {
      const target = memberCurrent(member);description(selected, runOriginal, target);runCurrent(runOriginal);
      const {record, cid: requestCid} = own(request, runOriginal);
      if (targetForRecord(record) !== target) fail('ForeignMockEffectRequest');
      let use: UsedGrant | undefined, primary: unknown, failed = false;
      const child = file.updateChild({signal, runOriginal,
        assertCurrent: () => {runCurrent(runOriginal); useCurrent(use);},
        authorize() {use = consume('write', supplied, selected, target);},
        replace(bytes) {
          return codec.update(bytes, target, record, physicalOperation);
        }});
      try {
        physicalOperation?.retainPhysicalChild(child);
        await child.prepare();
      } catch (cause) {primary = cause; failed = true;}
      await retireChild(child, failed, primary);
      current();
      return Object.freeze({observation: Object.freeze({useCid: use!.useCid, statusCode: 200,
        body: Buffer.from(wire({request_cid: requestCid, target: record.target, action: 'updated'}))})});
    },
    project({request, observation}: Readonly<{request: object; observation?: Observation}>) {
      const {record, cid: requestCid} = own(request);
      if (!cid(observation?.useCid) || observation.statusCode !== 200 ||
          !(observation.body instanceof Uint8Array) ||
          observation.body.length > targetLimits.maxResponseBytes) {
        return {kind: 'unknown'};
      }
      let response: unknown;
      try {response = JSON.parse(Buffer.from(observation.body).toString('utf8'));}
      catch {return {kind: 'unknown'};}
      if (!closed(response, ['request_cid', 'target', 'action']) ||
          response.request_cid !== requestCid || response.target !== record.target || response.action !== 'updated') {
        return {kind: 'unknown'};
      }
      return {kind: 'typed-success-response', outcome: {state: 'applied', action: 'updated', result: {id: record.target}}};
    },
  });
  const site = Object.freeze({issueReadGrant: (options: GrantOptions) => issue('read', options),
    issueEffectGrant: (options: GrantOptions) => issue('write', options), status: file.status, close: file.close});
  return {driver, site, resourceObservation};
}
